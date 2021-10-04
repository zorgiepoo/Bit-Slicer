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

#import "ZGSearchFunctions.h"
#import "ZGSearchData.h"
#import "ZGSearchProgress.h"
#import "ZGRegion.h"
#import "ZGVirtualMemory.h"
#import "NSArrayAdditions.h"
#import "ZGSearchResults.h"
#import "ZGStoredData.h"
#import "HFByteArray_FindReplace.h"
#import <stdint.h>

#define INITIAL_BUFFER_ADDRESSES_CAPACITY 4096U
#define REALLOCATION_GROWTH_RATE 1.5f

template <typename T>
bool ZGByteArrayNotEquals(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T *__restrict__ extraStorage);

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

#pragma mark Generic Searching

static bool ZGMemoryProtectionMatchesProtectionMode(ZGMemoryProtection memoryProtection, ZGProtectionMode protectionMode)
{
	return ((protectionMode == ZGProtectionAll && memoryProtection & VM_PROT_READ) || (protectionMode == ZGProtectionWrite && memoryProtection & VM_PROT_WRITE) || (protectionMode == ZGProtectionExecute && memoryProtection & VM_PROT_EXECUTE));
}

static NSArray<ZGRegion *> *ZGFilterRegions(NSArray<ZGRegion *> *regions, ZGMemoryAddress beginAddress, ZGMemoryAddress endAddress, ZGProtectionMode protectionMode, BOOL includeSharedMemory)
{
	return [regions zgFilterUsingBlock:^(ZGRegion *region) {
		// For shared memory / pmap, see https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/KernelProgramming/vm/vm.html
		return static_cast<BOOL>(region.address < endAddress && region.address + region.size > beginAddress && ZGMemoryProtectionMatchesProtectionMode(region.protection, protectionMode) && (includeSharedMemory || region.userTag != VM_MEMORY_SHARED_PMAP));
	}];
}

typedef NSData *(^zg_search_for_data_helper_t)(ZGMemorySize dataIndex, ZGMemoryAddress address, ZGMemorySize size, void *bytes, void *regionBytes, void *extraStorage);

ZGSearchResults *ZGSearchForDataHelper(ZGMemoryMap processTask, ZGSearchData *searchData, BOOL unalignedAccesses, BOOL usesExtraStorage, id <ZGSearchProgressDelegate> delegate,  zg_search_for_data_helper_t helper)
{
	ZGMemorySize dataAlignment = searchData.dataAlignment;
	ZGMemorySize dataSize = searchData.dataSize;
	ZGMemorySize pointerSize = searchData.pointerSize;
	
	BOOL shouldCompareStoredValues = searchData.shouldCompareStoredValues;
	
	ZGMemoryAddress dataBeginAddress = searchData.beginAddress;
	ZGMemoryAddress dataEndAddress = searchData.endAddress;
	
	NSArray<ZGRegion *> *regions;
	if (!shouldCompareStoredValues)
	{
		BOOL includeSharedMemory = searchData.includeSharedMemory;
		
		NSArray<ZGRegion *> *nonFilteredRegions = includeSharedMemory ? [ZGRegion submapRegionsFromProcessTask:processTask] :  [ZGRegion regionsFromProcessTask:processTask];
		
		regions = ZGFilterRegions(nonFilteredRegions, dataBeginAddress, dataEndAddress, searchData.protectionMode, includeSharedMemory);
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
	
	NSMutableArray<NSData *> *allResultSets = [[NSMutableArray alloc] init];
	for (NSUInteger regionIndex = 0; regionIndex < regions.count; regionIndex++)
	{
		[allResultSets addObject:[[NSData alloc] init]];
	}
	
	dispatch_apply(regions.count, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t regionIndex) {
		@autoreleasepool
		{
			ZGRegion *region = [regions objectAtIndex:regionIndex];
			ZGMemoryAddress address = region.address;
			ZGMemorySize size = region.size;
			void *regionBytes = region.bytes;
			
			ZGMemorySize dataIndex = 0;
			char *bytes = nullptr;
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
					void *extraStorage = usesExtraStorage ? calloc(1, dataSize) : nullptr;
					
					allResultSets[regionIndex] = helper(dataIndex, address, size, bytes, regionBytes, extraStorage);
					
					free(extraStorage);
					ZGFreeBytes(bytes, size);
				}
			}
			
			if (delegate != nil)
			{
				dispatch_async(dispatch_get_main_queue(), ^{
					searchProgress.numberOfVariablesFound += allResultSets[regionIndex].length / pointerSize;
					searchProgress.progress++;
					[delegate progress:searchProgress advancedWithResultSet:allResultSets[regionIndex]];
				});
			}
		}
	});
	
	NSArray<NSData *> *resultSets;
	
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
		resultSets = [allResultSets zgFilterUsingBlock:^(NSData *resultSet) {
			return static_cast<BOOL>(resultSet.length != 0);
		}];
	}
	
	return [[ZGSearchResults alloc] initWithResultSets:resultSets dataSize:dataSize pointerSize:pointerSize unalignedAccess:unalignedAccesses];
}

#define MOVE_VALUE_FUNC [](void * __restrict__ __bytes, void *__unused __restrict__ __extraStorage, ZGMemorySize __unused __dataSize) -> void* { return __bytes; }

#define COPY_VALUE_FUNC [](void * __restrict__ __bytes, void * __restrict__ __extraStorage, ZGMemorySize __dataSize) -> void* { \
	memcpy(__extraStorage, __bytes, __dataSize);\
	return __extraStorage; \
}

template <typename T, typename P, typename F, typename C>
NSData *ZGSearchWithFunctionHelperRegular(T *searchValue, F comparisonFunction, C transferBytes, ZGSearchData * __unsafe_unretained searchData, ZGMemorySize dataIndex, ZGMemorySize dataAlignment, ZGMemorySize dataSize, ZGMemorySize endLimit, ZGMemoryAddress address, void *bytes, void *extraStorage)
{
	size_t addressCapacity = INITIAL_BUFFER_ADDRESSES_CAPACITY;
	P *memoryAddresses = static_cast<P *>(malloc(addressCapacity * sizeof(*memoryAddresses)));
	ZGMemorySize numberOfVariablesFound = 0;
	
	while (dataIndex <= endLimit)
	{
		if (numberOfVariablesFound == addressCapacity)
		{
			addressCapacity = static_cast<size_t>(addressCapacity * REALLOCATION_GROWTH_RATE);
			memoryAddresses = static_cast<P *>(realloc(memoryAddresses, addressCapacity * sizeof(*memoryAddresses)));
		}
		
		ZGMemorySize numberOfStepsToTake = MIN(addressCapacity - numberOfVariablesFound, (endLimit + dataAlignment - dataIndex) / dataAlignment);
		for (ZGMemorySize stepIndex = 0; stepIndex < numberOfStepsToTake; stepIndex++)
		{
			T *variableValue = static_cast<T *>(transferBytes(static_cast<uint8_t *>(bytes) + dataIndex, extraStorage, dataSize));
			
			if (comparisonFunction(searchData, variableValue, searchValue, static_cast<T *>(extraStorage)))
			{
				memoryAddresses[numberOfVariablesFound] = static_cast<P>(address + dataIndex);
				numberOfVariablesFound++;
			}
			
			dataIndex += dataAlignment;
		}
	}
	
	return [NSData dataWithBytesNoCopy:memoryAddresses length:numberOfVariablesFound * sizeof(*memoryAddresses) freeWhenDone:YES];
}

