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
#import "NSArrayAdditions.h"

@implementation ZGRegion
@end

@interface ZGResultsWrapper : NSObject
@property (nonatomic, strong) NSArray *results;
@end

@implementation ZGResultsWrapper
@end

static NSDictionary *gTasksDictionary = nil;

BOOL ZGTaskExistsForProcess(pid_t process, ZGMemoryMap *task)
{
	*task = MACH_PORT_NULL;
	if (gTasksDictionary)
	{
		*task = [[gTasksDictionary objectForKey:@(process)] unsignedIntValue];
	}
	return MACH_PORT_VALID(*task);
}

BOOL ZGGetTaskForProcess(pid_t process, ZGMemoryMap *task)
{
	if (!gTasksDictionary)
	{
		gTasksDictionary = [[NSDictionary alloc] init];
	}
	
	BOOL success = YES;
	
	if (!ZGTaskExistsForProcess(process, task))
	{
		kern_return_t result = task_for_pid(current_task(), process, task);
		if (result != KERN_SUCCESS)
		{
			*task = MACH_PORT_NULL;
			NSLog(@"Failed to get task for process %d: %s", process, mach_error_string(result));
			success = NO;
		}
		else if (!MACH_PORT_VALID(*task))
		{
			*task = MACH_PORT_NULL;
			NSLog(@"Mach port is not valid for process %d", process);
			success = NO;
		}
		else
		{
			NSMutableDictionary *newTasksDictionary = [[NSMutableDictionary alloc] initWithDictionary:gTasksDictionary];
			[newTasksDictionary setObject:@(*task) forKey:@(process)];
			gTasksDictionary = [NSDictionary dictionaryWithDictionary:newTasksDictionary];
		}
	}
	
	return success;
}

