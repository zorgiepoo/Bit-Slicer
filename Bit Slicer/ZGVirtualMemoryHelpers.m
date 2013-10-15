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
		if (!ZGTaskForPID(process, task))
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
	mach_msg_type_number_t infoCount;
	mach_port_t objectName = MACH_PORT_NULL;
	
	while (1)
	{
		infoCount = VM_REGION_BASIC_INFO_COUNT_64;
		if (mach_vm_region(processTask, &address, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &infoCount, &objectName) != KERN_SUCCESS)
		{
			break;
		}
		
		ZGRegion *region = [[ZGRegion alloc] initWithAddress:address size:size];
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
			ZGRegion *region = [[ZGRegion alloc] initWithAddress:address size:size];
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

#define ZGUserTagPretty(x) [[[(x) stringByReplacingOccurrencesOfString:@"VM_MEMORY_" withString:@""] stringByReplacingOccurrencesOfString:@"_" withString:@" "] capitalizedString]
#define ZGHandleUserTagCase(result, value) \
case value: \
	result = ZGUserTagPretty(@(#value)); \
	break;

NSString *ZGUserTagDescription(ZGMemoryMap processTask, ZGMemoryAddress address, ZGMemorySize size)
{
	NSString *userTag = nil;
	ZGMemoryAddress regionAddress = address;
	ZGMemorySize regionSize = size;
	ZGMemorySubmapInfo submapInfo;
	if (ZGRegionSubmapInfo(processTask, &regionAddress, &regionSize, &submapInfo) && regionAddress <= address && address + size <= regionAddress + regionSize)
	{
		switch (submapInfo.user_tag)
		{
			ZGHandleUserTagCase(userTag, VM_MEMORY_MALLOC)
			ZGHandleUserTagCase(userTag, VM_MEMORY_MALLOC_SMALL)
			ZGHandleUserTagCase(userTag, VM_MEMORY_MALLOC_LARGE)
			ZGHandleUserTagCase(userTag, VM_MEMORY_MALLOC_HUGE)
			ZGHandleUserTagCase(userTag, VM_MEMORY_SBRK)
			ZGHandleUserTagCase(userTag, VM_MEMORY_REALLOC)
			ZGHandleUserTagCase(userTag, VM_MEMORY_MALLOC_TINY)
			ZGHandleUserTagCase(userTag, VM_MEMORY_MALLOC_LARGE_REUSABLE)
			ZGHandleUserTagCase(userTag, VM_MEMORY_MALLOC_LARGE_REUSED)
			ZGHandleUserTagCase(userTag, VM_MEMORY_ANALYSIS_TOOL)
			ZGHandleUserTagCase(userTag, VM_MEMORY_MACH_MSG)
			ZGHandleUserTagCase(userTag, VM_MEMORY_IOKIT)
			ZGHandleUserTagCase(userTag, VM_MEMORY_STACK)
			ZGHandleUserTagCase(userTag, VM_MEMORY_GUARD)
			ZGHandleUserTagCase(userTag, VM_MEMORY_SHARED_PMAP)
			ZGHandleUserTagCase(userTag, VM_MEMORY_DYLIB)
			ZGHandleUserTagCase(userTag, VM_MEMORY_OBJC_DISPATCHERS)
			ZGHandleUserTagCase(userTag, VM_MEMORY_UNSHARED_PMAP)
			ZGHandleUserTagCase(userTag, VM_MEMORY_APPKIT)
			ZGHandleUserTagCase(userTag, VM_MEMORY_FOUNDATION)
			ZGHandleUserTagCase(userTag, VM_MEMORY_COREGRAPHICS)
			ZGHandleUserTagCase(userTag, VM_MEMORY_CORESERVICES)
			ZGHandleUserTagCase(userTag, VM_MEMORY_JAVA)
			ZGHandleUserTagCase(userTag, VM_MEMORY_ATS)
			ZGHandleUserTagCase(userTag, VM_MEMORY_LAYERKIT)
			ZGHandleUserTagCase(userTag, VM_MEMORY_CGIMAGE)
			ZGHandleUserTagCase(userTag, VM_MEMORY_TCMALLOC)
			ZGHandleUserTagCase(userTag, VM_MEMORY_COREGRAPHICS_DATA)
			ZGHandleUserTagCase(userTag, VM_MEMORY_COREGRAPHICS_SHARED)
			ZGHandleUserTagCase(userTag, VM_MEMORY_COREGRAPHICS_FRAMEBUFFERS)
			ZGHandleUserTagCase(userTag, VM_MEMORY_COREGRAPHICS_BACKINGSTORES)
			ZGHandleUserTagCase(userTag, VM_MEMORY_DYLD)
			ZGHandleUserTagCase(userTag, VM_MEMORY_DYLD_MALLOC)
			ZGHandleUserTagCase(userTag, VM_MEMORY_SQLITE)
			ZGHandleUserTagCase(userTag, VM_MEMORY_JAVASCRIPT_CORE)
			ZGHandleUserTagCase(userTag, VM_MEMORY_JAVASCRIPT_JIT_EXECUTABLE_ALLOCATOR)
			ZGHandleUserTagCase(userTag, VM_MEMORY_JAVASCRIPT_JIT_REGISTER_FILE)
			ZGHandleUserTagCase(userTag, VM_MEMORY_GLSL)
			ZGHandleUserTagCase(userTag, VM_MEMORY_OPENCL)
			ZGHandleUserTagCase(userTag, VM_MEMORY_COREIMAGE)
			ZGHandleUserTagCase(userTag, VM_MEMORY_WEBCORE_PURGEABLE_BUFFERS)
			ZGHandleUserTagCase(userTag, VM_MEMORY_IMAGEIO)
			ZGHandleUserTagCase(userTag, VM_MEMORY_COREPROFILE)
			ZGHandleUserTagCase(userTag, VM_MEMORY_ASSETSD)
		}
	}
	return userTag;
}

ZGRegion *ZGBaseExecutableRegion(ZGMemoryMap processTask)
{
	// Obtain first __TEXT region
	ZGRegion *chosenRegion = nil;
	for (ZGRegion *region in ZGRegionsForProcessTask(processTask))
	{
		if (region.protection & VM_PROT_READ && region.protection & VM_PROT_EXECUTE)
		{
			chosenRegion = region;
			break;
		}
	}
	return chosenRegion;
}

#define ZGFindTextAddressAndTotalSegmentSize(segment_type, section_type, bytes, machHeaderAddress, textAddress, slide, textSize, dataSize, linkEditSize, numberOfSegmentsToFind) \
struct segment_type *segmentCommand = bytes; \
void *sectionBytes = bytes + sizeof(*segmentCommand); \
if (strcmp(segmentCommand->segname, "__TEXT") == 0) \
{ \
	for (struct section_type *section = sectionBytes; (void *)section < sectionBytes + segmentCommand->cmdsize; section++) \
	{ \
		if (strcmp("__text", section->sectname) == 0) \
		{ \
			if (textAddress != NULL) *textAddress = machHeaderAddress + section->offset; \
			if (slide != NULL) *slide = machHeaderAddress + section->offset - section->addr; \
			break; \
		} \
	} \
	if (textSize != NULL) *textSize = segmentCommand->vmsize; \
	numberOfSegmentsToFind--; \
} \
else if (strcmp(segmentCommand->segname, "__DATA") == 0) \
{ \
	if (dataSize != NULL) *dataSize = segmentCommand->vmsize; \
	numberOfSegmentsToFind--; \
} \
else if (strcmp(segmentCommand->segname, "__LINKEDIT") == 0) \
{ \
	if (linkEditSize != NULL) *linkEditSize = segmentCommand->vmsize; \
	numberOfSegmentsToFind--; \
}

void ZGGetMachBinaryInfo(ZGMemoryMap processTask, ZGMemoryAddress machHeaderAddress, ZGMemoryAddress *firstInstructionAddress, ZGMemoryAddress *slide, ZGMemorySize *textSize, ZGMemorySize *dataSize, ZGMemorySize *linkEditSize)
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
							ZGFindTextAddressAndTotalSegmentSize(segment_command_64, section_64, segmentBytes, machHeaderAddress, firstInstructionAddress, slide, textSize, dataSize, linkEditSize, numberOfSegmentsToFind);
						}
						else if (loadCommand->cmd == LC_SEGMENT)
						{
							ZGFindTextAddressAndTotalSegmentSize(segment_command, section, segmentBytes, machHeaderAddress, firstInstructionAddress, slide, textSize, dataSize, linkEditSize, numberOfSegmentsToFind);
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

NSString *ZGMappedFilePath(ZGMemoryMap processTask, ZGMemoryAddress regionAddress)
{
	NSString *mappedFilePath = nil;
	
	int processID = 0;
	if (ZGPIDForTask(processTask, &processID))
	{
		void *buffer = calloc(1, PATH_MAX);
		int numberOfBytesReturned = proc_regionfilename(processID, regionAddress, buffer, PATH_MAX);
		if (numberOfBytesReturned > 0 && numberOfBytesReturned <= PATH_MAX)
		{
			mappedFilePath = [[NSString alloc] initWithBytes:buffer length:numberOfBytesReturned encoding:NSUTF8StringEncoding];
		}
		free(buffer);
	}
	
	return mappedFilePath;
}

NSArray *ZGMachBinaryRegions(ZGMemoryMap processTask)
{
	NSMutableArray *regions = [[NSMutableArray alloc] init];
	NSString *lastVisitedFilePath = nil;
	for (ZGRegion *region in ZGRegionsForProcessTask(processTask))
	{
		NSString *mappedFilePath = ZGMappedFilePath(processTask, region.address);
		if (mappedFilePath != nil && ![lastVisitedFilePath isEqualToString:mappedFilePath])
		{
			ZGMemorySize textSize = 0;
			ZGMemorySize dataSize = 0;
			ZGMemorySize linkEditSize = 0;
			ZGMemorySize slide = 0;
			ZGGetMachBinaryInfo(processTask, region.address, NULL, &slide, &textSize, &dataSize, &linkEditSize);
			
			region.mappedPath = mappedFilePath;
			region.size = textSize + dataSize + linkEditSize;
			region.slide = slide;
			[regions addObject:region];
			lastVisitedFilePath = mappedFilePath;
		}
	}
	return regions;
}

ZGMemoryAddress ZGNearestMachHeaderBeforeRegion(ZGMemoryMap processTask, ZGRegion *targetRegion, NSString **mappedFilePath)
{
	NSString *lastVisitedFilePath = nil;
	ZGMemoryAddress previousHeaderAddress = 0;
	for (ZGRegion *region in ZGRegionsForProcessTask(processTask))
	{
		if (region.address > targetRegion.address) break;
		
		NSString *mappedFilePath = ZGMappedFilePath(processTask, region.address);
		if (mappedFilePath == nil) continue;
		
		if ([mappedFilePath isEqualToString:lastVisitedFilePath]) continue;
		
		lastVisitedFilePath = mappedFilePath;
		
		// We just have to read the first magic field
		const ZGMemorySize originalSize = sizeof(int32_t);
		ZGMemorySize readSize = originalSize;
		void *regionBytes = NULL;
		if (ZGReadBytes(processTask, region.address, &regionBytes, &readSize))
		{
			if (readSize >= originalSize)
			{
				struct mach_header_64 *header = regionBytes;
				if (header->magic == MH_MAGIC || header->magic == MH_MAGIC_64)
				{
					previousHeaderAddress = region.address;
				}
			}
			ZGFreeBytes(processTask, regionBytes, readSize);
		}
	}
	
	if (mappedFilePath != NULL) *mappedFilePath = lastVisitedFilePath;
	
	return previousHeaderAddress;
}

void ZGGetMappedRegionInfo(ZGMemoryMap processTask, ZGRegion *region, NSString **mappedFilePath, ZGMemoryAddress *machHeaderAddress, ZGMemoryAddress *textAddress, ZGMemoryAddress *slide, ZGMemorySize *textSize, ZGMemorySize *dataSize, ZGMemorySize *linkEditSize)
{
	ZGMemoryAddress nearestMachHeaderAddress = ZGNearestMachHeaderBeforeRegion(processTask, region, mappedFilePath);
	if (machHeaderAddress != NULL) *machHeaderAddress = nearestMachHeaderAddress;
	ZGGetMachBinaryInfo(processTask, nearestMachHeaderAddress, textAddress, slide, textSize, dataSize, linkEditSize);
}

NSString *ZGSectionName(ZGMemoryMap processTask, ZGMemoryAddress address, ZGMemorySize size, NSString **mappedFilePath, ZGMemoryAddress *relativeOffset, ZGMemoryAddress *slide)
{
	NSString *sectionName = nil;
	ZGMemoryBasicInfo unusedInfo;
	ZGRegion *region = [[ZGRegion alloc] initWithAddress:address size:size];
	if (ZGRegionInfo(processTask, &region->_address, &region->_size, &unusedInfo) && region.address <= address && address + size <= region.address + region.size)
	{
		ZGMemoryAddress machHeaderAddress = 0;
		ZGMemorySize textSize = 0;
		ZGMemorySize dataSize = 0;
		ZGMemorySize linkEditSize = 0;
		
		ZGGetMappedRegionInfo(processTask, region, mappedFilePath, &machHeaderAddress, NULL, slide, &textSize, &dataSize, &linkEditSize);
		if (relativeOffset != NULL) *relativeOffset = address - machHeaderAddress;
		
		if (address >= machHeaderAddress)
		{
			if (address + size <= machHeaderAddress + textSize)
			{
				sectionName = @"__TEXT";
			}
			else if (address + size <= machHeaderAddress + textSize + dataSize)
			{
				sectionName = @"__DATA";
			}
			else if (address + size <= machHeaderAddress + textSize + dataSize + linkEditSize)
			{
				sectionName = @"__LINKEDIT";
			}
			else
			{
				// Can't prove anything
				if (mappedFilePath != NULL) *mappedFilePath = nil;
			}
		}
	}
	return sectionName;
}

NSRange ZGTextRange(ZGMemoryMap processTask, ZGRegion *region, NSString **mappedFilePath, ZGMemoryAddress *machHeaderAddress, ZGMemoryAddress *slide)
{
	ZGMemoryAddress textAddress = 0;
	ZGMemorySize textSize = 0;
	ZGGetMappedRegionInfo(processTask, region, mappedFilePath, machHeaderAddress, &textAddress, slide, &textSize, NULL, NULL);
	
	return NSMakeRange(textAddress, textSize);
}

ZGMemoryAddress ZGInstructionOffset(ZGMemoryMap processTask, NSMutableDictionary *cacheDictionary, ZGMemoryAddress instructionAddress, ZGMemorySize instructionSize, ZGMemoryAddress *slide, NSString **partialImageName)
{
	ZGMemoryAddress offset = 0x0;
	
	ZGMemoryAddress regionAddress = instructionAddress;
	ZGMemorySize regionSize = instructionSize;
	ZGMemoryBasicInfo unusedInfo;
	if (ZGRegionInfo(processTask, &regionAddress, &regionSize, &unusedInfo) && regionAddress <= instructionAddress && regionAddress + regionSize >= instructionAddress + instructionSize)
	{
		ZGRegion *region = [[ZGRegion alloc] initWithAddress:regionAddress size:regionSize];
		NSString *mappedFilePath = nil;
		ZGMemoryAddress machHeaderAddress = 0x0;
		NSRange textRange = ZGTextRange(processTask, region, &mappedFilePath, &machHeaderAddress, slide);
		if (textRange.location <= instructionAddress && textRange.location + textRange.length >= instructionAddress + instructionSize && mappedFilePath != nil)
		{
			NSError *error = nil;
			NSString *partialPath = [mappedFilePath lastPathComponent];
			// Make sure base address with our partial path matches with base address at full path
			ZGMemoryAddress baseVerificationAddress = ZGFindExecutableImageWithCache(processTask, partialPath, cacheDictionary, &error);
			if (error == nil && baseVerificationAddress == machHeaderAddress)
			{
				offset = instructionAddress - machHeaderAddress;
				if (partialImageName != NULL) *partialImageName = [partialPath copy];
			}
		}
	}
	
	return offset;
}

ZGMemoryAddress ZGBaseExecutableAddress(ZGMemoryMap processTask)
{
	return [ZGBaseExecutableRegion(processTask) address];
}

ZGMemoryAddress ZGFindExecutableImageWithCache(ZGMemoryMap processTask, NSString *partialImageName, NSMutableDictionary *cacheDictionary, NSError **error)
{
	ZGMemoryAddress foundAddress = 0x0;
	NSNumber *addressNumber = [cacheDictionary objectForKey:partialImageName];
	if (addressNumber == nil)
	{
		ZGRegion *foundRegion = ZGFindExecutableImage(processTask, partialImageName);
		if (foundRegion != nil)
		{
			foundAddress = foundRegion.address;
			[cacheDictionary setObject:@(foundAddress) forKey:partialImageName];
		}
		else if (error != NULL)
		{
			*error = [NSError errorWithDomain:@"ZGFindExecutableImageFailed" code:1 userInfo:nil];
		}
	}
	else
	{
		foundAddress = [addressNumber unsignedLongLongValue];
	}
	return foundAddress;
}

ZGRegion *ZGFindExecutableImage(ZGMemoryMap processTask, NSString *partialImageName)
{
	for (ZGRegion *region in ZGRegionsForProcessTask(processTask))
	{
		NSString *mappedFilePath = ZGMappedFilePath(processTask, region.address);
		if ([mappedFilePath hasSuffix:partialImageName])
		{
			return region;
		}
	}
	return nil;
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
