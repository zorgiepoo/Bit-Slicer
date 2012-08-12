/*
 * This file is part of Bit Slicer.
 *
 * Bit Slicer is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 
 * Bit Slicer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 
 * You should have received a copy of the GNU General Public License
 * along with Bit Slicer.  If not, see <http://www.gnu.org/licenses/>.
 * 
 * Created by Mayur Pawashe on 10/28/09.
 * Copyright 2010 zgcoder. All rights reserved.
 */

#import "ZGProcess.h"

@implementation ZGProcess

static NSArray *frozenProcesses = nil;
+ (NSArray *)frozenProcesses
{
	if (!frozenProcesses)
	{
		frozenProcesses = [[NSArray alloc] init];
	}
	
	return frozenProcesses;
}

+ (void)addFrozenProcess:(pid_t)pid
{
	frozenProcesses = [frozenProcesses arrayByAddingObject:@(pid)];
}

+ (void)removeFrozenProcess:(pid_t)pid
{
	NSMutableArray *mutableArray = [[NSMutableArray alloc] init];
	
	for (NSNumber *currentPID in frozenProcesses)
	{
		if (currentPID.intValue != pid)
		{
			[mutableArray addObject:currentPID];
		}
	}
	
	frozenProcesses = [NSArray arrayWithArray:mutableArray];
}

+ (void)pauseOrUnpauseProcess:(pid_t)pid
{
	BOOL success;
	
	if ([ZGProcess.frozenProcesses containsObject:@(pid)])
	{
		// Unfreeze
		success = ZGUnpauseProcess(pid);
		
		if (success)
		{
			[ZGProcess removeFrozenProcess:pid];
		}
	}
	else
	{
		// Freeze
		success = ZGPauseProcess(pid);
		
		if (success)
		{
			[ZGProcess addFrozenProcess:pid];
		}
	}
}

- (id)initWithName:(NSString *)processName processID:(pid_t)aProcessID set64Bit:(BOOL)flag64Bit
{
	if ((self = [super init]))
	{
		self.name = processName;
		self.processID = aProcessID;
		self.is64Bit = flag64Bit;
	}
	
	return self;
}

- (void)dealloc
{
	self.processTask = MACH_PORT_NULL;
}

- (void)setProcessTask:(ZGMemoryMap)newProcessTask
{
	if (_processTask)
	{
		ZGFreeTask(_processTask);
	}
	
	_processTask = newProcessTask;
}

- (int)numberOfRegions
{
	return ZGNumberOfRegionsForProcessTask(self.processTask);
}

- (BOOL)grantUsAccess
{
	ZGMemoryMap newProcessTask = MACH_PORT_NULL;
	BOOL success = ZGGetTaskForProcess(self.processID, &newProcessTask);
	if (success)
	{
		self.processTask = newProcessTask;
	}
	
	return success;
}

- (BOOL)hasGrantedAccess
{
    return (self.processTask != MACH_PORT_NULL);
}

- (ZGMemorySize)pointerSize
{
	return self.is64Bit ? sizeof(int64_t) : sizeof(int32_t);
}

@end
