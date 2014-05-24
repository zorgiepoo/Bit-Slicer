/*
 * Created by Mayur Pawashe on 5/12/11.
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

#import "ZGUtilities.h"
#import "NSStringAdditions.h"

BOOL ZGGrantMemoryAccessToProcess(ZGProcessTaskManager *processTaskManager, ZGProcess *process)
{
	ZGMemoryMap processTask;
	BOOL success = [processTaskManager getTask:&processTask forProcessIdentifier:process.processID];
	process.processTask = processTask;
	
	return success;
}

ZGMemoryAddress ZGMemoryAddressFromExpression(NSString *expression)
{
	ZGMemoryAddress address;
	if (expression.zgIsHexRepresentation)
	{
		[[NSScanner scannerWithString:expression] scanHexLongLong:&address];
	}
	else
	{
		address = expression.zgUnsignedLongLongValue;
	}
	
	return address;
}

BOOL ZGIsValidNumber(NSString *expression)
{
	BOOL result = YES;
	
	// If it's in hex, then we assume it's valid
	if (![expression zgIsHexRepresentation])
	{
		NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
		// We have to use en_US locale since we don't want commas to be used for decimal points
		// Also DDMathParser won't handle a comma as decimal point for evaluating expressions either due to ambiguity
		[numberFormatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
		NSNumber *number = [numberFormatter numberFromString:expression];
		result = (number != nil);
	}
	
	return result;
}

BOOL ZGIsNumericalDataType(ZGVariableType dataType)
{
	return (dataType != ZGByteArray && dataType != ZGString8 && dataType != ZGString16);
}

ZGMemorySize ZGDataSizeFromNumericalDataType(BOOL isProcess64Bit, ZGVariableType dataType)
{
	ZGMemorySize dataSize;
	switch (dataType)
	{
		case ZGInt8:
			dataSize = 1;
			break;
		case ZGInt16:
			dataSize = 2;
			break;
		case ZGInt32:
		case ZGFloat:
			dataSize = 4;
			break;
		case ZGInt64:
		case ZGDouble:
			dataSize = 8;
			break;
		case ZGPointer:
			dataSize = isProcess64Bit ? 8 : 4;
			break;
		case ZGString8:
		case ZGString16:
		case ZGByteArray:
		case ZGScript:
			dataSize = 0;
			break;
	}
	return dataSize;
}

NSArray *ZGByteArrayComponentsFromString(NSString *searchString)
{
	NSArray *originalByteArray = [searchString componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	NSMutableArray *transformedByteArray = [NSMutableArray array];
	
	for (NSString *byteString in originalByteArray)
	{
		for (NSUInteger byteIndex = 0; byteIndex < byteString.length; byteIndex++)
		{
			if (byteIndex % 2 == 1)
			{
				[transformedByteArray addObject:[byteString substringWithRange:NSMakeRange(byteIndex - 1, 2)]];
			}
			else if (byteIndex == byteString.length - 1)
			{
				[transformedByteArray addObject:[byteString substringWithRange:NSMakeRange(byteIndex, 1)]];
			}
		}
	}
	
	return transformedByteArray;
}

void *ZGSwappedValue(BOOL isProcess64Bit, void *value, ZGVariableType dataType, ZGMemorySize dataSize)
{
	void *swappedValue = malloc(dataSize);
	
	if (dataType == ZGPointer)
	{
		dataType = isProcess64Bit ? ZGInt64 : ZGInt32;
	}
	
	switch (dataType)
	{
		case ZGInt16:
		{
			uint16_t tempValue = CFSwapInt16(*(uint16_t *)value);
			memcpy(swappedValue, &tempValue, dataSize);
			break;
		}
		
		case ZGInt32:
		{
			uint32_t tempValue = CFSwapInt32(*(uint32_t *)value);
			memcpy(swappedValue, &tempValue, dataSize);
			break;
		}
			
		case ZGInt64:
		{
			uint64_t tempValue = CFSwapInt64(*(uint64_t *)value);
			memcpy(swappedValue, &tempValue, dataSize);
			break;
		}
			
		case ZGFloat:
		{
			CFSwappedFloat32 tempValue = CFConvertFloat32HostToSwapped(*(Float32 *)value);
			memcpy(swappedValue, &tempValue, dataSize);
			break;
		}
			
		case ZGDouble:
		{
			CFSwappedFloat64 tempValue = CFConvertFloat64HostToSwapped(*(Float64 *)value);
			memcpy(swappedValue, &tempValue, dataSize);
			break;
		}
			
		case ZGString16:
		{
			for (ZGMemorySize characterIndex = 0; characterIndex < dataSize / sizeof(uint16_t); characterIndex++)
			{
				((uint16_t *)swappedValue)[characterIndex] = CFSwapInt16(((uint16_t *)value)[characterIndex]);
			}
			break;
		}
		
		case ZGInt8:
		case ZGString8:
		case ZGByteArray:
			memcpy(swappedValue, value, dataSize);
			break;
		case ZGScript:
		case ZGPointer:
			break;
	}
	
	return swappedValue;
}

void *ZGValueFromString(BOOL isProcess64Bit, NSString *stringValue, ZGVariableType dataType, ZGMemorySize *dataSize)
{
	void *value = NULL;
	BOOL searchValueIsAHexRepresentation = stringValue.zgIsHexRepresentation;
	ZGMemorySize tempDataSize = 0;
	
	if (ZGIsNumericalDataType(dataType))
	{
		tempDataSize = ZGDataSizeFromNumericalDataType(isProcess64Bit, dataType);
	}
	
	if (dataType == ZGInt8 && tempDataSize > 0)
	{
		int8_t variableValue = 0;
		
		if (searchValueIsAHexRepresentation)
		{
			unsigned int theValue = 0;
			[[NSScanner scannerWithString:stringValue] scanHexInt:&theValue];
			variableValue = (int8_t)theValue;
		}
		else
		{
			variableValue = (int8_t)stringValue.intValue;
		}
		
		value = malloc((size_t)tempDataSize);
		memcpy(value, &variableValue, (size_t)tempDataSize);
	}
	else if (dataType == ZGInt16 && tempDataSize > 0)
	{
		int16_t variableValue = 0;
		
		if (searchValueIsAHexRepresentation)
		{
			unsigned int theValue = 0;
			[[NSScanner scannerWithString:stringValue] scanHexInt:&theValue];
			variableValue = (int16_t)theValue;
		}
		else
		{
			variableValue = (int16_t)stringValue.intValue;
		}
		
		value = malloc((size_t)tempDataSize);
		memcpy(value, &variableValue, (size_t)tempDataSize);
	}
	else if ((dataType == ZGInt32 || (dataType == ZGPointer && !isProcess64Bit)) && tempDataSize > 0)
	{
		uint32_t variableValue = 0;
		
		if (searchValueIsAHexRepresentation)
		{
			unsigned int theValue = 0;
			[[NSScanner scannerWithString:stringValue] scanHexInt:&theValue];
			variableValue = theValue;
		}
		else
		{
			variableValue = stringValue.zgUnsignedIntValue;
		}
		
		value = malloc((size_t)tempDataSize);
		memcpy(value, &variableValue, (size_t)tempDataSize);
	}
	else if (dataType == ZGFloat && tempDataSize > 0)
	{
		float variableValue = 0.0;
		
		if (searchValueIsAHexRepresentation)
		{
			[[NSScanner scannerWithString:stringValue] scanHexFloat:&variableValue];
		}
		else
		{
			variableValue = stringValue.floatValue;
		}
		
		value = malloc((size_t)tempDataSize);
		memcpy(value, &variableValue, (size_t)tempDataSize);
	}
	else if ((dataType == ZGInt64 || (dataType == ZGPointer && isProcess64Bit)) && tempDataSize > 0)
	{
		uint64_t variableValue = 0;
		
		if (searchValueIsAHexRepresentation)
		{
			unsigned long long theValue = 0;
			[[NSScanner scannerWithString:stringValue] scanHexLongLong:&theValue];
			variableValue = theValue;
		}
		else
		{
			variableValue = stringValue.zgUnsignedLongLongValue;
		}
		
		value = malloc((size_t)tempDataSize);
		memcpy(value, &variableValue, (size_t)tempDataSize);
	}
	else if (dataType == ZGDouble && tempDataSize > 0)
	{
		double variableValue = 0.0;
		
		if (searchValueIsAHexRepresentation)
		{
			[[NSScanner scannerWithString:stringValue] scanHexDouble:&variableValue];
		}
		else
		{
			variableValue = stringValue.doubleValue;
		}
		
		value = malloc((size_t)tempDataSize);
		memcpy(value, &variableValue, (size_t)tempDataSize);
	}
	else if (dataType == ZGString8)
	{
		const char *variableValue = [stringValue cStringUsingEncoding:NSUTF8StringEncoding];
		tempDataSize = strlen(variableValue);
		value = malloc((size_t)tempDataSize);
		strncpy(value, variableValue, (size_t)tempDataSize);
	}
	else if (dataType == ZGString16)
	{
		tempDataSize = stringValue.length * sizeof(unichar);
		value = malloc((size_t)tempDataSize);
		[stringValue getCharacters:value range:NSMakeRange(0, stringValue.length)];
	}
	
	else if (dataType == ZGByteArray)
	{
		NSArray *bytesArray = ZGByteArrayComponentsFromString(stringValue);
		
		tempDataSize = bytesArray.count;
		value = malloc((size_t)tempDataSize);
		
		unsigned char *valuePtr = value;
		
		for (NSString *byteString in bytesArray)
		{
			unsigned int theValue = 0;
			if (([byteString rangeOfString:@"?"].location == NSNotFound && [byteString rangeOfString:@"*"].location == NSNotFound) || byteString.length != 2)
			{
				[[NSScanner scannerWithString:byteString] scanHexInt:&theValue];
				*valuePtr = (unsigned char)theValue;
			}
			else
			{
				*valuePtr = 0;
				if (byteString.length == 2)
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
	
	if (dataSize != NULL) *dataSize = tempDataSize;
	
	return value;
}

ZGMemorySize ZGDataAlignment(BOOL isProcess64Bit, ZGVariableType dataType, ZGMemorySize dataSize)
{
	ZGMemorySize dataAlignment;
	
	if (dataType == ZGString8 || dataType == ZGByteArray)
	{
		dataAlignment = sizeof(int8_t);
	}
	else if (dataType == ZGString16)
	{
		dataAlignment = sizeof(int16_t);
	}
	else
	{
		// doubles and 64-bit integers are on 4 byte boundaries only in 32-bit processes, while every other integral type is on its own size of boundary
		dataAlignment = (!isProcess64Bit && dataSize == sizeof(int64_t)) ? sizeof(int32_t) : dataSize;
	}
	
	return dataAlignment;
}

unsigned char *ZGAllocateFlagsForByteArrayWildcards(NSString *searchValue)
{
	NSArray *bytesArray = ZGByteArrayComponentsFromString(searchValue);
	
	unsigned char *data = calloc(1, bytesArray.count * sizeof(unsigned char));
	
	if (data)
	{
		__block BOOL didUseWildcard = NO;
		[bytesArray enumerateObjectsUsingBlock:^(NSString *byteString, NSUInteger byteIndex, BOOL *__unused stop)
		 {
			 if (byteString.length == 2)
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

NSString *ZGProtectionDescription(ZGMemoryProtection protection)
{
	NSMutableArray *protectionAttributes = [NSMutableArray array];
	[protectionAttributes addObject:(protection & VM_PROT_READ) ? @"r" : @"-"];
	[protectionAttributes addObject:(protection & VM_PROT_WRITE) ? @"w" : @"-"];
	[protectionAttributes addObject:(protection & VM_PROT_EXECUTE) ? @"x" : @"-"];
	return [protectionAttributes componentsJoinedByString:@""];
}

void ZGUpdateProcessMenuItem(NSMenuItem *menuItem, NSString *name, pid_t processIdentifier, NSImage *icon)
{
	BOOL isDead = (processIdentifier < 0);
	if (isDead)
	{
		NSFont *menuFont = [NSFont menuFontOfSize:12]; // don't think there's a real way to get font size if we were to set the non-attributed title
		NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@ (none)", name]];
		[attributedString addAttribute:NSStrikethroughStyleAttributeName value:@(NSUnderlineStyleSingle) range:NSMakeRange(0, attributedString.length)];
		[attributedString addAttribute:NSFontAttributeName value:menuFont range:NSMakeRange(0, attributedString.length)];
		menuItem.attributedTitle = attributedString;
	}
	else
	{
		menuItem.title = [NSString stringWithFormat:@"%@ (%d)", name, processIdentifier];
	}
	
	NSImage *smallIcon = isDead ? [[NSImage imageNamed:@"NSDefaultApplicationIcon"] copy] : [icon copy];
	smallIcon.size = NSMakeSize(16, 16);
	menuItem.image = smallIcon;
}

void ZGDeliverUserNotification(NSString *title, NSString *subtitle, NSString *informativeText)
{
	NSUserNotification *userNotification = [[NSUserNotification alloc] init];
	userNotification.title = title;
	userNotification.subtitle = subtitle;
	userNotification.informativeText = informativeText;
	[[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:userNotification];
}
