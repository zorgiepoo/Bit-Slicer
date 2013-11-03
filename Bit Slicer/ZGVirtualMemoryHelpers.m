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
#import "ZGMachBinary.h"
#import "NSArrayAdditions.h"

#import <mach/mach_error.h>
#import <mach/mach_vm.h>

#import <mach-o/loader.h>
#import <mach-o/dyld_images.h>

#import <mach-o/fat.h>

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
			ZGHandleUserTagCase(userTag, VM_MEMORY_MALLOC_NANO)
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
			ZGHandleUserTagCase(userTag, VM_MEMORY_COREDATA)
			ZGHandleUserTagCase(userTag, VM_MEMORY_COREDATA_OBJECTIDS)
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
			ZGHandleUserTagCase(userTag, VM_MEMORY_OS_ALLOC_ONCE)
			ZGHandleUserTagCase(userTag, VM_MEMORY_LIBDISPATCH)
			ZGHandleUserTagCase(userTag, VM_MEMORY_ACCELERATE)
			ZGHandleUserTagCase(userTag, VM_MEMORY_COREUI)
		}
	}
	return userTag;
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

void ZGParseMachHeader(ZGMemoryAddress machHeaderAddress, ZGMemorySize pointerSize, const void *machHeaderBytes, const void *minimumBoundaryPointer, ZGMemorySize maximumBoundarySize, ZGMemoryAddress *firstInstructionAddress, ZGMemoryAddress *slide, ZGMemorySize *textSize, ZGMemorySize *dataSize, ZGMemorySize *linkEditSize)
{
	const struct mach_header_64 *machHeader = machHeaderBytes;
	if (machHeader->magic == FAT_CIGAM) // only interested in little endian
	{
		uint32_t numberOfArchitectures = CFSwapInt32BigToHost(((struct fat_header *)machHeader)->nfat_arch);
		for (uint32_t architectureIndex = 0; architectureIndex < numberOfArchitectures; architectureIndex++)
		{
			struct fat_arch *fatArchitecture = (void *)machHeader + sizeof(struct fat_header) + sizeof(struct fat_arch) * architectureIndex;
			if ((pointerSize == sizeof(ZGMemoryAddress) && fatArchitecture->cputype & CPU_TYPE_X86_64) || (pointerSize == sizeof(ZG32BitMemoryAddress) && fatArchitecture->cputype & CPU_TYPE_I386))
			{
				machHeader = (void *)machHeader + CFSwapInt32BigToHost(fatArchitecture->offset);
				break;
			}
		}
	}
	
	if (machHeader->magic == MH_MAGIC || machHeader->magic == MH_MAGIC_64)
	{
		void *segmentBytes = (void *)machHeader + ((machHeader->magic == MH_MAGIC) ? sizeof(struct mach_header) : sizeof(struct mach_header_64));
		if ((segmentBytes - minimumBoundaryPointer) + (ZGMemorySize)machHeader->sizeofcmds <= maximumBoundarySize)
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
}

void ZGGetMachBinaryInfoFromFilePath(NSString *mappedFilePath, ZGMemorySize pointerSize, ZGMemoryAddress machHeaderAddress, ZGMemoryAddress *firstInstructionAddress, ZGMemoryAddress *slide, ZGMemorySize *textSize, ZGMemorySize *dataSize, ZGMemorySize *linkEditSize)
{
	NSData *machFileData = [NSData dataWithContentsOfFile:mappedFilePath];
	if (machFileData != nil)
	{
		ZGParseMachHeader(machHeaderAddress, pointerSize, machFileData.bytes, machFileData.bytes, machFileData.length, firstInstructionAddress, slide, textSize, dataSize, linkEditSize);
	}
}

void ZGGetMachBinaryInfoFromMemory(ZGMemoryMap processTask, ZGMemorySize pointerSize, ZGMemoryAddress machHeaderAddress, ZGMemoryAddress *firstInstructionAddress, ZGMemoryAddress *slide, ZGMemorySize *textSize, ZGMemorySize *dataSize, ZGMemorySize *linkEditSize)
{
	ZGMemoryAddress regionAddress = machHeaderAddress;
	ZGMemorySize regionSize = 1;
	ZGMemoryBasicInfo unusedInfo;
	if (ZGRegionInfo(processTask, &regionAddress, &regionSize, &unusedInfo) && machHeaderAddress >= regionAddress && machHeaderAddress < regionAddress + regionSize)
	{
		void *regionBytes = NULL;
		if (ZGReadBytes(processTask, regionAddress, &regionBytes, &regionSize))
		{
			const struct mach_header_64 *machHeader = regionBytes + machHeaderAddress - regionAddress;
			ZGParseMachHeader(machHeaderAddress, pointerSize, machHeader, regionBytes, regionSize, firstInstructionAddress, slide, textSize, dataSize, linkEditSize);
			
			ZGFreeBytes(processTask, regionBytes, regionSize);
		}
	}
}

void ZGGetMachBinaryInfo(ZGMemoryMap processTask, ZGMemorySize pointerSize, ZGMemoryAddress machHeaderAddress, NSString *mappedFilePath, ZGMemoryAddress *firstInstructionAddress, ZGMemoryAddress *slide, ZGMemorySize *textSize, ZGMemorySize *dataSize, ZGMemorySize *linkEditSize)
{
	ZGMemorySize textSizeReturned = 0;
	ZGMemorySize dataSizeReturned = 0;
	ZGMemorySize linkEditSizeReturned = 0;
	
	ZGGetMachBinaryInfoFromMemory(processTask, pointerSize, machHeaderAddress, firstInstructionAddress, slide, &textSizeReturned, &dataSizeReturned, &linkEditSizeReturned);
	
	if (textSizeReturned + dataSizeReturned + linkEditSizeReturned > 0)
	{
		if (textSize != NULL) *textSize = textSizeReturned;
		if (dataSize != NULL) *dataSize = dataSizeReturned;
		if (linkEditSize != NULL) *linkEditSize = linkEditSizeReturned;
	}
	else if (mappedFilePath.length > 0)
	{
		ZGGetMachBinaryInfoFromFilePath(mappedFilePath, pointerSize, machHeaderAddress, firstInstructionAddress, slide, textSize, dataSize, linkEditSize);
	}
}

ZGMachBinary *ZGDylinkerBinary(ZGMemoryMap processTask)
{
	ZGMachBinary *dylinkerBinary = nil;
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
				void *bytes = (void *)machHeader + ((machHeader->magic == MH_MAGIC) ? sizeof(struct mach_header) : sizeof(struct mach_header_64));
				for (uint32_t commandIndex = 0; commandIndex < machHeader->ncmds; commandIndex++)
				{
					struct dylinker_command *dylinkerCommand = bytes;
					
					if (dylinkerCommand->cmd == LC_ID_DYLINKER || dylinkerCommand->cmd == LC_LOAD_DYLINKER)
					{
						dylinkerBinary = [[ZGMachBinary alloc] initWithHeaderAddress:regionAddress filePathAddress:dylinkerCommand->name.offset + (void *)dylinkerCommand - regionBytes + regionAddress];
					}
					
					bytes += dylinkerCommand->cmdsize;
				}
			}
			ZGFreeBytes(processTask, regionBytes, regionSize);
		}
		if (dylinkerBinary != nil)
		{
			break;
		}
	}
	return dylinkerBinary;
}

