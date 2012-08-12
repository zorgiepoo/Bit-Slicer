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
#import "ZGSearchData.h"

@interface ZGRegion : NSObject

@property (assign, nonatomic) ZGMemoryMap processTask;
@property (assign, nonatomic) ZGMemoryAddress address;
@property (assign, nonatomic) ZGMemorySize size;
@property (assign, nonatomic) void *bytes;

@end

@implementation ZGRegion
@end

BOOL ZGIsProcessValid(pid_t process, ZGMemoryMap *task)
{
	*task = MACH_PORT_NULL;
	BOOL success = task_for_pid(current_task(), process, task) == KERN_SUCCESS;
	if (!success)
	{
		*task = MACH_PORT_NULL;
	}
	
	return success;
}

void ZGFreeTask(ZGMemoryMap task)
{
	if (mach_port_deallocate(current_task(), task) != KERN_SUCCESS)
	{
		NSLog(@"Failed to deallocate mach port");
	}
}

int ZGNumberOfRegionsForProcess(ZGMemoryMap processTask)
{
	int numberOfRegions = 0;
	ZGMemoryAddress address = 0x0;
	ZGMemorySize size;
	vm_region_basic_info_data_64_t info;
	mach_msg_type_number_t infoCount = VM_REGION_BASIC_INFO_COUNT_64;
	mach_port_t objectName = MACH_PORT_NULL;
	
	while (mach_vm_region(processTask, &address, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &infoCount, &objectName) == KERN_SUCCESS)
	{
		numberOfRegions++;
		address += size;
	}
	
	return numberOfRegions;
}

// ZGReadBytes allocates memory, the caller is responsible for deallocating it using ZGFreeBytes(...)
BOOL ZGReadBytes(ZGMemoryMap processTask, ZGMemoryAddress address, void **bytes, ZGMemorySize *size)
{
	ZGMemorySize originalSize = *size;
	vm_offset_t dataPointer = 0;
	mach_msg_type_number_t dataSize = 0;
	BOOL success = NO;
	if (mach_vm_read(processTask, address, originalSize, &dataPointer, &dataSize) == KERN_SUCCESS)
	{
		success = YES;
		*bytes = (void *)dataPointer;
		*size = dataSize;
	}
	
	return success;
}

void ZGFreeBytes(ZGMemoryMap processTask, const void *bytes, ZGMemorySize size)
{
	mach_vm_deallocate(current_task(), (vm_offset_t)bytes, size);
}

BOOL ZGWriteBytes(ZGMemoryMap processTask, ZGMemoryAddress address, const void *bytes, ZGMemorySize size)
{
	return (mach_vm_write(processTask, address, (vm_offset_t)bytes, (mach_msg_type_number_t)size) == KERN_SUCCESS);
}

BOOL ZGMemoryProtectionInRegion(ZGMemoryMap processTask, ZGMemoryAddress *address, ZGMemorySize *size, ZGMemoryProtection *memoryProtection)
{
	BOOL success = NO;
	
	mach_port_t objectName = MACH_PORT_NULL;
	vm_region_basic_info_data_t regionInfo;
	mach_msg_type_number_t regionInfoSize = VM_REGION_BASIC_INFO_COUNT_64;
	
	success = mach_vm_region(processTask, address, size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&regionInfo, &regionInfoSize, &objectName) == KERN_SUCCESS;
	
	if (success)
	{
		*memoryProtection = regionInfo.protection;
	}
	return success;
}

BOOL ZGProtect(ZGMemoryMap processTask, ZGMemoryAddress address, ZGMemorySize size, ZGMemoryProtection protection)
{
	return (mach_vm_protect(processTask, address, size, FALSE, protection) == KERN_SUCCESS);
}

// helper function for ZGSaveAllDataToDirectory
void ZGSavePieceOfData(NSMutableData *currentData, ZGMemoryAddress currentStartingAddress, NSString *directory, int *fileNumber, FILE *mergedFile)
{
	if (currentData)
	{
		ZGMemoryAddress endAddress = currentStartingAddress + [currentData length];
		(*fileNumber)++;
		[currentData
		 writeToFile:[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"(%d) 0x%llX - 0x%llX", *fileNumber, currentStartingAddress, endAddress]]
		 atomically:NO];
		
		if (mergedFile)
		{
			fwrite(currentData.bytes, currentData.length, 1, mergedFile);
		}
	}
}

void ZGFreeData(NSArray *dataArray)
{
	for (ZGRegion *memoryRegion in dataArray)
	{
		ZGFreeBytes(memoryRegion.processTask, memoryRegion.bytes, memoryRegion.size);
	}
}

