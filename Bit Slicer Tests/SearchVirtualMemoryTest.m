/*
 * Copyright (c) 2014 Mayur Pawashe
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

#import <XCTest/XCTest.h>

#import "ZGVirtualMemory.h"
#import "ZGSearchFunctions.h"
#import "ZGSearchData.h"
#import "ZGSearchResults.h"
#import "ZGStoredData.h"
#import "ZGDataValueExtracting.h"

#include <TargetConditionals.h>

@interface SearchVirtualMemoryTest : XCTestCase

@end

@implementation SearchVirtualMemoryTest
{
	ZGMemoryMap _processTask;
	NSData *_data;
	ZGMemorySize _pageSize;
}

- (void)setUp
{
    [super setUp];

#if TARGET_CPU_ARM64
	XCTSkip("Virtual Memory Tests are not supported for arm64 yet");
#endif

	NSBundle *bundle = [NSBundle bundleForClass:[self class]];
	NSString *randomDataPath = [bundle pathForResource:@"random_data" ofType:@""];
	XCTAssertNotNil(randomDataPath);

	_data = [NSData dataWithContentsOfFile:randomDataPath];
	XCTAssertNotNil(_data);

	// We'll use our own process because it's a pain to use another one
	if (!ZGTaskForPID(getpid(), &_processTask))
	{
		XCTFail(@"Failed to grant access to task");
	}

	if (!ZGPageSize(_processTask, &_pageSize))
	{
		XCTFail(@"Failed to retrieve page size from task");
	}

	if (_pageSize * 5 != _data.length)
	{
		XCTFail(@"Page size %llu is not what we expected", _pageSize);
	}
}

- (ZGMemoryAddress)allocateDataIntoProcess
{
	ZGMemoryAddress address = 0x0;
	if (!ZGAllocateMemory(_processTask, &address, _data.length))
	{
		XCTFail(@"Failed to retrieve page size from task");
	}

	XCTAssertTrue(address % _pageSize == 0);

	if (!ZGProtect(_processTask, address, _data.length, VM_PROT_READ | VM_PROT_WRITE))
	{
		XCTFail(@"Failed to memory protect allocated data");
	}

	if (!ZGWriteBytes(_processTask, address, _data.bytes, _data.length))
	{
		XCTFail(@"Failed to write data into pages");
	}

	// Ensure the pages will be split in at least 3 different regions
	if (!ZGProtect(_processTask, address + _pageSize * 1, _pageSize, VM_PROT_ALL))
	{
		XCTFail(@"Failed to change page 2 protection to ALL");
	}
	if (!ZGProtect(_processTask, address + _pageSize * 3, _pageSize, VM_PROT_ALL))
	{
		XCTFail(@"Failed to change page 4 protection to ALL");
	}

	return address;
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
	ZGDeallocatePort(_processTask);

    [super tearDown];
}

/**
 * Tests the basic functionality of finding data in memory.
 *
 * This test:
 * 1. Allocates memory in the process and writes test data to it
 * 2. Creates a search pattern for a specific byte sequence
 * 3. Performs a search for exact matches of the byte sequence
 * 4. Verifies that the allocated memory address is found in the results
 *
 * Memory layout:
 * ┌───────────────────────────────────────────────────────┐
 * │                      Process Memory                    │
 * ├───────────────────────────────────────────────────────┤
 * │                           ...                          │
 * ├───────────────────────────────────────────────────────┤
 * │                                                        │
 * │                    Allocated Memory                    │
 * │                                                        │
 * │  00 B1 17 11 34 03 28 D7 D4 98 4A C2 ... (test data)  │
 * │  ↑                                                     │
 * │  └── Search for this byte sequence                     │
 * │                                                        │
 * ├───────────────────────────────────────────────────────┤
 * │                           ...                          │
 * └───────────────────────────────────────────────────────┘
 */
- (void)testFindingData
{
	ZGMemoryAddress address = [self allocateDataIntoProcess];

	uint8_t firstBytes[] = {0x00, 0xB1, 0x17, 0x11, 0x34, 0x03, 0x28, 0xD7, 0xD4, 0x98, 0x4A, 0xC2};
	void *bytes = malloc(sizeof(firstBytes));
	if (bytes == NULL)
	{
		XCTFail(@"Failed to allocate memory for first bytes...");
	}

	memcpy(bytes, firstBytes, sizeof(firstBytes));

	ZGSearchData *searchData = [[ZGSearchData alloc] initWithSearchValue:bytes dataSize:sizeof(firstBytes) dataAlignment:1 pointerSize:8];

	ZGSearchResults *results = ZGSearchForData(_processTask, searchData, nil, ZGByteArray, 0, ZGEquals);

	__block BOOL foundAddress = NO;
	[results enumerateWithCount:results.count removeResults:NO usingBlock:^(const void *resultAddressData, BOOL *stop) {
		ZGMemoryAddress resultAddress = *(const ZGMemoryAddress *)resultAddressData;
		if (resultAddress == address)
		{
			foundAddress = YES;
			*stop = YES;
		}
	}];

	XCTAssertTrue(foundAddress);
}

- (ZGSearchData *)searchDataFromBytes:(const void *)bytes size:(ZGMemorySize)size dataType:(ZGVariableType)dataType address:(ZGMemoryAddress)address alignment:(ZGMemorySize)alignment
{
	void *copiedBytes = malloc(size);
	if (copiedBytes == NULL)
	{
		XCTFail(@"Failed to allocate memory for copied bytes...");
	}

	memcpy(copiedBytes, bytes, size);

	ZGSearchData *searchData = [[ZGSearchData alloc] initWithSearchValue:copiedBytes dataSize:size dataAlignment:alignment pointerSize:8];
	searchData.beginAddress = address;
	searchData.endAddress = address + _data.length;
	searchData.swappedValue = ZGSwappedValue(ZGProcessTypeX86_64, bytes, dataType, size);

	return searchData;
}

/**
 * Tests searching for 8-bit integers with various search types and operations.
 *
 * This test:
 * 1. Allocates memory and searches for a specific 8-bit value (0xB1)
 * 2. Tests different search operations (equals, not equals, greater than, less than)
 * 3. Tests narrowing search results by modifying memory
 * 4. Tests searching with different protection modes
 * 5. Tests comparing against stored values
 *
 * Memory layout and operations:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │                         Process Memory                           │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                              ...                                 │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                                                                  │
 * │                       Allocated Memory                           │
 * │                                                                  │
 * │  Byte 0   Byte 1   Byte 2   ...                                  │
 * │  ┌────┐   ┌────┐   ┌────┐                                        │
 * │  │ ?? │   │ B1 │   │ ?? │ ...                                    │
 * │  └────┘   └────┘   └────┘                                        │
 * │            ↑                                                     │
 * │            └── Search for this value (0xB1)                      │
 * │                                                                  │
 * │  Initial search finds 89 occurrences of 0xB1                     │
 * │                                                                  │
 * │  Then modify Byte 1:                                             │
 * │  ┌────┐   ┌────┐   ┌────┐                                        │
 * │  │ ?? │   │ B0 │   │ ?? │ ...                                    │
 * │  └────┘   └────┘   └────┘                                        │
 * │            ↑                                                     │
 * │            └── Changed to (0xB0)                                 │
 * │                                                                  │
 * │  Narrowed search now finds 88 occurrences                        │
 * │                                                                  │
 * │  Protection mode tests:                                          │
 * │  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐
 * │  │  Page 1    │ │  Page 2    │ │  Page 3    │ │  Page 4    │ │  Page 5    │
 * │  │ R/W Access │ │ All Access │ │ R/W Access │ │ All Access │ │ R/W Access │
 * │  └────────────┘ └────────────┘ └────────────┘ └────────────┘ └────────────┘
 * │                                                                  │
 * └─────────────────────────────────────────────────────────────────┘
 */
