/*
 * Copyright (c) 2015 Mayur Pawashe
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

#import "ZGRootlessConfiguration.h"
#import "ZGDebugLogging.h"

// Path to rootless configuration file that contains directories and applications that participate in 'rootless'
// This file should be thought of as documentation, not as a 100% true picture of what applications cannot be accessed
#define ROOTLESS_CONFIGURATION_PATH @"/System/Library/Sandbox/rootless.conf"

@implementation ZGRootlessConfiguration
{
	NSArray<NSURL *> * _Nullable _rootlessApplicationURLs;
	NSCache<NSURL *, NSNumber *> * _Nonnull _affectedFileURLsCache;
}

- (id)init
{
	self = [super init];
	if (self != nil)
	{
		_affectedFileURLsCache = [[NSCache alloc] init];
		
		NSFileManager *fileManager = [[NSFileManager alloc] init];
		if (![fileManager fileExistsAtPath:ROOTLESS_CONFIGURATION_PATH])
		{
			ZG_LOG(@"Warning: %@ does not exist", ROOTLESS_CONFIGURATION_PATH);
		}
		else
		{
			NSError *readError = nil;
			NSString *rootlessApplicationsContents = [[NSString alloc] initWithContentsOfFile:ROOTLESS_CONFIGURATION_PATH encoding:NSUTF8StringEncoding error:&readError];
			
			if (rootlessApplicationsContents == nil)
			{
				ZG_LOG(@"Warning: %@ could not be read with error: %@", ROOTLESS_CONFIGURATION_PATH, readError);
			}
			else
			{
				NSMutableArray<NSURL *> *tempRootlessApplicationURLs = [[NSMutableArray alloc] init];
				for (NSString *line in [rootlessApplicationsContents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]])
				{
					if ([line hasPrefix:@"#"])
					{
						continue;
					}
					
					NSArray<NSString *> *components = [line componentsSeparatedByString:@"\t"];
					if (components.count == 0)
					{
						continue;
					}
					
					NSString *applicationPath = components[components.count - 1];
					if (![applicationPath.pathExtension isEqualToString:@"app"] || ![fileManager fileExistsAtPath:applicationPath])
					{
						continue;
					}
					
					NSURL *applicationURL = [NSURL fileURLWithPath:applicationPath isDirectory:YES];
					if (applicationURL != nil)
					{
						[tempRootlessApplicationURLs addObject:applicationURL];
					}
				}
				
				_rootlessApplicationURLs = [tempRootlessApplicationURLs copy];
			}
		}
	}
	return self;
}

- (BOOL)_isFileURLAffected:(NSURL *)fileURL
{
	NSArray<NSString *> *pathComponents = fileURL.pathComponents;
	if (pathComponents.count > 1)
	{
		if ([[pathComponents subarrayWithRange:NSMakeRange(0, 2)] isEqualToArray:@"/System".pathComponents])
		{
			return YES;
		}
		
		if ([[pathComponents subarrayWithRange:NSMakeRange(0, 2)] isEqualToArray:@"/bin".pathComponents])
		{
			return YES;
		}
		
		if (pathComponents.count > 2)
		{
			if ([[pathComponents subarrayWithRange:NSMakeRange(0, 3)] isEqualToArray:@"/usr/libexec".pathComponents])
			{
				return YES;
			}
			
			if ([[pathComponents subarrayWithRange:NSMakeRange(0, 3)] isEqualToArray:@"/usr/bin".pathComponents])
			{
				return YES;
			}
			
			if ([[pathComponents subarrayWithRange:NSMakeRange(0, 3)] isEqualToArray:@"/usr/sbin".pathComponents])
			{
				return YES;
			}
		}
	}
	
	if (_rootlessApplicationURLs != nil)
	{
		NSURL *rootMostBundleURL = nil;
		NSUInteger pathComponentIndex = 0;
		for (NSString *pathComponent in fileURL.pathComponents)
		{
			if ([pathComponent.pathExtension isEqualToString:@"app"] || [pathComponent.pathExtension isEqualToString:@"xpc"])
			{
				rootMostBundleURL = [[NSURL fileURLWithPathComponents:[pathComponents subarrayWithRange:NSMakeRange(0, pathComponentIndex)]] URLByAppendingPathComponent:pathComponent isDirectory:YES];
				break;
			}
			pathComponentIndex++;
		}
		
		if (rootMostBundleURL != nil)
		{
			if ([_rootlessApplicationURLs containsObject:rootMostBundleURL])
			{
				return YES;
			}
			
			if ([[[NSBundle bundleWithURL:rootMostBundleURL] bundleIdentifier] hasPrefix:@"com.apple."])
			{
				return YES;
			}
		}
	}
	
	return NO;
}

- (BOOL)isFileURLAffected:(NSURL *)fileURL
{
	NSNumber *cachedResult = [_affectedFileURLsCache objectForKey:fileURL];
	if (cachedResult != nil) return cachedResult.boolValue;
	
	BOOL result = [self _isFileURLAffected:fileURL];
	[_affectedFileURLsCache setObject:@(result) forKey:fileURL];
	return result;
}

@end
