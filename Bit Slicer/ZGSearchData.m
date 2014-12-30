/*
 * Created by Mayur Pawashe on 7/21/12.
 *
 * Copyright (c) 2012 zgcoder
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

#import "ZGSearchData.h"
#import "ZGVirtualMemoryHelpers.h"

#define ZGSearchDataSearchValueKey @"ZGSearchDataSearchValueKey"
#define ZGSearchDataFunctionTypeKey @"ZGSearchDataFunctionTypeKey"
#define ZGSearchDataDataTypeKey @"ZGSearchDataDataTypeKey"
#define ZGSearchDataDataSizeKey @"ZGSearchDataDataSizeKey"
#define ZGSearchDataDataAlignmentKey @"ZGSearchDataDataAlignmentKey"
#define ZGSearchDataPointerSizeKey @"ZGSearchDataPointerSizeKey"
#define ZGSearchDataQualifierKey @"ZGSearchDataQualifierKey"
#define ZGSearchDataBeginAddressKey @"ZGSearchDataBeginAddressKey"
#define ZGSearchDataEndAddressKey @"ZGSearchDataEndAddressKey"
#define ZGSearchDataProtectionModeKey @"ZGSearchDataProtectionModeKey"
#define ZGSearchDataEpsilonKey @"ZGSearchDataEpsilonKey"
#define ZGSearchDataShouldIgnoreStringCaseKey @"ZGSearchDataShouldIgnoreStringCaseKey"
#define ZGSearchDataShouldIncludeNullTerminatorKey @"ZGSearchDataShouldIncludeNullTerminatorKey"
#define ZGSearchDataShouldCompareStoredValuesKey @"ZGSearchDataShouldCompareStoredValuesKey"
#define ZGSearchDataBytesSwappedKey @"ZGSearchDataBytesSwappedKey"
#define ZGSearchDataSwappedValueKey @"ZGSearchDataSwappedValueKey"
#define ZGSearchDataRangeValueKey @"ZGSearchDataRangeValueKey"
#define ZGSearchDataAdditiveConstantKey @"ZGSearchDataAdditiveConstantKey"
#define ZGSearchDataMultiplicativeConstantKey @"ZGSearchDataMultiplicativeConstantKey"
#define ZGSearchDataByteArrayFlagsKey @"ZGSearchDataByteArrayFlagsKey"

@implementation ZGSearchData

+ (BOOL)supportsSecureCoding
{
	return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeInt32:_functionType forKey:ZGSearchDataFunctionTypeKey];
	[coder encodeInt32:_dataType forKey:ZGSearchDataDataTypeKey];
	[coder encodeInt64:(int64_t)_dataSize forKey:ZGSearchDataDataSizeKey];
	[coder encodeInt64:(int64_t)_dataAlignment forKey:ZGSearchDataDataAlignmentKey];
	[coder encodeInt64:(int64_t)_pointerSize forKey:ZGSearchDataPointerSizeKey];
	[coder encodeInt32:_qualifier forKey:ZGSearchDataQualifierKey];
	
	[coder encodeInt64:(int64_t)_beginAddress forKey:ZGSearchDataBeginAddressKey];
	[coder encodeInt64:(int64_t)_endAddress forKey:ZGSearchDataEndAddressKey];
	[coder encodeInt32:_protectionMode forKey:ZGSearchDataProtectionModeKey];
	[coder encodeDouble:_epsilon forKey:ZGSearchDataEpsilonKey];
	
	[coder encodeBool:_shouldIgnoreStringCase forKey:ZGSearchDataShouldIgnoreStringCaseKey];
	[coder encodeBool:_shouldIncludeNullTerminator forKey:ZGSearchDataShouldIncludeNullTerminatorKey];
	[coder encodeBool:_shouldCompareStoredValues forKey:ZGSearchDataShouldCompareStoredValuesKey];
	[coder encodeBool:_bytesSwapped forKey:ZGSearchDataBytesSwappedKey];
	
	if (_searchValue != NULL)
	{
		[coder encodeBytes:_searchValue length:_dataSize forKey:ZGSearchDataSearchValueKey];
	}
	
	if (_swappedValue != NULL)
	{
		[coder encodeBytes:_swappedValue length:_dataSize forKey:ZGSearchDataSwappedValueKey];
	}
	
	if (_rangeValue != NULL)
	{
		[coder encodeBytes:_rangeValue length:_dataSize forKey:ZGSearchDataRangeValueKey];
	}
	
	if (_additiveConstant != NULL)
	{
		[coder encodeBytes:_additiveConstant length:_dataSize forKey:ZGSearchDataAdditiveConstantKey];
	}
	
	if (_multiplicativeConstant != NULL)
	{
		[coder encodeBytes:_multiplicativeConstant length:_dataSize forKey:ZGSearchDataMultiplicativeConstantKey];
	}
	
	if (_byteArrayFlags != NULL)
	{
		[coder encodeBytes:_byteArrayFlags length:_dataSize forKey:ZGSearchDataByteArrayFlagsKey];
	}
}

- (void)decodeWithDecoder:(NSCoder *)decoder getBytes:(void **)bytesReturned forKey:(NSString *)key expectedLength:(NSUInteger)expectedLength
{
	NSUInteger lengthDecoded = 0;
	const uint8_t *bytes = [decoder decodeBytesForKey:key returnedLength:&lengthDecoded];
	if (lengthDecoded == _dataSize)
	{
		*bytesReturned = malloc(expectedLength);
		memcpy(*bytesReturned, bytes, expectedLength);
	}
}

- (id)initWithCoder:(NSCoder *)decoder
{
	self = [super init];
	if (self == nil) return nil;
	
	_functionType = (uint16_t)[decoder decodeInt32ForKey:ZGSearchDataFunctionTypeKey];
	_dataType = (uint16_t)[decoder decodeInt32ForKey:ZGSearchDataDataTypeKey];
	_dataSize = (uint64_t)[decoder decodeInt64ForKey:ZGSearchDataDataSizeKey];
	_dataAlignment = (uint64_t)[decoder decodeInt64ForKey:ZGSearchDataDataAlignmentKey];
	_pointerSize = (uint64_t)[decoder decodeInt64ForKey:ZGSearchDataDataAlignmentKey];
	_qualifier = (uint16_t)[decoder decodeInt32ForKey:ZGSearchDataQualifierKey];
	
	_beginAddress = (uint64_t)[decoder decodeInt64ForKey:ZGSearchDataBeginAddressKey];
	_endAddress = (uint64_t)[decoder decodeInt64ForKey:ZGSearchDataEndAddressKey];
	_protectionMode = (uint16_t)[decoder decodeInt32ForKey:ZGSearchDataProtectionModeKey];
	_epsilon = [decoder decodeDoubleForKey:ZGSearchDataEpsilonKey];
	
	_shouldIgnoreStringCase = [decoder decodeBoolForKey:ZGSearchDataShouldIgnoreStringCaseKey];
	_shouldIncludeNullTerminator = [decoder decodeBoolForKey:ZGSearchDataShouldIncludeNullTerminatorKey];
	_shouldCompareStoredValues = [decoder decodeBoolForKey:ZGSearchDataShouldCompareStoredValuesKey];
	_bytesSwapped = [decoder decodeBoolForKey:ZGSearchDataBytesSwappedKey];
	
	[self decodeWithDecoder:decoder getBytes:&_searchValue forKey:ZGSearchDataSearchValueKey expectedLength:_dataSize];
	[self decodeWithDecoder:decoder getBytes:&_swappedValue forKey:ZGSearchDataSwappedValueKey expectedLength:_dataSize];
	[self decodeWithDecoder:decoder getBytes:&_rangeValue forKey:ZGSearchDataRangeValueKey expectedLength:_dataSize];
	[self decodeWithDecoder:decoder getBytes:&_additiveConstant forKey:ZGSearchDataAdditiveConstantKey expectedLength:_dataSize];
	[self decodeWithDecoder:decoder getBytes:&_multiplicativeConstant forKey:ZGSearchDataMultiplicativeConstantKey expectedLength:_dataSize];
	[self decodeWithDecoder:decoder getBytes:(void **)&_byteArrayFlags forKey:ZGSearchDataByteArrayFlagsKey expectedLength:_dataSize];
	
	UCCreateCollator(NULL, 0, kUCCollateCaseInsensitiveMask, &_collator);
	
	return self;
}

- (id)init
{
	return [self initWithSearchValue:NULL functionType:ZGEquals dataType:ZGInt32 dataSize:0 dataAlignment:1 pointerSize:0];
}

- (id)initWithSearchValue:(void *)searchValue dataSize:(ZGMemorySize)dataSize dataAlignment:(ZGMemorySize)dataAlignment pointerSize:(ZGMemorySize)pointerSize
{
	return [self initWithSearchValue:searchValue functionType:ZGEquals dataType:ZGInt32 dataSize:dataSize dataAlignment:dataAlignment pointerSize:pointerSize];
}

- (id)initWithSearchValue:(void *)searchValue functionType:(ZGFunctionType)functionType dataType:(ZGVariableType)dataType dataSize:(ZGMemorySize)dataSize dataAlignment:(ZGMemorySize)dataAlignment pointerSize:(ZGMemorySize)pointerSize
{
	self = [super init];
	if (self != nil)
	{
		UCCreateCollator(NULL, 0, kUCCollateCaseInsensitiveMask, &_collator);
		self.endAddress = MAX_MEMORY_ADDRESS;
		self.protectionMode = ZGProtectionAll;
		self.epsilon = DEFAULT_FLOATING_POINT_EPSILON;
		
		self.searchValue = searchValue;
		self.functionType = functionType;
		self.dataType = dataType;
		self.dataSize = dataSize;
		self.dataAlignment = dataAlignment;
		self.pointerSize = pointerSize;
	}
	return self;
}

- (void)dealloc
{
	UCDisposeCollator(&_collator);
	
	self.rangeValue = NULL;
	self.swappedValue = NULL;
	self.byteArrayFlags = NULL;
	self.searchValue = NULL;
	self.savedData = nil;
	self.additiveConstant = NULL;
}

- (void)setSearchValue:(void *)searchValue
{
	free(_searchValue);
	_searchValue = searchValue;
}

- (void)setSwappedValue:(void *)swappedValue
{
	free(_swappedValue);
	_swappedValue = swappedValue;
}

- (void)setRangeValue:(void *)newRangeValue
{
	free(_rangeValue);
	_rangeValue = newRangeValue;
}

- (void)setByteArrayFlags:(unsigned char *)newByteArrayFlags
{
	free(_byteArrayFlags);
	_byteArrayFlags = newByteArrayFlags;
}

- (void)setAdditiveConstant:(void *)additiveConstant
{
	free(_additiveConstant);
	_additiveConstant = additiveConstant;
}

- (void)setMultiplicativeConstant:(void *)multiplicativeConstant
{
	free(_multiplicativeConstant);
	_multiplicativeConstant = multiplicativeConstant;
}

@end