- (void)testInt8Search
{
	ZGMemoryAddress address = [self allocateDataIntoProcess];
	uint8_t valueToFind = 0xB1;

	ZGSearchData *searchData = [self searchDataFromBytes:&valueToFind size:sizeof(valueToFind) dataType:ZGInt8 address:address alignment:1];
	searchData.savedData = [ZGStoredData storedDataFromProcessTask:_processTask beginAddress:searchData.beginAddress endAddress:searchData.endAddress protectionMode:searchData.protectionMode includeSharedMemory:NO];
	XCTAssertNotNil(searchData.savedData);

	ZGSearchResults *equalResults = ZGSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGEquals);
	XCTAssertEqual(equalResults.count, 89U);

	ZGSearchResults *equalSignedResults = ZGSearchForData(_processTask, searchData, nil, ZGInt8, ZGSigned, ZGEquals);
	XCTAssertEqual(equalSignedResults.count, 89U);

	ZGSearchResults *notEqualResults = ZGSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGNotEquals);
	XCTAssertEqual(notEqualResults.count, _data.length - 89U);

	ZGSearchResults *greaterThanResults = ZGSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGGreaterThan);
	XCTAssertEqual(greaterThanResults.count, 6228U);

	ZGSearchResults *lessThanResults = ZGSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGLessThan);
	XCTAssertEqual(lessThanResults.count, 14163U);

	searchData.shouldCompareStoredValues = YES;
	ZGSearchResults *storedEqualResults = ZGSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGEqualsStored);
	XCTAssertEqual(storedEqualResults.count, _data.length);
	searchData.shouldCompareStoredValues = NO;

	if (!ZGWriteBytes(_processTask, address + 0x1, (uint8_t []){valueToFind - 1}, 0x1))
	{
		XCTFail(@"Failed to write 2nd byte");
	}

	ZGSearchResults *emptyResults = [[ZGSearchResults alloc] initWithResultSets:@[] resultType:ZGSearchResultTypeDirect dataType:ZGInt8 stride:sizeof(ZGMemoryAddress) unalignedAccess:NO];

	ZGSearchResults *equalNarrowResults = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGInt8, ZGUnsigned, ZGEquals, emptyResults, equalResults);
	XCTAssertEqual(equalNarrowResults.count, 88U);

	ZGSearchResults *notEqualNarrowResults = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGInt8, ZGUnsigned, ZGNotEquals, emptyResults, equalResults);
	XCTAssertEqual(notEqualNarrowResults.count, 1U);

	ZGSearchResults *greaterThanNarrowResults = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGInt8, ZGUnsigned, ZGGreaterThan, emptyResults, equalResults);
	XCTAssertEqual(greaterThanNarrowResults.count, 0U);

	ZGSearchResults *lessThanNarrowResults = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGInt8, ZGUnsigned, ZGLessThan, emptyResults, equalResults);
	XCTAssertEqual(lessThanNarrowResults.count, 1U);

	searchData.shouldCompareStoredValues = YES;
	ZGSearchResults *storedEqualResultsNarrowed = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGInt8, ZGUnsigned, ZGEqualsStored, emptyResults, storedEqualResults);
	XCTAssertEqual(storedEqualResultsNarrowed.count, _data.length - 1);
	searchData.shouldCompareStoredValues = NO;

	searchData.protectionMode = ZGProtectionExecute;

	ZGSearchResults *equalExecuteResults = ZGSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGEquals);
	XCTAssertEqual(equalExecuteResults.count, 34U);

	// this will ignore the 2nd byte we changed since it's out of range
	ZGSearchResults *equalExecuteNarrowResults = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGInt8, ZGUnsigned, ZGEquals, emptyResults, equalResults);
	XCTAssertEqual(equalExecuteNarrowResults.count, 34U);

	ZGMemoryAddress *addressesRemoved = calloc(2, sizeof(*addressesRemoved));
	if (addressesRemoved == NULL) XCTFail(@"Failed to allocate memory for addressesRemoved");
	XCTAssertEqual(sizeof(ZGMemoryAddress), 8U);

	__block NSUInteger addressIndex = 0;
	[equalExecuteNarrowResults enumerateWithCount:2 removeResults:YES usingBlock:^(const void *resultAddressData, __unused BOOL *stop) {
		ZGMemoryAddress resultAddress = *(const ZGMemoryAddress *)resultAddressData;
		addressesRemoved[addressIndex] = resultAddress;
		addressIndex++;
	}];

	// first results do not have to be ordered
	addressesRemoved[0] ^= addressesRemoved[1];
	addressesRemoved[1] ^= addressesRemoved[0];
	addressesRemoved[0] ^= addressesRemoved[1];

	ZGSearchResults *equalExecuteNarrowTwiceResults = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGInt8, ZGUnsigned, ZGEquals, emptyResults, equalExecuteNarrowResults);
	XCTAssertEqual(equalExecuteNarrowTwiceResults.count, 32U);

	ZGSearchResults *searchResultsRemoved = [[ZGSearchResults alloc] initWithResultSets:@[[NSData dataWithBytes:addressesRemoved length:2 * sizeof(*addressesRemoved)]] resultType:ZGSearchResultTypeDirect dataType:ZGInt8 stride:8 unalignedAccess:NO];

	ZGSearchResults *equalExecuteNarrowTwiceAgainResults = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGInt8, ZGUnsigned, ZGEquals, searchResultsRemoved, equalExecuteNarrowResults);
	XCTAssertEqual(equalExecuteNarrowTwiceAgainResults.count, 34U);

	free(addressesRemoved);

	searchData.shouldCompareStoredValues = YES;
	ZGSearchResults *storedEqualExecuteNarrowResults = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGInt8, ZGUnsigned, ZGEqualsStored, emptyResults, storedEqualResults);
	XCTAssertEqual(storedEqualExecuteNarrowResults.count, _pageSize * 2);
	searchData.shouldCompareStoredValues = NO;

	if (!ZGWriteBytes(_processTask, address + 0x1, (uint8_t []){valueToFind}, 0x1))
	{
		XCTFail(@"Failed to revert 2nd byte");
	}
}

/**
 * Tests searching for 16-bit integers with alignment considerations and endianness.
 *
 * This test:
 * 1. Allocates memory and searches for a specific 16-bit value (-13398, which is 0xCBAA in hex)
 * 2. Tests searching with proper alignment (2-byte boundaries)
 * 3. Tests searching with misaligned addresses
 * 4. Tests searching with no alignment restrictions
 * 5. Tests searching with swapped byte order (endianness)
 *
 * Memory layout and alignment:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │                         Process Memory                           │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                              ...                                 │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                                                                  │
 * │                       Allocated Memory                           │
 * │                                                                  │
 * │  Address:   0x...00   0x...01   0x...02   0x...03                │
 * │             ┌────────┬────────┐┌────────┬────────┐               │
 * │  Data:      │   AA   │   CB   ││   ??   │   ??   │...            │
 * │             └────────┴────────┘└────────┴────────┘               │
 * │                   ↑                                              │
 * │                   └── 16-bit value: 0xCBAA (-13398)              │
 * │                                                                  │
 * │  Aligned search (2-byte boundary):                               │
 * │  Finds the value at 0x...00                                      │
 * │                                                                  │
 * │  At offset 0x291:                                                │
 * │  Address:   0x...90   0x...91   0x...92   0x...93                │
 * │             ┌────────┬────────┐┌────────┬────────┐               │
 * │  Data:      │   ??   │   AA   ││   CB   │   ??   │...            │
 * │             └────────┴────────┘└────────┴────────┘               │
 * │                        ↑  ↑                                      │
 * │                        │  └── Misaligned 16-bit value            │
 * │                        └── Odd address (0x...91)                 │
 * │                                                                  │
 * │  No alignment search:                                            │
 * │  Finds both aligned (0x...00) and misaligned (0x...91) values    │
 * │                                                                  │
 * │  Swapped endianness:                                             │
 * │  Searches for 0xAABC instead of 0xCBAA                           │
 * │                                                                  │
 * └─────────────────────────────────────────────────────────────────┘
 */
