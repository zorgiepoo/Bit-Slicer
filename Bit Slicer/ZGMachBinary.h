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
#import "ZGMachBinaryInfo.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const ZGMachBinaryPathToBinaryInfoDictionary;
extern NSString * const ZGMachBinaryPathToBinaryDictionary;
extern NSString * const ZGFailedImageName;

@class ZGProcess;

@interface ZGMachBinary : NSObject

+ (nullable instancetype)dynamicLinkerMachBinaryInProcess:(ZGProcess *)process;
+ (NSArray<ZGMachBinary *> *)machBinariesInProcess:(ZGProcess *)process;
+ (nullable instancetype)mainMachBinaryFromMachBinaries:(NSArray<ZGMachBinary *> *)machBinaries;
+ (nullable instancetype)machBinaryNearestToAddress:(ZGMemoryAddress)address fromMachBinaries:(NSArray<ZGMachBinary *> *)machBinaries;
+ (nullable instancetype)machBinaryWithPartialImageName:(NSString *)partialImageName inProcess:(ZGProcess *)process fromCachedMachBinaries:(nullable NSArray<ZGMachBinary *> *)machBinaries error:(NSError **)error;

- (id)initWithHeaderAddress:(ZGMemoryAddress)headerAddress filePathAddress:(ZGMemoryAddress)filePathAddress;

@property (nonatomic, readonly) ZGMemoryAddress headerAddress;
@property (nonatomic, readonly) ZGMemoryAddress filePathAddress;

+ (NSArray<NSString *> *)filePathsForMachBinaries:(NSArray<ZGMachBinary *> *)machBinaries inProcess:(ZGProcess *)process;
- (nullable NSString *)filePathInProcess:(ZGProcess *)process;

- (nullable ZGMachBinaryInfo *)machBinaryInfoInProcess:(ZGProcess *)process;

@end

NS_ASSUME_NONNULL_END
