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
#import <limits>
#import <os/lock.h>

@interface ZGSearchProgressNotifier : NSObject

@property (nonatomic, readonly) ZGSearchProgress *searchProgress;

@end

@implementation ZGSearchProgressNotifier
{
	ZGSearchProgress *_searchProgress;
	ZGVariableType _dataType;
	ZGMemorySize _stride;
	ZGSearchResultType _resultType;
	
	NSArray<NSNumber *> *_headerAddresses;
	
	NSMutableArray<NSData *> *_resultSets;
	NSMutableArray<NSData *> *_staticMainExecutableResultSets;
	NSMutableArray<NSData *> *_staticOtherLibraryResultSets;
	
	os_unfair_lock _lock;
	dispatch_source_t _notifyTimer;
	id<ZGSearchProgressDelegate> _delegate;
	
	BOOL _notifiesStaticResults;
}

static NSUInteger ZGLengthForResultSets(NSArray<NSData *> *resultSets)
{
	NSUInteger length = 0;
	for (NSData *resultSet in resultSets)
	{
		length += resultSet.length;
	}
	return length;
}

static ZGMemorySize ZGPageSizeForRegionAlignment(ZGMemoryMap processTask, BOOL translated)
{
	ZGMemorySize computedPageSize = NSPageSize(); // sane default
	ZGPageSize(processTask, &computedPageSize);
	
	ZGMemorySize pageSize;
	if (translated)
	{
		// ZGPageSize() can get us the wrong page size for VM region alignment for Rosetta processes
		// Hardcode a safe minimum x86 constant in this case
		// Note this does not need to be accurate, since this returned page size is used for optimization purposes
		// The page size needs to meet the "minimum" boundary however
		const ZGMemorySize x86PageSize = 4096;
		pageSize = (computedPageSize < x86PageSize) ? computedPageSize : x86PageSize;
	}
	else
	{
		pageSize = computedPageSize;
	}
	return pageSize;
}

- (instancetype)initWithSearchProgress:(ZGSearchProgress *)searchProgress resultType:(ZGSearchResultType)resultType dataType:(ZGVariableType)dataType stride:(ZGMemorySize)stride notifiesStaticResults:(BOOL)notifiesStaticResults headerAddresses:(NSArray<NSNumber *> *)headerAddresses delegate:(id<ZGSearchProgressDelegate>)delegate
{
	self = [super init];
	if (self != nil)
	{
		_searchProgress = searchProgress;
		_dataType = dataType;
		_stride = stride;
		_resultType = resultType;
		_notifiesStaticResults = notifiesStaticResults;
		
		_headerAddresses = headerAddresses;
		
		_resultSets = [NSMutableArray array];
		_staticMainExecutableResultSets = _notifiesStaticResults ? [NSMutableArray array] : nil;
		_staticOtherLibraryResultSets = _notifiesStaticResults ? [NSMutableArray array] : nil;
		_lock = OS_UNFAIR_LOCK_INIT;
		
		_delegate = delegate;
		_notifyTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
		
		uint64_t interval = static_cast<uint64_t>(0.05 * NSEC_PER_SEC);
		dispatch_time_t start = dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(interval));
		dispatch_source_set_timer(_notifyTimer, start, interval, interval / 2);
		
		dispatch_source_set_event_handler(_notifyTimer, ^{
			[self _notifyProgress];
		});
	}
	return self;
}

- (void)start
{
	if (_delegate == nil)
	{
		return;
	}
	
	dispatch_async(dispatch_get_main_queue(), ^{
		[self->_delegate progressWillBegin:self->_searchProgress];
	});
	
	dispatch_resume(_notifyTimer);
}

- (void)stop
{
	if (_delegate == nil)
	{
		return;
	}
	
	dispatch_source_cancel(_notifyTimer);
	
	dispatch_async(dispatch_get_main_queue(), ^{
		[self _notifyProgress];
	});
}

- (void)_notifyProgress
{
	NSArray<NSData *> *resultSets;
	NSArray<NSData *> *staticMainExecutableResultSets;
	NSArray<NSData *> *staticOtherLibraryResultSets;
	
	os_unfair_lock_lock(&self->_lock);
	
	resultSets = [self->_resultSets copy];
	
	if (_notifiesStaticResults)
	{
		staticMainExecutableResultSets = [self->_staticMainExecutableResultSets copy];
		staticOtherLibraryResultSets = [self->_staticOtherLibraryResultSets copy];
	}
	
	[_resultSets removeAllObjects];
	
	if (_notifiesStaticResults)
	{
		[_staticMainExecutableResultSets removeAllObjects];
		[_staticOtherLibraryResultSets removeAllObjects];
	}
	
	os_unfair_lock_unlock(&self->_lock);
	
	NSUInteger resultSetsCount = resultSets.count;
	if (resultSetsCount > 0)
	{
		NSUInteger resultSetsLength = ZGLengthForResultSets(resultSets);
		NSUInteger staticMainExecutableResultSetsLength = _notifiesStaticResults ? ZGLengthForResultSets(staticMainExecutableResultSets) : 0;
		NSUInteger staticOtherLibraryResultSetsLength = _notifiesStaticResults ? ZGLengthForResultSets(staticOtherLibraryResultSets) : 0;
		
		_searchProgress.numberOfVariablesFound += (resultSetsLength + staticMainExecutableResultSetsLength + staticOtherLibraryResultSetsLength) / self->_stride;
		
		_searchProgress.progress += resultSets.count;
		
		BOOL reportedProgress = NO;
		if (staticMainExecutableResultSetsLength > 0)
		{
			[self->_delegate progress:_searchProgress advancedWithResultSets:staticMainExecutableResultSets totalResultSetLength:staticMainExecutableResultSetsLength resultType:_resultType dataType:_dataType addressType:ZGSearchResultAddressTypeStaticMainExecutable stride:_stride headerAddresses:_headerAddresses];
			reportedProgress = YES;
		}
		
		if (staticOtherLibraryResultSetsLength > 0)
		{
			[self->_delegate progress:_searchProgress advancedWithResultSets:staticOtherLibraryResultSets totalResultSetLength:staticOtherLibraryResultSetsLength resultType:_resultType dataType:_dataType addressType:ZGSearchResultAddressTypeStaticOtherLibrary stride:_stride headerAddresses:_headerAddresses];
			reportedProgress = YES;
		}
		
		if (resultSetsLength > 0 || !reportedProgress)
		{
			[self->_delegate progress:_searchProgress advancedWithResultSets:resultSets totalResultSetLength:resultSetsLength resultType:_resultType dataType:_dataType addressType:ZGSearchResultAddressTypeRegular stride:_stride headerAddresses:_headerAddresses];
		}
	}
}

- (void)addResultSet:(NSData *)resultSet staticMainExecutableResultSet:(NSData *)staticMainExecutableResultSet staticOtherLibraryResultSet:(NSData *)staticOtherLibraryResultSet
{
	if (_delegate == nil)
	{
		return;
	}
	
	os_unfair_lock_lock(&_lock);
	
	[_resultSets addObject:resultSet];
	
	if (_notifiesStaticResults)
	{
		[_staticMainExecutableResultSets addObject:staticMainExecutableResultSet];
		[_staticOtherLibraryResultSets addObject:staticOtherLibraryResultSet];
	}
	
	os_unfair_lock_unlock(&_lock);
}

@end

#define INITIAL_BUFFER_ADDRESSES_CAPACITY 4096U
#define REALLOCATION_GROWTH_RATE 1.5f

template <typename T>
bool ZGByteArrayNotEquals(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T *__restrict__ extraStorage);

struct ZGPointerValueEntry
{
	ZGMemoryAddress pointerValue;
	ZGMemoryAddress address;
};

struct ZGRegionValue
{
	ZGMemoryAddress address;
	ZGMemorySize size;
	void *bytes;
};

enum ZGPointerComparisonResult
{
	ZGPointerComparisonResultAscending,
	ZGPointerComparisonResultEqual,
	ZGPointerComparisonResultDescending
};

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

typedef NSData *(^zg_search_for_data_helper_t)(ZGMemorySize dataIndex, ZGMemoryAddress address, ZGMemorySize size, void *bytes, void *regionBytes, void *extraStorage);

ZGSearchResults *ZGSearchForDataHelper(ZGMemoryMap processTask, ZGSearchData *searchData, ZGVariableType resultDataType, ZGMemorySize stride, BOOL unalignedAccesses, BOOL usesExtraStorage, id <ZGSearchProgressDelegate> delegate, zg_search_for_data_helper_t helper)
{
	ZGMemorySize dataAlignment = searchData.dataAlignment;
	ZGMemorySize dataSize = searchData.dataSize;
	
	BOOL shouldCompareStoredValues = searchData.shouldCompareStoredValues;
	
	ZGMemoryAddress dataBeginAddress = searchData.beginAddress;
	ZGMemoryAddress dataEndAddress = searchData.endAddress;
	
	NSArray<ZGRegion *> *regions;
	if (!shouldCompareStoredValues)
	{
		BOOL includeSharedMemory = searchData.includeSharedMemory;
		
		NSArray<ZGRegion *> *nonFilteredRegions = includeSharedMemory ? [ZGRegion submapRegionsFromProcessTask:processTask] :  [ZGRegion regionsWithExtendedInfoFromProcessTask:processTask];
		
		BOOL filterHeapAndStackData = searchData.filterHeapAndStackData;
		NSArray<NSValue *> *totalStaticSegmentRanges = searchData.totalStaticSegmentRanges;
		
		BOOL excludeStaticDataFromSystemLibraries = searchData.excludeStaticDataFromSystemLibraries;
		NSArray<NSString *> *filePaths = searchData.filePaths;
		
		regions = [ZGRegion regionsFilteredFromRegions:nonFilteredRegions beginAddress:dataBeginAddress endAddress:dataEndAddress protectionMode:searchData.protectionMode includeSharedMemory:includeSharedMemory filterHeapAndStackData:filterHeapAndStackData totalStaticSegmentRanges:totalStaticSegmentRanges excludeStaticDataFromSystemLibraries:excludeStaticDataFromSystemLibraries filePaths:filePaths];
	}
	else
	{
		regions = searchData.savedData.regions;
	}
	
	ZGSearchProgress *searchProgress = [[ZGSearchProgress alloc] initWithProgressType:ZGSearchProgressMemoryScanning maxProgress:regions.count];
	
	ZGSearchProgressNotifier *progressNotifier = [[ZGSearchProgressNotifier alloc] initWithSearchProgress:searchProgress resultType:ZGSearchResultTypeDirect dataType:resultDataType stride:stride notifiesStaticResults:NO headerAddresses:nil delegate:delegate];
	
	[progressNotifier start];
	
	const void **allResultSets = static_cast<const void **>(calloc(regions.count, sizeof(*allResultSets)));
	assert(allResultSets != NULL);
	
	dispatch_queue_attr_t qosAttribute = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT, QOS_CLASS_USER_INITIATED, 0);
	dispatch_queue_t queue = dispatch_queue_create("com.zgcoder.BitSlicer.ValueSearch", qosAttribute);
	
	dispatch_apply(regions.count, queue, ^(size_t regionIndex) {
		@autoreleasepool
		{
			ZGRegion *region = [regions objectAtIndex:regionIndex];
			ZGMemoryAddress address = region.address;
			ZGMemorySize size = region.size;
			void *regionBytes = region.bytes;
			
			NSData *results = nil;
			
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
					
					results = helper(dataIndex, address, size, bytes, regionBytes, extraStorage);
					allResultSets[regionIndex] = CFBridgingRetain(results);
					
					free(extraStorage);
					ZGFreeBytes(bytes, size);
				}
			}
			
			[progressNotifier addResultSet:results != nil ? results : NSData.data staticMainExecutableResultSet:nil staticOtherLibraryResultSet:nil];
		}
	});
	
	[progressNotifier stop];
	
	NSArray<NSData *> *resultSets;
	
	if (searchProgress.shouldCancelSearch)
	{
		resultSets = [NSArray array];
		
		// Deallocate results into separate queue since this could take some time
		dispatch_async(queue, ^{
			for (NSUInteger resultSetIndex = 0; resultSetIndex < regions.count; resultSetIndex++)
			{
				const void *resultSetData = allResultSets[resultSetIndex];
				if (resultSetData != nullptr)
				{
					CFRelease(resultSetData);
				}
			}
			
			free(allResultSets);
		});
	}
	else
	{
		NSMutableArray<NSData *> *filteredResultSets = [NSMutableArray array];
		for (NSUInteger resultSetIndex = 0; resultSetIndex < regions.count; resultSetIndex++)
		{
			const void *resultSetData = allResultSets[resultSetIndex];
			if (resultSetData != nullptr)
			{
				NSData *resultSetObjCData = static_cast<NSData *>(CFBridgingRelease(resultSetData));
				
				if (resultSetObjCData.length != 0)
				{
					[filteredResultSets addObject:resultSetObjCData];
				}
			}
		}
		
		free(allResultSets);
		
		resultSets = [filteredResultSets copy];
	}
	
	return [[ZGSearchResults alloc] initWithResultSets:resultSets resultType:ZGSearchResultTypeDirect dataType:resultDataType stride:stride unalignedAccess:unalignedAccesses];
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

