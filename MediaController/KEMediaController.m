//
//  KEMediaController.m
//  MediaController
//
//  Created by Denis Dovgan on 4/27/16.
//  Copyright (c) 2015. All rights reserved.
//

#import "KEMediaController.h"

@import AVFoundation;
@import MediaPlayer.MPNowPlayingInfoCenter;
@import MediaPlayer.MPMediaItem;
@import UIKit.UIApplication;

typedef void (^TimeBlock)(NSTimeInterval duration, NSTimeInterval currentTime);

NSString *const KEMediaControllerDidFinishPlayingMediaNotification = @"KEMediaControllerDidFinishPlayingMediaNotification";

static NSString * const kPlayable = @"playable";
static NSString * const kDuration = @"duration";

static NSString * const kRateKeyPath = @"rate";
static NSString * const kStatusKeyPath = @"status";
static NSString * const kPlaybackEmptyBufferKeyPath = @"playbackBufferEmpty";
static NSString * const kPlaybackLikelyToKeepUpKeyPath = @"playbackLikelyToKeepUp";
static NSString * const kReadyForDisplayKeyPath = @"readyForDisplay";

static NSString * const kPlayerItemContext = @"kPlayerItemContext";
static NSString * const kPlayerContext = @"kPlayerContext";


#pragma mark - KEMediaController
@interface KEMediaController ()
{
	id _periodicTimeObserver;
	NSTimeInterval _currentPlayerItemDuration;
	NSTimeInterval _currentPlayerItemProgress;
}

@property (nonatomic) AVPlayer *player;
@property (nonatomic) AVPlayerItem *playerItem;
@property (nonatomic) AVAsset *asset;

@property (nonatomic, readwrite) KEMediaControllerPlaybackState playbackState;
@property (nonatomic, readwrite) KEMediaControllerBufferingState bufferingState;

@end


@implementation KEMediaController

#pragma mark - Init

- (instancetype)init {
	
	self = [super init];
	if (self) {
		[self setupPlayer];
	}
	
	return self;
}

- (void)setupPlayer {
	
	NSAssert(self.player == nil, @"");
	
	self.player = [AVPlayer new];
	self.player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
	
	[self subscribeForNotifications];
}

- (void)dealloc {

	[self removeTimeObserver];
	[self.player removeObserver:self forKeyPath:kRateKeyPath];
	
	[self unsubscribeFromNotifications];
	self.asset = nil;
	[[UIApplication sharedApplication] endReceivingRemoteControlEvents];
}

#pragma mark - Setters

- (void)setAsset:(AVAsset *)asset {
	
	if (asset == _asset) {
		return;
	}
	
	_asset = asset;
	
	if (self.asset == nil) {
		self.playerItem = nil;
	} else {
		__weak KEMediaController* wself = self;
		[self.asset loadValuesAsynchronouslyForKeys:@[kPlayable, kDuration] completionHandler:^{

			__strong KEMediaController *sself = wself;
			if (sself != nil) {
				
				if (sself.asset != asset) {
					return;
				}
			
				NSError *error = nil;
				AVKeyValueStatus playableStatus = [asset statusOfValueForKey:kPlayable error:&error];
				if (playableStatus == AVKeyValueStatusFailed) {
					dispatch_async(dispatch_get_main_queue(), ^{
						sself->_error = error;
						[sself.delegate mediaController:sself didHandleInitializationError:error];
						
						[self setPlaybackState:KEMediaControllerPlaybackStateFailed notifyDelegate:YES];
					});
					return;
				}
				
				AVKeyValueStatus durationStatus = [asset statusOfValueForKey:kDuration error:&error];
				switch (durationStatus) {
					case AVKeyValueStatusLoaded: {
						dispatch_async(dispatch_get_main_queue(), ^{
							sself->_currentPlayerItemDuration = CMTimeGetSeconds(wself.asset.duration);
							[sself.delegate mediaController:sself didFetchItemDuration:sself->_currentPlayerItemDuration];
						});
					}
						break;
						
					case AVKeyValueStatusFailed: {
						dispatch_async(dispatch_get_main_queue(), ^{
							sself->_error = error;
							[sself.delegate mediaController:sself didHandleInitializationError:error];
							[self setPlaybackState:KEMediaControllerPlaybackStateFailed notifyDelegate:YES];
						});
						return;
					}
						break;
						
					default:
						break;
				}
			}
			
			dispatch_async(dispatch_get_main_queue(), ^{
				wself.playerItem = [AVPlayerItem playerItemWithAsset:wself.asset];
				[wself reloadLockScreenInfo];
			});
		}];
	}
}

