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
 * ZGARM64DisassemblerObject Implementation
 * ----------------------------------------
 * This file implements the ARM64 disassembler using the Capstone engine.
 * 
 * ARM64 Instruction Format:
 * +--------+--------+--------+--------+
 * |31    24|23    16|15     8|7      0|  Byte offsets
 * +--------+--------+--------+--------+
 * |  Op1   |  Op2   |  Op3   |  Op4   |  4-byte (32-bit) instruction
 * +--------+--------+--------+--------+
 *
 * ARM64 instructions are always 4 bytes (32 bits) in size, which makes
 * disassembly more straightforward compared to variable-length instruction
 * sets like x86. However, the instruction encoding is complex with many
 * different formats depending on the instruction type.
 *
 * Disassembly Process Flow:
 * 
 * 1. Initialize Capstone engine for ARM64
 *    cs_open(CS_ARCH_ARM64, CS_MODE_ARM, &_object)
 *    
 * 2. Copy and store machine code bytes
 *    _bytes = malloc(size)
 *    memcpy(_bytes, bytes, size)
 *    
 * 3. Disassemble instructions
 *    cs_disasm(_object, _bytes, _size, _startAddress, 0, &disassembledInstructions)
 *    
 * 4. Convert to ZGInstruction objects
 *    For each disassembled instruction:
 *      - Extract address, size, mnemonic ID
 *      - Create ZGVariable to hold instruction bytes
 *      - Create ZGInstruction with variable, text, and mnemonic
 *      
 * 5. Clean up Capstone resources
 *    cs_free(disassembledInstructions, numberOfInstructionsDisassembled)
 */

#import "ZGARM64DisassemblerObject.h"
#import "ZGVariable.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation-unknown-command"
#pragma clang diagnostic ignored "-Wduplicate-enum"
#pragma clang diagnostic ignored "-Wshift-sign-overflow"
#pragma clang diagnostic ignored "-Wnon-modular-include-in-module"
#pragma clang diagnostic ignored "-Wobjc-messaging-id"
#pragma clang diagnostic ignored "-Woverriding-method-mismatch"
#import <Capstone/capstone.h>
#pragma clang diagnostic pop

@implementation ZGARM64DisassemblerObject
{
	/**
	 * Buffer containing a copy of the machine code bytes to disassemble.
	 * This is allocated in initWithBytes:address:size: and freed in dealloc.
	 */
	void * _Nonnull _bytes;

	/**
	 * The memory address where the code starts in the target process.
	 * Used to calculate the absolute address of each instruction.
	 */
	ZGMemoryAddress _startAddress;

	/**
	 * The size of the code buffer in bytes.
	 * Defines how much memory to disassemble.
	 */
	ZGMemorySize _size;

	/**
	 * Capstone engine handle.
	 * This is initialized in initWithBytes:address:size: and closed in dealloc.
	 */
	csh _object;
}

@synthesize bytes = _bytes;

/**
 * Initializes the disassembler with machine code bytes and prepares the Capstone engine.
 *
 * Memory Layout After Initialization:
 * +-----------------+
 * | Original Bytes  |  (Input parameter 'bytes')
 * +-----------------+
 *         |
 *         | memcpy()
 *         v
 * +-----------------+
 * | Copied Bytes    |  (Instance variable '_bytes')
 * | (_size bytes)   |
 * +-----------------+
 *         |
 *         | Used by Capstone
 *         v
 * +-----------------+
 * | Disassembled    |
 * | Instructions    |
 * +-----------------+
 *
 * @param bytes Pointer to the machine code bytes to disassemble
 * @param address The memory address where the code is located
 * @param size The size of the code in bytes
 * @return An initialized disassembler object, or nil if initialization fails
 */
- (instancetype)initWithBytes:(const void *)bytes address:(ZGMemoryAddress)address size:(ZGMemorySize)size
{
	self = [super init];
	if (self != nil)
	{
		_startAddress = address;
		_size = size;

		// Initialize Capstone for ARM64 architecture
		if (cs_open(CS_ARCH_ARM64, CS_MODE_ARM, &_object) != CS_ERR_OK)
		{
			return nil;
		}

		// Allocate memory for a copy of the machine code bytes
		_bytes = malloc(size);
		if (_bytes == NULL)
		{
			cs_close(&_object);
			return nil;
		}

		// Enable SKIPDATA option to handle non-instruction data
		// Even with a fixed instruction size, we can encounter data we will want to ignore (like .byte / db)
		cs_option(_object, CS_OPT_SKIPDATA, CS_OPT_ON);

		// Copy the machine code bytes to our buffer
		memcpy(_bytes, bytes, size);
	}
	return self;
}

