/*
 * Created by Mayur Pawashe on 1/30/14.
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

#import "ZGMachBinaryInfo.h"
#import "ZGMachBinary.h"
#import "ZGVirtualMemory.h"
#import "ZGVirtualMemoryHelpers.h"
#import "ZGRegion.h"

#import <mach-o/loader.h>
#import <mach-o/dyld_images.h>
#import <mach-o/fat.h>

NSString * const ZGMachFileDataDictionary = @"ZGMachFileDataDictionary";
NSString * const ZGImageName = @"ZGImageName";
NSString * const ZGMappedPathDictionary = @"ZGMappedPathDictionary";
NSString * const ZGMappedBinaryDictionary = @"ZGMappedBinaryDictionary";

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

void ZGGetMachBinaryInfoFromFilePath(NSString *mappedFilePath, ZGMemorySize pointerSize, ZGMemoryAddress machHeaderAddress, ZGMemoryAddress *firstInstructionAddress, ZGMemoryAddress *slide, ZGMemorySize *textSize, ZGMemorySize *dataSize, ZGMemorySize *linkEditSize, NSMutableDictionary *cacheDictionary)
{
	NSMutableDictionary *machFileDataDictionary = [cacheDictionary objectForKey:ZGMachFileDataDictionary];
	NSData *machFileData = [machFileDataDictionary objectForKey:mappedFilePath];
	if (machFileData == nil)
	{
		machFileData = [NSData dataWithContentsOfFile:mappedFilePath];
		if (machFileData != nil)
		{
			[machFileDataDictionary setObject:machFileData forKey:mappedFilePath];
		}
	}
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

void ZGGetMachBinaryInfo(ZGMemoryMap processTask, ZGMemorySize pointerSize, ZGMemoryAddress machHeaderAddress, NSString *mappedFilePath, ZGMemoryAddress *firstInstructionAddress, ZGMemoryAddress *slide, ZGMemorySize *textSize, ZGMemorySize *dataSize, ZGMemorySize *linkEditSize, NSMutableDictionary *cacheDictionary)
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
		ZGGetMachBinaryInfoFromFilePath(mappedFilePath, pointerSize, machHeaderAddress, firstInstructionAddress, slide, textSize, dataSize, linkEditSize, cacheDictionary);
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
						break;
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

static void ZGGetNearestMachBinaryInfo(ZGMemoryMap processTask, ZGMemorySize pointerSize, ZGMachBinary *dylinkerBinary, ZGMemoryAddress targetAddress, NSString **mappedFilePath, ZGMemoryAddress *machHeaderAddress, ZGMemoryAddress *textAddress, ZGMemoryAddress *slide, ZGMemorySize *textSize, ZGMemorySize *dataSize, ZGMemorySize *linkEditSize, NSMutableDictionary *cacheDictionary)
{
	ZGMachBinary *machBinary = ZGNearestMachBinary(ZGMachBinaries(processTask, pointerSize, dylinkerBinary), targetAddress);
	if (machBinary != nil)
	{
		ZGMemoryAddress returnedMachHeaderAddress = machBinary.headerAddress;
		ZGMemoryAddress returnedMachFilePathAddress = machBinary.filePathAddress;
		
		NSString *returnedFilePath = ZGFilePathAtAddress(processTask, returnedMachFilePathAddress);
		
		if (machHeaderAddress != NULL) *machHeaderAddress = returnedMachHeaderAddress;
		if (mappedFilePath != NULL) *mappedFilePath = returnedFilePath;
		
		ZGGetMachBinaryInfo(processTask, pointerSize, returnedMachHeaderAddress, returnedFilePath, textAddress, slide, textSize, dataSize, linkEditSize, cacheDictionary);
	}
}

NSString *ZGSectionName(ZGMemoryMap processTask, ZGMemorySize pointerSize, ZGMachBinary *dylinkerBinary, ZGMemoryAddress address, ZGMemorySize size, NSString **mappedFilePath, ZGMemoryAddress *relativeOffset, ZGMemoryAddress *slide, NSMutableDictionary *cacheDictionary)
{
	NSString *sectionName = nil;
	
	ZGMemoryAddress machHeaderAddress = 0;
	ZGMemorySize textSize = 0;
	ZGMemorySize dataSize = 0;
	ZGMemorySize linkEditSize = 0;
	
	ZGGetNearestMachBinaryInfo(processTask, pointerSize, dylinkerBinary, address, mappedFilePath, &machHeaderAddress, NULL, slide, &textSize, &dataSize, &linkEditSize, cacheDictionary);
	
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
	
	ZGGetNearestMachBinaryInfo(processTask, pointerSize, dylinkerBinary, targetAddress, mappedFilePath, &machHeaderAddressReturned, &textAddress, slide, &textSize, NULL, NULL, cacheDictionary);
	
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

