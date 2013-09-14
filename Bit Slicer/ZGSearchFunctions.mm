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
#import <stdint.h>

// Fast string-searching function from HexFiend's framework
extern "C" unsigned char* boyer_moore_helper(const unsigned char *haystack, const unsigned char *needle, unsigned long haystack_length, unsigned long needle_length, const unsigned long *char_jump, const unsigned long *match_jump);

// This portion of code is mostly stripped from a function in Hex Fiend's framework; it's wicked fast.
void ZGPrepareBoyerMooreSearch(const unsigned char *needle, const unsigned long needle_length, const unsigned char *haystack, unsigned long haystack_length, unsigned long *char_jump, unsigned long *match_jump)
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
		char_jump[((unsigned char) needle[u])] = needle_length - u - 1;
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
	
	ub = backup[ua];
	while (ua <= needle_length)
	{
		while (ua <= ub)
		{
			if (match_jump[ua] > ub - ua + needle_length)
			{
				match_jump[ua] = ub - ua + needle_length;
			}
			ua++;
		}
		ub = backup[ub];
	}
}

ZGSearchResults *ZGSearchForDataHelper(ZGMemoryMap processTask, ZGSearchData *searchData, ZGSearchProgress *searchProgress, zg_search_for_data_helper_t helper)
{
	ZGMemorySize dataAlignment = searchData.dataAlignment;
	ZGMemorySize dataSize = searchData.dataSize;
	ZGMemorySize pointerSize = searchData.pointerSize;
	
	BOOL shouldCompareStoredValues = searchData.shouldCompareStoredValues;
	
	ZGMemoryAddress dataBeginAddress = searchData.beginAddress;
	ZGMemoryAddress dataEndAddress = searchData.endAddress;
	BOOL shouldScanUnwritableValues = searchData.shouldScanUnwritableValues;
	
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
				
				if (!searchProgress.shouldCancelSearch && ZGReadBytes(processTask, address, (void **)&bytes, &size))
				{
					helper(dataIndex, address, size, resultSet, bytes, regionBytes);
					
					ZGFreeBytes(processTask, bytes, size);
				}
			}
			
			dispatch_async(dispatch_get_main_queue(), ^{
				searchProgress.numberOfVariablesFound += resultSet.length / pointerSize;
				searchProgress.progress++;
			});
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
		resultSets = [allResultSets zgFilterUsingBlock:(zg_array_filter_t)^(NSMutableData *resultSet) {
			return resultSet.length == 0;
		}];
	}
	
	return [[ZGSearchResults alloc] initWithResultSets:resultSets dataSize:dataSize pointerSize:pointerSize];
}

#define ADD_VARIABLE_ADDRESS(addressExpression, pointerSize, resultSet) \
switch (pointerSize) \
{ \
case sizeof(ZGMemoryAddress): \
	{ \
		ZGMemoryAddress memoryAddress = (addressExpression); \
		[resultSet appendBytes:&memoryAddress length:sizeof(memoryAddress)]; \
		break; \
	} \
case sizeof(ZG32BitMemoryAddress): \
	{ \
		ZG32BitMemoryAddress memoryAddress = (ZG32BitMemoryAddress)(addressExpression); \
		[resultSet appendBytes:&memoryAddress length:sizeof(memoryAddress)]; \
		break; \
	} \
}

ZGSearchResults *ZGSearchForBytes(ZGMemoryMap processTask, ZGSearchData *searchData, ZGSearchProgress *searchProgress)
{
	const unsigned long dataSize = searchData.dataSize;
	const unsigned char *searchValue = (const unsigned char *)searchData.searchValue;
	ZGMemorySize pointerSize = searchData.pointerSize;
	
	return ZGSearchForDataHelper(processTask, searchData, searchProgress, ^(ZGMemorySize dataIndex, ZGMemoryAddress address, ZGMemorySize size, NSMutableData * __unsafe_unretained resultSet, void *bytes, void *regionBytes) {
		// generate the two Boyer-Moore auxiliary buffers
		unsigned long charJump[UCHAR_MAX + 1] = {0};
		unsigned long *matchJump = (unsigned long *)malloc(2 * (dataSize + 1) * sizeof(*matchJump));
		
		ZGPrepareBoyerMooreSearch(searchValue, dataSize, (const unsigned char *)bytes, size, charJump, matchJump);
		
		unsigned char *foundSubstring = (unsigned char *)bytes;
		unsigned long haystackLengthLeft = size;
		
		while (haystackLengthLeft >= dataSize)
		{
			foundSubstring = boyer_moore_helper((const unsigned char *)foundSubstring, searchValue, haystackLengthLeft, (unsigned long)dataSize, (const unsigned long *)charJump, (const unsigned long *)matchJump);
			if (foundSubstring == NULL) break;
			
			ADD_VARIABLE_ADDRESS(foundSubstring - (unsigned char *)bytes + address, pointerSize, resultSet);
			
			foundSubstring++;
			haystackLengthLeft = (unsigned char *)bytes + size - foundSubstring;
		}
		
		free(matchJump);
	});
}

