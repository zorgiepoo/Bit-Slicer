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

#import "ZGRemoteProcessTaskManager.h"
#import "ZGAppClient.h"
#import "ZGRemoteProcessList.h"
#import "ZGRemoteProcessHandle.h"

@implementation ZGRemoteProcessTaskManager
{
	ZGAppClient *_appClient;
}

- (id)initWithAppClient:(ZGAppClient *)appClient
{
	self = [super init];
	if (self != nil)
	{
		_appClient = appClient;
	}
	return self;
}

- (ZGProcessList *)createProcessList
{
	return [[ZGRemoteProcessList alloc] initWithProcessTaskManager:self];
}

- (id <ZGProcessHandleProtocol>)createProcessHandleWithProcessTask:(ZGMemoryMap)processTask
{
	return [[ZGRemoteProcessHandle alloc] initWithProcessTask:processTask appClient:_appClient];
}

- (BOOL)taskExistsForProcessIdentifier:(pid_t)processIdentifier
{
	__block bool result = false;
	
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:ZGNetworkMessageTaskExistsForProcessIndentifier];
		[self->_appClient sendBytes:&processIdentifier length:sizeof(processIdentifier)];
		
		[self->_appClient receiveBytes:&result length:sizeof(bool)];
	});
	
	return result;
}

- (BOOL)getTask:(ZGMemoryMap *)processTask forProcessIdentifier:(pid_t)processIdentifier
{
	__block uint32_t *results = calloc(2, sizeof(*results));
	__block ZGMemoryMap task = 0;
	
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:ZGNetworkMessageGetTaskForProcessIdentifier];
		[self->_appClient sendBytes:&processIdentifier length:sizeof(processIdentifier)];
		
		[self->_appClient receiveBytes:results length:sizeof(results)];
		
		task = results[0];
	});
	
	BOOL success = (bool)results[1];
	*processTask = task;
	
	free(results);
	
	return success;
}

- (void)freeTaskForProcessIdentifier:(pid_t)processIdentifier
{
	dispatch_async(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:ZGNetworkMessageFreeTaskForProcessIdentifier];
		[self->_appClient sendBytes:&processIdentifier length:sizeof(processIdentifier)];
	});
}

- (BOOL)setPortSendRightReferenceCountByDelta:(mach_port_delta_t)delta task:(ZGMemoryMap)processTask
{
	__block bool success = false;
	dispatch_sync(_appClient.dispatchQueue, ^{
		[self->_appClient sendMessageType:ZGNetworkMessageSetPortRightReferenceCountByDelta];
		
		int32_t deltaSent = delta;
		[self->_appClient sendBytes:&deltaSent length:sizeof(deltaSent)];
		
		uint32_t taskSent = processTask;
		[self->_appClient sendBytes:&taskSent length:sizeof(taskSent)];
		
		[self->_appClient receiveBytes:&success length:sizeof(success)];
	});
	return success;
}

@end