- (void)testInt16Search
{
	ZGMemoryAddress address = [self allocateDataIntoProcess];
	int16_t valueToFind = -13398; // AA CB

	ZGSearchData *searchData = [self searchDataFromBytes:&valueToFind size:sizeof(valueToFind) dataType:ZGInt16 address:address alignment:sizeof(valueToFind)];

	ZGSearchResults *equalResults = ZGSearchForData(_processTask, searchData, nil, ZGInt16, ZGSigned, ZGEquals);
	XCTAssertEqual(equalResults.count, 1U);

	searchData.beginAddress += 0x291;
	ZGSearchResults *misalignedEqualResults = ZGSearchForData(_processTask, searchData, nil, ZGInt16, ZGSigned, ZGEquals);
	XCTAssertEqual(misalignedEqualResults.count, 1U);
	searchData.beginAddress -= 0x291;

	ZGSearchData *noAlignmentSearchData = [self searchDataFromBytes:&valueToFind size:sizeof(valueToFind) dataType:ZGInt16 address:address alignment:1];
	ZGSearchResults *noAlignmentEqualResults = ZGSearchForData(_processTask, noAlignmentSearchData, nil, ZGInt16, ZGSigned, ZGEquals);
	XCTAssertEqual(noAlignmentEqualResults.count, 2U);

	ZGMemoryAddress oldEndAddress = searchData.endAddress;
	searchData.beginAddress += 0x291;
	searchData.endAddress = searchData.beginAddress + 0x3;

	ZGSearchResults *noAlignmentRestrictedEqualResults = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGInt16, ZGSigned, ZGEquals, [[ZGSearchResults alloc] initWithResultSets:@[] resultType:ZGSearchResultTypeDirect dataType:ZGInt16 stride:sizeof(ZGMemoryAddress) unalignedAccess:YES], noAlignmentEqualResults);
	XCTAssertEqual(noAlignmentRestrictedEqualResults.count, 1U);

	searchData.beginAddress -= 0x291;
	searchData.endAddress = oldEndAddress;

	int16_t swappedValue = (int16_t)CFSwapInt16((uint16_t)valueToFind);
	ZGSearchData *swappedSearchData = [self searchDataFromBytes:&swappedValue size:sizeof(swappedValue) dataType:ZGInt16 address:address alignment:sizeof(swappedValue)];
	swappedSearchData.bytesSwapped = YES;

	ZGSearchResults *equalSwappedResults = ZGSearchForData(_processTask, swappedSearchData, nil, ZGInt16, ZGUnsigned, ZGEquals);
	XCTAssertEqual(equalSwappedResults.count, 1U);
}

/**
 * Tests searching for 32-bit integers with range bounds, endianness, and linear transformations.
 *
 * This test:
 * 1. Allocates memory and searches for 32-bit values within specific ranges
 * 2. Tests searching with swapped byte order (big endian)
 * 3. Tests linear transformations on stored values (ax + b)
 * 4. Tests narrowing search results based on transformed values
 *
 * Memory layout and operations:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │                         Process Memory                           │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                              ...                                 │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                                                                  │
 * │                       Allocated Memory                           │
 * │                                                                  │
 * │  Initial search: Find values > -300,000,000                      │
 * │  With upper bound: 300,000,000                                   │
 * │  Finds 746 matches                                               │
 * │                                                                  │
 * │  Swapped endianness search: Find values < -600,000,000           │
 * │  Finds 354 matches                                               │
 * │                                                                  │
 * │  At offset 0x54:                                                 │
 * │  ┌────────────────────────────┐                                  │
 * │  │ Original value (big endian)│                                  │
 * │  └────────────────────────────┘                                  │
 * │                ↓                                                 │
 * │  ┌────────────────────────────┐                                  │
 * │  │ Read and convert to host   │                                  │
 * │  └────────────────────────────┘                                  │
 * │                ↓                                                 │
 * │  Linear transformation: ax + b                                   │
 * │  Where a = 3 (multiplicative constant)                           │
 * │        b = 10 (additive constant)                                │
 * │                ↓                                                 │
 * │  ┌────────────────────────────┐                                  │
 * │  │ Transformed value          │                                  │
 * │  │ (original * 3 + 10)        │                                  │
 * │  └────────────────────────────┘                                  │
 * │                ↓                                                 │
 * │  ┌────────────────────────────┐                                  │
 * │  │ Convert to big endian      │                                  │
 * │  │ and write back to memory   │                                  │
 * │  └────────────────────────────┘                                  │
 * │                                                                  │
 * │  Narrow search using linear transformation equation:             │
 * │  new_value = old_value * 3 + 10                                  │
 * │  Finds exactly 1 match                                           │
 * │                                                                  │
 * └─────────────────────────────────────────────────────────────────┘
 */
- (void)testInt32Search
{
	ZGMemoryAddress address = [self allocateDataIntoProcess];
	int32_t value = -300000000;
	ZGSearchData *searchData = [self searchDataFromBytes:&value size:sizeof(value) dataType:ZGInt32 address:address alignment:sizeof(value)];

	int32_t *topBound = malloc(sizeof(*topBound));
	*topBound = 300000000;
	searchData.rangeValue = topBound;

	ZGSearchResults *betweenResults = ZGSearchForData(_processTask, searchData, nil, ZGInt32, ZGSigned, ZGGreaterThan);
	XCTAssertEqual(betweenResults.count, 746U);

	int32_t *belowBound = malloc(sizeof(*belowBound));
	*belowBound = -600000000;
	searchData.rangeValue = belowBound;

	searchData.bytesSwapped = YES;

	ZGSearchResults *betweenSwappedResults = ZGSearchForData(_processTask, searchData, nil, ZGInt32, ZGSigned, ZGLessThan);
	XCTAssertEqual(betweenSwappedResults.count, 354U);

	searchData.savedData = [ZGStoredData storedDataFromProcessTask:_processTask beginAddress:searchData.beginAddress endAddress:searchData.endAddress protectionMode:searchData.protectionMode includeSharedMemory:NO];
	XCTAssertNotNil(searchData.savedData);

	int32_t *integerReadReference = NULL;
	ZGMemorySize integerSize = sizeof(*integerReadReference);
	if (!ZGReadBytes(_processTask, address + 0x54, (void **)&integerReadReference, &integerSize))
	{
		XCTFail(@"Failed to read integer at offset 0x54");
	}

	int32_t integerRead = (int32_t)CFSwapInt32BigToHost(*(uint32_t *)integerReadReference);

	ZGFreeBytes(integerReadReference, integerSize);

	int32_t *additiveConstant = malloc(sizeof(*additiveConstant));
	if (additiveConstant == NULL) XCTFail(@"Failed to malloc addititive constant");
	*additiveConstant = 10;

	int32_t *multiplicativeConstant = malloc(sizeof(*multiplicativeConstant));
	if (multiplicativeConstant == NULL) XCTFail(@"Failed to malloc multiplicative constant");
	*multiplicativeConstant = 3;

	searchData.additiveConstant = additiveConstant;
	searchData.multiplicativeConstant = multiplicativeConstant;
	searchData.shouldCompareStoredValues = YES;

	int32_t alteredInteger = (int32_t)CFSwapInt32HostToBig((uint32_t)((integerRead * *multiplicativeConstant + *additiveConstant)));
	if (!ZGWriteBytesIgnoringProtection(_processTask, address + 0x54, &alteredInteger, sizeof(alteredInteger)))
	{
		XCTFail(@"Failed to write altered integer at offset 0x54");
	}

	ZGSearchResults *narrowedSwappedAndStoredResults = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGInt32, ZGSigned, ZGEqualsStoredLinear, [[ZGSearchResults alloc] initWithResultSets:@[] resultType:ZGSearchResultTypeDirect dataType:ZGInt32 stride:sizeof(ZGMemoryAddress) unalignedAccess:NO], betweenSwappedResults);
	XCTAssertEqual(narrowedSwappedAndStoredResults.count, 1U);
}

