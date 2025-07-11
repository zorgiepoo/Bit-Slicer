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
 * ZGBreakPointController
 * ======================
 *
 * This class manages hardware and software breakpoints in target processes.
 * It handles two main types of breakpoints:
 *
 * 1. Instruction Breakpoints: Software breakpoints that pause execution when a specific instruction is reached.
 *    These work by replacing the first byte of the target instruction with 0xCC (INT 3 instruction).
 *
 * 2. Watchpoints: Hardware breakpoints that monitor memory access.
 *    These use CPU debug registers to detect when specific memory addresses are accessed.
 *
 * For more details on implementation, see ZGBreakPointController.m
 */

#import <Foundation/Foundation.h>
#import "pythonlib.h"
#import "ZGMemoryTypes.h"
#import "ZGBreakPointDelegate.h"

@class ZGVariable;
@class ZGProcess;
@class ZGBreakPoint;
@class ZGInstruction;
@class ZGRunningProcess;
@class ZGAppTerminationState;
@class ZGScriptingInterpreter;
@class ZGCodeInjectionHandler;

/**
 * Defines the type of memory access to watch for in a watchpoint
 *
 * ZGWatchPointWrite:      Trigger when memory is written to
 * ZGWatchPointReadOrWrite: Trigger when memory is either read from or written to
 */
typedef NS_ENUM(uint8_t, ZGWatchPointType)
{
	ZGWatchPointWrite,
	ZGWatchPointReadOrWrite,
};

NS_ASSUME_NONNULL_BEGIN

@interface ZGBreakPointController : NSObject

/**
 * Creates a singleton instance of the breakpoint controller
 *
 * @param scriptingInterpreter The scripting interpreter to use for evaluating breakpoint conditions
 * @return The singleton instance of the breakpoint controller
 */
+ (instancetype)createBreakPointControllerOnceWithScriptingInterpreter:(ZGScriptingInterpreter *)scriptingInterpreter;

/**
 * All active breakpoints managed by this controller
 */
@property (nonatomic, readonly) NSArray<ZGBreakPoint *> *breakPoints;

/**
 * Application termination state used to manage graceful shutdown with active breakpoints
 */
@property (nonatomic) ZGAppTerminationState *appTerminationState;

/**
 * Adds a conditional instruction breakpoint
 *
 * @param instruction The instruction to break on
 * @param process The process to add the breakpoint to
 * @param condition Python condition to evaluate when breakpoint is hit
 * @param delegate The delegate to notify when the breakpoint is hit
 * @return YES if the breakpoint was added successfully, NO otherwise
 */
- (BOOL)addBreakPointOnInstruction:(ZGInstruction *)instruction inProcess:(ZGProcess *)process condition:(PyObject * _Nullable)condition delegate:(id)delegate;

/**
 * Adds an instruction breakpoint with a callback
 *
 * @param instruction The instruction to break on
 * @param process The process to add the breakpoint to
 * @param callback Python callback to execute when breakpoint is hit
 * @param delegate The delegate to notify when the breakpoint is hit
 * @return YES if the breakpoint was added successfully, NO otherwise
 */
- (BOOL)addBreakPointOnInstruction:(ZGInstruction *)instruction inProcess:(ZGProcess *)process callback:(PyObject *)callback delegate:(id)delegate;

/**
 * Adds an instruction breakpoint with thread and base pointer context
 *
 * @param instruction The instruction to break on
 * @param process The process to add the breakpoint to
 * @param thread The thread to associate with the breakpoint
 * @param basePointer The base pointer value to associate with the breakpoint
 * @param callback Python callback to execute when breakpoint is hit
 * @param delegate The delegate to notify when the breakpoint is hit
 * @return YES if the breakpoint was added successfully, NO otherwise
 */
- (BOOL)addBreakPointOnInstruction:(ZGInstruction *)instruction inProcess:(ZGProcess *)process thread:(thread_act_t)thread basePointer:(ZGMemoryAddress)basePointer callback:(PyObject *)callback delegate:(id)delegate;

/**
 * Adds an instruction breakpoint with thread and base pointer context
 *
 * @param instruction The instruction to break on
 * @param process The process to add the breakpoint to
 * @param thread The thread to associate with the breakpoint
 * @param basePointer The base pointer value to associate with the breakpoint
 * @param delegate The delegate to notify when the breakpoint is hit
 * @return YES if the breakpoint was added successfully, NO otherwise
 */
- (BOOL)addBreakPointOnInstruction:(ZGInstruction *)instruction inProcess:(ZGProcess *)process thread:(thread_act_t)thread basePointer:(ZGMemoryAddress)basePointer delegate:(id)delegate;