void ZGFreeTask(ZGMemoryMap task)
{
	for (id process in gTasksDictionary.allKeys)
	{
		if ([@(task) isEqualToNumber:[gTasksDictionary objectForKey:process]])
		{
			NSMutableDictionary *newTasksDictionary = [[NSMutableDictionary alloc] initWithDictionary:gTasksDictionary];
			[newTasksDictionary removeObjectForKey:process];
			gTasksDictionary = [NSDictionary dictionaryWithDictionary:newTasksDictionary];
			
			break;
		}
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

BOOL ZGWriteBytesIgnoringProtection(ZGMemoryMap processTask, ZGMemoryAddress address, const void *bytes, ZGMemorySize size)
{
	ZGMemoryAddress protectionAddress = address;
	ZGMemorySize protectionSize = size;
	ZGMemoryProtection oldProtection = 0;
	
	if (!ZGMemoryProtectionInRegion(processTask, &protectionAddress, &protectionSize, &oldProtection))
	{
		return NO;
	}
	
	if (!(oldProtection & VM_PROT_WRITE))
	{
		if (!ZGProtect(processTask, protectionAddress, protectionSize, oldProtection | VM_PROT_WRITE))
		{
			return NO;
		}
	}
	
	BOOL success = ZGWriteBytes(processTask, address, bytes, size);
	
	// Re-protect the region back to the way it was
	if (!(oldProtection & VM_PROT_WRITE))
	{
		ZGProtect(processTask, protectionAddress, protectionSize, oldProtection);
	}
	
	return success;
}

BOOL ZGMemoryProtectionInRegion(ZGMemoryMap processTask, ZGMemoryAddress *address, ZGMemorySize *size, ZGMemoryProtection *memoryProtection)
{
	BOOL success = NO;
	
	mach_port_t objectName = MACH_PORT_NULL;
	vm_region_basic_info_data_64_t regionInfo;
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

void *ZGSavedValue(ZGMemoryAddress address, ZGSearchData * __unsafe_unretained searchData, ZGRegion **hintedRegionReference, ZGMemorySize dataSize)
{
	// Use a binary search
	
	void *value = NULL;
	
	ZGRegion *hintedRegion = (hintedRegionReference && *hintedRegionReference) ? *hintedRegionReference : nil;
	if (hintedRegion && address >= hintedRegion.address && address + dataSize <= hintedRegion.address + hintedRegion.size)
	{
		value = hintedRegion.bytes + (address - hintedRegion.address);
	}
	else
	{
		NSArray *regions = searchData.savedData;
		
		NSUInteger maxIndex = regions.count - 1;
		NSUInteger minIndex = 0;
		
		while (maxIndex >= minIndex)
		{
			NSUInteger midIndex = (maxIndex + minIndex) / 2;
			ZGRegion *region = [regions objectAtIndex:midIndex];
			
			ZGMemoryAddress regionAddress = region.address;
			ZGMemorySize regionSize = region.size;
			
			if (address >= regionAddress + regionSize)
			{
				minIndex = midIndex + 1;
			}
			else if (address + dataSize <= regionAddress)
			{
				if (midIndex == 0) break;
				maxIndex = midIndex - 1;
			}
			else
			{
				// Found match
				if (address >= regionAddress && address + dataSize <= regionAddress + regionSize)
				{
					value = region.bytes + (address - regionAddress);
					if (hintedRegionReference)
					{
						*hintedRegionReference = region;
					}
					break;
				}
			}
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

NSArray *ZGSearchForSavedData(ZGMemoryMap processTask, ZGSearchData * __unsafe_unretained searchData, search_for_data_t searchForDataBlock, search_for_data_update_progress_t updateProgressBlock)
{
	ZGInitializeSearch(searchData);
	
	ZGMemorySize dataAlignment = searchData.dataAlignment;
	ZGMemorySize dataSize = searchData.dataSize;
	ZGMemoryAddress dataBeginAddress = searchData.beginAddress;
	ZGMemoryAddress dataEndAddress = searchData.endAddress;
	
	NSMutableArray *resultsWrapperArray = [[NSMutableArray alloc] init];
	for (NSUInteger regionIndex = 0; regionIndex < searchData.savedData.count; regionIndex++)
	{
		[resultsWrapperArray addObject:[[ZGResultsWrapper alloc] init]];
	}
	
	__block ZGMemorySize numberOfRegionsProcessed = 0;
	
	dispatch_apply(searchData.savedData.count, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t regionIndex) {
		ZGRegion *region = [searchData.savedData objectAtIndex:regionIndex];
		
		ZGResultsWrapper *resultsWrapper = [resultsWrapperArray objectAtIndex:regionIndex];
		NSMutableArray *localResults = [[NSMutableArray alloc] init];
		
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
			while (offset + dataSize <= size && !searchData->_shouldCancelSearch)
			{
				if (dataBeginAddress <= regionAddress + offset &&
					dataEndAddress >= regionAddress + offset + dataSize)
				{
					searchForDataBlock(searchData, &currentData[offset], regionBytes + offset, regionAddress + offset, localResults);
				}
				offset += dataAlignment;
			}
			
			ZGFreeBytes(processTask, currentData, size);
		}
		
		resultsWrapper.results = localResults;
		
		if (searchData->_shouldCancelSearch)
		{
			searchData.searchDidCancel = YES;
		}
		
		dispatch_async(dispatch_get_main_queue(), ^{
			numberOfRegionsProcessed++;
			updateProgressBlock(localResults, numberOfRegionsProcessed);
		});
	});
	
	NSMutableArray *allResults = [[NSMutableArray alloc] init];
	
	for (ZGResultsWrapper *taggedResults in resultsWrapperArray)
	{
		[allResults addObjectsFromArray:taggedResults.results];
	}
	
	return allResults;
}

NSArray *ZGSearchForData(ZGMemoryMap processTask, ZGSearchData * __unsafe_unretained searchData, search_for_data_t searchForDataBlock, search_for_data_update_progress_t updateProgressBlock)
{
	ZGInitializeSearch(searchData);
	
	ZGMemorySize dataAlignment = searchData.dataAlignment;
	ZGMemorySize dataSize = searchData.dataSize;
	
	ZGMemoryAddress dataBeginAddress = searchData.beginAddress;
	ZGMemoryAddress dataEndAddress = searchData.endAddress;
	BOOL shouldScanUnwritableValues = searchData.shouldScanUnwritableValues;
	
	NSArray *regions = ZGRegionsForProcessTask(processTask);
	
	__block ZGMemorySize numberOfRegionsProcessed = regions.count;
	
	regions = [regions zgFilterUsingBlock:(zg_array_filter_t)^(ZGRegion *region) {
		return !(region.address < dataEndAddress && region.address + region.size > dataBeginAddress && region.protection & VM_PROT_READ && (shouldScanUnwritableValues || (region.protection & VM_PROT_WRITE)));
	}];
	
	numberOfRegionsProcessed -= regions.count;
	
	NSMutableArray *resultsWrapperArray = [[NSMutableArray alloc] init];
	for (NSUInteger regionIndex = 0; regionIndex < regions.count; regionIndex++)
	{
		[resultsWrapperArray addObject:[[ZGResultsWrapper alloc] init]];
	}
	
	dispatch_apply(regions.count, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t regionIndex) {
		ZGRegion *region = [regions objectAtIndex:regionIndex];
		ZGMemoryAddress address = region.address;
		ZGMemorySize size = region.size;
		
		ZGResultsWrapper *resultsWrapper = [resultsWrapperArray objectAtIndex:regionIndex];
		NSMutableArray *localResults = [[NSMutableArray alloc] init];
		
		char *bytes = NULL;
		if (ZGReadBytes(processTask, address, (void **)&bytes, &size))
		{
			ZGMemorySize dataIndex = 0;
			while (dataIndex + dataSize <= size && !searchData->_shouldCancelSearch)
			{
				if (dataBeginAddress <= address + dataIndex &&
					dataEndAddress >= address + dataIndex + dataSize)
				{
					searchForDataBlock(searchData, &bytes[dataIndex], NULL, address + dataIndex, localResults);
				}
				dataIndex += dataAlignment;
			}
			
			ZGFreeBytes(processTask, bytes, size);
		}
		
		if (searchData->_shouldCancelSearch)
		{
			if (!searchData->_searchDidCancel)
			{
				searchData.searchDidCancel = YES;
			}
		}
		
		resultsWrapper.results = localResults;
		
		dispatch_async(dispatch_get_main_queue(), ^{
			numberOfRegionsProcessed++;
			updateProgressBlock(localResults, numberOfRegionsProcessed);
		});
	});
	
	NSMutableArray *allResults = [[NSMutableArray alloc] init];
	
	for (ZGResultsWrapper *resultsWrapper in resultsWrapperArray)
	{
		[allResults addObjectsFromArray:resultsWrapper.results];
	}
	
	return allResults;
}

#define MAX_STRING_SIZE 1024
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
			
			if (totalSize >= MAX_STRING_SIZE)
			{
				totalSize = MAX_STRING_SIZE;
				shouldBreak = YES;
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

BOOL ZGSuspendCount(ZGMemoryMap processTask, integer_t *suspendCount)
{
	*suspendCount = -1;
	task_basic_info_64_data_t taskInfo;
	mach_msg_type_number_t count = TASK_BASIC_INFO_64_COUNT;
	
	BOOL success = (task_info(processTask, TASK_BASIC_INFO_64, (task_info_t)&taskInfo, &count) == KERN_SUCCESS);
	if (success)
	{
		*suspendCount = taskInfo.suspend_count;
	}
	
	return success;
}

BOOL ZGSuspendTask(ZGMemoryMap processTask)
{
	return (task_suspend(processTask) == KERN_SUCCESS);
}

BOOL ZGResumeTask(ZGMemoryMap processTask)
{
	return (task_resume(processTask) == KERN_SUCCESS);
}