/**
 * Tests searching for 64-bit integers with alignment and endianness considerations.
 *
 * This test:
 * 1. Allocates memory and searches for 64-bit values less than a specific value
 * 2. Tests searching with different alignment requirements (8-byte vs 4-byte)
 * 3. Tests searching with swapped byte order (big endian)
 *
 * Memory layout and alignment:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │                         Process Memory                           │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                              ...                                 │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                                                                  │
 * │                       Allocated Memory                           │
 * │                                                                  │
 * │  8-byte aligned addresses:                                       │
 * │  ┌───────────────────────────────────────────┐                   │
 * │  │ 64-bit value at 0x...00, 0x...08, etc.    │                   │
 * │  └───────────────────────────────────────────┘                   │
 * │                                                                  │
 * │  Search value: 0x0B765697AFAA3400                                │
 * │  Search operation: Less Than                                     │
 * │                                                                  │
 * │  With 8-byte alignment:                                          │
 * │  Finds 132 matches                                               │
 * │                                                                  │
 * │  With 4-byte alignment:                                          │
 * │  ┌───────────────────┐ ┌───────────────────┐                     │
 * │  │ 64-bit at 0x...00 │ │ 64-bit at 0x...04 │                     │
 * │  └───────────────────┘ └───────────────────┘                     │
 * │  ┌───────────────────┐ ┌───────────────────┐                     │
 * │  │ 64-bit at 0x...08 │ │ 64-bit at 0x...0C │                     │
 * │  └───────────────────┘ └───────────────────┘                     │
 * │                                                                  │
 * │  Finds 256 matches (more because of 4-byte alignment)            │
 * │                                                                  │
 * │  With big endian (swapped bytes):                                │
 * │  Search for 0x00343AAFA7975670B (byte-swapped)                   │
 * │  Finds 101 matches                                               │
 * │                                                                  │
 * └─────────────────────────────────────────────────────────────────┘
 */
- (void)testInt64Search
{
	ZGMemoryAddress address = [self allocateDataIntoProcess];
	uint64_t value = 0x0B765697AFAA3400;

	ZGSearchData *searchData = [self searchDataFromBytes:&value size:sizeof(value) dataType:ZGInt64 address:address alignment:sizeof(value)];
	ZGSearchResults *results = ZGSearchForData(_processTask, searchData, nil, ZGInt64, ZGUnsigned, ZGLessThan);
	XCTAssertEqual(results.count, 132U);

	searchData.dataAlignment = sizeof(uint32_t);

	ZGSearchResults *resultsWithHalfAlignment = ZGSearchForData(_processTask, searchData, nil, ZGInt64, ZGUnsigned, ZGLessThan);
	XCTAssertEqual(resultsWithHalfAlignment.count, 256U);

	searchData.dataAlignment = sizeof(uint64_t);

	searchData.bytesSwapped = YES;
	ZGSearchResults *bigEndianResults = ZGSearchForData(_processTask, searchData, nil, ZGInt64, ZGUnsigned, ZGLessThan);
	XCTAssertEqual(bigEndianResults.count, 101U);
}

/**
 * Tests searching for floating-point values with epsilon and endianness considerations.
 *
 * This test:
 * 1. Allocates memory and searches for a specific float value (-0.036687)
 * 2. Tests searching with different epsilon values (precision tolerances)
 * 3. Tests searching with swapped byte order (big endian)
 *
 * Memory layout and epsilon concept:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │                         Process Memory                           │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                              ...                                 │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                                                                  │
 * │                       Allocated Memory                           │
 * │                                                                  │
 * │  Search value: -0.036687                                         │
 * │                                                                  │
 * │  With small epsilon (0.0000001):                                 │
 * │  ┌─────────────────────────────────────────────────┐            │
 * │  │ Matches values between -0.0366871 and -0.0366869 │            │
 * │  └─────────────────────────────────────────────────┘            │
 * │  Finds 1 exact match                                             │
 * │                                                                  │
 * │  With larger epsilon (0.01):                                     │
 * │  ┌─────────────────────────────────────────────────┐            │
 * │  │ Matches values between -0.046687 and -0.026687  │            │
 * │  └─────────────────────────────────────────────────┘            │
 * │  Finds 5 matches (more tolerance)                                │
 * │                                                                  │
 * │  Epsilon visualization:                                          │
 * │                                                                  │
 * │  Small epsilon:                                                  │
 * │       -0.0366871 ← -0.036687 → -0.0366869                        │
 * │                    ↑                                             │
 * │                 Target                                           │
 * │                                                                  │
 * │  Large epsilon:                                                  │
 * │       -0.046687 ←---- -0.036687 ---→ -0.026687                   │
 * │                         ↑                                        │
 * │                      Target                                      │
 * │                                                                  │
 * │  Big endian test:                                                │
 * │  Search for 7522.56 with swapped bytes                           │
 * │  With small epsilon: Finds 1 match                               │
 * │  With large epsilon (100.0): Finds 2 matches                     │
 * │                                                                  │
 * └─────────────────────────────────────────────────────────────────┘
 */
- (void)testFloatSearch
{
	ZGMemoryAddress address = [self allocateDataIntoProcess];
	float value = -0.036687f;
	ZGSearchData *searchData = [self searchDataFromBytes:&value size:sizeof(value) dataType:ZGFloat address:address alignment:sizeof(value)];
	searchData.epsilon = 0.0000001;

	ZGSearchResults *results = ZGSearchForData(_processTask, searchData, nil, ZGFloat, 0, ZGEquals);
	XCTAssertEqual(results.count, 1U);

	searchData.epsilon = 0.01;
	ZGSearchResults *resultsWithBigEpsilon = ZGSearchForData(_processTask, searchData, nil, ZGFloat, 0, ZGEquals);
	XCTAssertEqual(resultsWithBigEpsilon.count, 5U);

	float *bigEndianValue = malloc(sizeof(*bigEndianValue));
	if (bigEndianValue == NULL) XCTFail(@"bigEndianValue malloc'd is NULL");
	*bigEndianValue = 7522.56f;

	searchData.searchValue = bigEndianValue;
	searchData.bytesSwapped = YES;

	ZGSearchResults *bigEndianResults = ZGSearchForData(_processTask, searchData, nil, ZGFloat, 0, ZGEquals);
	XCTAssertEqual(bigEndianResults.count, 1U);

	searchData.epsilon = 100.0;
	ZGSearchResults *bigEndianResultsWithBigEpsilon = ZGSearchForData(_processTask, searchData, nil, ZGFloat, 0, ZGEquals);
	XCTAssertEqual(bigEndianResultsWithBigEpsilon.count, 2U);
}

/**
 * Tests searching for double-precision floating-point values with alignment, epsilon, and endianness.
 *
 * This test:
 * 1. Allocates memory and searches for double values greater than 100.0
 * 2. Tests searching with different alignment requirements (8-byte vs 4-byte)
 * 3. Tests searching with swapped byte order (big endian) and large epsilon
 *
 * Memory layout and operations:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │                         Process Memory                           │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                              ...                                 │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                                                                  │
 * │                       Allocated Memory                           │
 * │                                                                  │
 * │  Search value: 100.0                                             │
 * │  Search operation: Greater Than                                  │
 * │                                                                  │
 * │  With 8-byte alignment (natural for double):                     │
 * │  ┌───────────────────────────────────────────┐                   │
 * │  │ 64-bit doubles at 0x...00, 0x...08, etc.  │                   │
 * │  └───────────────────────────────────────────┘                   │
 * │  Finds 616 matches                                               │
 * │                                                                  │
 * │  With 4-byte alignment (half-aligned):                           │
 * │  ┌───────────────────┐ ┌───────────────────┐                     │
 * │  │ Double at 0x...00 │ │ Double at 0x...04 │                     │
 * │  └───────────────────┘ └───────────────────┘                     │
 * │  ┌───────────────────┐ ┌───────────────────┐                     │
 * │  │ Double at 0x...08 │ │ Double at 0x...0C │                     │
 * │  └───────────────────┘ └───────────────────┘                     │
 * │                                                                  │
 * │  Restricted to first page only                                   │
 * │  Finds 250 matches                                               │
 * │                                                                  │
 * │  Big endian test with large epsilon:                             │
 * │  Search value: 4.56194e56 (very large number)                    │
 * │  Epsilon: 1e57 (extremely large tolerance)                       │
 * │                                                                  │
 * │  Epsilon visualization:                                          │
 * │                                                                  │
 * │  Target: 4.56194e56                                              │
 * │  Range: -9.5e56 to 1.05e57                                       │
 * │  │←─────────────────┼─────────────────→│                         │
 * │  -9.5e56        4.56194e56          1.05e57                      │
 * │                    ↑                                             │
 * │                 Target                                           │
 * │                                                                  │
 * │  Finds 302 matches with swapped bytes and large epsilon          │
 * │                                                                  │
 * └─────────────────────────────────────────────────────────────────┘
 */
