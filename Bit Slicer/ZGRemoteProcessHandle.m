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
#import "ZGRemoteSearchResults.h"
#import "ZGSearchProgress.h"
#import "ZGSearchData.h"
#import "ZGLocalSearchResults.h"

#import "ZGUtilities.h"

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
			
			[self->_appClient sendEndMessage];
		});
	}
	return self;
}

- (void)dealloc
{
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:ZGNetworkMessageDeallocProcessHandle andObjectID:self->_remoteHandleIdentifier];
		[self->_appClient sendEndMessage];
	});
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
		
		[self->_appClient sendEndMessage];
		
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
		
		[self->_appClient sendEndMessage];
	});
	
	return success;
}

- (BOOL)readBytes:(void **)bytes address:(ZGMemoryAddress)address size:(ZGMemorySize *)size
{
	__block bool success = false;
	
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:ZGNetworkMessageReadBytes andObjectID:self->_remoteHandleIdentifier];
		
		uint64_t sendData[2] = {address, *size};
		[self->_appClient sendBytes:sendData length:sizeof(sendData)];
		
		[self->_appClient receiveBytes:&success length:sizeof(success)];
		
		if (success)
		{
			uint64_t sizeReceived = 0;
			[self->_appClient receiveBytes:&sizeReceived length:sizeof(sizeReceived)];
			
			//NSLog(@"Allocating size %llu, size first was %llu", sizeReceived, *size);
			*size = sizeReceived;
			*bytes = malloc(sizeReceived);
			
			if (sizeReceived > 0)
			{
				[self->_appClient receiveBytes:*bytes length:sizeReceived];
			}
		}
		
		[self->_appClient sendEndMessage];
	});
	
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
		
		[self->_appClient sendEndMessage];
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
		
		[self->_appClient sendEndMessage];
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
		
		[self->_appClient sendEndMessage];
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
		
		[self->_appClient sendEndMessage];
	});
	return success;
}

- (BOOL)suspendOrResumeWithMessageType:(ZGNetworkMessageType)messageType
{
	__block bool success = false;
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:messageType andObjectID:self->_remoteHandleIdentifier];
		[self->_appClient receiveBytes:&success length:sizeof(success)];
		[self->_appClient sendEndMessage];
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
		
		[self->_appClient sendEndMessage];
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
		
		[self->_appClient sendEndMessage];
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
		
		[self->_appClient sendEndMessage];
	});
	
	assert([regions isKindOfClass:[NSArray class]]);
	for (id resultRegion in regions)
	{
		assert([resultRegion isKindOfClass:[ZGRegion class]]);
	}
	
	return regions;
}

- (BOOL)getRegionInfo:(void *)regionInfo regionInfoSize:(size_t)regionInfoSize messageType:(ZGNetworkMessageType)messageType address:(ZGMemoryAddress *)address size:(ZGMemorySize *)size
{
	__block bool success = false;
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:messageType andObjectID:self->_remoteHandleIdentifier];
		
		uint64_t sendData[2] = {*address, *size};
		[self->_appClient sendBytes:sendData length:sizeof(sendData)];
		
		[self->_appClient receiveBytes:&success length:sizeof(success)];
		
		if (success)
		{
			uint64_t receiveData[2] = {};
			[self->_appClient receiveBytes:receiveData length:sizeof(receiveData)];
			
			*address = receiveData[0];
			*size = receiveData[1];
			
			[self->_appClient receiveBytes:regionInfo length:regionInfoSize];
		}
		
		[self->_appClient sendEndMessage];
	});
	
	return success;
}

- (BOOL)getRegionInfo:(ZGMemoryBasicInfo *)regionInfo address:(ZGMemoryAddress *)address size:(ZGMemorySize *)size
{
	return [self getRegionInfo:regionInfo regionInfoSize:sizeof(*regionInfo) messageType:ZGNetworkMessageGetRegionInfo address:address size:size];
}

- (BOOL)getSubmapRegionInfo:(ZGMemorySubmapInfo *)submapRegionInfo address:(ZGMemoryAddress *)address size:(ZGMemorySize *)size
{
	return [self getRegionInfo:submapRegionInfo regionInfoSize:sizeof(*submapRegionInfo) messageType:ZGNetworkMessageGetRegionSubmapInfo address:address size:size];
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
		
		[self->_appClient sendEndMessage];
	});
	
	return success;
}

- (NSString *)userTagDescriptionFromAddress:(ZGMemoryAddress)address size:(ZGMemorySize)size
{
	__block NSString *userTag = nil;
	
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:ZGNetworkMessageUserTagDescription andObjectID:self->_remoteHandleIdentifier];
		
		uint64_t addressAndSize[2] = {address, size};
		[self->_appClient sendBytes:addressAndSize length:sizeof(addressAndSize)];
		
		bool success = false;
		[self->_appClient receiveBytes:&success length:sizeof(success)];
		
		if (success)
		{
			uint64_t length = 0;
			[self->_appClient receiveBytes:&length length:sizeof(length)];
			
			void *buffer = malloc(length);
			[self->_appClient receiveBytes:buffer length:length];
			
			userTag = [[NSString alloc] initWithBytesNoCopy:buffer length:length encoding:NSUTF8StringEncoding freeWhenDone:YES];
		}
		
		[self->_appClient sendEndMessage];
	});
	
	return userTag;
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
		
		[self->_appClient sendEndMessage];
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
		
		[self->_appClient sendEndMessage];
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
		
		[self->_appClient sendEndMessage];
	});
	
	return sizeRead;
}

