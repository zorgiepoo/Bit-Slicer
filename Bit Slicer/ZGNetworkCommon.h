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

#import <Foundation/Foundation.h>

#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <sys/wait.h>
#include <signal.h>

#define NETWORK_PORT "58393"

typedef  NS_ENUM(uint16_t, ZGNetworkMessageType)
{
	ZGNetworkMessageTaskExistsForProcessIndentifier,
	ZGNetworkMessageGetTaskForProcessIdentifier,
	ZGNetworkMessageFreeTaskForProcessIdentifier,
	ZGNetworkMessageIsProcessAlive,
	ZGNetworkMessageCreateProcessList,
	ZGNetworkMessageRetreiveProcessList,
	ZGNetworkMessageCreateProcessHandle,
	ZGNetworkMessageDeallocProcessHandle,
	ZGNetworkMessageAllocateMemory,
	ZGNetworkMessageDeallocateMemory,
	ZGNetworkMessageReadBytes,
	ZGNetworkMessageWriteBytes,
	ZGNetworkMessageWriteBytesOverwritingProtection,
	ZGNetworkMessageWriteBytesIgnoringProtection,
	ZGNetworkMessageGetDlydTaskInfo,
	ZGNetworkMessageSetProtection,
	ZGNetworkMessageGetPageSize,
	ZGNetworkMessageSuspend,
	ZGNetworkMessageResume,
	ZGNetworkMessageGetSuspendCount,
	ZGNetworkMessageRegions,
	ZGNetworkMessageSubmapRegions,
	ZGNetworkMessageSubmapRegionsInRegion,
	ZGNetworkMessageGetRegionInfo,
	ZGNetworkMessageGetRegionSubmapInfo,
	ZGNetworkMessageGetMemoryProtection,
	ZGNetworkMessageUserTagDescription,
	ZGNetworkMessageSymbolAtAddress,
	ZGNetworkMessageFindSymbol,
	ZGNetworkMessageReadStringSizeFromAddress,
	ZGNetworkMessageSendSearchData,
	ZGNetworkMessageReceiveSearchProgress,
	ZGNetworkMessageSearchResultsRemoveNumberOfAddresses,
	ZGNetworkMessageSearchResultsEnumerateWithCount,
	ZGNetworkMessageSearchResultsAddressCount,
	ZGNetworkMessageSearchResultsPointerSize,
	ZGNetworkMessageSearchResultsDealloc,
	ZGNetworkMessageEndProcedure = 0xFFFF
};

bool ZGNetworkWriteData(int socket, const void *data, size_t length);
bool ZGNetworkReadData(int socket, void *data, size_t length);
