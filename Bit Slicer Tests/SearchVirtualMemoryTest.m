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
	
	ZGSearchData *searchData = [[ZGSearchData alloc] initWithSearchValue:bytes dataSize:sizeof(firstBytes) dataAlignment:1 pointerSize:8];
	
	ZGSearchResults *results = ZGSearchForData(_processTask, searchData, nil, ZGByteArray, 0, ZGEquals);
	
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
	
	ZGSearchResults *equalResults = ZGSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGEquals);
	XCTAssertEqual(equalResults.addressCount, 89U);
	
	ZGSearchResults *equalSignedResults = ZGSearchForData(_processTask, searchData, nil, ZGInt8, ZGSigned, ZGEquals);
	XCTAssertEqual(equalSignedResults.addressCount, 89U);
	
	ZGSearchResults *notEqualResults = ZGSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGNotEquals);
	XCTAssertEqual(notEqualResults.addressCount, _data.length - 89U);
	
	ZGSearchResults *greaterThanResults = ZGSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGGreaterThan);
	XCTAssertEqual(greaterThanResults.addressCount, 6228U);
	
	ZGSearchResults *lessThanResults = ZGSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGLessThan);
	XCTAssertEqual(lessThanResults.addressCount, 14163U);
	
	searchData.shouldCompareStoredValues = YES;
	ZGSearchResults *storedEqualResults = ZGSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGEqualsStored);
	XCTAssertEqual(storedEqualResults.addressCount, _data.length);
	searchData.shouldCompareStoredValues = NO;
	
	if (!ZGWriteBytes(_processTask, address + 0x1, (uint8_t []){valueToFind - 1}, 0x1))
	{
		XCTFail(@"Failed to write 2nd byte");
	}
	
	ZGSearchResults *emptyResults = [[ZGSearchResults alloc] init];
	
	ZGSearchResults *equalNarrowResults = ZGNarrowSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGEquals, emptyResults, equalResults);
	XCTAssertEqual(equalNarrowResults.addressCount, 88U);
	
	ZGSearchResults *notEqualNarrowResults = ZGNarrowSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGNotEquals, emptyResults, equalResults);
	XCTAssertEqual(notEqualNarrowResults.addressCount, 1U);
	
	ZGSearchResults *greaterThanNarrowResults = ZGNarrowSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGGreaterThan, emptyResults, equalResults);
	XCTAssertEqual(greaterThanNarrowResults.addressCount, 0U);
	
	ZGSearchResults *lessThanNarrowResults = ZGNarrowSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGLessThan, emptyResults, equalResults);
	XCTAssertEqual(lessThanNarrowResults.addressCount, 1U);
	
	searchData.shouldCompareStoredValues = YES;
	ZGSearchResults *storedEqualResultsNarrowed = ZGNarrowSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGEqualsStored, emptyResults, storedEqualResults);
	XCTAssertEqual(storedEqualResultsNarrowed.addressCount, _data.length - 1);
	searchData.shouldCompareStoredValues = NO;
	
	searchData.protectionMode = ZGProtectionExecute;
	
	ZGSearchResults *equalExecuteResults = ZGSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGEquals);
	XCTAssertEqual(equalExecuteResults.addressCount, 34U);
	
	// this will ignore the 2nd byte we changed since it's out of range
	ZGSearchResults *equalExecuteNarrowResults = ZGNarrowSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGEquals, emptyResults, equalResults);
	XCTAssertEqual(equalExecuteNarrowResults.addressCount, 34U);
	
	ZGMemoryAddress *addressesRemoved = calloc(2, sizeof(*addressesRemoved));
	if (addressesRemoved == NULL) XCTFail(@"Failed to allocate memory for addressesRemoved");
	XCTAssertEqual(sizeof(ZGMemoryAddress), 8U);
	
	__block NSUInteger addressIndex = 0;
	[equalExecuteNarrowResults enumerateWithCount:2 usingBlock:^(ZGMemoryAddress resultAddress, __unused BOOL *stop) {
		addressesRemoved[addressIndex] = resultAddress;
		addressIndex++;
	}];
	
	// first results do not have to be ordered
	addressesRemoved[0] ^= addressesRemoved[1];
	addressesRemoved[1] ^= addressesRemoved[0];
	addressesRemoved[0] ^= addressesRemoved[1];
	
	[equalExecuteNarrowResults removeNumberOfAddresses:2];
	
	ZGSearchResults *equalExecuteNarrowTwiceResults = ZGNarrowSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGEquals, emptyResults, equalExecuteNarrowResults);
	XCTAssertEqual(equalExecuteNarrowTwiceResults.addressCount, 32U);
	
	ZGSearchResults *searchResultsRemoved = [[ZGSearchResults alloc] initWithResultSets:@[[NSData dataWithBytes:addressesRemoved length:2 * sizeof(*addressesRemoved)]] dataSize:sizeof(uint8_t) pointerSize:8];
	
	ZGSearchResults *equalExecuteNarrowTwiceAgainResults = ZGNarrowSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGEquals, searchResultsRemoved, equalExecuteNarrowResults);
	XCTAssertEqual(equalExecuteNarrowTwiceAgainResults.addressCount, 34U);
	
	free(addressesRemoved);
	
	searchData.shouldCompareStoredValues = YES;
	ZGSearchResults *storedEqualExecuteNarrowResults = ZGNarrowSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGEqualsStored, emptyResults, storedEqualResults);
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
	
	ZGSearchResults *equalResults = ZGSearchForData(_processTask, searchData, nil, ZGInt16, ZGSigned, ZGEquals);
	XCTAssertEqual(equalResults.addressCount, 1U);
	
	searchData.beginAddress += 0x291;
	ZGSearchResults *misalignedEqualResults = ZGSearchForData(_processTask, searchData, nil, ZGInt16, ZGSigned, ZGEquals);
	XCTAssertEqual(misalignedEqualResults.addressCount, 1U);
	searchData.beginAddress -= 0x291;
	
	ZGSearchData *noAlignmentSearchData = [self searchDataFromBytes:&valueToFind size:sizeof(valueToFind) address:address alignment:1];
	ZGSearchResults *noAlignmentEqualResults = ZGSearchForData(_processTask, noAlignmentSearchData, nil, ZGInt16, ZGSigned, ZGEquals);
	XCTAssertEqual(noAlignmentEqualResults.addressCount, 2U);
	
	ZGMemoryAddress oldEndAddress = searchData.endAddress;
	searchData.beginAddress += 0x291;
	searchData.endAddress = searchData.beginAddress + 0x3;
	
	ZGSearchResults *noAlignmentRestrictedEqualResults = ZGNarrowSearchForData(_processTask, searchData, nil, ZGInt16, ZGSigned, ZGEquals, [[ZGSearchResults alloc] init], noAlignmentEqualResults);
	XCTAssertEqual(noAlignmentRestrictedEqualResults.addressCount, 1U);
	
	searchData.beginAddress -= 0x291;
	searchData.endAddress = oldEndAddress;
	
	uint16_t *swappedValue = malloc(sizeof(*swappedValue));
	if (swappedValue == NULL) XCTFail(@"Fail malloc'ing swappedValue");
	*swappedValue = 0xCBAA;
	searchData.swappedValue = swappedValue;
	searchData.bytesSwapped = YES;
	
	ZGSearchResults *equalSwappedResults = ZGSearchForData(_processTask, searchData, nil, ZGInt16, ZGUnsigned, ZGEquals);
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
	
	ZGSearchResults *betweenResults = ZGSearchForData(_processTask, searchData, nil, ZGInt32, ZGSigned, ZGGreaterThan);
	XCTAssertEqual(betweenResults.addressCount, 746U);
	
	int32_t *belowBound = malloc(sizeof(*belowBound));
	*belowBound = -600000000;
	searchData.rangeValue = belowBound;
	
	searchData.bytesSwapped = YES;
	
	ZGSearchResults *betweenSwappedResults = ZGSearchForData(_processTask, searchData, nil, ZGInt32, ZGSigned, ZGLessThan);
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
	*additiveConstant = 10;
	double multiplicativeConstant = 3;
	
	searchData.additiveConstant = additiveConstant;
	searchData.multiplicativeConstant = multiplicativeConstant;
	searchData.shouldCompareStoredValues = YES;
	
	int32_t alteredInteger = (int32_t)CFSwapInt32HostToBig((uint32_t)((integerRead * multiplicativeConstant + *additiveConstant)));
	if (!ZGWriteBytesIgnoringProtection(_processTask, address + 0x54, &alteredInteger, sizeof(alteredInteger)))
	{
		XCTFail(@"Failed to write altered integer at offset 0x54");
	}
	
	ZGSearchResults *narrowedSwappedAndStoredResults = ZGNarrowSearchForData(_processTask, searchData, nil, ZGInt32, ZGSigned, ZGEqualsStoredLinear, [[ZGSearchResults alloc] init], betweenSwappedResults);
	XCTAssertEqual(narrowedSwappedAndStoredResults.addressCount, 1U);
}

