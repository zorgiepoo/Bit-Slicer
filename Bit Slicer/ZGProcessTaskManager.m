/*
 * Created by Mayur Pawashe on 2/2/14.
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

#import "ZGProcessTaskManager.h"
#import "ZGVirtualMemory.h"
#import "ZGUtilities.h"

@interface ZGProcessTaskManager ()

@property (nonatomic) NSMutableDictionary *tasksDictionary;

@end

@implementation ZGProcessTaskManager

- (BOOL)taskExistsForProcessIdentifier:(pid_t)processIdentifier
{
	return [self.tasksDictionary objectForKey:@(processIdentifier)] != nil;
}

- (BOOL)getTask:(ZGMemoryMap *)processTask forProcessIdentifier:(pid_t)processIdentifier
{
	if (self.tasksDictionary == nil)
	{
		self.tasksDictionary = [NSMutableDictionary dictionary];
	}
	
	NSNumber *taskNumber = [self.tasksDictionary objectForKey:@(processIdentifier)];
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
	
	[self.tasksDictionary setObject:@(*processTask) forKey:@(processIdentifier)];
	
	return YES;
}

- (void)freeTaskForProcessIdentifier:(pid_t)processIdentifier
{
	NSNumber *taskNumber = [self.tasksDictionary objectForKey:@(processIdentifier)];
	if (taskNumber == nil)
	{
		return;
	}
	
	ZGDeallocatePort([taskNumber unsignedIntValue]);
	[self.tasksDictionary removeObjectForKey:@(processIdentifier)];
}

@end