template <typename T, typename P, typename F, typename C>
NSData *ZGSearchWithFunctionHelperRegularAndStoreValueDifference(T *searchValue, F comparisonFunction, C transferBytes, ZGSearchData * __unsafe_unretained searchData, ZGMemorySize dataIndex, ZGMemorySize dataAlignment, ZGMemorySize dataSize, ZGMemorySize endLimit, ZGMemoryAddress address, void *bytes, void *extraStorage)
{
	size_t capacity = INITIAL_BUFFER_ADDRESSES_CAPACITY;
	size_t resultSize = sizeof(P) + sizeof(uint16_t);
	uint8_t *results = static_cast<uint8_t *>(malloc(capacity * resultSize));
	ZGMemorySize numberOfVariablesFound = 0;
	
	while (dataIndex <= endLimit)
	{
		if (numberOfVariablesFound == capacity)
		{
			capacity = static_cast<size_t>(capacity * REALLOCATION_GROWTH_RATE);
			results = static_cast<uint8_t *>(realloc(results, capacity * resultSize));
		}
		
		ZGMemorySize numberOfStepsToTake = MIN(capacity - numberOfVariablesFound, (endLimit + dataAlignment - dataIndex) / dataAlignment);
		for (ZGMemorySize stepIndex = 0; stepIndex < numberOfStepsToTake; stepIndex++)
		{
			T *variableValue = static_cast<T *>(transferBytes(static_cast<uint8_t *>(bytes) + dataIndex, extraStorage, dataSize));
			
			if (comparisonFunction(searchData, variableValue, searchValue, static_cast<T *>(extraStorage)))
			{
				P resultAddress = static_cast<P>(address + dataIndex);
				memcpy(results + numberOfVariablesFound * resultSize, &resultAddress, sizeof(P));
				
				T theVariableValue = *(static_cast<T *>(variableValue));
				T theCompareValue = *(static_cast<T *>(searchValue));
				
				uint16_t valueDifference = static_cast<uint16_t>(theCompareValue - theVariableValue);
				memcpy(results + numberOfVariablesFound * resultSize + sizeof(P), &valueDifference, sizeof(valueDifference));
				
				numberOfVariablesFound++;
			}
			
			dataIndex += dataAlignment;
		}
	}
	
	return [NSData dataWithBytesNoCopy:results length:numberOfVariablesFound * resultSize freeWhenDone:YES];
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
ZGSearchResults *ZGSearchWithFunction(F comparisonFunction, ZGMemoryMap processTask, T *searchValue, ZGSearchData * __unsafe_unretained searchData, ZGVariableType rawDataType, ZGVariableType resultDataType, BOOL storeValueDifference, id <ZGSearchProgressDelegate> delegate)
{
	ZGMemorySize dataAlignment = searchData.dataAlignment;
	ZGMemorySize pointerSize = searchData.pointerSize;
	ZGMemorySize dataSize = searchData.dataSize;
	ZGMemorySize stride = storeValueDifference ? (searchData.pointerSize + sizeof(uint16_t)) : searchData.pointerSize;
	BOOL shouldCompareStoredValues = searchData.shouldCompareStoredValues;
	BOOL unalignedAccesses = searchResultsHaveUnalignedAccess(searchData, rawDataType);
	BOOL requiresExtraCopy = NO;
	BOOL usesExtraStorage = searchUsesExtraStorage(searchData, rawDataType, unalignedAccesses, &requiresExtraCopy);
	
	return ZGSearchForDataHelper(processTask, searchData, resultDataType, stride, unalignedAccesses, usesExtraStorage, delegate, ^NSData *(ZGMemorySize dataIndex, ZGMemoryAddress address, ZGMemorySize size, void *bytes, void *regionBytes, void *extraStorage) {
		ZGMemorySize endLimit = size - dataSize;
		
		NSData *resultSet;
		
		if (!shouldCompareStoredValues)
		{
			if (pointerSize == sizeof(ZGMemoryAddress))
			{
				if (!requiresExtraCopy)
				{
					if (storeValueDifference)
					{
						resultSet = ZGSearchWithFunctionHelperRegularAndStoreValueDifference<T, ZGMemoryAddress>(searchValue, comparisonFunction, MOVE_VALUE_FUNC, searchData, dataIndex, dataAlignment, dataSize, endLimit, address, bytes, extraStorage);
					}
					else
					{
						resultSet = ZGSearchWithFunctionHelperRegular<T, ZGMemoryAddress>(searchValue, comparisonFunction, MOVE_VALUE_FUNC, searchData, dataIndex, dataAlignment, dataSize, endLimit, address, bytes, extraStorage);
					}
				}
				else
				{
					if (storeValueDifference)
					{
						resultSet = ZGSearchWithFunctionHelperRegularAndStoreValueDifference<T, ZGMemoryAddress>(searchValue, comparisonFunction, COPY_VALUE_FUNC, searchData, dataIndex, dataAlignment, dataSize, endLimit, address, bytes, extraStorage);
					}
					else
					{
						resultSet = ZGSearchWithFunctionHelperRegular<T, ZGMemoryAddress>(searchValue, comparisonFunction, COPY_VALUE_FUNC, searchData, dataIndex, dataAlignment, dataSize, endLimit, address, bytes, extraStorage);
					}
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
	
	ZGMemorySize stride = searchData.pointerSize;
	
	BOOL unalignedAccesses = searchResultsHaveUnalignedAccess(searchData, dataType);
	BOOL usesExtraStorage = searchUsesExtraStorage(searchData, dataType, unalignedAccesses, nullptr);
	
	return ZGSearchForDataHelper(processTask, searchData, dataType, stride, unalignedAccesses, usesExtraStorage, delegate, ^NSData *(ZGMemorySize __unused dataIndex, ZGMemoryAddress address, ZGMemorySize size, void *bytes, void * __unused regionBytes, void * __unused extraStorage) {
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
			retValue = ZGSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, type *a, type *b, type *c) -> bool { return functionType(sd, a, b, c); }, processTask, static_cast<type *>(searchData.searchValue), searchData, dataType, dataType, NO, delegate); \
			break; \
		} else { \
			retValue = ZGSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, u##type *a, u##type *b, u##type *c) -> bool { return functionType(sd, a, b, c); }, processTask, static_cast<u##type *>(searchData.searchValue), searchData, dataType, dataType, NO, delegate); \
			break; \
		}

#define ZGHandleIntegerCase(dataType, function) \
if (dataType == ZGPointer) {\
	switch (searchData.dataSize) {\
		case sizeof(ZGMemoryAddress):\
			retValue = ZGSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint64_t *a, uint64_t *b, uint64_t *c) -> bool { return function(sd, a, b, c); }, processTask, static_cast<uint64_t *>(searchData.searchValue), searchData, ZGInt64, ZGPointer, NO, delegate); \
			break;\
		case sizeof(ZG32BitMemoryAddress):\
			retValue = ZGSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint32_t *a, uint32_t *b, uint32_t *c) -> bool { return function(sd, a, b, c); }, processTask, static_cast<uint32_t *>(searchData.searchValue), searchData, ZGInt32, ZGPointer, NO, delegate); \
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

#pragma mark Pointers

template <typename T>
bool ZGPointerEqualsWithMaxOffset(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ __unused extraStorage)
{
	T theVariableValue = *(static_cast<T *>(variableValue));
	T theCompareValue = *(static_cast<T *>(compareValue));
	
	return (theCompareValue >= theVariableValue) && (theCompareValue - theVariableValue <= static_cast<T>(searchData->_indirectOffset));
}

template <typename T>
bool ZGPointerEqualsWithSameOffset(ZGSearchData *__unsafe_unretained searchData, T *__restrict__ variableValue, T *__restrict__ compareValue, T * __restrict__ __unused extraStorage)
{
	T theVariableValue = *(static_cast<T *>(variableValue));
	T theCompareValue = *(static_cast<T *>(compareValue));
	
	return (theCompareValue >= theVariableValue) && (theCompareValue - theVariableValue == static_cast<T>(searchData->_indirectOffset));
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
		retValue = ZGSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, type *a, type *b, type *c) -> bool { return functionType(sd, a, b, c); }, processTask, static_cast<type *>(searchData.searchValue), searchData, dataType, dataType, NO, delegate); \
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
			retValue = ZGSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b, uint8_t *c) -> bool { return ZGByteArrayWithWildcardsEquals(sd, a, b, c); }, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, ZGByteArray, ZGByteArray, NO, delegate);
			break;
		case ZGNotEquals:
			retValue = ZGSearchWithFunction([](ZGSearchData *__unsafe_unretained sd, uint8_t *a, uint8_t *b, uint8_t *c) -> bool { return ZGByteArrayWithWildcardsNotEquals(sd, a, b, c); }, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, ZGByteArray, ZGByteArray, NO, delegate);
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
			retValue = ZGSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b, uint8_t *c) -> bool { return ZGByteArrayNotEquals(sd, a, b, c); }, processTask, static_cast<uint8_t *>(searchData.searchValue), searchData, ZGByteArray, ZGByteArray, NO, delegate);
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

template <typename F>
static ZGSearchResults *ZGBinarySearchAndCompareForIndirectPointer(const ZGPointerValueEntry *pointerValueEntries, const size_t pointerValueEntriesCount, const ZGMemoryAddress searchValueAddress, const uint16_t indirectOffset, ZGVariableType resultDataType, const BOOL storeValueDifference, F compareFunc)
{
	NSUInteger end = pointerValueEntriesCount;
	NSUInteger start = 0;
	NSUInteger middleIndex = 0;
	
	NSMutableData *pointerValueResultSet = [[NSMutableData alloc] init];
	
	while (end > start)
	{
		middleIndex = start + (end - start) / 2;
		ZGPointerValueEntry pointerValueEntry = pointerValueEntries[middleIndex];
		
		ZGPointerComparisonResult compareResult = compareFunc(pointerValueEntry.pointerValue, searchValueAddress, indirectOffset);
		switch (compareResult)
		{
			case ZGPointerComparisonResultAscending:
				start = middleIndex + 1;
				break;
			case ZGPointerComparisonResultDescending:
				end = middleIndex;
				break;
			case ZGPointerComparisonResultEqual:
				goto END_BINARY_SEARCH;
		}
	}
	
END_BINARY_SEARCH:
	if (end > start)
	{
		NSUInteger lowerTargetIndex = middleIndex;
		
		while (lowerTargetIndex > 0)
		{
			ZGPointerValueEntry pointerValueEntry = pointerValueEntries[lowerTargetIndex];
			if (pointerValueEntry.pointerValue <= searchValueAddress && pointerValueEntry.pointerValue + indirectOffset >= searchValueAddress)
			{
				ZGMemoryAddress address = pointerValueEntry.address;
				[pointerValueResultSet appendBytes:&address length:sizeof(address)];
				
				if (storeValueDifference)
				{
					uint16_t offset = static_cast<uint16_t>(searchValueAddress - pointerValueEntry.pointerValue);
					[pointerValueResultSet appendBytes:&offset length:sizeof(offset)];
				}
			}
			else
			{
				break;
			}
			
			lowerTargetIndex--;
		}
		
		NSUInteger higherTargetIndex = middleIndex + 1;
		while (higherTargetIndex < end)
		{
			ZGPointerValueEntry pointerValueEntry = pointerValueEntries[higherTargetIndex];
			if (pointerValueEntry.pointerValue <= searchValueAddress && pointerValueEntry.pointerValue + indirectOffset >= searchValueAddress)
			{
				ZGMemoryAddress address = pointerValueEntry.address;
				[pointerValueResultSet appendBytes:&address length:sizeof(address)];
				
				if (storeValueDifference)
				{
					uint16_t offset = static_cast<uint16_t>(searchValueAddress - pointerValueEntry.pointerValue);
					[pointerValueResultSet appendBytes:&offset length:sizeof(offset)];
				}
			}
			else
			{
				break;
			}
			
			higherTargetIndex++;
		}
	}
	
	const ZGMemorySize stride = storeValueDifference ? (sizeof(ZGMemoryAddress) + sizeof(uint16_t)) : sizeof(ZGMemoryAddress);
		
	ZGSearchResults *searchResults = [[ZGSearchResults alloc] initWithResultSets:@[pointerValueResultSet] resultType:ZGSearchResultTypeDirect dataType:resultDataType stride:stride unalignedAccess:NO];
	
	return searchResults;
}

