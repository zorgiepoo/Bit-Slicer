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

@property (readwrite, nonatomic) ZGMemoryAddress address;

@end

@implementation ZGVariable

NSString *ZGVariablePboardType = @"ZGVariablePboardType";

#define ZGAddressKey @"ZGAddressKey"
#define ZGSizeKey	 @"ZGSizeKey"
#define ZGEnabledKey @"ZGShouldBeSearchedKey" // for backwards compatibility
#define ZGIsFrozenKey @"ZGIsFrozenKey"
#define ZGTypeKey @"ZGTypeKey"
#define ZGQualifierKey @"ZGQualifierKey"
#define ZGValueKey @"ZGValueKey"
#define ZGFreezeValueKey @"ZGFreezeValueKey"
#define ZGNameKey @"ZGNameKey"
#define ZGIsPointerKey @"ZGIsPointerKey"
#define ZGAddressFormulaKey @"ZGAddressFormulaKey"
#define ZGScriptKey @"ZGScriptKey"

- (void)encodeWithCoder:(NSCoder *)coder
{	
	[coder
	 encodeInt64:self.address
	 forKey:ZGAddressKey];
	
	[coder
	 encodeInt64:self.size
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
	 encodeObject:self.name
	 forKey:ZGNameKey];
	
	[coder
	 encodeBool:self.isPointer
	 forKey:ZGIsPointerKey];
	
	[coder
	 encodeObject:self.addressFormula
	 forKey:ZGAddressFormulaKey];
	
	if (self.value != nil)
	{
		[coder
		 encodeBytes:self.value
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
}

- (id)initWithCoder:(NSCoder *)coder
{
	self.address = [coder decodeInt64ForKey:ZGAddressKey];
	[self setAddressStringValue:nil];
	
	self.size = [coder decodeInt64ForKey:ZGSizeKey];
	self.enabled = [coder decodeBoolForKey:ZGEnabledKey];
	self.isFrozen = [coder decodeBoolForKey:ZGIsFrozenKey];
	self.type = [coder decodeInt32ForKey:ZGTypeKey];
	self.qualifier = [coder decodeInt32ForKey:ZGQualifierKey];
	
	self.isPointer = [coder decodeBoolForKey:ZGIsPointerKey];
	[self setAddressFormula:[coder decodeObjectForKey:ZGAddressFormulaKey]];
	
	NSString *variableName = [coder decodeObjectForKey:ZGNameKey];
	[self setName:variableName != nil ? variableName : @""];
	
	NSUInteger returnedLength = 0;
	const uint8_t *buffer =
		[coder
		 decodeBytesForKey:ZGValueKey
		 returnedLength:&returnedLength];
	
	if (returnedLength == self.size)
	{
		self.value = (void *)buffer;
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
	
	return self;
}

- (id)copyWithZone:(NSZone *)zone
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
		default:
			break;
	}
	
	return size;
}

- (id)initWithValue:(void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)aType qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize name:(NSString *)name enabled:(BOOL)enabled
{
	if ((self = [super init]))
	{
		self.size = size;
		self.type = aType;
		
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
		
		if (value != nil)
		{
			self.value = value;
		}
		
		if (name != nil)
		{
			self.name = name;
		}
	}
	
	return self;
}

- (id)initWithValue:(void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)aType qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize name:(NSString *)name
{
	return [self initWithValue:value size:size address:address type:aType qualifier:qualifier pointerSize:pointerSize name:name enabled:YES];
}

- (id)initWithValue:(void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)aType qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize
{
	return [self initWithValue:value size:size address:address type:aType qualifier:qualifier pointerSize:pointerSize name:@""];
}

- (void)dealloc
{
	self.value = NULL;
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

- (void)updateStringValue
{
	if (self.size > 0 && self.value)
	{
		NSString *newStringValue = nil;
		
		switch (self.type)
		{
			case ZGInt8:
				if (self.qualifier == ZGSigned)
				{
					self.stringValue = [NSString stringWithFormat:@"%d", *((int8_t *)self.value)];
				}
				else
				{
					self.stringValue = [NSString stringWithFormat:@"%u", *((uint8_t *)self.value)];
				}
				break;
			case ZGInt16:
				if (self.qualifier == ZGSigned)
				{
					self.stringValue = [NSString stringWithFormat:@"%d", *((int16_t *)self.value)];
				}
				else
				{
					self.stringValue = [NSString stringWithFormat:@"%u", *((uint16_t *)self.value)];
				}
				break;
			case ZGInt32:
				if (self.qualifier == ZGSigned)
				{
					self.stringValue = [NSString stringWithFormat:@"%d", *((int32_t *)self.value)];
				}
				else
				{
					self.stringValue = [NSString stringWithFormat:@"%u", *((uint32_t *)self.value)];
				}
				break;
			case ZGInt64:
				if (self.qualifier == ZGSigned)
				{
					self.stringValue = [NSString stringWithFormat:@"%lld", *((int64_t *)self.value)];
				}
				else
				{
					self.stringValue = [NSString stringWithFormat:@"%llu", *((uint64_t *)self.value)];
				}
				break;
			case ZGPointer:
				if (self.size == sizeof(int32_t))
				{
					self.stringValue = [NSString stringWithFormat:@"0x%X", *((uint32_t *)self.value)];
				}
				else if (self.size == sizeof(int64_t))
				{
					self.stringValue = [NSString stringWithFormat:@"0x%llX", *((uint64_t *)self.value)];
				}
				break;
			case ZGFloat:
				self.stringValue = [NSString stringWithFormat:@"%f", *((float *)self.value)];
				break;
			case ZGDouble:
				self.stringValue = [NSString stringWithFormat:@"%lf", *((double *)self.value)];
				break;
			case ZGUTF8String:
				self.stringValue =
					[[NSString alloc]
					 initWithData:[NSData dataWithBytes:self.value length:(NSUInteger)self.size]
					 encoding:NSUTF8StringEncoding];
				
				// UTF8 string encoding can fail sometimes on some invalid-ish strings
				if (!_stringValue)
				{
					newStringValue =
						[[NSString alloc]
						 initWithData:[NSData dataWithBytes:self.value length:(NSUInteger)self.size]
						 encoding:NSASCIIStringEncoding];
					
					self.stringValue = newStringValue;
				}
				
				if (!_stringValue)
				{
					self.stringValue = @"";
				}
				
				break;
			case ZGUTF16String:
				newStringValue =
					[[NSString alloc]
					 initWithData:[NSData dataWithBytes:self.value length:(NSUInteger)self.size]
					 encoding:NSUTF16LittleEndianStringEncoding];
				
				self.stringValue = newStringValue;
				
				if (!_stringValue)
				{
					self.stringValue = @"";
				}
				
				break;
			case ZGByteArray:
			{
				ZGMemorySize byteIndex;
				unsigned char *valuePtr = self.value;
				NSMutableString *byteString = [NSMutableString stringWithString:@""];
				for (byteIndex = 0; byteIndex < self.size; byteIndex++)
				{
					NSString *hexString = [NSString stringWithFormat:@"%X", valuePtr[byteIndex]];
					// Make each byte two digits so it looks nice
					if (hexString.length == 1)
					{
						hexString = [@"0" stringByAppendingString:hexString];
					}
					
					[byteString appendFormat:@"%@", hexString];
					if (byteIndex < self.size - 1)
					{
						[byteString appendString:@" "];
					}
				}
				
				self.stringValue = byteString;
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

- (void)setValue:(void *)newValue
{
	free(_value);
	_value = NULL;

	if (newValue && self.size > 0)
	{
		_value = malloc((size_t)self.size);
		if (_value)
		{
			memcpy(_value, newValue, (size_t)self.size);
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

// frees value, freezeValue, makes unfrozen
- (void)cleanState
{
	self.value = NULL;
	
	// Only safe way to go about the freeze value is to remove it..
	self.freezeValue = NULL;
	
	self.isFrozen = NO;
}

- (void)setType:(ZGVariableType)newType requestedSize:(ZGMemorySize)requestedSize pointerSize:(ZGMemorySize)pointerSize
{
	self.type = newType;
	
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