NSArray *ZGGetAllData(ZGProcess *process, BOOL shouldScanUnwritableValues)
{
	NSMutableArray *dataArray = [[NSMutableArray alloc] init];
    
	ZGMemoryAddress address = 0x0;
	ZGMemorySize size;
	vm_region_basic_info_data_64_t regionInfo;
	mach_msg_type_number_t infoCount = VM_REGION_BASIC_INFO_COUNT_64;
	mach_port_t objectName = MACH_PORT_NULL;
	
	process.isStoringAllData = YES;
	process.searchProgress = 0;
	
	while (mach_vm_region(process.processTask, &address, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&regionInfo, &infoCount, &objectName) == KERN_SUCCESS)
	{
		if ((regionInfo.protection & VM_PROT_READ) && (shouldScanUnwritableValues || (regionInfo.protection & VM_PROT_WRITE)))
		{
			void *bytes = NULL;
			if (ZGReadBytes(process.processTask, address, &bytes, &size))
			{
				ZGRegion *memoryRegion = [[ZGRegion alloc] init];
				memoryRegion.processTask = process.processTask;
				memoryRegion.bytes = bytes;
				memoryRegion.address = address;
				memoryRegion.size = size;
				
				[dataArray addObject:memoryRegion];
				[memoryRegion release];
			}
		}
		
		address += size;
		
		process.searchProgress++;
		
		if (!process.isStoringAllData)
		{
			ZGFreeData(dataArray);
			
			[dataArray release];
			dataArray = nil;
			break;
		}
	}
	
	return [dataArray autorelease];
}

void *ZGSavedValue(ZGMemoryAddress address, ZGSearchData *searchData, ZGMemorySize dataSize)
{
	void *value = NULL;
	
	for (ZGRegion *region in searchData.savedData)
	{
		if (address >= region.address && address + dataSize <= region.address + region.size)
		{
			value = region.bytes + (address - region.address);
			break;
		}
	}
	
	return value;
}

BOOL ZGSaveAllDataToDirectory(NSString *directory, ZGProcess *process)
{
	BOOL success = NO;
	
	ZGMemoryAddress address = 0x0;
	ZGMemoryAddress lastAddress = address;
	ZGMemorySize size;
	vm_region_basic_info_data_64_t regionInfo;
	mach_msg_type_number_t infoCount = VM_REGION_BASIC_INFO_COUNT_64;
	mach_port_t objectName = MACH_PORT_NULL;
	
	NSMutableData *currentData = nil;
	ZGMemoryAddress currentStartingAddress = address;
	int fileNumber = 0;
	
	FILE *mergedFile = fopen([directory stringByAppendingPathComponent:@"(All) Merged"].UTF8String, "w");
	
	process.isDoingMemoryDump = YES;
	process.searchProgress = 0;
    
	while (mach_vm_region(process.processTask, &address, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&regionInfo, &infoCount, &objectName) == KERN_SUCCESS)
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
			
			// outputSize should not differ from size
			ZGMemorySize outputSize = size;
			void *bytes = NULL;
			if (ZGReadBytes(process.processTask, address, &bytes, &outputSize))
			{
				[currentData appendBytes:bytes length:(NSUInteger)size];
				ZGFreeBytes(process.processTask, bytes, outputSize);
			}
		}
		
		address += size;
		lastAddress = address;
		
		process.searchProgress++;
  	    
		if (!process.isDoingMemoryDump)
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
	
	return success;
}

void ZGInitializeSearch(ZGSearchData *searchData)
{
	searchData.shouldCancelSearch = NO;
	searchData.searchDidCancel = NO;
}

void ZGCancelSearchImmediately(ZGSearchData *searchData)
{
	searchData.shouldCancelSearch = YES;
	searchData.searchDidCancel = YES;
}

void ZGCancelSearch(ZGSearchData *searchData)
{
	searchData.shouldCancelSearch = YES;
}

BOOL ZGSearchIsCancelling(ZGSearchData *searchData)
{
	return searchData.shouldCancelSearch;
}

BOOL ZGSearchDidCancelSearch(ZGSearchData *searchData)
{
	return searchData.searchDidCancel;
}

ZGMemorySize ZGDataAlignment(BOOL isProcess64Bit, ZGVariableType dataType, ZGMemorySize dataSize)
{
	ZGMemorySize dataAlignment;
	
	if (dataType == ZGUTF8String || dataType == ZGByteArray)
	{
		dataAlignment = sizeof(int8_t);
	}
	else if (dataType == ZGUTF16String)
	{
		dataAlignment = sizeof(int16_t);
	}
	else
	{
		// doubles and 64-bit integers are on 4 byte boundaries only in 32-bit processes, while every other integral type is on its own size of boundary
		dataAlignment = (!isProcess64Bit && dataSize == sizeof(int64_t)) ? sizeof(int32_t) : dataSize;
	}
	
	return dataAlignment;
}