- (void)testInt64Search
{
	ZGMemoryAddress address = [self allocateDataIntoProcess];
	uint64_t value = 0x0B765697AFAA3400;
	
	ZGSearchData *searchData = [self searchDataFromBytes:&value size:sizeof(value) address:address alignment:sizeof(value)];
	ZGSearchResults *results = ZGSearchForData(_processTask, searchData, nil, ZGInt64, ZGUnsigned, ZGLessThan);
	XCTAssertEqual(results.addressCount, 132U);
	
	searchData.dataAlignment = sizeof(uint32_t);
	
	ZGSearchResults *resultsWithHalfAlignment = ZGSearchForData(_processTask, searchData, nil, ZGInt64, ZGUnsigned, ZGLessThan);
	XCTAssertEqual(resultsWithHalfAlignment.addressCount, 256U);
	
	searchData.dataAlignment = sizeof(uint64_t);
	
	searchData.bytesSwapped = YES;
	ZGSearchResults *bigEndianResults = ZGSearchForData(_processTask, searchData, nil, ZGInt64, ZGUnsigned, ZGLessThan);
	XCTAssertEqual(bigEndianResults.addressCount, 101U);
}

- (void)testFloatSearch
{
	ZGMemoryAddress address = [self allocateDataIntoProcess];
	float value = -0.036687f;
	ZGSearchData *searchData = [self searchDataFromBytes:&value size:sizeof(value) address:address alignment:sizeof(value)];
	searchData.epsilon = 0.0000001f;
	
	ZGSearchResults *results = ZGSearchForData(_processTask, searchData, nil, ZGFloat, 0, ZGEquals);
	XCTAssertEqual(results.addressCount, 1U);
	
	searchData.epsilon = 0.01f;
	ZGSearchResults *resultsWithBigEpsilon = ZGSearchForData(_processTask, searchData, nil, ZGFloat, 0, ZGEquals);
	XCTAssertEqual(resultsWithBigEpsilon.addressCount, 5U);
	
	float *bigEndianValue = malloc(sizeof(*bigEndianValue));
	if (bigEndianValue == NULL) XCTFail(@"bigEndianValue malloc'd is NULL");
	*bigEndianValue = 7522.56f;
	
	searchData.searchValue = bigEndianValue;
	searchData.bytesSwapped = YES;
	
	ZGSearchResults *bigEndianResults = ZGSearchForData(_processTask, searchData, nil, ZGFloat, 0, ZGEquals);
	XCTAssertEqual(bigEndianResults.addressCount, 1U);
	
	searchData.epsilon = 100.0f;
	ZGSearchResults *bigEndianResultsWithBigEpsilon = ZGSearchForData(_processTask, searchData, nil, ZGFloat, 0, ZGEquals);
	XCTAssertEqual(bigEndianResultsWithBigEpsilon.addressCount, 2U);
}

