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
 * ZGThreadStates.c - Implementation of Thread State Management
 * ===========================================================
 *
 * This file implements the functions declared in ZGThreadStates.h, providing
 * cross-platform thread state management for debugging purposes.
 *
 * Thread State Transition Flow:
 * ----------------------------
 *
 *                                 +----------------+
 *                                 | Normal Program |
 *                                 |   Execution    |
 *                                 +--------+-------+
 *                                          |
 *                                          | (Breakpoint Hit)
 *                                          v
 *  +----------------+            +-------------------+
 *  | ZGSetGeneral   |<-----------| ZGGetGeneral     |
 *  | ThreadState()  |            | ThreadState()    |
 *  +----------------+            +-------------------+
 *          |                              |
 *          |                              | (Access Registers)
 *          |                              v
 *          |                     +-------------------+
 *          |                     | ZGInstruction     |
 *          |                     | PointerFromGeneral|
 *          |                     | ThreadState()     |
 *          |                     +-------------------+
 *          |                              |
 *          |                              | (Modify Registers)
 *          |                              v
 *          |                     +-------------------+
 *          |                     | ZGSetInstruction  |
 *          |                     | PointerFromGeneral|
 *          |                     | ThreadState()     |
 *          |                     +-------------------+
 *          |                              |
 *          +------------------------------+
 *                                         |
 *                                         v
 *                                 +----------------+
 *                                 | Resume Program |
 *                                 |   Execution    |
 *                                 +----------------+
 *
 * Debug State Handling:
 * --------------------
 * For hardware breakpoints, the debug registers are managed through:
 * - ZGGetDebugThreadState()
 * - ZGSetDebugThreadState()
 *
 * Vector State Handling:
 * ---------------------
 * For SIMD operations, vector registers are managed through:
 * - ZGGetVectorThreadState()
 * - ZGSetVectorThreadState()
 */

#include "ZGThreadStates.h"

#if TARGET_CPU_ARM64
typedef arm_neon_state64_t zg_float_state_t;
#else
typedef x86_float_state_t zg_float_state_t;
#endif

/**
 * Retrieves the general purpose thread state for a given thread.
 *
 * This function uses the appropriate thread state flavor based on the architecture:
 * - ARM_THREAD_STATE64 for ARM64
 * - x86_THREAD_STATE for x86/x86_64
 *
 * Example:
 * -------
 * ```
 * zg_thread_state_t threadState;
 * mach_msg_type_number_t stateCount;
 * if (ZGGetGeneralThreadState(&threadState, thread, &stateCount)) {
 *     // Thread state retrieved successfully
 * }
 * ```
 *
 * @param threadState Pointer to store the thread state
 * @param thread The thread to get state from
 * @param stateCount Optional pointer to store the state count
 * @return true if successful, false otherwise
 */
bool ZGGetGeneralThreadState(zg_thread_state_t *threadState, thread_act_t thread, mach_msg_type_number_t *stateCount)
{
#if TARGET_CPU_ARM64
	mach_msg_type_number_t localStateCount = ARM_THREAD_STATE64_COUNT;
	thread_state_flavor_t flavor = ARM_THREAD_STATE64;
#else
	mach_msg_type_number_t localStateCount = x86_THREAD_STATE_COUNT;
	thread_state_flavor_t flavor = x86_THREAD_STATE;
#endif

	bool success = (thread_get_state(thread, flavor, (thread_state_t)threadState, &localStateCount) == KERN_SUCCESS);
	if (stateCount != NULL) *stateCount = localStateCount;
	return success;
}

/**
 * Sets the general purpose thread state for a given thread.
 *
 * This function uses the appropriate thread state flavor based on the architecture:
 * - ARM_THREAD_STATE64 for ARM64
 * - x86_THREAD_STATE for x86/x86_64
 *
 * Example:
 * -------
 * ```
 * // After modifying threadState
 * if (ZGSetGeneralThreadState(&threadState, thread, stateCount)) {
 *     // Thread state set successfully
 * }
 * ```
 *
 * @param threadState Pointer to the thread state to set
 * @param thread The thread to set state for
 * @param stateCount The state count
 * @return true if successful, false otherwise
 */