- (uint16_t)sendSearchData:(ZGSearchData *)searchData isNarrowing:(BOOL)narrowing withFirstSearchResults:(ZGLocalSearchResults <ZGSearchResults> *)firstSearchResults laterSearchResults:(id <ZGSearchResults>)laterSearchResults
{
	__block uint16_t searchIdentifier = 0;
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:ZGNetworkMessageSendSearchData andObjectID:self->_remoteHandleIdentifier];
		
		NSData *archivedData = [NSKeyedArchiver archivedDataWithRootObject:searchData];
		
		uint64_t dataLength = archivedData.length;
		[self->_appClient sendBytes:&dataLength length:sizeof(dataLength)];
		
		[self->_appClient sendBytes:archivedData.bytes length:dataLength];
		
		[self->_appClient receiveBytes:&searchIdentifier length:sizeof(searchIdentifier)];
		
		bool isNarrowing = narrowing;
		[self->_appClient sendBytes:&isNarrowing length:sizeof(isNarrowing)];
		
		if (isNarrowing)
		{
			NSData *archivedResultsData = [NSKeyedArchiver archivedDataWithRootObject:firstSearchResults.resultSets];
			uint64_t archivedResultsSize = archivedResultsData.length;
			
			[self->_appClient sendBytes:&archivedResultsSize length:sizeof(archivedResultsSize)];
			[self->_appClient sendBytes:archivedResultsData.bytes length:archivedResultsSize];
			
			assert([laterSearchResults isKindOfClass:[ZGRemoteSearchResults class]]);
			uint16_t laterSearchResultsIdentifier = [((ZGRemoteSearchResults *)laterSearchResults) remoteIdentifier];
			
			[self->_appClient sendBytes:&laterSearchResultsIdentifier length:sizeof(laterSearchResultsIdentifier)];
		}
		
		[self->_appClient sendEndMessage];
	});
	return searchIdentifier;
}

- (id <ZGSearchResults>)receiveProgressUpdatesWithDelegate:(id <ZGSearchProgressDelegate>)delegate andSearchResultsFromSearchIdentifier:(uint16_t)searchIdentifier withSearchData:(ZGSearchData *)searchData
{
	__block bool reachedEnd = false;
	__block uint16_t remoteIdentifier = 0;
	while (!reachedEnd)
	{
		dispatch_sync(_appClient.dispatchQueue, ^{
			[self->_appClient sendMessageType:ZGNetworkMessageReceiveSearchProgress andObjectID:searchIdentifier];
			
			uint64_t numberOfBytes = 0;
			[self->_appClient receiveBytes:&numberOfBytes length:sizeof(numberOfBytes)];
			
			if (numberOfBytes > 0)
			{
				void *bytes = malloc(numberOfBytes);
				[self->_appClient receiveBytes:bytes length:numberOfBytes];
				
				NSArray *queue = [NSKeyedUnarchiver unarchiveObjectWithData:[NSData dataWithBytesNoCopy:bytes length:numberOfBytes]];
				
				for (id object in queue)
				{
					if ([object isKindOfClass:[ZGSearchProgress class]])
					{
						dispatch_async(dispatch_get_main_queue(), ^{
							[delegate progressWillBegin:object searchData:searchData];
						});
					}
					else if ([object isKindOfClass:[NSArray class]] && [object count] == 2)
					{
						ZGSearchProgress *searchProgress = [object objectAtIndex:0];
						NSData *resultData = [object objectAtIndex:1];
						
						if ([searchProgress isKindOfClass:[ZGSearchProgress class]] && [resultData isKindOfClass:[NSData class]])
						{
							dispatch_async(dispatch_get_main_queue(), ^{
								[delegate progress:searchProgress advancedWithResultSet:resultData searchData:searchData];
							});
						}
					}
				}
			}
			
			[self->_appClient receiveBytes:&reachedEnd length:sizeof(reachedEnd)];
			
			if (reachedEnd)
			{
				[self->_appClient receiveBytes:&remoteIdentifier length:sizeof(remoteIdentifier)];
			}
			
			[self->_appClient sendEndMessage];
		});
	}
	
	return [[ZGRemoteSearchResults alloc] initWithAppClient:_appClient remoteIdentifier:remoteIdentifier dataSize:searchData.dataSize];
}

- (id <ZGSearchResults>)searchData:(ZGSearchData *)searchData delegate:(id <ZGSearchProgressDelegate>)delegate
{
	uint16_t searchIdentifier = [self sendSearchData:searchData isNarrowing:NO withFirstSearchResults:nil laterSearchResults:nil];
	return [self receiveProgressUpdatesWithDelegate:delegate andSearchResultsFromSearchIdentifier:searchIdentifier withSearchData:searchData];
}

- (id <ZGSearchResults>)narrowSearchData:(ZGSearchData *)searchData withFirstSearchResults:(ZGLocalSearchResults <ZGSearchResults> *)firstSearchResults laterSearchResults:(id <ZGSearchResults>)laterSearchResults delegate:(id <ZGSearchProgressDelegate>)delegate
{
	uint16_t searchIdentifier = [self sendSearchData:searchData isNarrowing:YES withFirstSearchResults:firstSearchResults laterSearchResults:laterSearchResults];
	return [self receiveProgressUpdatesWithDelegate:delegate andSearchResultsFromSearchIdentifier:searchIdentifier withSearchData:searchData];
}

@end
