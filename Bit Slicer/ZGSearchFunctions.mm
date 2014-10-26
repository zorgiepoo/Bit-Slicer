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
#import "ZGStoredData.h"
#import "ZGMachBinaryInfo.h"

#import <stdint.h>
#include <cstdlib>
#include <stack>
#include <unordered_map>
#include <vector>

#define MAX_NUMBER_OF_LOCAL_BUFFER_ADDRESSES 4096U

template <typename T>
bool ZGByteArrayNotEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue);

#pragma mark Byte Order Swapping

template<typename T> T ZGSwapBytes(T value);

template<>
int8_t ZGSwapBytes<int8_t>(int8_t value)
{
	return value;
}

template<>
uint8_t ZGSwapBytes<uint8_t>(uint8_t value)
{
	return value;
}

template<>
int16_t ZGSwapBytes<int16_t>(int16_t value)
{
	return static_cast<int16_t>(CFSwapInt16(static_cast<uint16_t>(value)));
}

template<>
uint16_t ZGSwapBytes<uint16_t>(uint16_t value)
{
	return CFSwapInt16(value);
}

template<>
int32_t ZGSwapBytes<int32_t>(int32_t value)
{
	return static_cast<int32_t>(CFSwapInt32(static_cast<uint32_t>(value)));
}

template<>
uint32_t ZGSwapBytes<uint32_t>(uint32_t value)
{
	return CFSwapInt32(value);
}

template<>
int64_t ZGSwapBytes<int64_t>(int64_t value)
{
	return static_cast<int64_t>(CFSwapInt64(static_cast<uint64_t>(value)));
}

template<>
uint64_t ZGSwapBytes<uint64_t>(uint64_t value)
{
	return CFSwapInt64(value);
}

template<>
float ZGSwapBytes<float>(float value)
{
	CFSwappedFloat32 swappedValue = *(reinterpret_cast<CFSwappedFloat32 *>(&value));
	return CFConvertFloat32SwappedToHost(swappedValue);
}

template<>
double ZGSwapBytes<double>(double value)
{
	CFSwappedFloat64 swappedValue = *(reinterpret_cast<CFSwappedFloat64 *>(&value));
	return CFConvertFloat64SwappedToHost(swappedValue);
}

#pragma mark Boyer Moore Function

// Fast string-searching function from HexFiend's framework
extern "C" unsigned char* boyer_moore_helper(const unsigned char *haystack, const unsigned char *needle, unsigned long haystack_length, unsigned long needle_length, const unsigned long *char_jump, const unsigned long *match_jump);

// This portion of code is mostly stripped from a function in Hex Fiend's framework; it's wicked fast.
void ZGPrepareBoyerMooreSearch(const unsigned char *needle, const unsigned long needle_length, unsigned long *char_jump, unsigned long *match_jump)
{
	unsigned long *backup;
	unsigned long u, ua, ub;
	backup = match_jump + needle_length + 1;
	
	// heuristic #1 setup, simple text search
	for (u=0; u < sizeof char_jump / sizeof *char_jump; u++)
	{
		char_jump[u] = needle_length;
	}
	
	for (u = 0; u < needle_length; u++)
	{
		char_jump[(static_cast<unsigned char>(needle[u]))] = needle_length - u - 1;
	}
	
	// heuristic #2 setup, repeating pattern search
	for (u = 1; u <= needle_length; u++)
	{
		match_jump[u] = 2 * needle_length - u;
	}
	
	u = needle_length;
	ua = needle_length + 1;
	while (u > 0)
	{
		backup[u] = ua;
		while (ua <= needle_length && needle[u - 1] != needle[ua - 1])
		{
			if (match_jump[ua] > needle_length - u) match_jump[ua] = needle_length - u;
			ua = backup[ua];
		}
		u--; ua--;
	}
	
	for (u = 1; u <= ua; u++)
	{
		if (match_jump[u] > needle_length + ua - u) match_jump[u] = needle_length + ua - u;
	}
	
	ub = ua;
	while (ua <= needle_length)
	{
		ub = backup[ub];
		while (ua <= ub)
		{
			if (match_jump[ua] > ub - ua + needle_length)
			{
				match_jump[ua] = ub - ua + needle_length;
			}
			ua++;
		}
	}
}

#pragma mark Generic Searching

static bool ZGMemoryProtectionMatchesProtectionMode(ZGMemoryProtection memoryProtection, ZGProtectionMode protectionMode)
{
	return ((protectionMode == ZGProtectionAll && memoryProtection & VM_PROT_READ) || (protectionMode == ZGProtectionWrite && memoryProtection & VM_PROT_WRITE) || (protectionMode == ZGProtectionExecute && memoryProtection & VM_PROT_EXECUTE));
}

static NSArray *ZGFilterRegions(NSArray *regions, ZGMemoryAddress beginAddress, ZGMemoryAddress endAddress, ZGProtectionMode protectionMode)
{
	return [regions zgFilterUsingBlock:^(ZGRegion *region) {
		return static_cast<BOOL>(region.address < endAddress && region.address + region.size > beginAddress && ZGMemoryProtectionMatchesProtectionMode(region.protection, protectionMode));
	}];
}

typedef void (^zg_search_for_data_helper_t)(ZGMemorySize dataIndex, ZGMemoryAddress address, ZGMemorySize size, NSMutableData * __unsafe_unretained resultSet, void *bytes, void *regionBytes);

ZGSearchResults *ZGSearchForDataHelper(ZGMemoryMap processTask, ZGSearchData *searchData, id <ZGSearchProgressDelegate> delegate,  zg_search_for_data_helper_t helper)
{
	ZGMemorySize dataAlignment = searchData.dataAlignment;
	ZGMemorySize dataSize = searchData.dataSize;
	ZGMemorySize pointerSize = searchData.pointerSize;
	
	BOOL shouldCompareStoredValues = searchData.shouldCompareStoredValues;
	
	ZGMemoryAddress dataBeginAddress = searchData.beginAddress;
	ZGMemoryAddress dataEndAddress = searchData.endAddress;
	
	NSArray *regions;
	if (!shouldCompareStoredValues)
	{
		regions = ZGFilterRegions([ZGRegion regionsFromProcessTask:processTask], dataBeginAddress, dataEndAddress, searchData.protectionMode);
	}
	else
	{
		regions = searchData.savedData.regions;
	}
	
	ZGSearchProgress *searchProgress = [[ZGSearchProgress alloc] initWithProgressType:ZGSearchProgressMemoryScanning maxProgress:regions.count];
	
	if (delegate != nil)
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			[delegate progressWillBegin:searchProgress];
		});
	}
	
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
			
			ZGMemorySize dataIndex = 0;
			char *bytes = NULL;
			if (dataBeginAddress < address + size && dataEndAddress > address)
			{
				if (dataBeginAddress > address)
				{
					dataIndex = (dataBeginAddress - address);
					if (dataIndex % dataAlignment > 0)
					{
						dataIndex += dataAlignment - (dataIndex % dataAlignment);
					}
				}
				if (dataEndAddress < address + size)
				{
					size = dataEndAddress - address;
				}
				
				if (!searchProgress.shouldCancelSearch && ZGReadBytes(processTask, address, reinterpret_cast<void **>(&bytes), &size))
				{
					helper(dataIndex, address, size, resultSet, bytes, regionBytes);
					
					ZGFreeBytes(bytes, size);
				}
			}
			
			if (delegate != nil)
			{
				dispatch_async(dispatch_get_main_queue(), ^{
					searchProgress.numberOfVariablesFound += resultSet.length / pointerSize;
					searchProgress.progress++;
					[delegate progress:searchProgress advancedWithResultSet:resultSet];
				});
			}
		}
	});
	
	NSArray *resultSets;
	
	if (searchProgress.shouldCancelSearch)
	{
		resultSets = [NSArray array];
		
		// Deallocate results into separate queue since this could take some time
		__block id oldResultSets = allResultSets;
		allResultSets = nil;
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			oldResultSets = nil;
		});
	}
	else
	{
		resultSets = [allResultSets zgFilterUsingBlock:^(NSMutableData *resultSet) {
			return static_cast<BOOL>(resultSet.length != 0);
		}];
	}
	
	return [[ZGSearchResults alloc] initWithResultSets:resultSets dataSize:dataSize pointerSize:pointerSize];
}

template <typename T, typename P>
void ZGSearchWithFunctionHelperRegular(T *searchValue, bool (*comparisonFunction)(ZGSearchData *, T *, T *), ZGSearchData * __unsafe_unretained searchData, ZGMemorySize dataIndex, ZGMemorySize dataAlignment, ZGMemorySize endLimit, NSMutableData * __unsafe_unretained resultSet, ZGMemoryAddress address, void *bytes)
{
	while (dataIndex <= endLimit)
	{
		ZGMemorySize numberOfVariablesFound = 0;
		P memoryAddresses[MAX_NUMBER_OF_LOCAL_BUFFER_ADDRESSES];
		
		ZGMemorySize numberOfStepsToTake = MIN(MAX_NUMBER_OF_LOCAL_BUFFER_ADDRESSES, (endLimit + dataAlignment - dataIndex) / dataAlignment);
		for (ZGMemorySize stepIndex = 0; stepIndex < numberOfStepsToTake; stepIndex++)
		{
			if (comparisonFunction(searchData, static_cast<T *>(static_cast<void *>(static_cast<uint8_t *>(bytes) + dataIndex)), searchValue))
			{
				memoryAddresses[numberOfVariablesFound] = static_cast<P>(address + dataIndex);
				numberOfVariablesFound++;
			}
			
			dataIndex += dataAlignment;
		}
		
		[resultSet appendBytes:memoryAddresses length:sizeof(P) * numberOfVariablesFound];
	}
}

// like ZGSearchWithFunctionHelperRegular above except against stored values
template <typename T, typename P>
void ZGSearchWithFunctionHelperStored(T *regionBytes, bool (*comparisonFunction)(ZGSearchData *, T *, T *), ZGSearchData * __unsafe_unretained searchData, ZGMemorySize dataIndex, ZGMemorySize dataAlignment, ZGMemorySize endLimit, NSMutableData * __unsafe_unretained resultSet, ZGMemoryAddress address, void *bytes)
{
	while (dataIndex <= endLimit)
	{
		ZGMemorySize numberOfVariablesFound = 0;
		P memoryAddresses[MAX_NUMBER_OF_LOCAL_BUFFER_ADDRESSES];
		
		ZGMemorySize numberOfStepsToTake = MIN(MAX_NUMBER_OF_LOCAL_BUFFER_ADDRESSES, (endLimit + dataAlignment - dataIndex) / dataAlignment);
		for (ZGMemorySize stepIndex = 0; stepIndex < numberOfStepsToTake; stepIndex++)
		{
			if (comparisonFunction(searchData, (static_cast<T *>(static_cast<void *>(static_cast<uint8_t *>(bytes) + dataIndex))), static_cast<T *>(static_cast<void *>(static_cast<uint8_t *>(static_cast<void *>(regionBytes)) + dataIndex))))
			{
				memoryAddresses[numberOfVariablesFound] = static_cast<P>(address + dataIndex);
				numberOfVariablesFound++;
			}
			
			dataIndex += dataAlignment;
		}
		
		[resultSet appendBytes:memoryAddresses length:sizeof(P) * numberOfVariablesFound];
	}
}

template <typename T>
ZGSearchResults *ZGSearchWithFunction(bool (*comparisonFunction)(ZGSearchData *, T *, T *), ZGMemoryMap processTask, T *searchValue, ZGSearchData * __unsafe_unretained searchData, id <ZGSearchProgressDelegate> delegate)
{
	ZGMemorySize dataAlignment = searchData.dataAlignment;
	ZGMemorySize pointerSize = searchData.pointerSize;
	ZGMemorySize dataSize = searchData.dataSize;
	BOOL shouldCompareStoredValues = searchData.shouldCompareStoredValues;
	
	return ZGSearchForDataHelper(processTask, searchData, delegate, ^(ZGMemorySize dataIndex, ZGMemoryAddress address, ZGMemorySize size, NSMutableData * __unsafe_unretained resultSet, void *bytes, void *regionBytes) {
		ZGMemorySize endLimit = size - dataSize;
		
		if (!shouldCompareStoredValues)
		{
			if (pointerSize == sizeof(ZGMemoryAddress))
			{
				ZGSearchWithFunctionHelperRegular<T, ZGMemoryAddress>(searchValue, comparisonFunction, searchData, dataIndex, dataAlignment, endLimit, resultSet, address, bytes);
			}
			else
			{
				ZGSearchWithFunctionHelperRegular<T, ZG32BitMemoryAddress>(searchValue, comparisonFunction, searchData, dataIndex, dataAlignment, endLimit, resultSet, address, bytes);
			}
		}
		else
		{
			if (pointerSize == sizeof(ZGMemoryAddress))
			{
				ZGSearchWithFunctionHelperStored<T, ZGMemoryAddress>(static_cast<T *>(regionBytes), comparisonFunction, searchData, dataIndex, dataAlignment, endLimit, resultSet, address, bytes);
			}
			else
			{
				ZGSearchWithFunctionHelperStored<T, ZG32BitMemoryAddress>(static_cast<T *>(regionBytes), comparisonFunction, searchData, dataIndex, dataAlignment, endLimit, resultSet, address, bytes);
			}
		}
	});
}

