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

#import "ZGRemoteProcessHandle.h"
#import "ZGAppClient.h"
#import "ZGRegion.h"

@implementation ZGRemoteProcessHandle
{
	ZGAppClient *_appClient;
	uint16_t _remoteHandleIdentifier;
}

- (id)initWithProcessTask:(ZGMemoryMap)processTask appClient:(ZGAppClient *)appClient
{
	self = [super init];
	if (self != nil)
	{
		_appClient = appClient;
		
		dispatch_sync(_appClient.dispatchQueue, ^{
			[self->_appClient sendMessageType:ZGNetworkMessageCreateProcessHandle];
			
			uint32_t task = processTask;
			[self->_appClient sendBytes:&task length:sizeof(task)];
			[self->_appClient receiveBytes:&self->_remoteHandleIdentifier length:sizeof(self->_remoteHandleIdentifier)];
		});
	}
	return self;
}

- (BOOL)allocateMemoryAndGetAddress:(ZGMemoryAddress *)address size:(ZGMemorySize)size
{
	__block ZGMemoryAddress addressReceived = 0x0;
	__block bool success = false;
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:ZGNetworkMessageAllocateMemory andObjectID:self->_remoteHandleIdentifier];
		
		uint64_t sizeSent = size;
		[self->_appClient sendBytes:&sizeSent length:sizeof(sizeSent)];
		
		uint64_t results[2];
		[self->_appClient receiveBytes:results length:sizeof(results)];
		
		addressReceived = results[0];
		success = (bool)results[1];
	});
	
	if (success)
	{
		*address = addressReceived;
	}
	
	return success;
}

- (BOOL)deallocateMemoryAtAddress:(ZGMemoryAddress)address size:(ZGMemorySize)size
{
	__block bool success = false;
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:ZGNetworkMessageDeallocateMemory andObjectID:self->_remoteHandleIdentifier];
		
		uint64_t sizeSent = size;
		uint64_t addressSent = address;
		
		[self->_appClient sendBytes:&addressSent length:sizeof(addressSent)];
		[self->_appClient sendBytes:&sizeSent length:sizeof(sizeSent)];
		
		[self->_appClient receiveBytes:&success length:sizeof(success)];
	});
	
	return success;
}

- (BOOL)readBytes:(void **)bytes address:(ZGMemoryAddress)address size:(ZGMemorySize *)size
{
	__block bool success = false;
	__block uint64_t sizeReceived = 0;
	__block void *bytesReceived = NULL;
	
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:ZGNetworkMessageReadBytes andObjectID:self->_remoteHandleIdentifier];
		
		uint64_t sendData[2] = {address, *size};
		[self->_appClient sendBytes:sendData length:sizeof(sendData)];
		
		[self->_appClient receiveBytes:&success length:sizeof(success)];
		
		if (success)
		{
			[self->_appClient receiveBytes:&sizeReceived length:sizeof(sizeReceived)];
			if (sizeReceived > 0)
			{
				bytesReceived = malloc(sizeReceived);
				
				[self->_appClient receiveBytes:bytesReceived length:sizeReceived];
			}
		}
	});
	
	if (success)
	{
		*bytes = bytesReceived;
		*size = sizeReceived;
	}
	
	return success;
}

- (BOOL)freeBytes:(void *)bytes size:(ZGMemorySize)__unused size
{
	free(bytes);
	return YES;
}

- (BOOL)writeBytes:(const void *)bytes address:(ZGMemoryAddress)address size:(ZGMemorySize)size messageType:(ZGNetworkMessageType)messageType
{
	__block bool success = false;
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:messageType andObjectID:self->_remoteHandleIdentifier];
		
		uint64_t sendData[2] = {address, size};
		[self->_appClient sendBytes:sendData length:sizeof(sendData)];
		
		[self->_appClient sendBytes:bytes length:size];
		
		[self->_appClient receiveBytes:&success length:sizeof(success)];
	});
	
	return success;
}

- (BOOL)writeBytes:(const void *)bytes address:(ZGMemoryAddress)address size:(ZGMemorySize)size
{
	return [self writeBytes:bytes address:address size:size messageType:ZGNetworkMessageWriteBytes];
}

