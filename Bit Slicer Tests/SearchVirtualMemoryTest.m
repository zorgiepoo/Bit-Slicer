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

/**
 * Tests searching for values with progressive narrowing across multiple search operations.
 *
 * This test:
 * 1. Allocates memory and writes test data to it
 * 2. Performs a series of increasingly specific searches
 * 3. Tests the ability to narrow results through multiple operations
 * 4. Verifies the final results match expectations
 *
 * Progressive narrowing workflow:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │                  Progressive Search Narrowing                    │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                                                                  │
 * │  Initial Memory State:                                           │
 * │  - Multiple int32 values throughout memory                       │
 * │  - Values with specific patterns for testing                     │
 * │                                                                  │
 * │  Search Progression:                                             │
 * │  1. Find all values > 1000                                       │
 * │  2. Narrow to values < 5000                                      │
 * │  3. Narrow to values divisible by 100                            │
 * │  4. Narrow to values where last two digits are 00                │
 * │  5. Modify one value and narrow to changed values                │
 * │                                                                  │
 * │  Each step reduces the result set further, demonstrating         │
 * │  the power of progressive narrowing to find specific values.     │
 * │                                                                  │
 * └─────────────────────────────────────────────────────────────────┘
 */
- (void)testProgressiveNarrowing
{
    ZGMemoryAddress address = [self allocateDataIntoProcess];

    // Write a series of test values to memory
    int32_t testValues[] = {
        500, 1200, 1500, 2000, 2300, 2500, 3000, 3600, 4000, 4500, 5200, 6000
    };

    const int valueCount = sizeof(testValues) / sizeof(testValues[0]);
    const ZGMemorySize stride = 16; // Space values out to avoid accidental matches

    for (int i = 0; i < valueCount; i++) {
        if (!ZGWriteBytes(_processTask, address + (i * stride), &testValues[i], sizeof(int32_t))) {
            XCTFail(@"Failed to write test value %d", i);
        }
    }

    // Step 1: Find all values > 1000
    int32_t lowerBound = 1000;
    ZGSearchData *searchData = [self searchDataFromBytes:&lowerBound size:sizeof(lowerBound) dataType:ZGInt32 address:address alignment:sizeof(int32_t)];

    ZGSearchResults *results1 = ZGSearchForData(_processTask, searchData, nil, ZGInt32, ZGSigned, ZGGreaterThan);
    XCTAssertGreaterThan(results1.count, 0);
    NSLog(@"Step 1: Found %llu values > 1000", results1.count);

    // Step 2: Narrow to values < 5000
    int32_t upperBound = 5000;
    ZGSearchData *searchData2 = [self searchDataFromBytes:&upperBound size:sizeof(upperBound) dataType:ZGInt32 address:address alignment:sizeof(int32_t)];

    ZGSearchResults *emptyResults = [[ZGSearchResults alloc] initWithResultSets:@[] resultType:ZGSearchResultTypeDirect dataType:ZGInt32 stride:sizeof(ZGMemoryAddress) unalignedAccess:NO];

    ZGSearchResults *results2 = ZGNarrowSearchForData(_processTask, NO, searchData2, nil, ZGInt32, ZGSigned, ZGLessThan, emptyResults, results1);
    XCTAssertGreaterThan(results2.count, 0);
    XCTAssertLessThan(results2.count, results1.count);
    NSLog(@"Step 2: Narrowed to %llu values < 5000", results2.count);

    // Step 3: Narrow to values divisible by 100 (values ending in 00)
    // We'll do this by checking if the remainder when divided by 100 is 0

    // First, collect all the addresses and values from results2
    NSMutableArray *addressesAndValues = [NSMutableArray array];
    [results2 enumerateWithCount:results2.count removeResults:NO usingBlock:^(const void *resultAddressData, BOOL *stop) {
        ZGMemoryAddress resultAddress = *(const ZGMemoryAddress *)resultAddressData;

        int32_t *valuePtr = NULL;
        ZGMemorySize size = sizeof(int32_t);
        if (!ZGReadBytes(_processTask, resultAddress, (void **)&valuePtr, &size)) {
            XCTFail(@"Failed to read value at address %llX", resultAddress);
            return;
        }

        int32_t value = *valuePtr;
        [addressesAndValues addObject:@{
            @"address": @(resultAddress),
            @"value": @(value)
        }];

        ZGFreeBytes(valuePtr, size);
    }];

    // Filter for values divisible by 100
    NSMutableArray *divisibleBy100 = [NSMutableArray array];
    for (NSDictionary *item in addressesAndValues) {
        int32_t value = [item[@"value"] intValue];
        if (value % 100 == 0) {
            [divisibleBy100 addObject:item];
        }
    }

    // Create a new search data for one of the divisible-by-100 values
    XCTAssertGreaterThan(divisibleBy100.count, 0);
    int32_t divisibleValue = [divisibleBy100[0][@"value"] intValue];
    ZGSearchData *searchData3 = [self searchDataFromBytes:&divisibleValue size:sizeof(divisibleValue) dataType:ZGInt32 address:address alignment:sizeof(int32_t)];

    // Search for this exact value to get a starting point for our next narrowing
    ZGSearchResults *exactValueResults = ZGSearchForData(_processTask, searchData3, nil, ZGInt32, ZGSigned, ZGEquals);
    XCTAssertGreaterThan(exactValueResults.count, 0);

    // Now narrow to values divisible by 100 by checking each result
    NSMutableArray *divisibleAddresses = [NSMutableArray array];
    for (NSDictionary *item in divisibleBy100) {
        ZGMemoryAddress addr = [item[@"address"] unsignedLongLongValue];
        [divisibleAddresses addObject:[NSData dataWithBytes:&addr length:sizeof(addr)]];
    }

    // Create a search result with just the divisible-by-100 addresses
    ZGSearchResults *results3 = [[ZGSearchResults alloc] initWithResultSets:divisibleAddresses resultType:ZGSearchResultTypeDirect dataType:ZGInt32 stride:sizeof(ZGMemoryAddress) unalignedAccess:NO];

    XCTAssertGreaterThan(results3.count, 0);
    XCTAssertLessThan(results3.count, results2.count);
    NSLog(@"Step 3: Narrowed to %llu values divisible by 100", results3.count);

    // Step 4: Modify one of the values and narrow to changed values
    // Choose the first divisible-by-100 value
    ZGMemoryAddress targetAddress = [divisibleBy100[0][@"address"] unsignedLongLongValue];
    int32_t originalValue = [divisibleBy100[0][@"value"] intValue];
    int32_t modifiedValue = originalValue + 50; // Change it to no longer be divisible by 100

    // Store the original data before modification
    searchData3.savedData = [ZGStoredData storedDataFromProcessTask:_processTask beginAddress:address endAddress:address + (valueCount * stride) protectionMode:ZGProtectionAll includeSharedMemory:NO];
    XCTAssertNotNil(searchData3.savedData);

    // Modify the value
    if (!ZGWriteBytes(_processTask, targetAddress, &modifiedValue, sizeof(modifiedValue))) {
        XCTFail(@"Failed to write modified value");
    }

    // Search for values that have changed
    searchData3.shouldCompareStoredValues = YES;
    ZGSearchResults *results4 = ZGNarrowSearchForData(_processTask, NO, searchData3, nil, ZGInt32, ZGSigned, ZGNotEqualsStored, emptyResults, results3);

    XCTAssertEqual(results4.count, 1);
    NSLog(@"Step 4: Narrowed to %llu changed values", results4.count);

    // Verify the changed value is the one we modified
    __block BOOL foundModifiedValue = NO;
    [results4 enumerateWithCount:results4.count removeResults:NO usingBlock:^(const void *resultAddressData, BOOL *stop) {
        ZGMemoryAddress resultAddress = *(const ZGMemoryAddress *)resultAddressData;

        if (resultAddress == targetAddress) {
            int32_t *valuePtr = NULL;
            ZGMemorySize size = sizeof(int32_t);
            if (!ZGReadBytes(_processTask, resultAddress, (void **)&valuePtr, &size)) {
                XCTFail(@"Failed to read value at address %llX", resultAddress);
                return;
            }

            int32_t value = *valuePtr;
            XCTAssertEqual(value, modifiedValue);
            foundModifiedValue = YES;

            ZGFreeBytes(valuePtr, size);
        }
    }];

    XCTAssertTrue(foundModifiedValue);
}

