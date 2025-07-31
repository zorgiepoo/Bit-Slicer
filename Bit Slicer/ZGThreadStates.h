/*
 * Copyright (c) 2014 Mayur Pawashe
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
 * ZGThreadStates - Thread State Management for Debugging
 * ======================================================
 *
 * This module provides a cross-platform abstraction for managing thread states
 * in a debugger. It handles both ARM64 and x86 architectures, providing a unified
 * interface for:
 *
 * 1. General purpose registers (instruction pointer, base pointer, etc.)
 * 2. Debug registers (hardware breakpoints)
 * 3. Vector/SIMD registers (AVX, NEON)
 *
 * Thread State Flow:
 * -----------------
 *
 * Normal Execution → Breakpoint Hit → Get Thread State → Modify Thread State → Resume Execution
 *       |                                                                            |
 *       |                                                                            |
 *       +----------------------------------------------------------------------------+
 *
 * When a breakpoint is hit:
 *   1. ZGGetGeneralThreadState() retrieves the current register values
 *   2. ZGInstructionPointerFromGeneralThreadState() gets the current instruction pointer
 *   3. The debugger may modify register values
 *   4. ZGSetGeneralThreadState() applies the modified register values
 *   5. Execution resumes with the new thread state
 *
 * Example Usage:
 * -------------
 *
 * // Get thread state when breakpoint is hit
 * zg_thread_state_t threadState;
 * mach_msg_type_number_t stateCount;
 * if (ZGGetGeneralThreadState(&threadState, thread, &stateCount)) {
 *     // Get instruction pointer
 *     ZGMemoryAddress instructionAddress = ZGInstructionPointerFromGeneralThreadState(&threadState, processType);
 *     
 *     // Modify instruction pointer (e.g., to skip an instruction)
 *     ZGSetInstructionPointerFromGeneralThreadState(&threadState, instructionAddress + instructionSize, processType);
 *     
 *     // Apply modified thread state
 *     ZGSetGeneralThreadState(&threadState, thread, stateCount);
 * }
 */

#ifndef Bit_Slicer_ZGThreadStates_h
#define Bit_Slicer_ZGThreadStates_h

#include "ZGMemoryTypes.h"
#include "ZGProcessTypes.h"

#include <machine/_mcontext.h> // this header is needed when modules are enabled
#include <mach/message.h>
#include <mach/thread_act.h>
#include <stdbool.h>
#include <TargetConditionals.h>

#if TARGET_CPU_ARM64
typedef arm_neon_state64_t zg_vector_state_t;
typedef arm_thread_state64_t zg_thread_state_t;
typedef arm_debug_state64_t zg_debug_state_t;
typedef arm_state_hdr_t zg_state_hdr_t;
typedef arm_thread_state32_t zg_thread_state32_t;
typedef arm_thread_state64_t zg_thread_state64_t;
#else
typedef x86_avx_state_t zg_vector_state_t;
typedef x86_thread_state_t zg_thread_state_t;
typedef x86_debug_state_t zg_debug_state_t;
typedef x86_state_hdr_t zg_state_hdr_t;
typedef x86_thread_state32_t zg_thread_state32_t;
typedef x86_thread_state64_t zg_thread_state64_t;
#endif

/*
 * General Purpose Thread State Functions
 * -------------------------------------
 * These functions handle the CPU's general purpose registers (like rip/eip, rbp/ebp, etc.)
 */

/**
 * Retrieves the general purpose thread state for a given thread.
 *
 * @param threadState Pointer to store the thread state
 * @param thread The thread to get state from
 * @param stateCount Optional pointer to store the state count
 * @return true if successful, false otherwise
 */
bool ZGGetGeneralThreadState(zg_thread_state_t *threadState, thread_act_t thread, mach_msg_type_number_t *stateCount);

/**
 * Sets the general purpose thread state for a given thread.
 *
 * @param threadState Pointer to the thread state to set
 * @param thread The thread to set state for
 * @param stateCount The state count
 * @return true if successful, false otherwise
 */