NSArray *ZGMachBinaries(ZGMemoryMap processTask, ZGMemoryAddress pointerSize, ZGMachBinary *dylinkerBinary)
{
	NSMutableArray *results = [[NSMutableArray alloc] init];
	
	struct task_dyld_info dyld_info;
	mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
	if (task_info(processTask, TASK_DYLD_INFO, (task_info_t)&dyld_info, &count) == KERN_SUCCESS)
	{
		ZGMemoryAddress allImageInfosAddress = dyld_info.all_image_info_addr;
		ZGMemorySize allImageInfosSize = sizeof(uint32_t) * 2 + pointerSize; // Just interested in first three fields of struct dyld_all_image_infos
		struct dyld_all_image_infos *allImageInfos = NULL;
		if (ZGReadBytes(processTask, allImageInfosAddress, (void **)&allImageInfos, &allImageInfosSize))
		{
			ZGMemoryAddress infoArrayAddress = (pointerSize == sizeof(ZG32BitMemoryAddress)) ? *(ZG32BitMemoryAddress *)&allImageInfos->infoArray : *(ZGMemoryAddress *)&allImageInfos->infoArray;
			const ZGMemorySize imageInfoSize = pointerSize * 3; // sizeof struct dyld_image_info
			
			void *infoArrayBytes = NULL;
			ZGMemorySize infoArraySize = imageInfoSize * allImageInfos->infoArrayCount;
			if (ZGReadBytes(processTask, infoArrayAddress, &infoArrayBytes, &infoArraySize))
			{
				for (uint32_t infoIndex = 0; infoIndex < allImageInfos->infoArrayCount; infoIndex++)
				{
					void *infoImage = infoArrayBytes + imageInfoSize * infoIndex;
					
					ZGMemoryAddress machHeaderAddress = (pointerSize == sizeof(ZG32BitMemoryAddress)) ? *(ZG32BitMemoryAddress *)infoImage : *(ZGMemoryAddress *)infoImage;
					
					ZGMemoryAddress imageFilePathAddress = (pointerSize == sizeof(ZG32BitMemoryAddress)) ? *(ZG32BitMemoryAddress *)(infoImage + pointerSize) : *(ZGMemoryAddress *)(infoImage + pointerSize);
					
					[results addObject:[[ZGMachBinary alloc] initWithHeaderAddress:machHeaderAddress filePathAddress:imageFilePathAddress]];
				}
				ZGFreeBytes(processTask, infoArrayBytes, infoArraySize);
			}
			ZGFreeBytes(processTask, allImageInfos, allImageInfosSize);
		}
		
		[results addObject:dylinkerBinary];
	}
	
	return [results sortedArrayUsingSelector:@selector(compare:)];
}

