#import "FlutterRadioPlugin.h"
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>

@implementation FlutterRadioPlugin{
    NSURL *audioFileURL;
    AVPlayer *audioPlayer;
    AVPlayerItem *playerItem;
    NSMutableDictionary* songInfo;
    NSTimer *timer;
    NSTimer *dbPeakTimer;
    bool _ready;
    bool _isPlaying;
    NSMutableSet* _listeners;
    int _count;
}
double subscriptionDuration = 1;
FlutterMethodChannel* _channel;

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterMethodChannel* channel = [FlutterMethodChannel
                                     methodChannelWithName:@"flutter_radio"
                                     binaryMessenger:[registrar messenger]];
    FlutterRadioPlugin* instance = [[FlutterRadioPlugin alloc] init];
    [registrar addMethodCallDelegate:instance channel:channel];
    _channel = channel;
}

- (instancetype)init {
    if (self = [super init]) {
        //setup control center and lock screen controls
        MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
        [commandCenter.togglePlayPauseCommand setEnabled:YES];
        [commandCenter.playCommand setEnabled:YES];
        [commandCenter.pauseCommand setEnabled:YES];
        [commandCenter.stopCommand setEnabled:YES];
        [commandCenter.nextTrackCommand setEnabled:NO];
        [commandCenter.previousTrackCommand setEnabled:NO];
        [commandCenter.changePlaybackRateCommand setEnabled:NO];
        
        [commandCenter.togglePlayPauseCommand addTarget:self action:@selector(playerPlayPause)];
        [commandCenter.playCommand addTarget:self action:@selector(playerPlayPause)];
        [commandCenter.pauseCommand addTarget:self action:@selector(playerPlayPause)];
        [commandCenter.stopCommand addTarget:self action:@selector(playerStop)];
        
        //Unused options
        [commandCenter.skipForwardCommand setEnabled:NO];
        [commandCenter.skipBackwardCommand setEnabled:NO];
        if (@available(iOS 9.0, *)) {
            [commandCenter.enableLanguageOptionCommand setEnabled:NO];
            [commandCenter.disableLanguageOptionCommand setEnabled:NO];
        }
        [commandCenter.changeRepeatModeCommand setEnabled:NO];
        [commandCenter.seekForwardCommand setEnabled:NO];
        [commandCenter.seekBackwardCommand setEnabled:NO];
        [commandCenter.changeShuffleModeCommand setEnabled:NO];
        
        // Rating Command
        [commandCenter.ratingCommand setEnabled:NO];
        
        // Feedback Commands
        // These are generalized to three distinct actions. Your application can provide
        // additional context about these actions with the localizedTitle property in
        // MPFeedbackCommand.
        [commandCenter.likeCommand setEnabled:NO];
        [commandCenter.dislikeCommand setEnabled:NO];
        [commandCenter.bookmarkCommand setEnabled:NO];
        
        _isPlaying = NO;
        _ready = NO;
        
        // Able to play in silent mode
        [[AVAudioSession sharedInstance]
         setCategory: AVAudioSessionCategoryPlayback
         error: nil];
        // Able to play in background
        [[AVAudioSession sharedInstance] setActive: YES error: nil];
        [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];

        if (!songInfo) {
            songInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                         @"", MPMediaItemPropertyTitle,
                         nil, MPMediaItemPropertyArtwork,
                         @"", MPMediaItemPropertyAlbumTitle,
                         0, MPMediaItemPropertyPlaybackDuration,
                         [NSNumber numberWithDouble:1.0], MPNowPlayingInfoPropertyPlaybackRate, nil];
        }
    }
    
    return self;
}

- (void)deinit {
    NSLog(@"deinit");
}

- (void) addListener:(id <AudioPlayerListener>) listener {
    NSLog(@"Adding listener: %@", listener);
    [_listeners addObject:listener];
    NSLog(@"added listeners: %@", _listeners);
}

- (void) stopTimer{
    // NSLog(@"stopTimer");
    if (timer != nil) {
        [timer invalidate];
        timer = nil;
    }
}

- (void) updateProgress:(NSTimer*) timer {
    NSNumber *duration = [NSNumber numberWithDouble:CMTimeGetSeconds(playerItem.duration) * 1000];
    NSNumber *currentTime = [NSNumber numberWithDouble:CMTimeGetSeconds(playerItem.currentTime) * 1000];
    
    if ([duration intValue] == 0 && timer != nil) {
        [self stopTimer];
        return;
    }
    
    NSString* status = [NSString stringWithFormat:@"{\"duration\": \"%@\", \"current_position\": \"%@\"}", [duration stringValue], [currentTime stringValue]];
    
    [_channel invokeMethod:@"updateProgress" arguments:status];
}

