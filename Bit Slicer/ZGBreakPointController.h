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
#import "Python/Python.h"
#import "ZGMemoryTypes.h"
#import "ZGBreakPointDelegate.h"

#define INSTRUCTION_BREAKPOINT_OPCODE 0xCC

@class ZGVariable;
@class ZGProcess;
@class ZGBreakPoint;
@class ZGInstruction;
@class ZGRunningProcess;
@class ZGAppTerminationState;
@class ZGScriptingInterpreter;

typedef NS_ENUM(uint8_t, ZGWatchPointType)
{
	ZGWatchPointWrite,
	ZGWatchPointReadOrWrite,
};

NS_ASSUME_NONNULL_BEGIN

@interface ZGBreakPointController : NSObject

+ (instancetype)createBreakPointControllerOnceWithScriptingInterpreter:(ZGScriptingInterpreter *)scriptingInterpreter;

@property (nonatomic, readonly) NSArray<ZGBreakPoint *> *breakPoints;
@property (nonatomic) ZGAppTerminationState *appTerminationState;

- (BOOL)addBreakPointOnInstruction:(ZGInstruction *)instruction inProcess:(ZGProcess *)process condition:(PyObject * _Nullable)condition delegate:(id)delegate;
- (BOOL)addBreakPointOnInstruction:(ZGInstruction *)instruction inProcess:(ZGProcess *)process callback:(PyObject *)callback delegate:(id)delegate;
- (BOOL)addBreakPointOnInstruction:(ZGInstruction *)instruction inProcess:(ZGProcess *)process thread:(thread_act_t)thread basePointer:(ZGMemoryAddress)basePointer callback:(PyObject *)callback delegate:(id)delegate;
- (BOOL)addBreakPointOnInstruction:(ZGInstruction *)instruction inProcess:(ZGProcess *)process thread:(thread_act_t)thread basePointer:(ZGMemoryAddress)basePointer delegate:(id)delegate;
- (ZGBreakPoint * _Nullable)removeBreakPointOnInstruction:(ZGInstruction *)instruction inProcess:(ZGProcess *)process;
- (void)resumeFromBreakPoint:(ZGBreakPoint *)breakPoint;
- (ZGBreakPoint *)addSingleStepBreakPointFromBreakPoint:(ZGBreakPoint *)breakPoint;
- (NSArray<ZGBreakPoint *> *)removeSingleStepBreakPointsFromBreakPoint:(ZGBreakPoint *)breakPoint;
- (void)removeInstructionBreakPoint:(ZGBreakPoint *)breakPoint;

- (BOOL)addWatchpointOnVariable:(ZGVariable *)variable inProcess:(ZGProcess *)process watchPointType:(ZGWatchPointType)watchPointType delegate:(id <ZGBreakPointDelegate>)delegate getBreakPoint:(ZGBreakPoint * _Nullable * _Nonnull)returnedBreakPoint;

- (NSArray<ZGBreakPoint *> *)removeObserver:(id)observer;
- (NSArray<ZGBreakPoint *> *)removeObserver:(id)observer runningProcess:(ZGRunningProcess *)process;
- (NSArray<ZGBreakPoint *> *)removeObserver:(id)observer withProcessID:(pid_t)processID atAddress:(ZGMemoryAddress)address;

@end

NS_ASSUME_NONNULL_END