// like ZGSearchWithFunctionHelperRegular above except against stored values
template <typename T, typename P, typename F, typename C>
NSData *ZGSearchWithFunctionHelperStored(void *regionBytes, F comparisonFunction, C transferBytes, ZGSearchData * __unsafe_unretained searchData, ZGMemorySize dataIndex, ZGMemorySize dataAlignment, ZGMemorySize dataSize, ZGMemorySize endLimit, ZGMemoryAddress address, void *bytes, void *extraStorage)
{
	size_t addressCapacity = INITIAL_BUFFER_ADDRESSES_CAPACITY;
	P *memoryAddresses = static_cast<P *>(malloc(addressCapacity * sizeof(*memoryAddresses)));
	ZGMemorySize numberOfVariablesFound = 0;
	
	while (dataIndex <= endLimit)
	{
		if (numberOfVariablesFound == addressCapacity)
		{
			addressCapacity = static_cast<size_t>(addressCapacity * REALLOCATION_GROWTH_RATE);
			memoryAddresses = static_cast<P *>(realloc(memoryAddresses, addressCapacity * sizeof(*memoryAddresses)));
		}
		
		ZGMemorySize numberOfStepsToTake = MIN(addressCapacity - numberOfVariablesFound, (endLimit + dataAlignment - dataIndex) / dataAlignment);
		for (ZGMemorySize stepIndex = 0; stepIndex < numberOfStepsToTake; stepIndex++)
		{
			T *variableValue = static_cast<T *>(transferBytes(static_cast<uint8_t *>(bytes) + dataIndex, extraStorage, dataSize));
			
			T *compareValue = static_cast<T *>(transferBytes(static_cast<uint8_t *>(regionBytes) + dataIndex, extraStorage, dataSize));
			
			if (comparisonFunction(searchData, variableValue, compareValue, static_cast<T *>(extraStorage)))
			{
				memoryAddresses[numberOfVariablesFound] = static_cast<P>(address + dataIndex);
				numberOfVariablesFound++;
			}
			
			dataIndex += dataAlignment;
		}
	}
	
	return [NSData dataWithBytesNoCopy:memoryAddresses length:numberOfVariablesFound * sizeof(*memoryAddresses) freeWhenDone:YES];
}

static BOOL searchResultsHaveUnalignedAccess(ZGSearchData *searchData, ZGVariableType dataType)
{
	ZGMemorySize dataAlignment = searchData.dataAlignment;
	ZGMemorySize dataSize = searchData.dataSize;
	
	switch (dataType)
	{
		case ZGInt8:
		case ZGString8:
		case ZGByteArray:
			return NO;
		case ZGInt16:
		case ZGInt32:
		case ZGInt64:
		case ZGFloat:
		case ZGDouble:
			return (dataAlignment % dataSize != 0);
		case ZGString16:
			// When we search for 16-bit strings where we don't ignore case,
			// we do a byte-array search optimization, which returns unaligned results
			// We may want to change this in the future..
			return !searchData.shouldIgnoreStringCase || (dataAlignment % sizeof(uint16_t) != 0);
		// Invalid inputs
		case ZGScript:
		case ZGPointer:
			return NO;
	}
}

static BOOL searchUsesExtraStorage(ZGSearchData *searchData, ZGVariableType dataType, BOOL resultsUnaligned, BOOL *requiresCopy)
{
	switch (dataType)
	{
		case ZGInt8:
		case ZGString8:
		case ZGByteArray:
		case ZGInt16:
		case ZGInt32:
		case ZGInt64:
		case ZGFloat:
		case ZGDouble:
			if (requiresCopy != nullptr)
			{
				*requiresCopy = resultsUnaligned;
			}
			return resultsUnaligned;
		case ZGString16: {
			// Byte array search optimization don't need extra storage
			if (!searchData.shouldIgnoreStringCase)
			{
				if (requiresCopy != nullptr)
				{
					*requiresCopy = NO;
				}
				
				return NO;
			}
			
			// Unalignment will require extra storage
			if (resultsUnaligned)
			{
				if (requiresCopy != nullptr)
				{
					*requiresCopy = YES;
				}
				
				return YES;
			}
			
			// Swapping bytes + insensitive compare will require temporary storage only for optimization sake
			if (requiresCopy != nullptr)
			{
				*requiresCopy = NO;
			}
			return searchData.bytesSwapped && searchData.shouldIgnoreStringCase;;
		}
		// Invalid inputs
		case ZGScript:
		case ZGPointer:
			if (requiresCopy != nullptr)
			{
				*requiresCopy = NO;
			}
			return NO;
	}
}

template <typename T, typename F>
ZGSearchResults *ZGSearchWithFunction(F comparisonFunction, ZGMemoryMap processTask, T *searchValue, ZGSearchData * __unsafe_unretained searchData, ZGVariableType dataType, id <ZGSearchProgressDelegate> delegate)
{
	ZGMemorySize dataAlignment = searchData.dataAlignment;
	ZGMemorySize pointerSize = searchData.pointerSize;
	ZGMemorySize dataSize = searchData.dataSize;
	BOOL shouldCompareStoredValues = searchData.shouldCompareStoredValues;
	BOOL unalignedAccesses = searchResultsHaveUnalignedAccess(searchData, dataType);
	BOOL requiresExtraCopy = NO;
	BOOL usesExtraStorage = searchUsesExtraStorage(searchData, dataType, unalignedAccesses, &requiresExtraCopy);
	
	return ZGSearchForDataHelper(processTask, searchData, unalignedAccesses, usesExtraStorage, delegate, ^NSData *(ZGMemorySize dataIndex, ZGMemoryAddress address, ZGMemorySize size, void *bytes, void *regionBytes, void *extraStorage) {
		ZGMemorySize endLimit = size - dataSize;
		
		NSData *resultSet;
		
		if (!shouldCompareStoredValues)
		{
			if (pointerSize == sizeof(ZGMemoryAddress))
			{
				if (!requiresExtraCopy)
				{
					resultSet = ZGSearchWithFunctionHelperRegular<T, ZGMemoryAddress>(searchValue, comparisonFunction, MOVE_VALUE_FUNC, searchData, dataIndex, dataAlignment, dataSize, endLimit, address, bytes, extraStorage);
				}
				else
				{
					resultSet = ZGSearchWithFunctionHelperRegular<T, ZGMemoryAddress>(searchValue, comparisonFunction, COPY_VALUE_FUNC, searchData, dataIndex, dataAlignment, dataSize, endLimit, address, bytes, extraStorage);
				}
			}
			else
			{
				if (!requiresExtraCopy)
				{
					resultSet = ZGSearchWithFunctionHelperRegular<T, ZG32BitMemoryAddress>(searchValue, comparisonFunction, MOVE_VALUE_FUNC, searchData, dataIndex, dataAlignment, dataSize, endLimit, address, bytes, extraStorage);
				}
				else
				{
					resultSet = ZGSearchWithFunctionHelperRegular<T, ZG32BitMemoryAddress>(searchValue, comparisonFunction, COPY_VALUE_FUNC, searchData, dataIndex, dataAlignment, dataSize, endLimit, address, bytes, extraStorage);
				}
			}
		}
		else
		{
			if (pointerSize == sizeof(ZGMemoryAddress))
			{
				if (!requiresExtraCopy)
				{
					resultSet = ZGSearchWithFunctionHelperStored<T, ZGMemoryAddress>(regionBytes, comparisonFunction, MOVE_VALUE_FUNC, searchData, dataIndex, dataAlignment, dataSize, endLimit, address, bytes, extraStorage);
				}
				else
				{
					resultSet = ZGSearchWithFunctionHelperStored<T, ZGMemoryAddress>(regionBytes, comparisonFunction, COPY_VALUE_FUNC, searchData, dataIndex, dataAlignment, dataSize, endLimit, address, bytes, extraStorage);
				}
			}
			else
			{
				if (!requiresExtraCopy)
				{
					resultSet = ZGSearchWithFunctionHelperStored<T, ZG32BitMemoryAddress>(regionBytes, comparisonFunction, MOVE_VALUE_FUNC, searchData, dataIndex, dataAlignment, dataSize, endLimit, address, bytes, extraStorage);
				}
				else
				{
					resultSet = ZGSearchWithFunctionHelperStored<T, ZG32BitMemoryAddress>(regionBytes, comparisonFunction, COPY_VALUE_FUNC, searchData, dataIndex, dataAlignment, dataSize, endLimit, address, bytes, extraStorage);
				}
			}
		}
		
		return resultSet;
	});
}

