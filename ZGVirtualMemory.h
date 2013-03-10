/*
 * Created by Mayur Pawashe on 10/25/09.
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

#import "ZGMemoryTypes.h"
#import "ZGVariableTypes.h"
#import <mach/mach_traps.h>
#import <signal.h>
#import <mach/mach_init.h>
#import <mach/vm_map.h>
#import <mach/mach_vm.h>
#import <mach/mach.h>

@class ZGSearchData;
@class ZGSearchProgress;
@class ZGRegion;

typedef void (^search_for_data_t)(ZGSearchData *searchData, void *variableData, void *compareData, ZGMemoryAddress address, NSMutableArray *results);

typedef NSArray *(*search_for_data_function_t)(ZGMemoryMap, ZGSearchData *, ZGSearchProgress *, search_for_data_t);

BOOL ZGTaskExistsForProcess(pid_t process, ZGMemoryMap *task);
BOOL ZGGetTaskForProcess(pid_t process, ZGMemoryMap *task);
void ZGFreeTask(ZGMemoryMap task);

NSArray *ZGRegionsForProcessTask(ZGMemoryMap processTask);
NSUInteger ZGNumberOfRegionsForProcessTask(ZGMemoryMap processTask);

BOOL ZGReadBytes(ZGMemoryMap processTask, ZGMemoryAddress address, void **bytes, ZGMemorySize *size);
void ZGFreeBytes(ZGMemoryMap processTask, const void *bytes, ZGMemorySize size);
BOOL ZGWriteBytes(ZGMemoryMap processTask, ZGMemoryAddress address, const void *bytes, ZGMemorySize size);
BOOL ZGWriteBytesIgnoringProtection(ZGMemoryMap processTask, ZGMemoryAddress address, const void *bytes, ZGMemorySize size);

BOOL ZGMemoryProtectionInRegion(ZGMemoryMap processTask, ZGMemoryAddress *address, ZGMemorySize *size, ZGMemoryProtection *memoryProtection);
BOOL ZGProtect(ZGMemoryMap processTask, ZGMemoryAddress address, ZGMemorySize size, ZGMemoryProtection protection);

void ZGFreeData(NSArray *dataArray);
NSArray *ZGGetAllData(ZGMemoryMap processTask, ZGSearchData *searchData, ZGSearchProgress *searchProgress);
void *ZGSavedValue(ZGMemoryAddress address, ZGSearchData * __unsafe_unretained searchData, ZGRegion **hintedRegionReference, ZGMemorySize dataSize);
BOOL ZGSaveAllDataToDirectory(NSString *directory, ZGMemoryMap processTask, ZGSearchProgress *searchProgress);

ZGMemorySize ZGDataAlignment(BOOL isProcess64Bit, ZGVariableType dataType, ZGMemorySize dataSize);

NSArray *ZGSearchForSavedData(ZGMemoryMap processTask, ZGSearchData * searchData, ZGSearchProgress *searchProgress, search_for_data_t searchForDataBlock);
NSArray *ZGSearchForData(ZGMemoryMap processTask, ZGSearchData *searchData, ZGSearchProgress *searchProgress, search_for_data_t searchForDataBlock);

ZGMemorySize ZGGetStringSize(ZGMemoryMap processTask, ZGMemoryAddress address, ZGVariableType dataType, ZGMemorySize oldSize);

BOOL ZGSuspendCount(ZGMemoryMap processTask, integer_t *suspendCount);

BOOL ZGSuspendTask(ZGMemoryMap processTask);
BOOL ZGResumeTask(ZGMemoryMap processTask);