- (BOOL)writeBytesOverwritingProtection:(const void *)bytes address:(ZGMemoryAddress)address size:(ZGMemorySize)size
{
	return [self writeBytes:bytes address:address size:size messageType:ZGNetworkMessageWriteBytesOverwritingProtection];
}

- (BOOL)writeBytesIgnoringProtection:(const void *)bytes address:(ZGMemoryAddress)address size:(ZGMemorySize)size
{
	return [self writeBytes:bytes address:address size:size messageType:ZGNetworkMessageWriteBytesIgnoringProtection];
}

- (BOOL)getDyldTaskInfo:(struct task_dyld_info *)dyldTaskInfo count:(mach_msg_type_number_t *)count
{
	__block bool success = false;
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:ZGNetworkMessageGetDlydTaskInfo andObjectID:self->_remoteHandleIdentifier];
		[self->_appClient receiveBytes:&success length:sizeof(success)];
		
		uint32_t countReceived = 0;
		[self ->_appClient receiveBytes:&countReceived length:sizeof(countReceived)];
		
		*count = countReceived;
		
		if (success)
		{
			[self ->_appClient receiveBytes:dyldTaskInfo length:sizeof(*dyldTaskInfo)];
		}
	});
	
	return success;
}

- (BOOL)setProtection:(ZGMemoryProtection)protection address:(ZGMemoryAddress)address size:(ZGMemorySize)size
{
	__block bool success = false;
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:ZGNetworkMessageSetProtection andObjectID:self->_remoteHandleIdentifier];
		int32_t sentProtection = protection;
		uint64_t addressAndSize[2] = {address, size};
		
		[self->_appClient sendBytes:&sentProtection length:sizeof(sentProtection)];
		[self->_appClient sendBytes:addressAndSize length:sizeof(addressAndSize)];
		[self->_appClient receiveBytes:&success length:sizeof(success)];
	});
	return success;
}

- (BOOL)getPageSize:(ZGMemorySize *)pageSize
{
	__block bool success = false;
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:ZGNetworkMessageGetPageSize andObjectID:self->_remoteHandleIdentifier];
		[self->_appClient receiveBytes:&success length:sizeof(success)];
		if (success)
		{
			uint64_t pageSizeReceived = 0;
			[self->_appClient receiveBytes:&pageSizeReceived length:sizeof(pageSizeReceived)];
			
			*pageSize = pageSizeReceived;
		}
	});
	return success;
}

- (BOOL)suspendOrResumeWithMessageType:(ZGNetworkMessageType)messageType
{
	__block bool success = false;
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:messageType andObjectID:self->_remoteHandleIdentifier];
		[self->_appClient receiveBytes:&success length:sizeof(success)];
	});
	return success;
}

- (BOOL)suspend
{
	return [self suspendOrResumeWithMessageType:ZGNetworkMessageSuspend];
}

- (BOOL)resume
{
	return [self suspendOrResumeWithMessageType:ZGNetworkMessageResume];
}

- (BOOL)getSuspendCount:(integer_t *)suspendCount
{
	__block bool success = false;
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:ZGNetworkMessageGetSuspendCount andObjectID:self->_remoteHandleIdentifier];
		[self->_appClient receiveBytes:&success length:sizeof(success)];
		
		if (success)
		{
			int32_t receivedSuspendCount = 0;
			[self->_appClient receiveBytes:&receivedSuspendCount length:sizeof(receivedSuspendCount)];
			
			*suspendCount = receivedSuspendCount;
		}
	});
	return success;
}

- (NSArray *)regionsOrSubmapRegionsWithMessageType:(ZGNetworkMessageType)messageType
{
	__block NSArray *regions = nil;
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:messageType andObjectID:self->_remoteHandleIdentifier];
		
		uint64_t numberOfBytes = 0;
		[self->_appClient receiveBytes:&numberOfBytes length:sizeof(numberOfBytes)];
		
		void *buffer = malloc(numberOfBytes);
		
		[self->_appClient receiveBytes:buffer length:numberOfBytes];
		
		regions = [NSKeyedUnarchiver unarchiveObjectWithData:[NSData dataWithBytesNoCopy:buffer length:numberOfBytes]];
	});
	
	assert([regions isKindOfClass:[NSArray class]]);
	for (id region in regions)
	{
		assert([region isKindOfClass:[ZGRegion class]]);
	}
	
	return regions;
}

