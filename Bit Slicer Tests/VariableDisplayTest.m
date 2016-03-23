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
#import "ZGVariable.h"

@interface VariableDisplayTest : XCTestCase

@end

@implementation VariableDisplayTest

- (void)test8BitInteger
{
	ZGVariableType type = ZGInt8;
	CFByteOrder byteOrders[] = {CFByteOrderLittleEndian, CFByteOrderBigEndian};
	for (ZGMemorySize pointerSize = 4; pointerSize <= 8; pointerSize += 4)
	{
		for (uint8_t byteOrderIndex = 0; byteOrderIndex < sizeof(byteOrders) / sizeof(*byteOrders); byteOrderIndex++)
		{
			CFByteOrder byteOrder = byteOrders[byteOrderIndex];
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(int8_t []){0} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"0");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(int8_t []){0} size:0 address:0x0 type:type qualifier:ZGUnsigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"0");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(int8_t []){35} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"35");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(int8_t []){35} size:0 address:0x0 type:type qualifier:ZGUnsigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"35");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint8_t []){255} size:0 address:0x0 type:type qualifier:ZGUnsigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"255");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(int8_t []){127} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"127");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(int8_t []){-128} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"-128");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(int8_t []){-1} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"-1");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(int8_t []){-1} size:0 address:0x0 type:type qualifier:ZGUnsigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"255");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(int8_t []){(int8_t)256} size:0 address:0x0 type:type qualifier:ZGUnsigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"0");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(int8_t []){(int8_t)128} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"-128");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(int8_t []){(int8_t)-129} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"127");
		}
	}
}

- (void)test16BitInteger
{
	typedef uint16_t (*ZGByteOrderFunction)(uint16_t);
	
	CFByteOrder byteOrders[] = {CFByteOrderLittleEndian, CFByteOrderBigEndian};
	
	ZGVariableType type = ZGInt16;
	
	for (uint8_t byteOrderIndex = 0; byteOrderIndex < sizeof(byteOrders) / sizeof(*byteOrders); byteOrderIndex++)
	{
		CFByteOrder byteOrder = byteOrders[byteOrderIndex];
		ZGByteOrderFunction byteOrderFunction = (byteOrder == CFByteOrderLittleEndian) ? CFSwapInt16HostToLittle : CFSwapInt16HostToBig;
		
		for (ZGMemorySize pointerSize = 4; pointerSize <= 8; pointerSize += 4)
		{
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint16_t []){byteOrderFunction(0)} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"0");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint16_t []){byteOrderFunction(0)} size:0 address:0x0 type:type qualifier:ZGUnsigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"0");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint16_t []){byteOrderFunction(35)} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"35");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint16_t []){byteOrderFunction(35)} size:0 address:0x0 type:type qualifier:ZGUnsigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"35");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint16_t []){byteOrderFunction(65535)} size:0 address:0x0 type:type qualifier:ZGUnsigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"65535");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint16_t []){byteOrderFunction(32767)} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"32767");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint16_t []){byteOrderFunction((uint16_t)-32768)} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"-32768");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint16_t []){byteOrderFunction((uint16_t)-1)} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"-1");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint16_t []){byteOrderFunction((uint16_t)-1)} size:0 address:0x0 type:type qualifier:ZGUnsigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"65535");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint16_t []){byteOrderFunction((uint16_t)65536)} size:0 address:0x0 type:type qualifier:ZGUnsigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"0");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint16_t []){byteOrderFunction(32768)} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"-32768");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint16_t []){byteOrderFunction((uint16_t)-32769)} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"32767");
		}
	}
}

- (void)test32BitInteger
{
	typedef uint32_t (*ZGByteOrderFunction)(uint32_t);
	
	CFByteOrder byteOrders[] = {CFByteOrderLittleEndian, CFByteOrderBigEndian};
	
	ZGVariableType type = ZGInt32;
	
	for (uint8_t byteOrderIndex = 0; byteOrderIndex < sizeof(byteOrders) / sizeof(*byteOrders); byteOrderIndex++)
	{
		CFByteOrder byteOrder = byteOrders[byteOrderIndex];
		ZGByteOrderFunction byteOrderFunction = (byteOrder == CFByteOrderLittleEndian) ? CFSwapInt32HostToLittle : CFSwapInt32HostToBig;
		
		for (ZGMemorySize pointerSize = 4; pointerSize <= 8; pointerSize += 4)
		{
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint32_t []){byteOrderFunction(0)} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"0");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint32_t []){byteOrderFunction(0)} size:0 address:0x0 type:type qualifier:ZGUnsigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"0");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint32_t []){byteOrderFunction(35)} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"35");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint32_t []){byteOrderFunction(35)} size:0 address:0x0 type:type qualifier:ZGUnsigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"35");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint32_t []){byteOrderFunction(4294967295)} size:0 address:0x0 type:type qualifier:ZGUnsigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"4294967295");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint32_t []){byteOrderFunction(2147483647)} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"2147483647");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint32_t []){byteOrderFunction((uint32_t)-2147483648)} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"-2147483648");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint32_t []){byteOrderFunction((uint32_t)-1)} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"-1");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint32_t []){byteOrderFunction((uint32_t)-1)} size:0 address:0x0 type:type qualifier:ZGUnsigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"4294967295");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint32_t []){byteOrderFunction((uint32_t)4294967296)} size:0 address:0x0 type:type qualifier:ZGUnsigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"0");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint32_t []){byteOrderFunction(2147483648)} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"-2147483648");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint32_t []){byteOrderFunction((uint32_t)-2147483649)} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"2147483647");
		}
	}
}