template <typename P>
ZGSearchResults *_ZGSearchForBytes(ZGMemoryMap processTask, ZGSearchData *searchData, id <ZGSearchProgressDelegate> delegate)
{
	const unsigned long dataSize = searchData.dataSize;
	const unsigned char *searchValue = (searchData.bytesSwapped && searchData.swappedValue != NULL) ? static_cast<const unsigned char *>(searchData.swappedValue) : static_cast<const unsigned char *>(searchData.searchValue);
	ZGMemorySize dataAlignment = searchData.dataAlignment;
	
	return ZGSearchForDataHelper(processTask, searchData, delegate, ^(ZGMemorySize __unused dataIndex, ZGMemoryAddress address, ZGMemorySize size, NSMutableData * __unsafe_unretained resultSet, void *bytes, void * __unused regionBytes) {
		// generate the two Boyer-Moore auxiliary buffers
		unsigned long charJump[UCHAR_MAX + 1] = {0};
		unsigned long *matchJump = static_cast<unsigned long *>(malloc(2 * (dataSize + 1) * sizeof(*matchJump)));
		
		ZGPrepareBoyerMooreSearch(searchValue, dataSize, charJump, matchJump);
		
		unsigned char *foundSubstring = static_cast<unsigned char *>(bytes);
		unsigned long haystackLengthLeft = size;

		P memoryAddresses[MAX_NUMBER_OF_LOCAL_BUFFER_ADDRESSES];
		ZGMemorySize numberOfVariablesFound = 0;
		
		while (haystackLengthLeft >= dataSize)
		{
			foundSubstring = boyer_moore_helper(static_cast<const unsigned char *>(foundSubstring), searchValue, haystackLengthLeft, static_cast<unsigned long>(dataSize), static_cast<const unsigned long *>(charJump), static_cast<const unsigned long *>(matchJump));
			if (foundSubstring == NULL) break;
			
			ZGMemoryAddress foundAddress = address + static_cast<ZGMemoryAddress>(foundSubstring - static_cast<unsigned char *>(bytes));
			// boyer_moore_helper is only checking 0 .. dataSize-1 characters, so make a check to see if the last characters are equal
			if (foundAddress % dataAlignment == 0 && foundSubstring[dataSize-1] == searchValue[dataSize-1])
			{
				memoryAddresses[numberOfVariablesFound] = static_cast<P>(foundAddress);
				numberOfVariablesFound++;

				if (numberOfVariablesFound >= MAX_NUMBER_OF_LOCAL_BUFFER_ADDRESSES)
				{
					[resultSet appendBytes:memoryAddresses length:sizeof(memoryAddresses[0]) * numberOfVariablesFound];
					numberOfVariablesFound = 0;
				}
			}
			
			foundSubstring++;
			haystackLengthLeft = address + size - foundAddress - 1;
		}
		
		if (numberOfVariablesFound > 0)
		{
			[resultSet appendBytes:&memoryAddresses length:sizeof(memoryAddresses[0]) * numberOfVariablesFound];
		}

		free(matchJump);
	});
}

ZGSearchResults *ZGSearchForBytes(ZGMemoryMap processTask, ZGSearchData *searchData, id <ZGSearchProgressDelegate> delegate)
{
	ZGSearchResults *searchResults = nil;
	ZGMemorySize pointerSize = searchData.pointerSize;
	switch (pointerSize)
	{
		case sizeof(ZGMemoryAddress):
			searchResults = _ZGSearchForBytes<ZGMemoryAddress>(processTask, searchData, delegate);
			break;
		case sizeof(ZG32BitMemoryAddress):
			searchResults = _ZGSearchForBytes<ZG32BitMemoryAddress>(processTask, searchData, delegate);
			break;
	}
	return searchResults;
}

#pragma mark Recursive Pointer Scanner

struct ZGMemoryPointerEntry
{
	ZGMemoryAddress address;
	ZGMemoryAddress value;
};

static int ZGSortMemoryPointers(const void *entry1, const void *entry2)
{
	auto entry1Reference = static_cast<const ZGMemoryPointerEntry *>(entry1);
	auto entry2Reference = static_cast<const ZGMemoryPointerEntry *>(entry2);
	
	if (entry1Reference->value < entry2Reference->value)
	{
		return -1;
	}
	
	if (entry1Reference->value > entry2Reference->value)
	{
		return 1;
	}
	
	return 0;
}

static NSMutableData *ZGSearchForAllPointerCandidates(ZGMemoryMap processTask, ZGSearchData *searchData)
{
	ZGStoredData *storedData = [ZGStoredData storedDataFromProcessTask:processTask regions:ZGFilterRegions([ZGRegion regionsFromProcessTask:processTask], searchData.beginAddress, searchData.endAddress, searchData.protectionMode)];
	
	ZGMemoryAddress dataAlignment = searchData.dataAlignment;
	ZGMemorySize dataSize = searchData.dataSize;
	
	ZGRegion *firstRegion = storedData.regions[0];
	ZGMemoryAddress firstAddress = firstRegion.address;
	
	ZGMemoryAddress minAddress = MAX(firstAddress, searchData.beginAddress);
	ZGMemoryAddress maxAddress = searchData.endAddress;
	
	const uint16_t MAX_NUMBER_OF_STACK_ENTRIES = MAX_NUMBER_OF_LOCAL_BUFFER_ADDRESSES;
	
	NSMutableData *resultSet = [[NSMutableData alloc] init];
	
	for (ZGRegion *region in storedData.regions)
	{
		void * const bytes = region.bytes;
		const ZGMemoryAddress address = region.address;
		const ZGMemorySize size = region.size;
		
		ZGMemoryAddress dataIndex = 0x0;
		ZGMemoryAddress endLimit = size - dataSize;
		
		while (dataIndex <= endLimit)
		{
			ZGMemorySize numberOfVariablesFound = 0;
			ZGMemoryPointerEntry memoryAddressesEntries[MAX_NUMBER_OF_STACK_ENTRIES];
			
			ZGMemorySize numberOfStepsToTake = MIN(MAX_NUMBER_OF_STACK_ENTRIES, (endLimit + dataAlignment - dataIndex) / dataAlignment);
			for (ZGMemorySize stepIndex = 0; stepIndex < numberOfStepsToTake; stepIndex++)
			{
				ZGMemoryAddress value = *(static_cast<ZGMemoryAddress *>(static_cast<void *>(static_cast<uint8_t *>(bytes) + dataIndex)));
				if (value >= minAddress && value < maxAddress)
				{
					ZGMemoryPointerEntry newEntry;
					newEntry.address = static_cast<ZGMemoryAddress>(address + dataIndex);
					newEntry.value = value;
					
					memoryAddressesEntries[numberOfVariablesFound] = newEntry;
					numberOfVariablesFound++;
				}
				
				dataIndex += dataAlignment;
			}
			
			[resultSet appendBytes:memoryAddressesEntries length:sizeof(ZGMemoryPointerEntry) * numberOfVariablesFound];
		}
	}
	
	storedData = nil;
	
	qsort(const_cast<void *>(resultSet.bytes), resultSet.length / sizeof(ZGMemoryPointerEntry), sizeof(ZGMemoryPointerEntry), ZGSortMemoryPointers);
	
	return resultSet;
}

struct ZGRecursivePointerEntry
{
	ZGMemoryAddress address;
	ZGMemoryAddress offset;
	std::vector<ZGRecursivePointerEntry> *nextEntries;
	int16_t baseImageIndex;
};

static int ZGComparePointerValue(ZGMemoryAddress addressToSearch, ZGMemoryAddress candidateValue, ZGMemoryAddress maxOffset)
{
	if (addressToSearch > candidateValue + maxOffset)
	{
		return 1;
	}
	
	if (addressToSearch < candidateValue)
	{
		return -1;
	}
	
	return 0;
}

static NSUInteger ZGBinarySearch(const ZGMemoryPointerEntry *dataTable, const NSUInteger dataTableSize, const ZGMemoryAddress addressToSearch, const ZGMemoryAddress maxOffset)
{
	NSUInteger end = dataTableSize;
	NSUInteger start = 0;
	
	while (end > start)
	{
		NSUInteger mid = start + (end - start) / 2;
		const ZGMemoryPointerEntry *entry = dataTable + mid;
		
		switch (ZGComparePointerValue(addressToSearch, entry->value, maxOffset))
		{
			case 0:
				return mid;
			case 1:
				start = mid + 1;
				break;
			case -1:
				end = mid;
				break;
		}
	}
	
	return NSUIntegerMax;
}

static void ZGAddRecursivePointerEntry(std::vector<ZGRecursivePointerEntry> *recursivePointerEntries, const ZGMemoryPointerEntry *pointerEntry, ZGMemoryAddress addressToSearch)
{
	ZGRecursivePointerEntry newEntry = {pointerEntry->address, addressToSearch - pointerEntry->value, nullptr, -1};
	recursivePointerEntries->push_back(newEntry);
}

static std::vector<ZGRecursivePointerEntry> *ZGSearchPointersRecursively(std::unordered_map<ZGMemoryAddress, std::vector<ZGRecursivePointerEntry> *> &hashTable, std::unordered_map<ZGMemoryAddress, bool> &encounteredEntries, const ZGMemoryPointerEntry *dataTable, const NSUInteger dataTableSize, const ZGMemoryAddress addressToSearch, const ZGMemoryAddress maxOffset, const uint16_t level)
{
	std::vector<ZGRecursivePointerEntry> *nextPointerEntries = nullptr;
	
	const NSUInteger searchIndex = ZGBinarySearch(dataTable, dataTableSize, addressToSearch, maxOffset);
	if (searchIndex != NSUIntegerMax)
	{
		nextPointerEntries = new std::vector<ZGRecursivePointerEntry>;
		hashTable[addressToSearch] = nextPointerEntries;
		
		ZGAddRecursivePointerEntry(nextPointerEntries, dataTable + searchIndex, addressToSearch);
		
		NSUInteger belowIndex = searchIndex;
		while (belowIndex-- > 0)
		{
			auto candidate = dataTable + belowIndex;
			if (candidate->value < addressToSearch - maxOffset || candidate->value > addressToSearch)
			{
				break;
			}
			ZGAddRecursivePointerEntry(nextPointerEntries, candidate, addressToSearch);
		}
		
		NSUInteger aboveIndex = searchIndex;
		while (++aboveIndex < dataTableSize)
		{
			auto candidate = dataTable + aboveIndex;
			if (candidate->value < addressToSearch - maxOffset || candidate->value > addressToSearch)
			{
				break;
			}
			ZGAddRecursivePointerEntry(nextPointerEntries, candidate, addressToSearch);
		}
		
		const uint16_t nextLevel = level - 1;
		if (nextLevel > 0)
		{
			for (auto &recursiveEntry : *nextPointerEntries)
			{
				if (encounteredEntries.find(recursiveEntry.address) == encounteredEntries.end())
				{
					auto hashTableIterator = hashTable.find(recursiveEntry.address);
					if (hashTableIterator == hashTable.end())
					{
						encounteredEntries[recursiveEntry.address] = true;
						
						recursiveEntry.nextEntries = ZGSearchPointersRecursively(hashTable, encounteredEntries, dataTable, dataTableSize, recursiveEntry.address, maxOffset, nextLevel);
						hashTable[recursiveEntry.address] = recursiveEntry.nextEntries;
						
						encounteredEntries.erase(recursiveEntry.address);
					}
					else
					{
						recursiveEntry.nextEntries = hashTableIterator->second;
					}
				}
			}
		}
	}
	
	return nextPointerEntries;
}