NSString *ZGFilePathAtAddress(ZGMemoryMap processTask, ZGMemoryAddress filePathAddress)
{
	NSString *filePath = nil;
	ZGMemorySize pathSize = ZGGetStringSize(processTask, filePathAddress, ZGString8, 200, PATH_MAX);
	void *filePathBytes = NULL;
	if (ZGReadBytes(processTask, filePathAddress, &filePathBytes, &pathSize))
	{
		filePath = [[NSString alloc] initWithBytes:filePathBytes length:pathSize encoding:NSUTF8StringEncoding];
		ZGFreeBytes(processTask, filePathBytes, pathSize);
	}
	return filePath;
}

ZGMachBinary *ZGNearestMachBinary(NSArray *machBinaries, ZGMemoryAddress targetAddress)
{
	id previousMachBinary = nil;
	
	for (ZGMachBinary *machBinary in machBinaries)
	{
		if (machBinary.headerAddress > targetAddress) break;
		
		previousMachBinary = machBinary;
	}
	
	return previousMachBinary;
}

void ZGGetNearestMachBinaryInfo(ZGMemoryMap processTask, ZGMemorySize pointerSize, ZGMachBinary *dylinkerBinary, ZGMemoryAddress targetAddress, NSString **mappedFilePath, ZGMemoryAddress *machHeaderAddress, ZGMemoryAddress *textAddress, ZGMemoryAddress *slide, ZGMemorySize *textSize, ZGMemorySize *dataSize, ZGMemorySize *linkEditSize)
{
	ZGMachBinary *machBinary = ZGNearestMachBinary(ZGMachBinaries(processTask, pointerSize, dylinkerBinary), targetAddress);
	if (machBinary != nil)
	{
		ZGMemoryAddress returnedMachHeaderAddress = machBinary.headerAddress;
		ZGMemoryAddress returnedMachFilePathAddress = machBinary.filePathAddress;
		
		NSString *returnedFilePath = ZGFilePathAtAddress(processTask, returnedMachFilePathAddress);
		
		if (machHeaderAddress != NULL) *machHeaderAddress = returnedMachHeaderAddress;
		if (mappedFilePath != NULL) *mappedFilePath = returnedFilePath;
		
		ZGGetMachBinaryInfo(processTask, pointerSize, returnedMachHeaderAddress, returnedFilePath, textAddress, slide, textSize, dataSize, linkEditSize);
	}
}

NSString *ZGSectionName(ZGMemoryMap processTask, ZGMemorySize pointerSize, ZGMachBinary *dylinkerBinary, ZGMemoryAddress address, ZGMemorySize size, NSString **mappedFilePath, ZGMemoryAddress *relativeOffset, ZGMemoryAddress *slide)
{
	NSString *sectionName = nil;
	
	ZGMemoryAddress machHeaderAddress = 0;
	ZGMemorySize textSize = 0;
	ZGMemorySize dataSize = 0;
	ZGMemorySize linkEditSize = 0;
	
	ZGGetNearestMachBinaryInfo(processTask, pointerSize, dylinkerBinary, address, mappedFilePath, &machHeaderAddress, NULL, slide, &textSize, &dataSize, &linkEditSize);
	
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
	
	return sectionName;
}

NSRange ZGTextRange(ZGMemoryMap processTask, ZGMemorySize pointerSize, ZGMachBinary *dylinkerBinary, ZGMemoryAddress targetAddress, NSString **mappedFilePath, ZGMemoryAddress *machHeaderAddress, ZGMemoryAddress *slide, NSMutableDictionary *cacheDictionary)
{
	ZGMemoryAddress textAddress = 0;
	ZGMemorySize textSize = 0;
	ZGMemoryAddress machHeaderAddressReturned = 0;
	
	ZGGetNearestMachBinaryInfo(processTask, pointerSize, dylinkerBinary, targetAddress, mappedFilePath, &machHeaderAddressReturned, &textAddress, slide, &textSize, NULL, NULL);
	
	if (machHeaderAddress != NULL) *machHeaderAddress = machHeaderAddressReturned;
	
	return NSMakeRange(textAddress, textSize);
}

