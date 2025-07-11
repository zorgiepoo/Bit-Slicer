/*
 * Copyright (c) 2020 Mayur Pawashe
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
 *
 * ZGARM64DisassemblerObject
 * -------------------------
 * This class provides ARM64 architecture-specific disassembly functionality.
 * It implements the ZGDisassemblerObject protocol and uses the Capstone
 * disassembly engine to convert ARM64 machine code into human-readable
 * assembly instructions.
 *
 * ARM64 (AArch64) is the 64-bit extension of the ARM architecture, used in
 * modern Apple devices (iPhones, iPads, and Apple Silicon Macs).
 *
 * Disassembly Process:
 * +----------------+     +----------------+     +----------------+
 * |  Machine Code  |     |   Capstone     |     |  Instruction   |
 * |  (Raw Bytes)   | --> |  Disassembly   | --> |  Objects       |
 * |                |     |  Engine        |     |                |
 * +----------------+     +----------------+     +----------------+
 *
 * Key responsibilities:
 * - Initializing the Capstone engine for ARM64 disassembly
 * - Converting raw machine code bytes to instruction objects
 * - Identifying branch and call instructions
 * - Extracting branch targets from instructions
 */

#import <Foundation/Foundation.h>
#import "ZGDisassemblerObjectProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZGARM64DisassemblerObject : NSObject <ZGDisassemblerObject>
// This class implements all methods of the ZGDisassemblerObject protocol, including:
// - readInstructions
// - readBranchOperand
// - readLastInstructionWithMaxSize:

/**
 * Initializes an ARM64 disassembler object with the specified machine code bytes.
 *
 * This initializer sets up the Capstone disassembly engine for ARM64 architecture
 * and prepares the object to disassemble the provided bytes.
 *
 * @param bytes Pointer to the machine code bytes to disassemble
 * @param address The memory address where the code is located
 * @param size The size of the code in bytes
 * @return An initialized disassembler object, or nil if initialization fails
 */
- (instancetype)initWithBytes:(const void *)bytes address:(ZGMemoryAddress)address size:(ZGMemorySize)size;

/**
 * Determines if the given mnemonic represents a call instruction in ARM64.
 *
 * In ARM64, the BL (Branch with Link) instruction is used for function calls.
 * It stores the return address in the link register (LR/X30).
 *
 * @param mnemonic The instruction mnemonic ID from Capstone
 * @return YES if the mnemonic is a call instruction, NO otherwise
 */
+ (BOOL)isCallMnemonic:(int64_t)mnemonic;

/**
 * Determines if the given mnemonic represents a jump instruction in ARM64.
 *
 * ARM64 has several branch instructions:
 * - B: Unconditional branch
 * - CBZ/CBNZ: Compare and branch if zero/not zero
 * - TBZ/TBNZ: Test bit and branch if zero/not zero
 *
 * @param mnemonic The instruction mnemonic ID from Capstone
 * @return YES if the mnemonic is a jump instruction, NO otherwise
 */
+ (BOOL)isJumpMnemonic:(int64_t)mnemonic;

@end

NS_ASSUME_NONNULL_END
