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

#pragma mark Generic Searching

static bool ZGMemoryProtectionMatchesProtectionMode(ZGMemoryProtection memoryProtection, ZGProtectionMode protectionMode)
{
	return ((protectionMode == ZGProtectionAll && memoryProtection & VM_PROT_READ) || (protectionMode == ZGProtectionWrite && memoryProtection & VM_PROT_WRITE) || (protectionMode == ZGProtectionExecute && memoryProtection & VM_PROT_EXECUTE));
}

static NSArray<ZGRegion *> *ZGFilterRegions(NSArray<ZGRegion *> *regions, ZGMemoryAddress beginAddress, ZGMemoryAddress endAddress, ZGProtectionMode protectionMode)
{
	return [regions zgFilterUsingBlock:^(ZGRegion *region) {
		return static_cast<BOOL>(region.address < endAddress && region.address + region.size > beginAddress && ZGMemoryProtectionMatchesProtectionMode(region.protection, protectionMode));
	}];
}

typedef NSData *(^zg_search_for_data_helper_t)(ZGMemorySize dataIndex, ZGMemoryAddress address, ZGMemorySize size, void *bytes, void *regionBytes);

ZGSearchResults *ZGSearchForDataHelper(ZGMemoryMap processTask, ZGSearchData *searchData, id <ZGSearchProgressDelegate> delegate,  zg_search_for_data_helper_t helper)
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
					allResultSets[regionIndex] = helper(dataIndex, address, size, bytes, regionBytes);
					
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
	
	return [[ZGSearchResults alloc] initWithResultSets:resultSets dataSize:dataSize pointerSize:pointerSize];
}

template <typename T, typename P, typename F>
NSData *ZGSearchWithFunctionHelperRegular(T *searchValue, F comparisonFunction, ZGSearchData * __unsafe_unretained searchData, ZGMemorySize dataIndex, ZGMemorySize dataAlignment, ZGMemorySize endLimit, ZGMemoryAddress address, void *bytes)
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
			if (comparisonFunction(searchData, static_cast<T *>(static_cast<void *>(static_cast<uint8_t *>(bytes) + dataIndex)), searchValue))
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
template <typename T, typename P, typename F>
NSData *ZGSearchWithFunctionHelperStored(T *regionBytes, F comparisonFunction, ZGSearchData * __unsafe_unretained searchData, ZGMemorySize dataIndex, ZGMemorySize dataAlignment, ZGMemorySize endLimit, ZGMemoryAddress address, void *bytes)
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
			if (comparisonFunction(searchData, (static_cast<T *>(static_cast<void *>(static_cast<uint8_t *>(bytes) + dataIndex))), static_cast<T *>(static_cast<void *>(static_cast<uint8_t *>(static_cast<void *>(regionBytes)) + dataIndex))))
			{
				memoryAddresses[numberOfVariablesFound] = static_cast<P>(address + dataIndex);
				numberOfVariablesFound++;
			}
			
			dataIndex += dataAlignment;
		}
	}
	
	return [NSData dataWithBytesNoCopy:memoryAddresses length:numberOfVariablesFound * sizeof(*memoryAddresses) freeWhenDone:YES];
}

template <typename T, typename F>
ZGSearchResults *ZGSearchWithFunction(F comparisonFunction, ZGMemoryMap processTask, T *searchValue, ZGSearchData * __unsafe_unretained searchData, id <ZGSearchProgressDelegate> delegate)
{
	ZGMemorySize dataAlignment = searchData.dataAlignment;
	ZGMemorySize pointerSize = searchData.pointerSize;
	ZGMemorySize dataSize = searchData.dataSize;
	BOOL shouldCompareStoredValues = searchData.shouldCompareStoredValues;
	
	return ZGSearchForDataHelper(processTask, searchData, delegate, ^NSData *(ZGMemorySize dataIndex, ZGMemoryAddress address, ZGMemorySize size, void *bytes, void *regionBytes) {
		ZGMemorySize endLimit = size - dataSize;
		
		NSData *resultSet;
		
		if (!shouldCompareStoredValues)
		{
			if (pointerSize == sizeof(ZGMemoryAddress))
			{
				resultSet = ZGSearchWithFunctionHelperRegular<T, ZGMemoryAddress>(searchValue, comparisonFunction, searchData, dataIndex, dataAlignment, endLimit, address, bytes);
			}
			else
			{
				resultSet = ZGSearchWithFunctionHelperRegular<T, ZG32BitMemoryAddress>(searchValue, comparisonFunction, searchData, dataIndex, dataAlignment, endLimit, address, bytes);
			}
		}
		else
		{
			if (pointerSize == sizeof(ZGMemoryAddress))
			{
				resultSet = ZGSearchWithFunctionHelperStored<T, ZGMemoryAddress>(static_cast<T *>(regionBytes), comparisonFunction, searchData, dataIndex, dataAlignment, endLimit, address, bytes);
			}
			else
			{
				resultSet = ZGSearchWithFunctionHelperStored<T, ZG32BitMemoryAddress>(static_cast<T *>(regionBytes), comparisonFunction, searchData, dataIndex, dataAlignment, endLimit, address, bytes);
			}
		}
		
		return resultSet;
	});
}

