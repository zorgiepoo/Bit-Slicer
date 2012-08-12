/*
 * This file is part of Bit Slicer.
 *
 * Bit Slicer is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 
 * Bit Slicer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 
 * You should have received a copy of the GNU General Public License
 * along with Bit Slicer.  If not, see <http://www.gnu.org/licenses/>.
 * 
 * Created by Mayur Pawashe on 10/29/09.
 * Copyright 2010 zgcoder. All rights reserved.
 */

#import "ZGVariable.h"
#import "NSStringAdditions.h"

@interface ZGVariable ()

@property (readwrite, assign, nonatomic) ZGMemoryAddress address;

@end

@implementation ZGVariable

NSString *ZGVariablePboardType = @"ZGVariablePboardType";

#define ZGAddressKey @"ZGAddressKey"
#define ZGSizeKey	 @"ZGSizeKey"
#define ZGShouldBeSearchedKey @"ZGShouldBeSearchedKey"
#define ZGIsFrozenKey @"ZGIsFrozenKey"
#define ZGTypeKey @"ZGTypeKey"
#define ZGQualifierKey @"ZGQualifierKey"
#define ZGValueKey @"ZGValueKey"
#define ZGFreezeValueKey @"ZGFreezeValueKey"
#define ZGNameKey @"ZGNameKey"
#define ZGIsPointerKey @"ZGIsPointerKey"
#define ZGAddressFormulaKey @"ZGAddressFormulaKey"

- (void)encodeWithCoder:(NSCoder *)coder
{	
	[coder
	 encodeInt64:self.address
	 forKey:ZGAddressKey];
	
	[coder
	 encodeInt64:self.size
	 forKey:ZGSizeKey];
	
	[coder
	 encodeBool:self.shouldBeSearched
	 forKey:ZGShouldBeSearchedKey];
	
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
	
	if (self.value)
	{
		[coder
		 encodeBytes:self.value
		 length:(NSUInteger)self.size
		 forKey:ZGValueKey];
	}
	
	if (self.freezeValue)
	{
		[coder
		 encodeBytes:self.freezeValue
		 length:(NSUInteger)self.size
		 forKey:ZGFreezeValueKey];
	}
}

- (id)initWithCoder:(NSCoder *)coder
{
	self.address = [coder decodeInt64ForKey:ZGAddressKey];
	[self setAddressStringValue:nil];
	
	self.size = [coder decodeInt64ForKey:ZGSizeKey];
	self.shouldBeSearched = [coder decodeBoolForKey:ZGShouldBeSearchedKey];
	self.isFrozen = [coder decodeBoolForKey:ZGIsFrozenKey];
	self.type = [coder decodeInt32ForKey:ZGTypeKey];
	self.qualifier = [coder decodeInt32ForKey:ZGQualifierKey];
	
	self.isPointer = [coder decodeBoolForKey:ZGIsPointerKey];
	[self setAddressFormula:[coder decodeObjectForKey:ZGAddressFormulaKey]];
	
	NSString *variableName = [coder decodeObjectForKey:ZGNameKey];
	[self setName:variableName ? variableName : @""];
	
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
	
	return self;
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

- (id)initWithValue:(void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)aType qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize
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
		self.shouldBeSearched = YES;
		
		if (value)
		{
			self.value = value;
		}
		
		self.name = @"";
	}
	
	return self;
}

- (void)dealloc
{
	self.value = NULL;
	self.freezeValue = NULL;
	
	[_addressStringValue release];
	self.addressFormula = nil;
	self.stringValue = nil;
	self.name = nil;
	
	[super dealloc];
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
		if ([newAddressString isHexRepresentation])
		{
			[[NSScanner scannerWithString:newAddressString] scanHexLongLong:&_address];
		}
		else
		{
			[[NSScanner scannerWithString:newAddressString] scanLongLong:(long long *)&_address];
		}
	}
	
	[_addressStringValue release];
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
					[[[NSString alloc]
					 initWithData:[NSData dataWithBytes:self.value length:(NSUInteger)(self.size - 1)]
					 encoding:NSUTF8StringEncoding] autorelease];
				
				// UTF8 string encoding can fail sometimes on some invalid-ish strings
				if (!_stringValue)
				{
					newStringValue =
						[[NSString alloc]
						 initWithData:[NSData dataWithBytes:self.value length:(NSUInteger)(self.size - 1)]
						 encoding:NSASCIIStringEncoding];
					self.stringValue = newStringValue;
					[newStringValue release];
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
				[newStringValue release];
				
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
	if (_value)
	{
		free(_value);
		_value = NULL;
	}

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
	if (_freezeValue)
	{
		free(_freezeValue);
		_freezeValue = NULL;
	}
	
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
