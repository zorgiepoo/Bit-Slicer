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
 *
 * Memory Layout Examples:
 * ---------------------
 *
 * Software Breakpoint Memory Layout (x86_64):
 * +-----------------------------------------------------------------------+
 * | Address         | Original Bytes       | Breakpoint Bytes    | Notes  |
 * |-----------------|----------------------|---------------------|---------|
 * | 0x00007fff5fc05000 | 55 48 89 e5 48 83 ec 10 | cc 48 89 e5 48 83 ec 10 | INT3 replaces first byte |
 * +-----------------------------------------------------------------------+
 *
 * x86_64 INT3 Instruction:
 * - Opcode: 0xCC (1 byte)
 * - When executed, generates a breakpoint exception
 * - Original instruction byte is saved and restored when continuing execution
 *
 * Software Breakpoint Memory Layout (ARM64):
 * +-----------------------------------------------------------------------+
 * | Address         | Original Bytes       | Breakpoint Bytes    | Notes  |
 * |-----------------|----------------------|---------------------|---------|
 * | 0x0000000016fd0000 | f4 4f be a9 fd 7b 01 a9 | 00 00 20 d4 fd 7b 01 a9 | BRK replaces first instruction |
 * +-----------------------------------------------------------------------+
 *
 * ARM64 BRK Instruction:
 * - Opcode: 0xD4200000 (4 bytes)
 * - When executed, generates a breakpoint exception
 * - Original instruction is saved and restored when continuing execution
 *
 * Hardware Breakpoint Memory Layout (x86_64 Debug Registers):
 * +-----------------------------------------------------------------------+
 * | Register | Value                | Description                         |
 * |----------|----------------------|-------------------------------------|
 * | DR0      | 0x00007fff5fc05000   | Address of breakpoint #0            |
 * | DR1      | 0x00007fff5fc06000   | Address of breakpoint #1            |
 * | DR2      | 0x0000000000000000   | Not used                            |
 * | DR3      | 0x0000000000000000   | Not used                            |
 * | DR6      | 0x0000000000000000   | Debug status register               |
 * | DR7      | 0x000000000000D5     | Debug control register              |
 * +-----------------------------------------------------------------------+
 *
 * DR7 Control Register Bits (x86_64):
 * - Bits 0-1: L0, G0 (Local/Global enable for DR0)
 * - Bits 2-3: L1, G1 (Local/Global enable for DR1)
 * - Bits 16-17: R/W0 (00=exec, 01=write, 11=read/write for DR0)
 * - Bits 18-19: LEN0 (00=1 byte, 01=2 bytes, 11=4 bytes for DR0)
 * - Bits 20-21: R/W1 (00=exec, 01=write, 11=read/write for DR1)
 * - Bits 22-23: LEN1 (00=1 byte, 01=2 bytes, 11=4 bytes for DR1)
 *
 * Hardware Breakpoint Memory Layout (ARM64 Debug Registers):
 * +-----------------------------------------------------------------------+
 * | Register | Value                | Description                         |
 * |----------|----------------------|-------------------------------------|
 * | DBGBCR0  | 0x000000000000E5     | Breakpoint Control Register #0      |
 * | DBGBVR0  | 0x0000000016fd0000   | Breakpoint Value Register #0        |
 * | DBGBCR1  | 0x000000000000E7     | Breakpoint Control Register #1      |
 * | DBGBVR1  | 0x0000000016fd1000   | Breakpoint Value Register #1        |
 * | DBGWCR0  | 0x000000000000EF     | Watchpoint Control Register #0      |
 * | DBGWVR0  | 0x0000000016fe0000   | Watchpoint Value Register #0        |
 * +-----------------------------------------------------------------------+
 *
 * DBGBCR Control Register Bits (ARM64):
 * - Bits 0-1: E (01=enabled)
 * - Bits 3-4: PMC (11=user or kernel mode)
 * - Bits 5-8: BAS (1111=match all bytes)
 * - Bits 20-23: BT (0000=execute)
 *
 * DBGWCR Control Register Bits (ARM64):
 * - Bits 0-1: E (01=enabled)
 * - Bits 3-4: PAC (11=user or kernel mode)
 * - Bits 5-12: BAS (11111111=match all bytes)
 * - Bits 20-21: LSC (01=load, 10=store, 11=load/store)
 *
 * Single-Step Implementation:
 * +-----------------------------------------------------------------------+
 * | Architecture | Register        | Value      | Description             |
 * |--------------|-----------------|------------|-------------------------|
 * | x86_64       | RFLAGS          | 0x100      | Trap Flag (bit 8)       |
 * | ARM64        | MDSCR_EL1       | 0x1        | Single Step bit         |
 * +-----------------------------------------------------------------------+
 *
 * When single-stepping is enabled:
 * 1. The CPU executes one instruction
 * 2. A debug exception is generated
 * 3. The debugger handles the exception
 * 4. The original breakpoint is reinstalled
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
