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

#import "ZGVirtualMemory.h"
#import "ZGProcess.h"

@implementation ZGSearchData
@end

BOOL ZGIsProcessValid(pid_t process)
{
	vm_map_t task = MACH_PORT_NULL;
	BOOL success = (task_for_pid(current_task(), process, &task) == KERN_SUCCESS);
	
	if (success && task != MACH_PORT_NULL)
	{
		mach_port_deallocate(current_task(), task);
	}
	
	return success;
}

int ZGNumberOfRegionsForProcess(pid_t process)
{
	vm_map_t task = MACH_PORT_NULL;
	int numberOfRegions = 0;
	if (task_for_pid(current_task(), process, &task) == KERN_SUCCESS)
	{
		ZGMemoryAddress address = 0x0;
		ZGMemorySize size;
		vm_region_basic_info_data_64_t info;
		mach_msg_type_number_t infoCount = VM_REGION_BASIC_INFO_COUNT_64;
		mach_port_t objectName = MACH_PORT_NULL;
		
		while (mach_vm_region(task, &address, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &infoCount, &objectName) == KERN_SUCCESS)
		{
			numberOfRegions++;
			address += size;
		}
		
		if (task != MACH_PORT_NULL)
		{
			mach_port_deallocate(current_task(), task);
		}
	}
	
	return numberOfRegions;
}

BOOL ZGReadBytes(pid_t process, ZGMemoryAddress address, void *bytes, ZGMemorySize size)
{
	BOOL success = NO;
	vm_map_t task = MACH_PORT_NULL;
	if (task_for_pid(current_task(), process, &task) == KERN_SUCCESS)
	{
		success = (mach_vm_read_overwrite(task, address, size, (ZGMemoryAddress)bytes, &size) == KERN_SUCCESS);
		
		if (task != MACH_PORT_NULL)
		{
			mach_port_deallocate(current_task(), task);
		}
	}
	
	return success;
}

BOOL ZGReadBytesCarefully(pid_t process, ZGMemoryAddress address, void *bytes, ZGMemorySize *size)
{
	BOOL success = NO;
	vm_map_t task = MACH_PORT_NULL;
	ZGMemorySize originalSize = *size;
	if (task_for_pid(current_task(), process, &task) == KERN_SUCCESS)
	{
		success = (mach_vm_read_overwrite(task, address, originalSize, (ZGMemoryAddress)bytes, size) == KERN_SUCCESS);
		
		if (task != MACH_PORT_NULL)
		{
			mach_port_deallocate(current_task(), task);
		}
	}
	
	return success;
}

BOOL ZGWriteBytes(pid_t process, ZGMemoryAddress address, const void *bytes, ZGMemorySize size)
{
	BOOL success = NO;
	vm_map_t task = MACH_PORT_NULL;
	if (task_for_pid(current_task(), process, &task) == KERN_SUCCESS)
	{
		success = (mach_vm_write(task, address, (vm_offset_t)bytes, (mach_msg_type_number_t)size) == KERN_SUCCESS);
		
		if (task != MACH_PORT_NULL)
		{
			mach_port_deallocate(current_task(), task);
		}
	}
	
	return success;
}

// helper function for ZGSaveAllDataToDirectory
void ZGSavePieceOfData(NSMutableData *currentData, ZGMemoryAddress currentStartingAddress, NSString *directory, int *fileNumber, FILE *mergedFile)
{
	if (currentData)
	{
		ZGMemoryAddress endAddress = currentStartingAddress + [currentData length];
		(*fileNumber)++;
		[currentData writeToFile:[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"(%i) 0x%llX - 0x%llX", *fileNumber, currentStartingAddress, endAddress]]
					  atomically:NO];
		
		if (mergedFile)
		{
			fwrite([currentData bytes], [currentData length], 1, mergedFile);
		}
	}
}

typedef struct
{
	ZGMemoryAddress address;
	ZGMemorySize size;
	void *bytes;
} ZGRegion;

void ZGFreeData(NSArray *dataArray)
{
	for (NSValue *value in dataArray)
	{
		ZGRegion *memoryRegion = [value pointerValue];
		free(memoryRegion->bytes);
		free(memoryRegion);
	}
}