/*
struct ZGPointerEntry
{
	ZGMemoryAddress address;
	ZGMemoryAddress offset;
	int16_t baseImageIndex;
};

#define MAX_NODE_POSITION_STACK_SIZE 50
struct ZGNodePositionStack
{
	uint64_t _positions[MAX_NODE_POSITION_STACK_SIZE];
	uint8_t _index = MAX_NODE_POSITION_STACK_SIZE;
	
	void push(uint64_t position)
	{
		_positions[--_index] = position;
	}
	
	void pop()
	{
		++_index;
	}
	
	uint64_t top() const
	{
		return _positions[_index];
	}
	
	const uint64_t *rawData() const
	{
		return _positions + _index;
	}
	
	uint8_t rawDataSize() const
	{
		return (MAX_NODE_POSITION_STACK_SIZE - _index) * sizeof(uint64_t);
	}
};

static uint64_t ZGSerializeRecursiveEntries(NSMutableData *pointerEntryData, NSMutableData *nodeNumberData, const std::vector<ZGRecursivePointerEntry> *recursivePointerEntries, ZGNodePositionStack nodePositions, const uint16_t level)
{
	const uint16_t nextLevel = level - 1;
	uint64_t nodePosition = nodePositions.top();
	for (auto recursiveEntry : *recursivePointerEntries)
	{
		const ZGPointerEntry newPointerEntry = {recursiveEntry.address, recursiveEntry.offset, recursiveEntry.baseImageIndex};
		[pointerEntryData appendBytes:&newPointerEntry length:sizeof(newPointerEntry)];
		
		nodePosition++;
		nodePositions.push(nodePosition);
		
		if (recursiveEntry.nextEntries != nullptr && nextLevel > 0 && recursiveEntry.nextEntries->size() > 0)
		{
			nodePosition = ZGSerializeRecursiveEntries(pointerEntryData, nodeNumberData, recursiveEntry.nextEntries, nodePositions, nextLevel);
		}
		else
		{
			[nodeNumberData appendBytes:nodePositions.rawData() length:nodePositions.rawDataSize()];
		}
		
		nodePositions.pop();
	}
	
	return nodePosition;
}

static NSString *ZGAddressFormulaForPointerPath(const uint64_t *nodeNumbers, const ZGPointerEntry *pointerEntries)
{
	NSString *addressFormula = nil;
	uint64_t nodeNumber;
	const uint64_t invalidNumber = 0;
	const uint64_t numberOfInvalidAttempts = 2;
	uint64_t currentAttempt = 0;
	
	while ((currentAttempt += ((nodeNumber = *nodeNumbers++) == invalidNumber)) < numberOfInvalidAttempts)
	{
		if (nodeNumber == invalidNumber) continue;
		
		const ZGPointerEntry *pointerEntry = pointerEntries + nodeNumber - 1;
		if (addressFormula == nil)
		{
			if (pointerEntry->offset > 0)
			{
				addressFormula = [NSString stringWithFormat:@"[base(%u) + 0x%llX] + 0x%llX", pointerEntry->baseImageIndex, pointerEntry->address, pointerEntry->offset];
			}
			else
			{
				addressFormula = [NSString stringWithFormat:@"[base(%u) + 0x%llX]", pointerEntry->baseImageIndex, pointerEntry->address];
			}
		}
		else
		{
			if (pointerEntry->offset > 0)
			{
				addressFormula = [NSString stringWithFormat:@"[%@] + 0x%llX", addressFormula, pointerEntry->offset];
			}
			else
			{
				addressFormula = [NSString stringWithFormat:@"[%@]", addressFormula];
			}
		}
	}
	
	return addressFormula;
}

static NSData *ZGFilterStaticNodes(NSData *nodeNumberData, NSData *pointerEntryData)
{
	NSMutableData *filteredNodeNumberData = [[NSMutableData alloc] init];
	
	const auto pointerEntries = static_cast<const ZGPointerEntry *>(pointerEntryData.bytes);
	
	const auto nodeNumbers = static_cast<const uint64_t *>(nodeNumberData.bytes);
	const NSUInteger numberOfNodes = nodeNumberData.length / sizeof(*nodeNumbers);
	
	const uint64_t invalidNumber = 0;
	
	auto visitedStartingNodes = new std::unordered_map<uint64_t, bool>;
	
	uint16_t count = 0;
	
	if (numberOfNodes > 1)
	{
		bool startWriting = false;
		for (NSUInteger nodeIndex = 0; nodeIndex < numberOfNodes; nodeIndex++)
		{
			auto nodeNumber = nodeNumbers[nodeIndex];
			if (nodeNumber != invalidNumber)
			{
				auto pointerEntry = pointerEntries[nodeNumber - 1];
				
				if (!startWriting && pointerEntry.baseImageIndex != -1 && visitedStartingNodes->find(nodeNumber - 1) == visitedStartingNodes->end())
				{
					(*visitedStartingNodes)[nodeNumber - 1] = true;
					[filteredNodeNumberData appendBytes:&invalidNumber length:sizeof(invalidNumber)];
					startWriting = true;
					count += 1;
				}
				
				if (startWriting)
				{
					[filteredNodeNumberData appendBytes:&nodeNumber length:sizeof(nodeNumber)];
				}
			}
			else
			{
				startWriting = false;
			}
		}
	}
	else
	{
		[filteredNodeNumberData appendBytes:&invalidNumber length:sizeof(invalidNumber)];
	}
	
	delete visitedStartingNodes;
	
	NSLog(@"Count paths really are %u", count);
	
	return filteredNodeNumberData;
}
 
 */

static bool ZGFindMachSegment(const NSRange *staticMachSegments, const NSUInteger numberOfSegments, ZGRecursivePointerEntry &recursivePointerEntry)
{
	NSUInteger end = numberOfSegments;
	NSUInteger start = 0;
	
	while (end > start)
	{
		NSUInteger mid = start + (end - start) / 2;
		NSRange segmentRange = staticMachSegments[mid];
		
		if (recursivePointerEntry.address < segmentRange.location)
		{
			end = mid;
		}
		else if (recursivePointerEntry.address >= segmentRange.location + segmentRange.length)
		{
			start = mid + 1;
		}
		else
		{
			recursivePointerEntry.baseImageIndex = static_cast<int16_t>(mid);
			recursivePointerEntry.address -= segmentRange.location;
			return true;
		}
	}
	
	return false;
}

static void ZGAnnotateTreeStaticInfo(const NSRange *staticMachSegments, const NSUInteger numberOfSegments, std::unordered_map<ZGMemoryAddress, int16_t> &staticsHashTable, std::unordered_map<ZGMemoryAddress, bool> &visitedEntries, std::vector<ZGRecursivePointerEntry> *recursivePointerEntries)
{
	for (auto &recursiveEntry : *recursivePointerEntries)
	{
		auto iterator = staticsHashTable.find(recursiveEntry.address);
		if (iterator == staticsHashTable.end())
		{
			ZGFindMachSegment(staticMachSegments, numberOfSegments, recursiveEntry);
			staticsHashTable[recursiveEntry.address] = recursiveEntry.baseImageIndex;
		}
		else
		{
			recursiveEntry.baseImageIndex = iterator->second;
		}
		
		if (recursiveEntry.nextEntries != nullptr && visitedEntries.find(recursiveEntry.address) == visitedEntries.end())
		{
			visitedEntries[recursiveEntry.address] = true;
			ZGAnnotateTreeStaticInfo(staticMachSegments, numberOfSegments, staticsHashTable, visitedEntries, recursiveEntry.nextEntries);
		}
	}
}

static std::vector<bool> ZGFliterTreeForStaticInfo(std::unordered_map<ZGMemoryAddress, std::vector<bool>> *staticsHashTable, std::vector<ZGRecursivePointerEntry> *recursivePointerEntries)
{
	std::vector<bool> statics;
	
	for (auto &recursiveEntry : *recursivePointerEntries)
	{
		if (recursiveEntry.nextEntries != nullptr && recursiveEntry.nextEntries->size() > 0)
		{
			std::vector<bool> staticsInside;
			auto hashIterator = staticsHashTable->find(recursiveEntry.address);
			if (hashIterator == staticsHashTable->end())
			{
				staticsInside = ZGFliterTreeForStaticInfo(staticsHashTable, recursiveEntry.nextEntries);
				
				size_t staticsInsideSize = staticsInside.size();
				for (size_t staticInsideIndex = 0; staticInsideIndex < staticsInsideSize; staticInsideIndex++)
				{
					size_t reverseIndex = staticsInsideSize - staticInsideIndex - 1;
					if (!staticsInside[reverseIndex])
					{
						recursiveEntry.nextEntries->erase(recursiveEntry.nextEntries->begin() + static_cast<ssize_t>(reverseIndex));
						staticsInside.erase(staticsInside.begin() + static_cast<ssize_t>(reverseIndex));
					}
				}
				
				(*staticsHashTable)[recursiveEntry.address] = staticsInside;
			}
			else
			{
				staticsInside = hashIterator->second;
			}
			
			statics.push_back(staticsInside.size() > 0);
		}
		else
		{
			statics.push_back(recursiveEntry.baseImageIndex != -1);
		}
	}
	
	return statics;
}

struct ZGFilterTreeKey
{
	ZGMemoryAddress address;
	uint16_t level;
	
	bool operator==(const ZGFilterTreeKey &other) const
	{
		return address == other.address && level == other.level;
	}
};

template <>
struct std::hash<ZGFilterTreeKey>
{
	std::size_t operator()(const ZGFilterTreeKey& key) const
	{
		return key.address + key.level;
	}
};

static uint64_t ZGCountFilteredTree(const std::vector<ZGRecursivePointerEntry> *recursivePointerEntries, const uint16_t level, std::unordered_map<ZGFilterTreeKey, uint64_t> *alreadyVisited)
{
	uint64_t count = 0;
	const uint16_t nextLevel = level - 1;
	for (auto &entry : *recursivePointerEntries)
	{
		if (entry.nextEntries == nullptr || entry.nextEntries->size() == 0 || nextLevel == 0)
		{
			count += (entry.baseImageIndex == -1) ? 0 : 1;
		}
		else
		{
			ZGFilterTreeKey key = {entry.address, level};
			auto iterator = alreadyVisited->find(key);
			
			if (iterator == alreadyVisited->end())
			{
				uint64_t result = ZGCountFilteredTree(entry.nextEntries, nextLevel, alreadyVisited);
				if (result < entry.nextEntries->size())
				{
					result += (entry.baseImageIndex == -1) ? 0 : 1;
				}
				count += result;
				
				(*alreadyVisited)[key] = result;
			}
			else
			{
				count += iterator->second;
			}
		}
	}
	return count;
}

static uint64_t ZGCountTree(const std::vector<ZGRecursivePointerEntry> *recursivePointerEntries, std::unordered_map<ZGMemoryAddress, uint64_t> *alreadyVisited)
{
	uint64_t count = 0;
	for (auto &entry : *recursivePointerEntries)
	{
		if (entry.nextEntries == nullptr || entry.nextEntries->size() == 0)
		{
			count++;
		}
		else
		{
			auto iterator = alreadyVisited->find(entry.address);
			if (iterator == alreadyVisited->end())
			{
				uint64_t result = ZGCountTree(entry.nextEntries, alreadyVisited) + 1;
				(*alreadyVisited)[entry.address] = result;
				count += result;
			}
			else
			{
				count += iterator->second;
			}
		}
	}
	return count;
}

static ZGSearchResults *ZGSearchForPointer(ZGMemoryMap processTask, ZGSearchData *searchData, id <ZGSearchProgressDelegate> delegate)
{
	ZGSearchProgress *searchProgress = [[ZGSearchProgress alloc] initWithProgressType:ZGSearchProgressMemoryScanning maxProgress:10];
	
	if (delegate != nil)
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			[delegate progressWillBegin:searchProgress];
		});
	}
	
	ZGMemorySize dataSize = searchData.dataSize;
	
	NSMutableData *memoryPointerEntries = ZGSearchForAllPointerCandidates(processTask, searchData);
	
	uint16_t numberOfLevels = searchData.numberOfPointerLevels;
	
	NSLog(@"Levels %d, searching...", numberOfLevels);
	
	auto allocatedEntries = new std::unordered_map<ZGMemoryAddress, std::vector<ZGRecursivePointerEntry> *>;
	std::unordered_map<ZGMemoryAddress, bool> encounteredEntries;
	const auto dataTable = static_cast<ZGMemoryPointerEntry *>(const_cast<void *>(memoryPointerEntries.bytes));
	const auto dataTableSize = memoryPointerEntries.length / sizeof(ZGMemoryPointerEntry);
	auto recursivePointerEntries = ZGSearchPointersRecursively(*allocatedEntries, encounteredEntries, dataTable, dataTableSize, *static_cast<ZGMemoryAddress *>(searchData.searchValue), searchData.maxPointerOffset, numberOfLevels);
	
	if (recursivePointerEntries == nullptr)
	{
		NSLog(@"Blah.. it was null");
	}
	
	NSLog(@"Found recursive entries...");
	
	NSArray *machBinariesInfo = searchData.machBinariesInfo;
	NSRange *segmentRanges = new NSRange[machBinariesInfo.count];
	
	NSUInteger machBinaryInfoIndex = 0;
	for (ZGMachBinaryInfo *machBinaryInfo in machBinariesInfo)
	{
		segmentRanges[machBinaryInfoIndex++] = machBinaryInfo.totalSegmentRange;
		NSLog(@"%lu: 0x%lX", machBinaryInfoIndex - 1, machBinaryInfo.totalSegmentRange.location);
	}
	
	NSLog(@"Annotating...");
	
	auto staticsHashTable = new std::unordered_map<ZGMemoryAddress, int16_t>;
	auto visitedStaticEntries = new std::unordered_map<ZGMemoryAddress, bool>;
	ZGAnnotateTreeStaticInfo(segmentRanges, machBinariesInfo.count, *staticsHashTable, *visitedStaticEntries, recursivePointerEntries);
	
	delete staticsHashTable;
	delete visitedStaticEntries;
	delete[] segmentRanges;
	
	NSLog(@"Pre Filtering statics...");
	
	auto hasStaticHashTable = new std::unordered_map<ZGMemoryAddress, std::vector<bool>>;
	ZGFliterTreeForStaticInfo(hasStaticHashTable, recursivePointerEntries);
	delete hasStaticHashTable;
	
	NSLog(@"Starting count...");
	auto countVisitors = new std::unordered_map<ZGMemoryAddress, uint64_t>;
	NSLog(@"Plain count is %llu", ZGCountTree(recursivePointerEntries, countVisitors));
	
	delete countVisitors;
	
	auto filterCountVisitors = new std::unordered_map<ZGFilterTreeKey, uint64_t>;
	NSLog(@"Filter Count will be %llu", ZGCountFilteredTree(recursivePointerEntries, numberOfLevels, filterCountVisitors));
	
	delete filterCountVisitors;
	
	/*
	NSLog(@"Serializing...");
	NSMutableData *pointerEntryData = [[NSMutableData alloc] init];
	NSMutableData *nodeNumberData = [[NSMutableData alloc] init];
	
	assert(numberOfLevels <= MAX_NODE_POSITION_STACK_SIZE);
	
	ZGNodePositionStack nodePositions;
	nodePositions.push(0);
	ZGSerializeRecursiveEntries(pointerEntryData, nodeNumberData, recursivePointerEntries, nodePositions, numberOfLevels);
	
	for (auto entry : *allocatedEntries)
	{
		delete (entry.second);
	}
	
	NSLog(@"Post filtering...");
	NSData *reducedNodeNumberData = ZGFilterStaticNodes(nodeNumberData, pointerEntryData);
	
	NSLog(@"Reduced vs real count: %lu, %lu", reducedNodeNumberData.length, nodeNumberData.length);
	
	NSLog(@"Formula..: %@", ZGAddressFormulaForPointerPath(static_cast<const uint64_t *>(reducedNodeNumberData.bytes), static_cast<const ZGPointerEntry *>(pointerEntryData.bytes)));
	
	NSLog(@"%lu, %lu", reducedNodeNumberData.length, pointerEntryData.length);
	 */
	
	NSLog(@"Done..");
	
	return [[ZGSearchResults alloc] initWithResultSets:@[] dataSize:dataSize pointerSize:sizeof(ZGMemoryAddress)];
}

