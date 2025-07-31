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
 * ZGRegisterEntries - Register Collection Management
 * ================================================
 *
 * This module provides a way to extract and manage collections of CPU registers
 * from thread states, converting them to a format suitable for display and manipulation.
 *
 * Register Entry Structure:
 * -----------------------
 *
 *  +-------------------------------------+
 *  |          ZGRegisterEntry            |
 *  |-------------------------------------|
 *  | - name[16]  : Register name (rax)   |
 *  | - value[64] : Register value data   |
 *  | - size      : Size in bytes         |
 *  | - offset    : Offset in thread state|
 *  | - type      : GP or Vector          |
 *  +-------------------------------------+
 *
 * Register Extraction Flow:
 * -----------------------
 *
 *                                 +----------------+
 *                                 | Thread State   |
 *                                 | (Raw Registers)|
 *                                 +--------+-------+
 *                                          |
 *                                          | (Extract)
 *                                          v
 *  +----------------+            +-------------------+
 *  | Architecture   |----------->| getRegisterEntries|
 *  | Specific Logic |            | Methods           |
 *  +----------------+            +-------------------+
 *          |                              |
 *          | (Determine                   | (Fill array of)
 *          |  register set)               v
 *          v                     +-------------------+
 *  +----------------+            | ZGRegisterEntry[] |
 *  | x86/x64 Regs   |            | (Register Array)  |
 *  | or ARM64 Regs  |            +-------------------+
 *  +----------------+                     |
 *                                         | (Convert to)
 *                                         v
 *                                +-------------------+
 *                                | ZGVariable Array  |
 *                                | (For UI/Scripting)|
 *                                +-------------------+
 *                                         |
 *                                         | (Wrap in)
 *                                         v
 *                                +-------------------+
 *                                | ZGRegister Objects|
 *                                | (For UI Display)  |
 *                                +-------------------+
 *
 * Architecture-Specific Register Sets:
 * ----------------------------------
 *
 * x86 (32-bit):                  | x86_64 (64-bit):               | ARM64:
 * ------------------------------- | ------------------------------ | ------------------------------
 * General Purpose:               | General Purpose:                | General Purpose:
 * - eax, ebx, ecx, edx           | - rax, rbx, rcx, rdx           | - x0-x28: General registers
 * - esi, edi                     | - rsi, rdi                      | - x29: Frame pointer (FP)
 * - ebp: Base pointer            | - rbp: Base pointer             | - x30: Link register (LR)
 * - esp: Stack pointer           | - rsp: Stack pointer            | - sp: Stack pointer
 * - eip: Instruction pointer     | - rip: Instruction pointer      | - pc: Program counter
 * - eflags: Flags register       | - rflags: Flags register        | - cpsr: Status register
 *                                |                                 |
 * Vector/SIMD:                   | Vector/SIMD:                    | Vector/SIMD:
 * - xmm0-xmm7: SSE registers     | - xmm0-xmm15: SSE registers     | - v0-v31: NEON registers
 * - st0-st7: FPU registers       | - ymm0-ymm15: AVX registers     |   (128-bit)
 *                                | - st0-st7: FPU registers        |
 *
 * Memory Layout Examples:
 * ---------------------
 *
 * ZGRegisterEntry Memory Layout:
 * +-----------------------------------------------------------------------+
 * | Offset | Size | Field    | Description                                |
 * |--------|------|----------|-------------------------------------------|
 * | 0x00   | 16   | name     | Null-terminated register name string       |
 * | 0x10   | 64   | value    | Raw register value data                    |
 * | 0x50   | 8    | size     | Size of the register value in bytes        |
 * | 0x58   | 8    | offset   | Offset in the thread state structure       |
 * | 0x60   | 1    | type     | Register type (GP=0, Vector=1)             |
 * | 0x61   | 7    | padding  | Alignment padding                          |
 * +-----------------------------------------------------------------------+
 * Total size: 104 bytes (0x68)
 *
 * Example x86_64 Register Entries Array in Memory:
 * +-----------------------------------------------------------------------+
 * | Address      | Register | Value                | Size | Notes         |
 * |--------------|----------|----------------------|------|---------------|
 * | entries+0x000| rax      | 0x0000000000000001   | 8    | Return value  |
 * | entries+0x068| rbx      | 0x00007fff5fc01000   | 8    | Preserved     |
 * | entries+0x0D0| rcx      | 0x0000000000000000   | 8    | 4th argument  |
 * | entries+0x138| rdx      | 0x0000000000000000   | 8    | 3rd argument  |
 * | entries+0x1A0| rdi      | 0x00007fff5fc02000   | 8    | 1st argument  |
 * | entries+0x208| rsi      | 0x00007fff5fc03000   | 8    | 2nd argument  |
 * | entries+0x270| rbp      | 0x00007fff5fc04000   | 8    | Frame pointer |
 * | entries+0x2D8| rsp      | 0x00007fff5fc03f00   | 8    | Stack pointer |
 * | entries+0x340| rip      | 0x00007fff5fc05000   | 8    | Instr pointer |
 * | ...          | ...      | ...                  | ...  | ...           |
 * | entries+0x4D0| xmm0     | [16 bytes of data]   | 16   | Vector reg    |
 * | ...          | ...      | ...                  | ...  | ...           |
 * +-----------------------------------------------------------------------+
 *
 * Example ARM64 Register Entries Array in Memory:
 * +-----------------------------------------------------------------------+
 * | Address      | Register | Value                | Size | Notes         |
 * |--------------|----------|----------------------|------|---------------|
 * | entries+0x000| x0       | 0x0000000000000001   | 8    | Return value  |
 * | entries+0x068| x1       | 0x0000000016fe0000   | 8    | 1st argument  |
 * | entries+0x0D0| x2       | 0x0000000000000010   | 8    | 2nd argument  |
 * | entries+0x138| x3       | 0x0000000000000000   | 8    | 3rd argument  |
 * | ...          | ...      | ...                  | ...  | ...           |
 * | entries+0x7A0| x29      | 0x0000000016fe1000   | 8    | Frame pointer |
 * | entries+0x808| x30      | 0x0000000016fd0004   | 8    | Link register |
 * | entries+0x870| sp       | 0x0000000016fdff00   | 8    | Stack pointer |
 * | entries+0x8D8| pc       | 0x0000000016fd0000   | 8    | Program cntr  |
 * | entries+0x940| cpsr     | 0x0000000000000000   | 8    | Status reg    |
 * | ...          | ...      | ...                  | ...  | ...           |
 * | entries+0x9A8| v0       | [16 bytes of data]   | 16   | Vector reg    |
 * | ...          | ...      | ...                  | ...  | ...           |
 * +-----------------------------------------------------------------------+
 *
 * Example Register Value Memory Layout (x86_64 rax):
 * +-----------------------------------------------------------------------+
 * | Offset | Bytes                          | Description                 |
 * |--------|--------------------------------|-----------------------------|
 * | 0x00   | 01 00 00 00 00 00 00 00        | Value: 0x0000000000000001   |
 * | 0x08   | 00 00 00 00 00 00 00 00        | Padding/unused              |
 * | ...    | ...                            | ...                         |
 * +-----------------------------------------------------------------------+
 *
 * Example Register Value Memory Layout (ARM64 v0):
 * +-----------------------------------------------------------------------+
 * | Offset | Bytes                          | Description                 |
 * |--------|--------------------------------|-----------------------------|
 * | 0x00   | 00 01 02 03 04 05 06 07        | First 8 bytes               |
 * | 0x08   | 08 09 0A 0B 0C 0D 0E 0F        | Second 8 bytes              |
 * | 0x10   | 00 00 00 00 00 00 00 00        | Padding/unused              |
 * | ...    | ...                            | ...                         |
 * +-----------------------------------------------------------------------+
 */

