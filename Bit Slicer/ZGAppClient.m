/*
 * Created by Mayur Pawashe on 12/27/14.
 *
 * Copyright (c) 2014 zgcoder
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

#import "ZGAppClient.h"
#import "ZGUtilities.h"

@implementation ZGAppClient
{
	NSString *_host;
	int _socket;
	BOOL _connected;
	dispatch_queue_t _dispatchQueue;
}

- (id)initWithHost:(NSString *)host
{
	self = [super init];
	if (self != nil)
	{
		_host = [host copy];
	}
	return self;
}

- (void)dealloc
{
	[self disconnect];
}

- (void)connect
{
	struct addrinfo hints;
	memset(&hints, 0, sizeof(hints));
	hints.ai_family = AF_UNSPEC;
	hints.ai_socktype = SOCK_STREAM;
	
	struct addrinfo *addressInfoResults = NULL;
	int addressInfoError = getaddrinfo([_host UTF8String], NETWORK_PORT, &hints, &addressInfoResults);
	if (addressInfoError != 0)
	{
		NSLog(@"Failed to get address info on connect: %s", gai_strerror(addressInfoError));
		return;
	}
	
	struct addrinfo *addressInfo = NULL;
	for (addressInfo = addressInfoResults; addressInfo != NULL; addressInfo = addressInfo->ai_next)
	{
		_socket = socket(addressInfo->ai_family, addressInfo->ai_socktype, addressInfo->ai_protocol);
		if (_socket == -1)
		{
			perror("client: socket");
			continue;
		}
		
		if (connect(_socket, addressInfo->ai_addr, addressInfo->ai_addrlen) == -1)
		{
			close(_socket);
			perror("client: connect");
			continue;
		}
		
		break;
	}
	
	if (addressInfo == NULL)
	{
		NSLog(@"Failed to find an addressInfo on connect");
		return;
	}
	
	freeaddrinfo(addressInfoResults);
	
	_connected = YES;
	if (_dispatchQueue == NULL)
	{
		_dispatchQueue = dispatch_queue_create(NULL, DISPATCH_QUEUE_SERIAL);
	}
	
	ZG_LOG(@"Connected to server");
}

- (void)disconnect
{
	if (_connected)
	{
		close(_socket);
		_connected = NO;
	}
}

- (void)sendBytes:(const void *)bytes length:(size_t)length
{
	if (_connected && !ZGNetworkWriteData(_socket, bytes, length))
	{
		[self disconnect];
		ZG_LOG(@"Client: Send failed..");
	}
}

- (void)receiveBytes:(void *)bytes length:(size_t)length
{
	if (_connected && !ZGNetworkReadData(_socket, bytes, length))
	{
		[self disconnect];
		ZG_LOG(@"Client: Recv failed..");
	}
}

- (void)sendMessageType:(ZGNetworkMessageType)messageType
{
	[self sendBytes:&messageType length:sizeof(messageType)];
}

- (void)sendMessageType:(ZGNetworkMessageType)messageType andObjectID:(uint16_t)objectID
{
	[self sendMessageType:messageType];
	[self sendBytes:&objectID length:sizeof(objectID)];
}

- (void)sendEndMessage
{
	[self sendMessageType:ZGNetworkMessageEndProcedure];
}

@end
