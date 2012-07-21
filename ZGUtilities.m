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
 * Created by Mayur Pawashe on 5/12/11.
 * Copyright 2010 zgcoder. All rights reserved.
 */

#import "ZGUtilities.h"
#import "NSStringAdditions.h"
#import "ZGProcess.h"

ZGMemoryAddress memoryAddressFromExpression(NSString *expression)
{
	ZGMemoryAddress address;
	if ([expression isHexRepresentation])
	{
		[[NSScanner scannerWithString:expression] scanHexLongLong:&address];
	}
	else
	{
		address = [expression unsignedLongLongValue];
	}
	
	return address;
}

BOOL isValidNumber(NSString *expression)
{
	BOOL result = YES;
	
	// If it's in hex, then we assume it's valid
	if (![expression isHexRepresentation])
	{
		NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
		NSNumber *number = [numberFormatter numberFromString:expression];
		result = (number != nil);
		[numberFormatter release];
	}
	
	return result;
}

void *valueFromString(ZGProcess *process, NSString *stringValue, ZGVariableType dataType, ZGMemorySize *dataSize)
{
	void *value = NULL;
	BOOL searchValueIsAHexRepresentation = [stringValue isHexRepresentation];
	
	if (dataType == ZGInt8)
	{
		int8_t variableValue = 0;
		
		if (searchValueIsAHexRepresentation)
		{
			unsigned int theValue = 0;
			[[NSScanner scannerWithString:stringValue] scanHexInt:&theValue];
			variableValue = theValue;
		}
		else
		{
			variableValue = [stringValue intValue];
		}
		
		*dataSize = 1;
		value = malloc((size_t)*dataSize);
		memcpy(value, &variableValue, (size_t)*dataSize);
	}
	else if (dataType == ZGInt16)
	{
		int16_t variableValue = 0;
		
		if (searchValueIsAHexRepresentation)
		{
			unsigned int theValue = 0;
			[[NSScanner scannerWithString:stringValue] scanHexInt:&theValue];
			variableValue = theValue;
		}
		else
		{
			variableValue = [stringValue intValue];
		}
		
		*dataSize = 2;
		value = malloc((size_t)*dataSize);
		memcpy(value, &variableValue, (size_t)*dataSize);
	}
	else if (dataType == ZGInt32 || (dataType == ZGPointer && ![process is64Bit]))
	{
		int32_t variableValue = 0;
		
		if (searchValueIsAHexRepresentation)
		{
			unsigned int theValue = 0;
			[[NSScanner scannerWithString:stringValue] scanHexInt:&theValue];
			variableValue = theValue;
		}
		else
		{
			variableValue = [stringValue unsignedIntValue];
		}
		
		*dataSize = 4;
		value = malloc((size_t)*dataSize);
		memcpy(value, &variableValue, (size_t)*dataSize);
	}
	else if (dataType == ZGFloat)
	{
		float variableValue = 0.0;
		
		if (searchValueIsAHexRepresentation)
		{
			[[NSScanner scannerWithString:stringValue] scanHexFloat:&variableValue];
		}
		else
		{
			variableValue = [stringValue floatValue];
		}
		
		*dataSize = 4;
		value = malloc((size_t)*dataSize);
		memcpy(value, &variableValue, (size_t)*dataSize);
	}
	else if (dataType == ZGInt64 || (dataType == ZGPointer && [process is64Bit]))
	{
		int64_t variableValue = 0;
		
		if (searchValueIsAHexRepresentation)
		{
			unsigned long long theValue = 0;
			[[NSScanner scannerWithString:stringValue] scanHexLongLong:&theValue];
			variableValue = theValue;
		}
		else
		{
			variableValue = [stringValue unsignedLongLongValue];
		}
		
		*dataSize = 8;
		value = malloc((size_t)*dataSize);
		memcpy(value, &variableValue, (size_t)*dataSize);
	}
	else if (dataType == ZGDouble)
	{
		double variableValue = 0.0;
		
		if (searchValueIsAHexRepresentation)
		{
			[[NSScanner scannerWithString:stringValue] scanHexDouble:&variableValue];
		}
		else
		{
			variableValue = [stringValue doubleValue];
		}
		
		*dataSize = 8;
		value = malloc((size_t)*dataSize);
		memcpy(value, &variableValue, (size_t)*dataSize);
	}
	else if (dataType == ZGUTF8String)
	{
		const char *variableValue = [stringValue cStringUsingEncoding:NSUTF8StringEncoding];
		*dataSize = strlen(variableValue) + 1;
		value = malloc((size_t)*dataSize);
		strncpy(value, variableValue, (size_t)*dataSize);
	}
	else if (dataType == ZGUTF16String)
	{
		*dataSize = [stringValue length] * sizeof(unichar);
		value = malloc((size_t)*dataSize);
		[stringValue getCharacters:value
							 range:NSMakeRange(0, [stringValue length])];
	}
	
	else if (dataType == ZGByteArray)
	{
		NSArray *bytesArray = [stringValue componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		
		*dataSize = [bytesArray count];
		value = malloc((size_t)*dataSize);
		
		unsigned char *valuePtr = value;
		
		for (NSString *byteString in bytesArray)
		{
			unsigned int theValue = 0;
			if (([byteString rangeOfString:@"?"].location == NSNotFound && [byteString rangeOfString:@"*"].location == NSNotFound) || [byteString length] != 2)
			{
				[[NSScanner scannerWithString:byteString] scanHexInt:&theValue];
				*valuePtr = (unsigned char)theValue;
			}
			else
			{
				*valuePtr = 0;
				if ([byteString length] == 2)
				{
					[[NSScanner scannerWithString:[byteString substringToIndex:1]] scanHexInt:&theValue];
					*valuePtr = (((unsigned char)theValue) << 4) & 0xF0;
					theValue = 0;
					[[NSScanner scannerWithString:[byteString substringFromIndex:1]] scanHexInt:&theValue];
					*valuePtr |= ((unsigned char)theValue) & 0x0F;
				}
			}
			
			valuePtr++;
		}
	}
	
	return value;
}

unsigned char *allocateFlagsForByteArrayWildcards(NSString *searchValue)
{
	NSArray *bytesArray = [searchValue componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	
	unsigned char *data = calloc(1, [bytesArray count] * sizeof(unsigned char));
	
	if (data)
	{
		__block BOOL didUseWildcard = NO;
		[bytesArray enumerateObjectsUsingBlock:^(NSString *byteString, NSUInteger byteIndex, BOOL *stop)
		 {
			 if ([byteString length] == 2)
			 {
				 if ([[byteString substringToIndex:1] isEqualToString:@"?"] || [[byteString substringToIndex:1] isEqualToString:@"*"])
				 {
					 data[byteIndex] |= 0xF0;
					 didUseWildcard = YES;
				 }
				 
				 if ([[byteString substringFromIndex:1] isEqualToString:@"?"] || [[byteString substringFromIndex:1] isEqualToString:@"*"])
				 {
					 data[byteIndex] |= 0x0F;
					 didUseWildcard = YES;
				 }
			 }
		 }];
		
		if (!didUseWildcard)
		{
			free(data);
			data = NULL;
		}
	}
    
	return data;
}