#pragma mark Integers

template <typename T>
bool ZGIntegerEquals(ZGSearchData *__unused __unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return *variableValue == *compareValue;
}

template <typename T>
bool ZGIntegerFastSwappedEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T * __unused compareValue)
{
	return ZGIntegerEquals(searchData, variableValue, static_cast<T *>(searchData->_swappedValue));
}

template <typename T>
bool ZGIntegerNotEquals(ZGSearchData * __unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return !ZGIntegerEquals(searchData, variableValue, compareValue);
}

template <typename T>
bool ZGIntegerFastSwappedNotEquals(ZGSearchData * __unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return !ZGIntegerFastSwappedEquals(searchData, variableValue, compareValue);
}

template <typename T>
bool ZGIntegerGreaterThan(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return (*variableValue > *compareValue) && (searchData->_rangeValue == NULL || *variableValue < *static_cast<T *>(searchData->_rangeValue));
}

template <typename T>
bool ZGIntegerSwappedGreaterThan(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	return ZGIntegerGreaterThan(searchData, &swappedVariableValue, compareValue);
}

template <typename T>
bool ZGIntegerSwappedGreaterThanStored(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	return ZGIntegerGreaterThan(searchData, &swappedVariableValue, &swappedCompareValue);
}

template <typename T>
bool ZGIntegerLesserThan(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return (*variableValue < *compareValue) && (searchData->_rangeValue == NULL || *variableValue > *static_cast<T *>(searchData->_rangeValue));
}

template <typename T>
bool ZGIntegerSwappedLesserThan(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	return ZGIntegerLesserThan(searchData, &swappedVariableValue, compareValue);
}

template <typename T>
bool ZGIntegerSwappedLesserThanStored(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	return ZGIntegerLesserThan(searchData, &swappedVariableValue, &swappedCompareValue);
}

template <typename T>
bool ZGIntegerEqualsLinear(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T newCompareValue = *static_cast<T *>(searchData->_multiplicativeConstant) * *compareValue + *(static_cast<T *>(searchData->_additiveConstant));
	return ZGIntegerEquals(searchData, variableValue, &newCompareValue);
}

template <typename T>
bool ZGIntegerSwappedEqualsLinear(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	T newCompareValue = *static_cast<T *>(searchData->_multiplicativeConstant) * swappedCompareValue + *(static_cast<T *>(searchData->_additiveConstant));
	
	return ZGIntegerEquals(searchData, &swappedVariableValue, &newCompareValue);
}

template <typename T>
bool ZGIntegerNotEqualsLinear(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T newCompareValue = *static_cast<T *>(searchData->_multiplicativeConstant) * *compareValue + *(static_cast<T *>(searchData->_additiveConstant));
	return ZGIntegerNotEquals(searchData, variableValue, &newCompareValue);
}

template <typename T>
bool ZGIntegerSwappedNotEqualsLinear(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	return ZGIntegerNotEqualsLinear(searchData, &swappedVariableValue, &swappedCompareValue);
}

template <typename T>
bool ZGIntegerGreaterThanLinear(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T newCompareValue = *static_cast<T *>(searchData->_multiplicativeConstant) * *compareValue + *(static_cast<T *>(searchData->_additiveConstant));
	return ZGIntegerGreaterThan(searchData, variableValue, &newCompareValue);
}

template <typename T>
bool ZGIntegerSwappedGreaterThanLinear(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	return ZGIntegerGreaterThanLinear(searchData, &swappedVariableValue, &swappedCompareValue);
}

template <typename T>
bool ZGIntegerLesserThanLinear(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T newCompareValue = *static_cast<T *>(searchData->_multiplicativeConstant) * *compareValue + *(static_cast<T *>(searchData->_additiveConstant));
	return ZGIntegerLesserThan(searchData, variableValue, &newCompareValue);
}

template <typename T>
bool ZGIntegerSwappedLesserThanLinear(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	return ZGIntegerLesserThanLinear(searchData, &swappedVariableValue, &swappedCompareValue);
}

#define ZGHandleIntegerType(functionType, type, integerQualifier, dataType, processTask, searchData, delegate) \
	case dataType: \
		if (integerQualifier == ZGSigned) \
			retValue = ZGSearchWithFunction(functionType, processTask, static_cast<type *>(searchData.searchValue), searchData, delegate); \
		else \
			retValue = ZGSearchWithFunction(functionType, processTask, static_cast<u##type *>(searchData.searchValue), searchData, delegate); \
		break

#define ZGHandleIntegerCase(dataType, function) \
if (dataType == ZGPointer) {\
	switch (searchData.dataSize) {\
		case sizeof(ZGMemoryAddress):\
			retValue = ZGSearchWithFunction(function, processTask, static_cast<uint64_t *>(searchData.searchValue), searchData, delegate);\
			break;\
		case sizeof(ZG32BitMemoryAddress):\
			retValue = ZGSearchWithFunction(function, processTask, static_cast<uint32_t *>(searchData.searchValue), searchData, delegate);\
			break;\
	}\
}\
else {\
	switch (dataType) {\
		ZGHandleIntegerType(function, int8_t, integerQualifier, ZGInt8, processTask, searchData, delegate);\
		ZGHandleIntegerType(function, int16_t, integerQualifier, ZGInt16, processTask, searchData, delegate);\
		ZGHandleIntegerType(function, int32_t, integerQualifier, ZGInt32, processTask, searchData, delegate);\
		ZGHandleIntegerType(function, int64_t, integerQualifier, ZGInt64, processTask, searchData, delegate);\
		case ZGFloat: \
		case ZGDouble: \
		case ZGString8: \
		case ZGString16: \
		case ZGPointer: \
		case ZGByteArray: \
		case ZGScript: \
		break;\
	}\
}\

ZGSearchResults *ZGSearchForIntegers(ZGMemoryMap processTask, ZGSearchData *searchData, id <ZGSearchProgressDelegate> delegate, ZGVariableType dataType, ZGVariableQualifier integerQualifier, ZGFunctionType functionType)
{
	id retValue = nil;
	
	switch (functionType)
	{
		case ZGEquals:
			if (searchData.bytesSwapped)
			{
				ZGHandleIntegerCase(dataType, ZGIntegerFastSwappedEquals);
			}
			else
			{
				ZGHandleIntegerCase(dataType, ZGIntegerEquals);
			}
			break;
		case ZGEqualsStored:
			ZGHandleIntegerCase(dataType, ZGIntegerEquals);
			break;
		case ZGNotEquals:
			if (searchData.bytesSwapped)
			{
				ZGHandleIntegerCase(dataType, ZGIntegerFastSwappedNotEquals);
			}
			else
			{
				ZGHandleIntegerCase(dataType, ZGIntegerNotEquals);
			}
			break;
		case ZGNotEqualsStored:
			ZGHandleIntegerCase(dataType, ZGIntegerNotEquals);
			break;
		case ZGGreaterThan:
			if (searchData.bytesSwapped)
			{
				ZGHandleIntegerCase(dataType, ZGIntegerSwappedGreaterThan);
			}
			else
			{
				ZGHandleIntegerCase(dataType, ZGIntegerGreaterThan);
			}
			break;
		case ZGGreaterThanStored:
			if (searchData.bytesSwapped)
			{
				ZGHandleIntegerCase(dataType, ZGIntegerSwappedGreaterThanStored);
			}
			else
			{
				ZGHandleIntegerCase(dataType, ZGIntegerGreaterThan);
			}
			break;
		case ZGLessThan:
			if (searchData.bytesSwapped)
			{
				ZGHandleIntegerCase(dataType, ZGIntegerSwappedLesserThan);
			}
			else
			{
				ZGHandleIntegerCase(dataType, ZGIntegerLesserThan);
			}
			break;
		case ZGLessThanStored:
			if (searchData.bytesSwapped)
			{
				ZGHandleIntegerCase(dataType, ZGIntegerSwappedLesserThanStored);
			}
			else
			{
				ZGHandleIntegerCase(dataType, ZGIntegerLesserThan);
			}
			break;
		case ZGEqualsStoredLinear:
			if (searchData.bytesSwapped)
			{
				ZGHandleIntegerCase(dataType, ZGIntegerSwappedEqualsLinear);
			}
			else
			{
				ZGHandleIntegerCase(dataType, ZGIntegerEqualsLinear);
			}
			break;
		case ZGNotEqualsStoredLinear:
			if (searchData.bytesSwapped)
			{
				ZGHandleIntegerCase(dataType, ZGIntegerSwappedNotEqualsLinear);
			}
			else
			{
				ZGHandleIntegerCase(dataType, ZGIntegerNotEqualsLinear);
			}
			break;
		case ZGGreaterThanStoredLinear:
			if (searchData.bytesSwapped)
			{
				ZGHandleIntegerCase(dataType, ZGIntegerSwappedGreaterThanLinear);
			}
			else
			{
				ZGHandleIntegerCase(dataType, ZGIntegerGreaterThanLinear);
			}
			break;
		case ZGLessThanStoredLinear:
			if (searchData.bytesSwapped)
			{
				ZGHandleIntegerCase(dataType, ZGIntegerSwappedLesserThanLinear);
			}
			else
			{
				ZGHandleIntegerCase(dataType, ZGIntegerLesserThanLinear);
			}
			break;
	}
	
	return retValue;
}

#pragma mark Floating Points

template <typename T>
bool ZGFloatingPointEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return ABS(*(static_cast<T *>(variableValue)) - *(static_cast<T *>(compareValue))) <= searchData->_epsilon;
}

template <typename T>
bool ZGFloatingPointSwappedEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	return ZGFloatingPointEquals(searchData, &swappedVariableValue, compareValue);
}

template <typename T>
bool ZGFloatingPointSwappedEqualsStored(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	return ZGFloatingPointEquals(searchData, &swappedVariableValue, &swappedCompareValue);
}

template <typename T>
bool ZGFloatingPointNotEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return !ZGFloatingPointEquals(searchData, variableValue, compareValue);
}

template <typename T>
bool ZGFloatingPointSwappedNotEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return !ZGFloatingPointSwappedEquals(searchData, variableValue, compareValue);
}

template <typename T>
bool ZGFloatingPointSwappedNotEqualsStored(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return !ZGFloatingPointSwappedEqualsStored(searchData, variableValue, compareValue);
}

template <typename T>
bool ZGFloatingPointGreaterThan(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return *variableValue > *compareValue && (searchData->_rangeValue == NULL || *variableValue < *static_cast<T *>(searchData->_rangeValue));
}

template <typename T>
bool ZGFloatingPointSwappedGreaterThan(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	return ZGFloatingPointGreaterThan(searchData, &swappedVariableValue, compareValue);
}

template <typename T>
bool ZGFloatingPointSwappedGreaterThanStored(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	return ZGFloatingPointGreaterThan(searchData, &swappedVariableValue, &swappedCompareValue);
}

template <typename T>
bool ZGFloatingPointLesserThan(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return *variableValue < *compareValue && (searchData->_rangeValue == NULL || *variableValue > *static_cast<T *>(searchData->_rangeValue));
}

template <typename T>
bool ZGFloatingPointSwappedLesserThan(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	return ZGFloatingPointLesserThan(searchData, &swappedVariableValue, compareValue);
}

template <typename T>
bool ZGFloatingPointSwappedLesserThanStored(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	return ZGFloatingPointLesserThan(searchData, &swappedVariableValue, &swappedCompareValue);
}

template <typename T>
bool ZGFloatingPointEqualsLinear(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T newCompareValue = *static_cast<T *>(searchData->_multiplicativeConstant) * *compareValue + *(static_cast<T *>(searchData->_additiveConstant));
	return ZGFloatingPointEquals(searchData, variableValue, &newCompareValue);
}

template <typename T>
bool ZGFloatingPointSwappedEqualsLinear(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	return ZGFloatingPointEqualsLinear(searchData, &swappedVariableValue, &swappedCompareValue);
}