template <typename P>
ZGSearchResults *_ZGSearchForBytes(ZGMemoryMap processTask, ZGSearchData *searchData, ZGVariableType dataType, id <ZGSearchProgressDelegate> delegate)
{
	const unsigned long dataSize = searchData.dataSize;
	const unsigned char *searchValue = (searchData.bytesSwapped && searchData.swappedValue != nullptr) ? static_cast<const unsigned char *>(searchData.swappedValue) : static_cast<const unsigned char *>(searchData.searchValue);
	
	BOOL unalignedAccesses = searchResultsHaveUnalignedAccess(searchData, dataType);
	BOOL usesExtraStorage = searchUsesExtraStorage(searchData, dataType, unalignedAccesses, nullptr);
	
	return ZGSearchForDataHelper(processTask, searchData, unalignedAccesses, usesExtraStorage, delegate, ^NSData *(ZGMemorySize __unused dataIndex, ZGMemoryAddress address, ZGMemorySize size, void *bytes, void * __unused regionBytes, void * __unused extraStorage) {
		// generate the two Boyer-Moore auxiliary buffers
		unsigned long charJump[UCHAR_MAX + 1] = {0};
		unsigned long *matchJump = static_cast<unsigned long *>(malloc(2 * (dataSize + 1) * sizeof(*matchJump)));
		
		ZGPrepareBoyerMooreSearch(searchValue, dataSize, charJump, sizeof charJump / sizeof *charJump, matchJump);
		
		unsigned char *foundSubstring = static_cast<unsigned char *>(bytes);
		unsigned long haystackLengthLeft = size;

		P memoryAddresses[INITIAL_BUFFER_ADDRESSES_CAPACITY];
		ZGMemorySize numberOfVariablesFound = 0;
		
		NSMutableData *resultSet = [NSMutableData data];
		
		while (haystackLengthLeft >= dataSize)
		{
			foundSubstring = boyer_moore_helper(static_cast<const unsigned char *>(foundSubstring), searchValue, haystackLengthLeft, static_cast<unsigned long>(dataSize), static_cast<const unsigned long *>(charJump), static_cast<const unsigned long *>(matchJump));
			if (foundSubstring == nullptr) break;
			
			ZGMemoryAddress foundAddress = address + static_cast<ZGMemoryAddress>(foundSubstring - static_cast<unsigned char *>(bytes));
			memoryAddresses[numberOfVariablesFound] = static_cast<P>(foundAddress);
			numberOfVariablesFound++;

			if (numberOfVariablesFound >= INITIAL_BUFFER_ADDRESSES_CAPACITY)
			{
				[resultSet appendBytes:memoryAddresses length:sizeof(memoryAddresses[0]) * numberOfVariablesFound];
				numberOfVariablesFound = 0;
			}
			
			foundSubstring++;
			haystackLengthLeft = address + size - foundAddress - 1;
		}
		
		if (numberOfVariablesFound > 0)
		{
			[resultSet appendBytes:&memoryAddresses length:sizeof(memoryAddresses[0]) * numberOfVariablesFound];
		}

		free(matchJump);
		
		return resultSet;
	});
}

ZGSearchResults *ZGSearchForBytes(ZGMemoryMap processTask, ZGSearchData *searchData, ZGVariableType dataType, id <ZGSearchProgressDelegate> delegate)
{
	ZGSearchResults *searchResults = nil;
	ZGMemorySize pointerSize = searchData.pointerSize;
	switch (pointerSize)
	{
		case sizeof(ZGMemoryAddress):
			searchResults = _ZGSearchForBytes<ZGMemoryAddress>(processTask, searchData, dataType, delegate);
			break;
		case sizeof(ZG32BitMemoryAddress):
			searchResults = _ZGSearchForBytes<ZG32BitMemoryAddress>(processTask, searchData, dataType, delegate);
			break;
	}
	return searchResults;
}

#pragma mark Integers

template <typename T>
bool ZGIntegerEquals(ZGSearchData *__unused __unsafe_unretained searchData, T *__restrict__ variableValue, T * __restrict__ compareValue, T * __restrict__ __unused extraStorage)
{
	return *variableValue == *compareValue;
}

template <typename T>
bool ZGIntegerFastSwappedEquals(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T * __restrict__ __unused compareValue, T * __restrict__ extraStorage)
{
	return ZGIntegerEquals(searchData, variableValue, static_cast<T *>(searchData->_swappedValue), extraStorage);
}

template <typename T>
bool ZGIntegerNotEquals(ZGSearchData * __unsafe_unretained searchData, T *__restrict__ variableValue, T * __restrict__ compareValue, T * __restrict__ extraStorage)
{
	return !ZGIntegerEquals(searchData, variableValue, compareValue, extraStorage);
}

template <typename T>
bool ZGIntegerFastSwappedNotEquals(ZGSearchData * __unsafe_unretained searchData, T * __restrict__ variableValue, T * __restrict__ compareValue, T * __restrict__ extraStorage)
{
	return !ZGIntegerFastSwappedEquals(searchData, variableValue, compareValue, extraStorage);
}

template <typename T>
bool ZGIntegerGreaterThan(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ __unused extraStorage)
{
	return (*variableValue > *compareValue) && (searchData->_rangeValue == nullptr || *variableValue < *static_cast<T *>(searchData->_rangeValue));
}

template <typename T>
bool ZGIntegerSwappedGreaterThan(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T * __restrict__ compareValue, T * __restrict__ extraStorage)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	return ZGIntegerGreaterThan(searchData, &swappedVariableValue, compareValue, extraStorage);
}

template <typename T>
bool ZGIntegerSwappedGreaterThanStored(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	return ZGIntegerGreaterThan(searchData, &swappedVariableValue, &swappedCompareValue, extraStorage);
}

template <typename T>
bool ZGIntegerLesserThan(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ __unused extraStorage)
{
	return (*variableValue < *compareValue) && (searchData->_rangeValue == nullptr || *variableValue > *static_cast<T *>(searchData->_rangeValue));
}

template <typename T>
bool ZGIntegerSwappedLesserThan(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	return ZGIntegerLesserThan(searchData, &swappedVariableValue, compareValue, extraStorage);
}

template <typename T>
bool ZGIntegerSwappedLesserThanStored(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	return ZGIntegerLesserThan(searchData, &swappedVariableValue, &swappedCompareValue, extraStorage);
}

template <typename T>
bool ZGIntegerEqualsLinear(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	T newCompareValue = *static_cast<T *>(searchData->_multiplicativeConstant) * *compareValue + *(static_cast<T *>(searchData->_additiveConstant));
	return ZGIntegerEquals(searchData, variableValue, &newCompareValue, extraStorage);
}

template <typename T>
bool ZGIntegerSwappedEqualsLinear(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	T newCompareValue = *static_cast<T *>(searchData->_multiplicativeConstant) * swappedCompareValue + *(static_cast<T *>(searchData->_additiveConstant));
	
	return ZGIntegerEquals(searchData, &swappedVariableValue, &newCompareValue, extraStorage);
}

template <typename T>
bool ZGIntegerNotEqualsLinear(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	T newCompareValue = *static_cast<T *>(searchData->_multiplicativeConstant) * *compareValue + *(static_cast<T *>(searchData->_additiveConstant));
	return ZGIntegerNotEquals(searchData, variableValue, &newCompareValue, extraStorage);
}

template <typename T>
bool ZGIntegerSwappedNotEqualsLinear(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	return ZGIntegerNotEqualsLinear(searchData, &swappedVariableValue, &swappedCompareValue, extraStorage);
}

