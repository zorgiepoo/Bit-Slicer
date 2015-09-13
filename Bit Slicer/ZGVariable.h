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
#import "ZGVariableTypes.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *ZGVariablePboardType;

@interface ZGVariable : NSObject <NSSecureCoding, NSCopying>
{
@public
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-interface-ivars"
	// For fast access
	NSString *_addressFormula;
#pragma clang diagnostic pop
}

@property (nonatomic) BOOL enabled;
@property (copy, nonatomic) NSString *addressFormula;
@property (nonatomic) ZGVariableType type;
@property (nonatomic) BOOL isFrozen;
@property (nonatomic) ZGVariableQualifier qualifier;
@property(nonatomic) CFByteOrder byteOrder;
@property (readonly, nonatomic) ZGMemoryAddress address;
@property (nonatomic) ZGMemorySize size;
@property (nonatomic) ZGMemorySize lastUpdatedSize;
@property (nonatomic) BOOL usesDynamicAddress;
@property (nonatomic) BOOL finishedEvaluatingDynamicAddress;

- (nullable void *)rawValue;
- (void)setRawValue:(nullable const void *)rawValue;

- (nullable void *)freezeValue;
- (void)setFreezeValue:(nullable const void *)freezeValue;

- (NSString *)addressStringValue;
- (void)setAddressStringValue:(nullable NSString *)newAddressString;

@property (readonly, nonatomic) NSString *stringValue;

@property (copy, nonatomic, nullable) NSString *scriptValue;
@property (copy, nonatomic, nullable) NSString *cachedScriptPath;
@property (copy, nonatomic, nullable) NSString *cachedScriptUUID;

@property (readonly, nonatomic) NSString *sizeStringValue;
@property (nonatomic) BOOL userAnnotated;
@property (copy, nonatomic) NSAttributedString *fullAttributedDescription;
@property (nonatomic, readonly) NSString *shortDescription;
@property (nonatomic, readonly) NSString *name;

- (id)initWithValue:(nullable const void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)type qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize;

- (id)initWithValue:(nullable const void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)type qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize description:(nullable NSAttributedString *)description;

- (id)initWithValue:(nullable const void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)type qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize description:(nullable NSAttributedString *)description enabled:(BOOL)enabled;

- (id)initWithValue:(nullable const void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)type qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize byteOrder:(CFByteOrder)byteOrder;

- (id)initWithValue:(nullable const void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)type qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize description:(nullable NSAttributedString *)description enabled:(BOOL)enabled byteOrder:(CFByteOrder)byteOrder;

+ (NSString *)byteArrayStringFromValue:(unsigned char *)value size:(ZGMemorySize)size;

- (void)updateStringValue;

- (void)setType:(ZGVariableType)newType requestedSize:(ZGMemorySize)requestedSize pointerSize:(ZGMemorySize)pointerSize;
- (void)changePointerSize:(ZGMemorySize)pointerSize;

@end

NS_ASSUME_NONNULL_END