- (void) startTimer {
    NSLog(@"stoarTimer");
    dispatch_async(dispatch_get_main_queue(), ^{
        self->timer = [NSTimer scheduledTimerWithTimeInterval:subscriptionDuration
                                                       target:self
                                                     selector:@selector(updateProgress:)
                                                     userInfo:nil
                                                      repeats:YES];
    });
}

// Flutter stuff:

- (void) handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([@"play" isEqualToString:call.method]) {
        NSString* path = (NSString*)call.arguments[@"url"];
        [self startPlayer:path result:result];
    } else if ([@"stop" isEqualToString:call.method]) {
        [self stopPlayer:result];
    } else if ([@"pause" isEqualToString:call.method]) {
        [self pausePlayer:result];
    } else if ([@"playOrPause" isEqualToString:call.method]) {
        [self playOrPause:result];
    } else if ([@"setVolume" isEqualToString:call.method]) {
        NSNumber* volume = (NSNumber*)call.arguments[@"volume"];
        [self setVolume:[volume doubleValue] result:result];
    } else if ([@"setMeta" isEqualToString:call.method]) {
        NSDictionary* meta = (NSDictionary*)call.arguments[@"meta"];
        [self setMeta:meta result:result];
    } else if ([@"audioStart" isEqualToString:call.method]) {
        NSDictionary* meta = (NSDictionary*)call.arguments[@"meta"];
        [self setMeta:meta result:result];
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (void) playOrPause:(FlutterResult)result {
    if (audioPlayer) {
        [self playerPlayPause];
    } else {
        result([FlutterError
                errorWithCode:@"Audio Player"
                message:@"player is not set"
                details:nil]);
    }
}

- (void) pausePlayer:(FlutterResult)result {
    if (audioPlayer) {
        [self stopTimer];
        [self playerPause];
    
        result(@"pause play");
    } else {
        result([FlutterError
                errorWithCode:@"Audio Player"
                message:@"player is not set"
                details:nil]);
    }
}

- (void) stopPlayer:(FlutterResult)result {
    if (audioPlayer) {
        [self stopTimer];
        [self playerStop];
        result(@"stop play");
    } else {
        result([FlutterError
                errorWithCode:@"Audio Player"
                message:@"player is not set"
                details:nil]);
    }
}

- (void) startPlayer:(NSString*)path result: (FlutterResult)result {
    NSLog(@"startPlayer");
    audioFileURL = [NSURL URLWithString:path];
    
    [self playerStart];
    
    NSString *filePath = audioFileURL.absoluteString;
    result(filePath);
}

// todo: remove?
- (void) setVolume:(double) volume result: (FlutterResult)result {
    if (audioPlayer) {
        [audioPlayer setVolume: volume];
        result(@"volume set");
    } else {
        result([FlutterError
                errorWithCode:@"Audio Player"
                message:@"player is not set"
                details:nil]);
    }
}

// todo: remove?
- (void) setMeta:(NSDictionary*) meta result: (FlutterResult)result {
    NSLog(@"setMeta");
    
    NSString* itemTitle = [meta objectForKey:@"title"];
    NSString* itemAlbum = [meta objectForKey:@"album"];
    NSNumber* duration = [meta objectForKey:@"duration"];
    NSNumber* progress = [meta objectForKey:@"progress"];

    MPMediaItemArtwork* ControlArtwork;
    if (@available(iOS 10.0, *)) {
        ControlArtwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:CGSizeMake(600, 600) requestHandler:^UIImage * _Nonnull(CGSize size) {
            return [UIImage imageWithData: [[NSData alloc] initWithContentsOfURL: [NSURL URLWithString: [meta objectForKey:@"thumb"]]]];
        }];
    } else {
        UIImage* image = [UIImage imageWithData: [[NSData alloc] initWithContentsOfURL: [NSURL URLWithString: [meta objectForKey:@"thumb"]]]];
        ControlArtwork = [[MPMediaItemArtwork alloc] initWithImage: image];
    }
    
    songInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                         itemTitle, MPMediaItemPropertyTitle,
                         ControlArtwork, MPMediaItemPropertyArtwork,
                         itemAlbum, MPMediaItemPropertyAlbumTitle,
                         duration, MPMediaItemPropertyPlaybackDuration,
                         progress, MPNowPlayingInfoPropertyElapsedPlaybackTime,
                         [NSNumber numberWithDouble:1.0], MPNowPlayingInfoPropertyPlaybackRate, nil];
    [self setNowPlaying];
    
    result(@"meta set");
}


// Native stuff

- (void) playerPlayPause{
    NSLog(@"playerPlayPause");
    if (_isPlaying) {
        NSLog(@"playerPlayPause pause");
        [self playerPause];
    }else{
        NSLog(@"playerPlayPause play");
        [self playerStart];
    }
}

