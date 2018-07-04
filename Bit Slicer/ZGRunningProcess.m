/*
 * Copyright (c) 2012 Mayur Pawashe
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

#import "ZGRunningProcess.h"
#import <sys/types.h>
#import <sys/sysctl.h>
#import <libproc.h>

@implementation ZGRunningProcess
{
	NSApplicationActivationPolicy _activationPolicy;
	NSImage * _Nullable _icon;
	NSString * _Nullable _name;
	NSURL * _Nullable _fileURL;
	BOOL _didFetchInfo;
	BOOL _isGame;
	BOOL _isThirdParty;
	BOOL _isWebContent;
	BOOL _hasHelpers;
}

#pragma mark Birth

- (id)initWithProcessIdentifier:(pid_t)processIdentifier is64Bit:(BOOL)is64Bit internalName:(NSString *)name
{
	self = [super init];
	if (self != nil)
	{
		_processIdentifier = processIdentifier;
		_internalName = (name != nil) ? [name copy] : [NSString stringWithFormat:@"%d", processIdentifier];
		_is64Bit = is64Bit;
	}
	return self;
}

- (id)initWithProcessIdentifier:(pid_t)processIdentifier
{
	return [self initWithProcessIdentifier:processIdentifier is64Bit:YES internalName:nil];
}

#pragma mark Comparisons

- (BOOL)isEqual:(id)object
{
	return _processIdentifier == [(ZGRunningProcess *)object processIdentifier];
}

- (NSUInteger)hash
{
	return (NSUInteger)_processIdentifier;
}

#pragma mark On-the-fly Accessors

- (void)fetchRunningApplicationInfo
{
	if (!_didFetchInfo)
	{
		NSRunningApplication *runningApplication = [NSRunningApplication runningApplicationWithProcessIdentifier:_processIdentifier];
		if (runningApplication != nil)
		{
			_activationPolicy = runningApplication.activationPolicy;
			_icon = runningApplication.icon;
			_name = runningApplication.localizedName;
			_fileURL = runningApplication.bundleURL;
			
			NSString *bundleIdentifier = runningApplication.bundleIdentifier;
			_isThirdParty = ![bundleIdentifier hasPrefix:@"com.apple."];
			_isWebContent = ([_name isEqualToString:@"Safari Web Content"] || [_name isEqualToString:@"Google Chrome Helper"] || [_name isEqualToString:@"Firefox Web Content"]);
			_hasHelpers = [bundleIdentifier isEqualToString:@"com.apple.Safari"] || [bundleIdentifier isEqualToString:@"com.google.Chrome"];
			
			NSURL *applicationBundleURL = runningApplication.bundleURL;
			if (applicationBundleURL != nil)
			{
				NSBundle *applicationBundle = [NSBundle bundleWithURL:applicationBundleURL];
				if (applicationBundle != nil)
				{
					NSString *category = [applicationBundle objectForInfoDictionaryKey:@"LSApplicationCategoryType"];
					if ([category isKindOfClass:[NSString class]])
					{
						_isGame = [category rangeOfString:@"games"].location != NSNotFound;
					}
				}
			}
		}
		else
		{
			_activationPolicy = NSApplicationActivationPolicyProhibited;
			_icon = [NSImage imageNamed:@"NSDefaultApplicationIcon"];
			_name = [_internalName copy];
			
			char pathBuffer[PROC_PIDPATHINFO_MAXSIZE] = {0};
			int numberOfBytesRead = proc_pidpath(_processIdentifier, pathBuffer, sizeof(pathBuffer));
			if (numberOfBytesRead > 0)
			{
				NSString *path = [[NSString alloc] initWithBytes:pathBuffer length:(NSUInteger)numberOfBytesRead encoding:NSUTF8StringEncoding];
				if (path != nil)
				{
					_fileURL = [NSURL fileURLWithPath:path];
				}
			}
		}
		
		_didFetchInfo = YES;
	}
}

- (void)invalidateAppInfoCache
{
	_didFetchInfo = NO;
}

- (NSApplicationActivationPolicy)activationPolicy
{
	[self fetchRunningApplicationInfo];
	return _activationPolicy;
}

- (NSImage *)icon
{
	[self fetchRunningApplicationInfo];
	return _icon;
}

- (NSString *)name
{
	[self fetchRunningApplicationInfo];
	return _name;
}

- (NSURL *)fileURL
{
	[self fetchRunningApplicationInfo];
	return _fileURL;
}

- (BOOL)isGame
{
	[self fetchRunningApplicationInfo];
	return _isGame;
}

- (BOOL)isThirdParty
{
	[self fetchRunningApplicationInfo];
	return _isThirdParty;
}

- (BOOL)isWebContent
{
	[self fetchRunningApplicationInfo];
	return _isWebContent;
}

- (BOOL)hasHelpers
{
	[self fetchRunningApplicationInfo];
	return _hasHelpers;
}

@end