template <typename T>
bool ZGIntegerEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return *variableValue == *compareValue;
}

template <typename T>
bool ZGIntegerNotEquals(ZGSearchData * __unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return !ZGIntegerEquals(searchData, variableValue, compareValue);
}

template <typename T>
bool ZGIntegerGreaterThan(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return (*variableValue > *compareValue) && (searchData->_rangeValue == NULL || *variableValue < *(T *)(searchData->_rangeValue));
}

template <typename T>
bool ZGIntegerLesserThan(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return (*variableValue < *compareValue) && (searchData->_rangeValue == NULL || *variableValue > *(T *)(searchData->_rangeValue));
}

template <typename T>
bool ZGIntegerEqualsPlus(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T newCompareValue = *((T *)compareValue) + *((T *)searchData->_compareOffset);
	return ZGIntegerEquals(searchData, variableValue, &newCompareValue);
}

template <typename T>
bool ZGIntegerNotEqualsPlus(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T newCompareValue = *compareValue + *((T *)searchData->_compareOffset);
	return ZGIntegerNotEquals(searchData, variableValue, &newCompareValue);
}

#define ZGSearchWithFunctionHelper(compareValueExpression) \
while (dataIndex <= endLimit) { \
	if (comparisonFunction(searchData, (T *)((int8_t *)bytes + dataIndex), (compareValueExpression))) { \
		ADD_VARIABLE_ADDRESS(address + dataIndex, pointerSize, resultSet); \
	}\
	dataIndex += dataAlignment; \
}

template <typename T>
ZGSearchResults *ZGSearchWithFunction(bool (*comparisonFunction)(ZGSearchData *, T *, T *), ZGMemoryMap processTask, T *searchValue, ZGSearchData * __unsafe_unretained searchData, ZGSearchProgress * __unsafe_unretained searchProgress)
{
	ZGMemorySize dataAlignment = searchData.dataAlignment;
	ZGMemorySize pointerSize = searchData.pointerSize;
	ZGMemorySize dataSize = searchData.dataSize;
	BOOL shouldCompareStoredValues = searchData.shouldCompareStoredValues;
	
	return ZGSearchForDataHelper(processTask, searchData, searchProgress, ^(ZGMemorySize dataIndex, ZGMemoryAddress address, ZGMemorySize size, NSMutableData * __unsafe_unretained resultSet, void *bytes, void *regionBytes) {
		ZGMemorySize endLimit = size - dataSize;
		
		if (!shouldCompareStoredValues)
		{
			ZGSearchWithFunctionHelper(searchValue);
		}
		else
		{
			ZGSearchWithFunctionHelper((T *)((int8_t *)regionBytes + dataIndex));
		}
	});
}