template <typename T>
bool ZGFloatingPointNotEqualsLinear(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T newCompareValue = *(static_cast<T *>(searchData->_multiplicativeConstant)) * *compareValue + *(static_cast<T *>(searchData->_additiveConstant));
	return ZGFloatingPointNotEquals(searchData, variableValue, &newCompareValue);
}

template <typename T>
bool ZGFloatingPointSwappedNotEqualsLinear(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	return ZGFloatingPointNotEqualsLinear(searchData, &swappedVariableValue, &swappedCompareValue);
}

template <typename T>
bool ZGFloatingPointGreaterThanLinear(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T newCompareValue = *(static_cast<T *>(searchData->_multiplicativeConstant)) * *compareValue + *(static_cast<T *>(searchData->_additiveConstant));
	return ZGFloatingPointGreaterThan(searchData, variableValue, &newCompareValue);
}

template <typename T>
bool ZGFloatingPointSwappedGreaterThanLinear(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	return ZGFloatingPointGreaterThan(searchData, &swappedVariableValue, &swappedCompareValue);
}

template <typename T>
bool ZGFloatingPointLesserThanLinear(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T newCompareValue = *(static_cast<T *>(searchData->_multiplicativeConstant)) * *compareValue + *(static_cast<T *>(searchData->_additiveConstant));
	return ZGFloatingPointLesserThan(searchData, variableValue, &newCompareValue);
}

template <typename T>
bool ZGFloatingPointSwappedLesserThanLinear(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	return ZGFloatingPointLesserThanLinear(searchData, &swappedVariableValue, &swappedCompareValue);
}

#define ZGHandleType(functionType, type, dataType, processTask, searchData, delegate) \
	case dataType: \
		retValue = ZGSearchWithFunction(functionType, processTask, static_cast<type *>(searchData.searchValue), searchData, delegate); \
	break

#define ZGHandleFloatingPointCase(theCase, function) \
switch (theCase) {\
	ZGHandleType(function, float, ZGFloat, processTask, searchData, delegate);\
	ZGHandleType(function, double, ZGDouble, processTask, searchData, delegate);\
	case ZGInt8:\
	case ZGInt16:\
	case ZGInt32:\
	case ZGInt64:\
	case ZGString8:\
	case ZGString16:\
	case ZGByteArray:\
	case ZGScript:\
	case ZGPointer:\
	break;\
}

ZGSearchResults *ZGSearchForFloatingPoints(ZGMemoryMap processTask, ZGSearchData *searchData, id <ZGSearchProgressDelegate> delegate, ZGVariableType dataType, ZGFunctionType functionType)
{
	id retValue = nil;
	
	switch (functionType)
	{
		case ZGEquals:
			if (searchData.bytesSwapped)
			{
				ZGHandleFloatingPointCase(dataType, ZGFloatingPointSwappedEquals);
			}
			else
			{
				ZGHandleFloatingPointCase(dataType, ZGFloatingPointEquals);
			}
			break;
		case ZGEqualsStored:
			if (searchData.bytesSwapped)
			{
				ZGHandleFloatingPointCase(dataType, ZGFloatingPointSwappedEqualsStored);
			}
			else
			{
				ZGHandleFloatingPointCase(dataType, ZGFloatingPointEquals);
			}
			break;
		case ZGNotEquals:
			if (searchData.bytesSwapped)
			{
				ZGHandleFloatingPointCase(dataType, ZGFloatingPointSwappedNotEquals);
			}
			else
			{
				ZGHandleFloatingPointCase(dataType, ZGFloatingPointNotEquals);
			}
			break;
		case ZGNotEqualsStored:
			if (searchData.bytesSwapped)
			{
				ZGHandleFloatingPointCase(dataType, ZGFloatingPointSwappedNotEqualsStored);
			}
			else
			{
				ZGHandleFloatingPointCase(dataType, ZGFloatingPointNotEquals);
			}
			break;
		case ZGGreaterThan:
			if (searchData.bytesSwapped)
			{
				ZGHandleFloatingPointCase(dataType, ZGFloatingPointSwappedGreaterThan);
			}
			else
			{
				ZGHandleFloatingPointCase(dataType, ZGFloatingPointGreaterThan);
			}
			break;
		case ZGGreaterThanStored:
			if (searchData.bytesSwapped)
			{
				ZGHandleFloatingPointCase(dataType, ZGFloatingPointSwappedGreaterThanStored);
			}
			else
			{
				ZGHandleFloatingPointCase(dataType, ZGFloatingPointGreaterThan);
			}
			break;
		case ZGLessThan:
			if (searchData.bytesSwapped)
			{
				ZGHandleFloatingPointCase(dataType, ZGFloatingPointSwappedLesserThan);
			}
			else
			{
				ZGHandleFloatingPointCase(dataType, ZGFloatingPointLesserThan);
			}
			break;
		case ZGLessThanStored:
			if (searchData.bytesSwapped)
			{
				ZGHandleFloatingPointCase(dataType, ZGFloatingPointSwappedLesserThanStored);
			}
			else
			{
				ZGHandleFloatingPointCase(dataType, ZGFloatingPointLesserThan);
			}
			break;
		case ZGEqualsStoredLinear:
			if (searchData.bytesSwapped)
			{
				ZGHandleFloatingPointCase(dataType, ZGFloatingPointSwappedEqualsLinear);
			}
			else
			{
				ZGHandleFloatingPointCase(dataType, ZGFloatingPointEqualsLinear);
			}
			break;
		case ZGNotEqualsStoredLinear:
			if (searchData.bytesSwapped)
			{
				ZGHandleFloatingPointCase(dataType, ZGFloatingPointSwappedNotEqualsLinear);
			}
			else
			{
				ZGHandleFloatingPointCase(dataType, ZGFloatingPointNotEqualsLinear);
			}
			break;
		case ZGGreaterThanStoredLinear:
			if (searchData.bytesSwapped)
			{
				ZGHandleFloatingPointCase(dataType, ZGFloatingPointSwappedGreaterThanLinear);
			}
			else
			{
				ZGHandleFloatingPointCase(dataType, ZGFloatingPointGreaterThanLinear);
			}
			break;
		case ZGLessThanStoredLinear:
			if (searchData.bytesSwapped)
			{
				ZGHandleFloatingPointCase(dataType, ZGFloatingPointSwappedLesserThanLinear);
			}
			else
			{
				ZGHandleFloatingPointCase(dataType, ZGFloatingPointLesserThanLinear);
			}
			break;
	}
	
	return retValue;
}

#pragma mark Strings

template <typename T>
bool ZGString8CaseInsensitiveEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return strncasecmp(variableValue, compareValue, searchData->_dataSize) == 0;
}

template <typename T>
bool ZGString16FastSwappedEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T * __unused compareValue)
{
	return ZGByteArrayEquals(searchData, variableValue, static_cast<T *>(searchData->_swappedValue));
}

template <typename T>
bool ZGString16CaseInsensitiveEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	Boolean isEqual = false;
	UCCompareText(searchData->_collator, variableValue, (static_cast<size_t>(searchData->_dataSize)) / sizeof(T), compareValue, (static_cast<size_t>(searchData->_dataSize)) / sizeof(T), static_cast<Boolean *>(&isEqual), NULL);
	return isEqual;
}

template <typename T>
bool ZGString16SwappedCaseInsensitiveEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	for (uint32_t index = 0; index < searchData->_dataSize / sizeof(T); index++)
	{
		variableValue[index] = ZGSwapBytes(variableValue[index]);
	}
	
	bool retValue = ZGString16CaseInsensitiveEquals(searchData, variableValue, compareValue);
	
	for (uint32_t index = 0; index < searchData->_dataSize / sizeof(T); index++)
	{
		variableValue[index] = ZGSwapBytes(variableValue[index]);
	}
	
	return retValue;
}

template <typename T>
bool ZGString8CaseInsensitiveNotEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return !ZGString8CaseInsensitiveEquals(searchData, variableValue, compareValue);
}

template <typename T>
bool ZGString16FastSwappedNotEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return !ZGString16FastSwappedEquals(searchData, static_cast<void *>(variableValue), static_cast<void *>(compareValue));
}

template <typename T>
bool ZGString16CaseInsensitiveNotEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return !ZGString16CaseInsensitiveEquals(searchData, variableValue, compareValue);
}

template <typename T>
bool ZGString16SwappedCaseInsensitiveNotEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return ZGString16CaseInsensitiveNotEquals(searchData, variableValue, compareValue);
}

template <typename T>
bool ZGString16FastSwappedCaseSensitiveNotEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T * __unused compareValue)
{
	return ZGByteArrayNotEquals(searchData, variableValue, static_cast<T *>(searchData->_swappedValue));
}

#define ZGHandleStringCase(theCase, function1, function2) \
	switch (theCase) {\
		ZGHandleType(function1, char, ZGString8, processTask, searchData, delegate);\
		ZGHandleType(function2, unichar, ZGString16, processTask, searchData, delegate);\
		case ZGInt8:\
		case ZGInt16:\
		case ZGInt32:\
		case ZGInt64:\
		case ZGFloat:\
		case ZGDouble:\
		case ZGScript:\
		case ZGPointer:\
		case ZGByteArray:\
		break;\
	}\

ZGSearchResults *ZGSearchForCaseInsensitiveStrings(ZGMemoryMap processTask, ZGSearchData *searchData, id <ZGSearchProgressDelegate> delegate, ZGVariableType dataType, ZGFunctionType functionType)
{
	id retValue = nil;
	
	switch (functionType)
	{
		case ZGEquals:
			if (searchData.bytesSwapped)
			{
				ZGHandleStringCase(dataType, ZGString8CaseInsensitiveEquals, ZGString16SwappedCaseInsensitiveEquals);
			}
			else
			{
				ZGHandleStringCase(dataType, ZGString8CaseInsensitiveEquals, ZGString16CaseInsensitiveEquals);
			}
			break;
		case ZGNotEquals:
			if (searchData.bytesSwapped)
			{
				ZGHandleStringCase(dataType, ZGString8CaseInsensitiveNotEquals, ZGString16SwappedCaseInsensitiveNotEquals);
			}
			else
			{
				ZGHandleStringCase(dataType, ZGString8CaseInsensitiveNotEquals, ZGString16CaseInsensitiveNotEquals);
			}
			break;
		case ZGEqualsStored:
		case ZGEqualsStoredLinear:
		case ZGNotEqualsStored:
		case ZGNotEqualsStoredLinear:
		case ZGGreaterThan:
		case ZGGreaterThanStored:
		case ZGGreaterThanStoredLinear:
		case ZGLessThan:
		case ZGLessThanStored:
		case ZGLessThanStoredLinear:
			break;
	}
	
	return retValue;
}

ZGSearchResults *ZGSearchForCaseSensitiveStrings(ZGMemoryMap processTask, ZGSearchData *searchData, id <ZGSearchProgressDelegate> delegate, ZGVariableType dataType, ZGFunctionType functionType)
{
	id retValue = nil;
	
	switch (functionType)
	{
		case ZGNotEquals:
			if (searchData.bytesSwapped)
			{
				ZGHandleStringCase(dataType, ZGByteArrayNotEquals, ZGString16FastSwappedCaseSensitiveNotEquals);
			}
			else
			{
				ZGHandleStringCase(dataType, ZGByteArrayNotEquals, ZGByteArrayNotEquals);
			}
			break;
		case ZGEquals:
		case ZGEqualsStored:
		case ZGEqualsStoredLinear:
		case ZGNotEqualsStored:
		case ZGNotEqualsStoredLinear:
		case ZGGreaterThan:
		case ZGGreaterThanStored:
		case ZGGreaterThanStoredLinear:
		case ZGLessThan:
		case ZGLessThanStored:
		case ZGLessThanStoredLinear:
			break;
	}
	
	return retValue;
}


#pragma mark Byte Arrays

template <typename T>
bool ZGByteArrayWithWildcardsEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	const unsigned char *variableValueArray = static_cast<const unsigned char *>(variableValue);
	const unsigned char *compareValueArray = static_cast<const unsigned char *>(compareValue);
	
	bool isEqual = true;
	
	for (unsigned int byteIndex = 0; byteIndex < searchData->_dataSize; byteIndex++)
	{
		if (!(searchData->_byteArrayFlags[byteIndex] & 0xF0) && ((variableValueArray[byteIndex] & 0xF0) != (compareValueArray[byteIndex] & 0xF0)))
		{
			isEqual = false;
			break;
		}
		
		if (!(searchData->_byteArrayFlags[byteIndex] & 0x0F) && ((variableValueArray[byteIndex] & 0x0F) != (compareValueArray[byteIndex] & 0x0F)))
		{
			isEqual = false;
			break;
		}
	}
	
	return isEqual;
}

template <typename T>
bool ZGByteArrayWithWildcardsNotEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return !ZGByteArrayWithWildcardsEquals(searchData, static_cast<void *>(variableValue), static_cast<void *>(compareValue));
}