/**
 * Cleans up resources used by the disassembler.
 *
 * This method:
 * 1. Closes the Capstone engine handle
 * 2. Frees the memory allocated for the machine code bytes
 */
- (void)dealloc
{
	cs_close(&_object);
	free(_bytes);
}

/**
 * Determines if the given mnemonic represents a call instruction in ARM64.
 *
 * ARM64 Call Instruction:
 * +--------+--------+--------+--------+
 * |        |        |        |        |
 * |   BL   |      Offset     |        |  Branch with Link (BL)
 * |        |        |        |        |
 * +--------+--------+--------+--------+
 *
 * The BL instruction is the primary function call instruction in ARM64.
 * It branches to the target address and stores the return address in X30 (LR).
 *
 * @param mnemonic The instruction mnemonic ID from Capstone
 * @return YES if the mnemonic is a call instruction (BL), NO otherwise
 */
+ (BOOL)isCallMnemonic:(int64_t)mnemonic
{
	return (mnemonic == ARM64_INS_BL);
}

/**
 * Determines if the given mnemonic represents a jump instruction in ARM64.
 *
 * ARM64 Jump Instructions:
 * +--------+--------+--------+--------+
 * |        |        |        |        |
 * |   B    |      Offset     |        |  Unconditional Branch
 * |        |        |        |        |
 * +--------+--------+--------+--------+
 * |        |        |        |        |
 * |  CBZ   |   Rt   |    Offset       |  Compare and Branch if Zero
 * |        |        |        |        |
 * +--------+--------+--------+--------+
 * |        |        |        |        |
 * |  CBNZ  |   Rt   |    Offset       |  Compare and Branch if Not Zero
 * |        |        |        |        |
 * +--------+--------+--------+--------+
 * |        |        |        |        |
 * |  TBZ   |   Rt   |bit|  Offset     |  Test Bit and Branch if Zero
 * |        |        |        |        |
 * +--------+--------+--------+--------+
 * |        |        |        |        |
 * |  TBNZ  |   Rt   |bit|  Offset     |  Test Bit and Branch if Not Zero
 * |        |        |        |        |
 * +--------+--------+--------+--------+
 *
 * @param mnemonic The instruction mnemonic ID from Capstone
 * @return YES if the mnemonic is a jump instruction, NO otherwise
 */
+ (BOOL)isJumpMnemonic:(int64_t)mnemonic
{
	return (mnemonic == ARM64_INS_CBNZ || mnemonic == ARM64_INS_CBZ || mnemonic == ARM64_INS_B || mnemonic == ARM64_INS_TBNZ || mnemonic == ARM64_INS_TBZ);
}

/**
 * Disassembles all instructions in the buffer and converts them to ZGInstruction objects.
 *
 * Disassembly Process:
 * 
 *  Machine Code Buffer (_bytes)
 *  +---+---+---+---+---+---+---+---+---+---+---+---+
 *  | Instruction 1 | Instruction 2 | Instruction 3 |...
 *  +---+---+---+---+---+---+---+---+---+---+---+---+
 *          |               |               |
 *          v               v               v
 *  +---------------+ +---------------+ +---------------+
 *  | cs_insn       | | cs_insn       | | cs_insn       |...
 *  | - address     | | - address     | | - address     |
 *  | - size        | | - size        | | - size        |
 *  | - mnemonic    | | - mnemonic    | | - mnemonic    |
 *  | - op_str      | | - op_str      | | - op_str      |
 *  | - id          | | - id          | | - id          |
 *  +---------------+ +---------------+ +---------------+
 *          |               |               |
 *          v               v               v
 *  +---------------+ +---------------+ +---------------+
 *  | ZGInstruction | | ZGInstruction | | ZGInstruction |...
 *  | - variable    | | - variable    | | - variable    |
 *  | - text        | | - text        | | - text        |
 *  | - mnemonic    | | - mnemonic    | | - mnemonic    |
 *  +---------------+ +---------------+ +---------------+
 *
 * @return An array of ZGInstruction objects representing the disassembled instructions
 */
