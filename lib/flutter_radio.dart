import 'dart:async';
import 'dart:core';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FlutterRadio {
  static const MethodChannel _channel = const MethodChannel('flutter_radio');
  static StreamController<PlayStatus> _playerController;
  static StreamController<bool> _playerState = StreamController.broadcast();
  static StreamController<PlaybackStatus> _playerMessage = StreamController.broadcast();

  /// Value ranges from 0 to 120
  static Stream<PlayStatus> get onPlayerStateChanged =>
      _playerController.stream;

  static Stream<bool> get onIsPlayingChanged => _playerState.stream;

  static Stream<PlaybackStatus> get onMessageReceived => _playerMessage.stream;

  static bool _isPlaying = false;

  static Future<void> audioStart([AudioPlayerItem item]) async {
    if (item != null) {
      await setMeta(item);
    }
    await _channel.invokeMethod('audioStart');
  }

  static Future<void> playOrPause({@required String url}) async {
    try {
      if (FlutterRadio._isPlaying) {
        FlutterRadio.pause(url: url);
      } else {
        FlutterRadio.play(url: url);
      }
    } catch (err) {
      throw Exception(err);
    }
  }

  static Future<void> play({@required String url}) async {
    try {
      String result = await _channel.invokeMethod('play', <String, dynamic>{
        'url': url,
      });
      print('result: $result');

      _setPlayerCallback();

      FlutterRadio._isPlaying = true;

      return result;
    } catch (err) {
      throw Exception(err);
    }
  }

  static Future<void> pause({@required String url}) async {
    FlutterRadio._isPlaying = false;

    final Map<String, dynamic> params = <String, dynamic>{'url': url};
    String result = await _channel.invokeMethod('pause', params);
    _removePlayerCallback();
    return result;
  }

  static Future<void> stop() async {
    FlutterRadio._isPlaying = false;

    String result = await _channel.invokeMethod('stop');
    _removePlayerCallback();
    return result;
  }

  static Future<bool> isPlaying() async {
    return Future.value(_isPlaying);
  }

  static Future<void> _setPlayerCallback() async {
    if (_playerController == null) {
      _playerController = new StreamController.broadcast();
    }

    _channel.setMethodCallHandler((MethodCall call) {
      switch (call.method) {
        case "updateProgress":
          Map<String, dynamic> result = jsonDecode(call.arguments);
          _playerController.add(new PlayStatus.fromJSON(result));
          break;
        case "stateChanged":
          Map<String, dynamic> result = jsonDecode(call.arguments);
          _playerState.add(new PlayState.fromJSON(result).isPlaying);
          break;
        case "onMessage":
          _playerMessage.add(stringToEnum(call.arguments));
          break;
        default:
          throw new ArgumentError('Unknown method ${call.method}');
      }
    });
  }

  static Future<void> _removePlayerCallback() async {
    if (_playerController != null) {
      _playerController
        ..add(null)
        ..close();
      _playerController = null;
    }
  }

  static Future<String> setMeta(AudioPlayerItem item) async {
    String result = await _channel.invokeMethod('setMeta', <String, dynamic>{
      'meta': item.toMap(),
    });
    _removePlayerCallback();
    return result;
  }

  static Future<String> setVolume(double volume) async {
    String result = '';
    if (volume < 0.0 || volume > 1.0) {
      result = 'Value of volume should be between 0.0 and 1.0.';
      return result;
    }

    result = await _channel.invokeMethod('setVolume', <String, dynamic>{
      'volume': volume,
    });
    return result;
  }
}

class PlayStatus {
  final double duration;
  double currentPosition;

  PlayStatus.fromJSON(Map<String, dynamic> json)
      : duration = double.parse(json['duration']),
        currentPosition = double.parse(json['current_position']);

  @override
  String toString() {
    return 'duration: $duration, '
        'currentPosition: $currentPosition';
  }
}

class PlayState {
  final bool isPlaying;

  PlayState.fromJSON(Map<String, dynamic> json)
      : isPlaying = json['isPlaying'].toLowerCase() == 'true';

  @override
  String toString() {
    return 'isPlaying: $isPlaying';
  }
}

class AudioPlayerItem {
  String id;
  String url;
  String thumbUrl;
  String title;
  Duration duration;
  double progress;
  String album;
  bool local;

  AudioPlayerItem(
      {this.id,
      this.url,
      this.thumbUrl,
      this.title,
      this.duration,
      this.progress,
      this.album,
      this.local});

  Map<String, dynamic> toMap() {
    return {
      'id': this.id,
      'url': this.url,
      'thumb': this.thumbUrl,
      'title': this.title,
      'duration': this.duration != null ? this.duration.inSeconds : 0,
      'progress': this.progress ?? 0,
      'album': this.album,
      'local': this.local
    };
  }
}

PlaybackStatus stringToEnum(String str) {
  switch (str) {
    case "PlaybackStatus_IDLE":
      return PlaybackStatus.IDLE;
    case "PlaybackStatus_LOADING":
      return PlaybackStatus.LOADING;
    case "PlaybackStatus_PLAYING":
      return PlaybackStatus.PLAYING;
    case "PlaybackStatus_PAUSED":
      return PlaybackStatus.PAUSED;
    case "PlaybackStatus_STOPPED":
      return PlaybackStatus.STOPPED;
    case "PlaybackStatus_ERROR":
      return PlaybackStatus.ERROR;
    default:
      throw new ArgumentError('FlutterRadio: Unknown state $str');
  }
}

enum PlaybackStatus {
  IDLE,
  LOADING,
  PLAYING,
  PAUSED,
  STOPPED,
  ERROR,
}
