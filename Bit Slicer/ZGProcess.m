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

#import "ZGProcess.h"
#import "ZGMachBinary.h"
#import "ZGVirtualMemory.h"
#import "ZGMachBinary.h"
#import "ZGMachBinaryInfo.h"
#import "ZGPrivateCoreSymbolicator.h"

@implementation ZGProcess
{
	NSMutableDictionary<NSString *, NSMutableDictionary *> * _Nullable _cacheDictionary;
	
	ZGMachBinary * _Nullable _mainMachBinary;
	ZGMachBinary * _Nullable _dylinkerBinary;
	
	id <ZGSymbolicator> _Nullable _symbolicator;
	BOOL _failedCreatingSymbolicator;
}

- (instancetype)initWithName:(NSString *)processName internalName:(NSString *)internalName processID:(pid_t)aProcessID is64Bit:(BOOL)flag64Bit
{
	if ((self = [super init]))
	{
		_name = [processName copy];
		_internalName = [internalName copy];
		_processID = aProcessID;
		_is64Bit = flag64Bit;
	}
	
	return self;
}

- (instancetype)initWithName:(NSString *)processName internalName:(NSString *)internalName is64Bit:(BOOL)flag64Bit
{
	return [self initWithName:processName internalName:internalName processID:NON_EXISTENT_PID_NUMBER is64Bit:flag64Bit];
}

- (instancetype)initWithProcess:(ZGProcess *)process processTask:(ZGMemoryMap)processTask name:(NSString *)name
{
	self = [self initWithName:name internalName:process.internalName processID:process.processID is64Bit:process.is64Bit];
	if (self != nil)
	{
		_processTask = processTask;
	}
	return self;
}

- (instancetype)initWithProcess:(ZGProcess *)process
{
	return [self initWithProcess:process processTask:process.processTask name:process.name];
}

- (instancetype)initWithProcess:(ZGProcess *)process name:(NSString *)name
{
	return [self initWithProcess:process processTask:process.processTask name:name];
}

- (instancetype)initWithProcess:(ZGProcess *)process processTask:(ZGMemoryMap)processTask
{
	return [self initWithProcess:process processTask:processTask name:process.name];
}

- (void)dealloc
{
	if ([self valid] && _symbolicator != nil)
	{
		[_symbolicator invalidate];
	}
}

- (BOOL)isEqual:(id)process
{
	return ([(ZGProcess *)process processID] == _processID);
}

- (NSUInteger)hash
{
	return (NSUInteger)_processID;
}

- (BOOL)valid
{
	return _processID != NON_EXISTENT_PID_NUMBER;
}

- (id <ZGSymbolicator>)symbolicator
{
	if ([self valid] && _symbolicator == nil && !_failedCreatingSymbolicator)
	{
		_symbolicator = [[ZGPrivateCoreSymbolicator alloc] initWithTask:_processTask];
		// Creating the symbolicator can be very costly; make sure we don't try creating one often if it keeps failing
		if (_symbolicator == nil)
		{
			_failedCreatingSymbolicator = YES;
		}
	}
	return _symbolicator;
}

- (NSMutableDictionary<NSString *, NSMutableDictionary *> *)cacheDictionary
{
	if (_cacheDictionary == nil)
	{
		_cacheDictionary = [[NSMutableDictionary alloc] initWithDictionary:@{ZGMachBinaryPathToBinaryInfoDictionary : [NSMutableDictionary dictionary], ZGMachBinaryPathToBinaryDictionary : [NSMutableDictionary dictionary]}];
	}
	return (id _Nonnull)_cacheDictionary;
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
    return MACH_PORT_VALID(_processTask);
}

- (ZGMemorySize)pointerSize
{
	return _is64Bit ? sizeof(int64_t) : sizeof(int32_t);
}

@end
