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

#import "ZGVirtualMemory.h"
#import "ZGProcess.h"
#import "ZGSearchData.h"

@implementation ZGRegion
@end

BOOL ZGGetTaskForProcess(pid_t process, ZGMemoryMap *task)
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

NSArray *ZGRegionsForProcessTask(ZGMemoryMap processTask)
{
	NSMutableArray *regions = [[NSMutableArray alloc] init];
	
	ZGMemoryAddress address = 0x0;
	ZGMemorySize size;
	vm_region_basic_info_data_64_t info;
	mach_msg_type_number_t infoCount = VM_REGION_BASIC_INFO_COUNT_64;
	mach_port_t objectName = MACH_PORT_NULL;
	
	while (mach_vm_region(processTask, &address, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &infoCount, &objectName) == KERN_SUCCESS)
	{
		ZGRegion *region = [[ZGRegion alloc] init];
		region.address = address;
		region.size = size;
		region.protection = info.protection;
		
		[regions addObject:region];
		
		address += size;
	}
	
	return [NSArray arrayWithArray:regions];
}

NSUInteger ZGNumberOfRegionsForProcessTask(ZGMemoryMap processTask)
{	
	return [ZGRegionsForProcessTask(processTask) count];
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
			}
		}
		
		address += size;
		
		process.searchProgress++;
		
		if (!process.isStoringAllData)
		{
			ZGFreeData(dataArray);
			dataArray = nil;
			break;
		}
	}
	
	return dataArray;
}

void *ZGSavedValue(ZGMemoryAddress address, ZGSearchData * __unsafe_unretained searchData, ZGMemorySize dataSize)
{
	void *value = NULL;
	
	for (ZGRegion *region in searchData.savedData)
	{
		ZGMemoryAddress regionAddress = region.address;
		if (address >= regionAddress && address + dataSize <= regionAddress + region.size)
		{
			value = region.bytes + (address - regionAddress);
			break;
		}
	}
	
	return value;
}

// helper function for ZGSaveAllDataToDirectory
static void ZGSavePieceOfData(NSMutableData *currentData, ZGMemoryAddress currentStartingAddress, NSString *directory, int *fileNumber, FILE *mergedFile)
{
	if (currentData)
	{
		ZGMemoryAddress endAddress = currentStartingAddress + [currentData length];
		(*fileNumber)++;
		[currentData
		 writeToFile:[directory stringByAppendingPathComponent:[[NSString alloc] initWithFormat:@"(%d) 0x%llX - 0x%llX", *fileNumber, currentStartingAddress, endAddress]]
		 atomically:NO];
		
		if (mergedFile)
		{
			fwrite(currentData.bytes, currentData.length, 1, mergedFile);
		}
	}
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

BOOL ZGSearchDidCancel(ZGSearchData * __unsafe_unretained searchData)
{
	return searchData->_searchDidCancel;
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

void ZGSearchForSavedData(ZGMemoryMap processTask, ZGMemorySize dataAlignment, ZGMemorySize dataSize, ZGSearchData * __unsafe_unretained searchData, search_for_data_t block)
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
		ZGMemoryAddress regionAddress = region.address;
		void *regionBytes = region.bytes;
		
		// Skipping an entire region will provide significant performance benefits
		if (regionAddress < dataEndAddress &&
			regionAddress + size > dataBeginAddress &&
			ZGReadBytes(processTask, regionAddress, (void **)&currentData, &size))
		{
			do
			{
				if (dataBeginAddress <= regionAddress + offset &&
					dataEndAddress >= regionAddress + offset + dataSize)
				{
					block(searchData, &currentData[offset], regionBytes + offset, regionAddress + offset, currentRegionNumber);
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

void ZGSearchForData(ZGMemoryMap processTask, ZGMemorySize dataAlignment, ZGMemorySize dataSize, ZGSearchData * __unsafe_unretained searchData, search_for_data_t block)
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

ZGMemorySize ZGGetStringSize(ZGMemoryMap processTask, ZGMemoryAddress address, ZGVariableType dataType, ZGMemorySize oldSize)
{
	ZGMemorySize totalSize = 0;
	
	ZGMemorySize characterSize = (dataType == ZGUTF8String) ? sizeof(char) : sizeof(unichar);
	void *buffer = NULL;
	
	if (dataType == ZGUTF16String && oldSize % 2 != 0)
	{
		oldSize--;
	}
	
	BOOL shouldUseOldSize = (oldSize >= characterSize);
	
	while (YES)
	{
		BOOL shouldBreak = NO;
		ZGMemorySize outputtedSize = shouldUseOldSize ? oldSize : characterSize;
		
		BOOL couldReadBytes = ZGReadBytes(processTask, address, &buffer, &outputtedSize);
		if (!couldReadBytes && shouldUseOldSize)
		{
			shouldUseOldSize = NO;
			continue;
		}
		
		if (couldReadBytes)
		{
			ZGMemorySize numberOfCharacters = outputtedSize / characterSize;
			if (dataType == ZGUTF16String && outputtedSize % 2 != 0 && numberOfCharacters > 0)
			{
				numberOfCharacters--;
				shouldBreak = YES;
			}
			
			for (ZGMemorySize characterCounter = 0; characterCounter < numberOfCharacters; characterCounter++)
			{
				if ((dataType == ZGUTF8String && ((char *)buffer)[characterCounter] == 0) || (dataType == ZGUTF16String && ((unichar *)buffer)[characterCounter] == 0))
				{
					// Only count the null terminator for a UTF-8 string, as long as the string has some length
					if (totalSize && dataType == ZGUTF8String)
					{
						totalSize += characterSize;
					}
					
					shouldBreak = YES;
					break;
				}
				
				totalSize += characterSize;
			}
			
			ZGFreeBytes(processTask, buffer, outputtedSize);
			
			if (dataType == ZGUTF16String)
			{
				outputtedSize = numberOfCharacters * characterSize;
			}
		}
		else
		{
			if (dataType == ZGUTF8String)
			{
				totalSize = 0;
			}
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

BOOL ZGPauseProcess(pid_t process)
{
	return kill(process, SIGSTOP) == 0;
}

BOOL ZGUnpauseProcess(pid_t process)
{
	return kill(process, SIGCONT) == 0;
}