ZGMemoryAddress ZGInstructionOffset(ZGMemoryMap processTask, ZGMemorySize pointerSize, ZGMachBinary *dylinkerBinary, NSMutableDictionary *cacheDictionary, ZGMemoryAddress instructionAddress, ZGMemorySize instructionSize, ZGMemoryAddress *slide, NSString **partialImageName)
{
	ZGMemoryAddress offset = 0x0;
	
	NSString *mappedFilePath = nil;
	ZGMemoryAddress machHeaderAddress = 0x0;
	
	NSRange textRange = ZGTextRange(processTask, pointerSize, dylinkerBinary, instructionAddress, &mappedFilePath, &machHeaderAddress, slide, cacheDictionary);
	if (textRange.location <= instructionAddress && textRange.location + textRange.length >= instructionAddress + instructionSize && mappedFilePath != nil)
	{
		NSError *error = nil;
		NSString *partialPath = [mappedFilePath lastPathComponent];
		// Make sure base address with our partial path matches with base address at full path
		ZGMemoryAddress baseVerificationAddress = ZGFindExecutableImageWithCache(processTask, pointerSize, dylinkerBinary, partialPath, cacheDictionary, &error);
		if (error == nil && baseVerificationAddress == machHeaderAddress)
		{
			offset = instructionAddress - machHeaderAddress;
			if (partialImageName != NULL) *partialImageName = [partialPath copy];
		}
	}
	
	return offset;
}

ZGMemoryAddress ZGFindExecutableImage(ZGMemoryMap processTask, ZGMemorySize pointerSize, ZGMachBinary *dylinkerBinary, NSString *partialImageName)
{
	ZGMemoryAddress foundAddress = 0;
	for (ZGMachBinary *machBinary in ZGMachBinaries(processTask, pointerSize, dylinkerBinary))
	{
		NSString *mappedFilePath = ZGFilePathAtAddress(processTask, machBinary.filePathAddress);
		if ([mappedFilePath hasSuffix:partialImageName])
		{
			foundAddress = machBinary.headerAddress;
			break;
		}
	}
	return foundAddress;
}

ZGMemoryAddress ZGFindExecutableImageWithCache(ZGMemoryMap processTask, ZGMemorySize pointerSize, ZGMachBinary *dylinkerBinary, NSString *partialImageName, NSMutableDictionary *cacheDictionary, NSError **error)
{
	ZGMemoryAddress foundAddress = 0x0;
	NSMutableDictionary *mappedPathDictionary = [cacheDictionary objectForKey:ZGMappedPathDictionary];
	NSNumber *addressNumber = [mappedPathDictionary objectForKey:partialImageName];
	if (addressNumber == nil)
	{
		ZGMemoryAddress foundAddress = ZGFindExecutableImage(processTask, pointerSize, dylinkerBinary, partialImageName);
		if (foundAddress != 0)
		{
			[mappedPathDictionary setObject:@(foundAddress) forKey:partialImageName];
		}
		else if (error != NULL)
		{
			*error = [NSError errorWithDomain:@"ZGFindExecutableImageFailed" code:1 userInfo:@{ZGImageName : partialImageName}];
		}
	}
	else
	{
		foundAddress = [addressNumber unsignedLongLongValue];
	}
	return foundAddress;
}

CSSymbolRef ZGFindFirstSymbol(CSSymbolicatorRef symbolicator, NSString *symbolName, NSString *partialSymbolOwnerName)
{
	__block CSSymbolRef resultSymbol = kCSNull;
	const char *symbolCString = [symbolName UTF8String];
	
	CSSymbolicatorForeachSymbolOwnerAtTime(symbolicator, kCSNow, ^(CSSymbolOwnerRef owner) {
		const char *symbolOwnerName = CSSymbolOwnerGetName(owner);
		if (partialSymbolOwnerName == nil || (symbolOwnerName != NULL && [@(symbolOwnerName) hasSuffix:partialSymbolOwnerName]))
		{
			CSSymbolOwnerForeachSymbol(owner, ^(CSSymbolRef symbol) {
				if (CSIsNull(resultSymbol))
				{
					const char *symbolFound = CSSymbolGetName(symbol);
					if (symbolFound != NULL && strcmp(symbolCString, symbolFound) == 0)
					{
						resultSymbol = symbol;
					}
				}
			});
		}
	});
	return resultSymbol;
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
			
			if (maxStringSizeLimit > 0 && totalSize >= maxStringSizeLimit)
			{
				totalSize = maxStringSizeLimit;
				shouldBreak = YES;
			}
			
			if (dataType == ZGString16)
			{
				outputtedSize = numberOfCharacters * characterSize;
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
