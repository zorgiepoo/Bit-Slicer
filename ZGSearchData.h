/*
 * Created by Mayur Pawashe on 7/21/12.
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

#import <Foundation/Foundation.h>
#import "ZGMemoryTypes.h"

#define DEFAULT_FLOATING_POINT_EPSILON 0.1

@interface ZGSearchData : NSObject
{
@public
	// All for fast access, for comparison functions
	void *_rangeValue;
	double _epsilon;
	BOOL _shouldIgnoreStringCase;
	BOOL _shouldIncludeNullTerminator;
	void *_compareOffset;
	CollatorRef _collator; // For comparing unicode strings
	unsigned char *_byteArrayFlags; // For wildcard byte array searches
	
	BOOL _shouldCancelSearch;
}

@property (readwrite, nonatomic) void *searchValue;
@property (readwrite, nonatomic) ZGMemorySize dataSize;
@property (readwrite, nonatomic) ZGMemorySize dataAlignment;

@property (readwrite, nonatomic) void *rangeValue;
@property (readwrite, copy, nonatomic) NSString *lastEpsilonValue;
@property (readwrite, copy, nonatomic) NSString *lastAboveRangeValue;
@property (readwrite, copy, nonatomic) NSString *lastBelowRangeValue;
@property (readwrite, strong, nonatomic) NSArray *savedData;
@property (readwrite, strong, nonatomic) NSArray *tempSavedData;
@property (readwrite, nonatomic) BOOL shouldCompareStoredValues;
@property (readwrite, nonatomic) double epsilon;
@property (readwrite, nonatomic) BOOL shouldIgnoreStringCase;
@property (readwrite, nonatomic) BOOL shouldIncludeNullTerminator;
@property (readwrite, nonatomic) ZGMemoryAddress beginAddress;
@property (readwrite, nonatomic) ZGMemoryAddress endAddress;
@property (readwrite, nonatomic) BOOL shouldScanUnwritableValues;
@property (readwrite, assign, nonatomic) void *compareOffset;
@property (readwrite, nonatomic) unsigned char *byteArrayFlags;

@property (readwrite, nonatomic) BOOL shouldCancelSearch;
@property (readwrite) BOOL searchDidCancel;

@end
