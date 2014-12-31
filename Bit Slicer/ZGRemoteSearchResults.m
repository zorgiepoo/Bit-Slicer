/*
 * Created by Mayur Pawashe on 12/30/14.
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

#import "ZGRemoteSearchResults.h"
#import "ZGAppClient.h"

@implementation ZGRemoteSearchResults
{
	ZGAppClient *_appClient;
}

@synthesize dataType = _dataType;
@synthesize enabled = _enabled;
@synthesize dataSize = _dataSize;

- (id)initWithAppClient:(ZGAppClient *)appClient remoteIdentifier:(uint16_t)remoteIdentifier dataSize:(ZGMemorySize)dataSize
{
	self = [super init];
	if (self != nil)
	{
		_appClient = appClient;
		_remoteIdentifier = remoteIdentifier;
		_dataSize = dataSize;
	}
	return self;
}

- (void)dealloc
{
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:ZGNetworkMessageSearchResultsDealloc andObjectID:self->_remoteIdentifier];
		[self->_appClient sendEndMessage];
	});
}

- (void)removeNumberOfAddresses:(ZGMemorySize)numberOfAddresses
{
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:ZGNetworkMessageSearchResultsRemoveNumberOfAddresses andObjectID:self->_remoteIdentifier];
		
		uint64_t numberAddresses = numberOfAddresses;
		[self->_appClient sendBytes:&numberAddresses length:sizeof(numberAddresses)];
		
		[self->_appClient sendEndMessage];
	});
}

- (void)enumerateWithCount:(ZGMemorySize)addressCount usingBlock:(zg_enumerate_search_results_t)addressCallback
{
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:ZGNetworkMessageSearchResultsEnumerateWithCount andObjectID:self->_remoteIdentifier];
		
		const uint64_t numberAddresses = addressCount;
		[self->_appClient sendBytes:&numberAddresses length:sizeof(numberAddresses)];
		
		uint64_t *addresses = calloc(numberAddresses, sizeof(*addresses));
		[self->_appClient receiveBytes:addresses length:numberAddresses * sizeof(*addresses)];
		
		for (uint64_t addressIndex = 0; addressIndex < numberAddresses; addressIndex++)
		{
			addressCallback(addresses[addressIndex]);
		}
		
		free(addresses);
		
		[self->_appClient sendEndMessage];
	});
}

- (ZGMemoryAddress)retreiveSizeFieldOfMessageType:(ZGNetworkMessageType)messageType
{
	__block uint64_t size = 0;
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:messageType andObjectID:self->_remoteIdentifier];
		
		[self->_appClient receiveBytes:&size length:sizeof(size)];
		
		[self->_appClient sendEndMessage];
	});
	return size;
}

- (ZGMemorySize)addressCount
{
	return [self retreiveSizeFieldOfMessageType:ZGNetworkMessageSearchResultsAddressCount];
}

- (ZGMemorySize)pointerSize
{
	return [self retreiveSizeFieldOfMessageType:ZGNetworkMessageSearchResultsPointerSize];
}

@end