#import <Foundation/Foundation.h>
#import "ZGRegister.h"
#import "ZGThreadStates.h"
#import "ZGProcessTypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZGRegisterEntries : NSObject

typedef struct
{
	char name[16];
	char value[64];
	size_t size;
	size_t offset;
	ZGRegisterType type;
} ZGRegisterEntry;

#define ZG_MAX_REGISTER_ENTRIES 128
#define ZG_REGISTER_ENTRY_IS_NULL(entry) ((entry)->name[0] == 0)

void *ZGRegisterEntryValue(ZGRegisterEntry *entry);

+ (int)getRegisterEntries:(ZGRegisterEntry *)entries fromGeneralPurposeThreadState:(zg_thread_state_t)threadState processType:(ZGProcessType)processType;
+ (int)getRegisterEntries:(ZGRegisterEntry *)entries fromVectorThreadState:(zg_vector_state_t)vectorState processType:(ZGProcessType)processType hasAVXSupport:(BOOL)hasAVXSupport;

+ (NSArray<ZGVariable *> *)registerVariablesFromVectorThreadState:(zg_vector_state_t)vectorState processType:(ZGProcessType)processType hasAVXSupport:(BOOL)hasAVXSupport;
+ (NSArray<ZGVariable *> *)registerVariablesFromGeneralPurposeThreadState:(zg_thread_state_t)threadState processType:(ZGProcessType)processType;

@end

NS_ASSUME_NONNULL_END