template <typename P>
ZGSearchResults *_ZGSearchForBytes(ZGMemoryMap processTask, ZGSearchData *searchData, id <ZGSearchProgressDelegate> delegate)
{
	const unsigned long dataSize = searchData.dataSize;
	const unsigned char *searchValue = (searchData.bytesSwapped && searchData.swappedValue != NULL) ? static_cast<const unsigned char *>(searchData.swappedValue) : static_cast<const unsigned char *>(searchData.searchValue);
	ZGMemorySize dataAlignment = searchData.dataAlignment;
	
	return ZGSearchForDataHelper(processTask, searchData, delegate, ^NSData *(ZGMemorySize __unused dataIndex, ZGMemoryAddress address, ZGMemorySize size, void *bytes, void * __unused regionBytes) {
		// generate the two Boyer-Moore auxiliary buffers
		unsigned long charJump[UCHAR_MAX + 1] = {0};
		unsigned long *matchJump = static_cast<unsigned long *>(malloc(2 * (dataSize + 1) * sizeof(*matchJump)));
		
		ZGPrepareBoyerMooreSearch(searchValue, dataSize, charJump, matchJump);
		
		unsigned char *foundSubstring = static_cast<unsigned char *>(bytes);
		unsigned long haystackLengthLeft = size;

		P memoryAddresses[INITIAL_BUFFER_ADDRESSES_CAPACITY];
		ZGMemorySize numberOfVariablesFound = 0;
		
		NSMutableData *resultSet = [NSMutableData data];
		
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

				if (numberOfVariablesFound >= INITIAL_BUFFER_ADDRESSES_CAPACITY)
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
		
		return resultSet;
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
		if (integerQualifier == ZGSigned) { \
			retValue = ZGSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, type *a, type *b) -> bool { return functionType(sd, a, b); }, processTask, static_cast<type *>(searchData.searchValue), searchData, delegate); \
			break; \
		} else { \
			retValue = ZGSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, u##type *a, u##type *b) -> bool { return functionType(sd, a, b); }, processTask, static_cast<u##type *>(searchData.searchValue), searchData, delegate); \
			break; \
		}

#define ZGHandleIntegerCase(dataType, function) \
if (dataType == ZGPointer) {\
	switch (searchData.dataSize) {\
		case sizeof(ZGMemoryAddress):\
			retValue = ZGSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint64_t *a, uint64_t *b) -> bool { return function(sd, a, b); }, processTask, static_cast<uint64_t *>(searchData.searchValue), searchData, delegate); \
			break;\
		case sizeof(ZG32BitMemoryAddress):\
			retValue = ZGSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint32_t *a, uint32_t *b) -> bool { return function(sd, a, b); }, processTask, static_cast<uint32_t *>(searchData.searchValue), searchData, delegate); \
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
	return ABS(*(static_cast<T *>(variableValue)) - *(static_cast<T *>(compareValue))) <= static_cast<T>(searchData->_epsilon);
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
		retValue = ZGSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, type *a, type *b) -> bool { return functionType(sd, a, b); }, processTask, static_cast<type *>(searchData.searchValue), searchData, delegate); \
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
			retValue = ZGSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b) -> bool { return ZGByteArrayWithWildcardsEquals(sd, a, b); }, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, delegate);
			break;
		case ZGNotEquals:
			retValue = ZGSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b) -> bool { return ZGByteArrayWithWildcardsNotEquals(sd, a, b); }, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, delegate);
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
			retValue = ZGSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b) -> bool { return ZGByteArrayNotEquals(sd, a, b); }, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, delegate);
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

typedef NSData *(^zg_narrow_search_for_data_helper_t)(size_t resultSetIndex, NSUInteger oldResultSetStartIndex, NSData * __unsafe_unretained oldResultSet);

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
					newResultSets[resultSetIndex] = helper(resultSetIndex, startIndex, oldResultSet);
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
		resultSets = [newResultSets zgFilterUsingBlock:^(NSMutableData *resultSet) {
			return static_cast<BOOL>(resultSet.length != 0);
		}];
	}
	
	return [[ZGSearchResults alloc] initWithResultSets:resultSets dataSize:dataSize pointerSize:pointerSize];
}

