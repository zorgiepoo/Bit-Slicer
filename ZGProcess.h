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

#import <Cocoa/Cocoa.h>
#import "ZGVirtualMemory.h"
#import <sys/sysctl.h>

@interface ZGProcess : NSObject
{
	NSString *name;
	
@public
	// searching related stuff
	int searchProgress;
	int numberOfVariablesFound;
	
	// other task-intensive related stuff
	BOOL isDoingMemoryDump;
	BOOL isStoringAllData;
	
	pid_t processID;
	ZGMemoryMap processTask;
	BOOL is64Bit;
}

+ (NSArray *)frozenProcesses;
+ (void)addFrozenProcess:(pid_t)pid;
+ (void)removeFrozenProcess:(pid_t)pid;
+ (void)pauseOrUnpauseProcess:(pid_t)pid;

- (id)initWithName:(NSString *)processName processID:(pid_t)aProcessID set64Bit:(BOOL)flag64Bit;
- (BOOL)grantUsAccess;
- (BOOL)hasGrantedAccess;

@property (assign) pid_t processID;
@property (assign) ZGMemoryMap processTask;
@property (copy) NSString *name;
@property (readonly) int numberOfRegions;

@end
