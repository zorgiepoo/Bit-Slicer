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
 *
 * Memory Layout Examples:
 * ---------------------
 *
 * x86_64 Thread State Memory Layout:
 * --------------------------------
 *
 * General Purpose Thread State (x86_64):
 * +-----------------------------------------------------------------------+
 * | Offset | Size | Register | Description                                |
 * |--------|------|----------|-------------------------------------------|
 * | 0x00   | 8    | rax      | Accumulator                               |
 * | 0x08   | 8    | rbx      | Base                                      |
 * | 0x10   | 8    | rcx      | Counter                                   |
 * | 0x18   | 8    | rdx      | Data                                      |
 * | 0x20   | 8    | rdi      | Destination Index                         |
 * | 0x28   | 8    | rsi      | Source Index                              |
 * | 0x30   | 8    | rbp      | Base Pointer (frame pointer)              |
 * | 0x38   | 8    | rsp      | Stack Pointer                             |
 * | 0x40   | 8    | r8       | General Purpose                           |
 * | 0x48   | 8    | r9       | General Purpose                           |
 * | 0x50   | 8    | r10      | General Purpose                           |
 * | 0x58   | 8    | r11      | General Purpose                           |
 * | 0x60   | 8    | r12      | General Purpose                           |
 * | 0x68   | 8    | r13      | General Purpose                           |
 * | 0x70   | 8    | r14      | General Purpose                           |
 * | 0x78   | 8    | r15      | General Purpose                           |
 * | 0x80   | 8    | rip      | Instruction Pointer                       |
 * | 0x88   | 8    | rflags   | Flags                                     |
 * | 0x90   | 8    | cs       | Code Segment                              |
 * | 0x98   | 8    | fs       | FS Segment                                |
 * | 0xA0   | 8    | gs       | GS Segment                                |
 * +-----------------------------------------------------------------------+
 *
 * Debug Thread State (x86_64):
 * +-----------------------------------------------------------------------+
 * | Offset | Size | Register | Description                                |
 * |--------|------|----------|-------------------------------------------|
 * | 0x00   | 8    | dr0      | Debug Register 0 (breakpoint address)      |
 * | 0x08   | 8    | dr1      | Debug Register 1 (breakpoint address)      |
 * | 0x10   | 8    | dr2      | Debug Register 2 (breakpoint address)      |
 * | 0x18   | 8    | dr3      | Debug Register 3 (breakpoint address)      |
 * | 0x20   | 8    | dr4      | Debug Register 4 (reserved)                |
 * | 0x28   | 8    | dr5      | Debug Register 5 (reserved)                |
 * | 0x30   | 8    | dr6      | Debug Register 6 (debug status)            |
 * | 0x38   | 8    | dr7      | Debug Register 7 (debug control)           |
 * +-----------------------------------------------------------------------+
 *
 * Example x86_64 Memory Snapshot (General Purpose Registers):
 * +-----------------------------------------------------------------------+
 * | Address      | Value                | Register | Notes                |
 * |--------------|----------------------|----------|----------------------|
 * | 0x7fff5fc00000 | 0x0000000000000001 | rax      | Return value        |
 * | 0x7fff5fc00008 | 0x00007fff5fc01000 | rbx      | Preserved register  |
 * | 0x7fff5fc00010 | 0x0000000000000000 | rcx      | 4th argument        |
 * | 0x7fff5fc00018 | 0x0000000000000000 | rdx      | 3rd argument        |
 * | 0x7fff5fc00020 | 0x00007fff5fc02000 | rdi      | 1st argument        |
 * | 0x7fff5fc00028 | 0x00007fff5fc03000 | rsi      | 2nd argument        |
 * | 0x7fff5fc00030 | 0x00007fff5fc04000 | rbp      | Frame pointer       |
 * | 0x7fff5fc00038 | 0x00007fff5fc03f00 | rsp      | Stack pointer       |
 * | ...           | ...                | ...      | ...                 |
 * | 0x7fff5fc00080 | 0x00007fff5fc05000 | rip      | Next instruction    |
 * +-----------------------------------------------------------------------+
 *
 * ARM64 Thread State Memory Layout:
 * ------------------------------
 *
 * General Purpose Thread State (ARM64):
 * +-----------------------------------------------------------------------+
 * | Offset | Size | Register | Description                                |
 * |--------|------|----------|-------------------------------------------|
 * | 0x00   | 8    | x0       | Function argument/return value             |
 * | 0x08   | 8    | x1       | Function argument                          |
 * | 0x10   | 8    | x2       | Function argument                          |
 * | 0x18   | 8    | x3       | Function argument                          |
 * | 0x20   | 8    | x4       | Function argument                          |
 * | 0x28   | 8    | x5       | Function argument                          |
 * | 0x30   | 8    | x6       | Function argument                          |
 * | 0x38   | 8    | x7       | Function argument                          |
 * | 0x40   | 8    | x8       | Indirect result location                   |
 * | 0x48   | 8    | x9-x15   | Temporary registers                        |
 * | 0x80   | 8    | x16-x17  | Intra-procedure-call scratch registers     |
 * | 0x90   | 8    | x18      | Platform register (reserved)               |
 * | 0x98   | 8    | x19-x28  | Callee-saved registers                     |
 * | 0xE8   | 8    | x29 (fp) | Frame pointer                              |
 * | 0xF0   | 8    | x30 (lr) | Link register (return address)             |
 * | 0xF8   | 8    | sp       | Stack pointer                              |
 * | 0x100  | 8    | pc       | Program counter                            |
 * | 0x108  | 8    | cpsr     | Current program status register            |
 * | 0x110  | 8    | pad      | Padding                                    |
 * +-----------------------------------------------------------------------+
 *
 * Debug Thread State (ARM64):
 * +-----------------------------------------------------------------------+
 * | Offset | Size | Register | Description                                |
 * |--------|------|----------|-------------------------------------------|
 * | 0x00   | 8    | bcr[0]   | Breakpoint Control Register 0              |
 * | 0x08   | 8    | bvr[0]   | Breakpoint Value Register 0                |
 * | ...    | ...  | ...      | ...                                        |
 * | 0x78   | 8    | bcr[15]  | Breakpoint Control Register 15             |
 * | 0x80   | 8    | bvr[15]  | Breakpoint Value Register 15               |
 * | 0x88   | 8    | wcr[0]   | Watchpoint Control Register 0              |
 * | 0x90   | 8    | wvr[0]   | Watchpoint Value Register 0                |
 * | ...    | ...  | ...      | ...                                        |
 * | 0xC8   | 8    | wcr[15]  | Watchpoint Control Register 15             |
 * | 0xD0   | 8    | wvr[15]  | Watchpoint Value Register 15               |
 * | 0xD8   | 8    | mdscr_el1| Debug Status and Control Register          |
 * +-----------------------------------------------------------------------+
 *
 * Example ARM64 Memory Snapshot (General Purpose Registers):
 * +-----------------------------------------------------------------------+
 * | Address      | Value                | Register | Notes                |
 * |--------------|----------------------|----------|----------------------|
 * | 0x16fdff000  | 0x0000000000000001  | x0       | Return value         |
 * | 0x16fdff008  | 0x0000000016fe0000  | x1       | Function argument    |
 * | 0x16fdff010  | 0x0000000000000010  | x2       | Function argument    |
 * | 0x16fdff018  | 0x0000000000000000  | x3       | Function argument    |
 * | ...          | ...                 | ...      | ...                  |
 * | 0x16fdff0e8  | 0x0000000016fe1000  | x29 (fp) | Frame pointer        |
 * | 0x16fdff0f0  | 0x0000000016fd0004  | x30 (lr) | Return address       |
 * | 0x16fdff0f8  | 0x0000000016fdff00  | sp       | Stack pointer        |
 * | 0x16fdff100  | 0x0000000016fd0000  | pc       | Current instruction  |
 * | 0x16fdff108  | 0x0000000000000000  | cpsr     | Status register      |
 * +-----------------------------------------------------------------------+
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