- (void)test64BitInteger
{
	typedef uint64_t (*ZGByteOrderFunction)(uint64_t);
	
	CFByteOrder byteOrders[] = {CFByteOrderLittleEndian, CFByteOrderBigEndian};
	
	ZGVariableType type = ZGInt64;
	
	for (uint8_t byteOrderIndex = 0; byteOrderIndex < sizeof(byteOrders) / sizeof(*byteOrders); byteOrderIndex++)
	{
		CFByteOrder byteOrder = byteOrders[byteOrderIndex];
		ZGByteOrderFunction byteOrderFunction = (byteOrder == CFByteOrderLittleEndian) ? CFSwapInt64HostToLittle : CFSwapInt64HostToBig;
		
		for (ZGMemorySize pointerSize = 4; pointerSize <= 8; pointerSize += 4)
		{
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint64_t []){byteOrderFunction(0)} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"0");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint64_t []){byteOrderFunction(0)} size:0 address:0x0 type:type qualifier:ZGUnsigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"0");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint64_t []){byteOrderFunction(35)} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"35");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint64_t []){byteOrderFunction(35)} size:0 address:0x0 type:type qualifier:ZGUnsigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"35");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint64_t []){byteOrderFunction(18446744073709551615U)} size:0 address:0x0 type:type qualifier:ZGUnsigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"18446744073709551615");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint64_t []){byteOrderFunction(9223372036854775807)} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"9223372036854775807");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint64_t []){byteOrderFunction((uint64_t)-9223372036854775808U)} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"-9223372036854775808");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint64_t []){byteOrderFunction((uint64_t)-1)} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"-1");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint64_t []){byteOrderFunction((uint64_t)-1)} size:0 address:0x0 type:type qualifier:ZGUnsigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"18446744073709551615");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint64_t []){byteOrderFunction((uint64_t)18446744073709551615U + 1)} size:0 address:0x0 type:type qualifier:ZGUnsigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"0");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint64_t []){byteOrderFunction(9223372036854775808U)} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"-9223372036854775808");
			
			XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint64_t []){byteOrderFunction((uint64_t)-9223372036854775808U - 1)} size:0 address:0x0 type:type qualifier:ZGSigned pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"9223372036854775807");
		}
	}
}

static float ZGSwapFloatHostToLittle(float value)
{
	return value;
}

static float ZGSwapFloatHostToBig(float value)
{
	CFSwappedFloat32 swappedValue = *((CFSwappedFloat32 *)&value);
	return CFConvertFloat32SwappedToHost(swappedValue);
}