ZGSearchResults *ZGSearchForByteArraysWithWildcards(ZGMemoryMap processTask, ZGSearchData *searchData, id <ZGSearchProgressDelegate> delegate, ZGFunctionType functionType)
{
	id retValue = nil;
	
	switch (functionType)
	{
		case ZGEquals:
			retValue = ZGSearchWithFunction(ZGByteArrayWithWildcardsEquals, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, delegate);
			break;
		case ZGNotEquals:
			retValue = ZGSearchWithFunction(ZGByteArrayWithWildcardsNotEquals, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, delegate);
			break;
		case ZGEqualsStored:
		case ZGEqualsStoredLinear:
		case ZGNotEqualsStored:
		case ZGNotEqualsStoredLinear:
		case ZGGreaterThan:
		case ZGGreaterThanStored:
		case ZGGreaterThanStoredLinear:
		case ZGLessThan:
		case ZGLessThanStored:
		case ZGLessThanStoredLinear:
			break;
	}
	
	return retValue;
}

ZGSearchResults *ZGSearchForByteArrays(ZGMemoryMap processTask, ZGSearchData *searchData, id <ZGSearchProgressDelegate> delegate, ZGFunctionType functionType)
{
	id retValue = nil;
	
	switch (functionType)
	{
		case ZGNotEquals:
			retValue = ZGSearchWithFunction(ZGByteArrayNotEquals, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, delegate);
			break;
		case ZGEquals:
		case ZGEqualsStored:
		case ZGEqualsStoredLinear:
		case ZGNotEqualsStored:
		case ZGNotEqualsStoredLinear:
		case ZGGreaterThan:
		case ZGGreaterThanStored:
		case ZGGreaterThanStoredLinear:
		case ZGLessThan:
		case ZGLessThanStored:
		case ZGLessThanStoredLinear:
			break;
	}
	
	return retValue;
}

#pragma mark Searching for Data

ZGSearchResults *ZGSearchForData(ZGMemoryMap processTask, ZGSearchData *searchData, id <ZGSearchProgressDelegate> delegate, ZGVariableType dataType, ZGVariableQualifier integerQualifier, ZGFunctionType functionType)
{
	id retValue = nil;
	if (((dataType == ZGByteArray && searchData.byteArrayFlags == NULL) || ((dataType == ZGString8 || dataType == ZGString16) && !searchData.shouldIgnoreStringCase)) && !searchData.shouldCompareStoredValues && functionType == ZGEquals)
	{
		// use fast boyer moore
		retValue = ZGSearchForBytes(processTask, searchData, delegate);
	}
	else
	{
		switch (dataType)
		{
			case ZGInt8:
			case ZGInt16:
			case ZGInt32:
			case ZGInt64:
				retValue = ZGSearchForIntegers(processTask, searchData, delegate, dataType, integerQualifier, functionType);
				break;
			case ZGPointer:
				retValue = ZGSearchForPointer(processTask, searchData, delegate);
				break;
			case ZGFloat:
			case ZGDouble:
				retValue = ZGSearchForFloatingPoints(processTask, searchData, delegate, dataType, functionType);
				break;
			case ZGString8:
			case ZGString16:
				if (searchData.shouldIgnoreStringCase)
				{
					retValue = ZGSearchForCaseInsensitiveStrings(processTask, searchData, delegate, dataType, functionType);
				}
				else
				{
					retValue = ZGSearchForCaseSensitiveStrings(processTask, searchData, delegate, dataType, functionType);
				}
				break;
			case ZGByteArray:
				if (searchData.byteArrayFlags == NULL)
				{
					retValue = ZGSearchForByteArrays(processTask, searchData, delegate, functionType);
				}
				else
				{
					retValue = ZGSearchForByteArraysWithWildcards(processTask, searchData, delegate, functionType);
				}
				break;
			case ZGScript:
				break;
		}
	}
	
	return retValue;
}

#pragma mark Generic Narrowing Searching

typedef void (^zg_narrow_search_for_data_helper_t)(size_t resultSetIndex, NSUInteger oldResultSetStartIndex, NSData * __unsafe_unretained oldResultSet, NSMutableData * __unsafe_unretained newResultSet);

ZGSearchResults *ZGNarrowSearchForDataHelper(ZGSearchData *searchData, id <ZGSearchProgressDelegate> delegate, ZGSearchResults *firstSearchResults, ZGSearchResults *laterSearchResults, zg_narrow_search_for_data_helper_t helper)
{
	ZGMemorySize dataSize = searchData.dataSize;
	
	ZGMemorySize pointerSize = searchData.pointerSize;
	
	ZGMemorySize newResultSetCount = firstSearchResults.resultSets.count + laterSearchResults.resultSets.count;
	
	ZGSearchProgress *searchProgress = [[ZGSearchProgress alloc] initWithProgressType:ZGSearchProgressMemoryScanning maxProgress:newResultSetCount];
	
	if (delegate != nil)
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			[delegate progressWillBegin:searchProgress];
		});
	}
	
	ZGMemorySize *laterResultSetsAbsoluteIndexes = static_cast<ZGMemorySize *>(malloc(sizeof(*laterResultSetsAbsoluteIndexes) * laterSearchResults.resultSets.count));
	ZGMemorySize laterResultSetsAbsoluteIndexAccumulator = 0;
	
	NSMutableArray *newResultSets = [[NSMutableArray alloc] init];
	for (NSUInteger regionIndex = 0; regionIndex < newResultSetCount; regionIndex++)
	{
		[newResultSets addObject:[[NSMutableData alloc] init]];
		if (regionIndex >= firstSearchResults.resultSets.count)
		{
			laterResultSetsAbsoluteIndexes[regionIndex - firstSearchResults.resultSets.count] = laterResultSetsAbsoluteIndexAccumulator;
			
			NSData *data = [laterSearchResults.resultSets objectAtIndex:regionIndex - firstSearchResults.resultSets.count];
			laterResultSetsAbsoluteIndexAccumulator += data.length;
		}
	}
	
	dispatch_apply(newResultSetCount, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t resultSetIndex) {
		@autoreleasepool
		{
			if (!searchProgress.shouldCancelSearch)
			{
				NSMutableData *newResultSet = [newResultSets objectAtIndex:resultSetIndex];
				NSData *oldResultSet = resultSetIndex < firstSearchResults.resultSets.count ? [firstSearchResults.resultSets objectAtIndex:resultSetIndex] : [laterSearchResults.resultSets objectAtIndex:resultSetIndex - firstSearchResults.resultSets.count];
				
				// Don't scan addresses that have been popped out from laterSearchResults
				NSUInteger startIndex = 0;
				if (resultSetIndex >= firstSearchResults.resultSets.count)
				{
					ZGMemorySize absoluteIndex = laterResultSetsAbsoluteIndexes[resultSetIndex - firstSearchResults.resultSets.count];
					if (absoluteIndex < laterSearchResults.addressIndex * pointerSize)
					{
						startIndex = (laterSearchResults.addressIndex * pointerSize - absoluteIndex);
					}
				}
				
				helper(resultSetIndex, startIndex, oldResultSet, newResultSet);
				
				if (delegate != nil)
				{
					dispatch_async(dispatch_get_main_queue(), ^{
						searchProgress.numberOfVariablesFound += newResultSet.length / pointerSize;
						searchProgress.progress++;
						[delegate progress:searchProgress advancedWithResultSet:newResultSet];
					});
				}
			}
		}
	});
	
	free(laterResultSetsAbsoluteIndexes);
	
	NSArray *resultSets;
	
	if (searchProgress.shouldCancelSearch)
	{
		resultSets = [NSArray array];
		
		// Deallocate results into separate queue since this could take some time
		__block id oldResultSets = newResultSets;
		newResultSets = nil;
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			oldResultSets = nil;
		});
	}
	else
	{
		resultSets = [newResultSets zgFilterUsingBlock:^(NSMutableData *resultSet) {
			return static_cast<BOOL>(resultSet.length != 0);
		}];
	}
	
	return [[ZGSearchResults alloc] initWithResultSets:resultSets dataSize:dataSize pointerSize:pointerSize];
}

template <typename T, typename P>
void ZGNarrowSearchWithFunctionRegularCompare(ZGRegion * __unused *lastUsedSavedRegionReference, ZGRegion * __unsafe_unretained lastUsedRegion, P variableAddress, ZGMemorySize __unused dataSize, NSDictionary * __unused __unsafe_unretained savedPageToRegionTable, NSArray * __unused __unsafe_unretained savedRegions, ZGMemorySize __unused pageSize, bool (*comparisonFunction)(ZGSearchData *, T *, T *), P *memoryAddresses, ZGMemorySize &numberOfVariablesFound, ZGSearchData * __unsafe_unretained searchData, T *searchValue)
{
	T *currentValue = static_cast<T *>(static_cast<void *>(static_cast<uint8_t *>(lastUsedRegion->_bytes) + (variableAddress - lastUsedRegion->_address)));
	if (comparisonFunction(searchData, currentValue, searchValue))
	{
		memoryAddresses[numberOfVariablesFound] = variableAddress;
		numberOfVariablesFound++;
	}
}

template <typename T, typename P>
void ZGNarrowSearchWithFunctionStoredCompare(ZGRegion **lastUsedSavedRegionReference, ZGRegion * __unsafe_unretained lastUsedRegion, P variableAddress, ZGMemorySize dataSize, NSDictionary * __unsafe_unretained savedPageToRegionTable, NSArray * __unsafe_unretained savedRegions, ZGMemorySize pageSize, bool (*comparisonFunction)(ZGSearchData *, T *, T *), P *memoryAddresses, ZGMemorySize &numberOfVariablesFound, ZGSearchData * __unsafe_unretained searchData, T * __unused searchValue)
{
	if (*lastUsedSavedRegionReference == nil || (variableAddress < (*lastUsedSavedRegionReference)->_address || variableAddress + dataSize > (*lastUsedSavedRegionReference)->_address + (*lastUsedSavedRegionReference)->_size))
	{
		ZGRegion *newRegion = nil;
		if (savedPageToRegionTable != nil)
		{
			newRegion = [savedPageToRegionTable objectForKey:@(variableAddress - (variableAddress % pageSize))];
		}
		else
		{
			newRegion = [savedRegions zgBinarySearchUsingBlock:^NSComparisonResult(__unsafe_unretained ZGRegion *region) {
				if (variableAddress >= region.address + region.size)
				{
					return NSOrderedAscending;
				}
				else if (variableAddress < region.address)
				{
					return NSOrderedDescending;
				}
				else
				{
					return NSOrderedSame;
				}
			}];
		}
		
		if (newRegion != nil && variableAddress >= newRegion->_address && variableAddress + dataSize <= newRegion->_address + newRegion->_size)
		{
			*lastUsedSavedRegionReference = newRegion;
		}
		else
		{
			*lastUsedSavedRegionReference = nil;
		}
	}
	
	if (*lastUsedSavedRegionReference != nil)
	{
		T *currentValue = static_cast<T *>(static_cast<void *>(static_cast<uint8_t *>(lastUsedRegion->_bytes) + (variableAddress - lastUsedRegion->_address)));
		
		T *compareValue = static_cast<T *>(static_cast<void *>(static_cast<uint8_t *>((*lastUsedSavedRegionReference)->_bytes) + (variableAddress - (*lastUsedSavedRegionReference)->_address)));
		
		if (comparisonFunction(searchData, currentValue, compareValue))
		{
			memoryAddresses[numberOfVariablesFound] = variableAddress;
			numberOfVariablesFound++;
		}
	}
}

#define zg_define_compare_function(name) void (*name)(ZGRegion **, ZGRegion *, P, ZGMemorySize, NSDictionary *, NSArray *, ZGMemorySize, bool (*)(ZGSearchData *, T *, T *), P *, ZGMemorySize &, ZGSearchData *, T *)

