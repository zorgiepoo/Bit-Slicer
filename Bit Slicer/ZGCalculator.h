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
#import "ZGVariable.h"

@class ZGProcess;

#define ZGBaseAddressFunction @"base"

NS_ASSUME_NONNULL_BEGIN

@interface ZGVariable (ZGCalculatorAdditions)

@property (nonatomic, readonly) BOOL usesDynamicPointerAddress;
@property (nonatomic, readonly) BOOL usesDynamicBaseAddress;

@end

@interface ZGCalculator : NSObject

+ (BOOL)parseLinearExpression:(NSString *)linearExpression andGetAdditiveConstant:(NSString * _Nullable * _Nonnull)additiveConstantString multiplicateConstant:(NSString *_Nullable * _Nonnull)multiplicativeConstantString;

+ (nullable NSString *)evaluateExpression:(NSString *)expression;

// Can evaluate [address] + [address2] + offset, [address + [address2 - [address3]]] + offset, etc...
// And also has a base() function that takes in a string, and returns the first address to a region such that the passed string partially matches the end of the corresponding region's mapped path
+ (nullable NSString *)evaluateExpression:(NSString *)expression process:(ZGProcess *)process failedImages:(nullable NSMutableArray<NSString *> *)failedImages error:(NSError **)error;
+ (nullable NSString *)evaluateAndSymbolicateExpression:(NSString *)expression process:(ZGProcess *)process currentAddress:(ZGMemoryAddress)currentAddress didSymbolicate:(nullable BOOL *)didSymbolicate error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