- (void)testFloat
{
	typedef float (*ZGByteOrderFunction)(float);
	
	CFByteOrder byteOrders[] = {CFByteOrderLittleEndian, CFByteOrderBigEndian};
	
	ZGVariableType type = ZGFloat;
	
	ZGVariableQualifier qualifiers[] = {ZGSigned, ZGUnsigned};
	
	for (uint8_t qualifierIndex = 0; qualifierIndex < sizeof(qualifiers) / sizeof(*qualifiers); qualifierIndex++)
	{
		ZGVariableQualifier qualifier = qualifiers[qualifierIndex];
		
		for (uint8_t byteOrderIndex = 0; byteOrderIndex < sizeof(byteOrders) / sizeof(*byteOrders); byteOrderIndex++)
		{
			CFByteOrder byteOrder = byteOrders[byteOrderIndex];
			ZGByteOrderFunction byteOrderFunction = (byteOrder == CFByteOrderLittleEndian) ? ZGSwapFloatHostToLittle : ZGSwapFloatHostToBig;
			
			for (ZGMemorySize pointerSize = 4; pointerSize <= 8; pointerSize += 4)
			{
				XCTAssertEqualWithAccuracy([[[[ZGVariable alloc] initWithValue:(float []){byteOrderFunction(0.0f)} size:0 address:0x0 type:type qualifier:qualifier pointerSize:pointerSize byteOrder:byteOrder] stringValue] floatValue], 0.0f, 0.01f);
				
				XCTAssertEqualWithAccuracy([[[[ZGVariable alloc] initWithValue:(float []){byteOrderFunction(35.0f)} size:0 address:0x0 type:type qualifier:qualifier pointerSize:pointerSize byteOrder:byteOrder] stringValue] floatValue], 35.0f, 0.01f);
				
				XCTAssertEqualWithAccuracy([[[[ZGVariable alloc] initWithValue:(float []){byteOrderFunction(-35.0f)} size:0 address:0x0 type:type qualifier:qualifier pointerSize:pointerSize byteOrder:byteOrder] stringValue] floatValue], -35.0f, 0.01f);
				
				XCTAssertEqualWithAccuracy([[[[ZGVariable alloc] initWithValue:(float []){byteOrderFunction(35345324.435f)} size:0 address:0x0 type:type qualifier:qualifier pointerSize:pointerSize byteOrder:byteOrder] stringValue] floatValue], 35345324.435f, 0.01f);
				
				XCTAssertEqualWithAccuracy([[[[ZGVariable alloc] initWithValue:(float []){byteOrderFunction(-35345324.435f)} size:0 address:0x0 type:type qualifier:qualifier pointerSize:pointerSize byteOrder:byteOrder] stringValue] floatValue], -35345324.435f, 0.01f);
			}
		}
	}
}

static double ZGSwapDoubleHostToLittle(double value)
{
	return value;
}

static double ZGSwapDoubleHostToBig(double value)
{
	CFSwappedFloat64 swappedValue = *((CFSwappedFloat64 *)&value);
	return CFConvertFloat64SwappedToHost(swappedValue);
}

- (void)testDouble
{
	typedef double (*ZGByteOrderFunction)(double);
	
	CFByteOrder byteOrders[] = {CFByteOrderLittleEndian, CFByteOrderBigEndian};
	
	ZGVariableType type = ZGDouble;
	
	ZGVariableQualifier qualifiers[] = {ZGSigned, ZGUnsigned};
	
	for (uint8_t qualifierIndex = 0; qualifierIndex < sizeof(qualifiers) / sizeof(*qualifiers); qualifierIndex++)
	{
		ZGVariableQualifier qualifier = qualifiers[qualifierIndex];
		
		for (uint8_t byteOrderIndex = 0; byteOrderIndex < sizeof(byteOrders) / sizeof(*byteOrders); byteOrderIndex++)
		{
			CFByteOrder byteOrder = byteOrders[byteOrderIndex];
			ZGByteOrderFunction byteOrderFunction = (byteOrder == CFByteOrderLittleEndian) ? ZGSwapDoubleHostToLittle : ZGSwapDoubleHostToBig;
			
			for (ZGMemorySize pointerSize = 4; pointerSize <= 8; pointerSize += 4)
			{
				XCTAssertEqualWithAccuracy([[[[ZGVariable alloc] initWithValue:(double []){byteOrderFunction(0.0)} size:0 address:0x0 type:type qualifier:qualifier pointerSize:pointerSize byteOrder:byteOrder] stringValue] floatValue], 0.0, 0.01);
				
				XCTAssertEqualWithAccuracy([[[[ZGVariable alloc] initWithValue:(double []){byteOrderFunction(35.0)} size:0 address:0x0 type:type qualifier:qualifier pointerSize:pointerSize byteOrder:byteOrder] stringValue] doubleValue], 35.0, 0.01);
				
				XCTAssertEqualWithAccuracy([[[[ZGVariable alloc] initWithValue:(double []){byteOrderFunction(-35.0)} size:0 address:0x0 type:type qualifier:qualifier pointerSize:pointerSize byteOrder:byteOrder] stringValue] doubleValue], -35.0, 0.01);
				
				XCTAssertEqualWithAccuracy([[[[ZGVariable alloc] initWithValue:(double []){byteOrderFunction(35345324.435)} size:0 address:0x0 type:type qualifier:qualifier pointerSize:pointerSize byteOrder:byteOrder] stringValue] doubleValue], 35345324.435, 0.01);
				
				XCTAssertEqualWithAccuracy([[[[ZGVariable alloc] initWithValue:(double []){byteOrderFunction(-35345324.435)} size:0 address:0x0 type:type qualifier:qualifier pointerSize:pointerSize byteOrder:byteOrder] stringValue] doubleValue], -35345324.435, 0.01);
				
				XCTAssertEqualWithAccuracy([[[[ZGVariable alloc] initWithValue:(double []){byteOrderFunction(-35345324.434345355415)} size:0 address:0x0 type:type qualifier:qualifier pointerSize:pointerSize byteOrder:byteOrder] stringValue] doubleValue], -35345324.434345355415, 0.01);
			}
		}
	}
}

