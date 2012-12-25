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
#import "ZGVariable.h"
#import <mach/mach_traps.h>
#import <signal.h>
#import <mach/mach_init.h>
#import <mach/vm_map.h>
#import <mach/mach_vm.h>
#import <mach/mach.h>

@interface ZGRegion : NSObject

@property (assign, nonatomic) ZGMemoryMap processTask;
@property (assign, nonatomic) ZGMemoryAddress address;
@property (assign, nonatomic) ZGMemorySize size;
@property (assign, nonatomic) ZGMemoryProtection protection;
@property (assign, nonatomic) void *bytes;

@end

@class ZGSearchData;
@class ZGProcess;

typedef void (^search_for_data_t)(ZGSearchData *searchData, void *variableData, void *compareData, ZGMemoryAddress address, ZGMemorySize currentRegionNumber, NSMutableArray *results);

typedef void (^search_for_data_update_interface_t)(NSArray *newResults, ZGMemorySize currentRegionNumber);

BOOL ZGGetTaskForProcess(pid_t process, ZGMemoryMap *task);
void ZGFreeTask(ZGMemoryMap task);

NSArray *ZGRegionsForProcessTask(ZGMemoryMap processTask);
NSUInteger ZGNumberOfRegionsForProcessTask(ZGMemoryMap processTask);

BOOL ZGReadBytes(ZGMemoryMap processTask, ZGMemoryAddress address, void **bytes, ZGMemorySize *size);
void ZGFreeBytes(ZGMemoryMap processTask, const void *bytes, ZGMemorySize size);
BOOL ZGWriteBytes(ZGMemoryMap processTask, ZGMemoryAddress address, const void *bytes, ZGMemorySize size);

BOOL ZGMemoryProtectionInRegion(ZGMemoryMap processTask, ZGMemoryAddress *address, ZGMemorySize *size, ZGMemoryProtection *memoryProtection);
BOOL ZGProtect(ZGMemoryMap processTask, ZGMemoryAddress address, ZGMemorySize size, ZGMemoryProtection protection);

void ZGFreeData(NSArray *dataArray);
NSArray *ZGGetAllData(ZGProcess *process, BOOL shouldScanUnwritableValues);
void *ZGSavedValue(ZGMemoryAddress address, ZGSearchData * __unsafe_unretained searchData, ZGMemorySize dataSize);
BOOL ZGSaveAllDataToDirectory(NSString *directory, ZGProcess *process);

void ZGInitializeSearch(ZGSearchData *searchData);
void ZGCancelSearch(ZGSearchData *searchData);
BOOL ZGSearchIsCancelling(ZGSearchData *searchData);
void ZGCancelSearchImmediately(ZGSearchData *searchData);
BOOL ZGSearchDidCancel(ZGSearchData * __unsafe_unretained searchData);
ZGMemorySize ZGDataAlignment(BOOL isProcess64Bit, ZGVariableType dataType, ZGMemorySize dataSize);

// Avoid using the autoreleasepool in the callback for these search functions, otherwise memory usage may grow
void ZGSearchForSavedData(ZGMemoryMap processTask, ZGSearchData * __unsafe_unretained searchData, search_for_data_t block);
NSArray *ZGSearchForData(ZGMemoryMap processTask, ZGSearchData * __unsafe_unretained searchData, search_for_data_t searchForDataBlock, search_for_data_update_interface_t updateInterfaceBlock);

ZGMemorySize ZGGetStringSize(ZGMemoryMap processTask, ZGMemoryAddress address, ZGVariableType dataType, ZGMemorySize oldSize);

BOOL ZGPauseProcess(pid_t process);
BOOL ZGUnpauseProcess(pid_t process);
