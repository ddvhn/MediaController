//
//  KEMediaController.h
//  MediaController
//
//  Created by Denis Dovgan on 4/27/16.
//  Copyright (c) 2015. All rights reserved.
//

@import Foundation;

typedef NS_ENUM(NSInteger, KEMediaControllerPlaybackState) {
    KEMediaControllerPlaybackStateStopped = 0,
    KEMediaControllerPlaybackStatePlaying,
    KEMediaControllerPlaybackStatePaused,
    KEMediaControllerPlaybackStateFailed
};

typedef NS_ENUM(NSInteger, KEMediaControllerBufferingState) {
    KEMediaControllerBufferingStateUnknown = 0,
    KEMediaControllerBufferingStateReady,
    KEMediaControllerBufferingStateBuffering
};

extern NSString *const KEMediaControllerDidFinishPlayingMediaNotification;

@class KEMediaController;
@protocol KEMediaControllerDelegate <NSObject>

@required
- (void)mediaController:(KEMediaController *)mediaController didHandleInitializationError:(NSError *)error;
- (void)mediaController:(KEMediaController *)mediaController didFetchItemDuration:(NSTimeInterval)duration;

- (void)mediaControllerDidChangePlaybackState:(KEMediaController *)mediaController;
- (void)mediaPlayeDidChangeBufferingState:(KEMediaController *)mediaController;

- (void)mediaControllerDidBeginPlayingFromBeginning:(KEMediaController *)mediaController;
- (void)mediaControllerDidUpdateProgress:(NSTimeInterval)seconds duration:(NSTimeInterval)duration;
- (void)mediaControllerDidFinishPlaying:(KEMediaController *)mediaController;

@end

@protocol KEMediaControllerDataSource <NSObject>

- (NSString *)mediaTitleForMediaController:(KEMediaController *)mediaController;

@end

@interface KEMediaController : NSObject

@property (nonatomic, readonly) KEMediaControllerPlaybackState playbackState;
@property (nonatomic, readonly) KEMediaControllerBufferingState bufferingState;

@property (nonatomic, readonly) NSURL *mediaUrl;
@property (nonatomic, readonly) NSError *error;

@property (nonatomic, weak) id <KEMediaControllerDelegate> delegate;
@property (nonatomic, weak) id <KEMediaControllerDataSource> dataSource;

- (instancetype)init;

- (void)updateWithMediaUrl:(NSURL *)mediaUrl;

- (void)playFromBeginning;
- (void)playFromCurrentTime;
- (void)playFromCurrentTimeWithRewindOffset:(NSTimeInterval)offset;
- (void)pause;
- (void)stop;

@end
