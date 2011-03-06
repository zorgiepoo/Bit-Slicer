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

#import "ZGVariable.h"
#import <mach/mach_traps.h>
#import <signal.h>
#import <mach/mach_init.h>
#import <mach/vm_map.h>
#import <mach/mach_vm.h>
#import <mach/mach.h>

#define INVALID_PROCESS_INITIALIZATION	-1

@class ZGProcess;

@interface ZGSearchData : NSObject
{
	@public
	BOOL shouldCancelSearch;
	BOOL searchDidCancel;
	
	NSArray *savedData;
	NSArray *tempSavedData;
}
@end

typedef void (^search_for_data_t)(void *data, void *data2, vm_address_t address, int currentRegionNumber);
typedef void (^memory_dump_t)(int currentRegionNumber);

int ZGInitializeTaskForProcess(pid_t process);
BOOL ZGReadBytes(pid_t process, mach_vm_address_t address, void *bytes, mach_vm_size_t size);
BOOL ZGReadBytesCarefully(pid_t process, mach_vm_address_t address, void *bytes, mach_vm_size_t *size);
BOOL ZGWriteBytes(pid_t process, mach_vm_address_t address, const void *bytes, mach_vm_size_t size);
void ZGFreeData(NSArray *dataArray);
NSArray *ZGGetAllData(ZGProcess *process);
void *ZGSavedValue(mach_vm_address_t address, ZGSearchData *searchData, mach_vm_size_t dataSize);
BOOL ZGSaveAllDataToDirectory(NSString *directory, ZGProcess *process);
void ZGInitializeSearch(ZGSearchData *searchData);
void ZGCancelSearch(ZGSearchData *searchData);
BOOL ZGSearchIsCancelling(ZGSearchData *searchData);
void ZGCancelSearchImmediately(ZGSearchData *searchData);
BOOL ZGSearchDidCancelSearch(ZGSearchData *searchData);
void ZGSearchForSavedData(pid_t process, BOOL is64Bit, mach_vm_size_t dataSize, ZGSearchData *searchData, search_for_data_t block);
void ZGSearchForData(pid_t process, BOOL is64Bit, ZGVariableType dataType, mach_vm_size_t dataSize, ZGSearchData *searchData, search_for_data_t block);
mach_vm_size_t ZGGetStringSize(pid_t process, mach_vm_address_t address, ZGVariableType dataType);
BOOL ZGPauseProcess(pid_t process);
BOOL ZGUnpauseProcess(pid_t process);