NSArray *ZGGetAllData(ZGProcess *process, BOOL scanReadOnly)
{
	NSMutableArray *dataArray = [[NSMutableArray alloc] init];
	
	vm_map_t task = MACH_PORT_NULL;
	if (task_for_pid(current_task(), process->processID, &task) == KERN_SUCCESS)
	{
		ZGMemoryAddress address = 0x0;
		ZGMemorySize size;
		vm_region_basic_info_data_64_t regionInfo;
		mach_msg_type_number_t infoCount = VM_REGION_BASIC_INFO_COUNT_64;
		mach_port_t objectName = MACH_PORT_NULL;
		
		process->isStoringAllData = YES;
		process->searchProgress = 0;
		
		while (mach_vm_region(task, &address, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&regionInfo, &infoCount, &objectName) == KERN_SUCCESS)
		{
			if ((regionInfo.protection & VM_PROT_READ) && (scanReadOnly || (regionInfo.protection & VM_PROT_WRITE)))
			{
				void *bytes = malloc((size_t)size);
				
				if (bytes)
				{
					ZGMemorySize outputSize = size;
					
					if (mach_vm_read_overwrite(task, address, size, (ZGMemoryAddress)bytes, &outputSize) == KERN_SUCCESS)
					{
						ZGRegion *memoryRegion = malloc(sizeof(ZGRegion));
						memoryRegion->bytes = bytes;
						memoryRegion->address = address;
						memoryRegion->size = outputSize;
						
						[dataArray addObject:[NSValue valueWithPointer:memoryRegion]];
					}
					else
					{
						// mach_vm_read_overwrite failed
						free(bytes);
					}
				}
			}
			
			address += size;
			
			(process->searchProgress)++;
			
			if (!process->isStoringAllData)
			{
				ZGFreeData(dataArray);
				[dataArray release];
				dataArray = nil;
				break;
			}
		}
		
		if (task != MACH_PORT_NULL)
		{
			mach_port_deallocate(current_task(), task);
		}
	}
	
	if (dataArray)
	{
		dataArray = [dataArray autorelease];
	}
	return dataArray;
}

void *ZGSavedValue(ZGMemoryAddress address, ZGSearchData *searchData, ZGMemorySize dataSize)
{
	void *value = NULL;
	
	for (NSValue *regionValue in searchData->savedData)
	{
		ZGRegion *region = [regionValue pointerValue];
		
		if (address >= region->address && address + dataSize <= region->address + region->size)
		{
			value = region->bytes + (address - region->address);
			break;
		}
	}
	
	return value;
}

BOOL ZGSaveAllDataToDirectory(NSString *directory, ZGProcess *process)
{
	vm_map_t task = MACH_PORT_NULL;
	BOOL success = NO;
	
	if (task_for_pid(current_task(), process->processID, &task) == KERN_SUCCESS)
	{
		ZGMemoryAddress address = 0x0;
		ZGMemoryAddress lastAddress = address;
		ZGMemorySize size;
		vm_region_basic_info_data_64_t regionInfo;
		mach_msg_type_number_t infoCount = VM_REGION_BASIC_INFO_COUNT_64;
		mach_port_t objectName = MACH_PORT_NULL;
		
		NSMutableData *currentData = nil;
		ZGMemoryAddress currentStartingAddress = address;
		int fileNumber = 0;
		
		FILE *mergedFile = fopen([[directory stringByAppendingPathComponent:@"(All) Merged"] UTF8String], "w");
		
		process->isDoingMemoryDump = YES;
		process->searchProgress = 0;
		
		while (mach_vm_region(task, &address, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&regionInfo, &infoCount, &objectName) == KERN_SUCCESS)
		{
			if (lastAddress != address || !(regionInfo.protection & VM_PROT_READ))
			{
				// We're done with this piece of data
				ZGSavePieceOfData(currentData, currentStartingAddress, directory, &fileNumber, mergedFile);
				[currentData release];
				currentData = nil;
			}
			
			if (regionInfo.protection & VM_PROT_READ)
			{
				if (!currentData)
				{
					currentData = [[NSMutableData alloc] init];
					currentStartingAddress = address;
				}
				
				void *bytes = malloc((size_t)size);
				ZGReadBytes(process->processID, address, bytes, size);
				
				[currentData appendBytes:bytes
								  length:(NSUInteger)size];
				
				free(bytes);
			}
			
			address += size;
			lastAddress = address;
			
			(process->searchProgress)++;
			
			if (!process->isDoingMemoryDump)
			{
				goto EXIT_ON_CANCEL;
			}
		}
		
		ZGSavePieceOfData(currentData, currentStartingAddress, directory, &fileNumber, mergedFile);
		
	EXIT_ON_CANCEL:
		[currentData release];
		
		if (mergedFile)
		{
			fclose(mergedFile);
		}
		
		success = YES;
		
		if (task != MACH_PORT_NULL)
		{
			mach_port_deallocate(current_task(), task);
		}
	}
	
	return success;
}

void ZGInitializeSearch(ZGSearchData *searchData)
{
	searchData->shouldCancelSearch = NO;
	searchData->searchDidCancel = NO;
}

void ZGCancelSearchImmediately(ZGSearchData *searchData)
{
	searchData->shouldCancelSearch = YES;
	searchData->searchDidCancel = YES;
}

void ZGCancelSearch(ZGSearchData *searchData)
{
	searchData->shouldCancelSearch = YES;
}

BOOL ZGSearchIsCancelling(ZGSearchData *searchData)
{
	return searchData->shouldCancelSearch;
}

BOOL ZGSearchDidCancelSearch(ZGSearchData *searchData)
{
	return searchData->searchDidCancel;
}

