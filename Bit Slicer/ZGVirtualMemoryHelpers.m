/*
 * Created by Mayur Pawashe on 8/9/13.
 *
 * Copyright (c) 2013 zgcoder
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

#import "ZGVirtualMemoryHelpers.h"
#import "ZGVirtualMemory.h"
#import "ZGRegion.h"
#import "ZGSearchProgress.h"
#import "ZGSearchData.h"
#import "NSArrayAdditions.h"

#import <mach/mach_error.h>
#import <mach/mach_vm.h>

#import <libproc.h>

#import <mach-o/loader.h>

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

// proc_regionfilename is not quite perfect
// In particular if you have a few regions like so:
// __TEXT 0x1000 - 0x2000
// __TEXT 0x2000 - 0x3000
// __DATA 0x3000 - 0x4000
// __LINKEDIT 0x4000 - 0x5000
// __LINKEDIT 0x5000 - 0x6000
// From observation, only the *first* unique type of segment listed will return a filepath
// That is, the 2nd __TEXT and 2nd __LINKEDIT using proc_regionfilename won't give same path
// We can't make an assumption on protection (initial or not) attributes (following regions don't have to be same)
// And I do not know how to get the segment type (it's not user_tag or object_id).. So, I am just going to fill in gaps for regions where paths before and after are defined
// This is not perfect since it may not retrieve the path of the last trailing regions
// However for our purposes this may be good enough since I am primarily interested in __TEXT and __DATA for now, and hope that __LINKEDIT will usually follow after
NSString *ZGFilePathForRegionHelper(BOOL canRedeemSelf, ZGMemoryMap processTask, ZGRegion *region)
{
	NSString *result = nil;
	int processID = 0;
	if (ZGPIDForTaskPort(processTask, &processID))
	{
		ZGPIDForTaskPort(processTask, &processID);
		void *filePath = calloc(1, PATH_MAX);
		if (proc_regionfilename(processID, region.address, filePath, PATH_MAX) > 0) // Returns # of bytes read
		{
			result = [NSString stringWithUTF8String:filePath];
		}
		else if (canRedeemSelf)
		{
			ZGMemoryAddress regionAddress = region.address - 1;
			ZGMemorySize regionSize = 1;
			ZGMemoryBasicInfo unusedInfo;
			
			ZGRegion *previousRegion = nil;
			ZGRegion *nextRegion = nil;
			
			if (!ZGRegionInfo(processTask, &regionAddress, &regionSize, &unusedInfo) || regionAddress + regionSize != region.address)
			{
				goto SKIP_NEXT_AND_PREVIOUS_REGIONS;
			}
			
			previousRegion = [[ZGRegion alloc] init];
			previousRegion.address	 = regionAddress;
			previousRegion.size = regionSize;
			
			regionAddress = region.address + region.size;
			regionSize = 1;
			if (!ZGRegionInfo(processTask, &regionAddress, &regionSize, &unusedInfo) || region.address + region.size != regionAddress)
			{
				goto SKIP_NEXT_AND_PREVIOUS_REGIONS;
			}
			
			nextRegion = [[ZGRegion alloc] init];
			nextRegion.address = regionAddress;
			nextRegion.size = regionSize;
			
			NSString *previousRegionFilePath = ZGFilePathForRegionHelper(NO, processTask, previousRegion);
			if (previousRegionFilePath == nil) goto SKIP_NEXT_AND_PREVIOUS_REGIONS;
			
			NSString *nextRegionFilePath = ZGFilePathForRegionHelper(NO, processTask, nextRegion);
			if ([nextRegionFilePath isEqualToString:previousRegionFilePath])
			{
				result = nextRegionFilePath;
			}
		}
	SKIP_NEXT_AND_PREVIOUS_REGIONS:
		free(filePath);
	}
	return result;
}

NSString *ZGFilePathForRegion(ZGMemoryMap processTask, ZGRegion *region)
{
	return ZGFilePathForRegionHelper(YES, processTask, region);
}

NSArray *ZGRegionsForProcessTask(ZGMemoryMap processTask)
{
	NSMutableArray *regions = [[NSMutableArray alloc] init];
	
	ZGMemoryAddress address = 0x0;
	ZGMemorySize size;
	vm_region_basic_info_data_64_t info;
	mach_msg_type_number_t infoCount;
	mach_port_t objectName = MACH_PORT_NULL;
	
	while (1)
	{
		infoCount = VM_REGION_BASIC_INFO_COUNT_64;
		if (mach_vm_region(processTask, &address, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &infoCount, &objectName) != KERN_SUCCESS)
		{
			break;
		}
		
		ZGRegion *region = [[ZGRegion alloc] init];
		region.address = address;
		region.size = size;
		region.protection = info.protection;
		
		[regions addObject:region];
		
		address += size;
	}
	
	return [NSArray arrayWithArray:regions];
}

NSArray *ZGRegionsForProcessTaskRecursively(ZGMemoryMap processTask)
{
	NSMutableArray *regions = [[NSMutableArray alloc] init];
	
	ZGMemoryAddress address = 0x0;
	ZGMemorySize size;
	vm_region_submap_info_data_64_t info;
	mach_msg_type_number_t infoCount;
	natural_t depth = 0;
	
	while (1)
	{
		infoCount = VM_REGION_SUBMAP_INFO_COUNT_64;
		if (mach_vm_region_recurse(processTask, &address, &size, &depth, (vm_region_recurse_info_t)&info, &infoCount) != KERN_SUCCESS)
		{
			break;
		}
		
		if (info.is_submap)
		{
			depth++;
		}
		else
		{
			ZGRegion *region = [[ZGRegion alloc] init];
			region.address = address;
			region.size = size;
			
			address += size;
		}
	}
	
	return [NSArray arrayWithArray:regions];
}

NSUInteger ZGNumberOfRegionsForProcessTask(ZGMemoryMap processTask)
{
	return [ZGRegionsForProcessTask(processTask) count];
}

ZGRegion *ZGBaseExecutableRegion(ZGMemoryMap taskPort)
{
	// Obtain first __TEXT region
	ZGRegion *chosenRegion = nil;
	for (ZGRegion *region in ZGRegionsForProcessTask(taskPort))
	{
		if (region.protection & VM_PROT_READ && region.protection & VM_PROT_EXECUTE)
		{
			chosenRegion = region;
			break;
		}
	}
	return chosenRegion;
}

#define ZGFindTextAddressInSegment(segment_type, section_type, bail_label, bytes, textAddress) \
struct segment_type *segmentCommand = bytes; \
if (strcmp(segmentCommand->segname, "__TEXT") == 0) \
{ \
	void *sectionBytes = bytes + sizeof(*segmentCommand); \
	for (struct section_type *section = sectionBytes; (void *)section < sectionBytes + segmentCommand->cmdsize; section++) \
	{ \
		if (strcmp("__text", section->sectname) == 0) \
		{ \
			textAddress += section->offset; \
			goto bail_label; \
		} \
	} \
}

ZGMemoryAddress ZGFirstInstructionAddress(ZGMemoryMap taskPort, ZGRegion *region)
{
	ZGMemoryAddress regionAddress = region.address;
	ZGMemorySize regionSize = region.size;
	
	// Find first __TEXT region by using the mapped file path
	NSString *filePathMappedToRegion = ZGFilePathForRegion(taskPort, region);
	if (filePathMappedToRegion != nil)
	{
		for (ZGRegion *theRegion in ZGRegionsForProcessTask(taskPort))
		{
			if ([ZGFilePathForRegionHelper(NO, taskPort, theRegion) isEqualToString:filePathMappedToRegion])
			{
				regionAddress = theRegion.address;
				regionSize = theRegion.size;
				break;
			}
		}
	}
	
	ZGMemoryAddress textAddress = regionAddress; // good default
	
	void *regionBytes = NULL;
	if (regionAddress > 0 && ZGReadBytes(taskPort, regionAddress, &regionBytes, &regionSize))
	{
		void *bytes = regionBytes;
		struct mach_header_64 *machHeader = bytes;
		if (machHeader->magic == MH_MAGIC || machHeader->magic == MH_MAGIC_64)
		{
			bytes += (machHeader->magic == MH_MAGIC) ? sizeof(struct mach_header) : sizeof(struct mach_header_64);
			
			if ((bytes - regionBytes) + (ZGMemorySize)machHeader->sizeofcmds <= regionSize)
			{
				for (uint32_t commandIndex = 0; commandIndex < machHeader->ncmds; commandIndex++)
				{
					struct load_command *loadCommand = bytes;
					if (loadCommand->cmd == LC_SEGMENT_64)
					{
						ZGFindTextAddressInSegment(segment_command_64, section_64, ZGFirstInstructionAddressBail, bytes, textAddress);
					}
					else if (loadCommand->cmd == LC_SEGMENT)
					{
						ZGFindTextAddressInSegment(segment_command, section, ZGFirstInstructionAddressBail, bytes, textAddress);
					}
					
					bytes += loadCommand->cmdsize;
				}
			}
		}
		
	ZGFirstInstructionAddressBail:
		ZGFreeBytes(taskPort, regionBytes, regionSize);
	}
	
	return textAddress;
}

ZGMemoryAddress ZGBaseExecutableAddress(ZGMemoryMap taskPort)
{
	return [ZGBaseExecutableRegion(taskPort) address];
}

NSArray *ZGGetAllData(ZGMemoryMap processTask, ZGSearchData *searchData, ZGSearchProgress *searchProgress)
{
	NSMutableArray *dataArray = [[NSMutableArray alloc] init];
	BOOL shouldScanUnwritableValues = searchData.shouldScanUnwritableValues;
	
	NSArray *regions = [ZGRegionsForProcessTask(processTask) zgFilterUsingBlock:(zg_array_filter_t)^(ZGRegion *region) {
		return region.protection & VM_PROT_READ && (shouldScanUnwritableValues || (region.protection & VM_PROT_WRITE));
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

ZGMemorySize ZGGetStringSize(ZGMemoryMap processTask, ZGMemoryAddress address, ZGVariableType dataType, ZGMemorySize oldSize, ZGMemorySize maxStringSizeLimit)
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
		
		BOOL couldReadBytes = ZGReadBytes(processTask, address, &buffer, &outputtedSize);
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
			
			ZGFreeBytes(processTask, buffer, outputtedSize);
			
			if (dataType == ZGString16)
			{
				outputtedSize = numberOfCharacters * characterSize;
			}
			
			if (maxStringSizeLimit > 0 && totalSize >= maxStringSizeLimit)
			{
				totalSize = maxStringSizeLimit;
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