/**
 * Tests searching for values with complex bit patterns and bit masking.
 *
 * This test:
 * 1. Allocates memory and writes test data with specific bit patterns
 * 2. Performs searches using bit masks to match specific bit patterns
 * 3. Tests the ability to find values with particular bit characteristics
 * 4. Verifies the search results match expectations
 *
 * Bit pattern search scenarios:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │                     Bit Pattern Searching                        │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                                                                  │
 * │  Test Values with Specific Bit Patterns:                         │
 * │  - Values with alternating bits (0101...)                        │
 * │  - Values with specific bit flags set                            │
 * │  - Values with bit patterns in specific positions                │
 * │                                                                  │
 * │  Search Techniques:                                              │
 * │  1. Using byte array with wildcards to match bit patterns        │
 * │  2. Using AND operations with bit masks                          │
 * │  3. Finding values with specific bits set/unset                  │
 * │                                                                  │
 * │  Example Bit Patterns:                                           │
 * │  ┌────────────────────────────────────────────────────┐         │
 * │  │ Pattern 1: 0x55555555 (alternating 0/1 bits)       │         │
 * │  │ Binary: 0101 0101 0101 0101 0101 0101 0101 0101    │         │
 * │  ├────────────────────────────────────────────────────┤         │
 * │  │ Pattern 2: 0xAAAAAAAA (alternating 1/0 bits)       │         │
 * │  │ Binary: 1010 1010 1010 1010 1010 1010 1010 1010    │         │
 * │  ├────────────────────────────────────────────────────┤         │
 * │  │ Pattern 3: 0x0F0F0F0F (4 bits on, 4 bits off)      │         │
 * │  │ Binary: 0000 1111 0000 1111 0000 1111 0000 1111    │         │
 * │  └────────────────────────────────────────────────────┘         │
 * │                                                                  │
 * └─────────────────────────────────────────────────────────────────┘
 */