- (void)setPlayerItem:(AVPlayerItem *)playerItem {
	
	if (self.playerItem != playerItem) {
	
		if (self.playerItem) {
			[self.playerItem removeObserver:self forKeyPath:kPlaybackEmptyBufferKeyPath context:(__bridge void *)(kPlayerItemContext)];
			[self.playerItem removeObserver:self forKeyPath:kPlaybackLikelyToKeepUpKeyPath context:(__bridge void *)(kPlayerItemContext)];
			[self.playerItem removeObserver:self forKeyPath:kStatusKeyPath context:(__bridge void *)(kPlayerItemContext)];
			
			// Notifications
			[[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification
				object:self.playerItem];
			[[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification
				object:self.playerItem];
		}
		
		_playerItem = playerItem;
		
		if (self.playerItem) {
		
			// AVPlayerItem KVO
			[self.playerItem addObserver:self forKeyPath:kPlaybackEmptyBufferKeyPath options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld)
				context:(__bridge void *)(kPlayerItemContext)];
			[self.playerItem addObserver:self forKeyPath:kPlaybackLikelyToKeepUpKeyPath options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld)
				context:(__bridge void *)(kPlayerItemContext)];
			[self.playerItem addObserver:self forKeyPath:kStatusKeyPath options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld)
				context:(__bridge void *)(kPlayerItemContext)];
			
			// Notifications
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerItemDidPlayToEndTimeNotification:)
				name:AVPlayerItemDidPlayToEndTimeNotification object:self.playerItem];
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerItemFailedToPlayToEndTimeNotification:)
				name:AVPlayerItemFailedToPlayToEndTimeNotification object:self.playerItem];
		}
		
		[self.player replaceCurrentItemWithPlayerItem:self.playerItem];
	}
}

- (void)setBufferingState:(KEMediaControllerBufferingState)bufferingState {
	
	if (_bufferingState != bufferingState) {
		_bufferingState = bufferingState;
		[self.delegate mediaPlayeDidChangeBufferingState:self];
		[self reloadLockScreenInfo];
	}
}

- (void)setPlaybackState:(KEMediaControllerPlaybackState)playbackState {
	
	[self setPlaybackState:playbackState notifyDelegate:YES];
}

- (void)setPlaybackState:(KEMediaControllerPlaybackState)playbackState notifyDelegate:(BOOL)notifyDelegate {

	if (_playbackState != playbackState) {
		_playbackState = playbackState;
	
		if (notifyDelegate) {
			[self.delegate mediaControllerDidChangePlaybackState:self];
		}
		[self reloadLockScreenInfo];
	}
}

#pragma mark - Common Code

- (void)updateWithMediaUrl:(NSURL *)mediaUrl {
	
	NSParameterAssert(mediaUrl != nil);

	[self stop];

	self.asset = nil;
	
	_mediaUrl = mediaUrl;
	
	_currentPlayerItemDuration = -1;
	_currentPlayerItemProgress = -1;
	
	self.asset = [AVURLAsset assetWithURL:mediaUrl];
}

- (void)currentTime:(TimeBlock)block {

	if (block != nil) {
		block(_currentPlayerItemDuration, _currentPlayerItemProgress);
	}
}