- (void)testPointer
{
	ZGVariableType type = ZGPointer;
	ZGMemorySize size32Bit = sizeof(int32_t);
	ZGMemorySize size64Bit = sizeof(int64_t);
	
	ZGVariableQualifier qualifiers[] = {ZGSigned, ZGUnsigned};
	
	for (uint8_t qualifierIndex = 0; qualifierIndex < sizeof(qualifiers) / sizeof(*qualifiers); qualifierIndex++)
	{
		ZGVariableQualifier qualifier = qualifiers[qualifierIndex];
		
		XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint32_t []){0x0} size:0 address:0x0 type:type qualifier:qualifier pointerSize:size32Bit byteOrder:CFByteOrderLittleEndian] stringValue], @"0x0");
		
		XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint32_t []){CFSwapInt32HostToBig(0x0)} size:0 address:0x0 type:type qualifier:qualifier pointerSize:size32Bit byteOrder:CFByteOrderBigEndian] stringValue], @"0x0");
		
		XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint64_t []){0x0} size:0 address:0x0 type:type qualifier:qualifier pointerSize:size64Bit byteOrder:CFByteOrderLittleEndian] stringValue], @"0x0");
		
		XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint64_t []){CFSwapInt64HostToBig(0x0)} size:0 address:0x0 type:type qualifier:qualifier pointerSize:size64Bit byteOrder:CFByteOrderBigEndian] stringValue], @"0x0");
		
		XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint32_t []){0x1000} size:0 address:0x0 type:type qualifier:qualifier pointerSize:size32Bit byteOrder:CFByteOrderLittleEndian] stringValue], @"0x1000");
		
		XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint32_t []){CFSwapInt32HostToBig(0x1000)} size:0 address:0x0 type:type qualifier:qualifier pointerSize:size32Bit byteOrder:CFByteOrderBigEndian] stringValue], @"0x1000");
		
		XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint64_t []){0x1000} size:0 address:0x0 type:type qualifier:qualifier pointerSize:size64Bit byteOrder:CFByteOrderLittleEndian] stringValue], @"0x1000");
		
		XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint64_t []){CFSwapInt64HostToBig(0x1000)} size:0 address:0x0 type:type qualifier:qualifier pointerSize:size64Bit byteOrder:CFByteOrderBigEndian] stringValue], @"0x1000");
		
		XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint32_t []){(uint32_t)-1} size:0 address:0x0 type:type qualifier:qualifier pointerSize:size32Bit byteOrder:CFByteOrderLittleEndian] stringValue], @"0xFFFFFFFF");
		
		XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint32_t []){(uint32_t)-1} size:0 address:0x0 type:type qualifier:qualifier pointerSize:size32Bit byteOrder:CFByteOrderBigEndian] stringValue], @"0xFFFFFFFF");
		
		XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint64_t []){(uint64_t)-1} size:0 address:0x0 type:type qualifier:qualifier pointerSize:size64Bit byteOrder:CFByteOrderLittleEndian] stringValue], @"0xFFFFFFFFFFFFFFFF");
		
		XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:(uint64_t []){(uint64_t)-1} size:0 address:0x0 type:type qualifier:qualifier pointerSize:size64Bit byteOrder:CFByteOrderBigEndian] stringValue], @"0xFFFFFFFFFFFFFFFF");
	}
}

