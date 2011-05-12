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
 * Created by Mayur Pawashe on 5/11/11
 * Copyright 2011 zgcoder. All rights reserved.
 */

#import "ZGStatusBarRepresenter.h"

@interface ZGStatusBarRepresenter (InheritedPrivateMethods)

- (NSString *)describeOffset:(unsigned long long)offset;
- (NSString *)describeLength:(unsigned long long)length;
- (NSString *)describeOffsetExcludingApproximate:(unsigned long long)offset;

@end

@interface HFStatusBarRepresenter (PrivateMethods)

- (void)updateString;

@end

@implementation ZGStatusBarRepresenter

- (void)setBeginningOffset:(ZGMemoryAddress)offset
{
	_beginningOffset = offset;
}

- (NSString *)stringForEmptySelectionAtOffset:(unsigned long long)offset length:(unsigned long long)length
{
    return [NSString stringWithFormat:@"Selected address is %@", [self describeOffset:offset + _beginningOffset]];
}

- (NSString *)stringForSingleByteSelectionAtOffset:(unsigned long long)offset length:(unsigned long long)length
{
    return [NSString stringWithFormat:@"Selected address is %@", [self describeOffset:offset + _beginningOffset]];
}

- (NSString *)stringForSingleRangeSelection:(HFRange)range length:(unsigned long long)length
{
    return [NSString stringWithFormat:@"%@ selected at address %@", [self describeLength:range.length], [self describeOffsetExcludingApproximate:range.location + _beginningOffset]];
}

- (NSString *)stringForMultipleSelectionsWithLength:(unsigned long long)multipleSelectionLength length:(unsigned long long)length
{
    return [NSString stringWithFormat:@"%@ selected at multiple addresses", [self describeLength:multipleSelectionLength]];
}

- (void)setStatusMode:(HFStatusBarMode)mode
{
	if (mode == HFStatusModeHexadecimal)
	{
		[super setStatusMode:mode];
	}
}

- (void)updateString
{
	[super updateString];
}

@end