#define ZGHandleIntegerType(functionType, type, integerQualifier, dataType, processTask, searchData, searchProgress) \
	case dataType: \
		if (integerQualifier == ZGSigned) \
			retValue = ZGSearchWithFunction(functionType, processTask, (type *)searchData.searchValue, searchData, searchProgress); \
		else \
			retValue = ZGSearchWithFunction(functionType, processTask, (u##type *)searchData.searchValue, searchData, searchProgress); \
		break

#define ZGHandleIntegerCase(dataType, function) \
if (dataType == ZGPointer) {\
	switch (searchData.dataSize) {\
		case sizeof(ZGMemoryAddress):\
			retValue = ZGSearchWithFunction(function, processTask, (uint64_t *)searchData.searchValue, searchData, searchProgress);\
			break;\
		case sizeof(ZG32BitMemoryAddress):\
			retValue = ZGSearchWithFunction(function, processTask, (uint32_t *)searchData.searchValue, searchData, searchProgress);\
			break;\
	}\
}\
else {\
	switch (dataType) {\
		ZGHandleIntegerType(function, int8_t, integerQualifier, ZGInt8, processTask, searchData, searchProgress);\
		ZGHandleIntegerType(function, int16_t, integerQualifier, ZGInt16, processTask, searchData, searchProgress);\
		ZGHandleIntegerType(function, int32_t, integerQualifier, ZGInt32, processTask, searchData, searchProgress);\
		ZGHandleIntegerType(function, int64_t, integerQualifier, ZGInt64, processTask, searchData, searchProgress);\
		default: break;\
	}\
}\

ZGSearchResults *ZGSearchForIntegers(ZGMemoryMap processTask, ZGSearchData *searchData, ZGSearchProgress *searchProgress, ZGVariableType dataType, ZGVariableQualifier integerQualifier, ZGFunctionType functionType)
{
	id retValue = nil;
	
	switch (functionType)
	{
		case ZGEquals:
		case ZGEqualsStored:
			ZGHandleIntegerCase(dataType, ZGIntegerEquals);
			break;
		case ZGNotEquals:
		case ZGNotEqualsStored:
			ZGHandleIntegerCase(dataType, ZGIntegerNotEquals);
			break;
		case ZGGreaterThan:
		case ZGGreaterThanStored:
			ZGHandleIntegerCase(dataType, ZGIntegerGreaterThan);
			break;
		case ZGLessThan:
		case ZGLessThanStored:
			ZGHandleIntegerCase(dataType, ZGIntegerLesserThan);
			break;
		case ZGEqualsStoredPlus:
			ZGHandleIntegerCase(dataType, ZGIntegerEqualsPlus);
			break;
		case ZGNotEqualsStoredPlus:
			ZGHandleIntegerCase(dataType, ZGIntegerNotEqualsPlus);
			break;
		case ZGStoreAllValues:
			break;
	}
	
	return retValue;
}

template <typename T>
bool ZGFloatingPointEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return ABS(*((T *)variableValue) - *((T *)compareValue)) <= searchData->_epsilon;
}

template <typename T>
bool ZGFloatingPointNotEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return !ZGFloatingPointEquals(searchData, variableValue, compareValue);
}

template <typename T>
bool ZGFloatingPointGreaterThan(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return *variableValue > *compareValue && (searchData->_rangeValue == NULL || *variableValue < *(T *)(searchData->_rangeValue));
}

template <typename T>
bool ZGFloatingPointLesserThan(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return *variableValue < *compareValue && (searchData->_rangeValue == NULL || *variableValue > *(T *)(searchData->_rangeValue));
}

template <typename T>
bool ZGFloatingPointEqualsPlus(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T newCompareValue = *((T *)compareValue) + *((T *)searchData->_compareOffset);
	return ZGFloatingPointEquals(searchData, variableValue, &newCompareValue);
}

template <typename T>
bool ZGFloatingPointNotEqualsPlus(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	T newCompareValue = *((T *)compareValue) + *((T *)searchData->_compareOffset);
	return ZGFloatingPointNotEquals(searchData, variableValue, &newCompareValue);
}

#define ZGHandleType(functionType, type, dataType, processTask, searchData, searchProgress) \
	case dataType: \
		retValue = ZGSearchWithFunction(functionType, processTask, (type *)searchData.searchValue, searchData, searchProgress); \
	break

#define ZGHandleFloatingPointCase(case, function) \
switch (case) {\
	ZGHandleType(function, float, ZGFloat, processTask, searchData, searchProgress);\
	ZGHandleType(function, double, ZGDouble, processTask, searchData, searchProgress);\
	default: break;\
}

ZGSearchResults *ZGSearchForFloatingPoints(ZGMemoryMap processTask, ZGSearchData *searchData, ZGSearchProgress *searchProgress, ZGVariableType dataType, ZGFunctionType functionType)
{
	id retValue = nil;
	
	switch (functionType)
	{
		case ZGEquals:
		case ZGEqualsStored:
			ZGHandleFloatingPointCase(dataType, ZGFloatingPointEquals);
			break;
		case ZGNotEquals:
		case ZGNotEqualsStored:
			ZGHandleFloatingPointCase(dataType, ZGFloatingPointNotEquals);
			break;
		case ZGGreaterThan:
		case ZGGreaterThanStored:
			ZGHandleFloatingPointCase(dataType, ZGFloatingPointGreaterThan);
			break;
		case ZGLessThan:
		case ZGLessThanStored:
			ZGHandleFloatingPointCase(dataType, ZGFloatingPointLesserThan);
			break;
		case ZGEqualsStoredPlus:
			ZGHandleFloatingPointCase(dataType, ZGFloatingPointEqualsPlus);
			break;
		case ZGNotEqualsStoredPlus:
			ZGHandleFloatingPointCase(dataType, ZGFloatingPointNotEqualsPlus);
			break;
		case ZGStoreAllValues:
			break;
	}
	
	return retValue;
}