- (void)testDoubleSearch
{
	ZGMemoryAddress address = [self allocateDataIntoProcess];
	double value = 100.0;

	ZGSearchData *searchData = [self searchDataFromBytes:&value size:sizeof(value) dataType:ZGDouble address:address alignment:sizeof(value)];

	ZGSearchResults *results = ZGSearchForData(_processTask, searchData, nil, ZGDouble, 0, ZGGreaterThan);
	XCTAssertEqual(results.count, 616U);

	searchData.dataAlignment = sizeof(float);
	searchData.endAddress = searchData.beginAddress + _pageSize;

	ZGSearchResults *resultsWithHalfAlignment = ZGSearchForData(_processTask, searchData, nil, ZGDouble, 0, ZGGreaterThan);
	XCTAssertEqual(resultsWithHalfAlignment.count, 250U);

	searchData.dataAlignment = sizeof(double);

	double *newValue = malloc(sizeof(*newValue));
	if (newValue == NULL) XCTFail(@"Failed to malloc newValue");
	*newValue = 4.56194e56;

	searchData.searchValue = newValue;
	searchData.bytesSwapped = YES;
	searchData.epsilon = 1e57;

	ZGSearchResults *swappedResults = ZGSearchForData(_processTask, searchData, nil, ZGDouble, 0, ZGEquals);
	XCTAssertEqual(swappedResults.count, 302U);
}

/**
 * Tests searching for 8-bit (ASCII) strings with case sensitivity and null termination.
 *
 * This test:
 * 1. Allocates memory and writes "hello" strings at different locations
 * 2. Tests searching for exact string matches
 * 3. Tests narrowing results by modifying strings
 * 4. Tests case-insensitive string searching
 * 5. Tests searching with and without null terminators
 *
 * Memory layout and string operations:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │                         Process Memory                           │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                              ...                                 │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                                                                  │
 * │                       Allocated Memory                           │
 * │                                                                  │
 * │  Initial string placement:                                       │
 * │                                                                  │
 * │  At offset 96:                                                   │
 * │  ┌───┬───┬───┬───┬───┐                                           │
 * │  │ h │ e │ l │ l │ o │                                           │
 * │  └───┴───┴───┴───┴───┘                                           │
 * │                                                                  │
 * │  At offset 150:                                                  │
 * │  ┌───┬───┬───┬───┬───┐                                           │
 * │  │ h │ e │ l │ l │ o │                                           │
 * │  └───┴───┴───┴───┴───┘                                           │
 * │                                                                  │
 * │  At offset 5000:                                                 │
 * │  ┌───┬───┬───┬───┬───┬───┐                                       │
 * │  │ h │ e │ l │ l │ o │ \0│                                       │
 * │  └───┴───┴───┴───┴───┴───┘                                       │
 * │                                                                  │
 * │  Initial search finds all 3 occurrences                          │
 * │                                                                  │
 * │  Modification 1: Change first character at offset 96             │
 * │  ┌───┬───┬───┬───┬───┐                                           │
 * │  │ m │ e │ l │ l │ o │                                           │
 * │  └───┴───┴───┴───┴───┘                                           │
 * │                                                                  │
 * │  Narrowed search finds 2 remaining "hello" strings               │
 * │                                                                  │
 * │  Modification 2: Include null terminator in search               │
 * │  Only the string at offset 5000 has a null terminator            │
 * │  Narrowed search finds 1 match                                   │
 * │                                                                  │
 * │  Modification 3: Change case at offset 150                       │
 * │  ┌───┬───┬───┬───┬───┐                                           │
 * │  │ H │ e │ L │ L │ o │                                           │
 * │  └───┴───┴───┴───┴───┘                                           │
 * │                                                                  │
 * │  Case-insensitive search finds 2 matches                         │
 * │                                                                  │
 * │  Modification 4: Change first character at offset 150            │
 * │  ┌───┬───┬───┬───┬───┐                                           │
 * │  │ M │ e │ L │ L │ o │                                           │
 * │  └───┴───┴───┴───┴───┘                                           │
 * │                                                                  │
 * │  Case-insensitive "not equals" search finds 1 match              │
 * │                                                                  │
 * └─────────────────────────────────────────────────────────────────┘
 */
- (void)test8BitStringSearch
{
	ZGMemoryAddress address = [self allocateDataIntoProcess];

	char *hello = "hello";
	if (!ZGWriteBytes(_processTask, address + 96, hello, strlen(hello))) XCTFail(@"Failed to write hello string 1");
	if (!ZGWriteBytes(_processTask, address + 150, hello, strlen(hello))) XCTFail(@"Failed to write hello string 2");
	if (!ZGWriteBytes(_processTask, address + 5000, hello, strlen(hello) + 1)) XCTFail(@"Failed to write hello string 3");

	ZGSearchData *searchData = [self searchDataFromBytes:hello size:strlen(hello) + 1 dataType:ZGString8 address:address alignment:1];
	searchData.dataSize -= 1; // ignore null terminator for now

	ZGSearchResults *results = ZGSearchForData(_processTask, searchData, nil, ZGString8, 0, ZGEquals);
	XCTAssertEqual(results.count, 3U);

	if (!ZGWriteBytes(_processTask, address + 96, "m", 1)) XCTFail(@"Failed to write m");

	ZGSearchResults *narrowedResults = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGString8, 0, ZGEquals, [[ZGSearchResults alloc] initWithResultSets:@[] resultType:ZGSearchResultTypeDirect dataType:ZGString8 stride:sizeof(ZGMemoryAddress) unalignedAccess:NO], results);
	XCTAssertEqual(narrowedResults.count, 2U);

	// .shouldIncludeNullTerminator field isn't "really" used for search functions; it's just a hint for UI state
	searchData.dataSize++;

	ZGSearchResults *narrowedTerminatedResults = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGString8, 0, ZGEquals, [[ZGSearchResults alloc] initWithResultSets:@[] resultType:ZGSearchResultTypeDirect dataType:ZGString8 stride:sizeof(ZGMemoryAddress) unalignedAccess:NO], narrowedResults);
	XCTAssertEqual(narrowedTerminatedResults.count, 1U);

	searchData.dataSize--;
	if (!ZGWriteBytes(_processTask, address + 150, "HeLLo", strlen(hello))) XCTFail(@"Failed to write mixed case string");
	searchData.shouldIgnoreStringCase = YES;

	ZGSearchResults *narrowedIgnoreCaseResults = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGString8, 0, ZGEquals, [[ZGSearchResults alloc] initWithResultSets:@[] resultType:ZGSearchResultTypeDirect dataType:ZGString8 stride:sizeof(ZGMemoryAddress) unalignedAccess:NO], narrowedResults);
	XCTAssertEqual(narrowedIgnoreCaseResults.count, 2U);

	if (!ZGWriteBytes(_processTask, address + 150, "M", 1)) XCTFail(@"Failed to write capital M");

	ZGSearchResults *narrowedIgnoreCaseNotEqualsResults = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGString8, 0, ZGNotEquals, [[ZGSearchResults alloc] initWithResultSets:@[] resultType:ZGSearchResultTypeDirect dataType:ZGString8 stride:sizeof(ZGMemoryAddress) unalignedAccess:NO], narrowedIgnoreCaseResults);
	XCTAssertEqual(narrowedIgnoreCaseNotEqualsResults.count, 1U);

	searchData.shouldIgnoreStringCase = NO;

	ZGSearchResults *equalResultsAgain = ZGSearchForData(_processTask, searchData, nil, ZGString8, 0, ZGEquals);
	XCTAssertEqual(equalResultsAgain.count, 1U);

	searchData.beginAddress = address + _pageSize;
	searchData.endAddress = address + _pageSize * 2;

	ZGSearchResults *notEqualResults = ZGSearchForData(_processTask, searchData, nil, ZGString8, 0, ZGNotEquals);
	XCTAssertEqual(notEqualResults.count, _pageSize - 1 - (strlen(hello) - 1)); // take account for bytes at end that won't be compared
}