- (NSTimeInterval)availableDuration {

	NSTimeInterval result = -1;
	NSArray *loadedTimeRanges = [self.player.currentItem loadedTimeRanges];
	
	if (loadedTimeRanges != nil) {
		CMTimeRange timeRange = [loadedTimeRanges.firstObject CMTimeRangeValue];
		
		Float64 startSeconds = CMTimeGetSeconds(timeRange.start);
		Float64 durationSeconds = CMTimeGetSeconds(timeRange.duration);
		result = startSeconds + durationSeconds;
	}
	
	return result;
}

- (BOOL)isPlaying {
	
	BOOL isPlaying = self.playbackState == KEMediaControllerPlaybackStatePlaying && self.bufferingState == KEMediaControllerBufferingStateReady;
	return isPlaying;
}

- (void)reloadLockScreenInfo {
	
	NSString *mediaTitle = [self.dataSource mediaTitleForMediaController:self];
	if (mediaTitle == nil) {
		[[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:nil];
	} else {
	
		__weak KEMediaController *wself = self;
		[self currentTime:^(NSTimeInterval duration, NSTimeInterval currentTime) {
			NSMutableDictionary *info = [[NSMutableDictionary alloc] init];
			
			info[MPMediaItemPropertyTitle] = mediaTitle;
			info[MPNowPlayingInfoPropertyPlaybackRate] = wself.isPlaying ? @1.0f : @0.0f;
			info[MPMediaItemPropertyPlaybackDuration] = @(duration);
			info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(currentTime);
			
			[[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:info];
		}];
	}
}

#pragma mark - Player controls

- (void)playFromBeginning {

	[self seekToTime:0];
    [self playFromCurrentTime];
	
	[self.delegate mediaControllerDidBeginPlayingFromBeginning:self];
}

- (void)playFromCurrentTime {
	
	self.playbackState = KEMediaControllerPlaybackStatePlaying;
	[self.player play];
	
	[self addTimeObserverIfNeeded];
}

- (void)playFromCurrentTimeWithRewindOffset:(NSTimeInterval)offset {
	
	__weak KEMediaController *wself = self;
	[self currentTime:^(NSTimeInterval duration, NSTimeInterval currentTime) {
		if (duration > 0.f && currentTime > 0) {
			CGFloat seconds = MAX(currentTime - offset, 0);
			
			[wself seekToTime:seconds];
			[wself playFromCurrentTime];
		}
	}];
}

- (void)stop {

    if (self.playbackState != KEMediaControllerPlaybackStateStopped) {
		[self removeTimeObserver];
		self.playbackState = KEMediaControllerPlaybackStateStopped;
		[self seekToTime:0.f];
		[self.player pause];
	}
}

- (void)pause {

	if (self.playbackState == KEMediaControllerPlaybackStatePlaying) {
		
		[self.player pause];
		self.playbackState = KEMediaControllerPlaybackStatePaused;
	}
}

- (void)seekToTime:(NSTimeInterval)time {
	
	CMTime newTimeValue = CMTimeMakeWithSeconds(time, 1.f);
	[self.player seekToTime:newTimeValue toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
	
	[self reloadLockScreenInfo];
}

#pragma mark - Progress

- (void)addTimeObserverIfNeeded {

	if (_periodicTimeObserver == nil) {
		// 1/4 sec
		__weak KEMediaController *wself = self;
		_periodicTimeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1.f, 4.f) queue:dispatch_get_main_queue()
			usingBlock:^(CMTime time) {
			
			__strong KEMediaController *sself = wself;
			if (sself != nil) {
				if (CMTIME_IS_NUMERIC(time)) {
					sself->_currentPlayerItemProgress = CMTimeGetSeconds(time);
					[sself.delegate mediaControllerDidUpdateProgress:sself->_currentPlayerItemProgress duration:sself->_currentPlayerItemDuration];
				}
			}
		}];
	}
}

- (void)removeTimeObserver {

	if (_periodicTimeObserver != nil) {
		[self.player removeTimeObserver:_periodicTimeObserver];
		_periodicTimeObserver = nil;
	}
}

#pragma mark - Notifications

- (void)subscribeForNotifications {

	NSNotificationCenter *nCenter = [NSNotificationCenter defaultCenter];

	[nCenter addObserver:self selector:@selector(didHandleAudioSessionInterruptionNotification:) name:AVAudioSessionInterruptionNotification object:nil];
}

- (void)unsubscribeFromNotifications {

	NSNotificationCenter *nCenter = [NSNotificationCenter defaultCenter];
	[nCenter removeObserver:self];
}

- (void)playerItemDidPlayToEndTimeNotification:(NSNotification *)aNotification {

	__weak KEMediaController *wself = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		[wself stop];
		[wself.delegate mediaControllerDidFinishPlaying:wself];
	});
	
	[[NSNotificationCenter defaultCenter] postNotificationName:KEMediaControllerDidFinishPlayingMediaNotification object:nil];
}