static ZGSearchResults *_ZGSearchForSingleLevelPointer(ZGMemoryAddress searchValueAddress, const ZGPointerValueEntry *pointerValueEntries, const size_t pointerValueEntriesCount, ZGMemoryMap processTask, ZGSearchData *searchData, BOOL offsetMaxComparison)
{
	ZGSearchResults *searchResults;
	if (pointerValueEntries == nullptr)
	{
		if (offsetMaxComparison)
		{
			searchResults = ZGSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint64_t *a, uint64_t *b, uint64_t *c) -> bool { return ZGPointerEqualsWithMaxOffset(sd, a, b, c); }, processTask, static_cast<uint64_t *>(&searchValueAddress), searchData, ZGInt64, ZGPointer, offsetMaxComparison, nil);
		}
		else
		{
			searchResults = ZGSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint64_t *a, uint64_t *b, uint64_t *c) -> bool { return ZGPointerEqualsWithSameOffset(sd, a, b, c); }, processTask, static_cast<uint64_t *>(&searchValueAddress), searchData, ZGInt64, ZGPointer, offsetMaxComparison, nil);
		}
	}
	else
	{
		if (offsetMaxComparison)
		{
			auto compareFunc = [](const ZGMemoryAddress pointerValue1, const ZGMemoryAddress pointerValue2, const uint16_t offset) {
				if (pointerValue1 + offset < pointerValue2)
				{
					return ZGPointerComparisonResultAscending;
				}
				else if (pointerValue1 > pointerValue2)
				{
					return ZGPointerComparisonResultDescending;
				}
				else
				{
					return ZGPointerComparisonResultEqual;
				}
			};
			
			searchResults = ZGBinarySearchAndCompareForIndirectPointer(pointerValueEntries, pointerValueEntriesCount, searchValueAddress, searchData->_indirectOffset, ZGPointer, offsetMaxComparison, compareFunc);
		}
		else
		{
			auto compareFunc = [](const ZGMemoryAddress pointerValue1, const ZGMemoryAddress pointerValue2, const uint16_t offset) {
				const ZGMemoryAddress pointerValue1WithOffset = pointerValue1 + offset;
				
				if (pointerValue1WithOffset < pointerValue2)
				{
					return ZGPointerComparisonResultAscending;
				}
				else if (pointerValue1WithOffset > pointerValue2)
				{
					return ZGPointerComparisonResultDescending;
				}
				else
				{
					return ZGPointerComparisonResultEqual;
				}
			};
			
			searchResults = ZGBinarySearchAndCompareForIndirectPointer(pointerValueEntries, pointerValueEntriesCount, searchValueAddress, searchData->_indirectOffset, ZGPointer, offsetMaxComparison, compareFunc);
		}
	}
	
	return searchResults;
}

static uint16_t _ZGBaseStaticImageIndexForAddress(const NSRange *totalStaticSegmentRangeValues, ZGMemorySize totalStaticSegmentRangeValuesCount, ZGMemoryAddress address, ZGMemorySize pointerSize)
{
	NSUInteger matchingSegmentIndex = 0;
	const NSRange *matchingTotalStaticSegmentRange;
	{
		NSUInteger end = totalStaticSegmentRangeValuesCount;
		NSUInteger start = 0;

		while (end > start)
		{
			matchingSegmentIndex = start + (end - start) / 2;
			matchingTotalStaticSegmentRange = &totalStaticSegmentRangeValues[matchingSegmentIndex];

			if (matchingTotalStaticSegmentRange->location + matchingTotalStaticSegmentRange->length <= address)
			{
				start = matchingSegmentIndex + 1;
			}
			else if (matchingTotalStaticSegmentRange->location >= address + pointerSize)
			{
				end = matchingSegmentIndex;
			}
			else
			{
				return static_cast<uint16_t>(matchingSegmentIndex);
			}
		}
	}
	
	return UINT16_MAX;
}

static void _ZGWriteIndirectResultToBuffer(uint8_t *writeBuffer, ZGMemoryAddress baseAddress, uint16_t baseImageIndex, uint16_t levelIndex, uint16_t *currentOffsets, ZGMemorySize stride, ZGMemorySize pointerSize, const ZGMemoryAddress *headerAddressValues)
{
	if (baseImageIndex == UINT16_MAX)
	{
		memcpy(writeBuffer, &baseAddress, pointerSize);
	}
	else
	{
		ZGMemoryAddress headerAddress = headerAddressValues[baseImageIndex];
		ZGMemoryAddress offsetAddress = (baseAddress - headerAddress);
		
		memcpy(writeBuffer, &offsetAddress, pointerSize);
	}
	
	memcpy(writeBuffer + pointerSize, &baseImageIndex, sizeof(baseImageIndex));
	
	// Write number of levels
	uint16_t numberOfLevels = levelIndex + 1;
	memcpy(writeBuffer + pointerSize + sizeof(baseImageIndex), &numberOfLevels, sizeof(numberOfLevels));
	
	// Populate writeBuffer with offsets
	memcpy(writeBuffer + pointerSize + sizeof(baseImageIndex) + sizeof(numberOfLevels), currentOffsets, sizeof(*currentOffsets) * numberOfLevels);
	
	size_t endOffset = pointerSize + sizeof(baseImageIndex) + sizeof(numberOfLevels) + sizeof(*currentOffsets) * numberOfLevels;
	
	if (stride > endOffset)
	{
		memset(writeBuffer + endOffset, 0, stride - endOffset);
	}
}

static void _ZGSearchForIndirectPointerRecursively(const ZGPointerValueEntry *pointerValueEntries, const size_t pointerValueEntriesCount, NSMutableData *currentResultSet, const ZGMemoryAddress *headerAddressValues, const NSRange *totalStaticSegmentRangeValues, ZGMemorySize totalStaticSegmentRangeValuesCount, NSMutableData *staticMainExecutableResultSet, NSMutableData *staticOtherLibrariesResultSet, uint16_t *currentOffsets, ZGMemoryAddress *currentBaseAddresses, NSCache<NSNumber *, ZGSearchResults *> *visitedSearchResults, uint16_t levelIndex, void *tempBuffer, void *searchValue, ZGSearchData *searchData, ZGVariableType indirectDataType, ZGMemorySize stride, uint16_t maxLevels, BOOL offsetMaxComparison, BOOL stopAtStaticAddresses, ZGMemoryMap processTask, id <ZGSearchProgressDelegate> delegate, ZGSearchProgressNotifier *progressNotifier)
{
	ZGMemoryAddress searchValueAddress = *(static_cast<ZGMemoryAddress *>(searchValue));
	
	NSNumber *searchValueAddressNumber = @(searchValueAddress);
	ZGSearchResults *cachedSearchResults = [visitedSearchResults objectForKey:searchValueAddressNumber];
	
	ZGSearchResults *searchResults;
	ZGMemorySize searchResultsStride;
	if (cachedSearchResults == nil)
	{
		searchResults = _ZGSearchForSingleLevelPointer(searchValueAddress, pointerValueEntries, pointerValueEntriesCount, processTask, searchData, offsetMaxComparison);
		
		searchResultsStride = searchResults.stride;
		
		currentBaseAddresses[levelIndex] = searchValueAddress;
		
		[visitedSearchResults setObject:searchResults forKey:searchValueAddressNumber cost:searchResultsStride * searchResults.count];
	}
	else
	{
		searchResults = cachedSearchResults;
		searchResultsStride = searchResults.stride;
	}
	
	uint16_t searchIndirectOffset = searchData->_indirectOffset;
	
	uint8_t scratchBufferForResults[4096];
	ZGMemorySize scratchBufferForResultsCount = 0;
	ZGMemorySize scratchBufferCapacity = sizeof(scratchBufferForResults) / stride;
	
	uint8_t scratchBufferForStaticMainExecutableResults[sizeof(scratchBufferForResults)];
	ZGMemorySize scratchBufferForStaticMainExecutableResultsCount = 0;

	uint8_t scratchBufferForStaticOtherLibraryExecutableResults[sizeof(scratchBufferForResults)];
	ZGMemorySize scratchBufferForStaticOtherLibraryExecutableResultsCount = 0;
	
	const ZGMemorySize pointerSize = sizeof(ZGMemoryAddress);
	
	for (NSData *searchResultSet in searchResults.resultSets)
	{
		const uint8_t *searchResultSetBytes = static_cast<const uint8_t *>(searchResultSet.bytes);
		NSUInteger searchResultSetDataCount = searchResultSet.length / searchResultsStride;
		for (NSUInteger searchResultSetDataIndex = 0; searchResultSetDataIndex < searchResultSetDataCount; searchResultSetDataIndex++)
		{
			const uint8_t *searchResultData = searchResultSetBytes + searchResultSetDataIndex * searchResultsStride;
			
			// Extract base address for searching
			ZGMemoryAddress baseAddress;
			memcpy(&baseAddress, searchResultData, pointerSize);
			
			// Detect if we have any cycles and stop here
			BOOL foundCycle = NO;
			for (ZGMemoryAddress cycleIndex = 0; cycleIndex <= levelIndex; cycleIndex++)
			{
				if (baseAddress == currentBaseAddresses[cycleIndex])
				{
					foundCycle = YES;
					break;
				}
			}
			
			if (!foundCycle)
			{
				//	Struct {
				//		uintptr_t baseAddress;
				//		uint16_t baseImageIndex;
				//		uint16_t numLevels;
				//		uint16_t offsets[MAX_NUM_LEVELS];
				//		uint8_t padding[N];
				//	}
				
				// Determine if variable is static
				uint16_t baseImageIndex = _ZGBaseStaticImageIndexForAddress(totalStaticSegmentRangeValues, totalStaticSegmentRangeValuesCount, baseAddress, pointerSize);
				
				// Figure out which scratch buffer to use
				uint8_t *scratchBuffer;
				ZGMemorySize *scratchBufferCount;
				if (baseImageIndex == UINT16_MAX)
				{
					scratchBuffer = scratchBufferForResults;
					scratchBufferCount = &scratchBufferForResultsCount;
				}
				else
				{
					if (baseImageIndex == 0)
					{
						scratchBuffer = scratchBufferForStaticMainExecutableResults;
						scratchBufferCount = &scratchBufferForStaticMainExecutableResultsCount;
					}
					else
					{
						scratchBuffer = scratchBufferForStaticOtherLibraryExecutableResults;
						scratchBufferCount = &scratchBufferForStaticOtherLibraryExecutableResultsCount;
					}
				}
				
				// Write offset to currentOffsets
				if (offsetMaxComparison)
				{
					memcpy(currentOffsets + levelIndex, static_cast<const uint8_t *>(searchResultData) + pointerSize, sizeof(uint16_t));
				}
				else
				{
					memcpy(currentOffsets + levelIndex, &searchIndirectOffset, sizeof(searchIndirectOffset));
				}
				
				uint8_t *writeBuffer = scratchBuffer + stride * (*scratchBufferCount);
				
				_ZGWriteIndirectResultToBuffer(writeBuffer, baseAddress, baseImageIndex, levelIndex, currentOffsets, stride, pointerSize, headerAddressValues);
				
				(*scratchBufferCount)++;
				
				if (*scratchBufferCount == scratchBufferCapacity)
				{
					NSMutableData *writeDataResultSet;
					if (baseImageIndex == UINT16_MAX)
					{
						writeDataResultSet = currentResultSet;
					}
					else if (baseImageIndex == 0)
					{
						writeDataResultSet = staticMainExecutableResultSet;
					}
					else
					{
						writeDataResultSet = staticOtherLibrariesResultSet;
					}
					
					[writeDataResultSet appendBytes:scratchBuffer length:*scratchBufferCount * stride];
					*scratchBufferCount = 0;
				}
				
				uint16_t nextLevelIndex = levelIndex + 1;
				if (nextLevelIndex < maxLevels && (!stopAtStaticAddresses || baseImageIndex == UINT16_MAX))
				{
					_ZGSearchForIndirectPointerRecursively(pointerValueEntries, pointerValueEntriesCount, currentResultSet, headerAddressValues, totalStaticSegmentRangeValues, totalStaticSegmentRangeValuesCount, staticMainExecutableResultSet, staticOtherLibrariesResultSet, currentOffsets, currentBaseAddresses, visitedSearchResults, nextLevelIndex, tempBuffer, &baseAddress, searchData, indirectDataType, stride, maxLevels, offsetMaxComparison, stopAtStaticAddresses, processTask, delegate, progressNotifier);
				}
			}
		}
	}
	
	if (scratchBufferForResultsCount > 0)
	{
		[currentResultSet appendBytes:scratchBufferForResults length:scratchBufferForResultsCount * stride];
	}
	
	if (scratchBufferForStaticMainExecutableResultsCount > 0)
	{
		[staticMainExecutableResultSet appendBytes:scratchBufferForStaticMainExecutableResults length:scratchBufferForStaticMainExecutableResultsCount * stride];
	}
	
	if (scratchBufferForStaticOtherLibraryExecutableResultsCount > 0)
	{
		[staticOtherLibrariesResultSet appendBytes:scratchBufferForStaticOtherLibraryExecutableResults length:scratchBufferForStaticOtherLibraryExecutableResultsCount * stride];
	}
}