template <typename T, typename P>
void ZGNarrowSearchWithFunctionType(bool (*comparisonFunction)(ZGSearchData *, T *, T *), ZGMemoryMap processTask, T *searchValue, ZGSearchData * __unsafe_unretained searchData, P __unused pointerSize, ZGMemorySize dataSize, NSUInteger oldResultSetStartIndex, NSData * __unsafe_unretained oldResultSet, NSMutableData * __unsafe_unretained newResultSet, NSDictionary * __unsafe_unretained pageToRegionTable, NSDictionary * __unsafe_unretained savedPageToRegionTable, NSArray * __unsafe_unretained savedRegions, ZGMemorySize pageSize, zg_define_compare_function(compareHelperFunction))
{
	ZGRegion *lastUsedRegion = nil;
	ZGRegion *lastUsedSavedRegion = nil;
	
	ZGMemorySize oldDataLength = oldResultSet.length;
	const void *oldResultSetBytes = oldResultSet.bytes;
	
	ZGProtectionMode protectionMode = searchData.protectionMode;
	bool regionMatchesProtection = true;

	ZGMemoryAddress beginAddress = searchData.beginAddress;
	ZGMemoryAddress endAddress = searchData.endAddress;

	ZGMemoryAddress dataIndex = oldResultSetStartIndex;
	while (dataIndex < oldDataLength)
	{
		P memoryAddresses[MAX_NUMBER_OF_LOCAL_BUFFER_ADDRESSES];
		ZGMemorySize numberOfVariablesFound = 0;
		ZGMemorySize numberOfStepsToTake = MIN(MAX_NUMBER_OF_LOCAL_BUFFER_ADDRESSES, (oldDataLength - dataIndex) / sizeof(P));
		for (ZGMemorySize stepIndex = 0; stepIndex < numberOfStepsToTake; stepIndex++)
		{
			P variableAddress = *(static_cast<P *>(const_cast<void *>(oldResultSetBytes)) + dataIndex / sizeof(P));
			
			if (lastUsedRegion == nil || (variableAddress < lastUsedRegion->_address || variableAddress + dataSize > lastUsedRegion->_address + lastUsedRegion->_size))
			{
				if (lastUsedRegion != nil)
				{
					ZGFreeBytes(lastUsedRegion->_bytes, lastUsedRegion->_size);
				}
				
				ZGRegion *newRegion = nil;

				if (pageToRegionTable == nil)
				{
					ZGMemoryAddress regionAddress = variableAddress;
					ZGMemorySize regionSize = dataSize;
					ZGMemoryBasicInfo basicInfo;
					if (ZGRegionInfo(processTask, &regionAddress, &regionSize, &basicInfo))
					{
						newRegion = [[ZGRegion alloc] initWithAddress:regionAddress size:regionSize protection:basicInfo.protection];
						regionMatchesProtection = ZGMemoryProtectionMatchesProtectionMode(basicInfo.protection, protectionMode);
					}
				}
				else
				{
					newRegion = [pageToRegionTable objectForKey:@(variableAddress - (variableAddress % pageSize))];
				}
				
				if (newRegion != nil && variableAddress >= newRegion->_address && variableAddress + dataSize <= newRegion->_address + newRegion->_size)
				{
					lastUsedRegion = [[ZGRegion alloc] initWithAddress:newRegion->_address size:newRegion->_size];
					
					void *bytes = NULL;
					if (ZGReadBytes(processTask, lastUsedRegion->_address, &bytes, &lastUsedRegion->_size))
					{
						lastUsedRegion->_bytes = bytes;
					}
					else
					{
						lastUsedRegion = nil;
					}
				}
				else
				{
					lastUsedRegion = nil;
				}
			}
			
			if (lastUsedRegion != nil && regionMatchesProtection && variableAddress >= beginAddress && variableAddress + dataSize <= endAddress)
			{
				compareHelperFunction(&lastUsedSavedRegion, lastUsedRegion, variableAddress, dataSize, savedPageToRegionTable, savedRegions, pageSize, comparisonFunction, memoryAddresses, numberOfVariablesFound, searchData, searchValue);
			}
			
			dataIndex += sizeof(P);
		}
		
		[newResultSet appendBytes:memoryAddresses length:sizeof(P) * numberOfVariablesFound];
	}
	
	if (lastUsedRegion != nil)
	{
		ZGFreeBytes(lastUsedRegion->_bytes, lastUsedRegion->_size);
	}
}

template <typename T>
ZGSearchResults *ZGNarrowSearchWithFunction(bool (*comparisonFunction)(ZGSearchData *, T *, T *), ZGMemoryMap processTask, T *searchValue, ZGSearchData * __unsafe_unretained searchData, id <ZGSearchProgressDelegate> delegate, ZGSearchResults * __unsafe_unretained firstSearchResults, ZGSearchResults * __unsafe_unretained laterSearchResults)
{
	ZGMemorySize pointerSize = searchData.pointerSize;
	ZGMemorySize dataSize = searchData.dataSize;
	BOOL shouldCompareStoredValues = searchData.shouldCompareStoredValues;
	
	ZGMemorySize pageSize = NSPageSize(); // sane default
	ZGPageSize(processTask, &pageSize);
	
	NSArray *allRegions = [ZGRegion regionsFromProcessTask:processTask];
	
	return ZGNarrowSearchForDataHelper(searchData, delegate, firstSearchResults, laterSearchResults, ^(size_t resultSetIndex, NSUInteger oldResultSetStartIndex, NSData * __unsafe_unretained oldResultSet, NSMutableData * __unsafe_unretained newResultSet) {
		NSMutableDictionary *pageToRegionTable = nil;
		
		ZGMemoryAddress firstAddress = 0;
		ZGMemoryAddress lastAddress = 0;
		
		if (resultSetIndex >= firstSearchResults.resultSets.count)
		{
			pageToRegionTable = [[NSMutableDictionary alloc] init];
			
			if (pointerSize == sizeof(ZGMemoryAddress))
			{
				firstAddress = *(static_cast<ZGMemoryAddress *>(const_cast<void *>(oldResultSet.bytes)) + oldResultSetStartIndex / sizeof(ZGMemoryAddress));
				lastAddress = *(static_cast<ZGMemoryAddress *>(const_cast<void *>(oldResultSet.bytes)) + oldResultSet.length / sizeof(ZGMemoryAddress) - 1) + dataSize;
			}
			else
			{
				firstAddress = *(static_cast<ZG32BitMemoryAddress *>(const_cast<void *>(oldResultSet.bytes)) + oldResultSetStartIndex / sizeof(ZG32BitMemoryAddress));
				lastAddress = *(static_cast<ZG32BitMemoryAddress *>(const_cast<void *>(oldResultSet.bytes)) + oldResultSet.length / sizeof(ZG32BitMemoryAddress) - 1) + dataSize;
			}

			if (firstAddress < searchData.beginAddress)
			{
				firstAddress = searchData.beginAddress;
			}

			if (lastAddress > searchData.endAddress)
			{
				lastAddress = searchData.endAddress;
			}

			NSArray *regions = ZGFilterRegions(allRegions, firstAddress, lastAddress, searchData.protectionMode);
			
			for (ZGRegion *region in regions)
			{
				ZGMemoryAddress regionAddress = region.address;
				ZGMemorySize regionSize = region.size;
				for (NSUInteger dataIndex = 0; dataIndex < regionSize; dataIndex += pageSize)
				{
					[pageToRegionTable setObject:region forKey:@(dataIndex + regionAddress)];
				}
			}
		}
		
		if (!shouldCompareStoredValues)
		{
			if (pointerSize == sizeof(ZGMemoryAddress))
			{
				ZGNarrowSearchWithFunctionType(comparisonFunction, processTask, searchValue, searchData, static_cast<ZGMemoryAddress>(pointerSize), dataSize, oldResultSetStartIndex, oldResultSet, newResultSet, pageToRegionTable, nil, nil, pageSize, ZGNarrowSearchWithFunctionRegularCompare);
			}
			else
			{
				ZGNarrowSearchWithFunctionType(comparisonFunction, processTask, searchValue, searchData, static_cast<ZG32BitMemoryAddress>(pointerSize), dataSize, oldResultSetStartIndex, oldResultSet, newResultSet, pageToRegionTable, nil, nil, pageSize, ZGNarrowSearchWithFunctionRegularCompare);
			}
		}
		else
		{
			NSArray *savedData = searchData.savedData.regions;
			
			NSMutableDictionary *pageToSavedRegionTable = nil;
			
			if (pageToRegionTable != nil)
			{
				pageToSavedRegionTable = [[NSMutableDictionary alloc] init];
				
				NSArray *regions = ZGFilterRegions(savedData, firstAddress, lastAddress, searchData.protectionMode);
				
				for (ZGRegion *region in regions)
				{
					ZGMemoryAddress regionAddress = region.address;
					ZGMemorySize regionSize = region.size;
					for (NSUInteger dataIndex = 0; dataIndex < regionSize; dataIndex += pageSize)
					{
						[pageToSavedRegionTable setObject:region forKey:@(dataIndex + regionAddress)];
					}
				}
			}
			
			if (pointerSize == sizeof(ZGMemoryAddress))
			{
				ZGNarrowSearchWithFunctionType(comparisonFunction, processTask, searchValue, searchData, static_cast<ZGMemoryAddress>(pointerSize), dataSize, oldResultSetStartIndex, oldResultSet, newResultSet, pageToRegionTable, pageToSavedRegionTable, savedData, pageSize, ZGNarrowSearchWithFunctionStoredCompare);
			}
			else
			{
				ZGNarrowSearchWithFunctionType(comparisonFunction, processTask, searchValue, searchData, static_cast<ZG32BitMemoryAddress>(pointerSize), dataSize, oldResultSetStartIndex, oldResultSet, newResultSet, pageToRegionTable, pageToSavedRegionTable, savedData, pageSize, ZGNarrowSearchWithFunctionStoredCompare);
			}
		}
	});
}

#pragma mark Narrowing Integers

#define ZGHandleNarrowIntegerType(functionType, type, integerQualifier, dataType, processTask, searchData, delegate, firstSearchResults, laterSearchResults) \
case dataType: \
if (integerQualifier == ZGSigned) \
	retValue = ZGNarrowSearchWithFunction(functionType, processTask, static_cast<type *>(searchData.searchValue), searchData, delegate, firstSearchResults, laterSearchResults); \