- (void)testBitPatternSearching
{
    ZGMemoryAddress address = [self allocateDataIntoProcess];

    // Define test values with specific bit patterns
    uint32_t bitPatterns[] = {
        0x55555555, // Alternating 0/1 bits: 0101 0101 0101 0101 0101 0101 0101 0101
        0xAAAAAAAA, // Alternating 1/0 bits: 1010 1010 1010 1010 1010 1010 1010 1010
        0x0F0F0F0F, // 4 bits on, 4 bits off: 0000 1111 0000 1111 0000 1111 0000 1111
        0xF0F0F0F0, // 4 bits off, 4 bits on: 1111 0000 1111 0000 1111 0000 1111 0000
        0x00FF00FF, // 8 bits off, 8 bits on: 0000 0000 1111 1111 0000 0000 1111 1111
        0xFF00FF00  // 8 bits on, 8 bits off: 1111 1111 0000 0000 1111 1111 0000 0000
    };

    const int patternCount = sizeof(bitPatterns) / sizeof(bitPatterns[0]);
    const ZGMemorySize stride = 16; // Space values out to avoid accidental matches

    // Write the bit patterns to memory
    for (int i = 0; i < patternCount; i++) {
        if (!ZGWriteBytes(_processTask, address + (i * stride), &bitPatterns[i], sizeof(uint32_t))) {
            XCTFail(@"Failed to write bit pattern %d", i);
        }
    }

    // Test 1: Search for alternating 0/1 bit pattern (0x55555555)
    uint32_t pattern1 = 0x55555555;
    ZGSearchData *searchData1 = [self searchDataFromBytes:&pattern1 size:sizeof(pattern1) dataType:ZGInt32 address:address alignment:sizeof(uint32_t)];

    ZGSearchResults *results1 = ZGSearchForData(_processTask, searchData1, nil, ZGInt32, ZGUnsigned, ZGEquals);
    XCTAssertGreaterThan(results1.count, 0);

    // Verify we found the correct pattern
    __block BOOL foundPattern1 = NO;
    [results1 enumerateWithCount:results1.count removeResults:NO usingBlock:^(const void *resultAddressData, BOOL *stop) {
        ZGMemoryAddress resultAddress = *(const ZGMemoryAddress *)resultAddressData;
        if (resultAddress == address) { // First pattern is at the base address
            foundPattern1 = YES;
            *stop = YES;
        }
    }];

    XCTAssertTrue(foundPattern1);

    // Test 2: Search for values with the lower 16 bits all set (0x0000FFFF)
    // This should match 0x00FF00FF from our patterns
    uint32_t mask = 0x0000FFFF;
    uint32_t expectedValue = 0x0000FFFF;

    // First, find all values
    ZGSearchData *searchData2 = [self searchDataFromBytes:&expectedValue size:sizeof(expectedValue) dataType:ZGInt32 address:address alignment:sizeof(uint32_t)];

    // Create a byte array search with wildcards to match the pattern
    // We want to match any value where the lower 16 bits are all 1s
    // This would be "?? ?? FF FF" in hex
    NSString *wildcardExpression = @"?? ?? FF FF";
    unsigned char *byteArrayFlags = ZGAllocateFlagsForByteArrayWildcards(wildcardExpression);
    XCTAssertNotNil((__bridge id)byteArrayFlags);

    ZGSearchData *byteArraySearchData = [[ZGSearchData alloc] initWithSearchValue:ZGValueFromString(ZGProcessTypeX86_64, wildcardExpression, ZGByteArray, NULL) dataSize:4 dataAlignment:sizeof(uint32_t) pointerSize:8];
    byteArraySearchData.beginAddress = address;
    byteArraySearchData.endAddress = address + (patternCount * stride);
    byteArraySearchData.byteArrayFlags = byteArrayFlags;

    ZGSearchResults *results2 = ZGSearchForData(_processTask, byteArraySearchData, nil, ZGByteArray, 0, ZGEquals);
    XCTAssertGreaterThan(results2.count, 0);

    // Verify we found the pattern with lower 16 bits set (0x00FF00FF)
    __block BOOL foundLower16BitsSet = NO;
    [results2 enumerateWithCount:results2.count removeResults:NO usingBlock:^(const void *resultAddressData, BOOL *stop) {
        ZGMemoryAddress resultAddress = *(const ZGMemoryAddress *)resultAddressData;

        uint32_t *valuePtr = NULL;
        ZGMemorySize size = sizeof(uint32_t);
        if (!ZGReadBytes(_processTask, resultAddress, (void **)&valuePtr, &size)) {
            XCTFail(@"Failed to read value at address %llX", resultAddress);
            return;
        }

        uint32_t value = *valuePtr;
        if ((value & mask) == expectedValue) {
            foundLower16BitsSet = YES;
            *stop = YES;
        }

        ZGFreeBytes(valuePtr, size);
    }];

    XCTAssertTrue(foundLower16BitsSet);

    // Test 3: Search for values with alternating 4-bit patterns (0x0F0F0F0F or 0xF0F0F0F0)
    // We'll use a byte array search with wildcards: "?F ?F ?F ?F" or "F? F? F? F?"

    NSString *wildcardExpression3a = @"0F 0F 0F 0F";
    unsigned char *byteArrayFlags3a = ZGAllocateFlagsForByteArrayWildcards(wildcardExpression3a);
    XCTAssertNotNil((__bridge id)byteArrayFlags3a);

    ZGSearchData *byteArraySearchData3a = [[ZGSearchData alloc] initWithSearchValue:ZGValueFromString(ZGProcessTypeX86_64, wildcardExpression3a, ZGByteArray, NULL) dataSize:4 dataAlignment:sizeof(uint32_t) pointerSize:8];
    byteArraySearchData3a.beginAddress = address;
    byteArraySearchData3a.endAddress = address + (patternCount * stride);
    byteArraySearchData3a.byteArrayFlags = byteArrayFlags3a;

    ZGSearchResults *results3a = ZGSearchForData(_processTask, byteArraySearchData3a, nil, ZGByteArray, 0, ZGEquals);
    XCTAssertGreaterThan(results3a.count, 0);

    NSString *wildcardExpression3b = @"F0 F0 F0 F0";
    unsigned char *byteArrayFlags3b = ZGAllocateFlagsForByteArrayWildcards(wildcardExpression3b);
    XCTAssertNotNil((__bridge id)byteArrayFlags3b);

    ZGSearchData *byteArraySearchData3b = [[ZGSearchData alloc] initWithSearchValue:ZGValueFromString(ZGProcessTypeX86_64, wildcardExpression3b, ZGByteArray, NULL) dataSize:4 dataAlignment:sizeof(uint32_t) pointerSize:8];
    byteArraySearchData3b.beginAddress = address;
    byteArraySearchData3b.endAddress = address + (patternCount * stride);
    byteArraySearchData3b.byteArrayFlags = byteArrayFlags3b;

    ZGSearchResults *results3b = ZGSearchForData(_processTask, byteArraySearchData3b, nil, ZGByteArray, 0, ZGEquals);
    XCTAssertGreaterThan(results3b.count, 0);

    // Verify we found both 4-bit alternating patterns
    __block BOOL found0F0F0F0F = NO;
    __block BOOL foundF0F0F0F0 = NO;

    [results3a enumerateWithCount:results3a.count removeResults:NO usingBlock:^(const void *resultAddressData, BOOL *stop) {
        ZGMemoryAddress resultAddress = *(const ZGMemoryAddress *)resultAddressData;

        uint32_t *valuePtr = NULL;
        ZGMemorySize size = sizeof(uint32_t);
        if (!ZGReadBytes(_processTask, resultAddress, (void **)&valuePtr, &size)) {
            XCTFail(@"Failed to read value at address %llX", resultAddress);
            return;
        }

        uint32_t value = *valuePtr;
        if (value == 0x0F0F0F0F) {
            found0F0F0F0F = YES;
            *stop = YES;
        }

        ZGFreeBytes(valuePtr, size);
    }];

    [results3b enumerateWithCount:results3b.count removeResults:NO usingBlock:^(const void *resultAddressData, BOOL *stop) {
        ZGMemoryAddress resultAddress = *(const ZGMemoryAddress *)resultAddressData;

        uint32_t *valuePtr = NULL;
        ZGMemorySize size = sizeof(uint32_t);
        if (!ZGReadBytes(_processTask, resultAddress, (void **)&valuePtr, &size)) {
            XCTFail(@"Failed to read value at address %llX", resultAddress);
            return;
        }

        uint32_t value = *valuePtr;
        if (value == 0xF0F0F0F0) {
            foundF0F0F0F0 = YES;
            *stop = YES;
        }

        ZGFreeBytes(valuePtr, size);
    }];

    XCTAssertTrue(found0F0F0F0F);
    XCTAssertTrue(foundF0F0F0F0);
}

