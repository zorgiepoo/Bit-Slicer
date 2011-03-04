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
 * Created by Mayur Pawashe on 8/24/10.
 * Copyright 2010 zgcoder. All rights reserved.
 */

#import "NSStringAdditions.h"

@implementation NSString (NSStringAdditions)

- (unsigned int)unsignedIntValue
{
	return strtoul([self UTF8String], NULL, 10);
}

- (unsigned long long)unsignedLongLongValue
{
	return strtoull([self UTF8String], NULL, 10);
}

- (BOOL)isHexRepresentation
{
	return ([self length] > 2 && ([[self substringToIndex:2] caseInsensitiveCompare:@"0x"] == NSOrderedSame || [[self substringToIndex:3] caseInsensitiveCompare:@"-0x"] == NSOrderedSame));
}

@end