- (void)playerItemFailedToPlayToEndTimeNotification:(NSNotification *)aNotification {

	__weak KEMediaController *wself = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		_error = [[aNotification userInfo] objectForKey:AVPlayerItemFailedToPlayToEndTimeErrorKey];
		wself.playbackState = KEMediaControllerPlaybackStateFailed;
	});

    NSLog(@"error (%@)", [[aNotification userInfo] objectForKey:AVPlayerItemFailedToPlayToEndTimeErrorKey]);
}

- (void)didHandleAudioSessionInterruptionNotification:(NSNotification *)notification {
	
	AVAudioSessionInterruptionType interruptionType = [notification.userInfo[AVAudioSessionInterruptionTypeKey] integerValue];
	if (interruptionType == AVAudioSessionInterruptionTypeBegan) {
		[self pause];
	}
}

- (void)remoteControlReceivedWithEvent:(UIEvent *)theEvent
{
    if (theEvent.type == UIEventTypeRemoteControl)
        switch (theEvent.subtype)
    {
        case UIEventSubtypeRemoteControlTogglePlayPause:
		
			if (self.playbackState == KEMediaControllerPlaybackStatePlaying) {
				[self pause];
			} else {
				[self playFromCurrentTime];
			}
            break;
            
        case UIEventSubtypeRemoteControlPause:
            [self pause];
            break;
            
        case UIEventSubtypeRemoteControlPlay:
            [self playFromCurrentTime];
            break;
            
        case UIEventSubtypeRemoteControlPreviousTrack:
            break;
            
        case UIEventSubtypeRemoteControlNextTrack:
            break;
            
        default:
            break;
    }
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {

	if (context == (__bridge void *)(kPlayerContext)) {
        // Player
    }
	else if (context == (__bridge void *)(kPlayerItemContext)) {
        
        // PlayerItem
        if ([keyPath isEqualToString:kPlaybackEmptyBufferKeyPath]) {
		
            if (self.playerItem.playbackBufferEmpty) {
                self.bufferingState = KEMediaControllerBufferingStateBuffering;
            }
        }
		else if ([keyPath isEqualToString:kPlaybackLikelyToKeepUpKeyPath]) {

            if (self.playerItem.playbackLikelyToKeepUp) {
                self.bufferingState = KEMediaControllerBufferingStateReady;
				
                if (self.playbackState == KEMediaControllerPlaybackStatePlaying) {
                    [self playFromCurrentTime];
                }
            }
        } else if ([keyPath isEqualToString:kStatusKeyPath]) {
			AVPlayerStatus newStatus = [change[NSKeyValueChangeNewKey] integerValue];
			AVPlayerStatus oldStatus = [change[NSKeyValueChangeOldKey] integerValue];
			
			if (newStatus != oldStatus) {
				
				switch (newStatus) {
					case AVPlayerStatusReadyToPlay: {
					}
					break;
					
					case AVPlayerStatusFailed: {
						self.playbackState = KEMediaControllerPlaybackStateFailed;
						break;
					}
					case AVPlayerStatusUnknown:
					default:
						break;
				}
			}
		}
    } else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

@end