template <typename T>
bool ZGString8CaseInsensitiveEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return strncasecmp(variableValue, compareValue, searchData->_dataSize) == 0;
}

template <typename T>
bool ZGString16CaseInsensitiveEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	Boolean isEqual = false;
	UCCompareText(searchData->_collator, variableValue, ((size_t)searchData->_dataSize) / sizeof(T), compareValue, ((size_t)searchData->_dataSize) / sizeof(T), (Boolean *)&isEqual, NULL);
	return isEqual;
}

template <typename T>
bool ZGString8CaseInsensitiveNotEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return !ZGString8CaseInsensitiveEquals(searchData, variableValue, compareValue);
}

template <typename T>
bool ZGString16CaseInsensitiveNotEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	return !ZGString16CaseInsensitiveEquals(searchData, variableValue, compareValue);
}

#define ZGHandleStringCase(case, function1, function2) \
	switch (case) {\
		ZGHandleType(function1, char, ZGString8, processTask, searchData, searchProgress);\
		ZGHandleType(function2, unichar, ZGString16, processTask, searchData, searchProgress);\
		default: break;\
	}\

ZGSearchResults *ZGSearchForCaseInsensitiveStrings(ZGMemoryMap processTask, ZGSearchData *searchData, ZGSearchProgress *searchProgress, ZGVariableType dataType, ZGFunctionType functionType)
{
	id retValue = nil;
	
	switch (functionType)
	{
		case ZGEquals:
			ZGHandleStringCase(dataType, ZGString8CaseInsensitiveEquals, ZGString16CaseInsensitiveEquals);
			break;
		case ZGNotEquals:
			ZGHandleStringCase(dataType, ZGString8CaseInsensitiveNotEquals, ZGString16CaseInsensitiveNotEquals);
			break;
		default:
			break;
	}
	
	return retValue;
}

template <typename T>
bool ZGByteArrayWithWildcardsEquals(ZGSearchData *__unsafe_unretained searchData, T *variableValue, T *compareValue)
{
	const unsigned char *variableValueArray = (const unsigned char *)variableValue;
	const unsigned char *compareValueArray = (const unsigned char *)compareValue;
	
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
	return !ZGByteArrayWithWildcardsEquals(searchData, (void *)variableValue, (void *)compareValue);
}

ZGSearchResults *ZGSearchForByteArraysWithWildcards(ZGMemoryMap processTask, ZGSearchData *searchData, ZGSearchProgress *searchProgress, ZGVariableType dataType, ZGFunctionType functionType)
{
	id retValue = nil;
	
	switch (functionType)
	{
		case ZGEquals:
			retValue = ZGSearchWithFunction(ZGByteArrayWithWildcardsEquals, processTask, searchData.searchValue, searchData, searchProgress);
			break;
		case ZGNotEquals:
			retValue = ZGSearchWithFunction(ZGByteArrayWithWildcardsNotEquals, processTask, searchData.searchValue, searchData, searchProgress);
			break;
		default:
			break;
	}
	
	return retValue;
}

ZGSearchResults *ZGSearchForData(ZGMemoryMap processTask, ZGSearchData *searchData, ZGSearchProgress *searchProgress, ZGVariableType dataType, ZGVariableQualifier integerQualifier, ZGFunctionType functionType)
{
	id retValue = nil;
	if (searchData.shouldUseBoyerMoore)
	{
		retValue = ZGSearchForBytes(processTask, searchData, searchProgress);
	}
	else if ([@[@(ZGInt8), @(ZGInt16), @(ZGInt32), @(ZGInt64), @(ZGPointer)] containsObject:@(dataType)])
	{
		retValue = ZGSearchForIntegers(processTask, searchData, searchProgress, dataType, integerQualifier, functionType);
	}
	else if ([@[@(ZGFloat), @(ZGDouble)] containsObject:@(dataType)])
	{
		retValue = ZGSearchForFloatingPoints(processTask, searchData, searchProgress, dataType, functionType);
	}
	else if ([@[@(ZGString8), @(ZGString16)] containsObject:@(dataType)])
	{
		retValue = ZGSearchForCaseInsensitiveStrings(processTask, searchData, searchProgress, dataType, functionType);
	}
	else if (dataType == ZGByteArray)
	{
		retValue = ZGSearchForByteArraysWithWildcards(processTask, searchData, searchProgress, dataType, functionType);
	}
	return retValue;
}