void ZGSearchForSavedData(pid_t process, BOOL is64Bit, ZGMemorySize dataSize, ZGSearchData *searchData, search_for_data_t block)
{
	ZGInitializeSearch(searchData);
	
	// doubles and 64-bit integers are on 4 byte boundaries only in 32-bit processes, while everything else is on its own size of boundary
	ZGMemorySize dataAlignment = (!is64Bit && dataSize == 8) ? 4 : dataSize;
	
	vm_map_t task = MACH_PORT_NULL;
	if (task_for_pid(current_task(), process, &task) == KERN_SUCCESS)
	{
		int currentRegionNumber = 0;
		
		for (NSValue *regionValue in searchData->savedData)
		{
			ZGRegion *region = [regionValue pointerValue];
			ZGMemoryAddress offset = 0;
			char *currentData = malloc((size_t)region->size);
			ZGMemorySize size = region->size;
			
			if (mach_vm_read_overwrite(task, region->address, size, (ZGMemoryAddress)currentData, &size) == KERN_SUCCESS)
			{
				do
				{
					block(&currentData[offset], region->bytes + offset, region->address + offset, currentRegionNumber);
					offset += dataAlignment;
				}
				while (offset + dataSize <= size && !searchData->shouldCancelSearch);
			}
			
			free(currentData);
			
			if (searchData->shouldCancelSearch)
			{
				searchData->searchDidCancel = YES;
				return;
			}
			
			currentRegionNumber++;
		}
		
		if (task != MACH_PORT_NULL)
		{
			mach_port_deallocate(current_task(), task);
		}
	}
}

void ZGSearchForData(pid_t process, BOOL is64Bit, ZGVariableType dataType, ZGMemorySize dataSize, ZGSearchData *searchData, search_for_data_t block)
{
	ZGInitializeSearch(searchData);
	
	// doubles and 64-bit integers are on 4 byte boundaries only in 32-bit processes, while everything else is on its own size of boundary
	// except for strings, which always operate on one byte boundaries
	ZGMemorySize dataAlignment = (dataType == ZGUTF8String || dataType == ZGUTF16String) ? 1 : (!is64Bit && dataSize == 8 ? 4 : dataSize);
	
	vm_map_t task = MACH_PORT_NULL;
	if (task_for_pid(current_task(), process, &task) == KERN_SUCCESS)
	{
		ZGMemoryAddress address = 0x0;
		ZGMemorySize size;
		mach_port_t objectName = MACH_PORT_NULL;
		vm_region_basic_info_data_t regionInfo;
		mach_msg_type_number_t regionInfoSize = VM_REGION_BASIC_INFO_COUNT_64;
		
		int currentRegionNumber = 0;
		
		while (mach_vm_region(task, &address, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&regionInfo, &regionInfoSize, &objectName) == KERN_SUCCESS)
		{
			if (regionInfo.protection & VM_PROT_READ && (searchData->scanReadOnly || (regionInfo.protection & VM_PROT_WRITE)))
			{
				char *bytes = malloc((size_t)size);
				
				if (bytes)
				{
					if (mach_vm_read_overwrite(task, address, size, (ZGMemoryAddress)bytes, &size) == KERN_SUCCESS)
					{
						int dataIndex = 0;
						while (dataIndex + dataSize <= size && !searchData->shouldCancelSearch)
						{
							block(&bytes[dataIndex], NULL, address + dataIndex, currentRegionNumber);
							dataIndex += dataAlignment;
						}
					}
					
					free(bytes);
				}
			}
			
			if (searchData->shouldCancelSearch)
			{
				searchData->searchDidCancel = YES;
				return;
			}
			
			currentRegionNumber++;
			address += size;
		}
		
		if (task != MACH_PORT_NULL)
		{
			mach_port_deallocate(current_task(), task);
		}
	}
}

ZGMemorySize ZGGetStringSize(pid_t process, ZGMemoryAddress address, ZGVariableType dataType)
{
	ZGMemorySize totalSize = 0;
	vm_map_t task = MACH_PORT_NULL;
	
	@try
	{
		if (task_for_pid(current_task(), process, &task) == KERN_SUCCESS)
		{
			ZGMemorySize characterSize = dataType == ZGUTF8String ? sizeof(char) : sizeof(unichar);
			void *theByte = malloc((size_t)characterSize);
			
			if (theByte)
			{
				while (YES)
				{
					ZGMemorySize outputtedSize = characterSize;
					
					if (mach_vm_read_overwrite(task, address, characterSize, (ZGMemoryAddress)theByte, &outputtedSize) == KERN_SUCCESS)
					{
						if ((dataType == ZGUTF8String && *((char *)theByte) == 0) || (dataType == ZGUTF16String && *((unichar *)theByte) == 0))
						{
							// Only count the null terminator for a UTF-8 string.
							if (dataType == ZGUTF8String)
							{
								totalSize += characterSize;
							}
							break;
						}
					}
					else
					{
						totalSize = 0;
						break;
					}
					
					totalSize += characterSize;
					address += characterSize;
				}
				
				free(theByte);
			}
		}
	}
	@catch (NSException *exception)
	{
		totalSize = 0;
	}
	
	if (task != MACH_PORT_NULL)
	{
		mach_port_deallocate(current_task(), task);
	}
	
	return totalSize;
}

BOOL ZGPauseProcess(pid_t process)
{
	return kill(process, SIGSTOP) == 0;
}

BOOL ZGUnpauseProcess(pid_t process)
{
	return kill(process, SIGCONT) == 0;
}