template <typename T, typename P, typename F>
void ZGNarrowSearchWithFunctionRegularCompare(ZGRegion * __unused *lastUsedSavedRegionReference, ZGRegion * __unsafe_unretained lastUsedRegion, P variableAddress, ZGMemorySize __unused dataSize, NSDictionary<NSNumber *, ZGRegion *> * __unused __unsafe_unretained savedPageToRegionTable, NSArray<ZGRegion *> * __unused __unsafe_unretained savedRegions, ZGMemorySize __unused pageSize, F comparisonFunction, P *memoryAddresses, ZGMemorySize &numberOfVariablesFound, ZGSearchData * __unsafe_unretained searchData, T *searchValue)
{
	T *currentValue = static_cast<T *>(static_cast<void *>(static_cast<uint8_t *>(lastUsedRegion->_bytes) + (variableAddress - lastUsedRegion->_address)));
	if (comparisonFunction(searchData, currentValue, searchValue))
	{
		memoryAddresses[numberOfVariablesFound] = variableAddress;
		numberOfVariablesFound++;
	}
}

template <typename T, typename P, typename F>
void ZGNarrowSearchWithFunctionStoredCompare(ZGRegion **lastUsedSavedRegionReference, ZGRegion * __unsafe_unretained lastUsedRegion, P variableAddress, ZGMemorySize dataSize, NSDictionary<NSNumber *, ZGRegion *> * __unsafe_unretained savedPageToRegionTable, NSArray<ZGRegion *> * __unsafe_unretained savedRegions, ZGMemorySize pageSize, F comparisonFunction, P *memoryAddresses, ZGMemorySize &numberOfVariablesFound, ZGSearchData * __unsafe_unretained searchData, T * __unused searchValue)
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

#define zg_define_compare_function(name) void (*name)(ZGRegion **, ZGRegion *, P, ZGMemorySize, NSDictionary<NSNumber *, ZGRegion *> *, NSArray<ZGRegion *> *, ZGMemorySize, F, P *, ZGMemorySize &, ZGSearchData *, T *)

template <typename T, typename P, typename F>
NSData *ZGNarrowSearchWithFunctionType(F comparisonFunction, ZGMemoryMap processTask, T *searchValue, ZGSearchData * __unsafe_unretained searchData, P __unused pointerSize, ZGMemorySize dataSize, NSUInteger oldResultSetStartIndex, NSData * __unsafe_unretained oldResultSet, NSDictionary<NSNumber *, ZGRegion *> * __unsafe_unretained pageToRegionTable, NSDictionary<NSNumber *, ZGRegion *> * __unsafe_unretained savedPageToRegionTable, NSArray<ZGRegion *> * __unsafe_unretained savedRegions, ZGMemorySize pageSize, zg_define_compare_function(compareHelperFunction))
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
	}
	
	if (lastUsedRegion != nil)
	{
		ZGFreeBytes(lastUsedRegion->_bytes, lastUsedRegion->_size);
	}
	
	return [NSData dataWithBytesNoCopy:memoryAddresses length:numberOfVariablesFound * sizeof(*memoryAddresses) freeWhenDone:YES];
}

template <typename T, typename F>
ZGSearchResults *ZGNarrowSearchWithFunction(F comparisonFunction, ZGMemoryMap processTask, T *searchValue, ZGSearchData * __unsafe_unretained searchData, id <ZGSearchProgressDelegate> delegate, ZGSearchResults * __unsafe_unretained firstSearchResults, ZGSearchResults * __unsafe_unretained laterSearchResults)
{
	ZGMemorySize pointerSize = searchData.pointerSize;
	ZGMemorySize dataSize = searchData.dataSize;
	BOOL shouldCompareStoredValues = searchData.shouldCompareStoredValues;
	
	ZGMemorySize pageSize = NSPageSize(); // sane default
	ZGPageSize(processTask, &pageSize);
	
	NSArray<ZGRegion *> *allRegions = [ZGRegion regionsFromProcessTask:processTask];
	
	return ZGNarrowSearchForDataHelper(searchData, delegate, firstSearchResults, laterSearchResults, ^NSData *(size_t resultSetIndex, NSUInteger oldResultSetStartIndex, NSData * __unsafe_unretained oldResultSet) {
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

			NSArray<ZGRegion *> *regions = ZGFilterRegions(allRegions, firstAddress, lastAddress, searchData.protectionMode);
			
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
				newResultSet = ZGNarrowSearchWithFunctionType(comparisonFunction, processTask, searchValue, searchData, static_cast<ZGMemoryAddress>(pointerSize), dataSize, oldResultSetStartIndex, oldResultSet, pageToRegionTable, nil, nil, pageSize, ZGNarrowSearchWithFunctionRegularCompare);
			}
			else
			{
				newResultSet = ZGNarrowSearchWithFunctionType(comparisonFunction, processTask, searchValue, searchData, static_cast<ZG32BitMemoryAddress>(pointerSize), dataSize, oldResultSetStartIndex, oldResultSet, pageToRegionTable, nil, nil, pageSize, ZGNarrowSearchWithFunctionRegularCompare);
			}
		}
		else
		{
			NSArray<ZGRegion *> *savedData = searchData.savedData.regions;
			
			NSMutableDictionary<NSNumber *, ZGRegion *> *pageToSavedRegionTable = nil;
			
			if (pageToRegionTable != nil)
			{
				pageToSavedRegionTable = [[NSMutableDictionary alloc] init];
				
				NSArray<ZGRegion *> *regions = ZGFilterRegions(savedData, firstAddress, lastAddress, searchData.protectionMode);
				
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
				newResultSet = ZGNarrowSearchWithFunctionType(comparisonFunction, processTask, searchValue, searchData, static_cast<ZGMemoryAddress>(pointerSize), dataSize, oldResultSetStartIndex, oldResultSet, pageToRegionTable, pageToSavedRegionTable, savedData, pageSize, ZGNarrowSearchWithFunctionStoredCompare);
			}
			else
			{
				newResultSet = ZGNarrowSearchWithFunctionType(comparisonFunction, processTask, searchValue, searchData, static_cast<ZG32BitMemoryAddress>(pointerSize), dataSize, oldResultSetStartIndex, oldResultSet, pageToRegionTable, pageToSavedRegionTable, savedData, pageSize, ZGNarrowSearchWithFunctionStoredCompare);
			}
		}
		
		return newResultSet;
	});
}

