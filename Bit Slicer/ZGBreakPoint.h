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

/*
 * ZGBreakPoint - Breakpoint Management
 * ==================================
 *
 * This module defines breakpoints for the debugger, supporting instruction
 * breakpoints, data watchpoints, and single-step breakpoints.
 *
 * Breakpoint Types:
 * ---------------
 * - Instruction Breakpoints: Triggered when execution reaches a specific address
 * - Data Watchpoints: Triggered when memory at a specific address is accessed
 * - Single-Step Breakpoints: Triggered after executing a single instruction
 *
 * Breakpoint Lifecycle:
 * -------------------
 *
 *                                 +----------------+
 *                                 | Create         |
 *                                 | Breakpoint     |
 *                                 +--------+-------+
 *                                          |
 *                                          | (Install)
 *                                          v
 *  +----------------+            +-------------------+
 *  | Hardware BP:   |            | Software BP:      |
 *  | Set Debug Regs |<-----------| Replace Instr     |
 *  | (watchpoints)  |    |       | with Trap         |
 *  +----------------+    |       +-------------------+
 *          ^             |                ^
 *          |             |                |
 *          +-------------+----------------+
 *                        |
 *                        | (Breakpoint Hit)
 *                        v
 *               +-------------------+
 *               | Exception Handler |
 *               | Catches Trap      |
 *               +-------------------+
 *                        |
 *                        | (Process Exception)
 *                        v
 *  +----------------+   +-------------------+   +------------------+
 *  | Get Thread     |-->| Notify Delegate  |-->| Get/Set Registers |
 *  | State          |   | (User Code)      |   | (Modify State)    |
 *  +----------------+   +-------------------+   +------------------+
 *                                |
 *                                | (Resume Execution)
 *                                v
 *                       +-------------------+
 *                       | Restore Original  |
 *                       | Instruction       |
 *                       +-------------------+
 *                                |
 *                                | (Single-Step)
 *                                v
 *                       +-------------------+
 *                       | Set Trap Flag     |
 *                       | Execute 1 Instr   |
 *                       +-------------------+
 *                                |
 *                                | (After Single-Step)
 *                                v
 *                       +-------------------+
 *                       | Reinstall         |
 *                       | Breakpoint        |
 *                       +-------------------+
 *                                |
 *                                | (Continue or Remove)
 *                                v
 *                       +-------------------+
 *                       | Resume Normal     |
 *                       | Execution         |
 *                       +-------------------+
 *
 * Interaction with Thread States:
 * -----------------------------
 * When a breakpoint is hit, the thread state is captured and can be
 * examined or modified before execution resumes. This allows for:
 * - Inspecting register values
 * - Modifying register values
 * - Generating backtraces
 * - Conditional breakpoints based on register state
 */

#import <Foundation/Foundation.h>
#import "pythonlib.h"
#import "ZGMemoryTypes.h"
#import "ZGBreakPointDelegate.h"
#import "ZGThreadStates.h"

@class ZGVariable;
@class ZGProcess;
@class ZGRegistersState;
@class ZGDebugThread;

typedef NS_ENUM(NSInteger, ZGBreakPointType)
{
	ZGBreakPointWatchData,
	ZGBreakPointInstruction,
	ZGBreakPointSingleStepInstruction,
};

NS_ASSUME_NONNULL_BEGIN

@interface ZGBreakPoint : NSObject

- (id)initWithProcess:(ZGProcess *)process type:(ZGBreakPointType)type delegate:(nullable id <ZGBreakPointDelegate>)delegate;

@property (atomic, weak, nullable) id <ZGBreakPointDelegate> delegate;
@property (readonly, nonatomic) ZGMemoryMap task;
@property (nonatomic) thread_act_t thread;
@property (nonatomic, nullable) ZGVariable *variable;
@property (nonatomic) ZGMemorySize watchSize;
@property (readonly, nonatomic) ZGProcess *process;
@property (atomic, nullable) NSArray<ZGDebugThread *> *debugThreads;
@property (readonly, nonatomic) ZGBreakPointType type;
@property (atomic) BOOL needsToRestore;
@property (nonatomic) BOOL hidden;
@property (atomic) BOOL dead;
@property (nonatomic) ZGMemoryAddress basePointer;
@property (nonatomic) NSMutableDictionary<NSNumber *, NSNumber *> *cacheDictionary;
@property (nonatomic, nullable) PyObject *condition;
@property (nonatomic, nullable) PyObject *callback;
@property (nonatomic, nullable) NSError *error;
@property (nonatomic) ZGMemoryProtection originalProtection;
@property (nonatomic) ZGRegistersState *registersState;
@property (nonatomic) BOOL emulated;

@end

NS_ASSUME_NONNULL_END
