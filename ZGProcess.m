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
	NSArray *oldFrozenProcesses = frozenProcesses;
	frozenProcesses = [[frozenProcesses arrayByAddingObject:@(pid)] retain];
	[oldFrozenProcesses release];
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
	
	[frozenProcesses release];
	frozenProcesses = [[NSArray arrayWithArray:mutableArray] retain];
	[mutableArray release];
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
		self.processTask = MACH_PORT_NULL;
	}
	
	return self;
}

- (void)dealloc
{
	self.name = nil;
	
	[super dealloc];
}

- (int)numberOfRegions
{
	return ZGNumberOfRegionsForProcess(self.processTask);
}

- (BOOL)grantUsAccess
{
	return ZGIsProcessValid(self.processID, &_processTask);
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
