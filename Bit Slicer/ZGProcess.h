/*
 * Created by Mayur Pawashe on 10/28/09.
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
#import <sys/sysctl.h>

#define NON_EXISTENT_PID_NUMBER -1

@class ZGSearchProgress;
@class ZGMachBinary;

@interface ZGProcess : NSObject

@property (nonatomic) pid_t processID;
@property (nonatomic) ZGMemoryMap processTask;
@property (readonly, nonatomic) BOOL valid;
@property (copy, nonatomic) NSString *name;
@property (copy, nonatomic) NSString *internalName;
@property (nonatomic) BOOL is64Bit;

@property (nonatomic, readonly) ZGMachBinary *mainMachBinary;
@property (nonatomic, readonly) ZGMachBinary *dylinkerBinary;

@property (nonatomic) NSMutableDictionary *cacheDictionary;

+ (void)pauseOrUnpauseProcessTask:(ZGMemoryMap)processTask;

- (instancetype)initWithName:(NSString *)processName internalName:(NSString *)internalName processID:(pid_t)aProcessID is64Bit:(BOOL)flag64Bit;
- (instancetype)initWithName:(NSString *)processName internalName:(NSString *)internalName is64Bit:(BOOL)flag64Bit;
- (instancetype)initWithProcess:(ZGProcess *)process;

- (NSString *)symbolAtAddress:(ZGMemoryAddress)address relativeOffset:(ZGMemoryAddress *)relativeOffset;
- (NSNumber *)findSymbol:(NSString *)symbolName withPartialSymbolOwnerName:(NSString *)partialSymbolOwnerName requiringExactMatch:(BOOL)requiresExactMatch pastAddress:(ZGMemoryAddress)pastAddress;

- (BOOL)isEqual:(id)process;

- (void)markInvalid;
- (BOOL)hasGrantedAccess;

- (ZGMemorySize)pointerSize;

@end