/**
 * Tests searching for 16-bit (Unicode) strings with various encodings, case sensitivity, and null termination.
 *
 * This test:
 * 1. Allocates memory and writes UTF-16 strings at different locations
 * 2. Tests searching with different alignment requirements
 * 3. Tests case-insensitive string searching
 * 4. Tests searching with different encodings (little endian vs big endian)
 * 5. Tests searching with and without null terminators
 *
 * Memory layout and string operations:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │                         Process Memory                           │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                              ...                                 │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                                                                  │
 * │                       Allocated Memory                           │
 * │                                                                  │
 * │  UTF-16 Little Endian strings:                                   │
 * │                                                                  │
 * │  At offsets 96, 150, 5000, 6001:                                 │
 * │  ┌────┬────┬────┬────┬────┬────┬────┬────┬────┬────┐             │
 * │  │ h  │    │ e  │    │ l  │    │ l  │    │ o  │    │             │
 * │  └────┴────┴────┴────┴────┴────┴────┴────┴────┴────┘             │
 * │                                                                  │
 * │  Initial search finds all 4 occurrences                          │
 * │                                                                  │
 * │  Alignment tests:                                                │
 * │  - With 2-byte alignment (natural for UTF-16): 4 matches         │
 * │  - With 1-byte alignment (unaligned): 4 matches                  │
 * │                                                                  │
 * │  String replacement at offset 5000:                              │
 * │  ┌────┬────┬────┬────┬────┬────┐                                 │
 * │  │ m  │    │ o  │    │ o  │    │                                 │
 * │  └────┴────┴────┴────┴────┴────┘                                 │
 * │  Narrowed search finds 1 match for "moo"                         │
 * │                                                                  │
 * │  Case sensitivity test at offset 5000:                           │
 * │  ┌────┬────┬────┬────┬────┬────┐                                 │
 * │  │ M  │    │ o  │    │ O  │    │                                 │
 * │  └────┴────┴────┴────┴────┴────┘                                 │
 * │  Case-insensitive search still finds 1 match                     │
 * │                                                                  │
 * │  String replacement at offset 5000:                              │
 * │  ┌────┬────┬────┬────┬────┬────┐                                 │
 * │  │ n  │    │ o  │    │ o  │    │                                 │
 * │  └────┴────┴────┴────┴────┴────┘                                 │
 * │  Case-insensitive search for "moo" finds 0 matches               │
 * │                                                                  │
 * │  Big endian test at offset 7000:                                 │
 * │  ┌────┬────┬────┬────┬────┬────┬────┬────┬────┬────┐             │
 * │  │    │ h  │    │ e  │    │ l  │    │ l  │    │ o  │             │
 * │  └────┴────┴────┴────┴────┴────┴────┴────┴────┴────┘             │
 * │                                                                  │
 * │  Byte-swapped search finds 1 match                               │
 * │                                                                  │
 * │  First character change at offset 7000:                          │
 * │  ┌────┬────┬────┬────┬────┬────┬────┬────┬────┬────┐             │
 * │  │    │ H  │    │ e  │    │ l  │    │ l  │    │ o  │             │
 * │  └────┴────┴────┴────┴────┴────┴────┴────┴────┴────┘             │
 * │                                                                  │
 * │  Case-sensitive search finds 0 matches                           │
 * │  Case-insensitive search finds 1 match                           │
 * │                                                                  │
 * │  Null terminator tests:                                          │
 * │  Adding null terminator at offset 7000+length:                   │
 * │  ┌────┬────┬────┬────┬────┬────┬────┬────┬────┬────┬────┬────┐   │
 * │  │    │ H  │    │ e  │    │ l  │    │ l  │    │ o  │    │ \0 │   │
 * │  └────┴────┴────┴────┴────┴────┴────┴────┴────┴────┴────┴────┘   │
 * │                                                                  │
 * │  Search including null terminator finds 1 match                  │
 * │                                                                  │
 * └─────────────────────────────────────────────────────────────────┘
 */