#pragma mark Narrowing Integers

#define ZGHandleNarrowIntegerType(functionType, type, integerQualifier, dataType, processTask, searchData, delegate, firstSearchResults, laterSearchResults) \
case dataType: \
if (integerQualifier == ZGSigned) \
	retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, type *a, type *b) -> bool { return functionType(sd, a, b); }, processTask, static_cast<type *>(searchData.searchValue), searchData, delegate, firstSearchResults, laterSearchResults); \
else \
	retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, u##type *a, u##type *b) -> bool { return functionType(sd, a, b); }, processTask, static_cast<u##type *>(searchData.searchValue), searchData, delegate, firstSearchResults, laterSearchResults); \
break

#define ZGHandleNarrowIntegerCase(dataType, function) \
if (dataType == ZGPointer) {\
	switch (searchData.dataSize) {\
		case sizeof(ZGMemoryAddress):\
			retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint64_t *a, uint64_t *b) -> bool { return function(sd, a, b); }, processTask, static_cast<uint64_t *>(searchData.searchValue), searchData, delegate, firstSearchResults, laterSearchResults); \
			break;\
		case sizeof(ZG32BitMemoryAddress):\
			retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint32_t *a, uint32_t *b) -> bool { return function(sd, a, b); }, processTask, static_cast<uint32_t *>(searchData.searchValue), searchData, delegate, firstSearchResults, laterSearchResults); \
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
		retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, type *a, type *b) -> bool { return functionType(sd, a, b); }, processTask, static_cast<type *>(searchData.searchValue), searchData, delegate, firstSearchResults, laterSearchResults);\
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
				retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b) -> bool { return ZGByteArrayWithWildcardsEquals(sd, a, b); }, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, delegate, firstSearchResults, laterSearchResults);
			}
			else
			{
				retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b) -> bool { return ZGByteArrayEquals(sd, a, b); }, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, delegate, firstSearchResults, laterSearchResults);
			}
			break;
		case ZGNotEquals:
			if (searchData.byteArrayFlags != NULL)
			{
				retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b) -> bool { return ZGByteArrayWithWildcardsNotEquals(sd, a, b); }, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, delegate, firstSearchResults, laterSearchResults);
			}
			else
			{
				retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b) -> bool { return ZGByteArrayNotEquals(sd, a, b); }, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, delegate, firstSearchResults, laterSearchResults);
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
					retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b) -> bool { return ZGString16FastSwappedEquals(sd, a, b); }, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, delegate, firstSearchResults, laterSearchResults);
				}
				else
				{
					retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b) -> bool { return ZGByteArrayEquals(sd, a, b); }, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, delegate, firstSearchResults, laterSearchResults);
				}
				break;
			case ZGNotEquals:
				if (dataType == ZGString16 && searchData.bytesSwapped)
				{
					retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b) -> bool { return ZGString16FastSwappedNotEquals(sd, a, b); }, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, delegate, firstSearchResults, laterSearchResults);
				}
				else
				{
					retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b) -> bool { return ZGByteArrayNotEquals(sd, a, b); }, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, delegate, firstSearchResults, laterSearchResults);
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
