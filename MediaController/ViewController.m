//
//  ViewController.m
//  MediaController
//
//  Created by Denis Dovgan on 5/9/16.
//  Copyright © 2016 Denis Dovgan. All rights reserved.
//

#import "ViewController.h"

#import "KEMediaController.h"

@interface ViewController () <KEMediaControllerDelegate> {
	
	KEMediaController *_mediaController;
}

@end

@implementation ViewController

#pragma mark - View Lifecycle

- (void)viewDidLoad {
	[super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
	
	_mediaController = [[KEMediaController alloc] init];
	_mediaController.delegate = self;
	[_mediaController updateWithMediaUrl:[NSURL URLWithString:@"http://www.tonycuffe.com/mp3/tail%20toddle.mp3"]];
}

#pragma mark - User Actions

- (IBAction)playTapped:(id)sender {
	
	[_mediaController playFromBeginning];
}

#pragma mark - <KEMediaControllerDelegate>

- (void)mediaController:(KEMediaController *)mediaController didHandleInitializationError:(NSError *)error {
	
	NSLog(@"Error %@", error.localizedDescription);
}

- (void)mediaController:(KEMediaController *)mediaController didFetchItemDuration:(NSTimeInterval)duration {
	
	NSLog(@"Did fetch item duration %@", @(duration));
}

- (void)mediaControllerDidChangePlaybackState:(KEMediaController *)mediaController {

	NSLog(@"Did change playback state %@", @(mediaController.playbackState));
}

- (void)mediaPlayeDidChangeBufferingState:(KEMediaController *)mediaController {

	NSLog(@"Did change buffering state %@", @(mediaController.bufferingState));
}

- (void)mediaControllerDidBeginPlayingFromBeginning:(KEMediaController *)mediaController {

	NSLog(@"Did begin playing from beginning");
}

- (void)mediaControllerDidUpdateProgress:(NSTimeInterval)seconds duration:(NSTimeInterval)duration {
	
	NSLog(@"Did update progress %@, duration %@", @(seconds), @(duration));
}

- (void)mediaControllerDidFinishPlaying:(KEMediaController *)mediaController {
	
	NSLog(@"Did finish playing");
	
	[mediaController playFromBeginning];
}

@end
