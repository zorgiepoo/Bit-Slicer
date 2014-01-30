/*
 * Created by Mayur Pawashe on 10/28/09.
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

#import "ZGProcess.h"
#import "ZGMachBinary.h"
#import "ZGVirtualMemory.h"
#import "ZGVirtualMemoryHelpers.h"
#import "ZGMachBinaryInfo.h"

#include <libproc.h>

@implementation ZGProcess

+ (void)pauseOrUnpauseProcessTask:(ZGMemoryMap)processTask
{
	integer_t suspendCount;
	if (ZGSuspendCount(processTask, &suspendCount))
	{
		if (suspendCount > 0)
		{
			ZGResumeTask(processTask);
		}
		else
		{
			ZGSuspendTask(processTask);
		}
	}
}

- (id)initWithName:(NSString *)processName internalName:(NSString *)internalName processID:(pid_t)aProcessID is64Bit:(BOOL)flag64Bit
{
	if ((self = [super init]))
	{
		self.name = processName;
		self.internalName = internalName;
		self.processID = aProcessID;
		self.is64Bit = flag64Bit;
	}
	
	return self;
}

- (id)initWithName:(NSString *)processName internalName:(NSString *)internalName is64Bit:(BOOL)flag64Bit
{
	return [self initWithName:processName internalName:internalName processID:NON_EXISTENT_PID_NUMBER is64Bit:flag64Bit];
}

- (BOOL)valid
{
	return self.processID != NON_EXISTENT_PID_NUMBER;
}

- (void)markInvalid
{
	self.processID = NON_EXISTENT_PID_NUMBER;
	self.processTask = MACH_PORT_NULL;
	self.cacheDictionary = nil;
}

- (BOOL)grantUsAccess
{
	BOOL success = ZGGetTaskForProcess(self.processID, &_processTask);
	if (success)
	{	
		self.cacheDictionary = [[NSMutableDictionary alloc] init];
		NSMutableDictionary *mappedPathDictionary = [[NSMutableDictionary alloc] init];
		NSMutableDictionary *mappedBinaryDictionary = [[NSMutableDictionary alloc] init];
		[self.cacheDictionary setObject:mappedPathDictionary forKey:ZGMappedPathDictionary];
		[self.cacheDictionary setObject:mappedBinaryDictionary forKey:ZGMappedBinaryDictionary];
		[self.cacheDictionary setObject:[NSMutableDictionary dictionary] forKey:ZGMachFileDataDictionary];
		
		_dylinkerBinary = ZGDylinkerBinary(_processTask);
		NSArray *machBinaries = ZGMachBinaries(_processTask, self.pointerSize, _dylinkerBinary);
		if (machBinaries.count > 0)
		{
			self.baseAddress = [[machBinaries objectAtIndex:0] headerAddress];
			
			// Set up initial cache for full paths, partial paths, and partial paths prepended with forward slashes
			for (ZGMachBinary *machBinary in machBinaries)
			{
				ZGMemoryAddress machAddress = machBinary.headerAddress;
				NSString *mappedPath = ZGFilePathAtAddress(_processTask, machBinary.filePathAddress);
				NSString *lastPathComponent = [mappedPath lastPathComponent];
				
				if ([mappedPathDictionary objectForKey:mappedPath] == nil)
				{
					[mappedPathDictionary setObject:@(machAddress) forKey:mappedPath];
				}
				if ([mappedPathDictionary objectForKey:lastPathComponent] == nil)
				{
					[mappedPathDictionary setObject:@(machAddress) forKey:lastPathComponent];
				}
				if ([[mappedPath stringByDeletingLastPathComponent] length] > 0)
				{
					NSString *forwardSlashedPrependedPath = [@"/" stringByAppendingString:lastPathComponent];
					if ([mappedPathDictionary objectForKey:forwardSlashedPrependedPath] == nil)
					{
						[mappedPathDictionary setObject:@(machAddress) forKey:forwardSlashedPrependedPath];
					}
				}
				
				// Region address -> mach binary address
				[mappedBinaryDictionary setObject:@(machAddress) forKey:@(machAddress)];
			}
		}
	}
	return success;
}

- (BOOL)hasGrantedAccess
{
    return MACH_PORT_VALID(self.processTask);
}

- (ZGMemorySize)pointerSize
{
	return self.is64Bit ? sizeof(int64_t) : sizeof(int32_t);
}

@end
