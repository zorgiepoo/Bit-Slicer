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

#import "ZGVariable.h"
#import "NSStringAdditions.h"
#import "ZGNullability.h"

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
#define ZGUserAnnotatedKey @"ZGUserAnnotatedKey"
#define ZGNameKey @"ZGNameKey" // legacy
#define ZGDynamicAddressKey @"ZGIsPointerKey" // value is for backwards compatibility
#define ZGAddressFormulaKey @"ZGAddressFormulaKey"
#define ZGScriptKey @"ZGScriptKey"
#define ZGScriptCachePathKey @"ZGScriptCachePathKey"
#define ZGScriptCacheUUIDKey @"ZGScriptCacheUUIDKey"

@implementation ZGVariable
{
	void * _Nullable _rawValue;
	void * _Nullable _freezeValue;
	
	NSString * _Nullable _stringValue;
	NSString * _Nullable _addressStringValue;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder
	 encodeInt64:(int64_t)_address
	 forKey:ZGAddressKey];
	
	[coder
	 encodeInt64:(int64_t)_size
	 forKey:ZGSizeKey];
	
	[coder
	 encodeBool:_enabled
	 forKey:ZGEnabledKey];
	
	[coder
	 encodeBool:_isFrozen
	 forKey:ZGIsFrozenKey];
	
	[coder
	 encodeInt32:_type
	 forKey:ZGTypeKey];
	
	[coder
	 encodeInt32:_qualifier
	 forKey:ZGQualifierKey];
	
	[coder
	 encodeInt32:(int32_t)_byteOrder
	 forKey:ZGByteOrderKey];
	
	[coder
	 encodeObject:_fullAttributedDescription
	 forKey:ZGDescriptionKey];
	
	[coder
	 encodeBool:_userAnnotated
	 forKey:ZGUserAnnotatedKey];
	
	// For backwards compatiblity with older versions
	[coder
	 encodeObject:[self name]
	 forKey:ZGNameKey];
	
	[coder
	 encodeBool:_usesDynamicAddress
	 forKey:ZGDynamicAddressKey];
	
	[coder
	 encodeObject:[self addressFormula]
	 forKey:ZGAddressFormulaKey];
	
	if (_rawValue != nil)
	{
		[coder
		 encodeBytes:_rawValue
		 length:_size
		 forKey:ZGValueKey];
	}
	
	if (_freezeValue != nil)
	{
		[coder
		 encodeBytes:_freezeValue
		 length:_size
		 forKey:ZGFreezeValueKey];
	}
	
	if (_scriptValue != nil)
	{
		[coder encodeObject:_scriptValue forKey:ZGScriptKey];
	}
	
	if (_cachedScriptPath != nil)
	{
		[coder encodeObject:_cachedScriptPath forKey:ZGScriptCachePathKey];
	}
	
	if (_cachedScriptUUID != nil)
	{
		[coder encodeObject:_cachedScriptUUID forKey:ZGScriptCacheUUIDKey];
	}
}

