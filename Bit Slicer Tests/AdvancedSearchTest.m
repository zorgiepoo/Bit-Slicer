/*
 * Copyright (c) 2025 Mayur Pawashe & Moreaki
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

/**
 * Advanced tests for the memory search functionality in Bit Slicer.
 *
 * These tests build on the basic search tests in SearchVirtualMemoryTest.m
 * and focus on more complex scenarios, edge cases, and combinations of features.
 */
@interface AdvancedSearchTest : XCTestCase

@end

@implementation AdvancedSearchTest
{
    ZGMemoryMap _processTask;
    NSData *_data;
    ZGMemorySize _pageSize;
    ZGMemoryAddress _allocatedAddress;
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
    
    // Allocate memory for tests
    _allocatedAddress = [self allocateDataIntoProcess];
}

- (void)tearDown
{
    // Deallocate memory
    if (_allocatedAddress != 0)
    {
        ZGDeallocateMemory(_processTask, _allocatedAddress, _data.length);
    }
    
    ZGDeallocatePort(_processTask);
    
    [super tearDown];
}

- (ZGMemoryAddress)allocateDataIntoProcess
{
    ZGMemoryAddress address = 0x0;
    if (!ZGAllocateMemory(_processTask, &address, _data.length))
    {
        XCTFail(@"Failed to allocate memory");
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
 * Tests searching for values with complex combinations of search criteria.
 *
 * This test:
 * 1. Allocates memory and writes test data to it
 * 2. Performs a search with multiple criteria (value range, alignment, endianness)
 * 3. Narrows results with different criteria
 * 4. Verifies the search results match expectations
 *
 * Complex search criteria:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │                   Complex Search Criteria                        │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                                                                  │
 * │  Initial Search:                                                 │
 * │  - Data Type: 32-bit Integer                                     │
 * │  - Value Range: 1000 to 5000                                     │
 * │  - Alignment: 4 bytes                                            │
 * │  - Endianness: Big Endian                                        │
 * │                                                                  │
 * │  Narrowed Search 1:                                              │
 * │  - Comparison: Greater Than 2000                                 │
 * │                                                                  │
 * │  Narrowed Search 2:                                              │
 * │  - Comparison: Less Than 4000                                    │
 * │                                                                  │
 * │  Final Results: Values between 2000 and 4000                     │
 * │                                                                  │
 * └─────────────────────────────────────────────────────────────────┘
 */
- (void)testComplexSearchCriteria
{
    // Create search data for 32-bit integers between 1000 and 5000
    int32_t lowerBound = 1000;
    ZGSearchData *searchData = [self searchDataFromBytes:&lowerBound size:sizeof(lowerBound) dataType:ZGInt32 address:_allocatedAddress alignment:sizeof(int32_t)];
    
    int32_t *upperBound = malloc(sizeof(*upperBound));
    *upperBound = 5000;
    searchData.rangeValue = upperBound;
    
    // Set big endian mode
    searchData.bytesSwapped = YES;
    
    // Perform initial search
    ZGSearchResults *initialResults = ZGSearchForData(_processTask, searchData, nil, ZGInt32, ZGSigned, ZGBetween);
    XCTAssertGreaterThan(initialResults.count, 0);
    
    // Create new bounds for narrowing
    int32_t narrowLowerBound = 2000;
    ZGSearchData *narrowSearchData = [self searchDataFromBytes:&narrowLowerBound size:sizeof(narrowLowerBound) dataType:ZGInt32 address:_allocatedAddress alignment:sizeof(int32_t)];
    narrowSearchData.bytesSwapped = YES;
    
    // Narrow to values greater than 2000
    ZGSearchResults *narrowedResults1 = ZGNarrowSearchForData(_processTask, NO, narrowSearchData, nil, ZGInt32, ZGSigned, ZGGreaterThan, [[ZGSearchResults alloc] initWithResultSets:@[] resultType:ZGSearchResultTypeDirect dataType:ZGInt32 stride:sizeof(ZGMemoryAddress) unalignedAccess:NO], initialResults);
    XCTAssertGreaterThan(narrowedResults1.count, 0);
    XCTAssertLessThan(narrowedResults1.count, initialResults.count);
    
    // Create upper bound for second narrowing
    int32_t narrowUpperBound = 4000;
    ZGSearchData *narrowSearchData2 = [self searchDataFromBytes:&narrowUpperBound size:sizeof(narrowUpperBound) dataType:ZGInt32 address:_allocatedAddress alignment:sizeof(int32_t)];
    narrowSearchData2.bytesSwapped = YES;
    
    // Narrow to values less than 4000
    ZGSearchResults *narrowedResults2 = ZGNarrowSearchForData(_processTask, NO, narrowSearchData2, nil, ZGInt32, ZGSigned, ZGLessThan, [[ZGSearchResults alloc] initWithResultSets:@[] resultType:ZGSearchResultTypeDirect dataType:ZGInt32 stride:sizeof(ZGMemoryAddress) unalignedAccess:NO], narrowedResults1);
    XCTAssertGreaterThan(narrowedResults2.count, 0);
    XCTAssertLessThan(narrowedResults2.count, narrowedResults1.count);
    
    // Verify results are between 2000 and 4000
    __block BOOL allResultsInRange = YES;
    [narrowedResults2 enumerateWithCount:narrowedResults2.count removeResults:NO usingBlock:^(const void *resultAddressData, BOOL *stop) {
        ZGMemoryAddress resultAddress = *(const ZGMemoryAddress *)resultAddressData;
        
        int32_t *valuePtr = NULL;
        ZGMemorySize size = sizeof(int32_t);
        if (!ZGReadBytes(_processTask, resultAddress, (void **)&valuePtr, &size)) {
            XCTFail(@"Failed to read value at address %llX", resultAddress);
            allResultsInRange = NO;
            *stop = YES;
            return;
        }
        
        // Convert from big endian to host
        int32_t value = (int32_t)CFSwapInt32BigToHost(*(uint32_t *)valuePtr);
        
        if (value < 2000 || value >= 4000) {
            XCTFail(@"Value %d at address %llX is outside expected range [2000, 4000)", value, resultAddress);
            allResultsInRange = NO;
            *stop = YES;
        }
        
        ZGFreeBytes(valuePtr, size);
    }];
    
    XCTAssertTrue(allResultsInRange);
    
    free(upperBound);
}

/**
 * Tests searching for values with wildcard patterns in different data types.
 *
 * This test:
 * 1. Allocates memory and writes test data to it
 * 2. Performs searches with wildcard patterns in different data types
 * 3. Verifies the search results match expectations
 *
 * Wildcard patterns across data types:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │                Wildcard Patterns Across Data Types               │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                                                                  │
 * │  Byte Array Wildcards:                                           │
 * │  Pattern: "A? B* CD"                                             │
 * │  Matches: "A1 B2 CD", "A5 BF CD", etc.                           │
 * │                                                                  │
 * │  String Wildcards (case-insensitive):                            │
 * │  Pattern: "Hello"                                                │
 * │  Matches: "hello", "HELLO", "Hello", etc.                        │
 * │                                                                  │
 * │  Floating Point Wildcards (epsilon):                             │
 * │  Value: 3.14159                                                  │
 * │  Epsilon: 0.001                                                  │
 * │  Matches: 3.14059 to 3.14259                                     │
 * │                                                                  │
 * └─────────────────────────────────────────────────────────────────┘
 */
- (void)testWildcardPatternsAcrossDataTypes
{
    // Test 1: Byte Array Wildcards
    // Write a specific pattern to memory
    uint8_t testPattern[] = {0xA1, 0xB2, 0xCD, 0xEF};
    if (!ZGWriteBytes(_processTask, _allocatedAddress + 0x100, testPattern, sizeof(testPattern))) {
        XCTFail(@"Failed to write test pattern");
    }
    
    // Create a wildcard search pattern
    NSString *wildcardExpression = @"A? B* CD ??";
    unsigned char *byteArrayFlags = ZGAllocateFlagsForByteArrayWildcards(wildcardExpression);
    XCTAssertNotNil((__bridge id)byteArrayFlags);
    
    ZGSearchData *byteArraySearchData = [[ZGSearchData alloc] initWithSearchValue:ZGValueFromString(ZGProcessTypeX86_64, wildcardExpression, ZGByteArray, NULL) dataSize:4 dataAlignment:1 pointerSize:8];
    byteArraySearchData.beginAddress = _allocatedAddress;
    byteArraySearchData.endAddress = _allocatedAddress + _data.length;
    byteArraySearchData.byteArrayFlags = byteArrayFlags;
    
    ZGSearchResults *byteArrayResults = ZGSearchForData(_processTask, byteArraySearchData, nil, ZGByteArray, 0, ZGEquals);
    XCTAssertGreaterThan(byteArrayResults.count, 0);
    
    // Test 2: String Wildcards (case-insensitive)
    // Write a string to memory
    const char *testString = "Hello World";
    if (!ZGWriteBytes(_processTask, _allocatedAddress + 0x200, testString, strlen(testString) + 1)) {
        XCTFail(@"Failed to write test string");
    }
    
    // Create a case-insensitive string search
    ZGSearchData *stringSearchData = [[ZGSearchData alloc] initWithSearchValue:(void *)"hello" dataSize:5 dataAlignment:1 pointerSize:8];
    stringSearchData.beginAddress = _allocatedAddress;
    stringSearchData.endAddress = _allocatedAddress + _data.length;
    stringSearchData.shouldIgnoreStringCase = YES;
    
    ZGSearchResults *stringResults = ZGSearchForData(_processTask, stringSearchData, nil, ZGString8, 0, ZGEquals);
    XCTAssertGreaterThan(stringResults.count, 0);
    
    // Test 3: Floating Point Wildcards (epsilon)
    // Write a float value to memory
    float testFloat = 3.14159f;
    if (!ZGWriteBytes(_processTask, _allocatedAddress + 0x300, &testFloat, sizeof(testFloat))) {
        XCTFail(@"Failed to write test float");
    }
    
    // Create a float search with epsilon
    ZGSearchData *floatSearchData = [[ZGSearchData alloc] initWithSearchValue:&testFloat dataSize:sizeof(testFloat) dataAlignment:sizeof(float) pointerSize:8];
    floatSearchData.beginAddress = _allocatedAddress;
    floatSearchData.endAddress = _allocatedAddress + _data.length;
    floatSearchData.epsilon = 0.001;
    
    ZGSearchResults *floatResults = ZGSearchForData(_processTask, floatSearchData, nil, ZGFloat, 0, ZGEquals);
    XCTAssertGreaterThan(floatResults.count, 0);
    
    // Verify the float result includes our test value
    __block BOOL foundTestFloat = NO;
    [floatResults enumerateWithCount:floatResults.count removeResults:NO usingBlock:^(const void *resultAddressData, BOOL *stop) {
        ZGMemoryAddress resultAddress = *(const ZGMemoryAddress *)resultAddressData;
        if (resultAddress == _allocatedAddress + 0x300) {
            foundTestFloat = YES;
            *stop = YES;
        }
    }];
    
    XCTAssertTrue(foundTestFloat);
}

/**
 * Tests searching for values with multiple data types in the same memory region.
 *
 * This test:
 * 1. Allocates memory and writes different data types to it
 * 2. Performs searches for each data type
 * 3. Verifies that each search finds the correct values
 * 4. Tests for overlapping values of different types
 *
 * Mixed data types in memory:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │                  Mixed Data Types in Memory                      │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                                                                  │
 * │  Memory Layout:                                                  │
 * │  ┌────────┬────────┬────────┬────────┬────────┬────────┐        │
 * │  │ Int32  │ Float  │ String │ Int64  │ Double │ Bytes  │        │
 * │  │ 0x100  │ 0x104  │ 0x108  │ 0x110  │ 0x118  │ 0x120  │        │
 * │  └────────┴────────┴────────┴────────┴────────┴────────┘        │
 * │                                                                  │
 * │  Overlapping Interpretations:                                    │
 * │  - Bytes at 0x100 can be read as Int32 or Float                  │
 * │  - Bytes at 0x110 can be read as Int64 or two Int32s             │
 * │                                                                  │
 * │  Search Types:                                                   │
 * │  - Exact value matches for each type                             │
 * │  - Searching same memory with different interpretations          │
 * │                                                                  │
 * └─────────────────────────────────────────────────────────────────┘
 */
- (void)testMixedDataTypes
{
    // Write different data types to memory
    int32_t testInt32 = 0x12345678;
    float testFloat = 3.14159f;
    const char *testString = "Test String";
    int64_t testInt64 = 0x1122334455667788;
    double testDouble = 2.71828;
    uint8_t testBytes[] = {0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE};
    
    if (!ZGWriteBytes(_processTask, _allocatedAddress + 0x100, &testInt32, sizeof(testInt32))) {
        XCTFail(@"Failed to write test int32");
    }
    
    if (!ZGWriteBytes(_processTask, _allocatedAddress + 0x104, &testFloat, sizeof(testFloat))) {
        XCTFail(@"Failed to write test float");
    }
    
    if (!ZGWriteBytes(_processTask, _allocatedAddress + 0x108, testString, strlen(testString) + 1)) {
        XCTFail(@"Failed to write test string");
    }
    
    if (!ZGWriteBytes(_processTask, _allocatedAddress + 0x110, &testInt64, sizeof(testInt64))) {
        XCTFail(@"Failed to write test int64");
    }
    
    if (!ZGWriteBytes(_processTask, _allocatedAddress + 0x118, &testDouble, sizeof(testDouble))) {
        XCTFail(@"Failed to write test double");
    }
    
    if (!ZGWriteBytes(_processTask, _allocatedAddress + 0x120, testBytes, sizeof(testBytes))) {
        XCTFail(@"Failed to write test bytes");
    }
    
    // Test 1: Search for Int32
    ZGSearchData *int32SearchData = [self searchDataFromBytes:&testInt32 size:sizeof(testInt32) dataType:ZGInt32 address:_allocatedAddress alignment:sizeof(int32_t)];
    ZGSearchResults *int32Results = ZGSearchForData(_processTask, int32SearchData, nil, ZGInt32, ZGSigned, ZGEquals);
    
    // Verify Int32 result
    __block BOOL foundInt32 = NO;
    [int32Results enumerateWithCount:int32Results.count removeResults:NO usingBlock:^(const void *resultAddressData, BOOL *stop) {
        ZGMemoryAddress resultAddress = *(const ZGMemoryAddress *)resultAddressData;
        if (resultAddress == _allocatedAddress + 0x100) {
            foundInt32 = YES;
            *stop = YES;
        }
    }];
    
    XCTAssertTrue(foundInt32);
    
    // Test 2: Search for Float
    ZGSearchData *floatSearchData = [self searchDataFromBytes:&testFloat size:sizeof(testFloat) dataType:ZGFloat address:_allocatedAddress alignment:sizeof(float)];
    floatSearchData.epsilon = 0.0001;
    ZGSearchResults *floatResults = ZGSearchForData(_processTask, floatSearchData, nil, ZGFloat, 0, ZGEquals);
    
    // Verify Float result
    __block BOOL foundFloat = NO;
    [floatResults enumerateWithCount:floatResults.count removeResults:NO usingBlock:^(const void *resultAddressData, BOOL *stop) {
        ZGMemoryAddress resultAddress = *(const ZGMemoryAddress *)resultAddressData;
        if (resultAddress == _allocatedAddress + 0x104) {
            foundFloat = YES;
            *stop = YES;
        }
    }];
    
    XCTAssertTrue(foundFloat);
    
    // Test 3: Search for String
    ZGSearchData *stringSearchData = [[ZGSearchData alloc] initWithSearchValue:(void *)testString dataSize:strlen(testString) dataAlignment:1 pointerSize:8];
    stringSearchData.beginAddress = _allocatedAddress;
    stringSearchData.endAddress = _allocatedAddress + _data.length;
    
    ZGSearchResults *stringResults = ZGSearchForData(_processTask, stringSearchData, nil, ZGString8, 0, ZGEquals);
    
    // Verify String result
    __block BOOL foundString = NO;
    [stringResults enumerateWithCount:stringResults.count removeResults:NO usingBlock:^(const void *resultAddressData, BOOL *stop) {
        ZGMemoryAddress resultAddress = *(const ZGMemoryAddress *)resultAddressData;
        if (resultAddress == _allocatedAddress + 0x108) {
            foundString = YES;
            *stop = YES;
        }
    }];
    
    XCTAssertTrue(foundString);
    
    // Test 4: Search for Int64
    ZGSearchData *int64SearchData = [self searchDataFromBytes:&testInt64 size:sizeof(testInt64) dataType:ZGInt64 address:_allocatedAddress alignment:sizeof(int64_t)];
    ZGSearchResults *int64Results = ZGSearchForData(_processTask, int64SearchData, nil, ZGInt64, ZGSigned, ZGEquals);
    
    // Verify Int64 result
    __block BOOL foundInt64 = NO;
    [int64Results enumerateWithCount:int64Results.count removeResults:NO usingBlock:^(const void *resultAddressData, BOOL *stop) {
        ZGMemoryAddress resultAddress = *(const ZGMemoryAddress *)resultAddressData;
        if (resultAddress == _allocatedAddress + 0x110) {
            foundInt64 = YES;
            *stop = YES;
        }
    }];
    
    XCTAssertTrue(foundInt64);
    
    // Test 5: Search for the same memory as different types (overlapping interpretations)
    // Extract the upper 32 bits of the 64-bit integer
    int32_t upperInt32 = (int32_t)(testInt64 >> 32);
    
    ZGSearchData *upperInt32SearchData = [self searchDataFromBytes:&upperInt32 size:sizeof(upperInt32) dataType:ZGInt32 address:_allocatedAddress + 0x110 alignment:sizeof(int32_t)];
    ZGSearchResults *upperInt32Results = ZGSearchForData(_processTask, upperInt32SearchData, nil, ZGInt32, ZGSigned, ZGEquals);
    
    // Verify we can find the upper 32 bits as an Int32
    __block BOOL foundUpperInt32 = NO;
    [upperInt32Results enumerateWithCount:upperInt32Results.count removeResults:NO usingBlock:^(const void *resultAddressData, BOOL *stop) {
        ZGMemoryAddress resultAddress = *(const ZGMemoryAddress *)resultAddressData;
        if (resultAddress == _allocatedAddress + 0x114) {  // Upper 32 bits are at offset +4
            foundUpperInt32 = YES;
            *stop = YES;
        }
    }];
    
    XCTAssertTrue(foundUpperInt32);
}

/**
 * Tests searching for values with linear transformations and stored value comparisons.
 *
 * This test:
 * 1. Allocates memory and writes test data to it
 * 2. Stores the initial values
 * 3. Applies linear transformations to the values (ax + b)
 * 4. Searches for values that match the transformation
 * 5. Verifies the search results match expectations
 *
 * Linear transformations and stored values:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │            Linear Transformations and Stored Values              │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                                                                  │
 * │  Initial Values:                                                 │
 * │  - Int32 at 0x100: 100                                           │
 * │  - Int32 at 0x104: 200                                           │
 * │  - Int32 at 0x108: 300                                           │
 * │                                                                  │
 * │  Linear Transformation:                                          │
 * │  - Formula: new_value = old_value * 2 + 50                       │
 * │                                                                  │
 * │  Transformed Values:                                             │
 * │  - Int32 at 0x100: 250  (100 * 2 + 50)                           │
 * │  - Int32 at 0x104: 450  (200 * 2 + 50)                           │
 * │  - Int32 at 0x108: 650  (300 * 2 + 50)                           │
 * │                                                                  │
 * │  Search for values matching the transformation                   │
 * │                                                                  │
 * └─────────────────────────────────────────────────────────────────┘
 */
- (void)testLinearTransformationsAndStoredValues
{
    // Write initial values to memory
    int32_t initialValues[] = {100, 200, 300};
    
    if (!ZGWriteBytes(_processTask, _allocatedAddress + 0x100, initialValues, sizeof(initialValues))) {
        XCTFail(@"Failed to write initial values");
    }
    
    // Create search data for the initial values
    ZGSearchData *searchData = [[ZGSearchData alloc] initWithSearchValue:NULL dataSize:sizeof(int32_t) dataAlignment:sizeof(int32_t) pointerSize:8];
    searchData.beginAddress = _allocatedAddress + 0x100;
    searchData.endAddress = _allocatedAddress + 0x100 + sizeof(initialValues);
    
    // Store the initial values
    searchData.savedData = [ZGStoredData storedDataFromProcessTask:_processTask beginAddress:searchData.beginAddress endAddress:searchData.endAddress protectionMode:ZGProtectionAll includeSharedMemory:NO];
    XCTAssertNotNil(searchData.savedData);
    
    // Apply linear transformation: new_value = old_value * 2 + 50
    for (int i = 0; i < 3; i++) {
        int32_t newValue = initialValues[i] * 2 + 50;
        if (!ZGWriteBytes(_processTask, _allocatedAddress + 0x100 + i * sizeof(int32_t), &newValue, sizeof(newValue))) {
            XCTFail(@"Failed to write transformed value %d", i);
        }
    }
    
    // Set up linear transformation parameters
    int32_t *multiplicativeConstant = malloc(sizeof(*multiplicativeConstant));
    *multiplicativeConstant = 2;
    
    int32_t *additiveConstant = malloc(sizeof(*additiveConstant));
    *additiveConstant = 50;
    
    searchData.multiplicativeConstant = multiplicativeConstant;
    searchData.additiveConstant = additiveConstant;
    searchData.shouldCompareStoredValues = YES;
    
    // Search for values that match the linear transformation
    ZGSearchResults *results = ZGSearchForData(_processTask, searchData, nil, ZGInt32, ZGSigned, ZGEqualsStoredLinear);
    
    // Verify we found all three transformed values
    XCTAssertEqual(results.count, 3);
    
    // Verify each transformed value
    int32_t expectedValues[] = {250, 450, 650};
    
    __block BOOL allValuesCorrect = YES;
    __block int foundCount = 0;
    
    [results enumerateWithCount:results.count removeResults:NO usingBlock:^(const void *resultAddressData, BOOL *stop) {
        ZGMemoryAddress resultAddress = *(const ZGMemoryAddress *)resultAddressData;
        
        int32_t *valuePtr = NULL;
        ZGMemorySize size = sizeof(int32_t);
        if (!ZGReadBytes(_processTask, resultAddress, (void **)&valuePtr, &size)) {
            XCTFail(@"Failed to read value at address %llX", resultAddress);
            allValuesCorrect = NO;
            *stop = YES;
            return;
        }
        
        int32_t value = *valuePtr;
        int index = (int)((resultAddress - (_allocatedAddress + 0x100)) / sizeof(int32_t));
        
        if (index >= 0 && index < 3) {
            if (value != expectedValues[index]) {
                XCTFail(@"Value at index %d is %d, expected %d", index, value, expectedValues[index]);
                allValuesCorrect = NO;
                *stop = YES;
            } else {
                foundCount++;
            }
        }
        
        ZGFreeBytes(valuePtr, size);
    }];
    
    XCTAssertTrue(allValuesCorrect);
    XCTAssertEqual(foundCount, 3);
    
    free(multiplicativeConstant);
    free(additiveConstant);
}

/**
 * Tests searching for values across memory region boundaries.
 *
 * This test:
 * 1. Allocates memory with different protection regions
 * 2. Writes values that span across region boundaries
 * 3. Searches for these values
 * 4. Verifies that the search correctly handles region boundaries
 *
 * Cross-boundary search:
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
 * │  1. String spanning Region 1 and Region 2                        │
 * │  2. 64-bit integer spanning Region 2 and Region 3                │
 * │  3. Double spanning Region 3 and Region 4                        │
 * │                                                                  │
 * │  Search Challenges:                                              │
 * │  - Values split across different memory protection regions       │
 * │  - Handling of region transitions during search                  │
 * │                                                                  │
 * └─────────────────────────────────────────────────────────────────┘
 */
- (void)testCrossBoundarySearch
{
    // Calculate addresses at region boundaries
    ZGMemoryAddress region1Start = _allocatedAddress;
    ZGMemoryAddress region2Start = _allocatedAddress + _pageSize;
    ZGMemoryAddress region3Start = _allocatedAddress + _pageSize * 2;
    ZGMemoryAddress region4Start = _allocatedAddress + _pageSize * 3;
    
    // 1. Write a string that spans Region 1 and Region 2
    const char *crossBoundaryString = "This string spans across two memory regions for testing boundary handling";
    ZGMemorySize stringLength = strlen(crossBoundaryString) + 1;
    ZGMemoryAddress stringAddress = region2Start - stringLength / 2;  // Place string so it crosses the boundary
    
    if (!ZGWriteBytes(_processTask, stringAddress, crossBoundaryString, stringLength)) {
        XCTFail(@"Failed to write cross-boundary string");
    }
    
    // 2. Write a 64-bit integer that spans Region 2 and Region 3
    int64_t crossBoundaryInt64 = 0x1122334455667788;
    ZGMemoryAddress int64Address = region3Start - sizeof(int64_t) / 2;  // Place integer so it crosses the boundary
    
    if (!ZGWriteBytes(_processTask, int64Address, &crossBoundaryInt64, sizeof(crossBoundaryInt64))) {
        XCTFail(@"Failed to write cross-boundary int64");
    }
    
    // 3. Write a double that spans Region 3 and Region 4
    double crossBoundaryDouble = 3.14159265358979;
    ZGMemoryAddress doubleAddress = region4Start - sizeof(double) / 2;  // Place double so it crosses the boundary
    
    if (!ZGWriteBytes(_processTask, doubleAddress, &crossBoundaryDouble, sizeof(crossBoundaryDouble))) {
        XCTFail(@"Failed to write cross-boundary double");
    }
    
    // Test 1: Search for the cross-boundary string
    ZGSearchData *stringSearchData = [[ZGSearchData alloc] initWithSearchValue:(void *)crossBoundaryString dataSize:stringLength dataAlignment:1 pointerSize:8];
    stringSearchData.beginAddress = _allocatedAddress;
    stringSearchData.endAddress = _allocatedAddress + _data.length;
    
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
    
    // Test 2: Search for the cross-boundary int64
    ZGSearchData *int64SearchData = [self searchDataFromBytes:&crossBoundaryInt64 size:sizeof(crossBoundaryInt64) dataType:ZGInt64 address:_allocatedAddress alignment:1];  // Use alignment 1 to find misaligned values
    
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
    
    // Test 3: Search for the cross-boundary double
    ZGSearchData *doubleSearchData = [self searchDataFromBytes:&crossBoundaryDouble size:sizeof(crossBoundaryDouble) dataType:ZGDouble address:_allocatedAddress alignment:1];  // Use alignment 1 to find misaligned values
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
}

@end