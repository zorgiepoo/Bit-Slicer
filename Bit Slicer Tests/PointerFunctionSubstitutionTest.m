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
#import "ZGCalculator.h"

#ifndef ZGCalculatePointerFunction
#define ZGCalculatePointerFunction @"ZGCalculatePointerFunction"
#endif

@interface ZGCalculator (Private)

+ (NSString *)expressionBySubstitutingCalculatePointerFunctionInExpression:(NSString *)expression;

@end

@interface PointerFunctionSubstitutionTest : XCTestCase

@end

@implementation PointerFunctionSubstitutionTest

- (void)testNoSubstitution
{
    XCTAssertEqualObjects([ZGCalculator expressionBySubstitutingCalculatePointerFunctionInExpression:@"1 + 2 + 0x3"], @"1 + 2 + 0x3");
}

- (void)testSimpleSubstitution
{
	XCTAssertEqualObjects([ZGCalculator expressionBySubstitutingCalculatePointerFunctionInExpression:@"[1 + 2] + 0x3"], ZGCalculatePointerFunction@"(1 + 2) + 0x3");
}

- (void)testNestedSubstitution
{
	XCTAssertEqualObjects([ZGCalculator expressionBySubstitutingCalculatePointerFunctionInExpression:@"[[1 + 2] + 0x3] + 4 + [10 + 3]"], ZGCalculatePointerFunction@"("ZGCalculatePointerFunction"(1 + 2) + 0x3) + 4 + "ZGCalculatePointerFunction"(10 + 3)");
}

- (void)testSubstitutionWithSingleQuotes
{
	NSString *expression = @"test('[1 + 2]') + 0x3";
	XCTAssertEqualObjects([ZGCalculator expressionBySubstitutingCalculatePointerFunctionInExpression:expression], expression);
}

- (void)testSubstitutionWithDoubleQuotes
{
	NSString *expression = @"test(\"[1 + 2]\") + 0x3";
	XCTAssertEqualObjects([ZGCalculator expressionBySubstitutingCalculatePointerFunctionInExpression:expression], expression);
}

- (void)testComplexSubstitution
{
	XCTAssertEqualObjects([ZGCalculator expressionBySubstitutingCalculatePointerFunctionInExpression:@"[base('[hello][ there') + 3] + \\\"[2]\\\""], ZGCalculatePointerFunction@"(base('[hello][ there') + 3) + \\\""ZGCalculatePointerFunction"(2)\\\"");
}

@end