bool ZGSetGeneralThreadState(zg_thread_state_t *threadState, thread_act_t thread, mach_msg_type_number_t stateCount)
{
#if TARGET_CPU_ARM64
	thread_state_flavor_t flavor = ARM_THREAD_STATE64;
#else
	thread_state_flavor_t flavor = x86_THREAD_STATE;
#endif

	return (thread_set_state(thread, flavor, (thread_state_t)threadState, stateCount) == KERN_SUCCESS);
}

/**
 * Gets the instruction pointer value from a thread state.
 *
 * This function extracts the program counter/instruction pointer from the thread state:
 * - pc register for ARM64
 * - rip register for x86_64
 * - eip register for x86
 *
 * Example:
 * -------
 * ```
 * ZGMemoryAddress currentAddress = ZGInstructionPointerFromGeneralThreadState(&threadState, processType);
 * ```
 *
 * @param threadState Pointer to the thread state
 * @param type The process type (32-bit or 64-bit)
 * @return The instruction pointer address
 */
ZGMemoryAddress ZGInstructionPointerFromGeneralThreadState(zg_thread_state_t *threadState, ZGProcessType type)
{
#if TARGET_CPU_ARM64
	(void)type;
	ZGMemoryAddress instructionPointer = arm_thread_state64_get_pc(*threadState);
#else
	ZGMemoryAddress instructionPointer = (ZG_PROCESS_TYPE_IS_X86_64(type)) ? threadState->uts.ts64.__rip : threadState->uts.ts32.__eip;
#endif
	return instructionPointer;
}

/**
 * Sets the instruction pointer value in a thread state.
 *
 * This function modifies the program counter/instruction pointer in the thread state:
 * - pc register for ARM64
 * - rip register for x86_64
 * - eip register for x86
 *
 * Example:
 * -------
 * ```
 * // Skip the current instruction
 * ZGMemoryAddress currentAddress = ZGInstructionPointerFromGeneralThreadState(&threadState, processType);
 * ZGSetInstructionPointerFromGeneralThreadState(&threadState, currentAddress + instructionSize, processType);
 * ```
 *
 * @param threadState Pointer to the thread state
 * @param instructionAddress The new instruction pointer address
 * @param type The process type (32-bit or 64-bit)
 */
void ZGSetInstructionPointerFromGeneralThreadState(zg_thread_state_t *threadState, ZGMemoryAddress instructionAddress, ZGProcessType type)
{
#if TARGET_CPU_ARM64
	(void)type;
	arm_thread_state64_set_pc_fptr(*threadState, instructionAddress);
#else
	if (ZG_PROCESS_TYPE_IS_X86_64(type))
	{
		threadState->uts.ts64.__rip = instructionAddress;
	}
	else
	{
		threadState->uts.ts32.__eip = (uint32_t)instructionAddress;
	}
#endif
}

/**
 * Gets the base pointer value from a thread state.
 *
 * The base pointer (frame pointer) is used for stack frame traversal and backtrace generation.
 * This function extracts:
 * - fp register for ARM64
 * - rbp register for x86_64
 * - ebp register for x86
 *
 * Example:
 * -------
 * ```
 * // Get base pointer for backtrace
 * ZGMemoryAddress basePointer = ZGBasePointerFromGeneralThreadState(&threadState, processType);
 * ```
 *
 * @param threadState Pointer to the thread state
 * @param type The process type (32-bit or 64-bit)
 * @return The base pointer address
 */
ZGMemoryAddress ZGBasePointerFromGeneralThreadState(zg_thread_state_t *threadState, ZGProcessType type)
{
#if TARGET_CPU_ARM64
	(void)type;
	ZGMemoryAddress framePointer = arm_thread_state64_get_fp(*threadState);
	return framePointer;
#else
	ZGMemoryAddress basePointer = (ZG_PROCESS_TYPE_IS_X86_64(type)) ? threadState->uts.ts64.__rbp : threadState->uts.ts32.__ebp;
	return basePointer;
#endif
}

/**
 * Retrieves the debug thread state for a given thread.
 *
 * The debug state contains hardware breakpoint registers:
 * - ARM_DEBUG_STATE64 for ARM64
 * - x86_DEBUG_STATE for x86/x86_64
 *
 * Example:
 * -------
 * ```
 * zg_debug_state_t debugState;
 * mach_msg_type_number_t debugStateCount;
 * if (ZGGetDebugThreadState(&debugState, thread, &debugStateCount)) {
 *     // Debug state retrieved successfully
 * }
 * ```
 *
 * @param debugState Pointer to store the debug state
 * @param thread The thread to get debug state from
 * @param stateCount Optional pointer to store the state count
 * @return true if successful, false otherwise
 */
