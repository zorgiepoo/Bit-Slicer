/*
 * Created by Mayur Pawashe on 8/29/13.
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

#import "ZGSearchFunctions.h"
#import "ZGSearchData.h"
#import "ZGSearchProgress.h"
#import "ZGRegion.h"
#import "ZGVirtualMemory.h"
#import "ZGVirtualMemoryHelpers.h"
#import "NSArrayAdditions.h"
#import "ZGSearchResults.h"
#import "ZGVariableProtocol.h"

ZGSearchResults *ZGSearchForData(ZGMemoryMap processTask, ZGSearchData *searchData, ZGSearchProgress *searchProgress, comparison_function_t comparisonFunction)
{
	ZGMemorySize dataAlignment = searchData.dataAlignment;
	ZGMemorySize dataSize = searchData.dataSize;
	
	void *searchValue = searchData.searchValue;
	BOOL shouldCompareStoredValues = searchData.shouldCompareStoredValues;
	
	ZGMemoryAddress dataBeginAddress = searchData.beginAddress;
	ZGMemoryAddress dataEndAddress = searchData.endAddress;
	BOOL shouldScanUnwritableValues = searchData.shouldScanUnwritableValues;
	
	ZGMemorySize pageSize = NSPageSize(); // sane default value in case ZGPageSize fails
	ZGPageSize(processTask, &pageSize);
	
	NSArray *regions;
	if (!shouldCompareStoredValues)
	{
		regions = [ZGRegionsForProcessTask(processTask) zgFilterUsingBlock:(zg_array_filter_t)^(ZGRegion *region) {
			return !(region.address < dataEndAddress && region.address + region.size > dataBeginAddress && region.protection & VM_PROT_READ && (shouldScanUnwritableValues || (region.protection & VM_PROT_WRITE)));
		}];
	}
	else
	{
		regions = searchData.savedData;
	}
	
	dispatch_async(dispatch_get_main_queue(), ^{
		searchProgress.initiatedSearch = YES;
		searchProgress.progressType = ZGSearchProgressMemoryScanning;
		searchProgress.maxProgress = regions.count;
	});
	
	NSMutableArray *allResultSets = [[NSMutableArray alloc] init];
	for (NSUInteger regionIndex = 0; regionIndex < regions.count; regionIndex++)
	{
		[allResultSets addObject:[[NSMutableData alloc] init]];
	}
	
	dispatch_apply(regions.count, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t regionIndex) {
		@autoreleasepool
		{
			ZGRegion *region = [regions objectAtIndex:regionIndex];
			ZGMemoryAddress address = region.address;
			ZGMemorySize size = region.size;
			void *regionBytes = region.bytes;
			
			NSMutableData *resultSet = [allResultSets objectAtIndex:regionIndex];
			
			char *bytes = NULL;
			if (!searchProgress.shouldCancelSearch && ZGReadBytes(processTask, address, (void **)&bytes, &size))
			{
				ZGMemorySize dataIndex = 0;
				while (dataIndex + dataSize <= size)
				{
					if (dataIndex % pageSize == 0 && searchProgress.shouldCancelSearch)
					{
						break;
					}
					
					if (dataBeginAddress <= address + dataIndex &&
						dataEndAddress >= address + dataIndex + dataSize)
					{	
						if (comparisonFunction(searchData, &bytes[dataIndex], !shouldCompareStoredValues ? (searchValue) : (regionBytes + dataIndex), dataSize))
						{
							ZGMemoryAddress variableAddress = address + dataIndex;
							[resultSet appendBytes:&variableAddress length:sizeof(variableAddress)];
						}
					}
					dataIndex += dataAlignment;
				}
				
				ZGFreeBytes(processTask, bytes, size);
			}
			
			dispatch_async(dispatch_get_main_queue(), ^{
				searchProgress.numberOfVariablesFound += resultSet.length / sizeof(ZGMemoryAddress);
				searchProgress.progress++;
			});
		}
	});
	
	NSArray *resultSets;
	
	if (searchProgress.shouldCancelSearch)
	{
		resultSets = [NSArray array];
	}
	else
	{
		resultSets = [allResultSets zgFilterUsingBlock:(zg_array_filter_t)^(NSMutableData *resultSet) {
			return resultSet.length == 0;
		}];
	}
	
	return [[ZGSearchResults alloc] initWithResultSets:resultSets dataSize:dataSize];
}

ZGSearchResults *ZGNarrowSearchForData(ZGMemoryMap processTask, ZGSearchData *searchData, ZGSearchProgress *searchProgress, comparison_function_t comparisonFunction, NSArray *variablesToSearchFirst, ZGSearchResults *previousSearchResults)
{
	ZGMemorySize dataSize = searchData.dataSize;
	void *searchValue = searchData.searchValue;
	
	ZGMemoryAddress beginningAddress = searchData.beginAddress;
	ZGMemoryAddress endingAddress = searchData.endAddress;
	
	// Get all relevant regions
	NSArray *regions = [ZGRegionsForProcessTask(processTask) zgFilterUsingBlock:(zg_array_filter_t)^(ZGRegion *region) {
		return !(region.address < endingAddress && region.address + region.size > beginningAddress && region.protection & VM_PROT_READ && (searchData.shouldScanUnwritableValues || (region.protection & VM_PROT_WRITE)));
	}];
	
	searchProgress.initiatedSearch = YES;
	searchProgress.progressType = ZGSearchProgressMemoryScanning;
	searchProgress.maxProgress = variablesToSearchFirst.count + previousSearchResults.addressCount;
	
	NSMutableData *newResultsData = [[NSMutableData alloc] init];
	
	__block ZGRegion *lastUsedRegion = nil;
	__block ZGRegion *lastUsedSavedRegion = nil;
	
	__block NSUInteger numberOfVariablesFound = 0;
	__block ZGMemorySize currentProgress = 0;
	
	ZGMemorySize maxProgress = searchProgress.maxProgress;
	
	// We'll update the progress at 5% intervals during our search
	ZGMemorySize numberOfVariablesRequiredToUpdateProgress = (ZGMemorySize)(maxProgress * 0.05);
	
	BOOL shouldCompareStoredValues = searchData.shouldCompareStoredValues;
	
	void (^searchVariableAddress)(ZGMemoryAddress, BOOL *) = ^(ZGMemoryAddress variableAddress, BOOL *stop) {
		void (^compareAndAddValue)(void)  = ^{
			void *compareValue = shouldCompareStoredValues ? ZGSavedValue(variableAddress, searchData, &lastUsedSavedRegion, dataSize) : searchValue;
			if (compareValue && comparisonFunction(searchData, lastUsedRegion->_bytes + (variableAddress - lastUsedRegion->_address), compareValue, dataSize))
			{
				[newResultsData appendBytes:&variableAddress length:sizeof(variableAddress)];
				numberOfVariablesFound++;
			}
		};
		
		if (beginningAddress <= variableAddress && endingAddress >= variableAddress + dataSize)
		{
			// Check if the variable is in the last region we scanned
			if (lastUsedRegion && variableAddress >= lastUsedRegion->_address && variableAddress + dataSize <= lastUsedRegion->_address + lastUsedRegion->_size)
			{
				compareAndAddValue();
			}
			else
			{
				ZGRegion *targetRegion = [regions zgBinarySearchUsingBlock:(zg_binary_search_t)^(ZGRegion * __unsafe_unretained region) {
					if (region->_address + region->_size <= variableAddress)
					{
						return NSOrderedAscending;
					}
					else if (region->_address >= variableAddress + dataSize)
					{
						return NSOrderedDescending;
					}
					else
					{
						return NSOrderedSame;
					}
				}];
				
				if (targetRegion)
				{
					if (!targetRegion->_bytes)
					{
						void *bytes = NULL;
						ZGMemorySize size = targetRegion->_size;
						
						if (ZGReadBytes(processTask, targetRegion->_address, &bytes, &size))
						{
							targetRegion->_bytes = bytes;
							targetRegion->_size = size;
							lastUsedRegion = targetRegion;
						}
					}
					else
					{
						lastUsedRegion = targetRegion;
					}
					
					if (lastUsedRegion == targetRegion && variableAddress >= targetRegion->_address && variableAddress + dataSize <= targetRegion->_address + targetRegion->_size)
					{
						compareAndAddValue();
					}
				}
			}
		}
		
		// Update progress
		if ((numberOfVariablesRequiredToUpdateProgress != 0 && currentProgress % numberOfVariablesRequiredToUpdateProgress == 0) || currentProgress + 1 == maxProgress)
		{
			if (searchProgress.shouldCancelSearch)
			{
				*stop = YES;
			}
			else
			{
				dispatch_async(dispatch_get_main_queue(), ^{
					searchProgress.progress = currentProgress;
					searchProgress.numberOfVariablesFound = numberOfVariablesFound;
				});
			}
		}
		
		currentProgress++;
	};
	
	BOOL shouldStopFirstIteration = NO;
	for (id <ZGVariableProtocol> variable in variablesToSearchFirst)
	{
		searchVariableAddress(variable.address, &shouldStopFirstIteration);
		if (shouldStopFirstIteration)
		{
			break;
		}
	}
	
	if (!shouldStopFirstIteration && previousSearchResults.addressCount > 0)
	{
		__block BOOL shouldStopSecondIteration = NO;
		[previousSearchResults enumerateUsingBlock:^(ZGMemoryAddress variableAddress, BOOL *stop) {
			searchVariableAddress(variableAddress, &shouldStopSecondIteration);
			if (shouldStopSecondIteration)
			{
				*stop = shouldStopSecondIteration;
			}
		}];
	}
	
	for (ZGRegion *region in regions)
	{
		if (region.bytes)
		{
			ZGFreeBytes(processTask, region.bytes, region.size);
		}
	}
	
	if (searchProgress.shouldCancelSearch)
	{
		newResultsData = [NSData data];
	}
	
	return [[ZGSearchResults alloc] initWithResultSets:@[newResultsData] dataSize:dataSize];
}