- (NSArray *)regions
{
	return [self regionsOrSubmapRegionsWithMessageType:ZGNetworkMessageRegions];
}

- (NSArray *)submapRegions
{
	return [self regionsOrSubmapRegionsWithMessageType:ZGNetworkMessageSubmapRegions];
}

- (NSArray *)submapRegionsInRegion:(ZGRegion *)region
{
	__block NSArray *regions = nil;
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:ZGNetworkMessageSubmapRegionsInRegion andObjectID:self->_remoteHandleIdentifier];
		
		NSData *archivedData = [NSKeyedArchiver archivedDataWithRootObject:region];
		uint64_t numberOfBytesSent = archivedData.length;
		[self->_appClient sendBytes:&numberOfBytesSent length:sizeof(numberOfBytesSent)];
		
		[self->_appClient sendBytes:archivedData.bytes length:numberOfBytesSent];
		
		uint64_t numberOfBytesToReceive = 0;
		[self->_appClient receiveBytes:&numberOfBytesToReceive length:sizeof(numberOfBytesToReceive)];
		
		void *buffer = malloc(numberOfBytesToReceive);
		
		[self->_appClient receiveBytes:buffer length:numberOfBytesToReceive];
		
		regions = [NSKeyedUnarchiver unarchiveObjectWithData:[NSData dataWithBytesNoCopy:buffer length:numberOfBytesToReceive]];
	});
	
	assert([regions isKindOfClass:[NSArray class]]);
	for (id resultRegion in regions)
	{
		assert([resultRegion isKindOfClass:[ZGRegion class]]);
	}
	
	return regions;
}

- (BOOL)getRegionInfo:(ZGMemoryBasicInfo *)regionInfo address:(ZGMemoryAddress *)address size:(ZGMemorySize *)size
{
	__block bool success = false;
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:ZGNetworkMessageGetRegionInfo andObjectID:self->_remoteHandleIdentifier];
		
		uint64_t sendData[2] = {*address, *size};
		[self->_appClient sendBytes:sendData length:sizeof(sendData)];
		
		[self->_appClient receiveBytes:&success length:sizeof(success)];
		
		if (success)
		{
			uint64_t receiveData[2] = {};
			[self->_appClient receiveBytes:receiveData length:sizeof(receiveData)];
			
			*address = receiveData[0];
			*size = receiveData[1];
			
			[self->_appClient receiveBytes:regionInfo length:sizeof(*regionInfo)];
		}
	});
	
	return success;
}

- (BOOL)getMemoryProtection:(ZGMemoryProtection *)memoryProtection address:(ZGMemoryAddress *)address size:(ZGMemorySize *)size
{
	__block bool success = false;
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:ZGNetworkMessageGetMemoryProtection andObjectID:self->_remoteHandleIdentifier];
		
		uint64_t sendData[2] = {*address, *size};
		[self->_appClient sendBytes:sendData length:sizeof(sendData)];
		
		[self->_appClient receiveBytes:&success length:sizeof(success)];
		
		if (success)
		{
			uint64_t receiveData[2] = {};
			[self->_appClient receiveBytes:receiveData length:sizeof(receiveData)];
			
			*address = receiveData[0];
			*size = receiveData[1];
			
			int32_t protection = 0;
			[self->_appClient receiveBytes:&protection length:sizeof(protection)];
			
			*memoryProtection = protection;
		}
	});
	
	return success;
}

