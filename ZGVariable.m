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

@implementation ZGVariable

@synthesize shouldBeSearched;
@synthesize addressFormula;

NSString *ZGVariablePboardType = @"ZGVariablePboardType";

#define ZGAddressKey			@"ZGAddressKey"
#define ZGSizeKey				@"ZGSizeKey"
#define ZGShouldBeSearchedKey	@"ZGShouldBeSearchedKey"
#define ZGIsFrozenKey			@"ZGIsFrozenKey"
#define ZGTypeKey				@"ZGTypeKey"
#define ZGQualifierKey			@"ZGQualifierKey"
#define ZGValueKey				@"ZGValueKey"
#define ZGFreezeValueKey		@"ZGFreezeValueKey"
#define ZGNameKey				@"ZGNameKey"
#define ZGIsPointerKey			@"ZGIsPointerKey"
#define ZGAddressFormulaKey		@"ZGAddressFormulaKey"

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeInt64:address
				forKey:ZGAddressKey];
	
	[coder encodeInt64:size
				forKey:ZGSizeKey];
	
	[coder encodeBool:shouldBeSearched
			   forKey:ZGShouldBeSearchedKey];
	
	[coder encodeBool:isFrozen
			   forKey:ZGIsFrozenKey];
	
	[coder encodeInt32:type
				forKey:ZGTypeKey];
	
	[coder encodeInt32:qualifier
				forKey:ZGQualifierKey];
	
	[coder encodeObject:name
				 forKey:ZGNameKey];
	
	[coder encodeBool:isPointer
			   forKey:ZGIsPointerKey];
	
	[coder encodeObject:addressFormula
				 forKey:ZGAddressFormulaKey];
	
	if (value)
	{
		[coder encodeBytes:value
					length:(NSUInteger)size
					forKey:ZGValueKey];
	}
	
	if (freezeValue)
	{
		[coder encodeBytes:freezeValue
					length:(NSUInteger)size
					forKey:ZGFreezeValueKey];
	}
}

- (id)initWithCoder:(NSCoder *)coder
{
	address = [coder decodeInt64ForKey:ZGAddressKey];
	[self setAddressStringValue:[NSString stringWithFormat:@"0x%llX", address]];
	
	size = [coder decodeInt64ForKey:ZGSizeKey];
	shouldBeSearched = [coder decodeBoolForKey:ZGShouldBeSearchedKey];
	isFrozen = [coder decodeBoolForKey:ZGIsFrozenKey];
	type = [coder decodeInt32ForKey:ZGTypeKey];
	qualifier = [coder decodeInt32ForKey:ZGQualifierKey];
	
	isPointer = [coder decodeBoolForKey:ZGIsPointerKey];
	[self setAddressFormula:[coder decodeObjectForKey:ZGAddressFormulaKey]];
	
	NSString *variableName = [coder decodeObjectForKey:ZGNameKey];
	[self setName:variableName ? variableName : @""];
	
	NSUInteger returnedLength = 0;
	const uint8_t *buffer = [coder decodeBytesForKey:ZGValueKey
									  returnedLength:&returnedLength];
	
	if (returnedLength == size)
	{
		[self setVariableValue:(void *)buffer];
	}
	else
	{
		value = NULL;
	}
	
	returnedLength = 0;
	buffer = [coder decodeBytesForKey:ZGFreezeValueKey
					   returnedLength:&returnedLength];
	
	if (returnedLength == size)
	{
		[self setFreezeValue:(void *)buffer];
	}
	else
	{
		freezeValue = NULL;
	}
	
	return self;
}

+ (unsigned long long)sizeFromType:(ZGVariableType)type
					   pointerSize:(unsigned long long)pointerSize
{
	unsigned long long size = 0;
	
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
		case ZGPointer:
			size = pointerSize;
			break;
		default:
			break;
	}
	
	return size;
}

- (id)initWithValue:(void *)aValue
			   size:(unsigned long long)aSize
			address:(unsigned long long)anAddress
			   type:(ZGVariableType)aType
		  qualifier:(ZGVariableQualifier)aQualifier
		pointerSize:(unsigned long long)pointerSize
{
	if ((self = [super init]))
	{
		size = aSize;
		type = aType;
		
		if (!size)
		{
			size = [ZGVariable sizeFromType:type
								pointerSize:pointerSize];
		}
		 
		address = anAddress;
		qualifier = aQualifier;
		shouldBeSearched = YES;
		
		if (aValue)
		{
			[self setVariableValue:aValue];
		}
		
		freezeValue = NULL;
		
		[self setName:@""];
	}
	
	return self;
}

- (void)dealloc
{
	if (value)
	{
		free(value);
	}
	
	if (freezeValue)
	{
		free(freezeValue);
	}
	
	[addressStringValue release];
	[addressFormula release];
	[stringValue release];
	[name release];
	
	[super dealloc];
}

- (NSString *)name
{
	return name;
}

- (NSString *)addressStringValue
{
	if (!addressStringValue)
	{
		[self setAddressStringValue:nil];
	}
	
	return addressStringValue;
}