static void ZGRetrieveIndirectAddressInformation(const void *indirectResult, NSArray<NSNumber *> * __unsafe_unretained headerAddresses, uint16_t *outNumberOfLevels, uint16_t *outBaseImageIndex, uint16_t *outOffsets, ZGMemoryAddress *outNextRecurseSearchAddress)
{
	//	Struct {
	//		uintptr_t baseAddress;
	//		uint16_t baseImageIndex;
	//		uint16_t numLevels;
	//		uint16_t offsets[MAX_NUM_LEVELS];
	//		uint8_t padding[N];
	//	}
	
	const uint8_t *resultBytes = static_cast<const uint8_t *>(indirectResult);
	
	const ZGMemorySize pointerSize = static_cast<ZGMemorySize>(sizeof(ZGMemoryAddress));
	
	ZGMemoryAddress initialBaseAddress;
	memcpy(&initialBaseAddress, resultBytes, pointerSize);
	
	uint16_t baseImageIndex;
	memcpy(&baseImageIndex, resultBytes + pointerSize, sizeof(baseImageIndex));
	
	if (outBaseImageIndex != nullptr)
	{
		*outBaseImageIndex = baseImageIndex;
	}
	
	ZGMemoryAddress baseAddress;
	if (baseImageIndex == UINT16_MAX)
	{
		baseAddress = initialBaseAddress;
	}
	else
	{
		baseAddress = initialBaseAddress + headerAddresses[baseImageIndex].unsignedLongLongValue;
	}
	
	if (outNextRecurseSearchAddress != nullptr)
	{
		*outNextRecurseSearchAddress = baseAddress;
	}
	
	uint16_t numberOfLevels;
	memcpy(&numberOfLevels, resultBytes + pointerSize + sizeof(baseImageIndex), sizeof(numberOfLevels));
	
	if (outNumberOfLevels != nullptr)
	{
		*outNumberOfLevels = numberOfLevels;
	}
	
	const uint8_t *offsets = resultBytes + pointerSize + sizeof(baseImageIndex) + sizeof(numberOfLevels);
	
	if (outOffsets != nullptr)
	{
		memcpy(outOffsets, offsets, sizeof(uint16_t) * numberOfLevels);
	}
}

static bool ZGEvaluateIndirectAddress(ZGMemoryAddress *outAddress, ZGMemoryMap processTask, const void *indirectResult, NSArray<NSNumber *> * __unsafe_unretained headerAddresses, ZGMemoryAddress minPointerAddress, ZGMemoryAddress maxPointerAddress, ZGRegionValue *regionValuesTable, ZGMemorySize regionValuesTableCount, uint16_t *outNumberOfLevels, uint16_t *outBaseImageIndex, uint16_t *outOffsets, ZGMemoryAddress *outBaseAddresses, ZGMemoryAddress *outNextRecurseSearchAddress)
{
	
	//	Struct {
	//		uintptr_t baseAddress;
	//		uint16_t baseImageIndex;
	//		uint16_t numLevels;
	//		uint16_t offsets[MAX_NUM_LEVELS];
	//		uint8_t padding[N];
	//	}
	
	const uint8_t *resultBytes = static_cast<const uint8_t *>(indirectResult);
	
	const ZGMemorySize pointerSize = static_cast<ZGMemorySize>(sizeof(ZGMemoryAddress));
	
	ZGMemoryAddress initialBaseAddress;
	memcpy(&initialBaseAddress, resultBytes, pointerSize);
	
	uint16_t baseImageIndex;
	memcpy(&baseImageIndex, resultBytes + pointerSize, sizeof(baseImageIndex));
	
	if (outBaseImageIndex != nullptr)
	{
		*outBaseImageIndex = baseImageIndex;
	}
	
	ZGMemoryAddress baseAddress;
	if (baseImageIndex == UINT16_MAX)
	{
		baseAddress = initialBaseAddress;
	}
	else
	{
		baseAddress = initialBaseAddress + headerAddresses[baseImageIndex].unsignedLongLongValue;
	}
	
	if (outNextRecurseSearchAddress != nullptr)
	{
		*outNextRecurseSearchAddress = baseAddress;
	}
	
	uint16_t numberOfLevels;
	memcpy(&numberOfLevels, resultBytes + pointerSize + sizeof(baseImageIndex), sizeof(numberOfLevels));
	
	if (outNumberOfLevels != nullptr)
	{
		*outNumberOfLevels = numberOfLevels;
	}
	
	const uint8_t *offsets = resultBytes + pointerSize + sizeof(baseImageIndex) + sizeof(numberOfLevels);
	
	if (outOffsets != nullptr)
	{
		memcpy(outOffsets, offsets, sizeof(uint16_t) * numberOfLevels);
	}
	
	bool validAddress = true;
	
	ZGMemoryAddress currentAddress = baseAddress;
	for (uint16_t level = 0; level < numberOfLevels; level++)
	{
		if (currentAddress < minPointerAddress || currentAddress >= maxPointerAddress)
		{
			validAddress = false;
			break;
		}
		
		NSUInteger targetIndex = 0;
		ZGRegionValue *regionValueEntry;
		{
			NSUInteger end = regionValuesTableCount;
			NSUInteger start = 0;
			
			while (end > start)
			{
				targetIndex = start + (end - start) / 2;
				regionValueEntry = &regionValuesTable[targetIndex];
				
				if (regionValueEntry->address + regionValueEntry->size <= currentAddress)
				{
					start = targetIndex + 1;
				}
				else if (regionValueEntry->address >= currentAddress + pointerSize)
				{
					end = targetIndex;
				}
				else
				{
					goto EVALUATE_INDIRECT_ADDRESS_FOUND_MATCH;
				}
			}
		}
		
		// Fail condition
		validAddress = false;
		break;
		
EVALUATE_INDIRECT_ADDRESS_FOUND_MATCH:
		if (regionValueEntry->bytes == nullptr)
		{
			ZGMemorySize newSize = regionValueEntry->size;
			void *newBytes = nullptr;
			if (!ZGReadBytes(processTask, regionValueEntry->address, &newBytes, &newSize))
			{
				validAddress = false;
				break;
			}
			else
			{
				regionValueEntry->size = newSize;
				regionValueEntry->bytes = newBytes;
			}
		}
		
		const void *bytesFromMemory = static_cast<const void *>(static_cast<const uint8_t *>(regionValueEntry->bytes) + currentAddress - regionValueEntry->address);
		
		ZGMemoryAddress dereferencedAddressFromMemory;
		memcpy(&dereferencedAddressFromMemory, bytesFromMemory, pointerSize);
		
		uint16_t offset;
		memcpy(&offset, offsets + sizeof(offset) * (numberOfLevels - 1 - level), sizeof(offset));
		
		currentAddress = dereferencedAddressFromMemory + offset;
		
		if (outBaseAddresses != nullptr)
		{
			outBaseAddresses[numberOfLevels - 1 - level] = currentAddress;
		}
	}
	
	if (validAddress)
	{
		*outAddress = currentAddress;
	}
	
	return validAddress;
}

static int _sortPointerMapTable(const void *entry1, const void *entry2)
{
	const ZGMemoryAddress pointerValue1 = *(static_cast<const ZGMemoryAddress *>(entry1));
	const ZGMemoryAddress pointerValue2 = *(static_cast<const ZGMemoryAddress *>(entry2));
	
	if (pointerValue1 < pointerValue2)
	{
		return -1;
	}
	else if (pointerValue1 > pointerValue2)
	{
		return 1;
	}
	else
	{
		return 0;
	}
}