template <typename T>
bool ZGIntegerGreaterThanLinear(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	T newCompareValue = *static_cast<T *>(searchData->_multiplicativeConstant) * *compareValue + *(static_cast<T *>(searchData->_additiveConstant));
	return ZGIntegerGreaterThan(searchData, variableValue, &newCompareValue, extraStorage);
}

template <typename T>
bool ZGIntegerSwappedGreaterThanLinear(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	return ZGIntegerGreaterThanLinear(searchData, &swappedVariableValue, &swappedCompareValue, extraStorage);
}

template <typename T>
bool ZGIntegerLesserThanLinear(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	T newCompareValue = *static_cast<T *>(searchData->_multiplicativeConstant) * *compareValue + *(static_cast<T *>(searchData->_additiveConstant));
	return ZGIntegerLesserThan(searchData, variableValue, &newCompareValue, extraStorage);
}

template <typename T>
bool ZGIntegerSwappedLesserThanLinear(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	return ZGIntegerLesserThanLinear(searchData, &swappedVariableValue, &swappedCompareValue, extraStorage);
}

#define ZGHandleIntegerType(functionType, type, integerQualifier, dataType, processTask, searchData, delegate) \
	case dataType: \
		if (integerQualifier == ZGSigned) { \
			retValue = ZGSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, type *a, type *b, type *c) -> bool { return functionType(sd, a, b, c); }, processTask, static_cast<type *>(searchData.searchValue), searchData, dataType, delegate); \
			break; \
		} else { \
			retValue = ZGSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, u##type *a, u##type *b, u##type *c) -> bool { return functionType(sd, a, b, c); }, processTask, static_cast<u##type *>(searchData.searchValue), searchData, dataType, delegate); \
			break; \
		}

#define ZGHandleIntegerCase(dataType, function) \
if (dataType == ZGPointer) {\
	switch (searchData.dataSize) {\
		case sizeof(ZGMemoryAddress):\
			retValue = ZGSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint64_t *a, uint64_t *b, uint64_t *c) -> bool { return function(sd, a, b, c); }, processTask, static_cast<uint64_t *>(searchData.searchValue), searchData, ZGInt64, delegate); \
			break;\
		case sizeof(ZG32BitMemoryAddress):\
			retValue = ZGSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint32_t *a, uint32_t *b, uint32_t *c) -> bool { return function(sd, a, b, c); }, processTask, static_cast<uint32_t *>(searchData.searchValue), searchData, ZGInt32, delegate); \
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
bool ZGFloatingPointEquals(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ __unused extraStorage)
{
	return ABS(*(static_cast<T *>(variableValue)) - *(static_cast<T *>(compareValue))) <= static_cast<T>(searchData->_epsilon);
}

template <typename T>
bool ZGFloatingPointSwappedEquals(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	return ZGFloatingPointEquals(searchData, &swappedVariableValue, compareValue, extraStorage);
}

template <typename T>
bool ZGFloatingPointSwappedEqualsStored(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	return ZGFloatingPointEquals(searchData, &swappedVariableValue, &swappedCompareValue, extraStorage);
}

template <typename T>
bool ZGFloatingPointNotEquals(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	return !ZGFloatingPointEquals(searchData, variableValue, compareValue, extraStorage);
}

template <typename T>
bool ZGFloatingPointSwappedNotEquals(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	return !ZGFloatingPointSwappedEquals(searchData, variableValue, compareValue, extraStorage);
}

template <typename T>
bool ZGFloatingPointSwappedNotEqualsStored(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	return !ZGFloatingPointSwappedEqualsStored(searchData, variableValue, compareValue, extraStorage);
}

template <typename T>
bool ZGFloatingPointGreaterThan(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ __unused extraStorage)
{
	return *variableValue > *compareValue && (searchData->_rangeValue == nullptr || *variableValue < *static_cast<T *>(searchData->_rangeValue));
}

template <typename T>
bool ZGFloatingPointSwappedGreaterThan(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	return ZGFloatingPointGreaterThan(searchData, &swappedVariableValue, compareValue, extraStorage);
}

template <typename T>
bool ZGFloatingPointSwappedGreaterThanStored(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	return ZGFloatingPointGreaterThan(searchData, &swappedVariableValue, &swappedCompareValue, extraStorage);
}

template <typename T>
bool ZGFloatingPointLesserThan(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ __unused extraStorage)
{
	return *variableValue < *compareValue && (searchData->_rangeValue == nullptr || *variableValue > *static_cast<T *>(searchData->_rangeValue));
}

template <typename T>
bool ZGFloatingPointSwappedLesserThan(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	return ZGFloatingPointLesserThan(searchData, &swappedVariableValue, compareValue, extraStorage);
}

template <typename T>
bool ZGFloatingPointSwappedLesserThanStored(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	return ZGFloatingPointLesserThan(searchData, &swappedVariableValue, &swappedCompareValue, extraStorage);
}

template <typename T>
bool ZGFloatingPointEqualsLinear(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	T newCompareValue = *static_cast<T *>(searchData->_multiplicativeConstant) * *compareValue + *(static_cast<T *>(searchData->_additiveConstant));
	return ZGFloatingPointEquals(searchData, variableValue, &newCompareValue, extraStorage);
}

template <typename T>
bool ZGFloatingPointSwappedEqualsLinear(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	return ZGFloatingPointEqualsLinear(searchData, &swappedVariableValue, &swappedCompareValue, extraStorage);
}

template <typename T>
bool ZGFloatingPointNotEqualsLinear(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	T newCompareValue = *(static_cast<T *>(searchData->_multiplicativeConstant)) * *compareValue + *(static_cast<T *>(searchData->_additiveConstant));
	return ZGFloatingPointNotEquals(searchData, variableValue, &newCompareValue, extraStorage);
}

template <typename T>
bool ZGFloatingPointSwappedNotEqualsLinear(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	return ZGFloatingPointNotEqualsLinear(searchData, &swappedVariableValue, &swappedCompareValue, extraStorage);
}

template <typename T>
bool ZGFloatingPointGreaterThanLinear(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	T newCompareValue = *(static_cast<T *>(searchData->_multiplicativeConstant)) * *compareValue + *(static_cast<T *>(searchData->_additiveConstant));
	return ZGFloatingPointGreaterThan(searchData, variableValue, &newCompareValue, extraStorage);
}

template <typename T>
bool ZGFloatingPointSwappedGreaterThanLinear(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	return ZGFloatingPointGreaterThan(searchData, &swappedVariableValue, &swappedCompareValue, extraStorage);
}

template <typename T>
bool ZGFloatingPointLesserThanLinear(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	T newCompareValue = *(static_cast<T *>(searchData->_multiplicativeConstant)) * *compareValue + *(static_cast<T *>(searchData->_additiveConstant));
	return ZGFloatingPointLesserThan(searchData, variableValue, &newCompareValue, extraStorage);
}

template <typename T>
bool ZGFloatingPointSwappedLesserThanLinear(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	return ZGFloatingPointLesserThanLinear(searchData, &swappedVariableValue, &swappedCompareValue, extraStorage);
}

#define ZGHandleType(functionType, type, dataType, processTask, searchData, delegate) \
	case dataType: \
		retValue = ZGSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, type *a, type *b, type *c) -> bool { return functionType(sd, a, b, c); }, processTask, static_cast<type *>(searchData.searchValue), searchData, dataType, delegate); \
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
bool ZGString8CaseInsensitiveEquals(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ __unused extraStorage)
{
	return strncasecmp(variableValue, compareValue, searchData->_dataSize) == 0;
}

template <typename T>
bool ZGString16FastSwappedEquals(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T * __restrict__ __unused compareValue, T * __restrict__ extraStorage)
{
	return ZGByteArrayEquals(searchData, variableValue, static_cast<T *>(searchData->_swappedValue), extraStorage);
}