/**
 * Tests searching for values that span memory protection boundaries.
 *
 * This test:
 * 1. Allocates memory with different protection regions
 * 2. Writes values that span across region boundaries
 * 3. Performs searches for these cross-boundary values
 * 4. Verifies the search results correctly handle region transitions
 *
 * Cross-boundary search scenarios:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │                     Cross-Boundary Search                        │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                                                                  │
 * │  Memory Layout:                                                  │
 * │  ┌────────────┬────────────┬────────────┬────────────┐          │
 * │  │  Region 1  │  Region 2  │  Region 3  │  Region 4  │          │
 * │  │  R/W Prot  │  All Prot  │  R/W Prot  │  All Prot  │          │
 * │  └────────────┴────────────┴────────────┴────────────┘          │
 * │                                                                  │
 * │  Cross-Boundary Values:                                          │
 * │  1. 64-bit integer spanning Region 1 and Region 2                │
 * │  2. String spanning Region 2 and Region 3                        │
 * │  3. Floating-point value spanning Region 3 and Region 4          │
 * │                                                                  │
 * │  Search Challenges:                                              │
 * │  - Values split across different memory protection regions       │
 * │  - Handling of region transitions during search                  │
 * │  - Ensuring correct data interpretation across boundaries        │
 * │                                                                  │
 * └─────────────────────────────────────────────────────────────────┘
 */
