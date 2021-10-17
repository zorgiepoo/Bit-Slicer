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

#import <Foundation/Foundation.h>
#import "ZGMemoryTypes.h"
#import "ZGSearchProtectionMode.h"

#define DEFAULT_FLOATING_POINT_EPSILON 0.1

@class ZGStoredData;

NS_ASSUME_NONNULL_BEGIN

@interface ZGSearchData : NSObject
{
@public
	// All for fast access, for comparison functions
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-interface-ivars"
	ZGMemorySize _dataSize;
	void * _Nullable _rangeValue;
	double _epsilon;
	BOOL _shouldIgnoreStringCase;
	BOOL _shouldIncludeNullTerminator;
	
	// For searching non-native byte order
	void * _Nullable _swappedValue;
	BOOL _bytesSwapped;
	
	// For linearly express stored values
	void * _Nullable _additiveConstant;
	void * _Nullable _multiplicativeConstant;
	
	CollatorRef _Nullable _collator; // For comparing unicode strings
	unsigned char * _Nullable _byteArrayFlags; // For wildcard byte array searches
#pragma clang diagnostic pop
}

@property (nonatomic, nullable) void *searchValue;
@property (nonatomic) ZGMemorySize dataSize;
@property (nonatomic) ZGMemorySize dataAlignment;
@property (nonatomic) ZGMemorySize pointerSize;

@property (nonatomic, nullable) void *swappedValue;
@property (nonatomic) BOOL bytesSwapped;

@property (nonatomic, nullable) void *rangeValue;
@property (nonatomic, nullable) ZGStoredData *savedData;
@property (nonatomic) BOOL shouldCompareStoredValues;
@property (nonatomic) double epsilon;
@property (nonatomic) BOOL shouldIgnoreStringCase;
@property (nonatomic) BOOL shouldIncludeNullTerminator;
@property (nonatomic) ZGMemoryAddress beginAddress;
@property (nonatomic) ZGMemoryAddress endAddress;
@property (nonatomic) ZGProtectionMode protectionMode;
@property (nonatomic, nullable) void *additiveConstant;
@property (nonatomic, nullable) void *multiplicativeConstant;
@property (nonatomic, nullable) unsigned char *byteArrayFlags;
@property (nonatomic) BOOL includeSharedMemory;

- (id)initWithSearchValue:(nullable void *)searchValue dataSize:(ZGMemorySize)dataSize dataAlignment:(ZGMemorySize)dataAlignment pointerSize:(ZGMemorySize)pointerSize;

@end

NS_ASSUME_NONNULL_END
