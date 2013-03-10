/*
 * Created by Mayur Pawashe on 10/29/09.
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

#import <Cocoa/Cocoa.h>
#import "ZGMemoryTypes.h"

extern NSString *ZGVariablePboardType;

@interface ZGVariable : NSObject <NSCoding, NSCopying>
{
	NSString *_addressStringValue;
}

@property (assign, nonatomic) BOOL shouldBeSearched;
@property (copy, nonatomic) NSString *addressFormula;
@property (readwrite, nonatomic) ZGVariableType type;
@property (readwrite, nonatomic) BOOL isFrozen;
@property (readwrite, nonatomic) ZGVariableQualifier qualifier;
@property (readonly, nonatomic) ZGMemoryAddress address;
@property (readwrite, nonatomic) ZGMemorySize size;
@property (readwrite, nonatomic) ZGMemorySize lastUpdatedSize;
@property (readwrite, nonatomic) BOOL isPointer;
@property (readwrite, nonatomic) void *value;
@property (copy, nonatomic) NSString *addressStringValue;
@property (copy, nonatomic) NSString *stringValue;
@property (readwrite, nonatomic) void *freezeValue;
@property (readonly, nonatomic) NSString *sizeStringValue;
@property (copy, nonatomic) NSString *name;

- (id)initWithValue:(void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)aType qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize;

- (id)initWithValue:(void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)aType qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize name:(NSString *)name;

- (id)initWithValue:(void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)aType qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize name:(NSString *)name shouldBeSearched:(BOOL)shouldBeSearched;

- (void)updateStringValue;

- (void)setType:(ZGVariableType)newType requestedSize:(ZGMemorySize)requestedSize pointerSize:(ZGMemorySize)pointerSize;
- (void)setPointerSize:(ZGMemorySize)pointerSize;

@end