- (id)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	if (self != nil)
	{
		_address = (uint64_t)[coder decodeInt64ForKey:ZGAddressKey];
		
		[self setAddressStringValue:nil];
		
		_size = (uint64_t)[coder decodeInt64ForKey:ZGSizeKey];
		_enabled = [coder decodeBoolForKey:ZGEnabledKey];
		_isFrozen = [coder decodeBoolForKey:ZGIsFrozenKey];
		_type = [coder decodeInt32ForKey:ZGTypeKey];
		_qualifier = [coder decodeInt32ForKey:ZGQualifierKey];
		_byteOrder = [coder decodeInt32ForKey:ZGByteOrderKey];
		if (_byteOrder == CFByteOrderUnknown)
		{
			_byteOrder = CFByteOrderGetCurrent();
		}
		
		_usesDynamicAddress = [coder decodeBoolForKey:ZGDynamicAddressKey];
		_addressFormula = [coder decodeObjectOfClass:[NSString class] forKey:ZGAddressFormulaKey];
		
		NSAttributedString *variableDescription = [coder decodeObjectOfClass:[NSAttributedString class] forKey:ZGDescriptionKey];
		if (variableDescription == nil)
		{
			NSString *name = [coder decodeObjectOfClass:[NSString class] forKey:ZGNameKey];
			if (name != nil)
			{
				variableDescription = [[NSAttributedString alloc] initWithString:name];
			}
		}
		_fullAttributedDescription = variableDescription != nil ? variableDescription : [[NSAttributedString alloc] initWithString:@""];
		
		NSNumber *userAnnotatedValue = [coder decodeObjectOfClass:[NSNumber class] forKey:ZGUserAnnotatedKey];
		// In order to not annoy the user, if the user annotated key does not exist, assume the description could have been modified by the user before
		_userAnnotated = (userAnnotatedValue == nil) ? (_fullAttributedDescription.length != 0) : userAnnotatedValue.boolValue;
		
		NSUInteger returnedLength = 0;
		const uint8_t *buffer = [coder decodeBytesForKey:ZGValueKey returnedLength:&returnedLength];
		
		if (returnedLength == _size)
		{
			[self setRawValue:buffer];
		}
		
		returnedLength = 0;
		buffer = [coder decodeBytesForKey:ZGFreezeValueKey returnedLength:&returnedLength];
		
		if (returnedLength == _size)
		{
			[self setFreezeValue:buffer];
		}
		
		NSString *scriptValue = [coder decodeObjectOfClass:[NSString class] forKey:ZGScriptKey];
		_scriptValue = scriptValue != nil ? [scriptValue copy] : @"";
		
		_cachedScriptPath = [(NSString *)[coder decodeObjectOfClass:[NSString class] forKey:ZGScriptCachePathKey] copy];
		
		_cachedScriptUUID = [(NSString *)[coder decodeObjectOfClass:[NSString class] forKey:ZGScriptCacheUUIDKey] copy];
		
		return self;
	}
	
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}

