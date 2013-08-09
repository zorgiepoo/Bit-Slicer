//
//  ZGVirtualMemoryHelpers.m
//  Bit Slicer
//
//  Created by Mayur Pawashe on 8/9/13.
//
//

#import "ZGVirtualMemoryHelpers.h"
#import "ZGVirtualMemory.h"
#import "ZGRegion.h"
#import "ZGSearchProgress.h"
#import "ZGSearchData.h"
#import "NSArrayAdditions.h"

#import <mach/mach_error.h>
#import <mach/mach_vm.h>

static NSDictionary *gTasksDictionary = nil;

BOOL ZGTaskExistsForProcess(pid_t process, ZGMemoryMap *task)
{
	*task = MACH_PORT_NULL;
	if (gTasksDictionary)
	{
		*task = [[gTasksDictionary objectForKey:@(process)] unsignedIntValue];
	}
	return *task != MACH_PORT_NULL;
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
		if (!ZGTaskPortForPID(process, task))
		{
			if (*task != MACH_PORT_NULL)
			{
				ZGDeallocatePort(*task);
			}
			*task = MACH_PORT_NULL;
			success = NO;
		}
		else if (!MACH_PORT_VALID(*task))
		{
			if (*task != MACH_PORT_NULL)
			{
				ZGDeallocatePort(*task);
			}
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
			
			ZGDeallocatePort(task);
			
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

NSArray *ZGGetAllData(ZGMemoryMap processTask, ZGSearchData *searchData, ZGSearchProgress *searchProgress)
{
	NSMutableArray *dataArray = [[NSMutableArray alloc] init];
	BOOL shouldScanUnwritableValues = searchData.shouldScanUnwritableValues;
	
	NSArray *regions = [ZGRegionsForProcessTask(processTask) zgFilterUsingBlock:(zg_array_filter_t)^(ZGRegion *region) {
		return !(region.protection & VM_PROT_READ && (shouldScanUnwritableValues || (region.protection & VM_PROT_WRITE)));
	}];
	
	dispatch_async(dispatch_get_main_queue(), ^{
		searchProgress.initiatedSearch = YES;
		searchProgress.progressType = ZGSearchProgressMemoryStoring;
		searchProgress.maxProgress = regions.count;
	});
	
	for (ZGRegion *region in regions)
	{
		void *bytes = NULL;
		ZGMemorySize size = region.size;
		
		if (ZGReadBytes(processTask, region.address, &bytes, &size))
		{
			region.bytes = bytes;
			region.size = size;
			
			[dataArray addObject:region];
		}
		
		if (searchProgress.shouldCancelSearch)
		{
			ZGFreeData(dataArray);
			dataArray = nil;
			break;
		}
		
		dispatch_async(dispatch_get_main_queue(), ^{
			searchProgress.progress++;
		});
	}
	
	return dataArray;
}

void ZGFreeData(NSArray *dataArray)
{
	for (ZGRegion *memoryRegion in dataArray)
	{
		ZGFreeBytes(memoryRegion.processTask, memoryRegion.bytes, memoryRegion.size);
	}
}

void *ZGSavedValue(ZGMemoryAddress address, ZGSearchData * __unsafe_unretained searchData, ZGRegion **hintedRegionReference, ZGMemorySize dataSize)
{
	void *value = NULL;
	
	ZGRegion * __unsafe_unretained hintedRegion = (hintedRegionReference && *hintedRegionReference) ? *hintedRegionReference : nil;
	if (hintedRegion && address >= hintedRegion->_address && address + dataSize <= hintedRegion->_address + hintedRegion->_size)
	{
		value = hintedRegion->_bytes + (address - hintedRegion->_address);
	}
	else
	{
		NSArray *regions = searchData.savedData;
		ZGRegion *targetRegion = [regions zgBinarySearchUsingBlock:(zg_binary_search_t)^(ZGRegion * __unsafe_unretained region) {
			if (region->_address + region->_size <= address)
			{
				return NSOrderedAscending;
			}
			else if (region->_address >= address + dataSize)
			{
				return NSOrderedDescending;
			}
			else
			{
				return NSOrderedSame;
			}
		}];
		
		if (targetRegion && address >= targetRegion->_address && address + dataSize <= targetRegion->_address + targetRegion->_size)
		{
			value = targetRegion->_bytes + (address - targetRegion->_address);
			if (hintedRegionReference)
			{
				*hintedRegionReference = targetRegion;
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

BOOL ZGSaveAllDataToDirectory(NSString *directory, ZGMemoryMap processTask, ZGSearchProgress *searchProgress)
{
	BOOL success = NO;
	
	NSMutableData *currentData = nil;
	ZGMemoryAddress currentStartingAddress = 0;
	ZGMemoryAddress lastAddress = currentStartingAddress;
	int fileNumber = 0;
	
	FILE *mergedFile = fopen([directory stringByAppendingPathComponent:@"(All) Merged"].UTF8String, "w");
	
	NSArray *regions = ZGRegionsForProcessTask(processTask);
	
	dispatch_async(dispatch_get_main_queue(), ^{
		searchProgress.initiatedSearch = YES;
		searchProgress.progressType = ZGSearchProgressMemoryDumping;
		searchProgress.maxProgress = regions.count;
	});
	
	for (ZGRegion *region in regions)
	{
		if (lastAddress != region.address || !(region.protection & VM_PROT_READ))
		{
			// We're done with this piece of data
			ZGSavePieceOfData(currentData, currentStartingAddress, directory, &fileNumber, mergedFile);
			currentData = nil;
		}
		
		if (region.protection & VM_PROT_READ)
		{
			if (!currentData)
			{
				currentData = [[NSMutableData alloc] init];
				currentStartingAddress = region.address;
			}
			
			// outputSize should not differ from size
			ZGMemorySize outputSize = region.size;
			void *bytes = NULL;
			if (ZGReadBytes(processTask, region.address, &bytes, &outputSize))
			{
				[currentData appendBytes:bytes length:(NSUInteger)outputSize];
				ZGFreeBytes(processTask, bytes, outputSize);
			}
		}
		
		lastAddress = region.address;
		
		dispatch_async(dispatch_get_main_queue(), ^{
			searchProgress.progress++;
		});
  	    
		if (searchProgress.shouldCancelSearch)
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