ZGSearchResults *ZGSearchForIndirectPointer(ZGMemoryMap processTask, ZGSearchData *searchData, id <ZGSearchProgressDelegate> delegate, uint16_t indirectMaxLevels, ZGVariableType indirectDataType, ZGSearchResults * _Nullable previousSearchResults)
{
	const uint16_t previousIndirectMaxLevels = previousSearchResults.indirectMaxLevels;
	const uint16_t maxLevels = (indirectMaxLevels >= previousIndirectMaxLevels) ? indirectMaxLevels : previousIndirectMaxLevels;
	
	NSArray<NSValue *> *totalStaticSegmentRanges = searchData.totalStaticSegmentRanges;
	NSValue *firstTotalStaticSegmentRangeValue = totalStaticSegmentRanges.firstObject;
	
	NSArray<NSNumber *> *headerAddresses = searchData.headerAddresses;
	NSArray<NSString *> *filePaths = searchData.filePaths;
	
	// Build pointer table across all regions of interest when we are going to do an expensive search
	NSMutableData *pointerTableData;
	ZGRegionValue *narrowRegionsTable;
	ZGMemorySize narrowRegionsTableCount;
	BOOL needsToBuildPointerTableData = (maxLevels > 1 && maxLevels > previousIndirectMaxLevels);
	
	ZGMemoryAddress maxPointerValue = searchData.endAddress;
	ZGMemoryAddress minPointerValue = MAX(firstTotalStaticSegmentRangeValue.rangeValue.location, searchData.beginAddress);
	
	if (needsToBuildPointerTableData || previousSearchResults != nil)
	{
		BOOL includeSharedMemory = searchData.includeSharedMemory;
		
		NSArray<ZGRegion *> *allRegions = includeSharedMemory ? [ZGRegion submapRegionsFromProcessTask:processTask] : [ZGRegion regionsWithExtendedInfoFromProcessTask:processTask];
		
		NSArray<ZGRegion *> *regions = [ZGRegion regionsFilteredFromRegions:allRegions beginAddress:searchData.beginAddress endAddress:searchData.endAddress protectionMode:searchData.protectionMode includeSharedMemory:searchData.includeSharedMemory filterHeapAndStackData:searchData.filterHeapAndStackData totalStaticSegmentRanges:totalStaticSegmentRanges excludeStaticDataFromSystemLibraries:searchData.excludeStaticDataFromSystemLibraries filePaths:filePaths];
		
		if (previousSearchResults != nil)
		{
			narrowRegionsTableCount = regions.count;
			narrowRegionsTable = static_cast<ZGRegionValue *>(calloc(narrowRegionsTableCount, sizeof(*narrowRegionsTable)));
		}
		else
		{
			narrowRegionsTableCount = 0;
			narrowRegionsTable = nullptr;
		}
		
		ZGMemorySize dataAlignment = searchData.dataAlignment;
		
		if (needsToBuildPointerTableData)
		{
			pointerTableData = [NSMutableData data];
		}
		else
		{
			pointerTableData = nil;
		}
		
		NSUInteger regionIndex = 0;
		for (ZGRegion *region in regions)
		{
			void *bytes = nullptr;
			if (ZGReadBytes(processTask, region->_address, &bytes, &region->_size))
			{
				ZGMemoryAddress address = region->_address;
				
				if (needsToBuildPointerTableData)
				{
					ZGMemoryAddress endAddress = (region->_address + region->_size);
					
					const ZGMemoryAddress *dataBytes = static_cast<const ZGMemoryAddress *>(bytes);
					while (address < endAddress)
					{
						ZGMemoryAddress pointerValue = *dataBytes;
						if (pointerValue >= minPointerValue && pointerValue < maxPointerValue)
						{
							ZGPointerValueEntry pointerValueEntry;
							pointerValueEntry.pointerValue = pointerValue;
							pointerValueEntry.address = address;
							
							[pointerTableData appendBytes:&pointerValueEntry length:sizeof(pointerValueEntry)];
						}
						
						dataBytes++;
						address += dataAlignment;
					}
				}
				
				if (narrowRegionsTable != nullptr)
				{
					ZGRegionValue *regionValue = &narrowRegionsTable[regionIndex];
					regionValue->address = region->_address;
					regionValue->size = region->_size;
					regionValue->bytes = bytes;
				}
				else
				{
					ZGFreeBytes(bytes, region->_size);
				}
			}
			else
			{
				NSLog(@"Failed to read region bytes of size %llu", region->_size);
			}
			
			regionIndex++;
		}
		
		const size_t width = sizeof(ZGPointerValueEntry);
		qsort(pointerTableData.mutableBytes, pointerTableData.length / width, width, _sortPointerMapTable);
	}
	else
	{
		pointerTableData = nil;
		narrowRegionsTable = nil;
		narrowRegionsTableCount = 0;
	}
	
	const ZGPointerValueEntry *pointerValueEntries = static_cast<const ZGPointerValueEntry *>(pointerTableData.bytes);
	const size_t pointerValueEntriesCount = pointerTableData.length / sizeof(*pointerValueEntries);
	
	ZGMemorySize pointerSize = searchData.pointerSize;
	
	ZGMemorySize stride = [ZGSearchResults indirectStrideWithMaxNumberOfLevels:maxLevels pointerSize:pointerSize];
	
	BOOL indirectOffsetMaxComparison = searchData.indirectOffsetMaxComparison;
	BOOL indirectStopAtStaticAddresses = searchData.indirectStopAtStaticAddresses;
	
	ZGMemoryAddress *headerAddressValues = static_cast<ZGMemoryAddress *>(calloc(headerAddresses.count, sizeof(*headerAddressValues)));
	NSUInteger headerAddressIndex = 0;
	for (NSNumber *headerAddress in headerAddresses)
	{
		headerAddressValues[headerAddressIndex++] = headerAddress.unsignedLongLongValue;
	}
	
	ZGMemorySize totalStaticSegmentRangeValuesCount = totalStaticSegmentRanges.count;
	NSRange *totalStaticSegmentRangeValues = static_cast<NSRange *>(calloc(totalStaticSegmentRangeValuesCount, sizeof(*totalStaticSegmentRangeValues)));
	NSUInteger totalStaticSegmentRangeIndex = 0;
	for (NSValue *totalStaticSegmentRange in totalStaticSegmentRanges)
	{
		totalStaticSegmentRangeValues[totalStaticSegmentRangeIndex++] = totalStaticSegmentRange.rangeValue;
	}
	
	ZGSearchResults *firstLevelSearchResults;
	if (previousSearchResults == nil)
	{
		ZGSearchProgress *searchProgress = [[ZGSearchProgress alloc] initWithProgressType:ZGSearchProgressMemoryScanning maxProgress:1.0];
		
		if (delegate != nil)
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				[delegate progressWillBegin:searchProgress];
			});
		}
		
		ZGSearchResults *initialSearchResults = _ZGSearchForSingleLevelPointer(*static_cast<ZGMemoryAddress *>(searchData.searchValue), pointerValueEntries, pointerValueEntriesCount, processTask, searchData, indirectOffsetMaxComparison);
		
		// Enumerate through initial search results
		// Create one-level indirect result sets based on them
		ZGMemorySize initialSearchResultsStride = initialSearchResults.stride;
		uint16_t indirectOffset = searchData.indirectOffset;
		
		const NSUInteger firstLevelResultSetCount = 4;
		NSMutableArray<NSMutableData *> *firstLevelResultSets = [NSMutableArray arrayWithCapacity:firstLevelResultSetCount];
		for (NSUInteger firstLevelResultSetIndex = 0; firstLevelResultSetIndex < firstLevelResultSetCount; firstLevelResultSetIndex++)
		{
			[firstLevelResultSets addObject:[NSMutableData data]];
		}
		
		void *tempBuffer = static_cast<uint8_t *>(calloc(1, stride));
		
		NSUInteger firstLevelResultSetCounter = 0;
		
		for (NSData *resultSet in initialSearchResults.resultSets)
		{
			const uint8_t *resultSetBytes = static_cast<const uint8_t *>(resultSet.bytes);
			NSUInteger resultSetDataCount = resultSet.length / initialSearchResultsStride;
			
			for (NSUInteger resultSetDataIndex = 0; resultSetDataIndex < resultSetDataCount; resultSetDataIndex++)
			{
				const uint8_t *searchResultData = resultSetBytes + resultSetDataIndex * initialSearchResultsStride;
				
				ZGMemoryAddress baseAddress;
				memcpy(&baseAddress, searchResultData, sizeof(baseAddress));
				
				uint16_t baseImageIndex = _ZGBaseStaticImageIndexForAddress(totalStaticSegmentRangeValues, totalStaticSegmentRangeValuesCount, baseAddress, pointerSize);
				
				uint16_t offset;
				if (indirectOffsetMaxComparison)
				{
					memcpy(&offset, searchResultData + sizeof(baseAddress), sizeof(offset));
				}
				else
				{
					offset = indirectOffset;
				}
				
				_ZGWriteIndirectResultToBuffer(static_cast<uint8_t *>(tempBuffer), baseAddress, baseImageIndex, 0, &offset, stride, pointerSize, headerAddressValues);
				
				NSMutableData *firstLevelResultSet = firstLevelResultSets[firstLevelResultSetCounter % firstLevelResultSetCount];
				firstLevelResultSetCounter++;
				
				[firstLevelResultSet appendBytes:tempBuffer length:stride];
			}
		}
		
		free(tempBuffer);
		
		firstLevelSearchResults = [[ZGSearchResults alloc] initWithResultSets:firstLevelResultSets resultType:ZGSearchResultTypeIndirect dataType:indirectDataType stride:stride unalignedAccess:NO];
	}
	else
	{
		firstLevelSearchResults = nil;
	}
	
	// Use prior or one level result sets we created, unless we only had to compute a single level
	NSMutableArray<NSMutableData *> *resultSets = [NSMutableArray array];
	NSMutableArray<NSMutableData *> *staticMainExecutableResultSets = [NSMutableArray array];
	NSMutableArray<NSMutableData *> *staticOtherLibrariesResultSets = [NSMutableArray array];
	
	{
		ZGMemoryAddress searchAddress = *(static_cast<ZGMemoryAddress *>(searchData.searchValue));;
		
		NSArray<NSData *> *previousIndirectResultSets;
		ZGMemorySize previousIndirectResultSetStride;
		if (previousSearchResults != nil)
		{
			previousIndirectResultSets = previousSearchResults.resultSets;
			previousIndirectResultSetStride = previousSearchResults.stride;
		}
		else
		{
			previousIndirectResultSets = firstLevelSearchResults.resultSets;
			previousIndirectResultSetStride = firstLevelSearchResults.stride;
		}
		
		NSUInteger previousIndirectResultSetsCount = previousIndirectResultSets.count;
		for (NSUInteger resultSetIndex = 0; resultSetIndex < previousIndirectResultSetsCount; resultSetIndex++)
		{
			[resultSets addObject:[NSMutableData data]];
			[staticMainExecutableResultSets addObject:[NSMutableData data]];
			[staticOtherLibrariesResultSets addObject:[NSMutableData data]];
		}
		
		ZGSearchProgress *searchProgress = [[ZGSearchProgress alloc] initWithProgressType:ZGSearchProgressMemoryScanning maxProgress:previousIndirectResultSetsCount];
		
		ZGSearchProgressNotifier *progressNotifier = [[ZGSearchProgressNotifier alloc] initWithSearchProgress:searchProgress resultType:ZGSearchResultTypeIndirect dataType:indirectDataType stride:stride notifiesStaticResults:YES headerAddresses:headerAddresses delegate:delegate];
		
		if (delegate != nil)
		{
			[progressNotifier start];
		}
		
		NSCache<NSNumber *, ZGSearchResults *> *visitedSearchResults = [[NSCache alloc] init];
		visitedSearchResults.totalCostLimit = 10000000000;
		
		dispatch_queue_attr_t qosAttribute = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT, QOS_CLASS_USER_INITIATED, 0);
		dispatch_queue_t queue = dispatch_queue_create("com.zgcoder.BitSlicer.PointerAddressSearch", qosAttribute);
		
		bool usingFirstLevelSearchResults = (firstLevelSearchResults != nil);
		
		dispatch_apply(previousIndirectResultSetsCount, queue, ^(size_t resultSetIndex) {
			@autoreleasepool {
				NSMutableData *newResultSet = resultSets[resultSetIndex];
				NSMutableData *staticMainExecutableResultSet = staticMainExecutableResultSets[resultSetIndex];
				NSMutableData *staticOtherLibrariesResultSet = staticOtherLibrariesResultSets[resultSetIndex];
				
				ZGMemoryAddress *currentBaseAddresses = static_cast<ZGMemoryAddress *>(calloc(maxLevels, sizeof(*currentBaseAddresses)));
				uint16_t *currentOffsets = static_cast<uint16_t *>(calloc(maxLevels, sizeof(currentOffsets)));
				void *tempBuffer = static_cast<uint8_t *>(calloc(1, stride));
				
				NSData *previousIndirectResultSet = previousIndirectResultSets[resultSetIndex];
				const uint8_t *previousIndirectResultSetBytes = static_cast<const uint8_t *>(previousIndirectResultSet.bytes);
				NSUInteger previousIndirectResultSetCount = previousIndirectResultSet.length / previousIndirectResultSetStride;
				for (NSUInteger previousIndirectResultSetIndex = 0; previousIndirectResultSetIndex < previousIndirectResultSetCount; previousIndirectResultSetIndex++)
				{
					const uint8_t *previousIndirectResult = previousIndirectResultSetBytes + previousIndirectResultSetIndex * previousIndirectResultSetStride;
					
					uint16_t numberOfLevels;
					ZGMemoryAddress nextRecurseSearchAddress;
					
					memset(currentOffsets, 0, sizeof(*currentOffsets) * maxLevels);
					memset(currentBaseAddresses, 0, sizeof(*currentBaseAddresses) * maxLevels);
					
					uint16_t baseImageIndex;
					
					if (usingFirstLevelSearchResults)
					{
						ZGRetrieveIndirectAddressInformation(previousIndirectResult, headerAddresses, &numberOfLevels, &baseImageIndex, currentOffsets, &nextRecurseSearchAddress);
						
						currentBaseAddresses[0] = searchAddress;
					}
					else
					{
						ZGMemoryAddress currentAddress;
						
						bool evaluatedIndirectAddress = ZGEvaluateIndirectAddress(&currentAddress, processTask, previousIndirectResult, headerAddresses, minPointerValue, maxPointerValue, narrowRegionsTable, narrowRegionsTableCount, &numberOfLevels, &baseImageIndex, currentOffsets, currentBaseAddresses, &nextRecurseSearchAddress);
						
						if (!evaluatedIndirectAddress || currentAddress != searchAddress)
						{
							continue;
						}
					}
					
					memset(tempBuffer, 0, stride);
					memcpy(tempBuffer, previousIndirectResult, previousIndirectResultSetStride);
					
					BOOL isStatic = (baseImageIndex != UINT16_MAX);
					if (isStatic)
					{
						NSMutableData *staticResultSet = (baseImageIndex == 0) ? staticMainExecutableResultSet : staticOtherLibrariesResultSet;
						
						[staticResultSet appendBytes:tempBuffer length:stride];
					}
					else
					{
						[newResultSet appendBytes:tempBuffer length:stride];
					}
					
					if (!isStatic || !indirectStopAtStaticAddresses)
					{
						// Determine if for this indirect result if we should recurse deeper
						// This will apply to results that have reached the maximum level from the previous indirect search
						if ((usingFirstLevelSearchResults || numberOfLevels == previousIndirectMaxLevels) && indirectMaxLevels > numberOfLevels)
						{
							_ZGSearchForIndirectPointerRecursively(pointerValueEntries, pointerValueEntriesCount, newResultSet, headerAddressValues, totalStaticSegmentRangeValues, totalStaticSegmentRangeValuesCount, staticMainExecutableResultSet, staticOtherLibrariesResultSet, currentOffsets, currentBaseAddresses, visitedSearchResults, numberOfLevels, tempBuffer, &nextRecurseSearchAddress, searchData, indirectDataType, stride, maxLevels, indirectOffsetMaxComparison, indirectStopAtStaticAddresses, processTask, delegate, progressNotifier);
						}
					}
				}
				
				if (delegate != nil)
				{
					[progressNotifier addResultSet:newResultSet staticMainExecutableResultSet:staticMainExecutableResultSet staticOtherLibraryResultSet:staticOtherLibrariesResultSet];
				}
				
				free(currentBaseAddresses);
				free(currentOffsets);
				free(tempBuffer);
			}
		});
		
		[progressNotifier stop];
		
		for (ZGMemorySize regionIndex = 0; regionIndex < narrowRegionsTableCount; regionIndex++)
		{
			ZGRegionValue regionValue = narrowRegionsTable[regionIndex];
			if (regionValue.bytes != nullptr)
			{
				ZGFreeBytes(regionValue.bytes, regionValue.size);
				narrowRegionsTable[regionIndex].bytes = nullptr;
			}
		}
	}
	
	free(narrowRegionsTable);
	narrowRegionsTable = nullptr;
	free(headerAddressValues);
	free(totalStaticSegmentRangeValues);
	
	[resultSets insertObjects:staticOtherLibrariesResultSets atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, staticOtherLibrariesResultSets.count)]];
	
	[resultSets insertObjects:staticMainExecutableResultSets atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, staticMainExecutableResultSets.count)]];
	
	// Assume unaligned access for now(?)
	BOOL unalignedAccess = NO;
	ZGSearchResults *indirectSearchResults = [[ZGSearchResults alloc] initWithResultSets:[resultSets copy] resultType:ZGSearchResultTypeIndirect dataType:indirectDataType stride:stride unalignedAccess:unalignedAccess];
	
	indirectSearchResults.indirectMaxLevels = maxLevels;
	
	indirectSearchResults.headerAddresses = headerAddresses;
	indirectSearchResults.totalStaticSegmentRanges = totalStaticSegmentRanges;
	indirectSearchResults.filePaths = filePaths;
	
	return indirectSearchResults;
}

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

