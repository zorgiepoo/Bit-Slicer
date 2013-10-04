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
#import <mach-o/dyld_images.h>

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

ZGRegion *ZGDylinkerRegion(ZGMemoryMap processTask, uint32_t *dyldAllImageInfosOffset, ZGMemorySize *pointerSize)
{
	ZGRegion *foundRegion = nil;
	for (ZGRegion *region in ZGRegionsForProcessTask(processTask))
	{
		ZGMemoryAddress regionAddress = region.address;
		ZGMemorySize regionSize = region.size;
		void *regionBytes = NULL;
		if (ZGReadBytes(processTask, regionAddress, &regionBytes, &regionSize))
		{
			struct mach_header_64 *machHeader = regionBytes;
			if ((machHeader->magic == MH_MAGIC || machHeader->magic == MH_MAGIC_64) && machHeader->filetype == MH_DYLINKER)
			{
				if (pointerSize != NULL)
				{
					*pointerSize = machHeader->magic == MH_MAGIC_64 ? sizeof(uint64_t) : sizeof(uint32_t);
				}
				foundRegion = region;
				if (dyldAllImageInfosOffset != NULL)
				{
					memcpy(dyldAllImageInfosOffset, regionBytes + DYLD_ALL_IMAGE_INFOS_OFFSET_OFFSET, sizeof(uint32_t));
				}
			}
			ZGFreeBytes(processTask, regionBytes, regionSize);
		}
		if (foundRegion != nil)
		{
			break;
		}
	}
	return foundRegion;
}

