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
 * Created by Mayur Pawashe on 5/12/11
 * Copyright 2011 zgcoder. All rights reserved.
 */

#import "ZGLineCountingRepresenter.h"
#import "ZGLineCountingView.h"

@implementation ZGLineCountingRepresenter

// Use a ZGLineCountingView instead of a HFLineCountingView
- (NSView *)createView
{
    ZGLineCountingView *result = [[ZGLineCountingView alloc] initWithFrame:NSMakeRect(0, 0, 60, 10)];
    [result setRepresenter:self];
    [result setAutoresizingMask:NSViewHeightSizable];
    // clang complains but perhaps this is how HexFiend library manages its memory? Argh.
    return result;
}

// Don't do cycling

- (void)setLineNumberFormat:(HFLineNumberFormat)format
{
	if (format == HFLineNumberFormatHexadecimal)
	{
		[super setLineNumberFormat:format];
	}
}

- (void)cycleLineNumberFormat
{
}

- (void)setBeginningMemoryAddress:(ZGMemoryAddress)newBeginningMemoryAddress
{
	_beginningMemoryAddress = newBeginningMemoryAddress;
}

- (ZGMemoryAddress)beginningMemoryAddress
{
	return _beginningMemoryAddress;
}

@end