- (id)copyWithZone:(NSZone *)__unused zone
{
	NSData *archivedData = [NSKeyedArchiver archivedDataWithRootObject:self];
	return ZGUnwrapNullableObject([NSKeyedUnarchiver unarchiveObjectWithData:archivedData]);
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

- (id)initWithValue:(const void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)type qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize description:(NSAttributedString *)description enabled:(BOOL)enabled byteOrder:(CFByteOrder)byteOrder
{
	if ((self = [super init]))
	{
		_size = size;
		_type = type;
		
		if (_size == 0)
		{
			_size =
			[ZGVariable
			 sizeFromType:_type
			 pointerSize:pointerSize];
		}
		
		_address = address;
		_qualifier = qualifier;
		_enabled = enabled;
		
		_byteOrder = byteOrder;
		
		if (value != NULL)
		{
			[self setRawValue:value];
		}
		
		if (description != nil)
		{
			_fullAttributedDescription = [description copy];
		}
	}
	
	return self;
}

- (id)initWithValue:(const void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)type qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize description:(NSAttributedString *)description enabled:(BOOL)enabled
{
	return [self initWithValue:value size:size address:address type:type qualifier:qualifier pointerSize:pointerSize description:description enabled:enabled byteOrder:CFByteOrderGetCurrent()];
}

- (id)initWithValue:(const void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)type qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize description:(NSAttributedString *)description
{
	return [self initWithValue:value size:size address:address type:type qualifier:qualifier pointerSize:pointerSize description:description enabled:YES];
}

- (id)initWithValue:(const void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)type qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize
{
	return [self initWithValue:value size:size address:address type:type qualifier:qualifier pointerSize:pointerSize description:[[NSAttributedString alloc] initWithString:@""]];
}

- (id)initWithValue:(const void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)type qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize byteOrder:(CFByteOrder)byteOrder
{
	return [self initWithValue:value size:size address:address type:type qualifier:qualifier pointerSize:pointerSize description:[[NSAttributedString alloc] initWithString:@""] enabled:YES byteOrder:byteOrder];
}

- (void)dealloc
{
	[self setRawValue:NULL];
	[self setFreezeValue:NULL];
}

- (NSString *)addressStringValue
{
	if (_addressStringValue == nil)
	{
		[self setAddressStringValue:nil];
	}
	
	return (NSString * _Nonnull)_addressStringValue;
}

- (void)setAddressStringValue:(NSString *)newAddressString
{
	if (newAddressString != nil)
	{
		if ([newAddressString zgIsHexRepresentation])
		{
			if (![[NSScanner scannerWithString:newAddressString] scanHexLongLong:&_address])
			{
				_address = 0x0;
			}
		}
		else
		{
			_address = [newAddressString zgUnsignedLongLongValue];
		}
	}
	
	_addressStringValue = [NSString stringWithFormat:@"0x%llX", _address];
}

- (NSString *)addressFormula
{
	if (_addressFormula == nil)
	{
		_addressFormula = [self addressStringValue];
	}
	
	return _addressFormula;
}

- (NSString *)stringValue
{
	[self updateStringValue];
	
	return (NSString * _Nonnull)_stringValue;
}

+ (NSString *)byteArrayStringFromValue:(unsigned char *)value size:(ZGMemorySize)size
{
	NSMutableArray<NSString *> *byteStringComponents = [NSMutableArray array];
	
	for (ZGMemorySize byteIndex = 0; byteIndex < size; byteIndex++)
	{
		NSString *hexString = [NSString stringWithFormat:@"%02X", value[byteIndex]];
		[byteStringComponents addObject:hexString];
	}
	
	return [byteStringComponents componentsJoinedByString:@" "];
}

- (void)updateStringValue
{
	void *rawValue = _rawValue;
	if (_size > 0 && rawValue != NULL)
	{
		NSString *newStringValue = nil;
		
		BOOL needsByteSwapping = _byteOrder != CFByteOrderGetCurrent();
		
		switch (_type)
		{
			case ZGInt8:
				if (_qualifier == ZGSigned)
				{
					_stringValue = [NSString stringWithFormat:@"%d", *((int8_t *)rawValue)];
				}
				else
				{
					_stringValue = [NSString stringWithFormat:@"%u", *((uint8_t *)rawValue)];
				}
				break;
			case ZGInt16:
			{
				uint16_t value = needsByteSwapping ? CFSwapInt16(*(uint16_t *)rawValue) : *(uint16_t *)rawValue;
				if (_qualifier == ZGSigned)
				{
					_stringValue = [NSString stringWithFormat:@"%d", (int16_t)value];
				}
				else
				{
					_stringValue = [NSString stringWithFormat:@"%u", value];
				}
				break;
			}
			case ZGInt32:
			{
				uint32_t value = needsByteSwapping ? CFSwapInt32(*(uint32_t *)rawValue) : *(uint32_t *)rawValue;
				if (_qualifier == ZGSigned)
				{
					_stringValue = [NSString stringWithFormat:@"%d", (int32_t)value];
				}
				else
				{
					_stringValue = [NSString stringWithFormat:@"%u", value];
				}
				break;
			}
			case ZGInt64:
			{
				uint64_t value = needsByteSwapping ? CFSwapInt64(*(uint64_t *)rawValue) : *(uint64_t *)rawValue;
				if (_qualifier == ZGSigned)
				{
					_stringValue = [NSString stringWithFormat:@"%lld", (int64_t)value];
				}
				else
				{
					_stringValue = [NSString stringWithFormat:@"%llu", value];
				}
				break;
			}
			case ZGPointer:
				if (_size == sizeof(int32_t))
				{
					uint32_t value = needsByteSwapping ? CFSwapInt32(*(uint32_t *)_rawValue) : *(uint32_t *)rawValue;
					_stringValue = [NSString stringWithFormat:@"0x%X", value];
				}
				else if (_size == sizeof(int64_t))
				{
					uint64_t value = needsByteSwapping ? CFSwapInt64(*(uint64_t *)_rawValue) : *(uint64_t *)rawValue;
					_stringValue = [NSString stringWithFormat:@"0x%llX", value];
				}
				break;
			case ZGFloat:
			{
				float value = needsByteSwapping ? CFConvertFloat32SwappedToHost(*(CFSwappedFloat32 *)rawValue) : *(float *)rawValue;
				_stringValue = [NSString stringWithFormat:@"%f", (double)value];
				break;
			}
			case ZGDouble:
			{
				double value = needsByteSwapping ? CFConvertFloat64SwappedToHost(*(CFSwappedFloat64 *)rawValue) : *(double *)rawValue;
				_stringValue = [NSString stringWithFormat:@"%lf", value];
				break;
			}
			case ZGString8:
				_stringValue =
					[[NSString alloc]
					 initWithData:[NSData dataWithBytes:rawValue length:_size]
					 encoding:NSUTF8StringEncoding];
				
				// UTF8 string encoding can fail sometimes on some invalid-ish strings
				if (_stringValue == nil)
				{
					newStringValue =
						[[NSString alloc]
						 initWithData:[NSData dataWithBytes:rawValue length:_size]
						 encoding:NSASCIIStringEncoding];
					
					_stringValue = newStringValue;
				}
				
				if (_stringValue == nil)
				{
					_stringValue = @"";
				}
				
				break;
			case ZGString16:
				newStringValue =
					[[NSString alloc]
					 initWithData:[NSData dataWithBytes:rawValue length:_size]
					 encoding:_byteOrder == CFByteOrderLittleEndian ? NSUTF16LittleEndianStringEncoding : NSUTF16BigEndianStringEncoding];
				
				_stringValue = newStringValue;
				
				if (_stringValue == nil)
				{
					_stringValue = @"";
				}
				
				break;
			case ZGByteArray:
			{
				_stringValue = [[self class] byteArrayStringFromValue:rawValue size:_size];
				break;
			}
			case ZGScript:
				_stringValue = @"";
				break;
		}
	}
	else
	{
		_stringValue = @"";
	}
}

- (NSString *)sizeStringValue
{
	return [NSString stringWithFormat:@"%llu", _size];
}

- (void)setSize:(ZGMemorySize)size
{
	if (size > _size)
	{
		[self setRawValue:NULL];
	}
	_size = size;
}

- (void *)rawValue
{
	return _rawValue;
}

- (void)setRawValue:(const void *)newValue
{
	free(_rawValue);
	_rawValue = NULL;

	if (newValue != NULL && _size > 0)
	{
		_rawValue = malloc(_size);
		if (_rawValue)
		{
			memcpy(_rawValue, newValue, _size);
		}
	}
}

- (void *)freezeValue
{
	return _freezeValue;
}

- (void)setFreezeValue:(const void *)newFreezeValue
{
	free(_freezeValue);
	_freezeValue = NULL;
	
	if (newFreezeValue != NULL)
	{
		_freezeValue = malloc(_size);
		if (_freezeValue != NULL)
		{
			memcpy(_freezeValue, newFreezeValue, _size);
		}
	}
}

- (NSString *)name
{
	NSArray<NSString *> *lines = [_fullAttributedDescription.string componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
	if (lines.count <= 1)
	{
		return _fullAttributedDescription.string;
	}
	
	return [lines objectAtIndex:0];
}

- (NSString *)shortDescription
{
	NSArray<NSString *> *lines = [_fullAttributedDescription.string componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
	if (lines.count <= 1)
	{
		return _fullAttributedDescription.string;
	}
	
	return [[lines objectAtIndex:0] stringByAppendingString:@"…"];
}

// frees value, freezeValue, makes unfrozen
- (void)cleanState
{
	[self setRawValue:NULL];
	
	// Only safe way to go about the freeze value is to remove it..
	[self setFreezeValue:NULL];
	
	_isFrozen = NO;
}

- (void)setType:(ZGVariableType)newType requestedSize:(ZGMemorySize)requestedSize pointerSize:(ZGMemorySize)pointerSize
{
	_type = newType;
	
	if (_type == ZGScript)
	{
		_enabled = NO;
	}
	
	[self cleanState];
	
	_size = (newType == ZGByteArray) ? requestedSize : [ZGVariable sizeFromType:newType pointerSize:pointerSize];
}

// Precondition: size != pointerSize, otherwise this is a wasted. Also, this must be a pointer type variable
- (void)changePointerSize:(ZGMemorySize)pointerSize
{
	[self cleanState];
	_size = [ZGVariable sizeFromType:_type pointerSize:pointerSize];
}

@end