template <typename T>
bool ZGString16CaseInsensitiveEquals(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ __unused extraStorage)
{
	Boolean isEqual = false;
	UCCompareText(searchData->_collator, variableValue, (static_cast<size_t>(searchData->_dataSize)) / sizeof(T), compareValue, (static_cast<size_t>(searchData->_dataSize)) / sizeof(T), static_cast<Boolean *>(&isEqual), nullptr);
	return isEqual;
}

template <typename T>
bool ZGString16SwappedCaseInsensitiveEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *__restrict__ compareValue, T *extraStorage)
{
	for (uint32_t index = 0; index < searchData->_dataSize / sizeof(T); index++)
	{
		extraStorage[index] = ZGSwapBytes(variableValue[index]);
	}

	return ZGString16CaseInsensitiveEquals(searchData, extraStorage, compareValue, static_cast<T *>(nullptr));
}

template <typename T>
bool ZGString8CaseInsensitiveNotEquals(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	return !ZGString8CaseInsensitiveEquals(searchData, variableValue, compareValue, extraStorage);
}

template <typename T>
bool ZGString16FastSwappedNotEquals(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	return !ZGString16FastSwappedEquals(searchData, variableValue, compareValue, extraStorage);
}

template <typename T>
bool ZGString16CaseInsensitiveNotEquals(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ extraStorage)
{
	return !ZGString16CaseInsensitiveEquals(searchData, variableValue, compareValue, extraStorage);
}

template <typename T>
bool ZGString16SwappedCaseInsensitiveNotEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *__restrict__ compareValue, T * extraStorage)
{
	return !ZGString16SwappedCaseInsensitiveEquals(searchData, variableValue, compareValue, extraStorage);
}

template <typename T>
bool ZGString16FastSwappedCaseSensitiveNotEquals(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ __unused compareValue, T * __restrict__ extraStorage)
{
	return ZGByteArrayNotEquals(searchData, variableValue, static_cast<T *>(searchData->_swappedValue), extraStorage);
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
bool ZGByteArrayWithWildcardsEquals(ZGSearchData *__unsafe_unretained searchData, T * __restrict__ variableValue, T *__restrict__ compareValue, T * __unused __restrict__ extraStorage)
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
bool ZGByteArrayWithWildcardsNotEquals(ZGSearchData *__unsafe_unretained searchData, T * __restrict__ variableValue, T * __restrict__ compareValue, T * __restrict__ extraStorage)
{
	return !ZGByteArrayWithWildcardsEquals(searchData, variableValue, compareValue, extraStorage);
}

ZGSearchResults *ZGSearchForByteArraysWithWildcards(ZGMemoryMap processTask, ZGSearchData *searchData, id <ZGSearchProgressDelegate> delegate, ZGFunctionType functionType)
{
	id retValue = nil;
	
	switch (functionType)
	{
		case ZGEquals:
			retValue = ZGSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b, uint8_t *c) -> bool { return ZGByteArrayWithWildcardsEquals(sd, a, b, c); }, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, ZGByteArray, delegate);
			break;
		case ZGNotEquals:
			retValue = ZGSearchWithFunction([](ZGSearchData *__unsafe_unretained sd, uint8_t *a, uint8_t *b, uint8_t *c) -> bool { return ZGByteArrayWithWildcardsNotEquals(sd, a, b, c); }, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, ZGByteArray, delegate);
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
			retValue = ZGSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b, uint8_t *c) -> bool { return ZGByteArrayNotEquals(sd, a, b, c); }, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, ZGByteArray, delegate);
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
	if (((dataType == ZGByteArray && searchData.byteArrayFlags == nullptr) || ((dataType == ZGString8 || dataType == ZGString16) && !searchData.shouldIgnoreStringCase)) && !searchData.shouldCompareStoredValues && functionType == ZGEquals)
	{
		// use fast boyer moore
		retValue = ZGSearchForBytes(processTask, searchData, dataType, delegate);
	}
	else
	{
		switch (dataType)
		{
			case ZGInt8:
			case ZGInt16:
			case ZGInt32:
			case ZGInt64:
			case ZGPointer:
				retValue = ZGSearchForIntegers(processTask, searchData, delegate, dataType, integerQualifier, functionType);
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
				if (searchData.byteArrayFlags == nullptr)
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

typedef NSData *(^zg_narrow_search_for_data_helper_t)(size_t resultSetIndex, NSUInteger oldResultSetStartIndex, NSData * __unsafe_unretained oldResultSet, void *extraStorage);

ZGSearchResults *ZGNarrowSearchForDataHelper(ZGSearchData *searchData, id <ZGSearchProgressDelegate> delegate, ZGSearchResults *firstSearchResults, ZGSearchResults *laterSearchResults, BOOL unalignedAccess, BOOL usesExtraStorage, zg_narrow_search_for_data_helper_t helper)
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
	
	NSMutableArray<NSData *> *newResultSets = [[NSMutableArray alloc] init];
	for (NSUInteger regionIndex = 0; regionIndex < newResultSetCount; regionIndex++)
	{
		[newResultSets addObject:[[NSData alloc] init]];
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
				
				if (oldResultSet.length >= pointerSize && startIndex < oldResultSet.length)
				{
					void *extraStorage = usesExtraStorage ? calloc(1, dataSize) : nullptr;
					newResultSets[resultSetIndex] = helper(resultSetIndex, startIndex, oldResultSet, extraStorage);
					free(extraStorage);
				}
				
				if (delegate != nil)
				{
					dispatch_async(dispatch_get_main_queue(), ^{
						searchProgress.numberOfVariablesFound += newResultSets[resultSetIndex].length / pointerSize;
						searchProgress.progress++;
						[delegate progress:searchProgress advancedWithResultSet:newResultSets[resultSetIndex]];
					});
				}
			}
		}
	});
	
	free(laterResultSetsAbsoluteIndexes);
	
	NSArray<NSData *> *resultSets;
	
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
		resultSets = [newResultSets zgFilterUsingBlock:^(NSData *resultSet) {
			return static_cast<BOOL>(resultSet.length != 0);
		}];
	}
	
	return [[ZGSearchResults alloc] initWithResultSets:resultSets dataSize:dataSize pointerSize:pointerSize unalignedAccess:unalignedAccess];
}

template <typename T, typename P, typename F, typename C>
void ZGNarrowSearchWithFunctionRegularCompare(ZGRegion * __unused *lastUsedSavedRegionReference, ZGRegion * __unsafe_unretained lastUsedRegion, P variableAddress, ZGMemorySize dataSize, NSDictionary<NSNumber *, ZGRegion *> * __unused __unsafe_unretained savedPageToRegionTable, NSArray<ZGRegion *> * __unused __unsafe_unretained savedRegions, ZGMemorySize __unused pageSize, F comparisonFunction, C transferBytes, P *memoryAddresses, ZGMemorySize &numberOfVariablesFound, ZGSearchData * __unsafe_unretained searchData, T *searchValue, void *extraStorage)
{
	T *currentValue = static_cast<T *>(transferBytes(static_cast<uint8_t *>(lastUsedRegion->_bytes) + (variableAddress - lastUsedRegion->_address), extraStorage, dataSize));
	
	if (comparisonFunction(searchData, currentValue, searchValue, static_cast<T *>(extraStorage)))
	{
		memoryAddresses[numberOfVariablesFound] = variableAddress;
		numberOfVariablesFound++;
	}
}