else \
	retValue = ZGNarrowSearchWithFunction(functionType, processTask, static_cast<u##type *>(searchData.searchValue), searchData, delegate, firstSearchResults, laterSearchResults); \
break

#define ZGHandleNarrowIntegerCase(dataType, function) \
if (dataType == ZGPointer) {\
	switch (searchData.dataSize) {\
		case sizeof(ZGMemoryAddress):\
			retValue = ZGNarrowSearchWithFunction(function, processTask, static_cast<uint64_t *>(searchData.searchValue), searchData, delegate, firstSearchResults, laterSearchResults);\
			break;\
		case sizeof(ZG32BitMemoryAddress):\
			retValue = ZGNarrowSearchWithFunction(function, processTask, static_cast<uint32_t *>(searchData.searchValue), searchData, delegate, firstSearchResults, laterSearchResults);\
			break;\
	}\
}\
else {\
	switch (dataType) {\
		ZGHandleNarrowIntegerType(function, int8_t, integerQualifier, ZGInt8, processTask, searchData, delegate, firstSearchResults, laterSearchResults);\
		ZGHandleNarrowIntegerType(function, int16_t, integerQualifier, ZGInt16, processTask, searchData, delegate, firstSearchResults, laterSearchResults);\
		ZGHandleNarrowIntegerType(function, int32_t, integerQualifier, ZGInt32, processTask, searchData, delegate, firstSearchResults, laterSearchResults);\
		ZGHandleNarrowIntegerType(function, int64_t, integerQualifier, ZGInt64, processTask, searchData, delegate, firstSearchResults, laterSearchResults);\
		case ZGFloat:\
		case ZGDouble:\
		case ZGPointer:\
		case ZGString8:\
		case ZGString16:\
		case ZGByteArray:\
		case ZGScript:\
			break;\
	}\
}\

ZGSearchResults *ZGNarrowSearchForIntegers(ZGMemoryMap processTask, ZGSearchData * __unsafe_unretained searchData, id <ZGSearchProgressDelegate> delegate, ZGVariableType dataType, ZGVariableQualifier integerQualifier, ZGFunctionType functionType, ZGSearchResults * __unsafe_unretained firstSearchResults, ZGSearchResults * __unsafe_unretained laterSearchResults)
{
	id retValue = nil;
	switch (functionType)
	{
		case ZGEquals:
			if (searchData.bytesSwapped)
			{
				ZGHandleNarrowIntegerCase(dataType, ZGIntegerFastSwappedEquals);
			}
			else
			{
				ZGHandleNarrowIntegerCase(dataType, ZGIntegerEquals);
			}
			break;
		case ZGEqualsStored:
			ZGHandleNarrowIntegerCase(dataType, ZGIntegerEquals);
			break;
		case ZGNotEquals:
			if (searchData.bytesSwapped)
			{
				ZGHandleNarrowIntegerCase(dataType, ZGIntegerFastSwappedNotEquals);
			}
			else
			{
				ZGHandleNarrowIntegerCase(dataType, ZGIntegerNotEquals);
			}
			break;
		case ZGNotEqualsStored:
			ZGHandleNarrowIntegerCase(dataType, ZGIntegerNotEquals);
			break;
		case ZGGreaterThan:
			if (searchData.bytesSwapped)
			{
				ZGHandleNarrowIntegerCase(dataType, ZGIntegerSwappedGreaterThan);
			}
			else
			{
				ZGHandleNarrowIntegerCase(dataType, ZGIntegerGreaterThan);
			}
			break;
		case ZGGreaterThanStored:
			if (searchData.bytesSwapped)
			{
				ZGHandleNarrowIntegerCase(dataType, ZGIntegerSwappedGreaterThanStored);
			}
			else
			{
				ZGHandleNarrowIntegerCase(dataType, ZGIntegerGreaterThan);
			}
			break;
		case ZGLessThan:
			if (searchData.bytesSwapped)
			{
				ZGHandleNarrowIntegerCase(dataType, ZGIntegerSwappedLesserThan);
			}
			else
			{
				ZGHandleNarrowIntegerCase(dataType, ZGIntegerLesserThan);
			}
			break;
		case ZGLessThanStored:
			if (searchData.bytesSwapped)
			{
				ZGHandleNarrowIntegerCase(dataType, ZGIntegerSwappedLesserThanStored);
			}
			else
			{
				ZGHandleNarrowIntegerCase(dataType, ZGIntegerLesserThan);
			}
			break;
		case ZGEqualsStoredLinear:
			if (searchData.bytesSwapped)
			{
				ZGHandleNarrowIntegerCase(dataType, ZGIntegerSwappedEqualsLinear);
			}
			else
			{
				ZGHandleNarrowIntegerCase(dataType, ZGIntegerEqualsLinear);
			}
			break;
		case ZGNotEqualsStoredLinear:
			if (searchData.bytesSwapped)
			{
				ZGHandleNarrowIntegerCase(dataType, ZGIntegerSwappedNotEqualsLinear);
			}
			else
			{
				ZGHandleNarrowIntegerCase(dataType, ZGIntegerNotEqualsLinear);
			}
			break;
		case ZGGreaterThanStoredLinear:
			if (searchData.bytesSwapped)
			{
				ZGHandleNarrowIntegerCase(dataType, ZGIntegerSwappedGreaterThanLinear);
			}
			else
			{
				ZGHandleNarrowIntegerCase(dataType, ZGIntegerGreaterThanLinear);
			}
			break;
		case ZGLessThanStoredLinear:
			if (searchData.bytesSwapped)
			{
				ZGHandleNarrowIntegerCase(dataType, ZGIntegerSwappedLesserThanLinear);
			}
			else
			{
				ZGHandleNarrowIntegerCase(dataType, ZGIntegerLesserThanLinear);
			}
			break;
	}
	return retValue;
}

#define ZGHandleNarrowType(functionType, type, dataType, processTask, searchData, delegate, firstSearchResults, laterSearchResults) \
	case dataType: \
		retValue = ZGNarrowSearchWithFunction(functionType, processTask, static_cast<type *>(searchData.searchValue), searchData, delegate, firstSearchResults, laterSearchResults);\
		break

#define ZGHandleNarrowFloatingPointCase(theCase, function) \
switch (theCase) {\
	ZGHandleNarrowType(function, float, ZGFloat, processTask, searchData, delegate, firstSearchResults, laterSearchResults);\
	ZGHandleNarrowType(function, double, ZGDouble, processTask, searchData, delegate, firstSearchResults, laterSearchResults);\
	case ZGInt8:\
	case ZGInt16:\
	case ZGInt32:\
	case ZGInt64:\
	case ZGByteArray:\
	case ZGPointer:\
	case ZGString8:\
	case ZGString16:\
	case ZGScript:\
	break;\
}

#pragma mark Narrowing Floating Points

ZGSearchResults *ZGNarrowSearchForFloatingPoints(ZGMemoryMap processTask, ZGSearchData * __unsafe_unretained searchData, id <ZGSearchProgressDelegate> delegate, ZGVariableType dataType, ZGFunctionType functionType, ZGSearchResults * __unsafe_unretained firstSearchResults, ZGSearchResults * __unsafe_unretained laterSearchResults)
{
	id retValue = nil;
	switch (functionType)
	{
		case ZGEquals:
			if (searchData.bytesSwapped)
			{
				ZGHandleNarrowFloatingPointCase(dataType, ZGFloatingPointSwappedEquals);
			}
			else
			{
				ZGHandleNarrowFloatingPointCase(dataType, ZGFloatingPointEquals);
			}
			break;
		case ZGEqualsStored:
			if (searchData.bytesSwapped)
			{
				ZGHandleNarrowFloatingPointCase(dataType, ZGFloatingPointSwappedEqualsStored);
			}
			else
			{
				ZGHandleNarrowFloatingPointCase(dataType, ZGFloatingPointEquals);
			}
			break;
		case ZGNotEquals:
			if (searchData.bytesSwapped)
			{
				ZGHandleNarrowFloatingPointCase(dataType, ZGFloatingPointSwappedNotEquals);
			}
			else
			{
				ZGHandleNarrowFloatingPointCase(dataType, ZGFloatingPointNotEquals);
			}
			break;
		case ZGNotEqualsStored:
			if (searchData.bytesSwapped)
			{
				ZGHandleNarrowFloatingPointCase(dataType, ZGFloatingPointSwappedNotEqualsStored);
			}
			else
			{
				ZGHandleNarrowFloatingPointCase(dataType, ZGFloatingPointNotEquals);
			}
			break;
		case ZGGreaterThan:
			if (searchData.bytesSwapped)
			{
				ZGHandleNarrowFloatingPointCase(dataType, ZGFloatingPointSwappedGreaterThan);
			}
			else
			{
				ZGHandleNarrowFloatingPointCase(dataType, ZGFloatingPointGreaterThan);
			}
			break;
		case ZGGreaterThanStored:
			if (searchData.bytesSwapped)
			{
				ZGHandleNarrowFloatingPointCase(dataType, ZGFloatingPointSwappedGreaterThanStored);
			}
			else
			{
				ZGHandleNarrowFloatingPointCase(dataType, ZGFloatingPointGreaterThan);
			}
			break;
		case ZGLessThan:
			if (searchData.bytesSwapped)
			{
				ZGHandleNarrowFloatingPointCase(dataType, ZGFloatingPointSwappedLesserThan);
			}
			else
			{
				ZGHandleNarrowFloatingPointCase(dataType, ZGFloatingPointLesserThan);
			}
			break;
		case ZGLessThanStored:
			if (searchData.bytesSwapped)
			{
				ZGHandleNarrowFloatingPointCase(dataType, ZGFloatingPointSwappedLesserThanStored);
			}
			else
			{
				ZGHandleNarrowFloatingPointCase(dataType, ZGFloatingPointLesserThan);
			}
			break;
		case ZGEqualsStoredLinear:
			if (searchData.bytesSwapped)
			{
				ZGHandleNarrowFloatingPointCase(dataType, ZGFloatingPointSwappedEqualsLinear);
			}
			else
			{
				ZGHandleNarrowFloatingPointCase(dataType, ZGFloatingPointEqualsLinear);
			}
			break;
		case ZGNotEqualsStoredLinear:
			if (searchData.bytesSwapped)
			{
				ZGHandleNarrowFloatingPointCase(dataType, ZGFloatingPointSwappedNotEqualsLinear);
			}
			else
			{
				ZGHandleNarrowFloatingPointCase(dataType, ZGFloatingPointNotEqualsLinear);
			}
			break;
		case ZGGreaterThanStoredLinear:
			if (searchData.bytesSwapped)
			{
				ZGHandleNarrowFloatingPointCase(dataType, ZGFloatingPointSwappedGreaterThanLinear);
			}
			else
			{
				ZGHandleNarrowFloatingPointCase(dataType, ZGFloatingPointGreaterThanLinear);
			}
			break;
		case ZGLessThanStoredLinear:
			if (searchData.bytesSwapped)
			{
				ZGHandleNarrowFloatingPointCase(dataType, ZGFloatingPointSwappedLesserThanLinear);
			}
			else
			{
				ZGHandleNarrowFloatingPointCase(dataType, ZGFloatingPointLesserThanLinear);
			}
			break;
	}
	return retValue;
}

#pragma mark Narrowing Byte Arrays

template <typename T>
bool ZGByteArrayEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return (memcmp(static_cast<void *>(variableValue), static_cast<void *>(compareValue), searchData->_dataSize) == 0);
}

template <typename T>
bool ZGByteArrayNotEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return !ZGByteArrayEquals(searchData, variableValue, compareValue);
}

ZGSearchResults *ZGNarrowSearchForByteArrays(ZGMemoryMap processTask, ZGSearchData *searchData, id <ZGSearchProgressDelegate> delegate, ZGFunctionType functionType, ZGSearchResults *firstSearchResults, ZGSearchResults *laterSearchResults)
{
	id retValue = nil;
	
	switch (functionType)
	{
		case ZGEquals:
			if (searchData.byteArrayFlags != NULL)
			{
				retValue = ZGNarrowSearchWithFunction(ZGByteArrayWithWildcardsEquals, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, delegate, firstSearchResults, laterSearchResults);
			}
			else
			{
				retValue = ZGNarrowSearchWithFunction(ZGByteArrayEquals, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, delegate, firstSearchResults, laterSearchResults);
			}
			break;
		case ZGNotEquals:
			if (searchData.byteArrayFlags != NULL)
			{
				retValue = ZGNarrowSearchWithFunction(ZGByteArrayWithWildcardsNotEquals, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, delegate, firstSearchResults, laterSearchResults);
			}
			else
			{
				retValue = ZGNarrowSearchWithFunction(ZGByteArrayNotEquals, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, delegate, firstSearchResults, laterSearchResults);
			}
			break;
		case ZGEqualsStored:
		case ZGEqualsStoredLinear:
		case ZGNotEqualsStored:
		case ZGNotEqualsStoredLinear:
		case ZGGreaterThan:
		case ZGGreaterThanStored:
		case ZGGreaterThanStoredLinear:
		case ZGLessThan:
		case ZGLessThanStored:
		case ZGLessThanStoredLinear:
			break;
	}
	
	return retValue;
}

#pragma mark Narrowing Strings

#define ZGHandleNarrowStringCase(theCase, function1, function2) \
switch (theCase) {\
	ZGHandleNarrowType(function1, char, ZGString8, processTask, searchData, delegate, firstSearchResults, laterSearchResults);\
	ZGHandleNarrowType(function2, unichar, ZGString16, processTask, searchData, delegate, firstSearchResults, laterSearchResults);\
	case ZGInt8:\
	case ZGInt16:\
	case ZGInt32:\
	case ZGInt64:\
	case ZGFloat:\
	case ZGDouble:\
	case ZGByteArray:\
	case ZGPointer:\
	case ZGScript:\
	break;\
}\

ZGSearchResults *ZGNarrowSearchForStrings(ZGMemoryMap processTask, ZGSearchData *searchData, id <ZGSearchProgressDelegate> delegate, ZGVariableType dataType, ZGFunctionType functionType, ZGSearchResults *firstSearchResults, ZGSearchResults *laterSearchResults)
{
	id retValue = nil;
	
	if (!searchData.shouldIgnoreStringCase)
	{
		switch (functionType)
		{
			case ZGEquals:
				if (dataType == ZGString16 && searchData.bytesSwapped)
				{
					retValue = ZGNarrowSearchWithFunction(ZGString16FastSwappedEquals, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, delegate, firstSearchResults, laterSearchResults);
				}
				else
				{
					retValue = ZGNarrowSearchWithFunction(ZGByteArrayEquals, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, delegate, firstSearchResults, laterSearchResults);
				}
				break;
			case ZGNotEquals:
				if (dataType == ZGString16 && searchData.bytesSwapped)
				{
					retValue = ZGNarrowSearchWithFunction(ZGString16FastSwappedNotEquals, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, delegate, firstSearchResults, laterSearchResults);
				}
				else
				{
					retValue = ZGNarrowSearchWithFunction(ZGByteArrayNotEquals, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, delegate, firstSearchResults, laterSearchResults);
				}
				break;
			case ZGEqualsStored:
			case ZGEqualsStoredLinear:
			case ZGNotEqualsStored:
			case ZGNotEqualsStoredLinear:
			case ZGGreaterThan:
			case ZGGreaterThanStored:
			case ZGGreaterThanStoredLinear:
			case ZGLessThan:
			case ZGLessThanStored:
			case ZGLessThanStoredLinear:
				break;
		}
	}
	else
	{
		switch (functionType)
		{
			case ZGEquals:
				if (searchData.bytesSwapped)
				{
					ZGHandleNarrowStringCase(dataType, ZGString8CaseInsensitiveEquals, ZGString16SwappedCaseInsensitiveEquals);
				}
				else
				{
					ZGHandleNarrowStringCase(dataType, ZGString8CaseInsensitiveEquals, ZGString16CaseInsensitiveEquals);
				}
				break;
			case ZGNotEquals:
				if (searchData.bytesSwapped)
				{
					ZGHandleNarrowStringCase(dataType, ZGString8CaseInsensitiveNotEquals, ZGString16SwappedCaseInsensitiveNotEquals);
				}
				else
				{
					ZGHandleNarrowStringCase(dataType, ZGString8CaseInsensitiveNotEquals, ZGString16CaseInsensitiveNotEquals);
				}
				break;
			case ZGEqualsStored:
			case ZGEqualsStoredLinear:
			case ZGNotEqualsStored:
			case ZGNotEqualsStoredLinear:
			case ZGGreaterThan:
			case ZGGreaterThanStored:
			case ZGGreaterThanStoredLinear:
			case ZGLessThan:
			case ZGLessThanStored:
			case ZGLessThanStoredLinear:
				break;
		}
	}
	
	return retValue;
}

#pragma mark Narrow Search for Data

ZGSearchResults *ZGNarrowSearchForData(ZGMemoryMap processTask, ZGSearchData *searchData, id <ZGSearchProgressDelegate> delegate, ZGVariableType dataType, ZGVariableQualifier integerQualifier, ZGFunctionType functionType, ZGSearchResults *firstSearchResults, ZGSearchResults *laterSearchResults)
{
	id retValue = nil;
	
	switch (dataType)
	{
		case ZGInt8:
		case ZGInt16:
		case ZGInt32:
		case ZGInt64:
		case ZGPointer:
			retValue = ZGNarrowSearchForIntegers(processTask, searchData, delegate, dataType, integerQualifier, functionType, firstSearchResults, laterSearchResults);
			break;
		case ZGFloat:
		case ZGDouble:
			retValue = ZGNarrowSearchForFloatingPoints(processTask, searchData, delegate, dataType, functionType, firstSearchResults, laterSearchResults);
			break;
		case ZGString8:
		case ZGString16:
			retValue = ZGNarrowSearchForStrings(processTask, searchData, delegate, dataType, functionType, firstSearchResults, laterSearchResults);
			break;
		case ZGByteArray:
			retValue = ZGNarrowSearchForByteArrays(processTask, searchData, delegate, functionType, firstSearchResults, laterSearchResults);
			break;
		case ZGScript:
			break;
	}
	
	return retValue;
}