bool ZGGetDebugThreadState(zg_debug_state_t *debugState, thread_act_t thread, mach_msg_type_number_t *stateCount)
{
#if TARGET_CPU_ARM64
	thread_state_flavor_t flavor = ARM_DEBUG_STATE64;
	mach_msg_type_number_t localStateCount = ARM_DEBUG_STATE64_COUNT;
#else
	thread_state_flavor_t flavor = x86_DEBUG_STATE;
	mach_msg_type_number_t localStateCount = x86_DEBUG_STATE_COUNT;
#endif

	bool success = (thread_get_state(thread, flavor, (thread_state_t)debugState, &localStateCount) == KERN_SUCCESS);
	if (stateCount != NULL) *stateCount = localStateCount;
	return success;
}

/**
 * Sets the debug thread state for a given thread.
 *
 * This function is used to configure hardware breakpoints by setting debug registers:
 * - ARM_DEBUG_STATE64 for ARM64
 * - x86_DEBUG_STATE for x86/x86_64
 *
 * Example:
 * -------
 * ```
 * // After configuring debug registers in debugState
 * if (ZGSetDebugThreadState(&debugState, thread, debugStateCount)) {
 *     // Debug state set successfully
 * }
 * ```
 *
 * @param debugState Pointer to the debug state to set
 * @param thread The thread to set debug state for
 * @param stateCount The state count
 * @return true if successful, false otherwise
 */
bool ZGSetDebugThreadState(zg_debug_state_t *debugState, thread_act_t thread, mach_msg_type_number_t stateCount)
{
#if TARGET_CPU_ARM64
	thread_state_flavor_t flavor = ARM_DEBUG_STATE64;
#else
	thread_state_flavor_t flavor = x86_DEBUG_STATE;
#endif

	return (thread_set_state(thread, flavor, (thread_state_t)debugState, stateCount) == KERN_SUCCESS);
}

#if TARGET_CPU_ARM64
#else
// For some reason for AVX set/get thread functions, it is important to distinguish between 32 vs 64 bit,
// even when I can use more generic versions for general purpose and debug registers

static bool ZGGetAVXThreadState(zg_vector_state_t * avxState, thread_act_t thread, mach_msg_type_number_t *stateCount, ZGProcessType type)
{
	bool isX86_64 = ZG_PROCESS_TYPE_IS_X86_64(type);
	mach_msg_type_number_t localStateCount = isX86_64 ? x86_AVX_STATE64_COUNT : x86_AVX_STATE32_COUNT;
	bool success = (thread_get_state(thread, isX86_64 ? x86_AVX_STATE64 : x86_AVX_STATE32, isX86_64 ? (thread_state_t)&(avxState->ufs.as64) : (thread_state_t)&(avxState->ufs.as32), &localStateCount) == KERN_SUCCESS);

	if (stateCount != NULL) *stateCount = localStateCount;

	return success;
}

static bool ZGSetAVXThreadState(zg_vector_state_t *avxState, thread_act_t thread, mach_msg_type_number_t stateCount, ZGProcessType type)
{
	bool isX86_64 = ZG_PROCESS_TYPE_IS_X86_64(type);
	return (thread_set_state(thread, isX86_64 ? x86_AVX_STATE64 : x86_AVX_STATE32, isX86_64 ? (thread_state_t)&(avxState->ufs.as64) : (thread_state_t)&(avxState->ufs.as32), stateCount) == KERN_SUCCESS);
}

// I will assume I have to provide 64-bit flag for same reasons I have to for AVX (see above)

static bool ZGGetFloatThreadState(zg_float_state_t *floatState, thread_act_t thread, mach_msg_type_number_t *stateCount, ZGProcessType type)
{
	bool isX86_64 = ZG_PROCESS_TYPE_IS_X86_64(type);
	mach_msg_type_number_t localStateCount = isX86_64 ? x86_FLOAT_STATE64_COUNT : x86_FLOAT_STATE32_COUNT;
	bool success = (thread_get_state(thread, isX86_64 ? x86_FLOAT_STATE64 : x86_FLOAT_STATE32, isX86_64 ? (thread_state_t)&(floatState->ufs.fs64) : (thread_state_t)&(floatState->ufs.fs32), &localStateCount) == KERN_SUCCESS);

	if (stateCount != NULL) *stateCount = localStateCount;

	return success;
}