- (void)test8BitString
{
	ZGVariableType type = ZGString8;
	
	ZGVariableQualifier qualifiers[] = {ZGSigned, ZGUnsigned};
	CFByteOrder byteOrders[] = {CFByteOrderLittleEndian, CFByteOrderBigEndian};
	
	for (uint8_t byteOrderIndex = 0; byteOrderIndex < sizeof(byteOrders) / sizeof(*byteOrders); byteOrderIndex++)
	{
		CFByteOrder byteOrder = byteOrders[byteOrderIndex];
		NSStringEncoding stringEncoding = NSUTF8StringEncoding;
	
		for (uint8_t qualifierIndex = 0; qualifierIndex < sizeof(qualifiers) / sizeof(*qualifiers); qualifierIndex++)
		{
			ZGVariableQualifier qualifier = qualifiers[qualifierIndex];
			
			for (ZGMemorySize pointerSize = 4; pointerSize <= 8; pointerSize += 4)
			{
				NSString *testString = @"test";
				const char *testCString = [testString cStringUsingEncoding:stringEncoding];
				XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:testCString size:strlen(testCString) address:0x0 type:type qualifier:qualifier pointerSize:pointerSize byteOrder:byteOrder] stringValue], [NSString stringWithCString:testCString encoding:stringEncoding]);
				
				NSString *testString2 = @"test†å∫¢";
				const char *testCString2 = [testString2 cStringUsingEncoding:stringEncoding];
				XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:testCString2 size:strlen(testCString2) address:0x0 type:type qualifier:qualifier pointerSize:pointerSize byteOrder:byteOrder] stringValue], [NSString stringWithCString:testCString2 encoding:stringEncoding]);
				
				NSString *emptyString = @"";
				const char *emptyCString = [emptyString cStringUsingEncoding:stringEncoding];
				XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:emptyCString size:strlen(emptyCString) address:0x0 type:type qualifier:qualifier pointerSize:pointerSize byteOrder:byteOrder] stringValue], emptyString);
				
				NSString *longString = @"This is a really long string maybe. This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe. ";
				const char *longCString = [longString cStringUsingEncoding:stringEncoding];
				XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:longCString size:strlen(longCString) address:0x0 type:type qualifier:qualifier pointerSize:pointerSize byteOrder:byteOrder] stringValue], [NSString stringWithCString:longCString encoding:stringEncoding]);
			}
		}
	}
}

- (void)test16BitString
{
	ZGVariableType type = ZGString16;
	
	ZGVariableQualifier qualifiers[] = {ZGSigned, ZGUnsigned};
	CFByteOrder byteOrders[] = {CFByteOrderLittleEndian, CFByteOrderBigEndian};
	
	for (uint8_t byteOrderIndex = 0; byteOrderIndex < sizeof(byteOrders) / sizeof(*byteOrders); byteOrderIndex++)
	{
		CFByteOrder byteOrder = byteOrders[byteOrderIndex];
		NSStringEncoding stringEncoding = (byteOrder == CFByteOrderLittleEndian) ? NSUTF16LittleEndianStringEncoding : NSUTF16BigEndianStringEncoding;
		
		for (uint8_t qualifierIndex = 0; qualifierIndex < sizeof(qualifiers) / sizeof(*qualifiers); qualifierIndex++)
		{
			ZGVariableQualifier qualifier = qualifiers[qualifierIndex];
			
			for (ZGMemorySize pointerSize = 4; pointerSize <= 8; pointerSize += 4)
			{
				NSString *testString = @"test";
				const char *testCString = [testString cStringUsingEncoding:stringEncoding];
				XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:testCString size:strlen(testCString) address:0x0 type:type qualifier:qualifier pointerSize:pointerSize byteOrder:byteOrder] stringValue], [NSString stringWithCString:testCString encoding:stringEncoding]);
				
				NSString *testString2 = @"test†å∫¢";
				const char *testCString2 = [testString2 cStringUsingEncoding:stringEncoding];
				XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:testCString2 size:strlen(testCString2) address:0x0 type:type qualifier:qualifier pointerSize:pointerSize byteOrder:byteOrder] stringValue], [NSString stringWithCString:testCString2 encoding:stringEncoding]);
				
				NSString *emptyString = @"";
				const char *emptyCString = [emptyString cStringUsingEncoding:stringEncoding];
				XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:emptyCString size:strlen(emptyCString) address:0x0 type:type qualifier:qualifier pointerSize:pointerSize byteOrder:byteOrder] stringValue], emptyString);
				
				NSString *longString = @"This is a really long string maybe. This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe.  This is a really long string maybe. ";
				const char *longCString = [longString cStringUsingEncoding:stringEncoding];
				XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:longCString size:strlen(longCString) address:0x0 type:type qualifier:qualifier pointerSize:pointerSize byteOrder:byteOrder] stringValue], [NSString stringWithCString:longCString encoding:stringEncoding]);
			}
		}
	}
}