template <typename T, typename P, typename F, typename C>
void ZGNarrowSearchWithFunctionStoredCompare(ZGRegion **lastUsedSavedRegionReference, ZGRegion * __unsafe_unretained lastUsedRegion, P variableAddress, ZGMemorySize dataSize, NSDictionary<NSNumber *, ZGRegion *> * __unsafe_unretained savedPageToRegionTable, NSArray<ZGRegion *> * __unsafe_unretained savedRegions, ZGMemorySize pageSize, F comparisonFunction, C transferBytes, P *memoryAddresses, ZGMemorySize &numberOfVariablesFound, ZGSearchData * __unsafe_unretained searchData, T * __unused searchValue, void *extraStorage)
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
		T *currentValue = static_cast<T *>(transferBytes(static_cast<uint8_t *>(lastUsedRegion->_bytes) + (variableAddress - lastUsedRegion->_address), extraStorage, dataSize));
		
		T *compareValue = static_cast<T *>(transferBytes(static_cast<uint8_t *>((*lastUsedSavedRegionReference)->_bytes) + (variableAddress - (*lastUsedSavedRegionReference)->_address), extraStorage, dataSize));
		
		if (comparisonFunction(searchData, currentValue, compareValue, static_cast<T *>(extraStorage)))
		{
			memoryAddresses[numberOfVariablesFound] = variableAddress;
			numberOfVariablesFound++;
		}
	}
}

template <typename T, typename P, typename F, typename H>
NSData *ZGNarrowSearchWithFunctionType(F comparisonFunction, ZGMemoryMap processTask, T *searchValue, ZGSearchData * __unsafe_unretained searchData, void *extraStorage, P __unused pointerSize, ZGMemorySize dataSize, NSUInteger oldResultSetStartIndex, NSData * __unsafe_unretained oldResultSet, NSDictionary<NSNumber *, ZGRegion *> * __unsafe_unretained pageToRegionTable, NSDictionary<NSNumber *, ZGRegion *> * __unsafe_unretained savedPageToRegionTable, NSArray<ZGRegion *> * __unsafe_unretained savedRegions, ZGMemorySize pageSize, H compareHelperFunction)
{
	ZGRegion *lastUsedRegion = nil;
	ZGRegion *lastUsedSavedRegion = nil;
	
	ZGMemorySize oldDataLength = oldResultSet.length;
	const void *oldResultSetBytes = oldResultSet.bytes;
	
	ZGProtectionMode protectionMode = searchData.protectionMode;
	bool regionMatchesProtection = true;

	ZGMemoryAddress beginAddress = searchData.beginAddress;
	ZGMemoryAddress endAddress = searchData.endAddress;
	
	size_t addressCapacity = INITIAL_BUFFER_ADDRESSES_CAPACITY;
	P *memoryAddresses = static_cast<P *>(malloc(addressCapacity * sizeof(*memoryAddresses)));
	ZGMemorySize numberOfVariablesFound = 0;

	ZGMemoryAddress dataIndex = oldResultSetStartIndex;
	while (dataIndex < oldDataLength)
	{
		if (numberOfVariablesFound == addressCapacity)
		{
			addressCapacity = static_cast<size_t>(addressCapacity * REALLOCATION_GROWTH_RATE);
			memoryAddresses = static_cast<P *>(realloc(memoryAddresses, addressCapacity * sizeof(*memoryAddresses)));
		}
		
		ZGMemorySize numberOfStepsToTake = MIN(addressCapacity - numberOfVariablesFound, (oldDataLength - dataIndex) / sizeof(P));
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
						newRegion = [[ZGRegion alloc] initWithAddress:regionAddress size:regionSize protection:basicInfo.protection userTag:0];
						regionMatchesProtection = ZGMemoryProtectionMatchesProtectionMode(basicInfo.protection, protectionMode);
					}
				}
				else
				{
					newRegion = [pageToRegionTable objectForKey:@(variableAddress - (variableAddress % pageSize))];
				}
				
				if (newRegion != nil && variableAddress >= newRegion->_address && variableAddress + dataSize <= newRegion->_address + newRegion->_size)
				{
					// Read all the pages enclosing the start and end variable address
					// Reading the entire region may be too expensive
					ZGMemoryAddress startPageAddress = variableAddress - (variableAddress % pageSize);
					ZGMemoryAddress endPageAddress = (variableAddress + dataSize) + (pageSize - ((variableAddress + dataSize) % pageSize));
					ZGMemorySize totalRegionSize = (endPageAddress - startPageAddress);
					
					lastUsedRegion = [[ZGRegion alloc] initWithAddress:startPageAddress size:totalRegionSize];
					
					void *bytes = nullptr;
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
				compareHelperFunction(&lastUsedSavedRegion, lastUsedRegion, variableAddress, dataSize, savedPageToRegionTable, savedRegions, pageSize, comparisonFunction, memoryAddresses, numberOfVariablesFound, searchData, searchValue, extraStorage);
			}
			
			dataIndex += sizeof(P);
		}
	}
	
	if (lastUsedRegion != nil)
	{
		ZGFreeBytes(lastUsedRegion->_bytes, lastUsedRegion->_size);
	}
	
	return [NSData dataWithBytesNoCopy:memoryAddresses length:numberOfVariablesFound * sizeof(*memoryAddresses) freeWhenDone:YES];
}

