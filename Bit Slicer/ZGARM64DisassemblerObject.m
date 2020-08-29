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
	void * _Nonnull _bytes;
	ZGMemoryAddress _startAddress;
	ZGMemorySize _size;
	csh _object;
}

@synthesize bytes = _bytes;

- (instancetype)initWithBytes:(const void *)bytes address:(ZGMemoryAddress)address size:(ZGMemorySize)size
{
	self = [super init];
	if (self != nil)
	{
		_startAddress = address;
		_size = size;
		
		if (cs_open(CS_ARCH_ARM64, CS_MODE_ARM, &_object) != CS_ERR_OK)
		{
			return nil;
		}
		
		_bytes = malloc(size);
		if (_bytes == NULL)
		{
			cs_close(&_object);
			return nil;
		}
		
		// Even with a fixed instruction size, we can encounter data we will want to ignore (like .byte / db)
		cs_option(_object, CS_OPT_SKIPDATA, CS_OPT_ON);
		
		memcpy(_bytes, bytes, size);
	}
	return self;
}

- (void)dealloc
{
	cs_close(&_object);
	free(_bytes);
}

+ (BOOL)isCallMnemonic:(int64_t)mnemonic
{
	return (mnemonic == ARM64_INS_BL);
}

+ (BOOL)isJumpMnemonic:(int64_t)mnemonic
{
	return (mnemonic == ARM64_INS_CBNZ || mnemonic == ARM64_INS_CBZ || mnemonic == ARM64_INS_B || mnemonic == ARM64_INS_TBNZ || mnemonic == ARM64_INS_TBZ);
}

- (NSArray<ZGInstruction *> *)readInstructions
{
	NSMutableArray *instructions = [NSMutableArray array];
	
	cs_insn *disassembledInstructions = NULL;
	size_t numberOfInstructionsDisassembled = cs_disasm(_object, _bytes, _size, _startAddress, 0, &disassembledInstructions);
	
	for (size_t instructionIndex = 0; instructionIndex < numberOfInstructionsDisassembled; instructionIndex++)
	{
		ZGMemoryAddress address = disassembledInstructions[instructionIndex].address;
		ZGMemorySize size = disassembledInstructions[instructionIndex].size;
		unsigned int mnemonicID = disassembledInstructions[instructionIndex].id;
		
		void *instructionBytes = (uint8_t *)_bytes + (address - _startAddress);
		
		NSString *text = [NSString stringWithFormat:@"%s %s", disassembledInstructions[instructionIndex].mnemonic, disassembledInstructions[instructionIndex].op_str];
		
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
		
		ZGInstruction *newInstruction = [[ZGInstruction alloc] initWithVariable:variable text:text mnemonic:(int64_t)mnemonicID];
		[instructions addObject:newInstruction];
	}
	
	if (numberOfInstructionsDisassembled > 0)
	{
		cs_free(disassembledInstructions, numberOfInstructionsDisassembled);
	}
	return instructions;
}

- (nullable NSString *)readBranchOperand
{
	int64_t immediateOperand = 0;
	
	cs_option(_object, CS_OPT_DETAIL, CS_OPT_ON);
	
	cs_insn *disassembledInstructions = NULL;
	size_t numberOfInstructionsDisassembled = cs_disasm(_object, _bytes, _size, _startAddress, 1, &disassembledInstructions);
	
	if (numberOfInstructionsDisassembled > 0)
	{
		cs_insn instruction = disassembledInstructions[0];
		cs_detail *detail = instruction.detail;
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
	
	cs_option(_object, CS_OPT_DETAIL, CS_OPT_OFF);
	
	return [NSString stringWithFormat:@"0x%llX", (uint64_t)immediateOperand];
}

@end
