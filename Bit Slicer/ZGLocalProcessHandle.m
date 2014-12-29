/*
 * Created by Mayur Pawashe on 12/26/14.
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

#import "ZGLocalProcessHandle.h"
#import "ZGVirtualMemory.h"
#import <mach/mach_vm.h>
#import "ZGRegion.h"
#import "CoreSymbolication.h"

@interface ZGLocalProcessHandle ()

@property (nonatomic) CSSymbolicatorRef symbolicator;

@end

@implementation ZGLocalProcessHandle
{
	ZGMemoryMap _processTask;
}

- (id)initWithProcessTask:(ZGMemoryMap)processTask
{
	self = [super init];
	if (self != nil)
	{
		_processTask = processTask;
	}
	return self;
}

- (void)dealloc
{
	if (!CSIsNull(_symbolicator))
	{
		CSRelease(_symbolicator);
	}
}

- (BOOL)allocateMemoryAndGetAddress:(ZGMemoryAddress *)address size:(ZGMemorySize)size
{
	return ZGAllocateMemory(_processTask, address, size);
}

- (BOOL)deallocateMemoryAtAddress:(ZGMemoryAddress)address size:(ZGMemorySize)size
{
	return ZGDeallocateMemory(_processTask, address, size);
}

- (BOOL)readBytes:(void **)bytes address:(ZGMemoryAddress)address size:(ZGMemorySize *)size
{
	return ZGReadBytes(_processTask, address, bytes, size);
}

- (BOOL)freeBytes:(void *)bytes size:(ZGMemorySize)size
{
	return ZGFreeBytes(bytes, size);
}

- (BOOL)writeBytes:(const void *)bytes address:(ZGMemoryAddress)address size:(ZGMemorySize)size
{
	return ZGWriteBytes(_processTask, address, bytes, size);
}

- (BOOL)writeBytesOverwritingProtection:(const void *)bytes address:(ZGMemoryAddress)address size:(ZGMemorySize)size
{
	return ZGWriteBytesOverwritingProtection(_processTask, address, bytes, size);
}

- (BOOL)writeBytesIgnoringProtection:(const void *)bytes address:(ZGMemoryAddress)address size:(ZGMemorySize)size
{
	return ZGWriteBytesIgnoringProtection(_processTask, address, bytes, size);
}

- (BOOL)getDyldTaskInfo:(struct task_dyld_info *)dyldTaskInfo count:(mach_msg_type_number_t *)count
{
	mach_msg_type_number_t localCount = TASK_DYLD_INFO_COUNT;
	bool success = ZGTaskInfo(_processTask, dyldTaskInfo, TASK_DYLD_INFO, &localCount);
	*count = localCount;
	return success;
}

- (BOOL)setProtection:(ZGMemoryProtection)protection address:(ZGMemoryAddress)address size:(ZGMemorySize)size
{
	return ZGProtect(_processTask, address, size, protection);
}

- (BOOL)getPageSize:(ZGMemorySize *)pageSize
{
	return ZGPageSize(_processTask, pageSize);
}

- (BOOL)suspend
{
	return ZGSuspendTask(_processTask);
}

- (BOOL)resume
{
	return ZGResumeTask(_processTask);
}

- (BOOL)getSuspendCount:(integer_t *)suspendCount
{
	return ZGSuspendCount(_processTask, suspendCount);
}

- (NSArray *)regions
{
	return [ZGRegion regionsFromProcessTask:_processTask];
}

- (NSArray *)submapRegions
{
	return [ZGRegion submapRegionsFromProcessTask:_processTask];
}

- (NSArray *)submapRegionsInRegion:(ZGRegion *)region
{
	return [ZGRegion submapRegionsFromProcessTask:_processTask region:region];
}

- (BOOL)getRegionInfo:(ZGMemoryBasicInfo *)regionInfo address:(ZGMemoryAddress *)address size:(ZGMemorySize *)size
{
	return ZGRegionInfo(_processTask, address, size, regionInfo);
}

- (BOOL)getMemoryProtection:(ZGMemoryProtection *)memoryProtection address:(ZGMemoryAddress *)address size:(ZGMemorySize *)size
{
	return ZGMemoryProtectionInRegion(_processTask, address, size, memoryProtection);
}

- (CSSymbolicatorRef)symbolicator
{
	if (CSIsNull(_symbolicator))
	{
		_symbolicator = CSSymbolicatorCreateWithTask(_processTask);
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

- (ZGMemorySize)readStringSizeFromAddress:(ZGMemoryAddress)address dataType:(ZGVariableType)dataType oldSize:(ZGMemorySize)oldSize maxSize:(ZGMemorySize)maxStringSizeLimit
{
	ZGMemorySize totalSize = 0;
	
	ZGMemorySize characterSize = (dataType == ZGString8) ? sizeof(char) : sizeof(unichar);
	void *buffer = NULL;
	
	if (dataType == ZGString16 && oldSize % 2 != 0)
	{
		oldSize--;
	}
	
	BOOL shouldUseOldSize = (oldSize >= characterSize);
	
	while (YES)
	{
		BOOL shouldBreak = NO;
		ZGMemorySize outputtedSize = shouldUseOldSize ? oldSize : characterSize;
		
		BOOL couldReadBytes = ZGReadBytes(_processTask, address, &buffer, &outputtedSize);
		if (!couldReadBytes && shouldUseOldSize)
		{
			shouldUseOldSize = NO;
			continue;
		}
		
		if (couldReadBytes)
		{
			ZGMemorySize numberOfCharacters = outputtedSize / characterSize;
			if (dataType == ZGString16 && outputtedSize % 2 != 0 && numberOfCharacters > 0)
			{
				numberOfCharacters--;
				shouldBreak = YES;
			}
			
			for (ZGMemorySize characterCounter = 0; characterCounter < numberOfCharacters; characterCounter++)
			{
				if ((dataType == ZGString8 && ((char *)buffer)[characterCounter] == 0) || (dataType == ZGString16 && ((unichar *)buffer)[characterCounter] == 0))
				{
					shouldBreak = YES;
					break;
				}
				
				totalSize += characterSize;
			}
			
			ZGFreeBytes(buffer, outputtedSize);
			
			if (maxStringSizeLimit > 0 && totalSize >= maxStringSizeLimit)
			{
				totalSize = maxStringSizeLimit;
				shouldBreak = YES;
			}
			
			if (dataType == ZGString16)
			{
				outputtedSize = numberOfCharacters * characterSize;
			}
		}
		else
		{
			shouldBreak = YES;
		}
		
		if (shouldBreak)
		{
			break;
		}
		
		address += outputtedSize;
	}
	
	return totalSize;
}

@end