- (void)setAddressStringValue:(NSString *)newAddressString
{
	if (newAddressString)
	{
		if ([newAddressString isHexRepresentation])
		{
			[[NSScanner scannerWithString:newAddressString] scanHexLongLong:&address];
		}
		else
		{
			[[NSScanner scannerWithString:newAddressString] scanLongLong:(long long *)&address];
		}
	}
	
	[addressStringValue release];
	addressStringValue = [[NSString stringWithFormat:@"0x%llX", address] retain];
}

- (NSString *)addressFormula
{
	if (!addressFormula)
	{
		[self setAddressFormula:[self addressStringValue]];
	}
	
	return addressFormula;
}

- (NSString *)stringValue
{
	[self updateStringValue];
	
	return stringValue;
}

- (void)setStringValue:(NSString *)newStringValue
{
	[stringValue release];
	stringValue = [newStringValue copy];
}

- (void)updateStringValue
{
	if (size > 0 && value)
	{
		NSString *newStringValue = nil;
		
		switch (type)
		{
			case ZGInt8:
				if (qualifier == ZGSigned)
				{
					[self setStringValue:[NSString stringWithFormat:@"%i", *((int8_t *)value)]];
				}
				else
				{
					[self setStringValue:[NSString stringWithFormat:@"%u", *((uint8_t *)value)]];
				}
				break;
			case ZGInt16:
				if (qualifier == ZGSigned)
				{
					[self setStringValue:[NSString stringWithFormat:@"%i", *((int16_t *)value)]];
				}
				else
				{
					[self setStringValue:[NSString stringWithFormat:@"%u", *((uint16_t *)value)]];
				}
				break;
			case ZGInt32:
				if (qualifier == ZGSigned)
				{
					[self setStringValue:[NSString stringWithFormat:@"%i", *((int32_t *)value)]];
				}
				else
				{
					[self setStringValue:[NSString stringWithFormat:@"%u", *((uint32_t *)value)]];
				}
				break;
			case ZGInt64:
				if (qualifier == ZGSigned)
				{
					[self setStringValue:[NSString stringWithFormat:@"%lld", *((int64_t *)value)]];
				}
				else
				{
					[self setStringValue:[NSString stringWithFormat:@"%llu", *((uint64_t *)value)]];
				}
				break;
			case ZGPointer:
				if (size == sizeof(int32_t))
				{
					[self setStringValue:[NSString stringWithFormat:@"0x%X", *((uint32_t *)value)]];
				}
				else if (size == sizeof(int64_t))
				{
					[self setStringValue:[NSString stringWithFormat:@"0x%llX", *((uint64_t *)value)]];
				}
				break;
			case ZGFloat:
				[self setStringValue:[NSString stringWithFormat:@"%f", *((float *)value)]];
				break;
			case ZGDouble:
				[self setStringValue:[NSString stringWithFormat:@"%lf", *((double *)value)]];
				break;
			case ZGUTF8String:
				stringValue = [[NSString alloc] initWithData:[NSData dataWithBytes:value length:(NSUInteger)(size - 1)]
													encoding:NSUTF8StringEncoding];
				
				// UTF8 string encoding can fail sometimes on some invalid-ish strings
				if (!stringValue)
				{
					newStringValue = [[NSString alloc] initWithData:[NSData dataWithBytes:value length:(NSUInteger)(size - 1)]
														   encoding:NSASCIIStringEncoding];
					[self setStringValue:newStringValue];
					[newStringValue release];
					newStringValue = nil;
				}
				
				if (!stringValue)
				{
					[self setStringValue:@""];
				}
				
				break;
			case ZGUTF16String:
				newStringValue = [[NSString alloc] initWithData:[NSData dataWithBytes:value length:(NSUInteger)size]
													   encoding:NSUTF16LittleEndianStringEncoding];
				
				[self setStringValue:newStringValue];
				[newStringValue release];
				
				if (!stringValue)
				{
					[self setStringValue:@""];
				}
				
				break;
		}
	}
	else
	{
		[self setStringValue:@""];
	}
}

- (void)setVariableValue:(void *)newValue
{
	if (value)
	{
		free(value);
		value = NULL;
	}

	if (newValue && size > 0)
	{
		value = malloc((size_t)size);
		memcpy(value, newValue, (size_t)size);
	}
}

- (void)setFreezeValue:(void *)newFreezeValue
{
	if (freezeValue)
	{
		free(freezeValue);
	}
	
	freezeValue = malloc((size_t)size);
	memcpy(freezeValue, newFreezeValue, (size_t)size);
}

- (void)setName:(NSString *)newName
{
	[name release];
	name = [newName copy];
}

// frees value, freezeValue, makes unfrozen
- (void)cleanState
{
	if (value)
	{
		free(value);
		value = NULL;
	}
	
	// Only safe way to go about the freeze value is to remove it..
	if (freezeValue)
	{
		free(freezeValue);
		freezeValue = NULL;
	}
	
	if (isFrozen)
	{
		isFrozen = NO;
	}
}

- (void)setType:(ZGVariableType)newType
	pointerSize:(unsigned long long)pointerSize
{
	type = newType;
	
	[self cleanState];
	
	size = [ZGVariable sizeFromType:newType
						pointerSize:pointerSize];
}

// Precondition: size != pointerSize, otherwise this is a wasted effort
//               also, this must be a pointer type variable
- (void)setPointerSize:(unsigned long long)pointerSize
{
	[self cleanState];
	
	size = [ZGVariable sizeFromType:type
						pointerSize:pointerSize];
}

@end
