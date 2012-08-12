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
 * Created by Mayur Pawashe on 10/25/09.
 * Copyright 2010 zgcoder. All rights reserved.
 */

#import "ZGMemoryTypes.h"
#import "ZGVariable.h"
#import <mach/mach_traps.h>
#import <signal.h>
#import <mach/mach_init.h>
#import <mach/vm_map.h>
#import <mach/mach_vm.h>
#import <mach/mach.h>

@class ZGSearchData;
@class ZGProcess;

typedef void (^search_for_data_t)(ZGSearchData *searchData, void *variableData, void *compareData, ZGMemoryAddress address, ZGMemorySize currentRegionNumber);

BOOL ZGIsProcessValid(pid_t process, ZGMemoryMap *task);
void ZGFreeTask(ZGMemoryMap task);

int ZGNumberOfRegionsForProcess(ZGMemoryMap processTask);

BOOL ZGReadBytes(ZGMemoryMap processTask, ZGMemoryAddress address, void **bytes, ZGMemorySize *size);
void ZGFreeBytes(ZGMemoryMap processTask, const void *bytes, ZGMemorySize size);
BOOL ZGWriteBytes(ZGMemoryMap processTask, ZGMemoryAddress address, const void *bytes, ZGMemorySize size);

BOOL ZGMemoryProtectionInRegion(ZGMemoryMap processTask, ZGMemoryAddress *address, ZGMemorySize *size, ZGMemoryProtection *memoryProtection);
BOOL ZGProtect(ZGMemoryMap processTask, ZGMemoryAddress address, ZGMemorySize size, ZGMemoryProtection protection);

void ZGFreeData(NSArray *dataArray);
NSArray *ZGGetAllData(ZGProcess *process, BOOL shouldScanUnwritableValues);
void *ZGSavedValue(ZGMemoryAddress address, ZGSearchData *searchData, ZGMemorySize dataSize);
BOOL ZGSaveAllDataToDirectory(NSString *directory, ZGProcess *process);

void ZGInitializeSearch(ZGSearchData *searchData);
void ZGCancelSearch(ZGSearchData *searchData);
BOOL ZGSearchIsCancelling(ZGSearchData *searchData);
void ZGCancelSearchImmediately(ZGSearchData *searchData);
BOOL ZGSearchDidCancelSearch(ZGSearchData *searchData);
ZGMemorySize ZGDataAlignment(BOOL isProcess64Bit, ZGVariableType dataType, ZGMemorySize dataSize);

// Avoid using the autoreleasepool in the callback for these search functions, otherwise memory usage may grow
void ZGSearchForSavedData(ZGMemoryMap processTask, ZGMemorySize dataAlignment, ZGMemorySize dataSize, ZGSearchData *searchData, search_for_data_t block);
void ZGSearchForData(ZGMemoryMap processTask, ZGMemorySize dataAlignment, ZGMemorySize dataSize, ZGSearchData *searchData, search_for_data_t block);

ZGMemorySize ZGGetStringSize(ZGMemoryMap processTask, ZGMemoryAddress address, ZGVariableType dataType);

BOOL ZGPauseProcess(pid_t process);
BOOL ZGUnpauseProcess(pid_t process);
