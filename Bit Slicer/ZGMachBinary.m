/*
 * Created by Mayur Pawashe on 10/29/13.
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

#import "ZGMachBinary.h"
#import "ZGProcess.h"
#import "ZGVirtualMemory.h"
#import "ZGVirtualMemoryHelpers.h"
#import "ZGRegion.h"
#import "ZGMachBinaryInfo.h"

#import <mach-o/loader.h>
#import <mach-o/dyld_images.h>
#import <mach-o/fat.h>

NSString * const ZGMachBinaryPathToBinaryInfoDictionary = @"ZGMachBinaryPathToBinaryInfoDictionary";
NSString * const ZGMachBinaryPathToBinaryDictionary = @"ZGMachBinaryPathToBinaryDictionary";
NSString * const ZGFailedImageName = @"ZGFailedImageName";

@implementation ZGMachBinary

+ (instancetype)dynamicLinkerMachBinaryInProcess:(ZGProcess *)process
{
	ZGMemoryMap processTask = process.processTask;
	ZGMachBinary *dylinkerBinary = nil;
	// dyld is usually near the end, so it'll be faster to iterate backwards
	for (ZGRegion *region in [[ZGRegion regionsFromProcessTask:process.processTask] reverseObjectEnumerator])
	{
		if ((region.protection & VM_PROT_READ) == 0)
		{
			continue;
		}
		
		struct mach_header_64 *machHeader = NULL;
		ZGMemoryAddress machHeaderAddress = region.address;
		ZGMemorySize machHeaderSize = sizeof(*machHeader);
		
		if (!ZGReadBytes(processTask, machHeaderAddress, (void **)&machHeader, &machHeaderSize))
		{
			continue;
		}
		
		BOOL foundPotentialDylinkerMatch = (machHeaderSize >= sizeof(*machHeader)) && ((machHeader->magic == MH_MAGIC || machHeader->magic == MH_MAGIC_64) && machHeader->filetype == MH_DYLINKER);
		
		ZGFreeBytes(machHeader, machHeaderSize);
		
		if (!foundPotentialDylinkerMatch)
		{
			continue;
		}
		
		ZGMemoryAddress regionAddress = region.address;
		ZGMemorySize regionSize = region.size;
		void *regionBytes = NULL;
		
		if (!ZGReadBytes(processTask, regionAddress, &regionBytes, &regionSize))
		{
			continue;
		}
		
		machHeader = regionBytes;
		void *bytes = (void *)machHeader + ((machHeader->magic == MH_MAGIC) ? sizeof(struct mach_header) : sizeof(struct mach_header_64));
		
		for (uint32_t commandIndex = 0; commandIndex < machHeader->ncmds; commandIndex++)
		{
			struct dylinker_command *dylinkerCommand = bytes;
			
			if (dylinkerCommand->cmd == LC_ID_DYLINKER || dylinkerCommand->cmd == LC_LOAD_DYLINKER)
			{
				dylinkerBinary =
				[[ZGMachBinary alloc]
				 initWithHeaderAddress:regionAddress
				 filePathAddress:regionAddress + dylinkerCommand->name.offset + (ZGMemoryAddress)((uint8_t *)dylinkerCommand - (uint8_t *)regionBytes)];
				
				break;
			}
			
			bytes += dylinkerCommand->cmdsize;
		}
		
		ZGFreeBytes(regionBytes, regionSize);
		
		if (dylinkerBinary != nil)
		{
			break;
		}
	}
	return dylinkerBinary;
}

+ (NSArray *)machBinariesInProcess:(ZGProcess *)process
{
	ZGMachBinary *dylinkerBinary = process.dylinkerBinary;
	ZGMemorySize pointerSize = process.pointerSize;
	ZGMemoryMap processTask = process.processTask;
	
	NSMutableArray *machBinaries = [[NSMutableArray alloc] init];
	
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
					
					[machBinaries addObject:[[ZGMachBinary alloc] initWithHeaderAddress:machHeaderAddress filePathAddress:imageFilePathAddress]];
				}
				ZGFreeBytes(infoArrayBytes, infoArraySize);
			}
			ZGFreeBytes(allImageInfos, allImageInfosSize);
		}
		
		[machBinaries addObject:dylinkerBinary];
	}
	
	return [machBinaries sortedArrayUsingSelector:@selector(compare:)];
}

+ (instancetype)mainMachBinaryFromMachBinaries:(NSArray *)machBinaries
{
	return machBinaries.firstObject;
}

+ (instancetype)machBinaryNearestToAddress:(ZGMemoryAddress)address fromMachBinaries:(NSArray *)machBinaries
{
	ZGMachBinary *previousMachBinary = nil;
	
	for (ZGMachBinary *machBinary in machBinaries)
	{
		if (machBinary.headerAddress > address) break;
		
		previousMachBinary = machBinary;
	}
	
	return previousMachBinary;
}

+ (instancetype)machBinaryWithPartialImageName:(NSString *)partialImageName inProcess:(ZGProcess *)process fromCachedMachBinaries:(NSArray *)machBinaries error:(NSError * __autoreleasing *)error
{
	NSMutableDictionary *mappedPathDictionary = [process.cacheDictionary objectForKey:ZGMachBinaryPathToBinaryDictionary];
	ZGMachBinary *foundMachBinary = [mappedPathDictionary objectForKey:partialImageName];
	
	if (foundMachBinary == nil)
	{
		if (machBinaries == nil)
		{
			machBinaries = [self machBinariesInProcess:process];
		}
		
		for (ZGMachBinary *machBinary in machBinaries)
		{
			NSString *mappedFilePath = [machBinary filePathInProcess:process];
			if ([mappedFilePath hasSuffix:partialImageName])
			{
				foundMachBinary = machBinary;
				[mappedPathDictionary setObject:foundMachBinary forKey:partialImageName];
				break;
			}
		}
		
		if (foundMachBinary == nil && error != NULL)
		{
			*error = [NSError errorWithDomain:@"ZGFindExecutableImageFailed" code:1 userInfo:@{ZGFailedImageName : partialImageName}];
		}
	}
	return foundMachBinary;
}

- (id)initWithHeaderAddress:(ZGMemoryAddress)headerAddress filePathAddress:(ZGMemoryAddress)filePathAddress
{
	self = [super init];
	if (self != nil)
	{
		_headerAddress = headerAddress;
		_filePathAddress = filePathAddress;
	}
	return self;
}

- (NSComparisonResult)compare:(ZGMachBinary *)binaryImage
{
	return [@(self.headerAddress) compare:@(binaryImage.headerAddress)];
}

- (NSString *)filePathInProcess:(ZGProcess *)process
{
	NSString *filePath = nil;
	ZGMemoryMap processTask = process.processTask;
	ZGMemorySize pathSize = ZGGetStringSize(processTask, self.filePathAddress, ZGString8, 200, PATH_MAX);
	void *filePathBytes = NULL;
	if (ZGReadBytes(processTask, self.filePathAddress, &filePathBytes, &pathSize))
	{
		filePath = [[NSString alloc] initWithBytes:filePathBytes length:pathSize encoding:NSUTF8StringEncoding];
		ZGFreeBytes(filePathBytes, pathSize);
	}
	return filePath;
}

- (ZGMachBinaryInfo *)parseMachHeaderWithBytes:(const void *)machHeaderBytes startPointer:(const void *)startPointer dataLength:(ZGMemorySize)dataLength pointerSize:(size_t)pointerSize
{
	ZGMemoryAddress machHeaderAddress = self.headerAddress;
	
	const struct mach_header_64 *machHeader = machHeaderBytes;
	
	// If this is a fat binary that is being loaded from disk, we'll need to find our target architecture
	if (machHeader->magic == FAT_CIGAM) // not checking FAT_MAGIC, only interested in little endian
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
	
	ZGMachBinaryInfo *machBinaryInfo = nil;
	
	if (machHeader->magic == MH_MAGIC || machHeader->magic == MH_MAGIC_64)
	{
		void *segmentBytes = (void *)machHeader + ((machHeader->magic == MH_MAGIC) ? sizeof(struct mach_header) : sizeof(struct mach_header_64));
		if (segmentBytes + machHeader->sizeofcmds <= startPointer + dataLength)
		{
			machBinaryInfo = [[ZGMachBinaryInfo alloc] initWithMachHeaderAddress:machHeaderAddress segmentBytes:segmentBytes commandSize:machHeader->sizeofcmds];
		}
	}
	
	return machBinaryInfo;
}

- (ZGMachBinaryInfo *)machBinaryInfoFromFilePath:(NSString *)filePath process:(ZGProcess *)process
{
	NSMutableDictionary *machPathToInfoDictionary = [process.cacheDictionary objectForKey:ZGMachBinaryPathToBinaryInfoDictionary];
	
	ZGMachBinaryInfo *binaryInfo = [machPathToInfoDictionary objectForKey:filePath];
	
	if (binaryInfo == nil)
	{
		NSData *machFileData = [NSData dataWithContentsOfFile:filePath];
		if (machFileData != nil)
		{
			binaryInfo = [self parseMachHeaderWithBytes:machFileData.bytes startPointer:machFileData.bytes dataLength:machFileData.length pointerSize:process.pointerSize];
			if (binaryInfo != nil)
			{
				[machPathToInfoDictionary setObject:binaryInfo forKey:filePath];
			}
		}
	}
	
	return binaryInfo;
}

- (ZGMachBinaryInfo *)machBinaryInfoFromMemoryInProcess:(ZGProcess *)process
{
	ZGMachBinaryInfo *binaryInfo = nil;
	
	ZGMemoryAddress regionAddress = self.headerAddress;
	ZGMemorySize regionSize = 0x1;
	ZGMemoryBasicInfo unusedInfo;
	
	if (ZGRegionInfo(process.processTask, &regionAddress, &regionSize, &unusedInfo) && self.headerAddress >= regionAddress && self.headerAddress < regionAddress + regionSize)
	{
		void *regionBytes = NULL;
		if (ZGReadBytes(process.processTask, regionAddress, &regionBytes, &regionSize))
		{
			const struct mach_header_64 *machHeader = regionBytes + self.headerAddress - regionAddress;
			binaryInfo = [self parseMachHeaderWithBytes:machHeader startPointer:regionBytes dataLength:regionSize pointerSize:process.pointerSize];
			
			ZGFreeBytes(regionBytes, regionSize);
		}
	}
	
	return binaryInfo;
}

- (ZGMachBinaryInfo *)machBinaryInfoInProcess:(ZGProcess *)process
{
	ZGMachBinaryInfo *machBinaryInfo = [self machBinaryInfoFromMemoryInProcess:process];
	if (machBinaryInfo.totalSegmentRange.length == 0)
	{
		NSString *filePath = [self filePathInProcess:process];
		if (filePath.length > 0)
		{
			machBinaryInfo = [self machBinaryInfoFromFilePath:filePath process:process];
		}
	}
	return machBinaryInfo;
}

@end
