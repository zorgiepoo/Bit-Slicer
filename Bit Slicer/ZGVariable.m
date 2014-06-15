/*
 * Created by Mayur Pawashe on 10/29/09.
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

#import "ZGVariable.h"
#import "NSStringAdditions.h"

@interface ZGVariable ()
{
	NSString *_addressStringValue;
}

@property (readwrite, nonatomic) ZGMemoryAddress address;

@end

@implementation ZGVariable

NSString *ZGVariablePboardType = @"ZGVariablePboardType";

#define ZGAddressKey @"ZGAddressKey"
#define ZGSizeKey	 @"ZGSizeKey"
#define ZGEnabledKey @"ZGShouldBeSearchedKey" // value is for backwards compatibility
#define ZGIsFrozenKey @"ZGIsFrozenKey"
#define ZGTypeKey @"ZGTypeKey"
#define ZGQualifierKey @"ZGQualifierKey"
#define ZGByteOrderKey @"ZGByteOrderKey"
#define ZGValueKey @"ZGValueKey"
#define ZGFreezeValueKey @"ZGFreezeValueKey"
#define ZGDescriptionKey @"ZGDescriptionKey"
#define ZGNameKey @"ZGNameKey" // legacy
#define ZGDynamicAddressKey @"ZGIsPointerKey" // value is for backwards compatibility
#define ZGAddressFormulaKey @"ZGAddressFormulaKey"
#define ZGScriptKey @"ZGScriptKey"
#define ZGScriptCachePathKey @"ZGScriptCachePathKey"

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder
	 encodeInt64:(int64_t)self.address
	 forKey:ZGAddressKey];
	
	[coder
	 encodeInt64:(int64_t)self.size
	 forKey:ZGSizeKey];
	
	[coder
	 encodeBool:self.enabled
	 forKey:ZGEnabledKey];
	
	[coder
	 encodeBool:self.isFrozen
	 forKey:ZGIsFrozenKey];
	
	[coder
	 encodeInt32:self.type
	 forKey:ZGTypeKey];
	
	[coder
	 encodeInt32:self.qualifier
	 forKey:ZGQualifierKey];
	
	[coder
	 encodeInt32:(int32_t)self.byteOrder
	 forKey:ZGByteOrderKey];
	
	[coder
	 encodeObject:self.fullAttributedDescription
	 forKey:ZGDescriptionKey];
	
	// For backwards compatiblity with older versions
	[coder
	 encodeObject:self.name
	 forKey:ZGNameKey];
	
	[coder
	 encodeBool:self.usesDynamicAddress
	 forKey:ZGDynamicAddressKey];
	
	[coder
	 encodeObject:self.addressFormula
	 forKey:ZGAddressFormulaKey];
	
	if (self.rawValue != nil)
	{
		[coder
		 encodeBytes:self.rawValue
		 length:(NSUInteger)self.size
		 forKey:ZGValueKey];
	}
	
	if (self.freezeValue != nil)
	{
		[coder
		 encodeBytes:self.freezeValue
		 length:(NSUInteger)self.size
		 forKey:ZGFreezeValueKey];
	}
	
	if (self.scriptValue != nil)
	{
		[coder encodeObject:self.scriptValue forKey:ZGScriptKey];
	}
	
	if (self.cachedScriptPath != nil)
	{
		[coder encodeObject:self.cachedScriptPath forKey:ZGScriptCachePathKey];
	}
}

- (id)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	if (self != nil)
	{
		self.address = (uint64_t)[coder decodeInt64ForKey:ZGAddressKey];
		
		[self setAddressStringValue:nil];
		
		self.size = (uint64_t)[coder decodeInt64ForKey:ZGSizeKey];
		self.enabled = [coder decodeBoolForKey:ZGEnabledKey];
		self.isFrozen = [coder decodeBoolForKey:ZGIsFrozenKey];
		self.type = (ZGVariableType)[coder decodeInt32ForKey:ZGTypeKey];
		self.qualifier = (ZGVariableQualifier)[coder decodeInt32ForKey:ZGQualifierKey];
		self.byteOrder = [coder decodeInt32ForKey:ZGByteOrderKey];
		if (self.byteOrder == CFByteOrderUnknown)
		{
			self.byteOrder = CFByteOrderGetCurrent();
		}
		
		self.usesDynamicAddress = [coder decodeBoolForKey:ZGDynamicAddressKey];
		[self setAddressFormula:[coder decodeObjectForKey:ZGAddressFormulaKey]];
		
		NSAttributedString *variableDescription = [coder decodeObjectForKey:ZGDescriptionKey];
		if (variableDescription == nil)
		{
			variableDescription = [coder decodeObjectForKey:ZGNameKey];
		}
		self.fullAttributedDescription = variableDescription != nil ? variableDescription : [[NSAttributedString alloc] initWithString:@""];
		
		NSUInteger returnedLength = 0;
		const uint8_t *buffer =
		[coder
		 decodeBytesForKey:ZGValueKey
		 returnedLength:&returnedLength];
		
		if (returnedLength == self.size)
		{
			self.rawValue = (void *)buffer;
		}
		
		returnedLength = 0;
		buffer =
		[coder
		 decodeBytesForKey:ZGFreezeValueKey
		 returnedLength:&returnedLength];
		
		if (returnedLength == self.size)
		{
			self.freezeValue = (void *)buffer;
		}
		
		NSString *scriptValue = [coder decodeObjectForKey:ZGScriptKey];
		self.scriptValue = scriptValue != nil ? scriptValue : @"";
		
		self.cachedScriptPath = [coder decodeObjectForKey:ZGScriptCachePathKey];
		
		return self;
	}
	
	return self;
}

- (id)copyWithZone:(NSZone *)__unused zone
{
	NSData *archivedData = [NSKeyedArchiver archivedDataWithRootObject:self];
	return [NSKeyedUnarchiver unarchiveObjectWithData:archivedData];
}

+ (ZGMemorySize)sizeFromType:(ZGVariableType)type pointerSize:(ZGMemorySize)pointerSize
{
	ZGMemorySize size = 0;
	
	switch (type)
	{
		case ZGInt8:
			size = 1;
			break;
		case ZGInt16:
			size = 2;
			break;
		case ZGInt32:
		case ZGFloat:
			size = 4;
			break;
		case ZGInt64:
		case ZGDouble:
			size = 8;
			break;
		case ZGByteArray:
		case ZGScript:
			// Use an arbitrary size, anything is better than 0
			size = 4;
			break;
		case ZGPointer:
			size = pointerSize;
			break;
		case ZGString8:
		case ZGString16:
			break;
	}
	
	return size;
}

- (id)initWithValue:(void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)type qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize description:(NSAttributedString *)description enabled:(BOOL)enabled byteOrder:(CFByteOrder)byteOrder
{
	if ((self = [super init]))
	{
		self.size = size;
		self.type = type;
		
		if (!self.size)
		{
			self.size =
			[ZGVariable
			 sizeFromType:self.type
			 pointerSize:pointerSize];
		}
		
		self.address = address;
		self.qualifier = qualifier;
		self.enabled = enabled;
		
		self.byteOrder = byteOrder;
		
		if (value != nil)
		{
			self.rawValue = value;
		}
		
		if (description != nil)
		{
			self.fullAttributedDescription = description;
		}
	}
	
	return self;
}

- (id)initWithValue:(void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)type qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize description:(NSAttributedString *)description enabled:(BOOL)enabled
{
	return [self initWithValue:value size:size address:address type:type qualifier:qualifier pointerSize:pointerSize description:description enabled:enabled byteOrder:CFByteOrderGetCurrent()];
}

- (id)initWithValue:(void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)type qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize description:(NSAttributedString *)description
{
	return [self initWithValue:value size:size address:address type:type qualifier:qualifier pointerSize:pointerSize description:description enabled:YES];
}

- (id)initWithValue:(void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)type qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize
{
	return [self initWithValue:value size:size address:address type:type qualifier:qualifier pointerSize:pointerSize description:[[NSAttributedString alloc] initWithString:@""]];
}

- (void)dealloc
{
	self.rawValue = NULL;
	self.freezeValue = NULL;
}

- (NSString *)addressStringValue
{
	if (!_addressStringValue)
	{
		[self setAddressStringValue:nil];
	}
	
	return _addressStringValue;
}

- (void)setAddressStringValue:(NSString *)newAddressString
{
	if (newAddressString)
	{
		if ([newAddressString zgIsHexRepresentation])
		{
			[[NSScanner scannerWithString:newAddressString] scanHexLongLong:&_address];
		}
		else
		{
			[[NSScanner scannerWithString:newAddressString] scanLongLong:(long long *)&_address];
		}
	}
	
	_addressStringValue = [[NSString stringWithFormat:@"0x%llX", self.address] copy];
}

- (NSString *)addressFormula
{
	if (!_addressFormula)
	{
		self.addressFormula = self.addressStringValue;
	}
	
	return _addressFormula;
}

- (NSString *)stringValue
{
	[self updateStringValue];
	
	return _stringValue;
}

+ (NSString *)byteArrayStringFromValue:(unsigned char *)value size:(ZGMemorySize)size
{
	NSMutableArray *byteStringComponents = [NSMutableArray array];
	
	for (ZGMemorySize byteIndex = 0; byteIndex < size; byteIndex++)
	{
		NSString *hexString = [NSString stringWithFormat:@"%02X", value[byteIndex]];
		[byteStringComponents addObject:hexString];
	}
	
	return [byteStringComponents componentsJoinedByString:@" "];
}

- (void)updateStringValue
{
	if (self.size > 0 && self.rawValue != nil)
	{
		NSString *newStringValue = nil;
		
		BOOL needsByteSwapping = CFByteOrderGetCurrent() != self.byteOrder;
		
		switch (self.type)
		{
			case ZGInt8:
				if (self.qualifier == ZGSigned)
				{
					self.stringValue = [NSString stringWithFormat:@"%d", *((int8_t *)self.rawValue)];
				}
				else
				{
					self.stringValue = [NSString stringWithFormat:@"%u", *((uint8_t *)self.rawValue)];
				}
				break;
			case ZGInt16:
			{
				uint16_t value = needsByteSwapping ? CFSwapInt16(*(uint16_t *)self.rawValue) : *(uint16_t *)self.rawValue;
				if (self.qualifier == ZGSigned)
				{
					self.stringValue = [NSString stringWithFormat:@"%d", value];
				}
				else
				{
					self.stringValue = [NSString stringWithFormat:@"%u", value];
				}
				break;
			}
			case ZGInt32:
			{
				uint32_t value = needsByteSwapping ? CFSwapInt32(*(uint32_t *)self.rawValue) : *(uint32_t *)self.rawValue;
				if (self.qualifier == ZGSigned)
				{
					self.stringValue = [NSString stringWithFormat:@"%d", value];
				}
				else
				{
					self.stringValue = [NSString stringWithFormat:@"%u", value];
				}
				break;
			}
			case ZGInt64:
			{
				uint64_t value = needsByteSwapping ? CFSwapInt64(*(uint64_t *)self.rawValue) : *(uint64_t *)self.rawValue;
				if (self.qualifier == ZGSigned)
				{
					self.stringValue = [NSString stringWithFormat:@"%lld", value];
				}
				else
				{
					self.stringValue = [NSString stringWithFormat:@"%llu", value];
				}
				break;
			}
			case ZGPointer:
				if (self.size == sizeof(int32_t))
				{
					uint32_t value = needsByteSwapping ? CFSwapInt32(*(uint32_t *)self.rawValue) : *(uint32_t *)self.rawValue;
					self.stringValue = [NSString stringWithFormat:@"0x%X", value];
				}
				else if (self.size == sizeof(int64_t))
				{
					uint64_t value = needsByteSwapping ? CFSwapInt64(*(uint64_t *)self.rawValue) : *(uint64_t *)self.rawValue;
					self.stringValue = [NSString stringWithFormat:@"0x%llX", value];
				}
				break;
			case ZGFloat:
			{
				float value = needsByteSwapping ? CFConvertFloat32SwappedToHost(*(CFSwappedFloat32 *)self.rawValue) : *(float *)self.rawValue;
				self.stringValue = [NSString stringWithFormat:@"%f", value];
				break;
			}
			case ZGDouble:
			{
				double value = needsByteSwapping ? CFConvertFloat64SwappedToHost(*(CFSwappedFloat64 *)self.rawValue) : *(double *)self.rawValue;
				self.stringValue = [NSString stringWithFormat:@"%lf", value];
				break;
			}
			case ZGString8:
				self.stringValue =
					[[NSString alloc]
					 initWithData:[NSData dataWithBytes:self.rawValue length:(NSUInteger)self.size]
					 encoding:NSUTF8StringEncoding];
				
				// UTF8 string encoding can fail sometimes on some invalid-ish strings
				if (!_stringValue)
				{
					newStringValue =
						[[NSString alloc]
						 initWithData:[NSData dataWithBytes:self.rawValue length:(NSUInteger)self.size]
						 encoding:NSASCIIStringEncoding];
					
					self.stringValue = newStringValue;
				}
				
				if (!_stringValue)
				{
					self.stringValue = @"";
				}
				
				break;
			case ZGString16:
				newStringValue =
					[[NSString alloc]
					 initWithData:[NSData dataWithBytes:self.rawValue length:(NSUInteger)self.size]
					 encoding:self.byteOrder == CFByteOrderLittleEndian ? NSUTF16LittleEndianStringEncoding : NSUTF16BigEndianStringEncoding];
				
				self.stringValue = newStringValue;
				
				if (!_stringValue)
				{
					self.stringValue = @"";
				}
				
				break;
			case ZGByteArray:
			{
				self.stringValue = [[self class] byteArrayStringFromValue:self.rawValue size:self.size];
				break;
			}
			case ZGScript:
				break;
		}
	}
	else
	{
		self.stringValue = @"";
	}
}

- (NSString *)sizeStringValue
{
	return [NSString stringWithFormat:@"%llu", self.size];
}

- (void)setRawValue:(void *)newValue
{
	free(_rawValue);
	_rawValue = NULL;

	if (newValue && self.size > 0)
	{
		_rawValue = malloc((size_t)self.size);
		if (_rawValue)
		{
			memcpy(_rawValue, newValue, (size_t)self.size);
		}
	}
}

- (void)setFreezeValue:(void *)newFreezeValue
{
	free(_freezeValue);
	_freezeValue = NULL;
	
	if (newFreezeValue)
	{
		_freezeValue = malloc((size_t)self.size);
		if (_freezeValue)
		{
			memcpy(_freezeValue, newFreezeValue, (size_t)self.size);
		}
	}
}

- (NSString *)name
{
	NSArray *lines = [self.fullAttributedDescription.string componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
	if (lines.count <= 1) return self.fullAttributedDescription.string;
	
	return [lines objectAtIndex:0];
}

- (NSString *)shortDescription
{
	NSArray *lines = [self.fullAttributedDescription.string componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
	if (lines.count <= 1) return self.fullAttributedDescription.string;
	
	return [[lines objectAtIndex:0] stringByAppendingString:@"…"];
}

// frees value, freezeValue, makes unfrozen
- (void)cleanState
{
	self.rawValue = NULL;
	
	// Only safe way to go about the freeze value is to remove it..
	self.freezeValue = NULL;
	
	self.isFrozen = NO;
}

- (void)setType:(ZGVariableType)newType requestedSize:(ZGMemorySize)requestedSize pointerSize:(ZGMemorySize)pointerSize
{
	self.type = newType;
	
	if (self.type == ZGScript)
	{
		self.enabled = NO;
	}
	
	[self cleanState];
	
	self.size = (newType == ZGByteArray) ? requestedSize : [ZGVariable sizeFromType:newType pointerSize:pointerSize];
}

// Precondition: size != pointerSize, otherwise this is a wasted effort
//               also, this must be a pointer type variable
- (void)setPointerSize:(ZGMemorySize)pointerSize
{
	[self cleanState];
	self.size = [ZGVariable sizeFromType:self.type pointerSize:pointerSize];
}

@end