static bool ZGSetFloatThreadState(zg_float_state_t *floatState, thread_act_t thread, mach_msg_type_number_t stateCount, ZGProcessType type)
{
	bool isX86_64 = ZG_PROCESS_TYPE_IS_X86_64(type);
	return (thread_set_state(thread, isX86_64 ? x86_FLOAT_STATE64 : x86_FLOAT_STATE32, isX86_64 ? (thread_state_t)&floatState->ufs.fs64 : (thread_state_t)&floatState->ufs.fs32, stateCount) == KERN_SUCCESS);
}

#endif

/**
 * Retrieves the vector thread state for a given thread.
 *
 * This function handles SIMD/vector registers:
 * - ARM_NEON_STATE64 for ARM64 (NEON registers)
 * - x86_AVX_STATE for x86/x86_64 (AVX registers if supported)
 * - Falls back to x86_FLOAT_STATE for x86/x86_64 if AVX is not supported
 *
 * Example:
 * -------
 * ```
 * zg_vector_state_t vectorState;
 * bool hasAVXSupport = false;
 * if (ZGGetVectorThreadState(&vectorState, thread, NULL, processType, &hasAVXSupport)) {
 *     // Vector state retrieved successfully
 *     // hasAVXSupport indicates whether AVX registers are available
 * }
 * ```
 *
 * @param vectorState Pointer to store the vector state
 * @param thread The thread to get vector state from
 * @param stateCount Optional pointer to store the state count
 * @param type The process type (32-bit or 64-bit)
 * @param hasAVXSupport Optional pointer to store whether AVX is supported
 * @return true if successful, false otherwise
 */
bool ZGGetVectorThreadState(zg_vector_state_t *vectorState, thread_act_t thread, mach_msg_type_number_t *stateCount, ZGProcessType type, bool *hasAVXSupport)
{
#if TARGET_CPU_ARM64
	(void)type;

	mach_msg_type_number_t localStateCount = ARM_NEON_STATE64_COUNT;
	bool success = (thread_get_state(thread, ARM_NEON_STATE64, (thread_state_t)vectorState, &localStateCount) == KERN_SUCCESS);

	if (hasAVXSupport != NULL) *hasAVXSupport = false;
	if (stateCount != NULL) *stateCount = localStateCount;

	return success;
#else
	if (ZGGetAVXThreadState((zg_vector_state_t *)vectorState, thread, stateCount, type))
	{
		if (hasAVXSupport != NULL) *hasAVXSupport = true;
		return true;
	}

	if (hasAVXSupport != NULL) *hasAVXSupport = false;

	return ZGGetFloatThreadState((zg_float_state_t *)vectorState, thread, stateCount, type);
#endif
}

/**
 * Sets the vector thread state for a given thread.
 *
 * This function handles SIMD/vector registers:
 * - ARM_NEON_STATE64 for ARM64 (NEON registers)
 * - x86_AVX_STATE for x86/x86_64 (AVX registers if supported)
 * - Falls back to x86_FLOAT_STATE for x86/x86_64 if AVX is not supported
 *
 * Example:
 * -------
 * ```
 * // After modifying vector registers in vectorState
 * if (ZGSetVectorThreadState(&vectorState, thread, stateCount, processType)) {
 *     // Vector state set successfully
 * }
 * ```
 *
 * @param vectorState Pointer to the vector state to set
 * @param thread The thread to set vector state for
 * @param stateCount The state count
 * @param type The process type (32-bit or 64-bit)
 * @return true if successful, false otherwise
 */
bool ZGSetVectorThreadState(zg_vector_state_t *vectorState, thread_act_t thread, mach_msg_type_number_t stateCount, ZGProcessType type)
{
#if TARGET_CPU_ARM64
	(void)type;

	return (thread_set_state(thread, ARM_NEON_STATE64, (thread_state_t)vectorState, stateCount) == KERN_SUCCESS);
#else
	if (ZGSetAVXThreadState((zg_vector_state_t *)vectorState, thread, stateCount, type))
	{
		return true;
	}

	return ZGSetFloatThreadState((zg_float_state_t *)vectorState, thread, stateCount, type);
#endif
}