- (void)testByteArray
{
	ZGVariableType type = ZGByteArray;
	
	ZGVariableQualifier qualifiers[] = {ZGSigned, ZGUnsigned};
	CFByteOrder byteOrders[] = {CFByteOrderLittleEndian, CFByteOrderBigEndian};
	
	for (uint8_t byteOrderIndex = 0; byteOrderIndex < sizeof(byteOrders) / sizeof(*byteOrders); byteOrderIndex++)
	{
		CFByteOrder byteOrder = byteOrders[byteOrderIndex];
		
		for (ZGMemorySize pointerSize = 4; pointerSize <= 8; pointerSize += 4)
		{
			for (uint8_t qualifierIndex = 0; qualifierIndex < sizeof(qualifiers) / sizeof(*qualifiers); qualifierIndex++)
			{
				ZGVariableQualifier qualifier = qualifiers[qualifierIndex];
				
				uint8_t zeroByte[] = {0x0};
				XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:zeroByte size:sizeof(zeroByte) / sizeof(*zeroByte) address:0x0 type:type qualifier:qualifier pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"00");
				
				uint8_t moreBytes[] = {0x31, 0x37, 0x3A, 0x30, 0x33, 0x3A, 0x33, 0x38, 0x2D, 0xBF, 0x34, 0x30, 0x30, 0x22, 0x3E, 0x3C, 0xEF, 0x69, 0x76, 0x3E, 0x59, 0x6F, 0x75, 0x20, 0xCD, 0x61, 0x0A, 0x65, 0x20, 0x63, 0x6F, 0x6E, 0x01, 0x65, 0x63, 0x74, 0x65, 0x64, 0x3C, 0x2F, 0x64, 0x69, 0x76, 0xA9, 0x00, 0x2F, 0x73, 0x74, 0x61, 0xC4, 0x75, 0x73, 0x3E, 0x0A, 0x3C, 0xE3, 0x74, 0x61, 0x74, 0xEA, 0x73, 0x20, 0x74, 0x97, 0xFF};
				XCTAssertEqualObjects([[[ZGVariable alloc] initWithValue:moreBytes size:sizeof(moreBytes) / sizeof(*moreBytes) address:0x0 type:type qualifier:qualifier pointerSize:pointerSize byteOrder:byteOrder] stringValue], @"31 37 3A 30 33 3A 33 38 2D BF 34 30 30 22 3E 3C EF 69 76 3E 59 6F 75 20 CD 61 0A 65 20 63 6F 6E 01 65 63 74 65 64 3C 2F 64 69 76 A9 00 2F 73 74 61 C4 75 73 3E 0A 3C E3 74 61 74 EA 73 20 74 97 FF");
			}
		}
	}
}

- (void)testValueChanges
{
	ZGVariable *qualifierVariable = [[ZGVariable alloc] initWithValue:(int16_t []){-1} size:0 address:0x0 type:ZGInt16 qualifier:ZGSigned pointerSize:4];
	
	XCTAssertEqualObjects(qualifierVariable.stringValue, @"-1");
	qualifierVariable.qualifier = ZGUnsigned;
	XCTAssertEqualObjects(qualifierVariable.stringValue, @"65535");
	
	ZGVariable *pointerVariable = [[ZGVariable alloc] initWithValue:(uint64_t []){(uint64_t)-1} size:0 address:0x0 type:ZGPointer qualifier:0 pointerSize:8];
	
	XCTAssertEqualObjects(pointerVariable.stringValue, @"0xFFFFFFFFFFFFFFFF");
	
	[pointerVariable changePointerSize:4];
	pointerVariable.rawValue = (uint32_t []){(uint32_t)-1};
	
	XCTAssertEqualObjects(pointerVariable.stringValue, @"0xFFFFFFFF");
	
	const char bytes[] = {0x2F, 0x69, 0x64, 0x65, 0x76, 0x67, 0x61, 0x6D};
	ZGVariable *variable = [[ZGVariable alloc] initWithValue:bytes size:sizeof(bytes) address:0x0 type:ZGByteArray qualifier:ZGSigned pointerSize:8];
	
	XCTAssertEqualObjects(variable.stringValue, @"2F 69 64 65 76 67 61 6D");
	
	variable.type = ZGInt64;
	XCTAssertEqualObjects(variable.stringValue, @"7881694581079959855");
	
	variable.type = ZGPointer;
	XCTAssertEqualObjects(variable.stringValue, @"0x6D6167766564692F");
	
	variable.type = ZGDouble;
	XCTAssertEqualWithAccuracy(variable.stringValue.doubleValue, 767961929264841293731366562656048705960477551908476656233812722397297712617640351278125988225051212455210851023096632167375632746311296404609808752754370722979878879753872341953689744375426608481766446515351387392442368.0, 0.01);
	
	variable.type = ZGInt32;
	XCTAssertEqualObjects(variable.stringValue, @"1701079343");
	
	variable.type = ZGFloat;
	XCTAssertEqualWithAccuracy(variable.stringValue.floatValue, 67414990808058649640960.0f, 0.01f);
	
	variable.type = ZGInt16;
	XCTAssertEqualObjects(variable.stringValue, @"26927");
	
	variable.type = ZGInt8;
	XCTAssertEqualObjects(variable.stringValue, @"47");
	
	variable.type = ZGInt64;
	XCTAssertEqualObjects(variable.stringValue, @"7881694581079959855");
	
	variable.type = ZGString8;
	XCTAssertEqualObjects(variable.stringValue, [[NSString alloc] initWithBytes:bytes length:sizeof(bytes) encoding:NSUTF8StringEncoding]);
	
	variable.type = ZGString16;
	XCTAssertEqualObjects(variable.stringValue, [[NSString alloc] initWithBytes:bytes length:sizeof(bytes) encoding:NSUTF16LittleEndianStringEncoding]);
	
	variable.byteOrder = CFByteOrderBigEndian;
	
	variable.type = ZGByteArray;
	XCTAssertEqualObjects(variable.stringValue, @"2F 69 64 65 76 67 61 6D");
	
	variable.type = ZGInt64;
	XCTAssertEqualObjects(variable.stringValue, @"3416372179278193005");
	
	variable.type = ZGInt32;
	XCTAssertEqualObjects(variable.stringValue, @"795436133");
	
	variable.type = ZGFloat;
	XCTAssertEqualWithAccuracy(variable.stringValue.floatValue, 0.0f, 0.001f);
	
	variable.type = ZGDouble;
	XCTAssertEqualWithAccuracy(variable.stringValue.doubleValue, 0.0, 0.001);
	
	variable.type = ZGInt16;
	XCTAssertEqualObjects(variable.stringValue, @"12137");
	
	variable.type = ZGInt8;
	XCTAssertEqualObjects(variable.stringValue, @"47");
}