- (NSArray<ZGInstruction *> *)readInstructions
{
	NSMutableArray *instructions = [NSMutableArray array];

	// Disassemble all instructions in the buffer
	cs_insn *disassembledInstructions = NULL;
	size_t numberOfInstructionsDisassembled = cs_disasm(_object, _bytes, _size, _startAddress, 0, &disassembledInstructions);

	// Process each disassembled instruction
	for (size_t instructionIndex = 0; instructionIndex < numberOfInstructionsDisassembled; instructionIndex++)
	{
		// Extract instruction details
		ZGMemoryAddress address = disassembledInstructions[instructionIndex].address;
		ZGMemorySize size = disassembledInstructions[instructionIndex].size;
		unsigned int mnemonicID = disassembledInstructions[instructionIndex].id;

		// Calculate pointer to the instruction bytes in our buffer
		void *instructionBytes = (uint8_t *)_bytes + (address - _startAddress);

		// Create human-readable instruction text
		NSString *text = [NSString stringWithFormat:@"%s %s", disassembledInstructions[instructionIndex].mnemonic, disassembledInstructions[instructionIndex].op_str];

		// Create a variable to hold the instruction bytes
		ZGVariable *variable =
		[[ZGVariable alloc]
		 initWithValue:instructionBytes
		 size:size
		 address:address
		 type:ZGByteArray
		 qualifier:0
		 pointerSize:8
		 description:nil
		 enabled:NO];

		// Create a new instruction object and add it to the array
		ZGInstruction *newInstruction = [[ZGInstruction alloc] initWithVariable:variable text:text mnemonic:(int64_t)mnemonicID];
		[instructions addObject:newInstruction];
	}

	// Clean up Capstone resources
	if (numberOfInstructionsDisassembled > 0)
	{
		cs_free(disassembledInstructions, numberOfInstructionsDisassembled);
	}
	return instructions;
}

/**
 * Extracts the immediate operand from a branch instruction.
 *
 * This method disassembles the first instruction in the buffer with detailed
 * operand information enabled, then searches for an immediate operand which
 * represents the branch target address.
 *
 * Branch Operand Extraction Process:
 * 
 * 1. Enable detailed mode in Capstone
 *    cs_option(_object, CS_OPT_DETAIL, CS_OPT_ON)
 *    
 * 2. Disassemble the first instruction
 *    cs_disasm(_object, _bytes, _size, _startAddress, 1, &disassembledInstructions)
 *    
 * 3. Examine operands to find immediate value
 *    +-------------------+
 *    | cs_insn           |
 *    |                   |
 *    | +---------------+ |
 *    | | cs_detail     | |
 *    | |               | |
 *    | | +-----------+ | |
 *    | | | arm64_op  | | |
 *    | | | - type    | | |  <-- Check if ARM64_OP_IMM
 *    | | | - imm     | | |  <-- Extract this value
 *    | | +-----------+ | |
 *    | +---------------+ |
 *    +-------------------+
 *    
 * 4. Disable detailed mode
 *    cs_option(_object, CS_OPT_DETAIL, CS_OPT_OFF)
 *
 * @return A string representation of the branch target address in hexadecimal format,
 *         or "0x0" if no immediate operand is found
 */
- (nullable NSString *)readBranchOperand
{
	int64_t immediateOperand = 0;

	// Enable detailed mode to access operand information
	cs_option(_object, CS_OPT_DETAIL, CS_OPT_ON);

	// Disassemble only the first instruction
	cs_insn *disassembledInstructions = NULL;
	size_t numberOfInstructionsDisassembled = cs_disasm(_object, _bytes, _size, _startAddress, 1, &disassembledInstructions);

	if (numberOfInstructionsDisassembled > 0)
	{
		cs_insn instruction = disassembledInstructions[0];
		cs_detail *detail = instruction.detail;

		// Search through operands for an immediate value
		for (int detailIndex = 0; detailIndex < detail->arm64.op_count; detailIndex++)
		{
			cs_arm64_op operand = detail->arm64.operands[detailIndex];
			if (operand.type == ARM64_OP_IMM)
			{
				immediateOperand = operand.imm;
				break;
			}
		}

		cs_free(disassembledInstructions, numberOfInstructionsDisassembled);
	}

	// Disable detailed mode to restore normal operation
	cs_option(_object, CS_OPT_DETAIL, CS_OPT_OFF);

	// Return the immediate operand as a hexadecimal string
	return [NSString stringWithFormat:@"0x%llX", (uint64_t)immediateOperand];
}

@end
