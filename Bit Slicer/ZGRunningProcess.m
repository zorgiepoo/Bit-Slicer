/*
 * Created by Mayur Pawashe on 1/1/13.
 *
 * Copyright (c) 2012 zgcoder
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

#define ZGRunningProcessInternalNameKey @"ZGRunningProcessInternalNameKey"
#define ZGRunningProcessIs64BitKey @"ZGRunningProcessIs64BitKey"
#define ZGRunningProcessIdentifierKey @"ZGRunningProcessIdentifierKey"
#define ZGRunningProcessIconKey @"ZGRunningProcessIconKey"
#define ZGRunningProcessNameKey @"ZGRunningProcessNameKey"
#define ZGRunningProcessActivationPolicyKey @"ZGRunningProcessActivationPolicyKey"
#define ZGRunningProcessDidFetchInfoKey @"ZGRunningProcessDidFetchInfoKey"

@implementation ZGRunningProcess
{
	NSApplicationActivationPolicy _activationPolicy;
	NSImage *_icon;
	NSString *_name;
	BOOL _didFetchInfo;
}

#pragma mark Archiving

+ (BOOL)supportsSecureCoding
{
	return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_internalName forKey:ZGRunningProcessInternalNameKey];
	[coder encodeBool:_is64Bit forKey:ZGRunningProcessIs64BitKey];
	[coder encodeInteger:_processIdentifier forKey:ZGRunningProcessIdentifierKey];
	
	[coder encodeObject:_icon forKey:ZGRunningProcessIconKey];
	[coder encodeObject:_name forKey:ZGRunningProcessNameKey];
	[coder encodeInteger:_activationPolicy forKey:ZGRunningProcessActivationPolicyKey];
	[coder encodeBool:_didFetchInfo forKey:ZGRunningProcessDidFetchInfoKey];
}

- (id)initWithCoder:(NSCoder *)decoder
{
	Class myClass = [self class];
	NSString *internalName = [decoder decodeObjectOfClass:myClass forKey:ZGRunningProcessInternalNameKey];
	BOOL is64Bit = [decoder decodeBoolForKey:ZGRunningProcessIs64BitKey];
	pid_t processIdentifier = (pid_t)[decoder decodeIntegerForKey:ZGRunningProcessIdentifierKey];
	
	self = [self initWithProcessIdentifier:processIdentifier is64Bit:is64Bit internalName:internalName];
	if (self != nil)
	{
		_didFetchInfo = [[decoder decodeObjectOfClass:myClass forKey:ZGRunningProcessDidFetchInfoKey] boolValue];
		if (_didFetchInfo)
		{
			_icon = [decoder decodeObjectOfClass:myClass forKey:ZGRunningProcessIconKey];
			_name = [decoder decodeObjectOfClass:myClass forKey:ZGRunningProcessNameKey];
			_activationPolicy = [decoder decodeIntegerForKey:ZGRunningProcessActivationPolicyKey];
		}
	}
	return self;
}

#pragma mark Birth

- (id)initWithProcessIdentifier:(pid_t)processIdentifier is64Bit:(BOOL)is64Bit internalName:(NSString *)name
{
	self = [super init];
	if (self != nil)
	{
		_processIdentifier = processIdentifier;
		_is64Bit = is64Bit;
		self.internalName = name;
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
	return self.processIdentifier == [object processIdentifier];
}

- (NSUInteger)hash
{
	return (NSUInteger)self.processIdentifier;
}

#pragma mark On-the-fly Accessors

- (void)fetchRunningApplicationInfo
{
	if (!_didFetchInfo)
	{
		NSRunningApplication *runningApplication = [NSRunningApplication runningApplicationWithProcessIdentifier:self.processIdentifier];
		if (runningApplication != nil)
		{
			self->_activationPolicy = runningApplication.activationPolicy;
			self->_icon = runningApplication.icon;
			self->_name = runningApplication.localizedName;
		}
		else
		{
			self->_activationPolicy = NSApplicationActivationPolicyProhibited;
			self->_icon = [NSImage imageNamed:@"NSDefaultApplicationIcon"];
			self->_name = self.internalName;
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

@end