- (void)testAddress
{
	ZGVariableQualifier qualifiers[] = {ZGSigned, ZGUnsigned};
	CFByteOrder byteOrders[] = {CFByteOrderLittleEndian, CFByteOrderBigEndian};
	ZGVariableType types[] = {ZGInt8, ZGInt16, ZGInt32, ZGInt64, ZGFloat, ZGDouble, ZGString8, ZGString16, ZGPointer, ZGByteArray, ZGScript};
	
	for (uint8_t byteOrderIndex = 0; byteOrderIndex < sizeof(byteOrders) / sizeof(*byteOrders); byteOrderIndex++)
	{
		CFByteOrder byteOrder = byteOrders[byteOrderIndex];
		
		for (ZGMemorySize pointerSize = 4; pointerSize <= 8; pointerSize += 4)
		{
			for (uint8_t qualifierIndex = 0; qualifierIndex < sizeof(qualifiers) / sizeof(*qualifiers); qualifierIndex++)
			{
				ZGVariableQualifier qualifier = qualifiers[qualifierIndex];
				
				for (uint8_t typeIndex = 0; typeIndex < sizeof(types) / sizeof(*types); typeIndex++)
				{
					ZGVariableType type = types[typeIndex];
					
					ZGVariable *zeroAddressVariable = [[ZGVariable alloc] initWithValue:NULL size:0 address:0x0 type:type qualifier:qualifier pointerSize:pointerSize byteOrder:byteOrder];
					
					XCTAssertEqualObjects(zeroAddressVariable.addressStringValue, @"0x0");
					
					ZGVariable *bigVariableAddress = [[ZGVariable alloc] initWithValue:NULL size:0 address:0xFFFFFFFFFFFFFFFF type:type qualifier:qualifier pointerSize:pointerSize byteOrder:byteOrder];
					
					XCTAssertEqualObjects(bigVariableAddress.addressStringValue, @"0xFFFFFFFFFFFFFFFF");
					
					ZGVariable *variable = [[ZGVariable alloc] initWithValue:NULL size:0 address:0x1000 type:type qualifier:qualifier pointerSize:pointerSize byteOrder:byteOrder];
					
					XCTAssertEqualObjects(variable.addressStringValue, @"0x1000");
					
					variable.addressStringValue = @"0xFFFFFFFFFFFFFFFF";
					XCTAssertEqualObjects(variable.addressStringValue, @"0xFFFFFFFFFFFFFFFF");
					
					variable.addressStringValue = @"0x500";
					XCTAssertEqualObjects(variable.addressStringValue, @"0x500");
					
					variable.addressStringValue = @"-1";
					XCTAssertEqualObjects(variable.addressStringValue, @"0xFFFFFFFFFFFFFFFF");
					
					variable.addressStringValue = @"500";
					XCTAssertEqualObjects(variable.addressStringValue, @"0x1F4");
					
					variable.addressStringValue = @"0xFFFFFFFffFfFFFFF";
					XCTAssertEqualObjects(variable.addressStringValue, @"0xFFFFFFFFFFFFFFFF");
					
					variable.addressStringValue = @"9223372036854775807";
					XCTAssertEqualObjects(variable.addressStringValue, @"0x7FFFFFFFFFFFFFFF");
					
					variable.addressStringValue = @"18446744073709551615";
					XCTAssertEqualObjects(variable.addressStringValue, @"0xFFFFFFFFFFFFFFFF");
					
					variable.addressStringValue = @"tawft18446744073709551615";
					XCTAssertEqualObjects(variable.addressStringValue, @"0x0");
					
					variable.addressStringValue = @"0xmiit300";
					XCTAssertEqualObjects(variable.addressStringValue, @"0x0");
				}
			}
		}
	}
}