/**
 * Adds an emulated instruction breakpoint
 *
 * @param instruction The instruction to break on
 * @param process The process to add the breakpoint to
 * @param emulated Whether the breakpoint should be emulated
 * @param delegate The delegate to notify when the breakpoint is hit
 * @return YES if the breakpoint was added successfully, NO otherwise
 */
- (BOOL)addBreakPointOnInstruction:(ZGInstruction *)instruction inProcess:(ZGProcess *)process emulated:(BOOL)emulated delegate:(id)delegate;

/**
 * Removes an instruction breakpoint
 *
 * @param instruction The instruction with the breakpoint
 * @param process The process containing the breakpoint
 * @return The removed breakpoint, or nil if no breakpoint was found
 */
- (ZGBreakPoint * _Nullable)removeBreakPointOnInstruction:(ZGInstruction *)instruction inProcess:(ZGProcess *)process;

/**
 * Resumes execution from a breakpoint
 *
 * @param breakPoint The breakpoint to resume from
 */
- (void)resumeFromBreakPoint:(ZGBreakPoint *)breakPoint;

/**
 * Adds a single-step breakpoint from an existing breakpoint
 *
 * @param breakPoint The breakpoint to single-step from
 * @return The newly created single-step breakpoint
 */
- (ZGBreakPoint *)addSingleStepBreakPointFromBreakPoint:(ZGBreakPoint *)breakPoint;

/**
 * Removes all single-step breakpoints associated with a breakpoint
 *
 * @param breakPoint The breakpoint whose single-step breakpoints should be removed
 * @return An array of the removed breakpoints
 */
- (NSArray<ZGBreakPoint *> *)removeSingleStepBreakPointsFromBreakPoint:(ZGBreakPoint *)breakPoint;

/**
 * Removes an instruction breakpoint
 *
 * @param breakPoint The breakpoint to remove
 */
- (void)removeInstructionBreakPoint:(ZGBreakPoint *)breakPoint;

/**
 * Adds a watchpoint on a variable
 *
 * @param variable The variable to watch
 * @param process The process containing the variable
 * @param watchPointType The type of memory access to watch for
 * @param delegate The delegate to notify when the watchpoint is triggered
 * @param returnedBreakPoint Pointer to store the created breakpoint
 * @return YES if the watchpoint was added successfully, NO otherwise
 */
- (BOOL)addWatchpointOnVariable:(ZGVariable *)variable inProcess:(ZGProcess *)process watchPointType:(ZGWatchPointType)watchPointType delegate:(id <ZGBreakPointDelegate>)delegate getBreakPoint:(ZGBreakPoint * _Nullable * _Nonnull)returnedBreakPoint;

/**
 * Adds a code injection handler
 *
 * @param codeInjectionHandler The code injection handler to add
 * @return YES if the handler was added successfully, NO otherwise
 */
- (BOOL)addCodeInjectionHandler:(ZGCodeInjectionHandler *)codeInjectionHandler;

/**
 * Gets the code injection handler for an instruction
 *
 * @param instruction The instruction to get the handler for
 * @param process The process containing the instruction
 * @return The code injection handler, or nil if none exists
 */
- (ZGCodeInjectionHandler * _Nullable)codeInjectionHandlerForInstruction:(ZGInstruction *)instruction process:(ZGProcess *)process;

/**
 * Gets the code injection handler for a memory address
 *
 * @param memoryAddress The memory address to get the handler for
 * @param process The process containing the memory address
 * @return The code injection handler, or nil if none exists
 */
- (ZGCodeInjectionHandler * _Nullable)codeInjectionHandlerForMemoryAddress:(ZGMemoryAddress)memoryAddress process:(ZGProcess *)process;

/**
 * Removes all breakpoints associated with an observer
 *
 * @param observer The observer to remove breakpoints for
 * @return An array of the removed breakpoints
 */
- (NSArray<ZGBreakPoint *> *)removeObserver:(id)observer;

/**
 * Removes all breakpoints associated with an observer in a specific process
 *
 * @param observer The observer to remove breakpoints for
 * @param process The process to remove breakpoints from
 * @return An array of the removed breakpoints
 */
- (NSArray<ZGBreakPoint *> *)removeObserver:(id)observer runningProcess:(ZGRunningProcess *)process;

/**
 * Removes all breakpoints associated with an observer at a specific address
 *
 * @param observer The observer to remove breakpoints for
 * @param processID The ID of the process to remove breakpoints from
 * @param address The address to remove breakpoints from
 * @return An array of the removed breakpoints
 */
- (NSArray<ZGBreakPoint *> *)removeObserver:(id)observer withProcessID:(pid_t)processID atAddress:(ZGMemoryAddress)address;

@end

NS_ASSUME_NONNULL_END