- (void) playerStart {
    NSLog(@"playerStart");
    _ready = NO;
    
    AVURLAsset* avAsset = [AVURLAsset URLAssetWithURL:audioFileURL options:nil];
    playerItem = [AVPlayerItem playerItemWithAsset:avAsset];
    audioPlayer = [AVPlayer playerWithPlayerItem:playerItem];
    
    //get audio state and call listeners
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackStalled:) name:AVPlayerItemPlaybackStalledNotification object:audioPlayer.currentItem];
    [audioPlayer.currentItem addObserver:self forKeyPath:@"status" options:0 context:nil];
    [audioPlayer addObserver:self forKeyPath:@"rate" options:0 context:nil];
    
    [self setNowPlaying];

    [_channel invokeMethod:@"onMessage" arguments:@"PlaybackStatus_CONNECTING"];
}

- (void)playbackStalled:(NSNotification *)notification {
    NSLog(@"player stalled");
    [_channel invokeMethod:@"onMessage" arguments:@"PlaybackStatus_ERROR"];
}

- (void) playerPause {
    NSLog(@"playerPause");
    
    if (audioPlayer.currentItem != nil){
        [audioPlayer pause];
        [audioPlayer.currentItem removeObserver:self forKeyPath:@"status"];
        [audioPlayer removeObserver:self forKeyPath:@"rate"];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemPlaybackStalledNotification object:nil];
    }
    
    for (id<AudioPlayerListener> listener in [_listeners allObjects]) {
        [listener onPlayerPaused];
    }

    [_channel invokeMethod:@"onMessage" arguments:@"PlaybackStatus_PAUSED"];
}

- (void) playerStop {
    NSLog(@"playerStop");
    
    if (audioPlayer.currentItem != nil){
        [audioPlayer pause];
        [audioPlayer.currentItem removeObserver:self forKeyPath:@"status"];
        [audioPlayer removeObserver:self forKeyPath:@"rate"];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemPlaybackStalledNotification object:nil];
        audioPlayer = nil;
    }
    
    for (id<AudioPlayerListener> listener in [_listeners allObjects]) {
        [listener onPlayerStopped];
    }
    [_channel invokeMethod:@"onMessage" arguments:@"PlaybackStatus_STOPPED"];
    
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
}

- (void) setNowPlaying {
    NSLog(@"setNowPlaying");
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = songInfo;
    [self startTimer];
}

//region: Observables

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*) context {
    NSLog(@"observeValueForKeyPath: %@", keyPath);
    if ([keyPath isEqualToString:@"status"]) {
        if (audioPlayer.status == AVPlayerStatusReadyToPlay) {
            // Note: we look for the AVPlayerItem's status ready rather than the AVPlayer because this
            // way we know that the duration will be available.
            NSLog(@"observableStatus: AVPlayerStatusReadyToPlay");
            [self _onAudioReady];
        } else if (audioPlayer.status == AVPlayerStatusFailed) {
            NSLog(@"observableStatus: AVPlayerStatusFailed");
            [self _onFailedToPrepareAudio];
        } else {
            NSLog(@"observableStatus: AVPlayerStatusUnknown");
        }
    } else if ([keyPath isEqualToString:@"rate"]) {
        [self _onPlaybackRateChange];
    }
}

- (void) _onAudioReady {
    NSLog(@"_onAudioReady ready: %d", _ready);
    // NSLog(@"_onAudioReady listeners: %@", _listeners);
    if (!_ready) {
        _ready = YES;
        
        for (id<AudioPlayerListener> listener in [_listeners allObjects]) {
            [listener onAudioReady];
        }
        
        [audioPlayer play];
        [_channel invokeMethod:@"onMessage" arguments:@"PlaybackStatus_PLAYING"];
        [self startTimer];
    }
}

- (void) _onFailedToPrepareAudio {
    NSLog(@"AVPlayer failed to load audio");
    
    for (id<AudioPlayerListener> listener in [_listeners allObjects]) {
        [listener onFailedPrepare];
    }

    [_channel invokeMethod:@"onMessage" arguments:@"PlaybackStatus_ERROR"];
    }

- (void) _onPlaybackRateChange {
    NSLog(@"Rate just changed to %f", audioPlayer.rate);
    if (audioPlayer.rate > 0 && !_isPlaying) {
        // Just started playing.
        NSLog(@"AVPlayer started playing.");
        for (id<AudioPlayerListener> listener in [_listeners allObjects]) {
            [listener onPlayerPlaying];
        }
        [_channel invokeMethod:@"onMessage" arguments:@"PlaybackStatus_PLAYING"];
        _isPlaying = YES;
    } else if (audioPlayer.rate == 0 && _isPlaying) {
        // Just paused playing.
        NSLog(@"AVPlayer paused playback.");
        for (id<AudioPlayerListener> listener in [_listeners allObjects]) {
            [listener onPlayerPaused];
        }
        [_channel invokeMethod:@"onMessage" arguments:@"PlaybackStatus_PAUSED"];
        _isPlaying = NO;
    }
}

@end
