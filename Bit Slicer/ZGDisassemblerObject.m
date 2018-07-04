/*
 * Copyright (c) 2013 Mayur Pawashe
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
#import "udis86.h"
#import "ZGVariable.h"

@implementation ZGDisassemblerObject
{
	ud_t * _Nonnull _object;
	void * _Nonnull _bytes;
	ZGMemoryAddress _startAddress;
	ZGMemorySize _pointerSize;
}

// Possible candidates: UD_Isyscall, UD_Ivmcall, UD_Ivmmcall ??
+ (BOOL)isCallMnemonic:(int)mnemonic
{
	return mnemonic == UD_Icall;
}

+ (BOOL)isJumpMnemonic:(int)mnemonic
{
	return mnemonic >= UD_Ijo && mnemonic <= UD_Ijmp;
}

// Put "short" in short jump instructions to be less ambiguous
static void disassemblerTranslator(ud_t *object)
{
	UD_SYN_INTEL(object);
	if (ud_insn_len(object) == 2 && object->mnemonic >= UD_Ijo && object->mnemonic <= UD_Ijmp)
	{
		const char *originalText = ud_insn_asm(object);
		// test for '0x' as a cheap way to detect if it's an immediate operand as opposed to an indirect register
		if (strstr(originalText, "short") == NULL && strstr(originalText, "0x") != NULL)
		{
			NSString *originalTextValue = @(originalText);
			if (originalTextValue != nil)
			{
				NSMutableArray<NSString *> *textComponents = [NSMutableArray arrayWithArray:[originalTextValue componentsSeparatedByString:@" "]];
				[textComponents insertObject:@"short" atIndex:1];
				const char *text = [[textComponents componentsJoinedByString:@" "] UTF8String];
				if (strlen(text)+1 <= object->asm_buf_size)
				{
					strncpy(object->asm_buf, text, strlen(text)+1);
				}
			}
		}
	}
}

- (id)initWithBytes:(const void *)bytes address:(ZGMemoryAddress)address size:(ZGMemorySize)size pointerSize:(ZGMemorySize)pointerSize
{
	self = [super init];
	if (self != nil)
	{
		_bytes = malloc(size);
		if (_bytes == NULL) return nil;
		memcpy(_bytes, bytes, size);
		
		_startAddress = address;
		_object = malloc(sizeof(*_object));
		
		_pointerSize = pointerSize;
		
		ud_init(_object);
		ud_set_input_buffer(_object, _bytes, size);
		ud_set_mode(_object, (uint8_t)_pointerSize * 8);
		ud_set_syntax(_object, disassemblerTranslator);
		ud_set_pc(_object, _startAddress);
	}
	return self;
}

- (void)dealloc
{
	free(_object);
	free(_bytes);
}

- (NSArray<ZGInstruction *> *)readInstructions
{
	NSMutableArray<ZGInstruction *> *instructions = [NSMutableArray array];
	
	while (ud_disassemble(_object) > 0)
	{
		ZGMemoryAddress instructionAddress = ud_insn_off(_object);
		ZGMemorySize instructionSize = ud_insn_len(_object);
		ud_mnemonic_code_t mnemonic = ud_insn_mnemonic(_object);
		NSString *disassembledText = @(ud_insn_asm(_object));
		
		ZGVariable *variable =
		[[ZGVariable alloc]
		 initWithValue:(uint8_t *)_bytes + (instructionAddress - _startAddress)
		 size:instructionSize
		 address:instructionAddress
		 type:ZGByteArray
		 qualifier:0
		 pointerSize:_pointerSize
		 description:nil
		 enabled:NO];
		
		ZGInstruction *newInstruction = [[ZGInstruction alloc] initWithVariable:variable text:disassembledText mnemonic:mnemonic];
		
		[instructions addObject:newInstruction];
	}
	
	return instructions;
}

- (ZGInstruction *)readLastInstructionWithMaxSize:(ZGMemorySize)maxSize
{
	ZGInstruction *newInstruction = nil;
	while (ud_disassemble(_object) > 0)
	{
		ZGMemoryAddress instructionAddress = ud_insn_off(_object);
		ZGMemorySize instructionSize = ud_insn_len(_object);
		
		if ((instructionAddress - _startAddress) + instructionSize >= maxSize)
		{
			ud_mnemonic_code_t mnemonic = ud_insn_mnemonic(_object);
			NSString *disassembledText = @(ud_insn_asm(_object));
			
			ZGVariable *variable =
			[[ZGVariable alloc]
			 initWithValue:(uint8_t *)_bytes + (instructionAddress - _startAddress)
			 size:instructionSize
			 address:instructionAddress
			 type:ZGByteArray
			 qualifier:0
			 pointerSize:_pointerSize
			 description:nil
			 enabled:NO];
			
			newInstruction = [[ZGInstruction alloc] initWithVariable:variable text:disassembledText mnemonic:mnemonic];
			
			break;
		}
	}
	return newInstruction;
}

- (NSString *)readBranchOperand
{
	NSString *branchOperandString = nil;
	ZGMemoryAddress branchOperandAddress = 0;

	if (ud_disassemble(_object) > 0)
	{
		const ud_operand_t *operand = NULL;
		enum ud_type operandType = UD_NONE;
		unsigned int operandIndex = 0;
		while ((operand = ud_insn_opr(_object, operandIndex)) != NULL)
		{
			if (operand->type == UD_OP_JIMM || operand->type == UD_OP_MEM)
			{
				operandType = operand->type;
				break;
			}
			operandIndex++;
		}

		if (operand != NULL && operandType != UD_NONE)
		{
			int64_t operandOffset = 0x0;
			switch (operand->size)
			{
				case sizeof(int8_t) * 8:
					operandOffset = operand->lval.sbyte;
					break;
				case sizeof(int16_t) * 8:
					operandOffset = operand->lval.sword;
					break;
				case sizeof(int32_t) * 8:
					operandOffset = operand->lval.sdword;
					break;
				case sizeof(int64_t) * 8:
					operandOffset = operand->lval.sqword;
					break;
			}
			
			BOOL canResolveOperand = YES;
			if (operandType == UD_OP_JIMM)
			{
				branchOperandAddress = _startAddress + ud_insn_len(_object);
				if (operandOffset >= 0)
				{
					branchOperandAddress += (uint64_t)operandOffset;
				}
				else
				{
					branchOperandAddress -= (uint64_t)(-operandOffset);
				}
			}
			else
			{
				if (operand->base == UD_R_RIP)
				{
					branchOperandAddress = _startAddress +  ud_insn_len(_object);
					if (operandOffset >= 0)
					{
						branchOperandAddress += (uint64_t)operandOffset;
					}
					else
					{
						branchOperandAddress -= (uint64_t)(-operandOffset);
					}
				}
				else if (operand->base != UD_NONE)
				{
					canResolveOperand = NO;
				}
				else
				{
					branchOperandAddress = (uint64_t)operandOffset;
				}
			}

			if (canResolveOperand)
			{
				if (_pointerSize == sizeof(ZG32BitMemoryAddress))
				{
					branchOperandAddress = (ZG32BitMemoryAddress)branchOperandAddress;
				}

				if (operandType == UD_OP_JIMM)
				{
					branchOperandString = [NSString stringWithFormat:@"0x%llX", branchOperandAddress];
				}
				else
				{
					branchOperandString = [NSString stringWithFormat:@"[0x%llX]", branchOperandAddress];
				}
			}
		}
	}
	
	return branchOperandString;
}

@end
