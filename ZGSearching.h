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
 * Created by Mayur Pawashe on 8/18/10.
 * Copyright 2010 zgcoder. All rights reserved.
 */

#import "ZGVirtualMemory.h"

typedef struct
{
	double epsilon;
	void *rangeValue;
	BOOL sensitive; // "Hi" == "hi" if insensitive
	BOOL disregardNullTerminator;
	BOOL isImplicit; // Should compare stored values?
	
	NSString *lastEpsilonValue;
	NSString *lastAboveRangeValue;
	NSString *lastBelowRangeValue;
	
	// these are not NSString's because there's no reason to save the values
	ZGMemoryAddress beginAddress;
	ZGMemoryAddress endAddress;
	BOOL beginAddressExists;
	BOOL endAddressExists;
} ZGSearchArguments;
