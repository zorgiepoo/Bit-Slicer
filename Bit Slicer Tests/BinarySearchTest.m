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
#import "NSArrayAdditions.h"
#import "ZGVariableDataInfo.h"

@interface BinarySearchTest : XCTestCase

@end

@implementation BinarySearchTest

- (void)testOddLengthSearch
{
    NSArray<NSNumber *> *numbers = @[@1, @2, @4, @5, @7, @21, @25];
	for (NSNumber *target in numbers)
	{
		NSNumber *foundNumber = [numbers zgBinarySearchUsingBlock:^(NSNumber *number) { return [number compare:target]; }];
		XCTAssertEqualObjects(target, foundNumber);
	}
	
	XCTAssertNil([numbers zgBinarySearchUsingBlock:^(NSNumber *number) { return [@3 compare:number]; }]);
}

- (void)testEvenLengthSearch
{
	NSArray<NSNumber *> *numbers = @[@1, @2, @4, @5, @7, @21, @22, @25];
	for (NSNumber *target in numbers)
	{
		NSNumber *foundNumber = [numbers zgBinarySearchUsingBlock:^(NSNumber *number) { return [number compare:target]; }];
		XCTAssertEqualObjects(target, foundNumber);
	}
	
	XCTAssertNil([numbers zgBinarySearchUsingBlock:^(NSNumber *number) { return [@3 compare:number]; }]);
}

- (void)testOneElementSearch
{
	NSArray<NSNumber *> *numbers = @[@4];
	NSNumber *target = @4;
	NSNumber *foundNumber = [numbers zgBinarySearchUsingBlock:^(NSNumber *number) { return [target compare:number]; }];
	XCTAssertEqualObjects(target, foundNumber);
	
	XCTAssertNil([numbers zgBinarySearchUsingBlock:^(NSNumber *number) { return [@3 compare:number]; }]);
}

- (void)testZeroElementSearch
{
	NSArray<NSNumber *> *numbers = @[];
	XCTAssertNil([numbers zgBinarySearchUsingBlock:^(NSNumber *number) { return [@3 compare:number]; }]);
}

@end
