/*
 * Copyright (c) 2014 Mayur Pawashe
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

#import "ZGProcessTaskManager.h"
#import "ZGVirtualMemory.h"
#import "ZGDebugLogging.h"

@implementation ZGProcessTaskManager
{
	NSMutableDictionary<NSNumber *, NSNumber *> * _Nullable _tasksDictionary;
}

- (BOOL)taskExistsForProcessIdentifier:(pid_t)processIdentifier
{
	return [_tasksDictionary objectForKey:@(processIdentifier)] != nil;
}

- (BOOL)getTask:(ZGMemoryMap *)processTask forProcessIdentifier:(pid_t)processIdentifier
{
	if (_tasksDictionary == nil)
	{
		_tasksDictionary = [NSMutableDictionary dictionary];
	}
	
	NSNumber *taskNumber = [_tasksDictionary objectForKey:@(processIdentifier)];
	if (taskNumber != nil)
	{
		*processTask = [taskNumber unsignedIntValue];
		return YES;
	}
	
	if (!ZGTaskForPID(processIdentifier, processTask) || !MACH_PORT_VALID(*processTask))
	{
		if (*processTask != MACH_PORT_NULL)
		{
			ZGDeallocatePort(*processTask);
		}
		
		ZG_LOG(@"Mach port is not valid for process %d", processIdentifier);
		
		*processTask = MACH_PORT_NULL;
		return NO;
	}
	
	[_tasksDictionary setObject:@(*processTask) forKey:@(processIdentifier)];
	
	return YES;
}

- (void)freeTaskForProcessIdentifier:(pid_t)processIdentifier
{
	NSNumber *taskNumber = [_tasksDictionary objectForKey:@(processIdentifier)];
	if (taskNumber == nil)
	{
		return;
	}
	
	ZGDeallocatePort([taskNumber unsignedIntValue]);
	[_tasksDictionary removeObjectForKey:@(processIdentifier)];
}

@end