#define ZGMachHeaderAddressKey @"ZGMachHeaderAddressKey"
#define ZGMappedFilePathKey @"ZGMappedFilePathKey"
NSArray *ZGMachHeadersAndMappedPaths(ZGMemoryMap processTask)
{
	NSMutableArray *results = [[NSMutableArray alloc] init];
	ZGMemorySize pointerSize = 0;
	uint32_t dyldAllImageInfosOffset = 0;
	ZGRegion *dylinkerRegion = ZGDylinkerRegion(processTask, &dyldAllImageInfosOffset, &pointerSize);
	if (dylinkerRegion != nil)
	{
		ZGMemoryAddress allImageInfosAddress = dylinkerRegion.address + dyldAllImageInfosOffset;
		ZGMemorySize allImageInfosSize = sizeof(uint32_t) * 2 + pointerSize; // Just interested in first three fields of struct dyld_all_image_infos
		struct dyld_all_image_infos *allImageInfos = NULL;
		if (ZGReadBytes(processTask, allImageInfosAddress, (void **)&allImageInfos, &allImageInfosSize))
		{
			ZGMemoryAddress infoArrayAddress = (pointerSize == sizeof(ZG32BitMemoryAddress)) ? *(ZG32BitMemoryAddress *)&allImageInfos->infoArray : *(ZGMemoryAddress *)&allImageInfos->infoArray;
			const ZGMemorySize imageInfoSize = pointerSize * 3;
			
			void *infoArrayBytes = NULL;
			ZGMemorySize infoArraySize = imageInfoSize * allImageInfos->infoArrayCount;
			if (ZGReadBytes(processTask, infoArrayAddress, &infoArrayBytes, &infoArraySize))
			{
				for (uint32_t infoIndex = 0; infoIndex < allImageInfos->infoArrayCount; infoIndex++)
				{
					void *infoImage = infoArrayBytes + imageInfoSize * infoIndex;
					
					ZGMemoryAddress machHeaderPointer = (pointerSize == sizeof(ZG32BitMemoryAddress)) ? *(ZG32BitMemoryAddress *)infoImage : *(ZGMemoryAddress *)infoImage;
					
					ZGMemoryAddress imageFilePathPointer = (pointerSize == sizeof(ZG32BitMemoryAddress)) ? *(ZG32BitMemoryAddress *)(infoImage + pointerSize) : *(ZGMemoryAddress *)(infoImage + pointerSize);
					
					NSString *filePath = nil;
					ZGMemorySize pathSize = ZGGetStringSize(processTask, imageFilePathPointer, ZGString8, 1, PATH_MAX) + 1;
					void *filePathBytes = NULL;
					if (ZGReadBytes(processTask, imageFilePathPointer, &filePathBytes, &pathSize))
					{
						filePath = [NSString stringWithUTF8String:filePathBytes];
						ZGFreeBytes(processTask, filePathBytes, pathSize);
					}
					
					[results addObject:@{ZGMachHeaderAddressKey : @(machHeaderPointer), ZGMappedFilePathKey : filePath != nil ? filePath : [NSNull null]}];
				}
				ZGFreeBytes(processTask, infoArrayBytes, infoArraySize);
			}
			ZGFreeBytes(processTask, allImageInfos, allImageInfosSize);
		}
	}
	return results;
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
			region.protection = info.protection;
			
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

#define ZGFindTextAddressAndTotalSegmentSize(segment_type, section_type, bytes, machHeaderAddress, textAddress, totalSize, numberOfSegmentsToFind) \
struct segment_type *segmentCommand = bytes; \
void *sectionBytes = bytes + sizeof(*segmentCommand); \
if (strcmp(segmentCommand->segname, "__TEXT") == 0) \
{ \
	for (struct section_type *section = sectionBytes; (void *)section < sectionBytes + segmentCommand->cmdsize; section++) \
	{ \
		if (strcmp("__text", section->sectname) == 0) \
		{ \
			if (textAddress != NULL) *textAddress = machHeaderAddress + section->offset; \
			break; \
		} \
	} \
	if (totalSize != NULL) *totalSize += segmentCommand->vmsize; \
	numberOfSegmentsToFind--; \
} \
else if (strcmp(segmentCommand->segname, "__DATA") == 0) \
{ \
	if (totalSize != NULL) *totalSize += segmentCommand->vmsize; \
	numberOfSegmentsToFind--; \
} \
else if (strcmp(segmentCommand->segname, "__LINKEDIT") == 0) \
{ \
	if (totalSize != NULL) *totalSize += segmentCommand->vmsize; \
	numberOfSegmentsToFind--; \
}

void ZGGetMachBinaryInfo(ZGMemoryMap processTask, ZGMemoryAddress machHeaderAddress, ZGMemoryAddress *firstInstructionAddress, ZGMemorySize *totalSize)
{
	ZGMemoryAddress regionAddress = machHeaderAddress;
	ZGMemorySize regionSize = 1;
	ZGMemoryBasicInfo unusedInfo;
	if (ZGRegionInfo(processTask, &regionAddress, &regionSize, &unusedInfo) && machHeaderAddress >= regionAddress && machHeaderAddress < regionAddress + regionSize)
	{
		void *regionBytes = NULL;
		if (ZGReadBytes(processTask, regionAddress, &regionBytes, &regionSize))
		{
			struct mach_header_64 *machHeader = regionBytes + regionAddress - machHeaderAddress;
			if (machHeader->magic == MH_MAGIC || machHeader->magic == MH_MAGIC_64)
			{
				void *segmentBytes = (void *)machHeader + ((machHeader->magic == MH_MAGIC) ? sizeof(struct mach_header) : sizeof(struct mach_header_64));
				if ((segmentBytes - regionBytes) + (ZGMemorySize)machHeader->sizeofcmds <= regionSize)
				{
					int numberOfSegmentsToFind = 3;
					for (uint32_t commandIndex = 0; commandIndex < machHeader->ncmds; commandIndex++)
					{
						struct load_command *loadCommand = segmentBytes;
						
						if (loadCommand->cmd == LC_SEGMENT_64)
						{
							ZGFindTextAddressAndTotalSegmentSize(segment_command_64, section_64, segmentBytes, machHeaderAddress, firstInstructionAddress, totalSize, numberOfSegmentsToFind);
						}
						else if (loadCommand->cmd == LC_SEGMENT)
						{
							ZGFindTextAddressAndTotalSegmentSize(segment_command, section, segmentBytes, machHeaderAddress, firstInstructionAddress, totalSize, numberOfSegmentsToFind);
						}
						
						if (numberOfSegmentsToFind <= 0)
						{
							break;
						}
						
						segmentBytes += loadCommand->cmdsize;
					}
				}
			}
			ZGFreeBytes(processTask, regionBytes, regionSize);
		}
	}
}

ZGMemoryAddress ZGNearestMachHeaderBeforeRegion(ZGMemoryMap processTask, ZGRegion *targetRegion)
{
	ZGMemoryAddress previousHeaderAddress = 0;
	for (ZGRegion *region in ZGRegionsForProcessTask(processTask))
	{
		if (region.address > targetRegion.address) break;
		
		ZGMemorySize regionSize = region.size;
		void *regionBytes = NULL;
		if (ZGReadBytes(processTask, region.address, &regionBytes, &regionSize))
		{
			struct mach_header_64 *header = regionBytes;
			if (header->magic == MH_MAGIC || header->magic == MH_MAGIC_64)
			{
				previousHeaderAddress = region.address;
			}
			ZGFreeBytes(processTask, regionBytes, regionSize);
		}
	}
	return previousHeaderAddress;
}

ZGMemoryAddress ZGFirstInstructionAddress(ZGMemoryMap processTask, ZGRegion *region)
{
	ZGMemoryAddress textAddress = 0;
	ZGGetMachBinaryInfo(processTask, ZGNearestMachHeaderBeforeRegion(processTask, region), &textAddress, NULL);
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