- (void)test16BitStringSearch
{
	ZGMemoryAddress address = [self allocateDataIntoProcess];

	NSString *helloString = @"hello";
	unichar *helloBytes = calloc(helloString.length + 1, sizeof(*helloBytes));
	if (helloBytes == NULL) XCTFail(@"Failed to write calloc hello bytes");

	[helloString getBytes:helloBytes maxLength:sizeof(*helloBytes) * helloString.length usedLength:NULL encoding:NSUTF16LittleEndianStringEncoding options:NSStringEncodingConversionAllowLossy range:NSMakeRange(0, helloString.length) remainingRange:NULL];

	size_t helloLength = helloString.length * sizeof(unichar);

	if (!ZGWriteBytes(_processTask, address + 96, helloBytes, helloLength)) XCTFail(@"Failed to write hello string 1");
	if (!ZGWriteBytes(_processTask, address + 150, helloBytes, helloLength)) XCTFail(@"Failed to write hello string 2");
	if (!ZGWriteBytes(_processTask, address + 5000, helloBytes, helloLength)) XCTFail(@"Failed to write hello string 3");
	if (!ZGWriteBytes(_processTask, address + 6001, helloBytes, helloLength)) XCTFail(@"Failed to write hello string 4");

	ZGSearchData *searchData = [self searchDataFromBytes:helloBytes size:helloLength + sizeof(unichar) dataType:ZGString16 address:address alignment:sizeof(unichar)];
	searchData.dataSize -= sizeof(unichar);

	ZGSearchResults *equalResults = ZGSearchForData(_processTask, searchData, nil, ZGString16, 0, ZGEquals);
	XCTAssertEqual(equalResults.count, 4U);

	ZGSearchResults *notEqualResults = ZGSearchForData(_processTask, searchData, nil, ZGString16, 0, ZGNotEquals);
	XCTAssertEqual(notEqualResults.count, _data.length / sizeof(unichar) - 3 - 4*5);

	searchData.dataAlignment = 1;

	ZGSearchResults *equalResultsWithNoAlignment = ZGSearchForData(_processTask, searchData, nil, ZGString16, 0, ZGEquals);
	XCTAssertEqual(equalResultsWithNoAlignment.count, 4U);

	searchData.dataAlignment = 2;

	NSString *mooString = @"moo";
	unichar *mooBytes = calloc(mooString.length + 1, sizeof(*mooBytes));
	if (mooBytes == NULL) XCTFail(@"Failed to write calloc moo bytes");

	[mooString getBytes:mooBytes maxLength:sizeof(*mooBytes) * mooString.length usedLength:NULL encoding:NSUTF16LittleEndianStringEncoding options:NSStringEncodingConversionAllowLossy range:NSMakeRange(0, mooString.length) remainingRange:NULL];

	size_t mooLength = mooString.length * sizeof(unichar);
	if (!ZGWriteBytes(_processTask, address + 5000, mooBytes, mooLength)) XCTFail(@"Failed to write moo string");

	ZGSearchData *mooSearchData = [self searchDataFromBytes:mooBytes size:mooLength dataType:ZGString16 address:address alignment:sizeof(unichar)];

	ZGSearchResults *equalNarrowedResults = ZGNarrowSearchForData(_processTask, NO, mooSearchData, nil, ZGString16, 0, ZGEquals, [[ZGSearchResults alloc] initWithResultSets:@[] resultType:ZGSearchResultTypeDirect dataType:ZGString16 stride:sizeof(ZGMemoryAddress) unalignedAccess:NO], equalResults);
	XCTAssertEqual(equalNarrowedResults.count, 1U);

	mooSearchData.shouldIgnoreStringCase = YES;
	const char *mooMixedCase = [@"MoO" cStringUsingEncoding:NSUTF16LittleEndianStringEncoding];
	if (!ZGWriteBytes(_processTask, address + 5000, mooMixedCase, mooLength)) XCTFail(@"Failed to write moo mixed string");

	ZGSearchResults *equalNarrowedIgnoreCaseResults = ZGNarrowSearchForData(_processTask, NO, mooSearchData, nil, ZGString16, 0, ZGEquals, [[ZGSearchResults alloc] initWithResultSets:@[] resultType:ZGSearchResultTypeDirect dataType:ZGString16 stride:sizeof(ZGMemoryAddress) unalignedAccess:NO], equalResults);
	XCTAssertEqual(equalNarrowedIgnoreCaseResults.count, 1U);

	NSString *nooString = @"noo";
	unichar *nooBytes = calloc(nooString.length + 1, sizeof(unichar));
	if (nooBytes == NULL) XCTFail(@"Failed to write calloc noo bytes");

	[nooString getBytes:nooBytes maxLength:sizeof(*nooBytes) * nooString.length usedLength:NULL encoding:NSUTF16LittleEndianStringEncoding options:NSStringEncodingConversionAllowLossy range:NSMakeRange(0, nooString.length) remainingRange:NULL];

	size_t nooLength = nooString.length * sizeof(unichar);
	if (!ZGWriteBytes(_processTask, address + 5000, nooBytes, nooLength)) XCTFail(@"Failed to write noo string");

	ZGSearchResults *equalNarrowedIgnoreCaseFalseResults = ZGNarrowSearchForData(_processTask, NO, mooSearchData, nil, ZGString16, 0, ZGEquals, [[ZGSearchResults alloc] initWithResultSets:@[] resultType:ZGSearchResultTypeDirect dataType:ZGString16 stride:sizeof(ZGMemoryAddress) unalignedAccess:NO], equalResults);
	XCTAssertEqual(equalNarrowedIgnoreCaseFalseResults.count, 0U);

	ZGSearchResults *notEqualNarrowedIgnoreCaseResults = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGString16, 0, ZGNotEquals, [[ZGSearchResults alloc] initWithResultSets:@[] resultType:ZGSearchResultTypeDirect dataType:ZGString16 stride:sizeof(ZGMemoryAddress) unalignedAccess:NO], equalResults);
	XCTAssertEqual(notEqualNarrowedIgnoreCaseResults.count, 1U);

	ZGSearchData *nooSearchData = [self searchDataFromBytes:nooBytes size:nooLength dataType:ZGString16 address:address alignment:sizeof(unichar)];
	nooSearchData.beginAddress = address + _pageSize;
	nooSearchData.endAddress = address + _pageSize * 2;

	ZGSearchResults *nooEqualResults = ZGSearchForData(_processTask, nooSearchData, nil, ZGString16, 0, ZGEquals);
	XCTAssertEqual(nooEqualResults.count, 1U);

	ZGSearchResults *nooNotEqualResults = ZGSearchForData(_processTask, nooSearchData, nil, ZGString16, 0, ZGNotEquals);
	XCTAssertEqual(nooNotEqualResults.count, _pageSize / 2 - 1 - 2);

	unichar *helloBigBytes = calloc(helloString.length + 1, sizeof(unichar));
	if (helloBigBytes == NULL) XCTFail(@"Failed to write calloc helloBigBytes");

	[helloString getBytes:helloBigBytes maxLength:sizeof(*helloBigBytes) * helloString.length usedLength:NULL encoding:NSUTF16BigEndianStringEncoding options:NSStringEncodingConversionAllowLossy range:NSMakeRange(0, helloString.length) remainingRange:NULL];

	if (!ZGWriteBytes(_processTask, address + 7000, helloBigBytes, helloLength)) XCTFail(@"Failed to write hello big string");

	searchData.bytesSwapped = YES;

	ZGSearchResults *equalResultsBig = ZGSearchForData(_processTask, searchData, nil, ZGString16, 0, ZGEquals);
	XCTAssertEqual(equalResultsBig.count, 1U);

	ZGSearchResults *equalResultsBigNarrow = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGString16, 0, ZGEquals, [[ZGSearchResults alloc] initWithResultSets:@[] resultType:ZGSearchResultTypeDirect dataType:ZGString16 stride:sizeof(ZGMemoryAddress) unalignedAccess:NO], equalResultsBig);
	XCTAssertEqual(equalResultsBigNarrow.count, 1U);

	unichar capitalHByte = 0x0;
	[@"H" getBytes:&capitalHByte maxLength:sizeof(capitalHByte) usedLength:NULL encoding:NSUTF16BigEndianStringEncoding options:NSStringEncodingConversionAllowLossy range:NSMakeRange(0, 1) remainingRange:NULL];

	if (!ZGWriteBytes(_processTask, address + 7000, &capitalHByte, sizeof(capitalHByte))) XCTFail(@"Failed to write capital H string");

	ZGSearchResults *equalResultsBigNarrowTwice = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGString16, 0, ZGEquals, [[ZGSearchResults alloc] initWithResultSets:@[] resultType:ZGSearchResultTypeDirect dataType:ZGString16 stride:sizeof(ZGMemoryAddress) unalignedAccess:NO], equalResultsBigNarrow);
	XCTAssertEqual(equalResultsBigNarrowTwice.count, 0U);

	ZGSearchResults *notEqualResultsBigNarrowTwice = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGString16, 0, ZGNotEquals, [[ZGSearchResults alloc] initWithResultSets:@[] resultType:ZGSearchResultTypeDirect dataType:ZGString16 stride:sizeof(ZGMemoryAddress) unalignedAccess:NO], equalResultsBigNarrow);
	XCTAssertEqual(notEqualResultsBigNarrowTwice.count, 1U);

	searchData.shouldIgnoreStringCase = YES;

	ZGSearchResults *equalResultsBigNarrowThrice = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGString16, 0, ZGEquals, [[ZGSearchResults alloc] initWithResultSets:@[] resultType:ZGSearchResultTypeDirect dataType:ZGString16 stride:sizeof(ZGMemoryAddress) unalignedAccess:NO], equalResultsBigNarrow);
	XCTAssertEqual(equalResultsBigNarrowThrice.count, 1U);

	ZGSearchResults *equalResultsBigCaseInsenitive = ZGSearchForData(_processTask, searchData, nil, ZGString16, 0, ZGEquals);
	XCTAssertEqual(equalResultsBigCaseInsenitive.count, 1U);

	searchData.dataSize += sizeof(unichar);
	// .shouldIncludeNullTerminator is not necessary to set, only used for UI state

	ZGSearchResults *equalResultsBigCaseInsenitiveNullTerminatedNarrowed = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGString16, 0, ZGEquals, [[ZGSearchResults alloc] initWithResultSets:@[] resultType:ZGSearchResultTypeDirect dataType:ZGString16 stride:sizeof(ZGMemoryAddress) unalignedAccess:NO], equalResultsBigCaseInsenitive);
	XCTAssertEqual(equalResultsBigCaseInsenitiveNullTerminatedNarrowed.count, 0U);

	unichar zero = 0x0;
	if (!ZGWriteBytes(_processTask, address + 7000 + helloLength, &zero, sizeof(zero))) XCTFail(@"Failed to write zero");

	ZGSearchResults *equalResultsBigCaseInsenitiveNullTerminatedNarrowedTwice = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGString16, 0, ZGEquals, [[ZGSearchResults alloc] initWithResultSets:@[] resultType:ZGSearchResultTypeDirect dataType:ZGString16 stride:sizeof(ZGMemoryAddress) unalignedAccess:NO], equalResultsBigCaseInsenitive);
	XCTAssertEqual(equalResultsBigCaseInsenitiveNullTerminatedNarrowedTwice.count, 1U);

	ZGSearchResults *equalResultsBigCaseInsensitiveNullTerminated = ZGSearchForData(_processTask, searchData, nil, ZGString16, 0, ZGEquals);
	XCTAssertEqual(equalResultsBigCaseInsensitiveNullTerminated.count, 1U);

	const ZGMemorySize regionCount = 5;
	const ZGMemorySize chancesMissedPerRegion = 5;
	ZGSearchResults *notEqualResultsBigCaseInsensitiveNullTerminated = ZGSearchForData(_processTask, searchData, nil, ZGString16, 0, ZGNotEquals);
	XCTAssertEqual(notEqualResultsBigCaseInsensitiveNullTerminated.count, _data.length / sizeof(unichar) - regionCount * chancesMissedPerRegion - equalResultsBigCaseInsensitiveNullTerminated.count);

	searchData.shouldIgnoreStringCase = NO;
	searchData.bytesSwapped = NO;

	ZGSearchResults *equalResultsNullTerminated = ZGSearchForData(_processTask, searchData, nil, ZGString16, 0, ZGEquals);
	XCTAssertEqual(equalResultsNullTerminated.count, 0U);

	if (!ZGWriteBytes(_processTask, address + 96 + helloLength, &zero, sizeof(zero))) XCTFail(@"Failed to write zero 2nd time");

	ZGSearchResults *equalResultsNullTerminatedTwice = ZGSearchForData(_processTask, searchData, nil, ZGString16, 0, ZGEquals);
	XCTAssertEqual(equalResultsNullTerminatedTwice.count, 1U);

	ZGSearchResults *equalResultsNullTerminatedNarrowed = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGString16, 0, ZGEquals, [[ZGSearchResults alloc] initWithResultSets:@[] resultType:ZGSearchResultTypeDirect dataType:ZGString16 stride:sizeof(ZGMemoryAddress) unalignedAccess:NO], equalResultsNullTerminatedTwice);
	XCTAssertEqual(equalResultsNullTerminatedNarrowed.count, 1U);

	if (!ZGWriteBytes(_processTask, address + 96 + helloLength, helloBytes, sizeof(zero))) XCTFail(@"Failed to write first character");

	ZGSearchResults *equalResultsNullTerminatedNarrowedTwice = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGString16, 0, ZGEquals, [[ZGSearchResults alloc] initWithResultSets:@[] resultType:ZGSearchResultTypeDirect dataType:ZGString16 stride:sizeof(ZGMemoryAddress) unalignedAccess:NO], equalResultsNullTerminatedNarrowed);
	XCTAssertEqual(equalResultsNullTerminatedNarrowedTwice.count, 0U);

	ZGSearchResults *notEqualResultsNullTerminatedNarrowedTwice = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGString16, 0, ZGNotEquals, [[ZGSearchResults alloc] initWithResultSets:@[] resultType:ZGSearchResultTypeDirect dataType:ZGString16 stride:sizeof(ZGMemoryAddress) unalignedAccess:NO], equalResultsNullTerminatedNarrowed);
	XCTAssertEqual(notEqualResultsNullTerminatedNarrowedTwice.count, 1U);
}

