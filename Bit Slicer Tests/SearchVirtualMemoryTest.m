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
	
	_task = [NSTask launchedTaskWithLaunchPath:taskPath arguments:@[@"man"]];
	
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

- (void)testInt8Search
{
	ZGMemoryAddress address = [self allocateDataIntoProcess];
	const uint8_t valueToFind = 0xB1;
	uint8_t * const value = malloc(sizeof(*value));
	if (value == NULL)
	{
		XCTFail(@"Failed to allocate memory for value...");
	}
	*value = valueToFind;
	
	ZGSearchData *searchData = [[ZGSearchData alloc] initWithSearchValue:value dataSize:sizeof(*value) dataAlignment:1 pointerSize:8];
	searchData.beginAddress = address;
	searchData.endAddress = address + _data.length;
	searchData.savedData = [ZGStoredData storedDataFromProcessTask:_processTask];
	
	ZGSearchResults *equalResults = ZGSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGEquals);
	XCTAssertEqual(equalResults.addressCount, 89U);
	
	ZGSearchResults *notEqualResults = ZGSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGNotEquals);
	XCTAssertEqual(notEqualResults.addressCount, _data.length - 89U);
	
	ZGSearchResults *greaterThanResults = ZGSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGGreaterThan);
	XCTAssertEqual(greaterThanResults.addressCount, 6228U);
	
	ZGSearchResults *lessThanResults = ZGSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGLessThan);
	XCTAssertEqual(lessThanResults.addressCount, 14163U);
	
	searchData.shouldCompareStoredValues = YES;
	ZGSearchResults *storedEqualResults = ZGSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGEquals);
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
	ZGSearchResults *storedEqualResultsNarrowed = ZGNarrowSearchForData(_processTask, searchData, nil, ZGInt8, ZGUnsigned, ZGEquals, emptyResults, storedEqualResults);
	XCTAssertEqual(storedEqualResultsNarrowed.addressCount, _data.length - 1);
	searchData.shouldCompareStoredValues = NO;
	
	if (!ZGWriteBytes(_processTask, address + 0x1, (uint8_t []){valueToFind}, 0x1))
	{
		XCTFail(@"Failed to revert 2nd byte");
	}
}

@end
