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

#import "ZGAppServer.h"
#import "ZGProcessTaskManager.h"
#import "ZGNetworkCommon.h"
#import "ZGProcessList.h"
#import "ZGLocalProcessHandle.h"
#import "ZGRegion.h"

#define BACKLOG 10

@implementation ZGAppServer
{
	id <ZGProcessTaskManager> _taskManager;
}

- (id)initWithProcessTaskManager:(id <ZGProcessTaskManager>)taskManager
{
	self = [super init];
	if (self != nil)
	{
		_taskManager = taskManager;
	}
	return self;
}

- (void)start
{
	struct addrinfo hints;
	memset(&hints, 0, sizeof(hints));
	hints.ai_family = AF_UNSPEC;
	hints.ai_socktype = SOCK_STREAM;
	hints.ai_flags = AI_PASSIVE;
	
	struct addrinfo *serverInfoResults = NULL;
	int addressInfoError = getaddrinfo(NULL, NETWORK_PORT, &hints, &serverInfoResults);
	if (addressInfoError != 0)
	{
		NSLog(@"getaddrinfo error: %s", gai_strerror(addressInfoError));
		return;
	}
	
	struct addrinfo *addressInfo;
	int listeningSocket = 0;
	for (addressInfo = serverInfoResults; addressInfo != NULL; addressInfo = addressInfo->ai_next)
	{
		listeningSocket = socket(addressInfo->ai_family, addressInfo->ai_socktype, addressInfo->ai_protocol);
		if (listeningSocket == -1)
		{
			perror("setsockopt");
			continue;
		}
		
		int yes = 1;
		if (setsockopt(listeningSocket, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(int)) == -1)
		{
			perror("setsockopt");
			close(listeningSocket);
			return;
		}
		
		if (bind(listeningSocket, addressInfo->ai_addr, addressInfo->ai_addrlen) == -1)
		{
			close(listeningSocket);
			perror("bind");
			continue;
		}
		
		break;
	}
	
	if (addressInfo == NULL)
	{
		NSLog(@"Failed to find addressInfo to bind to");
		return;
	}
	
	freeaddrinfo(serverInfoResults);
	
	if (listen(listeningSocket, BACKLOG) == -1)
	{
		perror("listen");
		return;
	}
	
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		while (1)
		{
			struct sockaddr_storage clientAddress;
			socklen_t sinSize = sizeof(clientAddress);
			int clientSocket = accept(listeningSocket, (struct sockaddr *)&clientAddress, &sinSize);
			if (clientSocket == -1)
			{
				perror("accept");
				continue;
			}
			
			NSLog(@"Accepted socket");
			
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				uint16_t nextAvailableObjectID = 0;
				NSMutableDictionary *objectDictionary = [NSMutableDictionary dictionary];
				NSMutableDictionary *retreivedListOnceDictionary = [NSMutableDictionary dictionary];
				while (1)
				{
					ZGNetworkMessageType messageType;
					if (![self receiveFromSocket:clientSocket bytes:&messageType length:sizeof(messageType)])
					{
						break;
					}
					
					if (messageType == ZGNetworkMessageTaskExistsForProcessIndentifier)
					{
						int32_t processIdentifier;
						if (![self receiveFromSocket:clientSocket bytes:&processIdentifier length:sizeof(processIdentifier)])
						{
							break;
						}
						
						__block bool result = false;
						dispatch_sync(dispatch_get_main_queue(), ^{
							result = [self->_taskManager taskExistsForProcessIdentifier:processIdentifier];
						});
						
						if (![self sendToSocket:clientSocket bytes:&result length:sizeof(result)])
						{
							break;
						}
					}
					else if (messageType == ZGNetworkMessageGetTaskForProcessIdentifier)
					{
						int32_t processIdentifier = 0;
						if (![self receiveFromSocket:clientSocket bytes:&processIdentifier length:sizeof(processIdentifier)])
						{
							break;
						}
						
						__block uint32_t processTask = 0;
						__block bool result = false;
						
						dispatch_sync(dispatch_get_main_queue(), ^{
							result = [self->_taskManager getTask:&processTask forProcessIdentifier:processIdentifier];
						});
						
						uint32_t outputBuffer[2] = {processTask, result};
						if (![self sendToSocket:clientSocket bytes:outputBuffer length:sizeof(outputBuffer)])
						{
							break;
						}
					}
					else if (messageType == ZGNetworkMessageFreeTaskForProcessIdentifier)
					{
						int32_t processIdentifier = 0;
						if (![self receiveFromSocket:clientSocket bytes:&processIdentifier length:sizeof(processIdentifier)])
						{
							break;
						}
						
						dispatch_async(dispatch_get_main_queue(), ^{
							[self->_taskManager freeTaskForProcessIdentifier:processIdentifier];
						});
					}
					else if (messageType == ZGNetworkMessageSetPortRightReferenceCountByDelta)
					{
						int32_t delta = 0;
						if (![self receiveFromSocket:clientSocket bytes:&delta length:sizeof(delta)])
						{
							break;
						}
						
						uint32_t processTask = 0;
						if (![self receiveFromSocket:clientSocket bytes:&processTask length:sizeof(processTask)])
						{
							break;
						}
						
						__block bool result = false;
						dispatch_sync(dispatch_get_main_queue(), ^{
							result = [self->_taskManager setPortSendRightReferenceCountByDelta:delta task:processTask];
						});
						
						if (![self sendToSocket:clientSocket bytes:&result length:sizeof(result)])
						{
							break;
						}
					}
					else if (messageType == ZGNetworkMessageCreateProcessList)
					{
						ZGProcessList *processList = [self->_taskManager createProcessList];
						objectDictionary[@(nextAvailableObjectID)] = processList;
						
						if (![self sendToSocket:clientSocket bytes:&nextAvailableObjectID length:sizeof(nextAvailableObjectID)])
						{
							break;
						}
						
						nextAvailableObjectID++;
					}
					else if (messageType == ZGNetworkMessageRetreiveProcessList)
					{
						uint16_t processListIdentifier = 0;
						if (![self receiveFromSocket:clientSocket bytes:&processListIdentifier length:sizeof(processListIdentifier)])
						{
							break;
						}
						
						ZGProcessList *processList = objectDictionary[@(processListIdentifier)];
						
						BOOL sentData = NO;
						
						if (![processList isKindOfClass:[ZGProcessList class]])
						{
							break;
						}
						
						__block NSArray *oldProcessesList = nil;
						__block NSArray *newProcessesList = nil;
						dispatch_sync(dispatch_get_main_queue(), ^{
							oldProcessesList = processList.runningProcesses;
							
							[processList retrieveList];
							
							newProcessesList = processList.runningProcesses;
						});
						
						if ([retreivedListOnceDictionary objectForKey:@(processListIdentifier)] == nil || ![oldProcessesList isEqualToArray:newProcessesList])
						{
							NSData *archivedData = [NSKeyedArchiver archivedDataWithRootObject:newProcessesList];
							uint64_t numberOfBytesToSend = [archivedData length];
							
							if (![self sendToSocket:clientSocket bytes:&numberOfBytesToSend length:sizeof(numberOfBytesToSend)])
							{
								break;
							}
							
							if (![self sendToSocket:clientSocket bytes:archivedData.bytes length:numberOfBytesToSend])
							{
								break;
							}
							
							[retreivedListOnceDictionary setObject:@(YES) forKey:@(processListIdentifier)];
							sentData = YES;
						}
						
						if (!sentData)
						{
							uint64_t zeroBytes = 0;
							if (![self sendToSocket:clientSocket bytes:&zeroBytes length:sizeof(zeroBytes)])
							{
								break;
							}
						}
					}
					else if (messageType == ZGNetworkMessageCreateProcessHandle)
					{
						uint32_t processTask = 0;
						if (![self receiveFromSocket:clientSocket bytes:&processTask length:sizeof(processTask)])
						{
							break;
						}
						
						ZGLocalProcessHandle *processHandle = [[ZGLocalProcessHandle alloc] initWithProcessTask:processTask];
						objectDictionary[@(nextAvailableObjectID)] = processHandle;
						
						if (![self sendToSocket:clientSocket bytes:&nextAvailableObjectID length:sizeof(nextAvailableObjectID)])
						{
							break;
						}
						
						nextAvailableObjectID++;
					}
					else if (messageType == ZGNetworkMessageAllocateMemory)
					{
						ZGLocalProcessHandle *processHandle = [self receiveFromSocket:clientSocket objectDictionary:objectDictionary expectedClass:[ZGLocalProcessHandle class]];
						if (processHandle == nil)
						{
							break;
						}
						
						uint64_t size = 0;
						if (![self receiveFromSocket:clientSocket bytes:&size length:sizeof(size)])
						{
							break;
						}
						
						uint64_t address = 0x0;
						bool success = [processHandle allocateMemoryAndGetAddress:&address size:size];
						
						uint64_t results[2] = {address, success};
						if (![self sendToSocket:clientSocket bytes:results length:sizeof(results)])
						{
							break;
						}
					}
					else if (messageType == ZGNetworkMessageDeallocateMemory)
					{
						ZGLocalProcessHandle *processHandle = [self receiveFromSocket:clientSocket objectDictionary:objectDictionary expectedClass:[ZGLocalProcessHandle class]];
						if (processHandle == nil)
						{
							break;
						}
						
						uint64_t results[2] = {};
						if (![self receiveFromSocket:clientSocket bytes:results length:sizeof(results)])
						{
							break;
						}
						
						[processHandle deallocateMemoryAtAddress:results[0] size:results[1]];
					}
					else if (messageType == ZGNetworkMessageReadBytes)
					{
						ZGLocalProcessHandle *processHandle = [self receiveFromSocket:clientSocket objectDictionary:objectDictionary expectedClass:[ZGLocalProcessHandle class]];
						if (processHandle == nil)
						{
							break;
						}
						
						uint64_t arguments[2] = {};
						if (![self receiveFromSocket:clientSocket bytes:arguments length:sizeof(arguments)])
						{
							break;
						}
						
						void *bytes = NULL;
						uint64_t sizeRead = arguments[1];
						bool success = [processHandle readBytes:&bytes address:arguments[0] size:&sizeRead];
						
						if (![self sendToSocket:clientSocket bytes:&success length:sizeof(success)])
						{
							break;
						}
						
						if (success)
						{
							if (![self sendToSocket:clientSocket bytes:&sizeRead length:sizeof(sizeRead)])
							{
								break;
							}
							
							if (sizeRead > 0)
							{
								if (![self sendToSocket:clientSocket bytes:bytes length:sizeRead])
								{
									break;
								}
							}
							
							[processHandle freeBytes:bytes size:sizeRead];
						}
					}
					else if (messageType == ZGNetworkMessageWriteBytes || messageType == ZGNetworkMessageWriteBytesOverwritingProtection || messageType == ZGNetworkMessageWriteBytesIgnoringProtection)
					{
						ZGLocalProcessHandle *processHandle = [self receiveFromSocket:clientSocket objectDictionary:objectDictionary expectedClass:[ZGLocalProcessHandle class]];
						if (processHandle == nil)
						{
							break;
						}
						
						uint64_t initialData[2] = {};
						if (![self receiveFromSocket:clientSocket bytes:initialData length:sizeof(initialData)])
						{
							break;
						}
						
						uint64_t address = initialData[0];
						uint64_t size = initialData[1];
						
						void *writeBytes = malloc(size);
						
						if (![self receiveFromSocket:clientSocket bytes:writeBytes length:size])
						{
							free(writeBytes);
							break;
						}
						
						bool success = false;
						if (messageType == ZGNetworkMessageWriteBytes)
						{
							success = [processHandle writeBytes:writeBytes address:address size:size];
						}
						else if (messageType == ZGNetworkMessageWriteBytesOverwritingProtection)
						{
							success = [processHandle writeBytesOverwritingProtection:writeBytes address:address size:size];
						}
						else if (messageType == ZGNetworkMessageWriteBytesIgnoringProtection)
						{
							success = [processHandle writeBytesIgnoringProtection:writeBytes address:address size:size];
						}
						
						free(writeBytes);
						
						if (![self sendToSocket:clientSocket bytes:&success length:sizeof(success)])
						{
							break;
						}
					}
					else if (messageType == ZGNetworkMessageGetDlydTaskInfo)
					{
						ZGLocalProcessHandle *processHandle = [self receiveFromSocket:clientSocket objectDictionary:objectDictionary expectedClass:[ZGLocalProcessHandle class]];
						if (processHandle == nil)
						{
							break;
						}
						
						struct task_dyld_info dyldTaskInfo = {};
						uint32_t count = 0;
						bool success = [processHandle getDyldTaskInfo:&dyldTaskInfo count:&count];
						
						if (![self sendToSocket:clientSocket bytes:&success length:sizeof(success)])
						{
							break;
						}
						
						if (![self sendToSocket:clientSocket bytes:&count length:sizeof(count)])
						{
							break;
						}
						
						if (success)
						{
							if (![self sendToSocket:clientSocket bytes:&dyldTaskInfo length:sizeof(dyldTaskInfo)])
							{
								break;
							}
						}
					}
					else if (messageType == ZGNetworkMessageSetProtection)
					{
						ZGLocalProcessHandle *processHandle = [self receiveFromSocket:clientSocket objectDictionary:objectDictionary expectedClass:[ZGLocalProcessHandle class]];
						if (processHandle == nil)
						{
							break;
						}
						
						int32_t protection = 0;
						if (![self receiveFromSocket:clientSocket bytes:&protection length:sizeof(protection)])
						{
							break;
						}
						
						uint64_t addressAndSize[2] = {};
						if (![self receiveFromSocket:clientSocket bytes:addressAndSize length:sizeof(addressAndSize)])
						{
							break;
						}
						
						bool success = [processHandle setProtection:protection address:addressAndSize[0] size:addressAndSize[1]];
						
						if (![self sendToSocket:clientSocket bytes:&success length:sizeof(success)])
						{
							break;
						}
					}
					else if (messageType == ZGNetworkMessageGetPageSize)
					{
						ZGLocalProcessHandle *processHandle = [self receiveFromSocket:clientSocket objectDictionary:objectDictionary expectedClass:[ZGLocalProcessHandle class]];
						if (processHandle == nil)
						{
							break;
						}
						
						uint64_t pageSize = 0;
						bool success = [processHandle getPageSize:&pageSize];
						
						if (![self sendToSocket:clientSocket bytes:&success length:sizeof(success)])
						{
							break;
						}
						
						if (success)
						{
							if (![self sendToSocket:clientSocket bytes:&pageSize length:sizeof(pageSize)])
							{
								break;
							}
						}
					}
					else if (messageType == ZGNetworkMessageSuspend || messageType == ZGNetworkMessageResume)
					{
						ZGLocalProcessHandle *processHandle = [self receiveFromSocket:clientSocket objectDictionary:objectDictionary expectedClass:[ZGLocalProcessHandle class]];
						if (processHandle == nil)
						{
							break;
						}
						
						bool success = (messageType == ZGNetworkMessageSuspend) ? [processHandle suspend] : [processHandle resume];
						if (![self sendToSocket:clientSocket bytes:&success length:sizeof(success)])
						{
							break;
						}
					}
					else if (messageType == ZGNetworkMessageGetSuspendCount)
					{
						ZGLocalProcessHandle *processHandle = [self receiveFromSocket:clientSocket objectDictionary:objectDictionary expectedClass:[ZGLocalProcessHandle class]];
						if (processHandle == nil)
						{
							break;
						}
						
						int32_t suspendCount = 0;
						bool success = [processHandle getSuspendCount:&suspendCount];
						
						if (![self sendToSocket:clientSocket bytes:&success length:sizeof(success)])
						{
							break;
						}
						
						if (success)
						{
							if (![self sendToSocket:clientSocket bytes:&suspendCount length:sizeof(suspendCount)])
							{
								break;
							}
						}
					}
					else if (messageType == ZGNetworkMessageRegions || messageType == ZGNetworkMessageSubmapRegions)
					{
						ZGLocalProcessHandle *processHandle = [self receiveFromSocket:clientSocket objectDictionary:objectDictionary expectedClass:[ZGLocalProcessHandle class]];
						if (processHandle == nil)
						{
							break;
						}
						
						NSArray *regions = (messageType == ZGNetworkMessageRegions) ? [processHandle regions] : [processHandle submapRegions];
						
						NSData *archivedData = [NSKeyedArchiver archivedDataWithRootObject:regions];
						
						uint64_t numberOfBytesToSend = archivedData.length;
						
						if (![self sendToSocket:clientSocket bytes:&numberOfBytesToSend length:sizeof(numberOfBytesToSend)])
						{
							break;
						}
						
						if (![self sendToSocket:clientSocket bytes:archivedData.bytes length:numberOfBytesToSend])
						{
							break;
						}
					}
					else if (messageType == ZGNetworkMessageSubmapRegionsInRegion)
					{
						ZGLocalProcessHandle *processHandle = [self receiveFromSocket:clientSocket objectDictionary:objectDictionary expectedClass:[ZGLocalProcessHandle class]];
						if (processHandle == nil)
						{
							break;
						}
						
						uint64_t numberOfBytesToReceive = 0;
						if (![self receiveFromSocket:clientSocket bytes:&numberOfBytesToReceive length:sizeof(numberOfBytesToReceive)])
						{
							break;
						}
						
						void *buffer = malloc(numberOfBytesToReceive);
						if (![self receiveFromSocket:clientSocket bytes:buffer length:numberOfBytesToReceive])
						{
							free(buffer);
							break;
						}
						
						ZGRegion *region = [NSKeyedUnarchiver unarchiveObjectWithData:[NSData dataWithBytesNoCopy:buffer length:numberOfBytesToReceive]];
						
						if (![region isKindOfClass:[ZGRegion class]])
						{
							break;
						}
						
						NSArray *submapRegions = [processHandle submapRegionsInRegion:region];
						NSData *archivedData = [NSKeyedArchiver archivedDataWithRootObject:submapRegions];
						uint64_t numberOfBytesToSend = archivedData.length;
						
						if (![self sendToSocket:clientSocket bytes:&numberOfBytesToSend length:sizeof(numberOfBytesToSend)])
						{
							break;
						}
						
						if (![self sendToSocket:clientSocket bytes:archivedData.bytes length:numberOfBytesToSend])
						{
							break;
						}
					}
					else if (messageType == ZGNetworkMessageGetRegionInfo)
					{
						ZGLocalProcessHandle *processHandle = [self receiveFromSocket:clientSocket objectDictionary:objectDictionary expectedClass:[ZGLocalProcessHandle class]];
						if (processHandle == nil)
						{
							break;
						}
						
						uint64_t addressAndSize[2] = {};
						if (![self receiveFromSocket:clientSocket bytes:addressAndSize length:sizeof(addressAndSize)])
						{
							break;
						}
						
						ZGMemoryBasicInfo basicInfo = {};
						bool success = [processHandle getRegionInfo:&basicInfo address:&addressAndSize[0] size:&addressAndSize[1]];
						
						if (![self sendToSocket:clientSocket bytes:&success length:sizeof(success)])
						{
							break;
						}
						
						if (success)
						{
							if (![self sendToSocket:clientSocket bytes:addressAndSize length:sizeof(addressAndSize)])
							{
								break;
							}
							
							if (![self sendToSocket:clientSocket bytes:&basicInfo length:sizeof(basicInfo)])
							{
								break;
							}
						}
					}
					else if (messageType == ZGNetworkMessageGetMemoryProtection)
					{
						ZGLocalProcessHandle *processHandle = [self receiveFromSocket:clientSocket objectDictionary:objectDictionary expectedClass:[ZGLocalProcessHandle class]];
						if (processHandle == nil)
						{
							break;
						}
						
						uint64_t addressAndSize[2] = {};
						if (![self receiveFromSocket:clientSocket bytes:addressAndSize length:sizeof(addressAndSize)])
						{
							break;
						}
						
						int32_t protection = 0;
						bool success = [processHandle getMemoryProtection:&protection address:&addressAndSize[0] size:&addressAndSize[1]];
						
						if (![self sendToSocket:clientSocket bytes:&success length:sizeof(success)])
						{
							break;
						}
						
						if (success)
						{
							if (![self sendToSocket:clientSocket bytes:addressAndSize length:sizeof(addressAndSize)])
							{
								break;
							}
							
							if (![self sendToSocket:clientSocket bytes:&protection length:sizeof(protection)])
							{
								break;
							}
						}
					}
					else if (messageType == ZGNetworkMessageSymbolAtAddress)
					{
						ZGLocalProcessHandle *processHandle = [self receiveFromSocket:clientSocket objectDictionary:objectDictionary expectedClass:[ZGLocalProcessHandle class]];
						if (processHandle == nil)
						{
							break;
						}
						
						uint64_t address = 0;
						if (![self receiveFromSocket:clientSocket bytes:&address length:sizeof(address)])
						{
							break;
						}
						
						bool wantsRelativeOffset = false;
						if (![self receiveFromSocket:clientSocket bytes:&wantsRelativeOffset length:sizeof(wantsRelativeOffset)])
						{
							break;
						}
						
						uint64_t relativeOffset = 0;
						NSString *symbol = [processHandle symbolAtAddress:address relativeOffset:wantsRelativeOffset ? &relativeOffset : NULL];
						
						const void *cString = [symbol UTF8String];
						
						bool success = (symbol != nil && cString != NULL);
						if (![self sendToSocket:clientSocket bytes:&success length:sizeof(success)])
						{
							break;
						}
						
						if (success)
						{
							uint64_t numberOfBytesToSend = strlen(cString);
							if (![self sendToSocket:clientSocket bytes:&numberOfBytesToSend length:sizeof(numberOfBytesToSend)])
							{
								break;
							}
							
							if (![self sendToSocket:clientSocket bytes:cString length:numberOfBytesToSend])
							{
								break;
							}
							
							if (wantsRelativeOffset)
							{
								if (![self sendToSocket:clientSocket bytes:&relativeOffset length:sizeof(relativeOffset)])
								{
									break;
								}
							}
						}
					}
					else if (messageType == ZGNetworkMessageFindSymbol)
					{
						ZGLocalProcessHandle *processHandle = [self receiveFromSocket:clientSocket objectDictionary:objectDictionary expectedClass:[ZGLocalProcessHandle class]];
						if (processHandle == nil)
						{
							break;
						}
						
						uint64_t symbolNameStringLength = 0;
						if (![self receiveFromSocket:clientSocket bytes:&symbolNameStringLength length:sizeof(symbolNameStringLength)])
						{
							break;
						}
						
						void *symbolNameCString = malloc(symbolNameStringLength);
						if (![self receiveFromSocket:clientSocket bytes:symbolNameCString length:symbolNameStringLength])
						{
							free(symbolNameCString);
							break;
						}
						
						NSString *symbolName = [[NSString alloc] initWithBytesNoCopy:symbolNameCString length:symbolNameStringLength encoding:NSUTF8StringEncoding freeWhenDone:YES];
						
						bool hasPartialSymbolOwnerName = false;
						if (![self receiveFromSocket:clientSocket bytes:&hasPartialSymbolOwnerName length:sizeof(hasPartialSymbolOwnerName)])
						{
							break;
						}
						
						NSString *partialSymbolOwnerName = nil;
						if (hasPartialSymbolOwnerName)
						{
							uint64_t partialSymbolOwnerNameStringLength = 0;
							if (![self receiveFromSocket:clientSocket bytes:&partialSymbolOwnerNameStringLength length:sizeof(partialSymbolOwnerNameStringLength)])
							{
								break;
							}
							
							void *partialSymbolOwnerNameCString = malloc(partialSymbolOwnerNameStringLength);
							if (![self receiveFromSocket:clientSocket bytes:partialSymbolOwnerNameCString length:partialSymbolOwnerNameStringLength])
							{
								free(partialSymbolOwnerNameCString);
								break;
							}
							
							partialSymbolOwnerName = [[NSString alloc] initWithBytesNoCopy:partialSymbolOwnerNameCString length:partialSymbolOwnerNameStringLength encoding:NSUTF8StringEncoding freeWhenDone:YES];
						}
						
						bool requiresExactMatch = false;
						if (![self receiveFromSocket:clientSocket bytes:&requiresExactMatch length:sizeof(requiresExactMatch)])
						{
							break;
						}
						
						uint64_t pastAddress = 0;
						if (![self receiveFromSocket:clientSocket bytes:&pastAddress length:sizeof(pastAddress)])
						{
							break;
						}
						
						NSNumber *result = [processHandle findSymbol:symbolName withPartialSymbolOwnerName:partialSymbolOwnerName requiringExactMatch:requiresExactMatch pastAddress:pastAddress];
						
						bool success = (result != nil);
						if (![self sendToSocket:clientSocket bytes:&success length:sizeof(success)])
						{
							break;
						}
						
						if (success)
						{
							uint64_t address = [result unsignedLongLongValue];
							if (![self sendToSocket:clientSocket bytes:&address length:sizeof(address)])
							{
								break;
							}
						}
					}
					else if (messageType == ZGNetworkMessageReadStringSizeFromAddress)
					{
						ZGLocalProcessHandle *processHandle = [self receiveFromSocket:clientSocket objectDictionary:objectDictionary expectedClass:[ZGLocalProcessHandle class]];
						if (processHandle == nil)
						{
							break;
						}
						
						uint64_t address = 0;
						if (![self receiveFromSocket:clientSocket bytes:&address length:sizeof(address)])
						{
							break;
						}
						
						uint16_t dataType = 0;
						if (![self receiveFromSocket:clientSocket bytes:&dataType length:sizeof(dataType)])
						{
							break;
						}
						
						uint64_t oldSize = 0;
						if (![self receiveFromSocket:clientSocket bytes:&oldSize length:sizeof(oldSize)])
						{
							break;
						}
						
						uint64_t maxStringSizeLimit = 0;
						if (![self receiveFromSocket:clientSocket bytes:&maxStringSizeLimit length:sizeof(maxStringSizeLimit)])
						{
							break;
						}
						
						uint64_t result = [processHandle readStringSizeFromAddress:address dataType:dataType oldSize:oldSize maxSize:maxStringSizeLimit];
						
						if (![self sendToSocket:clientSocket bytes:&result length:sizeof(result)])
						{
							break;
						}
					}
				}
				
				close(clientSocket);
				NSLog(@"Closing client socket..");
			});
		}
	});
}

- (BOOL)sendToSocket:(int)socket bytes:(const void *)bytes length:(size_t)length
{
	BOOL success = (send(socket, bytes, length, 0) > 0);
	if (!success)
	{
		NSLog(@"server: send failed..");
	}
	return success;
}

- (BOOL)receiveFromSocket:(int)socket bytes:(void *)bytes length:(size_t)length
{
	BOOL success = (recv(socket, bytes, length, 0) > 0);
	if (!success)
	{
		NSLog(@"server: recv failed..");
	}
	return success;
}

- (id)receiveFromSocket:(int)socket objectDictionary:(NSDictionary *)objectDictionary expectedClass:(Class)klass
{
	uint16_t objectID = 0;
	if (![self receiveFromSocket:socket bytes:&objectID length:sizeof(objectID)])
	{
		return nil;
	}
	
	id object = objectDictionary[@(objectID)];
	if (![object isKindOfClass:klass])
	{
		return nil;
	}
	
	return object;
}

@end