template <typename T, typename F>
ZGSearchResults *ZGNarrowSearchWithFunction(F comparisonFunction, ZGMemoryMap processTask, T *searchValue, ZGSearchData * __unsafe_unretained searchData, ZGVariableType dataType, id <ZGSearchProgressDelegate> delegate, ZGSearchResults * __unsafe_unretained firstSearchResults, ZGSearchResults * __unsafe_unretained laterSearchResults)
{
	ZGMemorySize pointerSize = searchData.pointerSize;
	ZGMemorySize dataSize = searchData.dataSize;
	BOOL shouldCompareStoredValues = searchData.shouldCompareStoredValues;
	
	ZGMemorySize pageSize = NSPageSize(); // sane default
	ZGPageSize(processTask, &pageSize);
	
	BOOL includeSharedMemory = searchData.includeSharedMemory;
	NSArray<ZGRegion *> *allRegions = includeSharedMemory ? [ZGRegion submapRegionsFromProcessTask:processTask] : [ZGRegion regionsFromProcessTask:processTask];
	
	BOOL unalignedAccess = firstSearchResults.unalignedAccess || laterSearchResults.unalignedAccess;
	BOOL requiresExtraCopy = NO;
	BOOL usesExtraStorage = searchUsesExtraStorage(searchData, dataType, unalignedAccess, &requiresExtraCopy);
	
	return ZGNarrowSearchForDataHelper(searchData, delegate, firstSearchResults, laterSearchResults, unalignedAccess, usesExtraStorage, ^NSData *(size_t resultSetIndex, NSUInteger oldResultSetStartIndex, NSData * __unsafe_unretained oldResultSet, void *extraStorage) {
		NSMutableDictionary<NSNumber *, ZGRegion *> *pageToRegionTable = nil;
		
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

			NSArray<ZGRegion *> *regions = ZGFilterRegions(allRegions, firstAddress, lastAddress, searchData.protectionMode, includeSharedMemory);
			
			for (ZGRegion *region in regions)
			{
				ZGMemoryAddress regionAddress = region.address;
				ZGMemorySize regionSize = region.size;
				for (NSUInteger dataIndex = 0; dataIndex < regionSize; dataIndex += pageSize)
				{
					pageToRegionTable[@(dataIndex + regionAddress)] = region;
				}
			}
		}
		
		NSData *newResultSet;
		
		if (!shouldCompareStoredValues)
		{
			if (pointerSize == sizeof(ZGMemoryAddress))
			{
				if (!requiresExtraCopy)
				{
					auto compareHelperFunc = [](ZGRegion **_lastUsedSavedRegion, ZGRegion *_lastUsedRegion, ZGMemoryAddress _variableAddress, ZGMemorySize _dataSize, NSDictionary<NSNumber *, ZGRegion *> *_savedPageToRegionTable, NSArray<ZGRegion *> *_savedRegions, ZGMemorySize _pageSize, F _comparisonFunction, ZGMemoryAddress *_memoryAddresses, ZGMemorySize &_numberOfVariablesFound, ZGSearchData *_searchData, T *_searchValue, void *_extraStorage) {
						
						ZGNarrowSearchWithFunctionRegularCompare(_lastUsedSavedRegion, _lastUsedRegion, _variableAddress, _dataSize, _savedPageToRegionTable, _savedRegions, _pageSize, _comparisonFunction, MOVE_VALUE_FUNC, _memoryAddresses, _numberOfVariablesFound, _searchData, _searchValue, _extraStorage);
					};
					
					newResultSet = ZGNarrowSearchWithFunctionType(comparisonFunction, processTask, searchValue, searchData, extraStorage, static_cast<ZGMemoryAddress>(pointerSize), dataSize, oldResultSetStartIndex, oldResultSet, pageToRegionTable, nil, nil, pageSize, compareHelperFunc);
				}
				else
				{
					auto compareHelperFunc = [](ZGRegion **_lastUsedSavedRegion, ZGRegion *_lastUsedRegion, ZGMemoryAddress _variableAddress, ZGMemorySize _dataSize, NSDictionary<NSNumber *, ZGRegion *> *_savedPageToRegionTable, NSArray<ZGRegion *> *_savedRegions, ZGMemorySize _pageSize, F _comparisonFunction, ZGMemoryAddress *_memoryAddresses, ZGMemorySize &_numberOfVariablesFound, ZGSearchData *_searchData, T *_searchValue, void *_extraStorage) {
						
						ZGNarrowSearchWithFunctionRegularCompare(_lastUsedSavedRegion, _lastUsedRegion, _variableAddress, _dataSize, _savedPageToRegionTable, _savedRegions, _pageSize, _comparisonFunction, COPY_VALUE_FUNC, _memoryAddresses, _numberOfVariablesFound, _searchData, _searchValue, _extraStorage);
					};
					
					newResultSet = ZGNarrowSearchWithFunctionType(comparisonFunction, processTask, searchValue, searchData, extraStorage, static_cast<ZGMemoryAddress>(pointerSize), dataSize, oldResultSetStartIndex, oldResultSet, pageToRegionTable, nil, nil, pageSize, compareHelperFunc);
				}
			}
			else
			{
				if (!requiresExtraCopy)
				{
					auto compareHelperFunc = [](ZGRegion **_lastUsedSavedRegion, ZGRegion *_lastUsedRegion, ZG32BitMemoryAddress _variableAddress, ZGMemorySize _dataSize, NSDictionary<NSNumber *, ZGRegion *> *_savedPageToRegionTable, NSArray<ZGRegion *> *_savedRegions, ZGMemorySize _pageSize, F _comparisonFunction, ZG32BitMemoryAddress *_memoryAddresses, ZGMemorySize &_numberOfVariablesFound, ZGSearchData *_searchData, T *_searchValue, void *_extraStorage) {
						
						ZGNarrowSearchWithFunctionRegularCompare(_lastUsedSavedRegion, _lastUsedRegion, _variableAddress, _dataSize, _savedPageToRegionTable, _savedRegions, _pageSize, _comparisonFunction, MOVE_VALUE_FUNC, _memoryAddresses, _numberOfVariablesFound, _searchData, _searchValue, _extraStorage);
					};
					
					newResultSet = ZGNarrowSearchWithFunctionType(comparisonFunction, processTask, searchValue, searchData, extraStorage, static_cast<ZG32BitMemoryAddress>(pointerSize), dataSize, oldResultSetStartIndex, oldResultSet, pageToRegionTable, nil, nil, pageSize, compareHelperFunc);
				}
				else
				{
					auto compareHelperFunc = [](ZGRegion **_lastUsedSavedRegion, ZGRegion *_lastUsedRegion, ZG32BitMemoryAddress _variableAddress, ZGMemorySize _dataSize, NSDictionary<NSNumber *, ZGRegion *> *_savedPageToRegionTable, NSArray<ZGRegion *> *_savedRegions, ZGMemorySize _pageSize, F _comparisonFunction, ZG32BitMemoryAddress *_memoryAddresses, ZGMemorySize &_numberOfVariablesFound, ZGSearchData *_searchData, T *_searchValue, void *_extraStorage) {
						
						ZGNarrowSearchWithFunctionRegularCompare(_lastUsedSavedRegion, _lastUsedRegion, _variableAddress, _dataSize, _savedPageToRegionTable, _savedRegions, _pageSize, _comparisonFunction, COPY_VALUE_FUNC, _memoryAddresses, _numberOfVariablesFound, _searchData, _searchValue, _extraStorage);
					};
					
					newResultSet = ZGNarrowSearchWithFunctionType(comparisonFunction, processTask, searchValue, searchData, extraStorage, static_cast<ZG32BitMemoryAddress>(pointerSize), dataSize, oldResultSetStartIndex, oldResultSet, pageToRegionTable, nil, nil, pageSize, compareHelperFunc);
				}
			}
		}
		else
		{
			NSArray<ZGRegion *> *savedData = searchData.savedData.regions;
			
			NSMutableDictionary<NSNumber *, ZGRegion *> *pageToSavedRegionTable = nil;
			
			if (pageToRegionTable != nil)
			{
				pageToSavedRegionTable = [[NSMutableDictionary alloc] init];
				
				NSArray<ZGRegion *> *regions = ZGFilterRegions(savedData, firstAddress, lastAddress, searchData.protectionMode, includeSharedMemory);
				
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
				if (!requiresExtraCopy)
				{
					auto compareHelperFunc = [](ZGRegion **_lastUsedSavedRegion, ZGRegion *_lastUsedRegion, ZGMemoryAddress _variableAddress, ZGMemorySize _dataSize, NSDictionary<NSNumber *, ZGRegion *> *_savedPageToRegionTable, NSArray<ZGRegion *> *_savedRegions, ZGMemorySize _pageSize, F _comparisonFunction, ZGMemoryAddress *_memoryAddresses, ZGMemorySize &_numberOfVariablesFound, ZGSearchData *_searchData, T *_searchValue, void *_extraStorage) {
						
						ZGNarrowSearchWithFunctionStoredCompare(_lastUsedSavedRegion, _lastUsedRegion, _variableAddress, _dataSize, _savedPageToRegionTable, _savedRegions, _pageSize, _comparisonFunction, MOVE_VALUE_FUNC, _memoryAddresses, _numberOfVariablesFound, _searchData, _searchValue, _extraStorage);
					};
					
					newResultSet = ZGNarrowSearchWithFunctionType(comparisonFunction, processTask, searchValue, searchData, extraStorage, static_cast<ZGMemoryAddress>(pointerSize), dataSize, oldResultSetStartIndex, oldResultSet, pageToRegionTable, pageToSavedRegionTable, savedData, pageSize, compareHelperFunc);
				}
				else
				{
					auto compareHelperFunc = [](ZGRegion **_lastUsedSavedRegion, ZGRegion *_lastUsedRegion, ZGMemoryAddress _variableAddress, ZGMemorySize _dataSize, NSDictionary<NSNumber *, ZGRegion *> *_savedPageToRegionTable, NSArray<ZGRegion *> *_savedRegions, ZGMemorySize _pageSize, F _comparisonFunction, ZGMemoryAddress *_memoryAddresses, ZGMemorySize &_numberOfVariablesFound, ZGSearchData *_searchData, T *_searchValue, void *_extraStorage) {
						
						ZGNarrowSearchWithFunctionStoredCompare(_lastUsedSavedRegion, _lastUsedRegion, _variableAddress, _dataSize, _savedPageToRegionTable, _savedRegions, _pageSize, _comparisonFunction, COPY_VALUE_FUNC, _memoryAddresses, _numberOfVariablesFound, _searchData, _searchValue, _extraStorage);
					};
					
					newResultSet = ZGNarrowSearchWithFunctionType(comparisonFunction, processTask, searchValue, searchData, extraStorage, static_cast<ZGMemoryAddress>(pointerSize), dataSize, oldResultSetStartIndex, oldResultSet, pageToRegionTable, pageToSavedRegionTable, savedData, pageSize, compareHelperFunc);
				}
			}
			else
			{
				if (!requiresExtraCopy)
				{
					auto compareHelperFunc = [](ZGRegion **_lastUsedSavedRegion, ZGRegion *_lastUsedRegion, ZG32BitMemoryAddress _variableAddress, ZGMemorySize _dataSize, NSDictionary<NSNumber *, ZGRegion *> *_savedPageToRegionTable, NSArray<ZGRegion *> *_savedRegions, ZGMemorySize _pageSize, F _comparisonFunction, ZG32BitMemoryAddress *_memoryAddresses, ZGMemorySize &_numberOfVariablesFound, ZGSearchData *_searchData, T *_searchValue, void *_extraStorage) {
						
						ZGNarrowSearchWithFunctionStoredCompare(_lastUsedSavedRegion, _lastUsedRegion, _variableAddress, _dataSize, _savedPageToRegionTable, _savedRegions, _pageSize, _comparisonFunction, MOVE_VALUE_FUNC, _memoryAddresses, _numberOfVariablesFound, _searchData, _searchValue, _extraStorage);
					};
					
					newResultSet = ZGNarrowSearchWithFunctionType(comparisonFunction, processTask, searchValue, searchData, extraStorage, static_cast<ZG32BitMemoryAddress>(pointerSize), dataSize, oldResultSetStartIndex, oldResultSet, pageToRegionTable, pageToSavedRegionTable, savedData, pageSize, compareHelperFunc);
				}
				else
				{
					auto compareHelperFunc = [](ZGRegion **_lastUsedSavedRegion, ZGRegion *_lastUsedRegion, ZG32BitMemoryAddress _variableAddress, ZGMemorySize _dataSize, NSDictionary<NSNumber *, ZGRegion *> *_savedPageToRegionTable, NSArray<ZGRegion *> *_savedRegions, ZGMemorySize _pageSize, F _comparisonFunction, ZG32BitMemoryAddress *_memoryAddresses, ZGMemorySize &_numberOfVariablesFound, ZGSearchData *_searchData, T *_searchValue, void *_extraStorage) {
						
						ZGNarrowSearchWithFunctionStoredCompare(_lastUsedSavedRegion, _lastUsedRegion, _variableAddress, _dataSize, _savedPageToRegionTable, _savedRegions, _pageSize, _comparisonFunction, COPY_VALUE_FUNC, _memoryAddresses, _numberOfVariablesFound, _searchData, _searchValue, _extraStorage);
					};
					
					newResultSet = ZGNarrowSearchWithFunctionType(comparisonFunction, processTask, searchValue, searchData, extraStorage, static_cast<ZG32BitMemoryAddress>(pointerSize), dataSize, oldResultSetStartIndex, oldResultSet, pageToRegionTable, pageToSavedRegionTable, savedData, pageSize, compareHelperFunc);
				}
			}
		}
		
		return newResultSet;
	});
}