- (void)testDescription
{
	ZGVariableQualifier qualifiers[] = {ZGSigned, ZGUnsigned};
	CFByteOrder byteOrders[] = {CFByteOrderLittleEndian, CFByteOrderBigEndian};
	ZGVariableType types[] = {ZGInt8, ZGInt16, ZGInt32, ZGInt64, ZGFloat, ZGDouble, ZGString8, ZGString16, ZGPointer, ZGByteArray, ZGScript};
	
	for (uint8_t byteOrderIndex = 0; byteOrderIndex < sizeof(byteOrders) / sizeof(*byteOrders); byteOrderIndex++)
	{
		CFByteOrder byteOrder = byteOrders[byteOrderIndex];
		
		for (ZGMemorySize pointerSize = 4; pointerSize <= 8; pointerSize += 4)
		{
			for (uint8_t qualifierIndex = 0; qualifierIndex < sizeof(qualifiers) / sizeof(*qualifiers); qualifierIndex++)
			{
				ZGVariableQualifier qualifier = qualifiers[qualifierIndex];
				
				for (uint8_t typeIndex = 0; typeIndex < sizeof(types) / sizeof(*types); typeIndex++)
				{
					ZGVariableType type = types[typeIndex];
					
					ZGVariable *noDescriptionVariable = [[ZGVariable alloc] initWithValue:NULL size:0 address:0x0 type:type qualifier:qualifier pointerSize:pointerSize description:nil enabled:NO byteOrder:byteOrder];
					
					XCTAssertEqualObjects(noDescriptionVariable.fullAttributedDescription, nil);
					
					ZGVariable *emptyDescriptionVariable = [[ZGVariable alloc] initWithValue:NULL size:0 address:0x0 type:type qualifier:qualifier pointerSize:pointerSize description:[[NSAttributedString alloc] init] enabled:NO byteOrder:byteOrder];
					
					XCTAssertEqualObjects(emptyDescriptionVariable.fullAttributedDescription, [[NSAttributedString alloc] init]);
					XCTAssertEqualObjects(emptyDescriptionVariable.shortDescription, @"");
					XCTAssertEqualObjects(emptyDescriptionVariable.name, @"");
					
					ZGVariable *descriptiveVariable = [[ZGVariable alloc] initWithValue:NULL size:0 address:0x0 type:type qualifier:qualifier pointerSize:pointerSize description:[[NSAttributedString alloc] initWithString:@"This is the world\nlosing you forever\nin space"] enabled:NO byteOrder:byteOrder];
					
					XCTAssertEqualObjects(descriptiveVariable.fullAttributedDescription, [[NSAttributedString alloc] initWithString:@"This is the world\nlosing you forever\nin space"]);
					XCTAssertEqualObjects(descriptiveVariable.shortDescription, @"This is the world…");
					XCTAssertEqualObjects(descriptiveVariable.name, @"This is the world");
					
					descriptiveVariable.fullAttributedDescription = [[NSAttributedString alloc] initWithString:@"Testing a change\nAre we now?"];
					
					XCTAssertEqualObjects(descriptiveVariable.fullAttributedDescription, [[NSAttributedString alloc] initWithString:@"Testing a change\nAre we now?"]);
					XCTAssertEqualObjects(descriptiveVariable.shortDescription, @"Testing a change…");
					XCTAssertEqualObjects(descriptiveVariable.name, @"Testing a change");
					
					descriptiveVariable.fullAttributedDescription = [[NSAttributedString alloc] initWithString:@"Back to normal"];
					
					XCTAssertEqualObjects(descriptiveVariable.fullAttributedDescription, [[NSAttributedString alloc] initWithString:@"Back to normal"]);
					XCTAssertEqualObjects(descriptiveVariable.shortDescription, @"Back to normal");
					XCTAssertEqualObjects(descriptiveVariable.name, @"Back to normal");
				}
			}
		}
	}
}

@end
