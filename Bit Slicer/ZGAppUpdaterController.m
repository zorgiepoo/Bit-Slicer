/*
 * Copyright (c) 2014 Mayur Pawashe
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * Redistributions of source code must retain the above copyright notice,
 * this list of conditions and the following disclaimer.
 *
 * Redistributions in binary form must reproduce the above copyright
 * notice, this list of conditions and the following disclaimer in the
 * documentation and/or other materials provided with the distribution.
 *
 * Neither the name of the project's author nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
 * TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "ZGAppUpdaterController.h"

#import <AppKit/AppKit.h>
#import <Sparkle/Sparkle.h>
#import "ZGNullability.h"

#define ZG_CHECK_FOR_ALPHA_UPDATES @"ZG_CHECK_FOR_ALPHA_UPDATES_2"
#define ZG_ENABLE_STAGING_CHANNEL @"ZG_ENABLE_STAGING_CHANNEL"

@interface ZGAppUpdaterController () <SPUUpdaterDelegate>
@end

@implementation ZGAppUpdaterController
{
	SPUStandardUpdaterController * _Nonnull _updaterController;
	SPUUpdater * _Nonnull _updater;
}

+ (BOOL)runningAlpha
{
	return [(NSString *)[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] rangeOfString:@"a"].location != NSNotFound;
}

+ (void)initialize
{
	[NSUserDefaults.standardUserDefaults
	 registerDefaults:
	 @{
	   // If user is running an alpha version, we should default alpha update checks to YES
	   ZG_CHECK_FOR_ALPHA_UPDATES : @([self runningAlpha])
	   }];
}

- (id)init
{
	self = [super init];
	if (self != nil)
	{
		_updaterController = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:NO updaterDelegate:self userDriverDelegate:nil];
		_updater = _updaterController.updater;
		
		// Clear feed URL so we don't use its cache
		[_updater clearFeedURLFromUserDefaults];
		
		[_updaterController startUpdater];
	}
	return self;
}

- (NSSet<NSString *> *)allowedChannelsForUpdater:(SPUUpdater *)__unused updater
{
	NSMutableArray<NSString *> *channels = [NSMutableArray array];
	
	if ([self checksForAlphaUpdates])
	{
		[channels addObject:@"alpha"];
	}
	
	if ([[NSUserDefaults standardUserDefaults] boolForKey:ZG_ENABLE_STAGING_CHANNEL])
	{
		[channels addObject:@"staging"];
	}
	
	return [NSSet setWithArray:channels];
}

- (BOOL)checksForUpdates
{
	return _updater.automaticallyChecksForUpdates;
}

- (void)setChecksForUpdates:(BOOL)checksForUpdates
{
	_updater.automaticallyChecksForUpdates = checksForUpdates;
}

- (BOOL)checksForAlphaUpdates
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:ZG_CHECK_FOR_ALPHA_UPDATES];
}

- (void)setChecksForAlphaUpdates:(BOOL)checksForAlphaUpdates
{
	[[NSUserDefaults standardUserDefaults] setBool:checksForAlphaUpdates forKey:ZG_CHECK_FOR_ALPHA_UPDATES];
	
	if (checksForAlphaUpdates)
	{
		[_updater resetUpdateCycleAfterShortDelay];
	}
}

- (BOOL)sendsAnonymousInfo
{
	return _updater.sendsSystemProfile;
}

- (void)setSendsAnonymousInfo:(BOOL)sendsAnonymousInfo
{
	_updater.sendsSystemProfile = sendsAnonymousInfo;
}

- (void)configureCheckForUpdatesMenuItem:(NSMenuItem *)checkForUpdatesMenuItem
{
	checkForUpdatesMenuItem.target = _updaterController;
	checkForUpdatesMenuItem.action = @selector(checkForUpdates:);
}

@end
