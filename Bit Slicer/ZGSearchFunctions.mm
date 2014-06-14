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
#import <stdint.h>

#define MAX_NUMBER_OF_LOCAL_BUFFER_ADDRESSES 4096U

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
			if (comparisonFunction(searchData, (static_cast<T *>(bytes) + dataIndex / sizeof(T)), searchValue))
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
			if (comparisonFunction(searchData, (static_cast<T *>(bytes) + dataIndex / sizeof(T)), (static_cast<T *>(regionBytes) + dataIndex / sizeof(T))))
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
	T newCompareValue = static_cast<T>(searchData->_multiplicativeConstant * *compareValue + *(static_cast<T *>(searchData->_additiveConstant)));
	return ZGIntegerEquals(searchData, variableValue, &newCompareValue);
}

template <typename T>
bool ZGIntegerSwappedEqualsLinear(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T swappedCompareValue = ZGSwapBytes(*compareValue);
	T swappedVariableValue = ZGSwapBytes(*variableValue);
	T newCompareValue = static_cast<T>(searchData->_multiplicativeConstant * swappedCompareValue + *(static_cast<T *>(searchData->_additiveConstant)));
	
	return ZGIntegerEquals(searchData, &swappedVariableValue, &newCompareValue);
}

template <typename T>
bool ZGIntegerNotEqualsLinear(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T newCompareValue = static_cast<T>(searchData->_multiplicativeConstant * *compareValue + *(static_cast<T *>(searchData->_additiveConstant)));
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
	T newCompareValue = static_cast<T>(searchData->_multiplicativeConstant * *compareValue + *(static_cast<T *>(searchData->_additiveConstant)));
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
	T newCompareValue = static_cast<T>(searchData->_multiplicativeConstant * *compareValue + *(static_cast<T *>(searchData->_additiveConstant)));
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
	T newCompareValue = static_cast<T>(searchData->_multiplicativeConstant * *(static_cast<T *>(compareValue)) + *(static_cast<T *>(searchData->_additiveConstant)));
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
	T newCompareValue = static_cast<T>(searchData->_multiplicativeConstant * *(static_cast<T *>(compareValue)) + *(static_cast<T *>(searchData->_additiveConstant)));
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
	T newCompareValue = static_cast<T>(searchData->_multiplicativeConstant * *(static_cast<T *>(compareValue)) + *(static_cast<T *>(searchData->_additiveConstant)));
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
	T newCompareValue = static_cast<T>(searchData->_multiplicativeConstant * *(static_cast<T *>(compareValue)) + *(static_cast<T *>(searchData->_additiveConstant)));
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
bool ZGString16FastSwappedCaseInsensitiveEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T * __unused compareValue)
{
	return ZGString16CaseInsensitiveEquals(searchData, variableValue, static_cast<T *>(searchData->_swappedValue));
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
bool ZGString16FastSwappedCaseInsensitiveNotEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T * __unused compareValue)
{
	return ZGString16CaseInsensitiveNotEquals(searchData, variableValue, static_cast<T *>(searchData->_swappedValue));
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
				ZGHandleStringCase(dataType, ZGString8CaseInsensitiveEquals, ZGString16FastSwappedCaseInsensitiveEquals);
			}
			else
			{
				ZGHandleStringCase(dataType, ZGString8CaseInsensitiveEquals, ZGString16CaseInsensitiveEquals);
			}
			break;
		case ZGNotEquals:
			if (searchData.bytesSwapped)
			{
				ZGHandleStringCase(dataType, ZGString8CaseInsensitiveEquals, ZGString16FastSwappedCaseInsensitiveNotEquals);
			}
			else
			{
				ZGHandleStringCase(dataType, ZGString8CaseInsensitiveEquals, ZGString16CaseInsensitiveNotEquals);
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
				retValue = ZGSearchForCaseInsensitiveStrings(processTask, searchData, delegate, dataType, functionType);
				break;
			case ZGByteArray:
				retValue = ZGSearchForByteArraysWithWildcards(processTask, searchData, delegate, functionType);
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
	T *currentValue = (static_cast<T *>(lastUsedRegion->_bytes) + (variableAddress - lastUsedRegion->_address) / sizeof(T));
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
		T *currentValue = (static_cast<T *>(lastUsedRegion->_bytes) + (variableAddress - lastUsedRegion->_address) / sizeof(T));
		T *compareValue = static_cast<T *>((*lastUsedSavedRegionReference)->_bytes) + (variableAddress - (*lastUsedSavedRegionReference)->_address) / sizeof(T);
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
					ZGHandleNarrowStringCase(dataType, ZGString8CaseInsensitiveEquals, ZGString16FastSwappedCaseInsensitiveEquals);
				}
				else
				{
					ZGHandleNarrowStringCase(dataType, ZGString8CaseInsensitiveEquals, ZGString16CaseInsensitiveEquals);
				}
				break;
			case ZGNotEquals:
				if (searchData.bytesSwapped)
				{
					ZGHandleNarrowStringCase(dataType, ZGString8CaseInsensitiveNotEquals, ZGString16FastSwappedCaseInsensitiveNotEquals);
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