- (void)testDoubleSearch
{
	ZGMemoryAddress address = [self allocateDataIntoProcess];
	double value = 100.0;
	
	ZGSearchData *searchData = [self searchDataFromBytes:&value size:sizeof(value) address:address alignment:sizeof(value)];
	
	ZGSearchResults *results = ZGSearchForData(_processTask, searchData, nil, ZGDouble, 0, ZGGreaterThan);
	XCTAssertEqual(results.addressCount, 616U);
	
	searchData.dataAlignment = sizeof(float);
	searchData.endAddress = searchData.beginAddress + _pageSize;
	
	ZGSearchResults *resultsWithHalfAlignment = ZGSearchForData(_processTask, searchData, nil, ZGDouble, 0, ZGGreaterThan);
	XCTAssertEqual(resultsWithHalfAlignment.addressCount, 250U);
	
	searchData.dataAlignment = sizeof(double);
	
	double *newValue = malloc(sizeof(*newValue));
	if (newValue == NULL) XCTFail(@"Failed to malloc newValue");
	*newValue = 4.56194e56;
	
	searchData.searchValue = newValue;
	searchData.bytesSwapped = YES;
	searchData.epsilon = 1e57;
	
	ZGSearchResults *swappedResults = ZGSearchForData(_processTask, searchData, nil, ZGDouble, 0, ZGEquals);
	XCTAssertEqual(swappedResults.addressCount, 302U);
}

@end
