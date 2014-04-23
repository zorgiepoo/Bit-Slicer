/*
 * Created by Mayur Pawashe on 1/12/13.
 *
 * Copyright (c) 2013 zgcoder
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

#import "ZGDisassemblerObject.h"
#import "capstone.h"
#import "ZGVariable.h"

@interface ZGDisassemblerObject ()

@property (nonatomic) csh object;

@property (nonatomic) void *bytes;
@property (nonatomic) ZGMemorySize size;
@property (nonatomic) ZGMemorySize pointerSize;
@property (nonatomic) ZGMemoryAddress startAddress;

@end

@implementation ZGDisassemblerObject

+ (BOOL)isCallMnemonic:(int)mnemonic
{
	return (mnemonic == X86_INS_CALL);
}

static BOOL isJumpMnemonic(int mnemonic)
{
	return (mnemonic >= X86_INS_JAE && mnemonic <= X86_INS_JS);
}

+ (BOOL)isJumpMnemonic:(int)mnemonic
{
	return isJumpMnemonic(mnemonic);
}

- (id)initWithBytes:(const void *)bytes address:(ZGMemoryAddress)address size:(ZGMemorySize)size pointerSize:(ZGMemorySize)pointerSize
{
	self = [super init];
	if (self != nil)
	{
		if (cs_open(CS_ARCH_X86, pointerSize == sizeof(int64_t) ? CS_MODE_64 : CS_MODE_32, &_object) != CS_ERR_OK)
		{
			return nil;
		}

		cs_opt_skipdata skipdata = { .mnemonic = "db" };
		if (cs_option(_object, CS_OPT_SKIPDATA_SETUP, &skipdata) != CS_ERR_OK)
		{
			return nil;
		}

		if (cs_option(_object, CS_OPT_SKIPDATA, CS_OPT_ON) != CS_ERR_OK)
		{
			return nil;
		}

		self.bytes = malloc(size);
		memcpy(self.bytes, bytes, size);

		self.startAddress = address;
		self.size = size;
		self.pointerSize = pointerSize;
	}
	return self;
}

- (void)dealloc
{
	cs_close(&_object);
	free(self.bytes); self.bytes = NULL;
}

static void getTextBuffer(void *instructionBytes, size_t instructionSize, unsigned int mnemonicID, char *destinationBuffer, const char *mnemonicBuffer, size_t mnemonicBufferSize, const char *operandStringBuffer, size_t operandStringBufferSize)
{
	size_t mnemonicStringLength = strlen(mnemonicBuffer);
	memcpy(destinationBuffer, mnemonicBuffer, mnemonicStringLength);
	
	if (isJumpMnemonic(mnemonicID) && instructionSize == 2 && strstr(operandStringBuffer, "0x") != NULL && strstr(mnemonicBuffer, "short") == NULL)
	{
		// Specify that instruction is a short jump
		char shortString[] = " short ";
		memcpy(destinationBuffer + mnemonicStringLength, shortString, sizeof(shortString) - 1);
		memcpy(destinationBuffer + mnemonicStringLength + sizeof(shortString) - 1, operandStringBuffer, operandStringBufferSize);
	}
	else
	{
		destinationBuffer[mnemonicStringLength] = ' ';
		memcpy(destinationBuffer + mnemonicStringLength + 1, operandStringBuffer, operandStringBufferSize);
	}
}

- (NSArray *)readInstructions
{
	NSMutableArray *instructions = [NSMutableArray array];
	
	cs_insn *disassembledInstructions = NULL;
	size_t numberOfInstructionsDisassembled = cs_disasm_ex(self.object, self.bytes, self.size, self.startAddress, 0, &disassembledInstructions);
	for (size_t instructionIndex = 0; instructionIndex < numberOfInstructionsDisassembled; instructionIndex++)
	{
		ZGMemoryAddress address = disassembledInstructions[instructionIndex].address;
		ZGMemorySize size = disassembledInstructions[instructionIndex].size;
		unsigned int mnemonicID = disassembledInstructions[instructionIndex].id;
		
		void *instructionBytes = _bytes + (address - _startAddress);
		
		char textBuffer[sizeof(disassembledInstructions[instructionIndex].mnemonic) + sizeof(disassembledInstructions[instructionIndex].op_str) + 10];
		getTextBuffer(instructionBytes, size, mnemonicID, textBuffer, disassembledInstructions[instructionIndex].mnemonic, sizeof(disassembledInstructions[instructionIndex].mnemonic), disassembledInstructions[instructionIndex].op_str, sizeof(disassembledInstructions[instructionIndex].op_str));
		NSString *text = @(textBuffer);
		
		ZGVariable *variable =
		[[ZGVariable alloc]
		 initWithValue:instructionBytes
		 size:size
		 address:address
		 type:ZGByteArray
		 qualifier:0
		 pointerSize:_pointerSize
		 description:nil
		 enabled:NO];
		
		ZGInstruction *newInstruction = [[ZGInstruction alloc] initWithVariable:variable text:text mnemonic:mnemonicID];
		[instructions addObject:newInstruction];
	}
	
	if (numberOfInstructionsDisassembled > 0)
	{
		cs_free(disassembledInstructions, numberOfInstructionsDisassembled);
	}
	
	return instructions;
}

- (ZGInstruction *)readLastInstructionWithMaxSize:(ZGMemorySize)maxSize
{
	ZGInstruction *newInstruction = nil;
	
	cs_insn *disassembledInstructions = NULL;
	size_t numberOfInstructionsDisassembled = cs_disasm_ex(self.object, self.bytes, self.size, self.startAddress, 0, &disassembledInstructions);
	for (size_t instructionIndex = 0; instructionIndex < numberOfInstructionsDisassembled; instructionIndex++)
	{
		ZGMemoryAddress address = disassembledInstructions[instructionIndex].address;
		ZGMemorySize size = disassembledInstructions[instructionIndex].size;
		
		if ((address - _startAddress) + size >= maxSize)
		{
			unsigned int mnemonicID = disassembledInstructions[instructionIndex].id;
			void *instructionBytes = _bytes + (address - _startAddress);
			
			char textBuffer[sizeof(disassembledInstructions[instructionIndex].mnemonic) + sizeof(disassembledInstructions[instructionIndex].op_str) + 10];
			getTextBuffer(instructionBytes, size, mnemonicID, textBuffer, disassembledInstructions[instructionIndex].mnemonic, sizeof(disassembledInstructions[instructionIndex].mnemonic), disassembledInstructions[instructionIndex].op_str, sizeof(disassembledInstructions[instructionIndex].op_str));
			NSString *text = @(textBuffer);
			
			ZGVariable *variable =
			[[ZGVariable alloc]
			 initWithValue:instructionBytes
			 size:size
			 address:address
			 type:ZGByteArray
			 qualifier:0
			 pointerSize:_pointerSize
			 description:nil
			 enabled:NO];
			
			newInstruction = [[ZGInstruction alloc] initWithVariable:variable text:text mnemonic:mnemonicID];
			
			break;
		}
	}
	
	if (numberOfInstructionsDisassembled > 0)
	{
		cs_free(disassembledInstructions, numberOfInstructionsDisassembled);
	}
	
	return newInstruction;
}

- (ZGMemoryAddress)readBranchImmediateOperand
{
	ZGMemoryAddress immediateOperand = 0;
	
	cs_option(self.object, CS_OPT_DETAIL, CS_OPT_ON);
	
	cs_insn *disassembledInstructions = NULL;
	size_t numberOfInstructionsDisassembled = cs_disasm_ex(self.object, self.bytes, self.size, self.startAddress, 1, &disassembledInstructions);
	if (numberOfInstructionsDisassembled > 0)
	{
		cs_insn instruction = disassembledInstructions[0];
		cs_detail *detail = instruction.detail;
		for (int detailIndex = 0; detailIndex < detail->x86.op_count; detailIndex++)
		{
			cs_x86_op operand = detail->x86.operands[detailIndex];
			if (operand.type != X86_OP_IMM) continue;
			
			immediateOperand = operand.imm;
			
			break;
		}
		
		cs_free(disassembledInstructions, numberOfInstructionsDisassembled);
	}
	
	return immediateOperand;
}

@end