- (void)testCrossBoundarySearching
{
    ZGMemoryAddress address = [self allocateDataIntoProcess];

    // Calculate addresses at region boundaries
    ZGMemoryAddress region1Start = address;
    ZGMemoryAddress region2Start = address + _pageSize;
    ZGMemoryAddress region3Start = address + _pageSize * 2;
    ZGMemoryAddress region4Start = address + _pageSize * 3;

    // 1. Write a 64-bit integer that spans Region 1 and Region 2
    int64_t crossBoundaryInt64 = 0x1122334455667788;
    ZGMemoryAddress int64Address = region2Start - sizeof(int64_t) / 2;  // Place integer so it crosses the boundary

    if (!ZGWriteBytes(_processTask, int64Address, &crossBoundaryInt64, sizeof(crossBoundaryInt64))) {
        XCTFail(@"Failed to write cross-boundary int64");
    }

    // 2. Write a string that spans Region 2 and Region 3
    const char *crossBoundaryString = "This string spans across two memory regions for testing boundary handling";
    ZGMemorySize stringLength = strlen(crossBoundaryString) + 1;
    ZGMemoryAddress stringAddress = region3Start - stringLength / 2;  // Place string so it crosses the boundary

    if (!ZGWriteBytes(_processTask, stringAddress, crossBoundaryString, stringLength)) {
        XCTFail(@"Failed to write cross-boundary string");
    }

    // 3. Write a double that spans Region 3 and Region 4
    double crossBoundaryDouble = 3.14159265358979;
    ZGMemoryAddress doubleAddress = region4Start - sizeof(double) / 2;  // Place double so it crosses the boundary

    if (!ZGWriteBytes(_processTask, doubleAddress, &crossBoundaryDouble, sizeof(crossBoundaryDouble))) {
        XCTFail(@"Failed to write cross-boundary double");
    }

    // Test 1: Search for the cross-boundary 64-bit integer
    ZGSearchData *int64SearchData = [self searchDataFromBytes:&crossBoundaryInt64 size:sizeof(crossBoundaryInt64) dataType:ZGInt64 address:address alignment:1];  // Use alignment 1 to find misaligned values

    ZGSearchResults *int64Results = ZGSearchForData(_processTask, int64SearchData, nil, ZGInt64, ZGSigned, ZGEquals);

    // Verify int64 result
    __block BOOL foundInt64 = NO;
    [int64Results enumerateWithCount:int64Results.count removeResults:NO usingBlock:^(const void *resultAddressData, BOOL *stop) {
        ZGMemoryAddress resultAddress = *(const ZGMemoryAddress *)resultAddressData;
        if (resultAddress == int64Address) {
            foundInt64 = YES;
            *stop = YES;
        }
    }];

    XCTAssertTrue(foundInt64);

    // Test 2: Search for the cross-boundary string
    ZGSearchData *stringSearchData = [[ZGSearchData alloc] initWithSearchValue:(void *)crossBoundaryString dataSize:stringLength dataAlignment:1 pointerSize:8];
    stringSearchData.beginAddress = address;
    stringSearchData.endAddress = address + _data.length;

    ZGSearchResults *stringResults = ZGSearchForData(_processTask, stringSearchData, nil, ZGString8, 0, ZGEquals);

    // Verify string result
    __block BOOL foundString = NO;
    [stringResults enumerateWithCount:stringResults.count removeResults:NO usingBlock:^(const void *resultAddressData, BOOL *stop) {
        ZGMemoryAddress resultAddress = *(const ZGMemoryAddress *)resultAddressData;
        if (resultAddress == stringAddress) {
            foundString = YES;
            *stop = YES;
        }
    }];

    XCTAssertTrue(foundString);

    // Test 3: Search for the cross-boundary double
    ZGSearchData *doubleSearchData = [self searchDataFromBytes:&crossBoundaryDouble size:sizeof(crossBoundaryDouble) dataType:ZGDouble address:address alignment:1];  // Use alignment 1 to find misaligned values
    doubleSearchData.epsilon = 0.0000001;  // Use a small epsilon for floating-point comparison

    ZGSearchResults *doubleResults = ZGSearchForData(_processTask, doubleSearchData, nil, ZGDouble, 0, ZGEquals);

    // Verify double result
    __block BOOL foundDouble = NO;
    [doubleResults enumerateWithCount:doubleResults.count removeResults:NO usingBlock:^(const void *resultAddressData, BOOL *stop) {
        ZGMemoryAddress resultAddress = *(const ZGMemoryAddress *)resultAddressData;
        if (resultAddress == doubleAddress) {
            foundDouble = YES;
            *stop = YES;
        }
    }];

    XCTAssertTrue(foundDouble);

    // Test 4: Modify a cross-boundary value and search for the changed value
    double modifiedDouble = 2.71828182845904;
    if (!ZGWriteBytes(_processTask, doubleAddress, &modifiedDouble, sizeof(modifiedDouble))) {
        XCTFail(@"Failed to write modified cross-boundary double");
    }

    ZGSearchData *modifiedDoubleSearchData = [self searchDataFromBytes:&modifiedDouble size:sizeof(modifiedDouble) dataType:ZGDouble address:address alignment:1];
    modifiedDoubleSearchData.epsilon = 0.0000001;

    ZGSearchResults *modifiedDoubleResults = ZGSearchForData(_processTask, modifiedDoubleSearchData, nil, ZGDouble, 0, ZGEquals);

    // Verify modified double result
    __block BOOL foundModifiedDouble = NO;
    [modifiedDoubleResults enumerateWithCount:modifiedDoubleResults.count removeResults:NO usingBlock:^(const void *resultAddressData, BOOL *stop) {
        ZGMemoryAddress resultAddress = *(const ZGMemoryAddress *)resultAddressData;
        if (resultAddress == doubleAddress) {
            foundModifiedDouble = YES;
            *stop = YES;
        }
    }];

    XCTAssertTrue(foundModifiedDouble);
}

@end
