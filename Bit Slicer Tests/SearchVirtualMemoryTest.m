/*
 * Created by Mayur Pawashe on 9/6/14.
 *
 * Copyright (c) 2014 zgcoder
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
#import "ZGUtilities.h"

@interface SearchVirtualMemoryTest : XCTestCase
{
	NSTask *_task;
	ZGMemoryMap _processTask;
	NSData *_data;
	ZGMemorySize _pageSize;
}

@end

@implementation SearchVirtualMemoryTest

- (void)setUp
{
    [super setUp];
	
    // Put setup code here. This method is called before the invocation of each test method in the class.
	
	_data = [NSData dataWithContentsOfFile:[[NSBundle bundleForClass:[self class]] pathForResource:@"random_data" ofType:@""]];
	XCTAssertNotNil(_data);
	
	NSString *taskPath = @"/usr/bin/man";
	if (![[NSFileManager defaultManager] fileExistsAtPath:taskPath])
	{
		XCTFail(@"%@ does not exist", taskPath);
	}
	
	_task = [[NSTask alloc] init];
	_task.launchPath = taskPath;
	_task.arguments = @[@"man"];
	_task.standardInput = [NSFileHandle fileHandleWithNullDevice];
	[_task launch];
	
	if (!ZGTaskForPID(_task.processIdentifier, &_processTask))
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
	[_task terminate];
	
    [super tearDown];
}

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
	
	ZGSearchData *searchData = [[ZGSearchData alloc] initWithSearchValue:bytes functionType:ZGEquals dataType:ZGByteArray dataSize:sizeof(firstBytes) dataAlignment:1 pointerSize:8];
	
	ZGSearchResults *results = ZGSearchForData(_processTask, searchData, nil);
	
	__block BOOL foundAddress = NO;
	[results enumerateUsingBlock:^(ZGMemoryAddress resultAddress, BOOL *stop) {
		if (resultAddress == address)
		{
			foundAddress = YES;
			*stop = YES;
		}
	}];
	
	XCTAssertTrue(foundAddress);
}

- (ZGSearchData *)searchDataFromBytes:(void *)bytes size:(ZGMemorySize)size address:(ZGMemoryAddress)address alignment:(ZGMemorySize)alignment
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
	
	return searchData;
}

- (void)testInt8Search
{
	ZGMemoryAddress address = [self allocateDataIntoProcess];
	uint8_t valueToFind = 0xB1;
	
	ZGSearchData *searchData = [self searchDataFromBytes:&valueToFind size:sizeof(valueToFind) address:address alignment:1];
	searchData.savedData = [ZGStoredData storedDataFromProcessTask:_processTask];
	XCTAssertNotNil(searchData.savedData);
	
	searchData.qualifier = ZGUnsigned; searchData.functionType = ZGEquals; searchData.dataType = ZGInt8;
	ZGSearchResults *equalResults = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(equalResults.addressCount, 89U);
	
	searchData.qualifier = ZGSigned; searchData.functionType = ZGEquals; searchData.dataType = ZGInt8;
	ZGSearchResults *equalSignedResults = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(equalSignedResults.addressCount, 89U);
	
	searchData.qualifier = ZGUnsigned; searchData.functionType = ZGNotEquals; searchData.dataType = ZGInt8;
	ZGSearchResults *notEqualResults = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(notEqualResults.addressCount, _data.length - 89U);
	
	searchData.qualifier = ZGUnsigned; searchData.functionType = ZGGreaterThan; searchData.dataType = ZGInt8;
	ZGSearchResults *greaterThanResults = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(greaterThanResults.addressCount, 6228U);
	
	searchData.qualifier = ZGUnsigned; searchData.functionType = ZGLessThan; searchData.dataType = ZGInt8;
	ZGSearchResults *lessThanResults = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(lessThanResults.addressCount, 14163U);
	
	searchData.qualifier = ZGUnsigned; searchData.functionType = ZGEqualsStored; searchData.dataType = ZGInt8;
	searchData.shouldCompareStoredValues = YES;
	ZGSearchResults *storedEqualResults = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(storedEqualResults.addressCount, _data.length);
	searchData.shouldCompareStoredValues = NO;
	
	if (!ZGWriteBytes(_processTask, address + 0x1, (uint8_t []){valueToFind - 1}, 0x1))
	{
		XCTFail(@"Failed to write 2nd byte");
	}
	
	ZGSearchResults *emptyResults = [[ZGSearchResults alloc] init];
	
	searchData.qualifier = ZGUnsigned; searchData.functionType = ZGEquals; searchData.dataType = ZGInt8;
	ZGSearchResults *equalNarrowResults = ZGNarrowSearchForData(_processTask, searchData, nil, emptyResults, equalResults);
	XCTAssertEqual(equalNarrowResults.addressCount, 88U);
	
	searchData.qualifier = ZGUnsigned; searchData.functionType = ZGNotEquals; searchData.dataType = ZGInt8;
	ZGSearchResults *notEqualNarrowResults = ZGNarrowSearchForData(_processTask, searchData, nil, emptyResults, equalResults);
	XCTAssertEqual(notEqualNarrowResults.addressCount, 1U);
	
	searchData.qualifier = ZGUnsigned; searchData.functionType = ZGGreaterThan; searchData.dataType = ZGInt8;
	ZGSearchResults *greaterThanNarrowResults = ZGNarrowSearchForData(_processTask, searchData, nil, emptyResults, equalResults);
	XCTAssertEqual(greaterThanNarrowResults.addressCount, 0U);
	
	searchData.qualifier = ZGUnsigned; searchData.functionType = ZGLessThan; searchData.dataType = ZGInt8;
	ZGSearchResults *lessThanNarrowResults = ZGNarrowSearchForData(_processTask, searchData, nil, emptyResults, equalResults);
	XCTAssertEqual(lessThanNarrowResults.addressCount, 1U);
	
	searchData.qualifier = ZGUnsigned; searchData.functionType = ZGEqualsStored; searchData.dataType = ZGInt8;
	searchData.shouldCompareStoredValues = YES;
	ZGSearchResults *storedEqualResultsNarrowed = ZGNarrowSearchForData(_processTask, searchData, nil, emptyResults, storedEqualResults);
	XCTAssertEqual(storedEqualResultsNarrowed.addressCount, _data.length - 1);
	searchData.shouldCompareStoredValues = NO;
	
	searchData.protectionMode = ZGProtectionExecute;
	
	searchData.qualifier = ZGUnsigned; searchData.functionType = ZGEquals; searchData.dataType = ZGInt8;
	ZGSearchResults *equalExecuteResults = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(equalExecuteResults.addressCount, 34U);
	
	// this will ignore the 2nd byte we changed since it's out of range
	searchData.qualifier = ZGUnsigned; searchData.functionType = ZGEquals; searchData.dataType = ZGInt8;
	ZGSearchResults *equalExecuteNarrowResults = ZGNarrowSearchForData(_processTask, searchData, nil, emptyResults, equalResults);
	XCTAssertEqual(equalExecuteNarrowResults.addressCount, 34U);
	
	ZGMemoryAddress *addressesRemoved = calloc(2, sizeof(*addressesRemoved));
	if (addressesRemoved == NULL) XCTFail(@"Failed to allocate memory for addressesRemoved");
	XCTAssertEqual(sizeof(ZGMemoryAddress), 8U);
	
	__block NSUInteger addressIndex = 0;
	[equalExecuteNarrowResults enumerateWithCount:2 usingBlock:^(ZGMemoryAddress resultAddress) {
		addressesRemoved[addressIndex] = resultAddress;
		addressIndex++;
	}];
	
	// first results do not have to be ordered
	addressesRemoved[0] ^= addressesRemoved[1];
	addressesRemoved[1] ^= addressesRemoved[0];
	addressesRemoved[0] ^= addressesRemoved[1];
	
	[equalExecuteNarrowResults removeNumberOfAddresses:2];
	
	searchData.qualifier = ZGUnsigned; searchData.functionType = ZGEquals; searchData.dataType = ZGInt8;
	ZGSearchResults *equalExecuteNarrowTwiceResults = ZGNarrowSearchForData(_processTask, searchData, nil, emptyResults, equalExecuteNarrowResults);
	XCTAssertEqual(equalExecuteNarrowTwiceResults.addressCount, 32U);
	
	ZGSearchResults *searchResultsRemoved = [[ZGSearchResults alloc] initWithResultSets:@[[NSData dataWithBytes:addressesRemoved length:2 * sizeof(*addressesRemoved)]] dataSize:sizeof(uint8_t) pointerSize:8];
	
	searchData.qualifier = ZGUnsigned; searchData.functionType = ZGEquals; searchData.dataType = ZGInt8;
	ZGSearchResults *equalExecuteNarrowTwiceAgainResults = ZGNarrowSearchForData(_processTask, searchData, nil, searchResultsRemoved, equalExecuteNarrowResults);
	XCTAssertEqual(equalExecuteNarrowTwiceAgainResults.addressCount, 34U);
	
	free(addressesRemoved);
	
	searchData.shouldCompareStoredValues = YES;
	searchData.qualifier = ZGUnsigned; searchData.functionType = ZGEqualsStored; searchData.dataType = ZGInt8;
	ZGSearchResults *storedEqualExecuteNarrowResults = ZGNarrowSearchForData(_processTask, searchData, nil, emptyResults, storedEqualResults);
	XCTAssertEqual(storedEqualExecuteNarrowResults.addressCount, _pageSize * 2);
	searchData.shouldCompareStoredValues = NO;
	
	if (!ZGWriteBytes(_processTask, address + 0x1, (uint8_t []){valueToFind}, 0x1))
	{
		XCTFail(@"Failed to revert 2nd byte");
	}
}

- (void)testInt16Search
{
	ZGMemoryAddress address = [self allocateDataIntoProcess];
	int16_t valueToFind = -13398; // AA CB
	
	ZGSearchData *searchData = [self searchDataFromBytes:&valueToFind size:sizeof(valueToFind) address:address alignment:sizeof(valueToFind)];
	
	searchData.qualifier = ZGSigned; searchData.functionType = ZGEquals; searchData.dataType = ZGInt16;
	ZGSearchResults *equalResults = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(equalResults.addressCount, 1U);
	
	searchData.beginAddress += 0x291;
	searchData.qualifier = ZGSigned; searchData.functionType = ZGEquals; searchData.dataType = ZGInt16;
	ZGSearchResults *misalignedEqualResults = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(misalignedEqualResults.addressCount, 1U);
	searchData.beginAddress -= 0x291;
	
	ZGSearchData *noAlignmentSearchData = [self searchDataFromBytes:&valueToFind size:sizeof(valueToFind) address:address alignment:1];
	
	noAlignmentSearchData.qualifier = ZGSigned; noAlignmentSearchData.functionType = ZGEquals; noAlignmentSearchData.dataType = ZGInt16;
	ZGSearchResults *noAlignmentEqualResults = ZGSearchForData(_processTask, noAlignmentSearchData, nil);
	XCTAssertEqual(noAlignmentEqualResults.addressCount, 2U);
	
	ZGMemoryAddress oldEndAddress = searchData.endAddress;
	searchData.beginAddress += 0x291;
	searchData.endAddress = searchData.beginAddress + 0x3;
	
	searchData.qualifier = ZGSigned; searchData.functionType = ZGEquals; searchData.dataType = ZGInt16;
	ZGSearchResults *noAlignmentRestrictedEqualResults = ZGNarrowSearchForData(_processTask, searchData, nil, [[ZGSearchResults alloc] init], noAlignmentEqualResults);
	XCTAssertEqual(noAlignmentRestrictedEqualResults.addressCount, 1U);
	
	searchData.beginAddress -= 0x291;
	searchData.endAddress = oldEndAddress;
	
	uint16_t *swappedValue = malloc(sizeof(*swappedValue));
	if (swappedValue == NULL) XCTFail(@"Fail malloc'ing swappedValue");
	*swappedValue = 0xCBAA;
	searchData.swappedValue = swappedValue;
	searchData.bytesSwapped = YES;
	
	searchData.qualifier = ZGUnsigned; searchData.functionType = ZGEquals; searchData.dataType = ZGInt16;
	ZGSearchResults *equalSwappedResults = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(equalSwappedResults.addressCount, 1U);
}

- (void)testInt32Search
{
	ZGMemoryAddress address = [self allocateDataIntoProcess];
	int32_t value = -300000000;
	ZGSearchData *searchData = [self searchDataFromBytes:&value size:sizeof(value) address:address alignment:sizeof(value)];
	
	int32_t *topBound = malloc(sizeof(*topBound));
	*topBound = 300000000;
	searchData.rangeValue = topBound;
	
	searchData.qualifier = ZGSigned; searchData.functionType = ZGGreaterThan; searchData.dataType = ZGInt32;
	ZGSearchResults *betweenResults = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(betweenResults.addressCount, 746U);
	
	int32_t *belowBound = malloc(sizeof(*belowBound));
	*belowBound = -600000000;
	searchData.rangeValue = belowBound;
	
	searchData.bytesSwapped = YES;
	
	searchData.qualifier = ZGSigned; searchData.functionType = ZGLessThan; searchData.dataType = ZGInt32;
	ZGSearchResults *betweenSwappedResults = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(betweenSwappedResults.addressCount, 354U);
	
	searchData.savedData = [ZGStoredData storedDataFromProcessTask:_processTask];
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
	
	searchData.qualifier = ZGSigned; searchData.functionType = ZGEqualsStoredLinear; searchData.dataType = ZGInt32;
	ZGSearchResults *narrowedSwappedAndStoredResults = ZGNarrowSearchForData(_processTask, searchData, nil, [[ZGSearchResults alloc] init], betweenSwappedResults);
	XCTAssertEqual(narrowedSwappedAndStoredResults.addressCount, 1U);
}

- (void)testInt64Search
{
	ZGMemoryAddress address = [self allocateDataIntoProcess];
	uint64_t value = 0x0B765697AFAA3400;
	
	ZGSearchData *searchData = [self searchDataFromBytes:&value size:sizeof(value) address:address alignment:sizeof(value)];
	searchData.qualifier = ZGUnsigned; searchData.functionType = ZGLessThan; searchData.dataType = ZGInt64;
	ZGSearchResults *results = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(results.addressCount, 132U);
	
	searchData.dataAlignment = sizeof(uint32_t);
	
	searchData.qualifier = ZGUnsigned; searchData.functionType = ZGLessThan; searchData.dataType = ZGInt64;
	ZGSearchResults *resultsWithHalfAlignment = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(resultsWithHalfAlignment.addressCount, 256U);
	
	searchData.dataAlignment = sizeof(uint64_t);
	
	searchData.bytesSwapped = YES;
	searchData.qualifier = ZGUnsigned; searchData.functionType = ZGLessThan; searchData.dataType = ZGInt64;
	ZGSearchResults *bigEndianResults = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(bigEndianResults.addressCount, 101U);
}

- (void)testFloatSearch
{
	ZGMemoryAddress address = [self allocateDataIntoProcess];
	float value = -0.036687f;
	ZGSearchData *searchData = [self searchDataFromBytes:&value size:sizeof(value) address:address alignment:sizeof(value)];
	searchData.epsilon = 0.0000001f;
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGFloat;
	ZGSearchResults *results = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(results.addressCount, 1U);
	
	searchData.epsilon = 0.01f;
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGFloat;
	ZGSearchResults *resultsWithBigEpsilon = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(resultsWithBigEpsilon.addressCount, 5U);
	
	float *bigEndianValue = malloc(sizeof(*bigEndianValue));
	if (bigEndianValue == NULL) XCTFail(@"bigEndianValue malloc'd is NULL");
	*bigEndianValue = 7522.56f;
	
	searchData.searchValue = bigEndianValue;
	searchData.bytesSwapped = YES;
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGFloat;
	ZGSearchResults *bigEndianResults = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(bigEndianResults.addressCount, 1U);
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGFloat;
	searchData.epsilon = 100.0f;
	ZGSearchResults *bigEndianResultsWithBigEpsilon = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(bigEndianResultsWithBigEpsilon.addressCount, 2U);
}

- (void)testDoubleSearch
{
	ZGMemoryAddress address = [self allocateDataIntoProcess];
	double value = 100.0;
	
	ZGSearchData *searchData = [self searchDataFromBytes:&value size:sizeof(value) address:address alignment:sizeof(value)];
	
	searchData.qualifier = 0; searchData.functionType = ZGGreaterThan; searchData.dataType = ZGDouble;
	ZGSearchResults *results = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(results.addressCount, 616U);
	
	searchData.dataAlignment = sizeof(float);
	searchData.endAddress = searchData.beginAddress + _pageSize;
	searchData.qualifier = 0; searchData.functionType = ZGGreaterThan; searchData.dataType = ZGDouble;
	ZGSearchResults *resultsWithHalfAlignment = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(resultsWithHalfAlignment.addressCount, 250U);
	
	searchData.dataAlignment = sizeof(double);
	
	double *newValue = malloc(sizeof(*newValue));
	if (newValue == NULL) XCTFail(@"Failed to malloc newValue");
	*newValue = 4.56194e56;
	
	searchData.searchValue = newValue;
	searchData.bytesSwapped = YES;
	searchData.epsilon = 1e57;
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGDouble;
	ZGSearchResults *swappedResults = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(swappedResults.addressCount, 302U);
}

- (void)test8BitStringSearch
{
	ZGMemoryAddress address = [self allocateDataIntoProcess];
	
	char *hello = "hello";
	if (!ZGWriteBytes(_processTask, address + 96, hello, strlen(hello))) XCTFail(@"Failed to write hello string 1");
	if (!ZGWriteBytes(_processTask, address + 150, hello, strlen(hello))) XCTFail(@"Failed to write hello string 2");
	if (!ZGWriteBytes(_processTask, address + 5000, hello, strlen(hello) + 1)) XCTFail(@"Failed to write hello string 3");
	
	ZGSearchData *searchData = [self searchDataFromBytes:hello size:strlen(hello) + 1 address:address alignment:1];
	searchData.dataSize -= 1; // ignore null terminator for now
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGString8;
	ZGSearchResults *results = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(results.addressCount, 3U);
	
	if (!ZGWriteBytes(_processTask, address + 96, "m", 1)) XCTFail(@"Failed to write m");
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGString8;
	ZGSearchResults *narrowedResults = ZGNarrowSearchForData(_processTask, searchData, nil, [[ZGSearchResults alloc] init], results);
	XCTAssertEqual(narrowedResults.addressCount, 2U);
	
	// .shouldIncludeNullTerminator field isn't "really" used for search functions; it's just a hint for UI state
	searchData.dataSize++;
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGString8;
	ZGSearchResults *narrowedTerminatedResults = ZGNarrowSearchForData(_processTask, searchData, nil, [[ZGSearchResults alloc] init], narrowedResults);
	XCTAssertEqual(narrowedTerminatedResults.addressCount, 1U);
	
	searchData.dataSize--;
	if (!ZGWriteBytes(_processTask, address + 150, "HeLLo", strlen(hello))) XCTFail(@"Failed to write mixed case string");
	searchData.shouldIgnoreStringCase = YES;
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGString8;
	ZGSearchResults *narrowedIgnoreCaseResults = ZGNarrowSearchForData(_processTask, searchData, nil, [[ZGSearchResults alloc] init], narrowedResults);
	XCTAssertEqual(narrowedIgnoreCaseResults.addressCount, 2U);
	
	if (!ZGWriteBytes(_processTask, address + 150, "M", 1)) XCTFail(@"Failed to write capital M");
	
	searchData.qualifier = 0; searchData.functionType = ZGNotEquals; searchData.dataType = ZGString8;
	ZGSearchResults *narrowedIgnoreCaseNotEqualsResults = ZGNarrowSearchForData(_processTask, searchData, nil, [[ZGSearchResults alloc] init], narrowedIgnoreCaseResults);
	XCTAssertEqual(narrowedIgnoreCaseNotEqualsResults.addressCount, 1U);
	
	searchData.shouldIgnoreStringCase = NO;
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGString8;
	ZGSearchResults *equalResultsAgain = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(equalResultsAgain.addressCount, 1U);
	
	searchData.beginAddress = address + _pageSize;
	searchData.endAddress = address + _pageSize * 2;
	
	searchData.qualifier = 0; searchData.functionType = ZGNotEquals; searchData.dataType = ZGString8;
	ZGSearchResults *notEqualResults = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(notEqualResults.addressCount, _pageSize - 1 - (strlen(hello) - 1)); // take account for bytes at end that won't be compared
}

- (void)test16BitStringSearch
{
	ZGMemoryAddress address = [self allocateDataIntoProcess];
	const char *hello = [@"hello" cStringUsingEncoding:NSUTF16LittleEndianStringEncoding];
	
	unichar *helloBytes = malloc((strlen("hello") + 1) * 2);
	if (helloBytes == NULL) XCTFail(@"Failed to write malloc hello bytes");
	memcpy(helloBytes, hello, strlen("hello") * 2);
	helloBytes[strlen("hello")] = 0x0;
	
	size_t helloLength = strlen("hello") * 2;
	
	if (!ZGWriteBytes(_processTask, address + 96, hello, helloLength)) XCTFail(@"Failed to write hello string 1");
	if (!ZGWriteBytes(_processTask, address + 150, hello, helloLength)) XCTFail(@"Failed to write hello string 2");
	if (!ZGWriteBytes(_processTask, address + 5000, hello, helloLength)) XCTFail(@"Failed to write hello string 3");
	if (!ZGWriteBytes(_processTask, address + 6001, hello, helloLength)) XCTFail(@"Failed to write hello string 4");
	
	ZGSearchData *searchData = [self searchDataFromBytes:helloBytes size:helloLength + 1 * 2 address:address alignment:2];
	searchData.dataSize -= 2 * 1;
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGString16;
	ZGSearchResults *equalResults = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(equalResults.addressCount, 3U);
	
	searchData.qualifier = 0; searchData.functionType = ZGNotEquals; searchData.dataType = ZGString16;
	ZGSearchResults *notEqualResults = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(notEqualResults.addressCount, _data.length / sizeof(unichar) - 3 - 4*5);
	
	searchData.dataAlignment = 1;
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGString16;
	ZGSearchResults *equalResultsWithNoAlignment = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(equalResultsWithNoAlignment.addressCount, 4U);
	
	searchData.dataAlignment = 2;
	
	const char *moo = [@"moo" cStringUsingEncoding:NSUTF16LittleEndianStringEncoding];
	size_t mooLength = strlen("moo") * 2;
	if (!ZGWriteBytes(_processTask, address + 5000, moo, mooLength)) XCTFail(@"Failed to write moo string");
	
	ZGSearchData *mooSearchData = [self searchDataFromBytes:(void *)moo size:mooLength address:address alignment:2];
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGString16;
	ZGSearchResults *equalNarrowedResults = ZGNarrowSearchForData(_processTask, mooSearchData, nil, [[ZGSearchResults alloc] init], equalResults);
	XCTAssertEqual(equalNarrowedResults.addressCount, 1U);
	
	mooSearchData.shouldIgnoreStringCase = YES;
	const char *mooMixedCase = [@"MoO" cStringUsingEncoding:NSUTF16LittleEndianStringEncoding];
	if (!ZGWriteBytes(_processTask, address + 5000, mooMixedCase, mooLength)) XCTFail(@"Failed to write moo mixed string");
	
	mooSearchData.qualifier = 0; mooSearchData.functionType = ZGEquals; mooSearchData.dataType = ZGString16;
	ZGSearchResults *equalNarrowedIgnoreCaseResults = ZGNarrowSearchForData(_processTask, mooSearchData, nil, [[ZGSearchResults alloc] init], equalResults);
	XCTAssertEqual(equalNarrowedIgnoreCaseResults.addressCount, 1U);
	
	const char *noo = [@"noo" cStringUsingEncoding:NSUTF16LittleEndianStringEncoding];
	size_t nooLength = strlen("noo") * 2;
	if (!ZGWriteBytes(_processTask, address + 5000, noo, nooLength)) XCTFail(@"Failed to write noo string");
	
	mooSearchData.qualifier = 0; mooSearchData.functionType = ZGEquals; mooSearchData.dataType = ZGString16;
	ZGSearchResults *equalNarrowedIgnoreCaseFalseResults = ZGNarrowSearchForData(_processTask, mooSearchData, nil, [[ZGSearchResults alloc] init], equalResults);
	XCTAssertEqual(equalNarrowedIgnoreCaseFalseResults.addressCount, 0U);
	
	searchData.qualifier = 0; searchData.functionType = ZGNotEquals; searchData.dataType = ZGString16;
	ZGSearchResults *notEqualNarrowedIgnoreCaseResults = ZGNarrowSearchForData(_processTask, searchData, nil, [[ZGSearchResults alloc] init], equalResults);
	XCTAssertEqual(notEqualNarrowedIgnoreCaseResults.addressCount, 1U);
	
	ZGSearchData *nooSearchData = [self searchDataFromBytes:(void *)noo size:nooLength address:address alignment:2];
	nooSearchData.beginAddress = address + _pageSize;
	nooSearchData.endAddress = address + _pageSize * 2;
	
	nooSearchData.qualifier = 0; nooSearchData.functionType = ZGEquals; nooSearchData.dataType = ZGString16;
	ZGSearchResults *nooEqualResults = ZGSearchForData(_processTask, nooSearchData, nil);
	XCTAssertEqual(nooEqualResults.addressCount, 1U);
	
	nooSearchData.qualifier = 0; nooSearchData.functionType = ZGNotEquals; nooSearchData.dataType = ZGString16;
	ZGSearchResults *nooNotEqualResults = ZGSearchForData(_processTask, nooSearchData, nil);
	XCTAssertEqual(nooNotEqualResults.addressCount, _pageSize / 2 - 1 - 2);
	
	const char *helloBig = [@"hello" cStringUsingEncoding:NSUTF16BigEndianStringEncoding];
	if (!ZGWriteBytes(_processTask, address + 7000, helloBig, helloLength)) XCTFail(@"Failed to write hello big string");
	
	char *helloBigCopy = malloc(strlen("hello") * 2);
	if (helloBigCopy == NULL) XCTFail(@"Failed to malloc hello big string copy");
	memcpy(helloBigCopy, helloBig, strlen("hello") * 2);
	
	searchData.swappedValue = helloBigCopy;
	searchData.bytesSwapped = YES;
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGString16;
	ZGSearchResults *equalResultsBig = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(equalResultsBig.addressCount, 1U);
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGString16;
	ZGSearchResults *equalResultsBigNarrow = ZGNarrowSearchForData(_processTask, searchData, nil, [[ZGSearchResults alloc] init], equalResultsBig);
	XCTAssertEqual(equalResultsBigNarrow.addressCount, 1U);
	
	const char *capitalH = [@"H" cStringUsingEncoding:NSUTF16BigEndianStringEncoding];
	if (!ZGWriteBytes(_processTask, address + 7000, capitalH, 2)) XCTFail(@"Failed to write capital H string");
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGString16;
	ZGSearchResults *equalResultsBigNarrowTwice = ZGNarrowSearchForData(_processTask, searchData, nil, [[ZGSearchResults alloc] init], equalResultsBigNarrow);
	XCTAssertEqual(equalResultsBigNarrowTwice.addressCount, 0U);
	
	searchData.qualifier = 0; searchData.functionType = ZGNotEquals; searchData.dataType = ZGString16;
	ZGSearchResults *notEqualResultsBigNarrowTwice = ZGNarrowSearchForData(_processTask, searchData, nil, [[ZGSearchResults alloc] init], equalResultsBigNarrow);
	XCTAssertEqual(notEqualResultsBigNarrowTwice.addressCount, 1U);
	
	searchData.shouldIgnoreStringCase = YES;
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGString16;
	ZGSearchResults *equalResultsBigNarrowThrice = ZGNarrowSearchForData(_processTask, searchData, nil, [[ZGSearchResults alloc] init], equalResultsBigNarrow);
	XCTAssertEqual(equalResultsBigNarrowThrice.addressCount, 1U);
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGString16;
	ZGSearchResults *equalResultsBigCaseInsenitive = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(equalResultsBigCaseInsenitive.addressCount, 1U);
	
	searchData.dataSize += 2 * 1;
	// .shouldIncludeNullTerminator is not necessary to set, only used for UI state
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGString16;
	ZGSearchResults *equalResultsBigCaseInsenitiveNullTerminatedNarrowed = ZGNarrowSearchForData(_processTask, searchData, nil, [[ZGSearchResults alloc] init], equalResultsBigCaseInsenitive);
	XCTAssertEqual(equalResultsBigCaseInsenitiveNullTerminatedNarrowed.addressCount, 0U);
	
	unichar zero = 0x0;
	if (!ZGWriteBytes(_processTask, address + 7000 + strlen("hello") * 2, &zero, sizeof(zero))) XCTFail(@"Failed to write zero");
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGString16;
	ZGSearchResults *equalResultsBigCaseInsenitiveNullTerminatedNarrowedTwice = ZGNarrowSearchForData(_processTask, searchData, nil, [[ZGSearchResults alloc] init], equalResultsBigCaseInsenitive);
	XCTAssertEqual(equalResultsBigCaseInsenitiveNullTerminatedNarrowedTwice.addressCount, 1U);
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGString16;
	ZGSearchResults *equalResultsBigCaseInsensitiveNullTerminated = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(equalResultsBigCaseInsensitiveNullTerminated.addressCount, 1U);
	
	searchData.qualifier = 0; searchData.functionType = ZGNotEquals; searchData.dataType = ZGString16;
	ZGSearchResults *notEqualResultsBigCaseInsensitiveNullTerminated = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(notEqualResultsBigCaseInsensitiveNullTerminated.addressCount, _data.length / sizeof(unichar) - 5 * 5);
	
	searchData.shouldIgnoreStringCase = NO;
	searchData.bytesSwapped = NO;
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGString16;
	ZGSearchResults *equalResultsNullTerminated = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(equalResultsNullTerminated.addressCount, 0U);
	
	if (!ZGWriteBytes(_processTask, address + 96 + strlen("hello") * 2, &zero, sizeof(zero))) XCTFail(@"Failed to write zero 2nd time");
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGString16;
	ZGSearchResults *equalResultsNullTerminatedTwice = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(equalResultsNullTerminatedTwice.addressCount, 1U);
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGString16;
	ZGSearchResults *equalResultsNullTerminatedNarrowed = ZGNarrowSearchForData(_processTask, searchData, nil, [[ZGSearchResults alloc] init], equalResultsNullTerminatedTwice);
	XCTAssertEqual(equalResultsNullTerminatedNarrowed.addressCount, 1U);
	
	if (!ZGWriteBytes(_processTask, address + 96 + strlen("hello") * 2, helloBytes, sizeof(zero))) XCTFail(@"Failed to write first character");
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGString16;
	ZGSearchResults *equalResultsNullTerminatedNarrowedTwice = ZGNarrowSearchForData(_processTask, searchData, nil, [[ZGSearchResults alloc] init], equalResultsNullTerminatedNarrowed);
	XCTAssertEqual(equalResultsNullTerminatedNarrowedTwice.addressCount, 0U);
	
	searchData.qualifier = 0; searchData.functionType = ZGNotEquals; searchData.dataType = ZGString16;
	ZGSearchResults *notEqualResultsNullTerminatedNarrowedTwice = ZGNarrowSearchForData(_processTask, searchData, nil, [[ZGSearchResults alloc] init], equalResultsNullTerminatedNarrowed);
	XCTAssertEqual(notEqualResultsNullTerminatedNarrowedTwice.addressCount, 1U);
}

- (void)testByteArraySearch
{
	ZGMemoryAddress address = [self allocateDataIntoProcess];
	uint8_t bytes[] = {0xC6, 0xED, 0x8F, 0x0D};
	
	ZGSearchData *searchData = [self searchDataFromBytes:bytes size:sizeof(bytes) address:address alignment:1];
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGByteArray;
	ZGSearchResults *equalResults = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(equalResults.addressCount, 1U);
	
	searchData.qualifier = 0; searchData.functionType = ZGNotEquals; searchData.dataType = ZGByteArray;
	ZGSearchResults *notEqualResults = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(notEqualResults.addressCount, _data.length - 1 - 3*5);
	
	uint8_t changedBytes[] = {0xC8, 0xED, 0xBF, 0x0D};
	if (!ZGWriteBytes(_processTask, address + 0x21D4, changedBytes, sizeof(changedBytes))) XCTFail(@"Failed to write changed bytes");
	
	NSString *wildcardExpression = @"C? ED *F 0D";
	unsigned char *byteArrayFlags = ZGAllocateFlagsForByteArrayWildcards(wildcardExpression);
	if (byteArrayFlags == NULL) XCTFail(@"Byte array flags is NULL");
	
	searchData.byteArrayFlags = byteArrayFlags;
	searchData.searchValue = ZGValueFromString(YES, wildcardExpression, ZGByteArray, NULL);
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGByteArray;
	ZGSearchResults *equalResultsWildcards = ZGSearchForData(_processTask, searchData, nil);
	XCTAssertEqual(equalResultsWildcards.addressCount, 1U);
	
	uint8_t changedBytesAgain[] = {0xD9, 0xED, 0xBF, 0x0D};
	if (!ZGWriteBytes(_processTask, address + 0x21D4, changedBytesAgain, sizeof(changedBytesAgain))) XCTFail(@"Failed to write changed bytes again");
	
	searchData.qualifier = 0; searchData.functionType = ZGEquals; searchData.dataType = ZGByteArray;
	ZGSearchResults *equalResultsWildcardsNarrowed = ZGNarrowSearchForData(_processTask, searchData, nil, [[ZGSearchResults alloc] init], equalResultsWildcards);
	XCTAssertEqual(equalResultsWildcardsNarrowed.addressCount, 0U);
	
	searchData.qualifier = 0; searchData.functionType = ZGNotEquals; searchData.dataType = ZGByteArray;
	ZGSearchResults *notEqualResultsWildcardsNarrowed = ZGNarrowSearchForData(_processTask, searchData, nil, [[ZGSearchResults alloc] init], equalResultsWildcards);
	XCTAssertEqual(notEqualResultsWildcardsNarrowed.addressCount, 1U);
}

@end