bool ZGSetGeneralThreadState(zg_thread_state_t *threadState, thread_act_t thread, mach_msg_type_number_t stateCount);

/**
 * Gets the instruction pointer value from a thread state.
 *
 * @param threadState Pointer to the thread state
 * @param type The process type (32-bit or 64-bit)
 * @return The instruction pointer address
 */
ZGMemoryAddress ZGInstructionPointerFromGeneralThreadState(zg_thread_state_t *threadState, ZGProcessType type);

/**
 * Sets the instruction pointer value in a thread state.
 *
 * @param threadState Pointer to the thread state
 * @param instructionAddress The new instruction pointer address
 * @param type The process type (32-bit or 64-bit)
 */
void ZGSetInstructionPointerFromGeneralThreadState(zg_thread_state_t *threadState, ZGMemoryAddress instructionAddress, ZGProcessType type);

/**
 * Gets the base pointer value from a thread state.
 * The base pointer is used for stack frame traversal.
 *
 * @param threadState Pointer to the thread state
 * @param type The process type (32-bit or 64-bit)
 * @return The base pointer address
 */
ZGMemoryAddress ZGBasePointerFromGeneralThreadState(zg_thread_state_t *threadState, ZGProcessType type);

/**
 * Gets the stack pointer value from a thread state.
 * The stack pointer indicates the current top of the stack.
 *
 * @param threadState Pointer to the thread state
 * @param type The process type (32-bit or 64-bit)
 * @return The stack pointer address
 */
ZGMemoryAddress ZGStackPointerFromGeneralThreadState(zg_thread_state_t *threadState, ZGProcessType type);

/*
 * Debug Thread State Functions
 * ---------------------------
 * These functions handle the CPU's debug registers (used for hardware breakpoints)
 */

/**
 * Retrieves the debug thread state for a given thread.
 *
 * @param debugState Pointer to store the debug state
 * @param thread The thread to get debug state from
 * @param stateCount Optional pointer to store the state count
 * @return true if successful, false otherwise
 */
bool ZGGetDebugThreadState(zg_debug_state_t *debugState, thread_act_t thread, mach_msg_type_number_t *stateCount);

/**
 * Sets the debug thread state for a given thread.
 *
 * @param debugState Pointer to the debug state to set
 * @param thread The thread to set debug state for
 * @param stateCount The state count
 * @return true if successful, false otherwise
 */
bool ZGSetDebugThreadState(zg_debug_state_t *debugState, thread_act_t thread, mach_msg_type_number_t stateCount);

/*
 * Vector Thread State Functions
 * ----------------------------
 * These functions handle the CPU's vector/SIMD registers (AVX, NEON)
 */

/**
 * Retrieves the vector thread state for a given thread.
 * On x86, tries AVX first, then falls back to FPU state if AVX is not supported.
 * On ARM64, retrieves NEON state.
 *
 * @param vectorState Pointer to store the vector state
 * @param thread The thread to get vector state from
 * @param stateCount Optional pointer to store the state count
 * @param type The process type (32-bit or 64-bit)
 * @param hasAVXSupport Optional pointer to store whether AVX is supported
 * @return true if successful, false otherwise
 */
bool ZGGetVectorThreadState(zg_vector_state_t *vectorState, thread_act_t thread, mach_msg_type_number_t *stateCount, ZGProcessType type, bool *hasAVXSupport);

/**
 * Sets the vector thread state for a given thread.
 * On x86, tries AVX first, then falls back to FPU state if AVX is not supported.
 * On ARM64, sets NEON state.
 *
 * @param vectorState Pointer to the vector state to set
 * @param thread The thread to set vector state for
 * @param stateCount The state count
 * @param type The process type (32-bit or 64-bit)
 * @return true if successful, false otherwise
 */
bool ZGSetVectorThreadState(zg_vector_state_t *vectorState, thread_act_t thread, mach_msg_type_number_t stateCount, ZGProcessType type);

#endif