/**
 * Tests searching for byte arrays with exact matching and wildcards.
 *
 * This test:
 * 1. Allocates memory and searches for a specific byte sequence
 * 2. Tests searching with exact byte matching
 * 3. Tests searching with wildcard patterns
 * 4. Tests narrowing results by modifying memory
 *
 * Memory layout and wildcard operations:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │                         Process Memory                           │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                              ...                                 │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                                                                  │
 * │                       Allocated Memory                           │
 * │                                                                  │
 * │  Initial byte sequence at some offset:                           │
 * │  ┌────┬────┬────┬────┐                                           │
 * │  │ C6 │ ED │ 8F │ 0D │                                           │
 * │  └────┴────┴────┴────┘                                           │
 * │                                                                  │
 * │  Exact search finds 1 match                                      │
 * │                                                                  │
 * │  Modified byte sequence at offset 0x21D4:                        │
 * │  ┌────┬────┬────┬────┐                                           │
 * │  │ C8 │ ED │ BF │ 0D │                                           │
 * │  └────┴────┴────┴────┘                                           │
 * │                                                                  │
 * │  Wildcard search pattern: "C? ED *F 0D"                          │
 * │  Where:                                                          │
 * │    - C? = Any byte starting with 'C' (C0-CF)                     │
 * │    - ED = Exact match for ED                                     │
 * │    - *F = Any byte ending with 'F' (?F)                          │
 * │    - 0D = Exact match for 0D                                     │
 * │                                                                  │
 * │  Wildcard pattern matches:                                       │
 * │  ┌────┬────┬────┬────┐                                           │
 * │  │ C8 │ ED │ BF │ 0D │                                           │
 * │  └────┴────┴────┴────┘                                           │
 * │  └─┬─┘ └─┬─┘ └─┬─┘ └─┬─┘                                         │
 * │    │    │    │    │                                              │
 * │    │    │    │    └── Exact match: 0D                            │
 * │    │    │    └── Wildcard match: *F matches BF                   │
 * │    │    └── Exact match: ED                                      │
 * │    └── Wildcard match: C? matches C8                             │
 * │                                                                  │
 * │  Finds 1 match with wildcards                                    │
 * │                                                                  │
 * │  Modified again at offset 0x21D4:                                │
 * │  ┌────┬────┬────┬────┐                                           │
 * │  │ D9 │ ED │ BF │ 0D │                                           │
 * │  └────┴────┴────┴────┘                                           │
 * │                                                                  │
 * │  Wildcard pattern no longer matches:                             │
 * │  - First byte D9 doesn't match C? pattern                        │
 * │  Narrowed search finds 0 matches                                 │
 * │                                                                  │
 * └─────────────────────────────────────────────────────────────────┘
 */
- (void)testByteArraySearch
{
	ZGMemoryAddress address = [self allocateDataIntoProcess];
	uint8_t bytes[] = {0xC6, 0xED, 0x8F, 0x0D};

	ZGSearchData *searchData = [self searchDataFromBytes:bytes size:sizeof(bytes) dataType:ZGByteArray address:address alignment:1];

	ZGSearchResults *equalResults = ZGSearchForData(_processTask, searchData, nil, ZGByteArray, 0, ZGEquals);
	XCTAssertEqual(equalResults.count, 1U);

	ZGSearchResults *notEqualResults = ZGSearchForData(_processTask, searchData, nil, ZGByteArray, 0, ZGNotEquals);
	XCTAssertEqual(notEqualResults.count, _data.length - 1 - 3*5);

	uint8_t changedBytes[] = {0xC8, 0xED, 0xBF, 0x0D};
	if (!ZGWriteBytes(_processTask, address + 0x21D4, changedBytes, sizeof(changedBytes))) XCTFail(@"Failed to write changed bytes");

	NSString *wildcardExpression = @"C? ED *F 0D";
	unsigned char *byteArrayFlags = ZGAllocateFlagsForByteArrayWildcards(wildcardExpression);
	if (byteArrayFlags == NULL) XCTFail(@"Byte array flags is NULL");

	searchData.byteArrayFlags = byteArrayFlags;
	searchData.searchValue = ZGValueFromString(ZGProcessTypeX86_64, wildcardExpression, ZGByteArray, NULL);

	ZGSearchResults *equalResultsWildcards = ZGSearchForData(_processTask, searchData, nil, ZGByteArray, 0, ZGEquals);
	XCTAssertEqual(equalResultsWildcards.count, 1U);

	uint8_t changedBytesAgain[] = {0xD9, 0xED, 0xBF, 0x0D};
	if (!ZGWriteBytes(_processTask, address + 0x21D4, changedBytesAgain, sizeof(changedBytesAgain))) XCTFail(@"Failed to write changed bytes again");

	ZGSearchResults *equalResultsWildcardsNarrowed = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGByteArray, 0, ZGEquals, [[ZGSearchResults alloc] initWithResultSets:@[] resultType:ZGSearchResultTypeDirect dataType:ZGByteArray stride:sizeof(ZGMemoryAddress) unalignedAccess:NO], equalResultsWildcards);
	XCTAssertEqual(equalResultsWildcardsNarrowed.count, 0U);

	ZGSearchResults *notEqualResultsWildcardsNarrowed = ZGNarrowSearchForData(_processTask, NO, searchData, nil, ZGByteArray, 0, ZGNotEquals, [[ZGSearchResults alloc] initWithResultSets:@[] resultType:ZGSearchResultTypeDirect dataType:ZGByteArray stride:sizeof(ZGMemoryAddress) unalignedAccess:NO], equalResultsWildcards);
	XCTAssertEqual(notEqualResultsWildcardsNarrowed.count, 1U);
}

@end
