/*
 * Created by Mayur Pawashe on 12/31/12.
 *
 * Copyright (c) 2012 zgcoder
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

@interface ZGProcessList ()
{
	NSMutableArray *_runningProcesses;
}

@property (atomic) NSUInteger pollRequestCount;
@property (nonatomic) NSArray *pollObservers;
@property (nonatomic) NSTimer *pollTimer;

@end

@implementation ZGProcessList

#pragma mark Setter & Accessors

// http://stackoverflow.com/questions/477204/key-value-observing-a-to-many-relationship-in-cocoa
// KVO with a one-to-many relationship

- (NSArray *)runningProcesses
{
	return [_runningProcesses copy];
}

- (void)setRunningProcesses:(NSArray *)runningProcesses
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

- (NSArray *)runningProcessesAtIndexes:(NSIndexSet *)indexes
{
	return [_runningProcesses objectsAtIndexes:indexes];
}

#pragma mark Birth

- (id)initWithProcessTaskManager:(id <ZGProcessTaskManager>)processTaskManager
{
	self = [super init];
	if (self != nil)
	{
		_processTaskManager = processTaskManager;
		_runningProcesses = [[NSMutableArray alloc] init];
		[self retrieveList];
	}
	return self;
}

#pragma mark Process Retrieval

- (void)retrieveList
{
	NSLog(@"Error: retrieveList not implemented!");
}

- (void)updateRunningProcessList:(NSArray *)newRunningProcesses
{
	NSMutableArray *currentProcesses = [self mutableArrayValueForKey:@"runningProcesses"];
	
	if (![currentProcesses isEqualToArray:newRunningProcesses])
	{
		// Remove old processes
		NSMutableArray *processesToRemove = [[NSMutableArray alloc] init];
		
		for (id process in currentProcesses)
		{
			if (![newRunningProcesses containsObject:process])
			{
				[processesToRemove addObject:process];
			}
		}
		
		[currentProcesses removeObjectsInArray:processesToRemove];
		
		// Add new processes
		NSMutableArray *processesToAdd = [[NSMutableArray alloc] init];
		
		for (id process in newRunningProcesses)
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
	self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(poll:) userInfo:nil repeats:YES];
}

- (void)destroyPollTimer
{
	[self.pollTimer invalidate];
	self.pollTimer = nil;
}

- (void)poll:(NSTimer *)__unused timer
{
	if (self.pollRequestCount > 0)
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
	if (![self.pollObservers containsObject:observer])
	{
		NSMutableArray *newObservers = self.pollObservers ? [NSMutableArray arrayWithArray:self.pollObservers] : [NSMutableArray array];
		
		[newObservers addObject:observer];
		self.pollObservers = [NSArray arrayWithArray:newObservers];
		
		if (self.pollRequestCount == 0 && !self.pollTimer)
		{
			[self createPollTimer];
		}
		
		self.pollRequestCount++;
	}
}

- (void)unrequestPollingWithObserver:(id)observer
{
	if ([self.pollObservers containsObject:observer])
	{
		NSMutableArray *newObservers = [NSMutableArray arrayWithArray:self.pollObservers];
		[newObservers removeObject:observer];
		self.pollObservers = [NSArray arrayWithArray:newObservers];
		
		self.pollRequestCount--;
		
		if (self.pollRequestCount == 0 && _priorityProcesses.count == 0)
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
		BOOL increasedUserReference = retrievedTask && [_processTaskManager setPortSendRightReferenceCountByDelta:1 task:task];
		
		if (!increasedUserReference || !MACH_PORT_VALID(task))
		{
			shouldRetrieveList = YES;
			[self removePriorityToProcessIdentifier:processIdentifier withObserver:runningProcessObserver.observer];
		}
		
		if (increasedUserReference && MACH_PORT_VALID(task))
		{
			[_processTaskManager setPortSendRightReferenceCountByDelta:-1 task:task];
		}
	}
	
	if (shouldRetrieveList)
	{
		[self retrieveList];
	}
}

- (void)addPriorityToProcessIdentifier:(pid_t)processIdentifier withObserver:(id)observer
{
	ZGRunningProcessObserver *runningProcessObserver = [[ZGRunningProcessObserver alloc] initWithProcessIdentifier:processIdentifier observer:observer];
	
	if (![_priorityProcesses containsObject:runningProcessObserver])
	{
		NSMutableArray *newPriorityProcesses = _priorityProcesses ? [NSMutableArray arrayWithArray:_priorityProcesses] : [NSMutableArray array];
		[newPriorityProcesses addObject:runningProcessObserver];
		_priorityProcesses = [NSArray arrayWithArray:newPriorityProcesses];
		if (!self.pollTimer)
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
		NSMutableArray *newPriorityProcesses = [NSMutableArray arrayWithArray:_priorityProcesses];
		[newPriorityProcesses removeObject:runningProcessObserver];
		_priorityProcesses = [NSArray arrayWithArray:newPriorityProcesses];
		if (_priorityProcesses.count == 0 && self.pollRequestCount == 0)
		{
			[self destroyPollTimer];
		}
	}
}

@end