typedef NSData *(^zg_narrow_search_for_data_helper_t)(size_t resultSetIndex, NSData * __unsafe_unretained oldResultSet, NSData * __unsafe_unretained oldIndirectResultSet, void *extraStorage);

ZGSearchResults *ZGNarrowSearchForDataHelper(ZGSearchData *searchData, id <ZGSearchProgressDelegate> delegate, ZGSearchResults *firstSearchResults, ZGSearchResults *laterSearchResults, ZGVariableType resultDataType, BOOL unalignedAccess, BOOL usesExtraStorage, ZGSearchResults *indirectSearchResults, zg_narrow_search_for_data_helper_t helper)
{
	ZGMemorySize dataSize = searchData.dataSize;
	
	ZGMemorySize oldFirstSearchResultsStride = firstSearchResults.stride;
	ZGMemorySize newResultStride = (indirectSearchResults == nil) ? oldFirstSearchResultsStride : indirectSearchResults.stride;
	
	ZGSearchResultType resultType = (indirectSearchResults == nil) ? ZGSearchResultTypeDirect : ZGSearchResultTypeIndirect;
	
	ZGMemorySize newResultSetCount = firstSearchResults.resultSets.count + laterSearchResults.resultSets.count;
	
	ZGSearchProgress *searchProgress = [[ZGSearchProgress alloc] initWithProgressType:ZGSearchProgressMemoryScanning maxProgress:newResultSetCount];
	
	ZGSearchProgressNotifier *progressNotifier = [[ZGSearchProgressNotifier alloc] initWithSearchProgress:searchProgress resultType:resultType dataType:resultDataType stride:newResultStride notifiesStaticResults:NO headerAddresses:searchData.headerAddresses delegate:delegate];
	
	if (delegate != nil)
	{
		[progressNotifier start];
	}
	
	const void **newResultSets = static_cast<const void **>(calloc(newResultSetCount, sizeof(*newResultSets)));
	assert(newResultSets != NULL);
	
	dispatch_queue_attr_t qosAttribute = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT, QOS_CLASS_USER_INITIATED, 0);
	dispatch_queue_t queue = dispatch_queue_create("com.zgcoder.BitSlicer.NarrowSearch", qosAttribute);
	
	dispatch_apply(newResultSetCount, queue, ^(size_t resultSetIndex) {
		@autoreleasepool
		{
			if (!searchProgress.shouldCancelSearch)
			{
				NSData *oldResultSet = resultSetIndex < firstSearchResults.resultSets.count ? [firstSearchResults.resultSets objectAtIndex:resultSetIndex] : [laterSearchResults.resultSets objectAtIndex:resultSetIndex - firstSearchResults.resultSets.count];
				
				// When indirect narrow searches are done, no laterSearchResults are used
				NSData *oldIndirectResultSet = (indirectSearchResults == nil) ? nil : [indirectSearchResults.resultSets objectAtIndex:resultSetIndex];
				
				NSData *results = nil;
				
				if (oldResultSet.length >= oldFirstSearchResultsStride)
				{
					void *extraStorage = usesExtraStorage ? calloc(1, dataSize) : nullptr;
					results = helper(resultSetIndex, oldResultSet, oldIndirectResultSet, extraStorage);
					newResultSets[resultSetIndex] = CFBridgingRetain(results);
					free(extraStorage);
				}
				
				[progressNotifier addResultSet:(results != nil ? results : NSData.data) staticMainExecutableResultSet:nil staticOtherLibraryResultSet:nil];
			}
		}
	});
	
	[progressNotifier stop];
	
	NSArray<NSData *> *resultSets;
	
	if (searchProgress.shouldCancelSearch)
	{
		resultSets = [NSArray array];
		
		// Deallocate results into separate queue since this could take some time
		dispatch_async(queue, ^{
			for (NSUInteger resultSetIndex = 0; resultSetIndex < newResultSetCount; resultSetIndex++)
			{
				const void *resultSetData = newResultSets[resultSetIndex];
				if (resultSetData != nullptr)
				{
					CFRelease(resultSetData);
				}
			}
			
			free(newResultSets);
		});
	}
	else
	{
		NSMutableArray<NSData *> *filteredResultSets = [NSMutableArray array];
		for (NSUInteger resultSetIndex = 0; resultSetIndex < newResultSetCount; resultSetIndex++)
		{
			const void *resultSetData = newResultSets[resultSetIndex];
			if (resultSetData != nullptr)
			{
				NSData *resultSetObjCData = static_cast<NSData *>(CFBridgingRelease(resultSetData));
				
				if (resultSetObjCData.length != 0)
				{
					[filteredResultSets addObject:resultSetObjCData];
				}
			}
		}
		
		free(newResultSets);
		
		resultSets = [filteredResultSets copy];
	}
	
	return [[ZGSearchResults alloc] initWithResultSets:resultSets resultType:resultType dataType:resultDataType stride:newResultStride unalignedAccess:unalignedAccess];
}

template <typename T, typename P, typename F, typename C>
bool ZGNarrowSearchWithFunctionRegularCompare(ZGRegion * __unused *lastUsedSavedRegionReference, ZGRegion * __unsafe_unretained lastUsedRegion, P variableAddress, ZGMemorySize dataSize, NSDictionary<NSNumber *, ZGRegion *> * __unused __unsafe_unretained savedPageToRegionTable, NSArray<ZGRegion *> * __unused __unsafe_unretained savedRegions, ZGMemorySize __unused pageSize, F comparisonFunction, C transferBytes, ZGSearchData * __unsafe_unretained searchData, T *searchValue, void *extraStorage)
{
	T *currentValue = static_cast<T *>(transferBytes(static_cast<uint8_t *>(lastUsedRegion->_bytes) + (variableAddress - lastUsedRegion->_address), extraStorage, dataSize));
	
	return comparisonFunction(searchData, currentValue, searchValue, static_cast<T *>(extraStorage));
}

template <typename T, typename P, typename F, typename C>
bool ZGNarrowSearchWithFunctionStoredCompare(ZGRegion **lastUsedSavedRegionReference, ZGRegion * __unsafe_unretained lastUsedRegion, P variableAddress, ZGMemorySize dataSize, NSDictionary<NSNumber *, ZGRegion *> * __unsafe_unretained savedPageToRegionTable, NSArray<ZGRegion *> * __unsafe_unretained savedRegions, ZGMemorySize pageSize, F comparisonFunction, C transferBytes, ZGSearchData * __unsafe_unretained searchData, T * __unused searchValue, void *extraStorage)
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
		
		return comparisonFunction(searchData, currentValue, compareValue, static_cast<T *>(extraStorage));
	}
	else
	{
		return false;
	}
}

template <typename T, typename P, typename F, typename H>
NSData *ZGNarrowSearchWithFunctionType(F comparisonFunction, ZGMemoryMap processTask, T *searchValue, ZGSearchData * __unsafe_unretained searchData, void *extraStorage, P resultDataStride, ZGMemorySize dataSize, NSData * __unsafe_unretained oldResultSet, NSDictionary<NSNumber *, ZGRegion *> * __unsafe_unretained pageToRegionTable, NSDictionary<NSNumber *, ZGRegion *> * __unsafe_unretained savedPageToRegionTable, NSArray<ZGRegion *> * __unsafe_unretained savedRegions, ZGMemorySize pageSize, NSData * __unsafe_unretained oldIndirectResultSet, H compareHelperFunction)
{
	ZGRegion *lastUsedRegion = nil;
	ZGRegion *lastUsedSavedRegion = nil;
	
	ZGMemorySize oldDataLength = oldResultSet.length;
	const void *oldResultSetBytes = oldResultSet.bytes;
	
	const void *oldIndirectResultSetBytes = oldIndirectResultSet.bytes;
	
	ZGMemorySize oldVariableCount = oldDataLength / sizeof(P);
	
	ZGProtectionMode protectionMode = searchData.protectionMode;
	bool regionMatchesProtection = true;
	bool indirectNarrowSearch = (oldIndirectResultSetBytes != nullptr);

	ZGMemoryAddress beginAddress = searchData.beginAddress;
	ZGMemoryAddress endAddress = searchData.endAddress;
	
	size_t capacity = MAX(INITIAL_BUFFER_ADDRESSES_CAPACITY, oldVariableCount);
	uint8_t *narrowResultData = static_cast<uint8_t *>(malloc(capacity * resultDataStride));
	ZGMemorySize numberOfVariablesFound = 0;

	// Make sure we don't integer overflow
	constexpr P maxAddressTypeValue {std::numeric_limits<P>::max()};
	const P maxVariableAddressWithDataSize = maxAddressTypeValue - static_cast<P>(dataSize);
	
	for (ZGMemorySize oldVariableIndex = 0; oldVariableIndex < oldVariableCount; oldVariableIndex++)
	{
		P variableAddress = *(static_cast<P *>(const_cast<void *>(oldResultSetBytes)) + oldVariableIndex);
		
		if (variableAddress == 0x0 || variableAddress > maxVariableAddressWithDataSize)
		{
			continue;
		}
		
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
		
		if (lastUsedRegion != nil && regionMatchesProtection && variableAddress >= beginAddress && variableAddress + dataSize <= endAddress && compareHelperFunction(&lastUsedSavedRegion, lastUsedRegion, variableAddress, dataSize, savedPageToRegionTable, savedRegions, pageSize, comparisonFunction, searchData, searchValue, extraStorage))
		{
			if (!indirectNarrowSearch)
			{
				memcpy(narrowResultData + numberOfVariablesFound * sizeof(variableAddress), &variableAddress, sizeof(variableAddress));
			}
			else
			{
				memcpy(narrowResultData + numberOfVariablesFound * resultDataStride, static_cast<const uint8_t *>(oldIndirectResultSetBytes) + oldVariableIndex * resultDataStride, resultDataStride);
			}
			numberOfVariablesFound++;
		}
	}
	
	if (lastUsedRegion != nil)
	{
		ZGFreeBytes(lastUsedRegion->_bytes, lastUsedRegion->_size);
	}
	
	return [NSData dataWithBytesNoCopy:narrowResultData length:numberOfVariablesFound * resultDataStride freeWhenDone:YES];
}