- (NSString *)symbolAtAddress:(ZGMemoryAddress)address relativeOffset:(ZGMemoryAddress *)relativeOffset
{
	__block NSString *symbol = nil;
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:ZGNetworkMessageSymbolAtAddress andObjectID:self->_remoteHandleIdentifier];
		
		uint64_t addressSent = address;
		[self->_appClient sendBytes:&addressSent length:sizeof(addressSent)];
		
		bool wantsRelativeOffset = (relativeOffset != NULL);
		[self->_appClient sendBytes:&wantsRelativeOffset length:sizeof(wantsRelativeOffset)];
		
		bool success = false;
		[self->_appClient receiveBytes:&success length:sizeof(success)];
		
		if (success)
		{
			uint64_t numberOfBytes = 0;
			[self->_appClient receiveBytes:&numberOfBytes length:sizeof(numberOfBytes)];
			
			void *buffer = malloc(numberOfBytes);
			[self->_appClient receiveBytes:buffer length:numberOfBytes];
			
			symbol = [[NSString alloc] initWithBytesNoCopy:buffer length:numberOfBytes encoding:NSUTF8StringEncoding freeWhenDone:YES];
			
			if (wantsRelativeOffset)
			{
				uint64_t offset = 0;
				[self->_appClient receiveBytes:&offset length:sizeof(offset)];
				
				*relativeOffset = offset;
			}
		}
	});
	return symbol;
}

- (NSNumber *)findSymbol:(NSString *)symbolName withPartialSymbolOwnerName:(NSString *)partialSymbolOwnerName requiringExactMatch:(BOOL)requiresExactMatch pastAddress:(ZGMemoryAddress)pastAddress
{
	__block NSNumber *symbolAddressNumber = nil;
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:ZGNetworkMessageFindSymbol andObjectID:self->_remoteHandleIdentifier];
		
		const void *symbolNameCString = [symbolName UTF8String];
		assert(symbolNameCString != NULL);
		uint64_t numberOfBytesForSymbolName = strlen(symbolNameCString);
		
		[self->_appClient sendBytes:&numberOfBytesForSymbolName length:sizeof(numberOfBytesForSymbolName)];
		[self->_appClient sendBytes:symbolNameCString length:numberOfBytesForSymbolName];
		
		const void *partialSymbolOwnerNameCString = [partialSymbolOwnerName UTF8String];
		bool hasPartialSymbolOwnerName = (partialSymbolOwnerName != nil && partialSymbolOwnerNameCString != NULL);
		
		[self->_appClient sendBytes:&hasPartialSymbolOwnerName length:sizeof(hasPartialSymbolOwnerName)];
		
		if (hasPartialSymbolOwnerName)
		{
			uint64_t numberOfBytesForPartialSymbolOwnerName = strlen(partialSymbolOwnerNameCString);
			[self->_appClient sendBytes:&numberOfBytesForPartialSymbolOwnerName length:sizeof(numberOfBytesForPartialSymbolOwnerName)];
			[self->_appClient sendBytes:partialSymbolOwnerNameCString length:numberOfBytesForPartialSymbolOwnerName];
		}
		
		bool exactMatch = requiresExactMatch;
		[self->_appClient sendBytes:&exactMatch length:sizeof(exactMatch)];
		
		uint64_t previousAddress = pastAddress;
		[self->_appClient sendBytes:&previousAddress length:sizeof(previousAddress)];
		
		bool success = false;
		[self->_appClient receiveBytes:&success length:sizeof(success)];
		
		if (success)
		{
			uint64_t result = 0;
			[self->_appClient receiveBytes:&result length:sizeof(result)];
			
			symbolAddressNumber = @(result);
		}
	});
	
	return symbolAddressNumber;
}

- (ZGMemorySize)readStringSizeFromAddress:(ZGMemoryAddress)address dataType:(ZGVariableType)dataType oldSize:(ZGMemorySize)oldSize maxSize:(ZGMemorySize)maxStringSizeLimit
{
	__block uint64_t sizeRead = 0;
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:ZGNetworkMessageReadStringSizeFromAddress andObjectID:self->_remoteHandleIdentifier];
		
		uint64_t addressToSend = address;
		[self->_appClient sendBytes:&addressToSend length:sizeof(addressToSend)];
		
		uint16_t dataTypeToSend = dataType;
		[self->_appClient sendBytes:&dataTypeToSend length:sizeof(dataTypeToSend)];
		
		uint64_t previousSize = oldSize;
		[self->_appClient sendBytes:&previousSize length:sizeof(previousSize)];
		
		uint64_t maxStringSizeLimitToSend = maxStringSizeLimit;
		[self->_appClient sendBytes:&maxStringSizeLimitToSend length:sizeof(maxStringSizeLimitToSend)];
		
		[self->_appClient receiveBytes:&sizeRead length:sizeof(sizeRead)];
	});
	
	return sizeRead;
}

@end