#pragma mark Narrowing Integers

#define ZGHandleNarrowIntegerType(functionType, type, integerQualifier, dataType, processTask, searchData, delegate, firstSearchResults, laterSearchResults) \
case dataType: \
if (integerQualifier == ZGSigned) \
	retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, type * a, type *b, type *c) -> bool { return functionType(sd, a, b, c); }, processTask, static_cast<type *>(searchData.searchValue), searchData, dataType, delegate, firstSearchResults, laterSearchResults); \
else \
	retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, u##type *a, u##type *b, u##type *c) -> bool { return functionType(sd, a, b, c); }, processTask, static_cast<u##type *>(searchData.searchValue), searchData, dataType, delegate, firstSearchResults, laterSearchResults); \
break

#define ZGHandleNarrowIntegerCase(dataType, function) \
if (dataType == ZGPointer) {\
	switch (searchData.dataSize) {\
		case sizeof(ZGMemoryAddress):\
			retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint64_t *a, uint64_t *b, uint64_t *c) -> bool { return function(sd, a, b, c); }, processTask, static_cast<uint64_t *>(searchData.searchValue), searchData, ZGInt64, delegate, firstSearchResults, laterSearchResults); \
			break;\
		case sizeof(ZG32BitMemoryAddress):\
			retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint32_t *a, uint32_t *b, uint32_t *c) -> bool { return function(sd, a, b, c); }, processTask, static_cast<uint32_t *>(searchData.searchValue), searchData, ZGInt32, delegate, firstSearchResults, laterSearchResults); \
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
		retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, type *a, type *b, type *c) -> bool { return functionType(sd, a, b, c); }, processTask, static_cast<type *>(searchData.searchValue), searchData, dataType, delegate, firstSearchResults, laterSearchResults);\
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
bool ZGByteArrayEquals(ZGSearchData *__unsafe_unretained searchData, T * __restrict__ variableValue, T * __restrict__ compareValue, T * __restrict__ __unused extraStorage)
{
	return (memcmp(static_cast<void *>(variableValue), static_cast<void *>(compareValue), searchData->_dataSize) == 0);
}

template <typename T>
bool ZGByteArrayNotEquals(ZGSearchData *__unsafe_unretained searchData, T * __restrict__ variableValue, T *__restrict__ compareValue, T *__restrict__ extraStorage)
{
	return !ZGByteArrayEquals(searchData, variableValue, compareValue, extraStorage);
}

ZGSearchResults *ZGNarrowSearchForByteArrays(ZGMemoryMap processTask, ZGSearchData *searchData, ZGVariableType dataType, id <ZGSearchProgressDelegate> delegate, ZGFunctionType functionType, ZGSearchResults *firstSearchResults, ZGSearchResults *laterSearchResults)
{
	id retValue = nil;
	
	switch (functionType)
	{
		case ZGEquals:
			if (searchData.byteArrayFlags != nullptr)
			{
				retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b, uint8_t *c) -> bool { return ZGByteArrayWithWildcardsEquals(sd, a, b, c); }, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, dataType, delegate, firstSearchResults, laterSearchResults);
			}
			else
			{
				retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b, uint8_t *c) -> bool { return ZGByteArrayEquals(sd, a, b, c); }, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, dataType, delegate, firstSearchResults, laterSearchResults);
			}
			break;
		case ZGNotEquals:
			if (searchData.byteArrayFlags != nullptr)
			{
				retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b, uint8_t *c) -> bool { return ZGByteArrayWithWildcardsNotEquals(sd, a, b, c); }, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, dataType, delegate, firstSearchResults, laterSearchResults);
			}
			else
			{
				retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b, uint8_t *c) -> bool { return ZGByteArrayNotEquals(sd, a, b, c); }, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, dataType, delegate, firstSearchResults, laterSearchResults);
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
					retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b, uint8_t *c) -> bool { return ZGString16FastSwappedEquals(sd, a, b, c); }, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, dataType, delegate, firstSearchResults, laterSearchResults);
				}
				else
				{
					retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b, uint8_t *c) -> bool { return ZGByteArrayEquals(sd, a, b, c); }, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, dataType, delegate, firstSearchResults, laterSearchResults);
				}
				break;
			case ZGNotEquals:
				if (dataType == ZGString16 && searchData.bytesSwapped)
				{
					retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b, uint8_t *c) -> bool { return ZGString16FastSwappedNotEquals(sd, a, b, c); }, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, dataType, delegate, firstSearchResults, laterSearchResults);
				}
				else
				{
					retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b, uint8_t *c) -> bool { return ZGByteArrayNotEquals(sd, a, b, c); }, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, dataType, delegate, firstSearchResults, laterSearchResults);
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
			retValue = ZGNarrowSearchForByteArrays(processTask, searchData, dataType, delegate, functionType, firstSearchResults, laterSearchResults);
			break;
		case ZGScript:
			break;
	}
	
	return retValue;
}