template <typename T, typename F>
ZGSearchResults *ZGNarrowSearchWithFunction(F comparisonFunction, ZGMemoryMap processTask, BOOL translated, T *searchValue, ZGSearchData * __unsafe_unretained searchData, ZGVariableType rawDataType, ZGVariableType resultDataType, id <ZGSearchProgressDelegate> delegate, ZGSearchResults * __unsafe_unretained firstSearchResults, ZGSearchResults * __unsafe_unretained laterSearchResults, ZGSearchResults * __unsafe_unretained indirectSearchResults)
{
	ZGMemorySize pointerSize = searchData.pointerSize;
	ZGMemorySize resultDataStride = (indirectSearchResults == nil) ? firstSearchResults.stride : indirectSearchResults.stride;
	ZGMemorySize dataSize = searchData.dataSize;
	BOOL shouldCompareStoredValues = searchData.shouldCompareStoredValues;
	
	ZGMemorySize pageSize = ZGPageSizeForRegionAlignment(processTask, translated);
	
	BOOL includeSharedMemory = searchData.includeSharedMemory;
	
	NSArray<ZGRegion *> *allRegions = includeSharedMemory ? [ZGRegion submapRegionsFromProcessTask:processTask] : [ZGRegion regionsWithExtendedInfoFromProcessTask:processTask];
	
	BOOL unalignedAccess = firstSearchResults.unalignedAccess || laterSearchResults.unalignedAccess || indirectSearchResults.unalignedAccess;
	BOOL requiresExtraCopy = NO;
	BOOL usesExtraStorage = searchUsesExtraStorage(searchData, rawDataType, unalignedAccess, &requiresExtraCopy);
	
	return ZGNarrowSearchForDataHelper(searchData, delegate, firstSearchResults, laterSearchResults, resultDataType, unalignedAccess, usesExtraStorage, indirectSearchResults, ^NSData *(size_t resultSetIndex, NSData * __unsafe_unretained oldResultSet, NSData * __unsafe_unretained oldIndirectResultSet, void *extraStorage) {
		NSMutableDictionary<NSNumber *, ZGRegion *> *pageToRegionTable = nil;
		
		ZGMemoryAddress firstAddress = 0;
		ZGMemoryAddress lastAddress = 0;
		
		if (resultSetIndex >= firstSearchResults.resultSets.count)
		{
			pageToRegionTable = [[NSMutableDictionary alloc] init];
			
			if (pointerSize == sizeof(ZGMemoryAddress))
			{
				firstAddress = *(static_cast<ZGMemoryAddress *>(const_cast<void *>(oldResultSet.bytes)));
				lastAddress = *(static_cast<ZGMemoryAddress *>(const_cast<void *>(oldResultSet.bytes)) + oldResultSet.length / sizeof(ZGMemoryAddress) - 1) + dataSize;
			}
			else
			{
				firstAddress = *(static_cast<ZG32BitMemoryAddress *>(const_cast<void *>(oldResultSet.bytes)));
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

			NSArray<ZGRegion *> *regions = [ZGRegion regionsFilteredFromRegions:allRegions beginAddress:firstAddress endAddress:lastAddress protectionMode:searchData.protectionMode includeSharedMemory:includeSharedMemory filterHeapAndStackData:NO totalStaticSegmentRanges:nil excludeStaticDataFromSystemLibraries:NO filePaths:nil];
			
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
					auto compareHelperFunc = [](ZGRegion **_lastUsedSavedRegion, ZGRegion *_lastUsedRegion, ZGMemoryAddress _variableAddress, ZGMemorySize _dataSize, NSDictionary<NSNumber *, ZGRegion *> *_savedPageToRegionTable, NSArray<ZGRegion *> *_savedRegions, ZGMemorySize _pageSize, F _comparisonFunction, ZGSearchData *_searchData, T *_searchValue, void *_extraStorage) {
						
						return ZGNarrowSearchWithFunctionRegularCompare(_lastUsedSavedRegion, _lastUsedRegion, _variableAddress, _dataSize, _savedPageToRegionTable, _savedRegions, _pageSize, _comparisonFunction, MOVE_VALUE_FUNC, _searchData, _searchValue, _extraStorage);
					};
					
					newResultSet = ZGNarrowSearchWithFunctionType(comparisonFunction, processTask, searchValue, searchData, extraStorage, static_cast<ZGMemoryAddress>(resultDataStride), dataSize, oldResultSet, pageToRegionTable, nil, nil, pageSize, oldIndirectResultSet, compareHelperFunc);
				}
				else
				{
					auto compareHelperFunc = [](ZGRegion **_lastUsedSavedRegion, ZGRegion *_lastUsedRegion, ZGMemoryAddress _variableAddress, ZGMemorySize _dataSize, NSDictionary<NSNumber *, ZGRegion *> *_savedPageToRegionTable, NSArray<ZGRegion *> *_savedRegions, ZGMemorySize _pageSize, F _comparisonFunction, ZGSearchData *_searchData, T *_searchValue, void *_extraStorage) {
						
						return ZGNarrowSearchWithFunctionRegularCompare(_lastUsedSavedRegion, _lastUsedRegion, _variableAddress, _dataSize, _savedPageToRegionTable, _savedRegions, _pageSize, _comparisonFunction, COPY_VALUE_FUNC, _searchData, _searchValue, _extraStorage);
					};
					
					newResultSet = ZGNarrowSearchWithFunctionType(comparisonFunction, processTask, searchValue, searchData, extraStorage, static_cast<ZGMemoryAddress>(resultDataStride), dataSize, oldResultSet, pageToRegionTable, nil, nil, pageSize, oldIndirectResultSet, compareHelperFunc);
				}
			}
			else
			{
				if (!requiresExtraCopy)
				{
					auto compareHelperFunc = [](ZGRegion **_lastUsedSavedRegion, ZGRegion *_lastUsedRegion, ZG32BitMemoryAddress _variableAddress, ZGMemorySize _dataSize, NSDictionary<NSNumber *, ZGRegion *> *_savedPageToRegionTable, NSArray<ZGRegion *> *_savedRegions, ZGMemorySize _pageSize, F _comparisonFunction, ZGSearchData *_searchData, T *_searchValue, void *_extraStorage) {
						
						return ZGNarrowSearchWithFunctionRegularCompare(_lastUsedSavedRegion, _lastUsedRegion, _variableAddress, _dataSize, _savedPageToRegionTable, _savedRegions, _pageSize, _comparisonFunction, MOVE_VALUE_FUNC, _searchData, _searchValue, _extraStorage);
					};
					
					newResultSet = ZGNarrowSearchWithFunctionType(comparisonFunction, processTask, searchValue, searchData, extraStorage, static_cast<ZG32BitMemoryAddress>(resultDataStride), dataSize, oldResultSet, pageToRegionTable, nil, nil, pageSize, oldIndirectResultSet, compareHelperFunc);
				}
				else
				{
					auto compareHelperFunc = [](ZGRegion **_lastUsedSavedRegion, ZGRegion *_lastUsedRegion, ZG32BitMemoryAddress _variableAddress, ZGMemorySize _dataSize, NSDictionary<NSNumber *, ZGRegion *> *_savedPageToRegionTable, NSArray<ZGRegion *> *_savedRegions, ZGMemorySize _pageSize, F _comparisonFunction, ZGSearchData *_searchData, T *_searchValue, void *_extraStorage) {
						
						return ZGNarrowSearchWithFunctionRegularCompare(_lastUsedSavedRegion, _lastUsedRegion, _variableAddress, _dataSize, _savedPageToRegionTable, _savedRegions, _pageSize, _comparisonFunction, COPY_VALUE_FUNC, _searchData, _searchValue, _extraStorage);
					};
					
					newResultSet = ZGNarrowSearchWithFunctionType(comparisonFunction, processTask, searchValue, searchData, extraStorage, static_cast<ZG32BitMemoryAddress>(resultDataStride), dataSize, oldResultSet, pageToRegionTable, nil, nil, pageSize, oldIndirectResultSet, compareHelperFunc);
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
				
				NSArray<ZGRegion *> *regions = [ZGRegion regionsFilteredFromRegions:savedData beginAddress:firstAddress endAddress:lastAddress protectionMode:searchData.protectionMode includeSharedMemory:includeSharedMemory filterHeapAndStackData:NO totalStaticSegmentRanges:nil excludeStaticDataFromSystemLibraries:NO filePaths:nil];
				
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
					auto compareHelperFunc = [](ZGRegion **_lastUsedSavedRegion, ZGRegion *_lastUsedRegion, ZGMemoryAddress _variableAddress, ZGMemorySize _dataSize, NSDictionary<NSNumber *, ZGRegion *> *_savedPageToRegionTable, NSArray<ZGRegion *> *_savedRegions, ZGMemorySize _pageSize, F _comparisonFunction, ZGSearchData *_searchData, T *_searchValue, void *_extraStorage) {
						
						return ZGNarrowSearchWithFunctionStoredCompare(_lastUsedSavedRegion, _lastUsedRegion, _variableAddress, _dataSize, _savedPageToRegionTable, _savedRegions, _pageSize, _comparisonFunction, MOVE_VALUE_FUNC, _searchData, _searchValue, _extraStorage);
					};
					
					newResultSet = ZGNarrowSearchWithFunctionType(comparisonFunction, processTask, searchValue, searchData, extraStorage, static_cast<ZGMemoryAddress>(resultDataStride), dataSize, oldResultSet, pageToRegionTable, pageToSavedRegionTable, savedData, pageSize, oldIndirectResultSet, compareHelperFunc);
				}
				else
				{
					auto compareHelperFunc = [](ZGRegion **_lastUsedSavedRegion, ZGRegion *_lastUsedRegion, ZGMemoryAddress _variableAddress, ZGMemorySize _dataSize, NSDictionary<NSNumber *, ZGRegion *> *_savedPageToRegionTable, NSArray<ZGRegion *> *_savedRegions, ZGMemorySize _pageSize, F _comparisonFunction, ZGSearchData *_searchData, T *_searchValue, void *_extraStorage) {
						
						return ZGNarrowSearchWithFunctionStoredCompare(_lastUsedSavedRegion, _lastUsedRegion, _variableAddress, _dataSize, _savedPageToRegionTable, _savedRegions, _pageSize, _comparisonFunction, COPY_VALUE_FUNC, _searchData, _searchValue, _extraStorage);
					};
					
					newResultSet = ZGNarrowSearchWithFunctionType(comparisonFunction, processTask, searchValue, searchData, extraStorage, static_cast<ZGMemoryAddress>(resultDataStride), dataSize, oldResultSet, pageToRegionTable, pageToSavedRegionTable, savedData, pageSize, oldIndirectResultSet, compareHelperFunc);
				}
			}
			else
			{
				if (!requiresExtraCopy)
				{
					auto compareHelperFunc = [](ZGRegion **_lastUsedSavedRegion, ZGRegion *_lastUsedRegion, ZG32BitMemoryAddress _variableAddress, ZGMemorySize _dataSize, NSDictionary<NSNumber *, ZGRegion *> *_savedPageToRegionTable, NSArray<ZGRegion *> *_savedRegions, ZGMemorySize _pageSize, F _comparisonFunction, ZGSearchData *_searchData, T *_searchValue, void *_extraStorage) {
						
						return ZGNarrowSearchWithFunctionStoredCompare(_lastUsedSavedRegion, _lastUsedRegion, _variableAddress, _dataSize, _savedPageToRegionTable, _savedRegions, _pageSize, _comparisonFunction, MOVE_VALUE_FUNC, _searchData, _searchValue, _extraStorage);
					};
					
					newResultSet = ZGNarrowSearchWithFunctionType(comparisonFunction, processTask, searchValue, searchData, extraStorage, static_cast<ZG32BitMemoryAddress>(resultDataStride), dataSize, oldResultSet, pageToRegionTable, pageToSavedRegionTable, savedData, pageSize, oldIndirectResultSet, compareHelperFunc);
				}
				else
				{
					auto compareHelperFunc = [](ZGRegion **_lastUsedSavedRegion, ZGRegion *_lastUsedRegion, ZG32BitMemoryAddress _variableAddress, ZGMemorySize _dataSize, NSDictionary<NSNumber *, ZGRegion *> *_savedPageToRegionTable, NSArray<ZGRegion *> *_savedRegions, ZGMemorySize _pageSize, F _comparisonFunction, ZGSearchData *_searchData, T *_searchValue, void *_extraStorage) {
						
						return ZGNarrowSearchWithFunctionStoredCompare(_lastUsedSavedRegion, _lastUsedRegion, _variableAddress, _dataSize, _savedPageToRegionTable, _savedRegions, _pageSize, _comparisonFunction, COPY_VALUE_FUNC, _searchData, _searchValue, _extraStorage);
					};
					
					newResultSet = ZGNarrowSearchWithFunctionType(comparisonFunction, processTask, searchValue, searchData, extraStorage, static_cast<ZG32BitMemoryAddress>(resultDataStride), dataSize, oldResultSet, pageToRegionTable, pageToSavedRegionTable, savedData, pageSize, oldIndirectResultSet, compareHelperFunc);
				}
			}
		}
		
		return newResultSet;
	});
}

#pragma mark Narrowing Integers

#define ZGHandleNarrowIntegerType(functionType, type, integerQualifier, dataType, processTask, translated, searchData, delegate, firstSearchResults, laterSearchResults, indirectSearchResults) \
case dataType: \
if (integerQualifier == ZGSigned) \
	retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, type * a, type *b, type *c) -> bool { return functionType(sd, a, b, c); }, processTask, translated, static_cast<type *>(searchData.searchValue), searchData, dataType, dataType, delegate, firstSearchResults, laterSearchResults, indirectSearchResults); \
else \
	retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, u##type *a, u##type *b, u##type *c) -> bool { return functionType(sd, a, b, c); }, processTask, translated, static_cast<u##type *>(searchData.searchValue), searchData, dataType, dataType, delegate, firstSearchResults, laterSearchResults, indirectSearchResults); \
break

#define ZGHandleNarrowIntegerCase(dataType, function) \
if (dataType == ZGPointer) {\
	switch (searchData.dataSize) {\
		case sizeof(ZGMemoryAddress):\
			retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint64_t *a, uint64_t *b, uint64_t *c) -> bool { return function(sd, a, b, c); }, processTask, translated, static_cast<uint64_t *>(searchData.searchValue), searchData, ZGInt64, ZGPointer, delegate, firstSearchResults, laterSearchResults, indirectSearchResults); \
			break;\
		case sizeof(ZG32BitMemoryAddress):\
			retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint32_t *a, uint32_t *b, uint32_t *c) -> bool { return function(sd, a, b, c); }, processTask, translated, static_cast<uint32_t *>(searchData.searchValue), searchData, ZGInt32, ZGPointer, delegate, firstSearchResults, laterSearchResults, indirectSearchResults); \
			break;\
	}\
}\
else {\
	switch (dataType) {\
		ZGHandleNarrowIntegerType(function, int8_t, integerQualifier, ZGInt8, processTask, translated, searchData, delegate, firstSearchResults, laterSearchResults, indirectSearchResults);\
		ZGHandleNarrowIntegerType(function, int16_t, integerQualifier, ZGInt16, processTask, translated, searchData, delegate, firstSearchResults, laterSearchResults, indirectSearchResults);\
		ZGHandleNarrowIntegerType(function, int32_t, integerQualifier, ZGInt32, processTask, translated, searchData, delegate, firstSearchResults, laterSearchResults, indirectSearchResults);\
		ZGHandleNarrowIntegerType(function, int64_t, integerQualifier, ZGInt64, processTask, translated, searchData, delegate, firstSearchResults, laterSearchResults, indirectSearchResults);\
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

ZGSearchResults *ZGNarrowSearchForIntegers(ZGMemoryMap processTask, BOOL translated, ZGSearchData * __unsafe_unretained searchData, id <ZGSearchProgressDelegate> delegate, ZGVariableType dataType, ZGVariableQualifier integerQualifier, ZGFunctionType functionType, ZGSearchResults * __unsafe_unretained firstSearchResults, ZGSearchResults * __unsafe_unretained laterSearchResults, ZGSearchResults *__unsafe_unretained indirectSearchResults)
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

#define ZGHandleNarrowType(functionType, type, dataType, processTask, translated, searchData, delegate, firstSearchResults, laterSearchResults, indirectSearchResults) \
	case dataType: \
		retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, type *a, type *b, type *c) -> bool { return functionType(sd, a, b, c); }, processTask, translated, static_cast<type *>(searchData.searchValue), searchData, dataType, dataType, delegate, firstSearchResults, laterSearchResults, indirectSearchResults);\
		break

