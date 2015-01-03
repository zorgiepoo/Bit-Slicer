/*
 * Created by Mayur Pawashe on 1/2/15.
 *
 * Copyright (c) 2015 zgcoder
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

#import "ZGRemoteStoredData.h"
#import "ZGAppClient.h"
#import "ZGRemoteProcessHandle.h"

#define ZGRemoteIdentifierKey @"ZGRemoteIdentifierKey"

@implementation ZGRemoteStoredData
{
	ZGAppClient *_appClient;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeInt32:_remoteIdentifier forKey:ZGRemoteIdentifierKey];
}

- (id)initWithCoder:(NSCoder *)decoder
{
	self = [super init];
	if (self != nil)
	{
		_remoteIdentifier = (uint16_t)[decoder decodeInt32ForKey:ZGRemoteIdentifierKey];
	}
	return self;
}

- (id)initWithAppClient:(ZGAppClient *)appClient handleIdentifier:(uint16_t)handleIdentifier
{
	self = [super init];
	if (self != nil)
	{
		_appClient = appClient;
		
		dispatch_sync(_appClient.dispatchQueue, ^{
			[self->_appClient sendMessageType:ZGNetworkMessageStoreValues andObjectID:handleIdentifier];
			[self->_appClient receiveBytes:&self->_remoteIdentifier length:sizeof(self->_remoteIdentifier)];
			[self->_appClient sendEndMessage];
		});
	}
	return self;
}

- (void)dealloc
{
	if (_appClient != nil) // could be nil if this instance was decoded
	{
		dispatch_sync(_appClient.dispatchQueue, ^{
			[self->_appClient sendMessageType:ZGNetworkMessageStoreValuesDealloc andObjectID:self->_remoteIdentifier];
			[self->_appClient sendEndMessage];
		});
	}
}

@end
