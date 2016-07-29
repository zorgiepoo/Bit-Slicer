/*
 * Copyright (c) 2012 Mayur Pawashe
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

#import "ZGProcessList.h"
#import "ZGRunningProcess.h"
#import "ZGRunningProcessObserver.h"
#import "ZGVirtualMemory.h"
#import "ZGProcessTaskManager.h"
#import "ZGStaticSelectorChecker.h"
#import <sys/types.h>
#import <sys/sysctl.h>

#define SYSCTL_PROC_CPUTYPE "sysctl.proc_cputype"

@implementation ZGProcessList
{
	ZGProcessTaskManager * _Nonnull _processTaskManager;
	NSMutableArray<ZGRunningProcess *> * _Nonnull _runningProcesses;
	
	NSTimer * _Nullable _pollTimer;
	NSUInteger _pollRequestCount;
	NSMutableArray<ZGRunningProcessObserver *> * _Nullable _priorityProcesses;
	NSMutableArray * _Nullable _pollObservers;
	
	// For SYSCTL_PROC_CPUTYPE MIB storage
	int _processTypeName[CTL_MAXNAME];
	size_t _processTypeNameLength;
}

#pragma mark Setter & Accessors

// http://stackoverflow.com/questions/477204/key-value-observing-a-to-many-relationship-in-cocoa
// KVO with a one-to-many relationship

- (NSArray<ZGRunningProcess *> *)runningProcesses
{
	return [_runningProcesses copy];
}

- (void)setRunningProcesses:(NSArray<ZGRunningProcess *> *)runningProcesses
{
	if (![_runningProcesses isEqualToArray:runningProcesses])
	{
		_runningProcesses = [runningProcesses mutableCopy];
	}
}

#pragma mark KVO Optimizations

// Implementing methods that should optimize our KVO model according to apple's documentation

- (NSUInteger)countOfRunningProcesses
{
	return _runningProcesses.count;
}

- (id)objectInRunningProcessesAtIndex:(NSUInteger)index
{
	return [_runningProcesses objectAtIndex:index];
}

- (NSArray<ZGRunningProcess *> *)runningProcessesAtIndexes:(NSIndexSet *)indexes
{
	return [_runningProcesses objectsAtIndexes:indexes];
}

#pragma mark Birth

- (id)init
{
	self = [super init];
	if (self != nil)
	{
		_runningProcesses = [[NSMutableArray alloc] init];
		[self retrieveProcessTypeInfoForMIB];
		[self retrieveList];
	}
	return self;
}

- (id)initWithProcessTaskManager:(ZGProcessTaskManager *)processTaskManager
{
	self = [self init];
	if (self != nil)
	{
		_processTaskManager = processTaskManager;
	}
	return self;
}

#pragma mark Process Retrieval

- (void)retrieveProcessTypeInfoForMIB
{
	const size_t maxLength = sizeof(_processTypeName) / sizeof(*_processTypeName);
	_processTypeNameLength = maxLength;
	
	int result = sysctlnametomib(SYSCTL_PROC_CPUTYPE, _processTypeName, &_processTypeNameLength);
	assert(result == 0);
	assert(_processTypeNameLength < maxLength);
	
	// last element in the name MIB will be the process ID that the client fills in before calling sysctl()
	_processTypeNameLength++;
}

// Useful reference: https://developer.apple.com/legacy/library/qa/qa2001/qa1123.html
// Could also use proc_listpids() instead, but we may not get enough info back with it compared to kinfo_proc
- (void)retrieveList
{
	int processListName[] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL};
	size_t processListNameLength = sizeof(processListName) / sizeof(*processListName);
	
	// Request the size we'll need to fill the process list buffer
	size_t processListRequestSize = 0;
	if (sysctl(processListName, (u_int)processListNameLength, NULL, &processListRequestSize, NULL, 0) != 0) return;
	struct kinfo_proc *processList = malloc(processListRequestSize);
	if (processList == NULL) return;
	
	// Note that it is realistic for the next call to fail or not have enough memory to write into processList, or
	// it could just return 0 size back. Between requesting the process list size and actually obtaining the list,
	// the process list could change enough such that we won't have enough space to fill in the buffer
	// (e.g, too many processes were spawned in between)
	// We could just always request for a really big buffer, but this might not be a better solution

	// Retrieve the actual process list using the obtained size
	size_t processListActualSize = processListRequestSize;
	if (sysctl(processListName, (u_int)processListNameLength, processList, &processListActualSize, NULL, 0) != 0
		|| (processListActualSize == 0))
	{
		free(processList);
		return;
	}
	
	NSMutableArray<ZGRunningProcess *> *newRunningProcesses = [[NSMutableArray alloc] init];
	
	// Show all processes if we are root
	BOOL isRoot = (geteuid() == 0);
	
	const size_t processCount = processListActualSize / sizeof(*processList);
	for (size_t processIndex = 0; processIndex < processCount; processIndex++)
	{
		struct kinfo_proc processInfo = processList[processIndex];
		
		uid_t uid = processInfo.kp_eproc.e_ucred.cr_uid;
		pid_t processIdentifier = processInfo.kp_proc.p_pid;
		
		// We want user processes, not zombies!
		BOOL isBeingForked = (processInfo.kp_proc.p_stat & SIDL) != 0;
		if (processIdentifier != -1 && (uid == getuid() || isRoot) && !isBeingForked)
		{
			cpu_type_t cpuType = 0;
			size_t cpuTypeSize = sizeof(cpuType);
			
			// Grab CPU architecture type
			_processTypeName[_processTypeNameLength - 1] = processIdentifier;
			if (sysctl(_processTypeName, (u_int)_processTypeNameLength, &cpuType, &cpuTypeSize, NULL, 0) == 0)
			{
				BOOL is64Bit = ((cpuType & CPU_ARCH_ABI64) != 0);
				// Note that the internal name is not really the "true" name of the process since it has a very small max character limit
				const char *internalName = processInfo.kp_proc.p_comm;
				
				ZGRunningProcess *runningProcess = [[ZGRunningProcess alloc] initWithProcessIdentifier:processIdentifier is64Bit:is64Bit internalName:@(internalName)];
				
				[newRunningProcesses addObject:runningProcess];
			}
		}
	}
	
	free(processList);
	
	NSMutableArray<ZGRunningProcess *> *currentProcesses = [self mutableArrayValueForKey:ZG_SELECTOR_STRING(self, runningProcesses)];
	
	if (![currentProcesses isEqualToArray:newRunningProcesses])
	{
		// Remove old processes
		NSMutableArray<ZGRunningProcess *> *processesToRemove = [[NSMutableArray alloc] init];
		
		for (ZGRunningProcess *process in currentProcesses)
		{
			if (![newRunningProcesses containsObject:process])
			{
				[processesToRemove addObject:process];
			}
		}
		
		[currentProcesses removeObjectsInArray:processesToRemove];
		
		// Add new processes
		NSMutableArray<ZGRunningProcess *> *processesToAdd = [[NSMutableArray alloc] init];
		
		for (ZGRunningProcess *process in newRunningProcesses)
		{
			if (![currentProcesses containsObject:process])
			{
				[processesToAdd addObject:process];
			}
		}
		
		[currentProcesses addObjectsFromArray:processesToAdd];
	}
}

#pragma mark Polling

- (void)createPollTimer
{
	_pollTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(poll:) userInfo:nil repeats:YES];
}

- (void)destroyPollTimer
{
	[_pollTimer invalidate];
	_pollTimer = nil;
}

- (void)poll:(NSTimer *)__unused timer
{
	if (_pollRequestCount > 0)
	{
		[self retrieveList];
	}
	else if (_priorityProcesses != nil)
	{
		[self watchPriorityProcesses];
	}
}

- (void)requestPollingWithObserver:(id)observer
{
	if (![_pollObservers containsObject:observer])
	{
		if (_pollObservers == nil)
		{
			_pollObservers = [NSMutableArray array];
		}
		
		[_pollObservers addObject:observer];
		
		if (_pollRequestCount == 0 && _pollTimer == nil)
		{
			[self createPollTimer];
		}
		
		_pollRequestCount++;
	}
}

- (void)unrequestPollingWithObserver:(id)observer
{
	if ([_pollObservers containsObject:observer])
	{
		[_pollObservers removeObject:observer];
		
		_pollRequestCount--;
		
		if (_pollRequestCount == 0 && _priorityProcesses.count == 0)
		{
			[self destroyPollTimer];
		}
	}
}

#pragma mark Watching Specific Processes Termination

- (void)watchPriorityProcesses
{
	BOOL shouldRetrieveList = NO;
	
	for (ZGRunningProcessObserver *runningProcessObserver in _priorityProcesses)
	{
		ZGMemoryMap task = MACH_PORT_NULL;
		pid_t processIdentifier = runningProcessObserver.runningProcess.processIdentifier;
		BOOL foundExistingTask = [_processTaskManager taskExistsForProcessIdentifier:processIdentifier];
		
		BOOL retrievedTask = foundExistingTask && [_processTaskManager getTask:&task forProcessIdentifier:processIdentifier];
		BOOL increasedUserReference = retrievedTask && ZGSetPortSendRightReferenceCountByDelta(task, 1);
		
		if (!increasedUserReference || !MACH_PORT_VALID(task))
		{
			shouldRetrieveList = YES;
			id observer = runningProcessObserver.observer;
			if (observer != nil)
			{
				[self removePriorityToProcessIdentifier:processIdentifier withObserver:observer];
			}
		}
		
		if (increasedUserReference && MACH_PORT_VALID(task))
		{
			ZGSetPortSendRightReferenceCountByDelta(task, -1);
		}
	}
	
	if (shouldRetrieveList)
	{
		[self retrieveList];
	}
}

- (void)addPriorityToProcessIdentifier:(pid_t)processIdentifier withObserver:(id)observer
{
	assert(_processTaskManager != nil);
	
	ZGRunningProcessObserver *runningProcessObserver = [[ZGRunningProcessObserver alloc] initWithProcessIdentifier:processIdentifier observer:observer];
	
	if (![_priorityProcesses containsObject:runningProcessObserver])
	{
		if (_priorityProcesses == nil)
		{
			_priorityProcesses = [NSMutableArray array];
		}
		
		[_priorityProcesses addObject:runningProcessObserver];
		
		if (_pollTimer == nil)
		{
			[self createPollTimer];
		}
	}
}

- (void)removePriorityToProcessIdentifier:(pid_t)processIdentifier withObserver:(id)observer
{
	ZGRunningProcessObserver *runningProcessObserver = [[ZGRunningProcessObserver alloc] initWithProcessIdentifier:processIdentifier observer:observer];
	
	if ([_priorityProcesses containsObject:runningProcessObserver])
	{
		[_priorityProcesses removeObject:runningProcessObserver];
		
		if (_priorityProcesses.count == 0 && _pollRequestCount == 0)
		{
			[self destroyPollTimer];
		}
	}
}

@end