ZGSearchResults *ZGNarrowSearchForData(ZGMemoryMap processTask, ZGSearchData *searchData, ZGSearchProgress *searchProgress, comparison_function_t comparisonFunction, ZGSearchResults *firstSearchResults, ZGSearchResults *laterSearchResults)
{
	ZGMemorySize dataSize = searchData.dataSize;
	void *searchValue = searchData.searchValue;
	
	ZGMemorySize pointerSize = searchData.pointerSize;
	
	ZGMemoryAddress beginningAddress = searchData.beginAddress;
	ZGMemoryAddress endingAddress = searchData.endAddress;
	
	// Get all relevant regions
	NSArray *regions = [ZGRegionsForProcessTask(processTask) zgFilterUsingBlock:(zg_array_filter_t)^(ZGRegion *region) {
		return !(region.address < endingAddress && region.address + region.size > beginningAddress && region.protection & VM_PROT_READ && (searchData.shouldScanUnwritableValues || (region.protection & VM_PROT_WRITE)));
	}];
	
	ZGMemorySize maxProgress = firstSearchResults.addressCount + laterSearchResults.addressCount;
	
	dispatch_async(dispatch_get_main_queue(), ^{
		searchProgress.initiatedSearch = YES;
		searchProgress.progressType = ZGSearchProgressMemoryScanning;
		searchProgress.maxProgress = maxProgress;
	});
	
	NSMutableData *newResultsData = [[NSMutableData alloc] init];
	
	__block ZGRegion *lastUsedRegion = nil;
	__block ZGRegion *lastUsedSavedRegion = nil;
	
	__block NSUInteger numberOfVariablesFound = 0;
	__block ZGMemorySize currentProgress = 0;
	
	// We'll update the progress at 5% intervals during our search
	ZGMemorySize numberOfVariablesRequiredToUpdateProgress = (ZGMemorySize)(maxProgress * 0.05);
	
	BOOL shouldCompareStoredValues = searchData.shouldCompareStoredValues;
	
	void (^compareAndAddValue)(ZGMemoryAddress)  = ^(ZGMemoryAddress variableAddress) {
		void *compareValue = shouldCompareStoredValues ? ZGSavedValue(variableAddress, searchData, &lastUsedSavedRegion, dataSize) : searchValue;
		if (compareValue && comparisonFunction(searchData, (char *)lastUsedRegion->_bytes + (variableAddress - lastUsedRegion->_address), compareValue, dataSize))
		{
			ADD_VARIABLE_ADDRESS(variableAddress, pointerSize, newResultsData);
			numberOfVariablesFound++;
		}
	};
	
	void (^searchVariableAddress)(ZGMemoryAddress, BOOL *) = ^(ZGMemoryAddress variableAddress, BOOL *stop) {
		if (beginningAddress <= variableAddress && endingAddress >= variableAddress + dataSize)
		{
			// Check if the variable is in the last region we scanned
			if (lastUsedRegion && variableAddress >= lastUsedRegion->_address && variableAddress + dataSize <= lastUsedRegion->_address + lastUsedRegion->_size)
			{
				compareAndAddValue(variableAddress);
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
						compareAndAddValue(variableAddress);
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
	
	__block BOOL shouldStopFirstIteration = NO;
	[firstSearchResults enumerateUsingBlock:^(ZGMemoryAddress variableAddress, BOOL *stop) {
		searchVariableAddress(variableAddress, &shouldStopFirstIteration);
		if (shouldStopFirstIteration)
		{
			*stop = shouldStopFirstIteration;
		}
	}];
	
	if (!shouldStopFirstIteration && laterSearchResults.addressCount > 0)
	{
		__block BOOL shouldStopSecondIteration = NO;
		[laterSearchResults enumerateUsingBlock:^(ZGMemoryAddress variableAddress, BOOL *stop) {
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
		// Deallocate results into separate queue since this could take some time
		__block id oldResultSets = newResultsData;
		newResultsData = [NSData data];
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			oldResultSets = nil;
		});
	}
	
	return [[ZGSearchResults alloc] initWithResultSets:@[newResultsData] dataSize:dataSize pointerSize:pointerSize];
}
