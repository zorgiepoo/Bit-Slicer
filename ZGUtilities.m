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
