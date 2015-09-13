/*
 * Copyright (c) 2013 Mayur Pawashe
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

#define ZGWatchVariablesArrayKey @"ZGWatchVariablesArrayKey"
#define ZGProcessInternalNameKey @"ZGProcessNameKey"

#define ZGSelectedDataTypeTag @"ZGSelectedDataTypeTag"
#define ZGQualifierTagKey @"ZGQualifierKey"
#define ZGByteOrderTagKey @"ZGByteOrderTagKey"
#define ZGFunctionTypeTagKey @"ZGFunctionTypeTagKey"
#define ZGProtectionModeKey @"ZGProtectionModeKey"
#define ZGIgnoreDataAlignmentKey @"ZGIgnoreDataAlignmentKey"
#define ZGExactStringLengthKey @"ZGExactStringLengthKey"
#define ZGIgnoreStringCaseKey @"ZGIgnoreStringCaseKey"
#define ZGBeginningAddressKey @"ZGBeginningAddressKey"
#define ZGEndingAddressKey @"ZGEndingAddressKey"
#define ZGEpsilonKey @"ZGEpsilonKey"
#define ZGAboveValueKey @"ZGAboveValueKey"
#define ZGBelowValueKey @"ZGBelowValueKey"
#define ZGSearchStringValueKeyNew @"ZGSearchStringValueNewKey"
#define ZGSearchStringValueKeyOld @"ZGSearchStringValueKey" // legacy

NS_ASSUME_NONNULL_BEGIN

@class ZGVariable;

@interface ZGDocumentData : NSObject

@property (nonatomic) NSInteger selectedDatatypeTag;
@property (nonatomic) NSInteger qualifierTag;
@property (nonatomic) NSInteger byteOrderTag;
@property (nonatomic) NSInteger functionTypeTag;
@property (nonatomic) BOOL ignoreDataAlignment;
@property (copy, nonatomic) NSString *beginningAddressStringValue;
@property (copy, nonatomic) NSString *endingAddressStringValue;
@property (copy, nonatomic) NSString *searchValue;
@property (nonatomic) NSArray<ZGVariable *> *variables;
@property (copy, nonatomic, nullable) NSString *desiredProcessInternalName;
@property (copy, nonatomic) NSString *lastEpsilonValue;
@property (copy, nonatomic, nullable) NSString *lastAboveRangeValue;
@property (copy, nonatomic, nullable) NSString *lastBelowRangeValue;

@end

NS_ASSUME_NONNULL_END
