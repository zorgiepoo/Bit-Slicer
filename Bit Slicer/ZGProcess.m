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
#import "ZGProcessTaskManager.h"
#import "ZGMachBinary.h"
#import "ZGMachBinaryInfo.h"
#import "CoreSymbolication.h"

@interface ZGProcess ()

@property (nonatomic) ZGMachBinary *mainMachBinary;
@property (nonatomic) ZGMachBinary *dylinkerBinary;

@property (nonatomic) CSSymbolicatorRef symbolicator;

@end

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

- (instancetype)initWithName:(NSString *)processName internalName:(NSString *)internalName processID:(pid_t)aProcessID is64Bit:(BOOL)flag64Bit
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

- (instancetype)initWithName:(NSString *)processName internalName:(NSString *)internalName is64Bit:(BOOL)flag64Bit
{
	return [self initWithName:processName internalName:internalName processID:NON_EXISTENT_PID_NUMBER is64Bit:flag64Bit];
}

- (instancetype)initWithProcess:(ZGProcess *)process
{
	self = [self initWithName:process.name internalName:process.internalName processID:process.processID is64Bit:process.is64Bit];
	if (self != nil)
	{
		self.processTask = process.processTask;
	}
	return self;
}

- (void)dealloc
{
	if (self.valid && !CSIsNull(self.symbolicator))
	{
		CSRelease(self.symbolicator);
	}
}

- (BOOL)isEqual:(id)process
{
	return ([process processID] == self.processID);
}

- (BOOL)valid
{
	return self.processID != NON_EXISTENT_PID_NUMBER;
}

- (void)markInvalid
{
	self.processID = NON_EXISTENT_PID_NUMBER;
	self.processTask = MACH_PORT_NULL;
	_cacheDictionary = nil;
	_dylinkerBinary = nil;
	_mainMachBinary = nil;
}

- (CSSymbolicatorRef)symbolicator
{
	if (self.valid && CSIsNull(_symbolicator))
	{
		_symbolicator = CSSymbolicatorCreateWithTask(self.processTask);
	}
	return _symbolicator;
}

- (NSString *)symbolAtAddress:(ZGMemoryAddress)address relativeOffset:(ZGMemoryAddress *)relativeOffset
{
	NSString *symbolName = nil;
	CSSymbolicatorRef symbolicator = self.symbolicator;
	if (!CSIsNull(symbolicator))
	{
		CSSymbolRef symbol = CSSymbolicatorGetSymbolWithAddressAtTime(symbolicator, address, kCSNow);
		if (!CSIsNull(symbol))
		{
			const char *symbolNameCString = CSSymbolGetName(symbol);
			if (symbolNameCString != NULL)
			{
				symbolName = @(symbolNameCString);
			}

			if (relativeOffset != NULL)
			{
				CSRange symbolRange = CSSymbolGetRange(symbol);
				*relativeOffset = address - symbolRange.location;
			}
		}
	}

	return symbolName;
}

- (NSNumber *)findSymbol:(NSString *)symbolName withPartialSymbolOwnerName:(NSString *)partialSymbolOwnerName requiringExactMatch:(BOOL)requiresExactMatch pastAddress:(ZGMemoryAddress)pastAddress
{
	__block CSSymbolRef resultSymbol = kCSNull;
	__block BOOL foundDesiredSymbol = NO;

	CSSymbolicatorRef symbolicator = self.symbolicator;
	if (CSIsNull(symbolicator)) return nil;

	const char *symbolCString = [symbolName UTF8String];

	CSSymbolicatorForeachSymbolOwnerAtTime(symbolicator, kCSNow, ^(CSSymbolOwnerRef owner) {
		if (!foundDesiredSymbol)
		{
			const char *symbolOwnerName = CSSymbolOwnerGetName(owner); // this really returns a suffix
			if (partialSymbolOwnerName == nil || (symbolOwnerName != NULL && [partialSymbolOwnerName hasSuffix:@(symbolOwnerName)]))
			{
				CSSymbolOwnerForeachSymbol(owner, ^(CSSymbolRef symbol) {
					if (!foundDesiredSymbol)
					{
						const char *symbolFound = CSSymbolGetName(symbol);
						if (symbolFound != NULL && ((requiresExactMatch && strcmp(symbolCString, symbolFound) == 0) || (!requiresExactMatch && strstr(symbolFound, symbolCString) != NULL)))
						{
							CSRange symbolRange = CSSymbolGetRange(symbol);
							if (pastAddress < symbolRange.location)
							{
								foundDesiredSymbol = YES;
							}

							resultSymbol = symbol;
						}
					}
				});
			}
		}
	});

	return CSIsNull(resultSymbol) ? nil : @(CSSymbolGetRange(resultSymbol).location);
}

- (NSMutableDictionary *)cacheDictionary
{
	if (_cacheDictionary == nil)
	{
		_cacheDictionary = [[NSMutableDictionary alloc] initWithDictionary:@{ZGMachBinaryPathToBinaryInfoDictionary : [NSMutableDictionary dictionary], ZGMachBinaryPathToBinaryDictionary : [NSMutableDictionary dictionary]}];
	}
	return _cacheDictionary;
}

- (ZGMachBinary *)dylinkerBinary
{
	if (_dylinkerBinary == nil)
	{
		_dylinkerBinary = [ZGMachBinary dynamicLinkerMachBinaryInProcess:self];;
	}
	return _dylinkerBinary;
}

- (ZGMachBinary *)mainMachBinary
{
	if (_mainMachBinary == nil)
	{
		_mainMachBinary = [ZGMachBinary mainMachBinaryFromMachBinaries:[ZGMachBinary machBinariesInProcess:self]];
	}
	return _mainMachBinary;
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
