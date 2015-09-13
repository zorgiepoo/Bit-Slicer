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
#import "ZGMemoryTypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZGSearchResults : NSObject

@property (nonatomic, readonly) ZGMemorySize addressIndex;
@property (nonatomic, readonly) ZGMemorySize addressCount;
@property (nonatomic, readonly) ZGMemorySize pointerSize;
@property (nonatomic, readonly) ZGMemorySize dataSize;
@property (nonatomic, readonly) NSArray<NSData *> *resultSets;

// User data fields
@property (nonatomic) NSInteger dataType;
@property (nonatomic) BOOL enabled;

typedef void (^zg_enumerate_search_results_t)(ZGMemoryAddress address, BOOL *stop);

- (id)initWithResultSets:(NSArray<NSData *> *)resultSets dataSize:(ZGMemorySize)dataSize pointerSize:(ZGMemorySize)pointerSize;

- (void)removeNumberOfAddresses:(ZGMemorySize)numberOfAddresses;

- (void)enumerateWithCount:(ZGMemorySize)addressCount usingBlock:(zg_enumerate_search_results_t)addressCallback;
- (void)enumerateUsingBlock:(zg_enumerate_search_results_t)addressCallback;

@end

NS_ASSUME_NONNULL_END
