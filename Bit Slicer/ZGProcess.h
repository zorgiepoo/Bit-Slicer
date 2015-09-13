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
#import "ZGSymbolicator.h"
#import "ZGMemoryTypes.h"
#import <sys/sysctl.h>

#define NON_EXISTENT_PID_NUMBER -1

NS_ASSUME_NONNULL_BEGIN

@class ZGMachBinary;

@interface ZGProcess : NSObject

- (instancetype)initWithName:(nullable NSString *)processName internalName:(NSString *)internalName processID:(pid_t)aProcessID is64Bit:(BOOL)flag64Bit;

- (instancetype)initWithName:(nullable NSString *)processName internalName:(NSString *)internalName is64Bit:(BOOL)flag64Bit;

- (instancetype)initWithProcess:(ZGProcess *)process;

- (instancetype)initWithProcess:(ZGProcess *)process name:(nullable NSString *)name;

- (instancetype)initWithProcess:(ZGProcess *)process processTask:(ZGMemoryMap)processTask;

@property (nonatomic, readonly) pid_t processID;
@property (nonatomic, readonly) ZGMemoryMap processTask;
@property (nonatomic, readonly) BOOL valid;
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *internalName;
@property (nonatomic, readonly) BOOL is64Bit;

// indicates if this represents any sort of actual program.. admittingly, this is kind of a hack
@property (nonatomic) BOOL isDummy;

@property (nonatomic, readonly, nullable) ZGMachBinary *mainMachBinary;
@property (nonatomic, readonly, nullable) ZGMachBinary *dylinkerBinary;

@property (nonatomic, readonly) NSMutableDictionary<NSString *, NSMutableDictionary *> *cacheDictionary;

@property (nonatomic, readonly, nullable) id <ZGSymbolicator> symbolicator;

- (BOOL)isEqual:(id)process;

- (BOOL)hasGrantedAccess;

- (ZGMemorySize)pointerSize;

@end

NS_ASSUME_NONNULL_END
