/*
 * Copyright (c) 2013 Mayur Pawashe
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

#import "ZGRegion.h"
#import <mach/mach_vm.h>
#import "NSArrayAdditions.h"
#import "ZGVirtualMemoryUserTags.h"

@implementation ZGRegion

+ (NSArray<ZGRegion *> *)regionsFromProcessTask:(ZGMemoryMap)processTask
{
	NSMutableArray<ZGRegion *> *regions = [[NSMutableArray alloc] init];
	
	ZGMemoryAddress address = 0x0;
	ZGMemorySize size;
	vm_region_basic_info_data_64_t info;
	mach_msg_type_number_t infoCount;
	mach_port_t objectName = MACH_PORT_NULL;
	
	while (YES)
	{
		infoCount = VM_REGION_BASIC_INFO_COUNT_64;
		if (mach_vm_region(processTask, &address, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &infoCount, &objectName) != KERN_SUCCESS)
		{
			break;
		}
		
		[regions addObject:[[ZGRegion alloc] initWithAddress:address size:size protection:info.protection userTag:0]];
		
		address += size;
	}
	
	return [NSArray arrayWithArray:regions];
}

+ (NSArray<ZGRegion *> *)regionsWithExtendedInfoFromProcessTask:(ZGMemoryMap)processTask
{
	NSMutableArray<ZGRegion *> *regions = [[NSMutableArray alloc] init];
	
	ZGMemoryAddress address = 0x0;
	ZGMemorySize size;
	vm_region_extended_info_data_t info;
	mach_msg_type_number_t infoCount;
	mach_port_t objectName = MACH_PORT_NULL;
	
	while (YES)
	{
		infoCount = VM_REGION_EXTENDED_INFO_COUNT;
		if (mach_vm_region(processTask, &address, &size, VM_REGION_EXTENDED_INFO, (vm_region_info_t)&info, &infoCount, &objectName) != KERN_SUCCESS)
		{
			break;
		}
		
		[regions addObject:[[ZGRegion alloc] initWithAddress:address size:size protection:info.protection userTag:info.user_tag]];
		
		address += size;
	}
	
	return [NSArray arrayWithArray:regions];
}

+ (NSArray<ZGRegion *> *)submapRegionsFromProcessTask:(ZGMemoryMap)processTask
{
	NSMutableArray<ZGRegion *> *regions = [[NSMutableArray alloc] init];
	
	ZGMemoryAddress address = 0x0;
	ZGMemorySize size;
	vm_region_submap_info_data_64_t info;
	mach_msg_type_number_t infoCount;
	natural_t depth = 0;
	
	while (YES)
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
			[regions addObject:[[ZGRegion alloc] initWithAddress:address size:size protection:info.protection userTag:info.user_tag]];
			
			address += size;
		}
	}
	
	return [NSArray arrayWithArray:regions];
}

+ (NSArray<ZGRegion *> *)submapRegionsFromProcessTask:(ZGMemoryMap)processTask region:(ZGRegion *)region
{
	NSMutableArray<ZGRegion *> *regions = [[NSMutableArray alloc] init];
	
	ZGMemoryAddress address = region.address;
	ZGMemorySize size = region.size; // possibly not necessary to initialize
	vm_region_submap_info_data_64_t info;
	mach_msg_type_number_t infoCount;
	natural_t depth = 0;
	
	while (YES)
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
			if (address >= region.address && address + size <= region.address + region.size)
			{
				[regions addObject:[[ZGRegion alloc] initWithAddress:address size:size protection:info.protection userTag:info.user_tag]];
			
				address += size;
				
				if (address >= region.address + region.size)
				{
					break;
				}
			}
			else
			{
				break;
			}
		}
	}
	
	return regions;
}

+ (NSArray<ZGRegion *> *)regionsFilteredFromRegions:(NSArray<ZGRegion *> *)regions beginAddress:(ZGMemoryAddress)beginAddress endAddress:(ZGMemoryAddress)endAddress protectionMode:(ZGProtectionMode)protectionMode includeSharedMemory:(BOOL)includeSharedMemory filterHeapAndStackData:(BOOL)filterHeapAndStackData totalStaticSegmentRanges:(NSArray<NSValue *> * _Nullable)totalStaticSegmentRanges excludeStaticDataFromSystemLibraries:(BOOL)excludeStaticDataFromSystemLibraries filePaths:(NSArray<NSString *> * _Nullable)filePaths
{
	return [regions zgFlatMapUsingBlock:^ZGRegion *(ZGRegion *region) {
		if (endAddress <= region.address || beginAddress >= region.address + region.size)
		{
			return nil;
		}
		
		if (!ZGMemoryProtectionMatchesProtectionMode(region.protection, protectionMode))
		{
			return nil;
		}
		
		if (!includeSharedMemory && ZGUserTagIsSharedMemory(region.userTag))
		{
			return nil;
		}
		
		if (filterHeapAndStackData && !ZGUserTagIsStackOrHeapData(region.userTag))
		{
			NSUInteger binaryIndex = 0;
			NSValue *matchingSegmentRangeValue = [totalStaticSegmentRanges zgBinarySearchUsingBlock:^NSComparisonResult(NSValue *__unsafe_unretained  _Nonnull currentValue) {
				NSRange totalSegmentRange = currentValue.rangeValue;
				if (region.address + region.size <= totalSegmentRange.location)
				{
					return NSOrderedDescending;
				}
				
				if (region.address >= totalSegmentRange.location + totalSegmentRange.length)
				{
					return NSOrderedAscending;
				}
				
				return NSOrderedSame;
			} getIndex:&binaryIndex];
			
			if (matchingSegmentRangeValue == nil)
			{
				return nil;
			}
			
			if (excludeStaticDataFromSystemLibraries && binaryIndex > 0 && filePaths != nil)
			{
				NSString *filePath = filePaths[binaryIndex];
				if ([filePath hasPrefix:@"/System/"] ||
					([filePath hasPrefix:@"/usr/"] && ![filePath hasPrefix:@"/usr/local/"]) ||
					[filePath hasPrefix:@"/Library/Apple/"])
				{
					return nil;
				}
			}
		}
		
		return region;
	}];
}

- (id)initWithAddress:(ZGMemoryAddress)address size:(ZGMemorySize)size protection:(ZGMemoryProtection)protection userTag:(uint32_t)userTag
{
	self = [super init];
	if (self != nil)
	{
		_address = address;
		_size = size;
		_protection = protection;
		_userTag = userTag;
	}
	return self;
}

- (id)initWithAddress:(ZGMemoryAddress)address size:(ZGMemorySize)size
{
	return [self initWithAddress:address size:size protection:0 userTag:0];
}

@end