#define ZGHandleNarrowFloatingPointCase(theCase, function) \
switch (theCase) {\
	ZGHandleNarrowType(function, float, ZGFloat, processTask, translated, searchData, delegate, firstSearchResults, laterSearchResults, indirectSearchResults);\
	ZGHandleNarrowType(function, double, ZGDouble, processTask, translated, searchData, delegate, firstSearchResults, laterSearchResults, indirectSearchResults);\
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

ZGSearchResults *ZGNarrowSearchForFloatingPoints(ZGMemoryMap processTask, BOOL translated, ZGSearchData * __unsafe_unretained searchData, id <ZGSearchProgressDelegate> delegate, ZGVariableType dataType, ZGFunctionType functionType, ZGSearchResults * __unsafe_unretained firstSearchResults, ZGSearchResults * __unsafe_unretained laterSearchResults, ZGSearchResults * __unsafe_unretained indirectSearchResults)
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

ZGSearchResults *ZGNarrowSearchForByteArrays(ZGMemoryMap processTask, BOOL translated, ZGSearchData *searchData, ZGVariableType dataType, id <ZGSearchProgressDelegate> delegate, ZGFunctionType functionType, ZGSearchResults *firstSearchResults, ZGSearchResults *laterSearchResults, ZGSearchResults *indirectSearchResults)
{
	id retValue = nil;
	
	switch (functionType)
	{
		case ZGEquals:
			if (searchData.byteArrayFlags != nullptr)
			{
				retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b, uint8_t *c) -> bool { return ZGByteArrayWithWildcardsEquals(sd, a, b, c); }, processTask, translated, static_cast<uint8_t *>(searchData.searchValue), searchData, dataType, dataType, delegate, firstSearchResults, laterSearchResults, indirectSearchResults);
			}
			else
			{
				retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b, uint8_t *c) -> bool { return ZGByteArrayEquals(sd, a, b, c); }, processTask, translated, static_cast<uint8_t *>(searchData.searchValue), searchData, dataType, dataType, delegate, firstSearchResults, laterSearchResults, indirectSearchResults);
			}
			break;
		case ZGNotEquals:
			if (searchData.byteArrayFlags != nullptr)
			{
				retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b, uint8_t *c) -> bool { return ZGByteArrayWithWildcardsNotEquals(sd, a, b, c); }, processTask, translated, static_cast<uint8_t *>(searchData.searchValue), searchData, dataType, dataType, delegate, firstSearchResults, laterSearchResults, indirectSearchResults);
			}
			else
			{
				retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b, uint8_t *c) -> bool { return ZGByteArrayNotEquals(sd, a, b, c); }, processTask, translated, static_cast<uint8_t *>(searchData.searchValue), searchData, dataType, dataType, delegate, firstSearchResults, laterSearchResults, indirectSearchResults);
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
	ZGHandleNarrowType(function1, char, ZGString8, processTask, translated, searchData, delegate, firstSearchResults, laterSearchResults, indirectSearchResults);\
	ZGHandleNarrowType(function2, unichar, ZGString16, processTask, translated, searchData, delegate, firstSearchResults, laterSearchResults, indirectSearchResults);\
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

ZGSearchResults *ZGNarrowSearchForStrings(ZGMemoryMap processTask, BOOL translated, ZGSearchData *searchData, id <ZGSearchProgressDelegate> delegate, ZGVariableType dataType, ZGFunctionType functionType, ZGSearchResults *firstSearchResults, ZGSearchResults *laterSearchResults, ZGSearchResults *indirectSearchResults)
{
	id retValue = nil;
	
	if (!searchData.shouldIgnoreStringCase)
	{
		switch (functionType)
		{
			case ZGEquals:
				if (dataType == ZGString16 && searchData.bytesSwapped)
				{
					retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b, uint8_t *c) -> bool { return ZGString16FastSwappedEquals(sd, a, b, c); }, processTask, translated, static_cast<uint8_t *>(searchData.searchValue), searchData, dataType, dataType, delegate, firstSearchResults, laterSearchResults, indirectSearchResults);
				}
				else
				{
					retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b, uint8_t *c) -> bool { return ZGByteArrayEquals(sd, a, b, c); }, processTask, translated, static_cast<uint8_t *>(searchData.searchValue), searchData, dataType, dataType, delegate, firstSearchResults, laterSearchResults, indirectSearchResults);
				}
				break;
			case ZGNotEquals:
				if (dataType == ZGString16 && searchData.bytesSwapped)
				{
					retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b, uint8_t *c) -> bool { return ZGString16FastSwappedNotEquals(sd, a, b, c); }, processTask, translated, static_cast<uint8_t *>(searchData.searchValue), searchData, dataType, dataType, delegate, firstSearchResults, laterSearchResults, indirectSearchResults);
				}
				else
				{
					retValue = ZGNarrowSearchWithFunction([](ZGSearchData * __unsafe_unretained sd, uint8_t *a, uint8_t *b, uint8_t *c) -> bool { return ZGByteArrayNotEquals(sd, a, b, c); }, processTask, translated, static_cast<uint8_t *>(searchData.searchValue), searchData, dataType, dataType, delegate, firstSearchResults, laterSearchResults, indirectSearchResults);
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

static ZGSearchResults *_ZGNarrowSearchForData(ZGMemoryMap processTask, BOOL translated, ZGSearchData *searchData, id <ZGSearchProgressDelegate> delegate, ZGVariableType dataType, ZGVariableQualifier integerQualifier, ZGFunctionType functionType, ZGSearchResults *firstSearchResults, ZGSearchResults *laterSearchResults, ZGSearchResults *indirectSearchResults)
{
	id retValue = nil;
	
	switch (dataType)
	{
		case ZGInt8:
		case ZGInt16:
		case ZGInt32:
		case ZGInt64:
		case ZGPointer:
			retValue = ZGNarrowSearchForIntegers(processTask, translated, searchData, delegate, dataType, integerQualifier, functionType, firstSearchResults, laterSearchResults, indirectSearchResults);
			break;
		case ZGFloat:
		case ZGDouble:
			retValue = ZGNarrowSearchForFloatingPoints(processTask, translated, searchData, delegate, dataType, functionType, firstSearchResults, laterSearchResults, indirectSearchResults);
			break;
		case ZGString8:
		case ZGString16:
			retValue = ZGNarrowSearchForStrings(processTask, translated, searchData, delegate, dataType, functionType, firstSearchResults, laterSearchResults, indirectSearchResults);
			break;
		case ZGByteArray:
			retValue = ZGNarrowSearchForByteArrays(processTask, translated, searchData, dataType, delegate, functionType, firstSearchResults, laterSearchResults, indirectSearchResults);
			break;
		case ZGScript:
			break;
	}
	
	return retValue;
}

ZGSearchResults *ZGNarrowSearchForData(ZGMemoryMap processTask, BOOL translated, ZGSearchData *searchData, id <ZGSearchProgressDelegate> delegate, ZGVariableType dataType, ZGVariableQualifier integerQualifier, ZGFunctionType functionType, ZGSearchResults *firstSearchResults, ZGSearchResults *laterSearchResults)
{
	return _ZGNarrowSearchForData(processTask, translated, searchData, delegate, dataType, integerQualifier, functionType, firstSearchResults, laterSearchResults, nil);
}

ZGSearchResults *ZGNarrowIndirectSearchForData(ZGMemoryMap processTask, BOOL translated, ZGSearchData *searchData, id <ZGSearchProgressDelegate> delegate, ZGVariableType dataType, ZGVariableQualifier integerQualifier, ZGFunctionType functionType, ZGSearchResults *indirectSearchResults)
{
	NSArray<NSData *> *indirectResultSets = indirectSearchResults.resultSets;
	
	NSArray<ZGRegion *> *allRegions = [ZGRegion regionsWithExtendedInfoFromProcessTask:processTask];
	
	NSArray<ZGRegion *> *regions = [ZGRegion regionsFilteredFromRegions:allRegions beginAddress:searchData.beginAddress endAddress:searchData.endAddress protectionMode:searchData.protectionMode includeSharedMemory:searchData.includeSharedMemory filterHeapAndStackData:NO totalStaticSegmentRanges:nil excludeStaticDataFromSystemLibraries:NO filePaths:nil];
	
	ZGMemorySize regionValuesCount = regions.count;
	ZGRegionValue *regionValues = static_cast<ZGRegionValue *>(calloc(regionValuesCount, sizeof(*regionValues)));
	
	{
		NSUInteger regionIndex = 0;
		for (ZGRegion *region in regions)
		{
			ZGRegionValue regionValue;
			regionValue.address = region.address;
			regionValue.size = region.size;
			regionValue.bytes = nullptr;
			regionValues[regionIndex++] = regionValue;
		}
	}
	
	NSMutableArray<NSData *> *directResultSets = [NSMutableArray array];
	
	NSArray<NSNumber *> *headerAddresses = indirectSearchResults.headerAddresses;
	
	ZGMemoryAddress minPointerAddress = searchData.beginAddress;
	ZGMemoryAddress maxPointerAddress = searchData.endAddress;
	
	ZGMemorySize pointerSize = searchData.pointerSize;
	ZGMemorySize indirectResultsStride = indirectSearchResults.stride;
	for (NSData *resultSet in indirectResultSets)
	{
		NSMutableData *newResultSet = [[NSMutableData alloc] init];
		
		const uint8_t *resultSetBytes = static_cast<const uint8_t *>(resultSet.bytes);
		ZGMemorySize numberOfResults = static_cast<ZGMemorySize>(resultSet.length) / indirectResultsStride;
		
		for (ZGMemorySize resultIndex = 0; resultIndex < numberOfResults; resultIndex++)
		{
			const uint8_t *resultBytes = resultSetBytes + resultIndex * indirectResultsStride;
			
			ZGMemoryAddress address;
			if (!ZGEvaluateIndirectAddress(&address, processTask, resultBytes, headerAddresses, minPointerAddress, maxPointerAddress, regionValues, regionValuesCount, nullptr, nullptr, nullptr, nullptr, nullptr))
			{
				address = 0x0;
			}
			
			switch (pointerSize)
			{
				case sizeof(ZGMemoryAddress):
					[newResultSet appendBytes:&address length:pointerSize];
					break;
				case sizeof(ZG32BitMemoryAddress):
				{
					ZG32BitMemoryAddress halfAddress = static_cast<ZG32BitMemoryAddress>(address);
					[newResultSet appendBytes:&halfAddress length:pointerSize];
					break;
				}
			}
		}
		
		[directResultSets addObject:newResultSet];
	}
	
	for (ZGMemorySize regionIndex = 0; regionIndex < regionValuesCount; regionIndex++)
	{
		ZGRegionValue regionValue = regionValues[regionIndex];
		if (regionValue.bytes != nullptr)
		{
			ZGFreeBytes(regionValue.bytes, regionValue.size);
			regionValues[regionIndex].bytes = nullptr;
		}
	}
	
	free(regionValues);
	regionValues = nullptr;
	
	ZGSearchResults *directSearchResults = [[ZGSearchResults alloc] initWithResultSets:directResultSets resultType:ZGSearchResultTypeDirect dataType:dataType stride:pointerSize unalignedAccess:indirectSearchResults.unalignedAccess];
	
	ZGSearchResults *narrowSearchResults = _ZGNarrowSearchForData(processTask, translated, searchData, delegate, dataType, integerQualifier, functionType, directSearchResults, nullptr, indirectSearchResults);
	
	narrowSearchResults.indirectMaxLevels = indirectSearchResults.indirectMaxLevels;
	narrowSearchResults.headerAddresses = headerAddresses;
	narrowSearchResults.totalStaticSegmentRanges = indirectSearchResults.totalStaticSegmentRanges;
	narrowSearchResults.filePaths = indirectSearchResults.filePaths;
	
	return narrowSearchResults;
}