void ZGSearchForSavedData(ZGMemoryMap processTask, ZGMemorySize dataAlignment, ZGMemorySize dataSize, ZGSearchData *searchData, search_for_data_t block)
{
	ZGInitializeSearch(searchData);
	
	ZGMemoryAddress dataBeginAddress = searchData.beginAddress;
	ZGMemoryAddress dataEndAddress = searchData.endAddress;
	
	int currentRegionNumber = 0;
	
	for (ZGRegion *region in searchData.savedData)
	{
		ZGMemoryAddress offset = 0;
		char *currentData = NULL;
		ZGMemorySize size = region.size;
		
		// Skipping an entire region will provide significant performance benefits
		if (region.address < dataEndAddress &&
			region.address + size > dataBeginAddress &&
			ZGReadBytes(processTask, region.address, (void **)&currentData, &size))
		{
			do
			{
				if (dataBeginAddress <= region.address + offset &&
					dataEndAddress >= region.address + offset + dataSize)
				{
					block(searchData, &currentData[offset], region.bytes + offset, region.address + offset, currentRegionNumber);
				}
				offset += dataAlignment;
			}
			while (offset + dataSize <= size && !searchData->_shouldCancelSearch);
			
			ZGFreeBytes(processTask, currentData, size);
		}
		
		if (searchData->_shouldCancelSearch)
		{
			searchData.searchDidCancel = YES;
			return;
		}
		
		currentRegionNumber++;
	}
}

void ZGSearchForData(ZGMemoryMap processTask, ZGMemorySize dataAlignment, ZGMemorySize dataSize, ZGSearchData *searchData, search_for_data_t block)
{
	ZGInitializeSearch(searchData);
	
	ZGMemoryAddress address = 0x0;
	ZGMemorySize size;
	mach_port_t objectName = MACH_PORT_NULL;
	vm_region_basic_info_data_t regionInfo;
	mach_msg_type_number_t regionInfoSize = VM_REGION_BASIC_INFO_COUNT_64;

	ZGMemorySize currentRegionNumber = 0;
	
	ZGMemoryAddress dataBeginAddress = searchData.beginAddress;
	ZGMemoryAddress dataEndAddress = searchData.endAddress;
	BOOL shouldScanUnwritableValues = searchData.shouldScanUnwritableValues;
	
	while (mach_vm_region(processTask, &address, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&regionInfo, &regionInfoSize, &objectName) == KERN_SUCCESS)
	{
		// Skipping an entire region will provide significant performance benefits
		if (address < dataEndAddress &&
			address + size > dataBeginAddress &&
			regionInfo.protection & VM_PROT_READ && (shouldScanUnwritableValues || (regionInfo.protection & VM_PROT_WRITE)))
		{
			char *bytes = NULL;
			if (ZGReadBytes(processTask, address, (void **)&bytes, &size))
			{
				ZGMemorySize dataIndex = 0;
				while (dataIndex + dataSize <= size && !searchData->_shouldCancelSearch)
				{
					if (dataBeginAddress <= address + dataIndex &&
						dataEndAddress >= address + dataIndex + dataSize)
					{
						block(searchData, &bytes[dataIndex], NULL, address + dataIndex, currentRegionNumber);
					}
					dataIndex += dataAlignment;
				}
				
				ZGFreeBytes(processTask, bytes, size);
			}
		}
		
		if (searchData->_shouldCancelSearch)
		{
			searchData.searchDidCancel = YES;
			return;
		}
		
		currentRegionNumber++;
		address += size;
	}
}

ZGMemorySize ZGGetStringSize(ZGMemoryMap processTask, ZGMemoryAddress address, ZGVariableType dataType)
{
	ZGMemorySize totalSize = 0;
	
	ZGMemorySize characterSize = dataType == ZGUTF8String ? sizeof(char) : sizeof(unichar);
	void *theByte = NULL;
	
	while (YES)
	{
		BOOL shouldBreak = NO;
		ZGMemorySize outputtedSize = characterSize;
		
		if (ZGReadBytes(processTask, address, &theByte, &outputtedSize))
		{
			if ((dataType == ZGUTF8String && *((char *)theByte) == 0) || (dataType == ZGUTF16String && *((unichar *)theByte) == 0))
			{
				// Only count the null terminator for a UTF-8 string, as long as the string has some length
				if (totalSize && dataType == ZGUTF8String)
				{
					totalSize += characterSize;
				}
				
				shouldBreak = YES;
			}
			
			ZGFreeBytes(processTask, theByte, outputtedSize);
		}
		else
		{
			totalSize = 0;
			shouldBreak = YES;
		}
		
		if (shouldBreak)
		{
			break;
		}
		
		totalSize += characterSize;
		address += characterSize;
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
