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

#import "ZGRemoteProcessList.h"
#import "ZGAppClient.h"
#import "ZGRemoteProcessTaskManager.h"
#import "ZGRunningProcess.h"

@interface ZGProcessList ()

- (void)updateRunningProcessList:(NSArray *)newRunningProcesses;

@end

@implementation ZGRemoteProcessList
{
	ZGAppClient *_appClient;
	uint16_t _processListIdentifier;
}

- (id)initWithProcessTaskManager:(id <ZGProcessTaskManager>)processTaskManager
{
	_appClient = [(ZGRemoteProcessTaskManager *)processTaskManager appClient];
	
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:ZGNetworkMessageCreateProcessList];
		[self->_appClient receiveBytes:&self->_processListIdentifier length:sizeof(self->_processListIdentifier)];
		[self->_appClient sendEndMessage];
	});
	
	return [super initWithProcessTaskManager:processTaskManager];
}

- (void)retrieveList
{
	__block NSArray *updatedRunningProcesses = nil;
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:ZGNetworkMessageRetreiveProcessList andObjectID:self->_processListIdentifier];
		
		uint64_t numberOfBytesToReceive = 0;
		[self->_appClient receiveBytes:&numberOfBytesToReceive length:sizeof(numberOfBytesToReceive)];
		
		if (numberOfBytesToReceive > 0)
		{
			void *bytes = malloc(numberOfBytesToReceive);
			
			[self->_appClient receiveBytes:bytes length:numberOfBytesToReceive];
			
			updatedRunningProcesses = [NSKeyedUnarchiver unarchiveObjectWithData:[NSData dataWithBytesNoCopy:bytes length:numberOfBytesToReceive]];
		}
		
		[self->_appClient sendEndMessage];
	});
	
	if (updatedRunningProcesses != nil)
	{
		assert([updatedRunningProcesses isKindOfClass:[NSArray class]]);
		for (ZGRunningProcess *runningProcess in updatedRunningProcesses)
		{
			assert([runningProcess isKindOfClass:[ZGRunningProcess class]]);
		}
		
		[self updateRunningProcessList:updatedRunningProcesses];
	}
}

@end
