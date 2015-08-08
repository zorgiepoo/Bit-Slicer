/*
 * Copyright (c) 2012 Mayur Pawashe
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

@interface LinearExpressionParsingTest : XCTestCase

@end

@implementation LinearExpressionParsingTest

- (void)testExpression:(NSString *)expression withExpectedAdditiveConstant:(double)expectedAdditiveConstant expectedMultiplicativeConstant:(double)expectedMultiplicativeConstant
{
	NSString *additiveConstantString;
	NSString *multiplicativeConstantString;
	BOOL parsedExpression = [ZGCalculator parseLinearExpression:expression andGetAdditiveConstant:&additiveConstantString multiplicateConstant:&multiplicativeConstantString];

	XCTAssertTrue(parsedExpression);

	if (parsedExpression)
	{
		XCTAssertEqualWithAccuracy([additiveConstantString doubleValue], expectedAdditiveConstant, 0.01);
		XCTAssertEqualWithAccuracy([multiplicativeConstantString doubleValue], expectedMultiplicativeConstant, 0.01);
	}
}

- (void)testSimpleAdditiveAndMultiplicativeExpressions
{
	[self testExpression:@"5 + 3*$x" withExpectedAdditiveConstant:5 expectedMultiplicativeConstant:3];
	[self testExpression:@"3 + $x" withExpectedAdditiveConstant:3 expectedMultiplicativeConstant:1];
	[self testExpression:@"5 * $x" withExpectedAdditiveConstant:0 expectedMultiplicativeConstant:5];
	[self testExpression:@"$x" withExpectedAdditiveConstant:0 expectedMultiplicativeConstant:1];
}

- (void)testSimpleNegationAdditiveAndMultiplicativeExpressions
{
	[self testExpression:@"-5 + -3 *$x" withExpectedAdditiveConstant:-5 expectedMultiplicativeConstant:-3];
	[self testExpression:@"-3 + $x" withExpectedAdditiveConstant:-3 expectedMultiplicativeConstant:1];
	[self testExpression:@"-5 * $x" withExpectedAdditiveConstant:0 expectedMultiplicativeConstant:-5];
	[self testExpression:@"-$x" withExpectedAdditiveConstant:0 expectedMultiplicativeConstant:-1];
}

- (void)testSimpleSubtractionAdditiveAndMultiplicativeExpressions
{
	[self testExpression:@"5 - 3*$x" withExpectedAdditiveConstant:5 expectedMultiplicativeConstant:-3];
	[self testExpression:@"-5 - -3 *$x" withExpectedAdditiveConstant:-5 expectedMultiplicativeConstant:3];
	[self testExpression:@"-3 - $x" withExpectedAdditiveConstant:-3 expectedMultiplicativeConstant:-1];
	[self testExpression:@"-5 * $x" withExpectedAdditiveConstant:0 expectedMultiplicativeConstant:-5];
	[self testExpression:@"$x - 4" withExpectedAdditiveConstant:-4 expectedMultiplicativeConstant:1];
	[self testExpression:@"2 - $x" withExpectedAdditiveConstant:2 expectedMultiplicativeConstant:-1];
}

- (void)testSimpleDivisionAdditiveAndMultiplicativeExpressions
{
	[self testExpression:@"$x / 1" withExpectedAdditiveConstant:0 expectedMultiplicativeConstant:1];
	[self testExpression:@"$x / 5" withExpectedAdditiveConstant:0 expectedMultiplicativeConstant:0.2];
	[self testExpression:@"$x / -13" withExpectedAdditiveConstant:0 expectedMultiplicativeConstant:-0.07];
	[self testExpression:@"$x / 1 + 3" withExpectedAdditiveConstant:3 expectedMultiplicativeConstant:1];
	[self testExpression:@"-6 + $x / 3" withExpectedAdditiveConstant:-6 expectedMultiplicativeConstant:0.33];
}

- (void)testComplexAdditiveAndMultiplicativeExpressions
{
	[self testExpression:@"$x / 4 + (2 * 3 - 5)" withExpectedAdditiveConstant:1 expectedMultiplicativeConstant:0.25];
	[self testExpression:@"(2 / 5 * 3 - 5) - ($x / 4) * 3" withExpectedAdditiveConstant:-3.8 expectedMultiplicativeConstant:-0.75];
	[self testExpression:@"((2 / 5 * 3 - 5) - ($x / 4) * 3) * 10" withExpectedAdditiveConstant:-38 expectedMultiplicativeConstant:-7.5];
	[self testExpression:@"1 + (((2 / 5 * 3 - 5) - ($x / 4) * 3) * 10) * -2" withExpectedAdditiveConstant:77 expectedMultiplicativeConstant:15];
}

@end
