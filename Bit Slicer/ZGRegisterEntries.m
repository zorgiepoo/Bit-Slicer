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

#import "ZGRegisterEntries.h"
#import "ZGVariable.h"
#import "ZGNullability.h"

@implementation ZGRegisterEntries

void *ZGRegisterEntryValue(ZGRegisterEntry *entry)
{
	return entry->value;
}

#define ADD_GENERAL_REGISTER(entries, entryIndex, threadState, registerName, structureType, structName) \
{ \
	strncpy((char *)&entries[entryIndex].name, #registerName, sizeof(entries[entryIndex].name)); \
	entries[entryIndex].name[sizeof(entries[entryIndex].name) - 1] = '\0'; \
	entries[entryIndex].size = sizeof(threadState.uts.structureType.__##registerName); \
	memcpy(&entries[entryIndex].value, &threadState.uts.structureType.__##registerName, entries[entryIndex].size); \
	entries[entryIndex].offset = offsetof(structName, __##registerName); \
	entries[entryIndex].type = ZGRegisterGeneralPurpose; \
	entryIndex++; \
}

#define ADD_GENERAL_REGISTER_32(entries, entryIndex, threadState, registerName) ADD_GENERAL_REGISTER(entries, entryIndex, threadState, registerName, ts32, x86_thread_state32_t)
#define ADD_GENERAL_REGISTER_64(entries, entryIndex, threadState, registerName) ADD_GENERAL_REGISTER(entries, entryIndex, threadState, registerName, ts64, x86_thread_state64_t)

+ (int)getRegisterEntries:(ZGRegisterEntry *)entries fromGeneralPurposeThreadState:(x86_thread_state_t)threadState is64Bit:(BOOL)is64Bit
{
	int entryIndex = 0;
	
	if (is64Bit)
	{
		// General registers
		ADD_GENERAL_REGISTER_64(entries, entryIndex, threadState, rax);
		ADD_GENERAL_REGISTER_64(entries, entryIndex, threadState, rbx);
		ADD_GENERAL_REGISTER_64(entries, entryIndex, threadState, rcx);
		ADD_GENERAL_REGISTER_64(entries, entryIndex, threadState, rdx);
		
		// Index and pointers
		ADD_GENERAL_REGISTER_64(entries, entryIndex, threadState, rdi);
		ADD_GENERAL_REGISTER_64(entries, entryIndex, threadState, rsi);
		ADD_GENERAL_REGISTER_64(entries, entryIndex, threadState, rbp);
		ADD_GENERAL_REGISTER_64(entries, entryIndex, threadState, rsp);
		
		// Extra registers
		ADD_GENERAL_REGISTER_64(entries, entryIndex, threadState, r8);
		ADD_GENERAL_REGISTER_64(entries, entryIndex, threadState, r9);
		ADD_GENERAL_REGISTER_64(entries, entryIndex, threadState, r10);
		ADD_GENERAL_REGISTER_64(entries, entryIndex, threadState, r11);
		ADD_GENERAL_REGISTER_64(entries, entryIndex, threadState, r12);
		ADD_GENERAL_REGISTER_64(entries, entryIndex, threadState, r13);
		ADD_GENERAL_REGISTER_64(entries, entryIndex, threadState, r14);
		ADD_GENERAL_REGISTER_64(entries, entryIndex, threadState, r15);
		
		// Instruction pointer
		ADD_GENERAL_REGISTER_64(entries, entryIndex, threadState, rip);
		
		// Flags indicator
		ADD_GENERAL_REGISTER_64(entries, entryIndex, threadState, rflags);
		
		// Segment registers
		ADD_GENERAL_REGISTER_64(entries, entryIndex, threadState, cs);
		ADD_GENERAL_REGISTER_64(entries, entryIndex, threadState, fs);
		ADD_GENERAL_REGISTER_64(entries, entryIndex, threadState, gs);
	}
	else
	{
		// General registers
		ADD_GENERAL_REGISTER_32(entries, entryIndex, threadState, eax);
		ADD_GENERAL_REGISTER_32(entries, entryIndex, threadState, ebx);
		ADD_GENERAL_REGISTER_32(entries, entryIndex, threadState, ecx);
		ADD_GENERAL_REGISTER_32(entries, entryIndex, threadState, edx);
		
		// Index and pointers
		ADD_GENERAL_REGISTER_32(entries, entryIndex, threadState, edi);
		ADD_GENERAL_REGISTER_32(entries, entryIndex, threadState, esi);
		ADD_GENERAL_REGISTER_32(entries, entryIndex, threadState, ebp);
		ADD_GENERAL_REGISTER_32(entries, entryIndex, threadState, esp);
		
		// Segment register
		ADD_GENERAL_REGISTER_32(entries, entryIndex, threadState, ss);
		
		// Flags indicator
		ADD_GENERAL_REGISTER_32(entries, entryIndex, threadState, eflags);
		
		// Instruction pointer
		ADD_GENERAL_REGISTER_32(entries, entryIndex, threadState, eip);
		
		// Segment registers
		ADD_GENERAL_REGISTER_32(entries, entryIndex, threadState, cs);
		ADD_GENERAL_REGISTER_32(entries, entryIndex, threadState, ds);
		ADD_GENERAL_REGISTER_32(entries, entryIndex, threadState, es);
		ADD_GENERAL_REGISTER_32(entries, entryIndex, threadState, fs);
		ADD_GENERAL_REGISTER_32(entries, entryIndex, threadState, gs);
	}
	
	entries[entryIndex].name[0] = 0;
	
	return entryIndex;
}

#define ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, registerName) \
{ \
	strncpy((char *)&entries[entryIndex].name, #registerName, sizeof(entries[entryIndex].name)); \
	entries[entryIndex].name[sizeof(entries[entryIndex].name) - 1] = '\0'; \
	entries[entryIndex].size = sizeof(vectorState.ufs.as64.__fpu_##registerName); \
	entries[entryIndex].offset = offsetof(x86_avx_state64_t, __fpu_##registerName); \
	memcpy(&entries[entryIndex].value, &vectorState.ufs.as64.__fpu_##registerName, entries[entryIndex].size); \
	entries[entryIndex].type = ZGRegisterVector; \
	entryIndex++; \
}

+ (int)getRegisterEntries:(ZGRegisterEntry *)entries fromVectorThreadState:(zg_x86_vector_state_t)vectorState is64Bit:(BOOL)is64Bit hasAVXSupport:(BOOL)hasAVXSupport
{
	int entryIndex = 0;
	
	ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, fcw); // FPU control word
	ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, fsw); // FPU status word
	ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, ftw); // FPU tag word
	ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, fop); // FPU Opcode
	
	// Instruction Pointer
	ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, ip); // offset
	ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, cs); // selector
	
	// Instruction operand (data) pointer
	ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, dp); // offset
	ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, ds); // selector
	
	ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, mxcsr); // MXCSR Register state
	ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, mxcsrmask); // MXCSR mask
	
	// STX/MMX
	ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, stmm0);
	ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, stmm1);
	ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, stmm2);
	ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, stmm3);
	ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, stmm4);
	ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, stmm5);
	ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, stmm6);
	ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, stmm7);
	
	// XMM 0 through 7
	ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, xmm0);
	ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, xmm1);
	ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, xmm2);
	ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, xmm3);
	ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, xmm4);
	ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, xmm5);
	ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, xmm6);
	ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, xmm7);
	
	if (is64Bit)
	{
		// XMM 8 through 15
		ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, xmm8);
		ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, xmm9);
		ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, xmm10);
		ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, xmm11);
		ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, xmm12);
		ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, xmm13);
		ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, xmm14);
		ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, xmm15);
	}
	
	if (hasAVXSupport)
	{
		// YMMH 0 through 7
		ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, ymmh0);
		ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, ymmh1);
		ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, ymmh2);
		ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, ymmh3);
		ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, ymmh4);
		ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, ymmh5);
		ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, ymmh6);
		ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, ymmh7);
		
		if (is64Bit)
		{
			// YMMH 8 through 15
			ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, ymmh8);
			ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, ymmh9);
			ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, ymmh10);
			ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, ymmh11);
			ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, ymmh12);
			ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, ymmh13);
			ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, ymmh14);
			ADD_VECTOR_REGISTER(entries, entryIndex, vectorState, ymmh15);
		}
	}
	
	entries[entryIndex].name[0] = 0;
	
	return entryIndex;
}

+ (NSArray<ZGVariable *> *)registerVariablesFromVectorThreadState:(zg_x86_vector_state_t)vectorState is64Bit:(BOOL)is64Bit hasAVXSupport:(BOOL)hasAVXSupport
{
	NSMutableArray<ZGVariable *> *registerVariables = [[NSMutableArray alloc] init];
	
	ZGRegisterEntry entries[64];
	[ZGRegisterEntries getRegisterEntries:entries fromVectorThreadState:vectorState is64Bit:is64Bit hasAVXSupport:hasAVXSupport];
	
	for (ZGRegisterEntry *entry = entries; !ZG_REGISTER_ENTRY_IS_NULL(entry); entry++)
	{
		ZGVariable *variable =
		[[ZGVariable alloc]
		 initWithValue:entry->value
		 size:entry->size
		 address:0
		 type:ZGByteArray
		 qualifier:0
		 pointerSize:is64Bit ? sizeof(int64_t) : sizeof(int32_t)
		 description:[[NSAttributedString alloc] initWithString:ZGUnwrapNullableObject(@(entry->name))]];
		
		[registerVariables addObject:variable];
	}
	
	return registerVariables;
}

+ (NSArray<ZGVariable *> *)registerVariablesFromGeneralPurposeThreadState:(x86_thread_state_t)threadState is64Bit:(BOOL)is64Bit
{
	NSMutableArray<ZGVariable *> *registerVariables = [[NSMutableArray alloc] init];
	
	ZGRegisterEntry entries[28];
	[ZGRegisterEntries getRegisterEntries:entries fromGeneralPurposeThreadState:threadState is64Bit:is64Bit];
	
	for (ZGRegisterEntry *entry = entries; !ZG_REGISTER_ENTRY_IS_NULL(entry); entry++)
	{
		ZGVariable *variable =
		[[ZGVariable alloc]
		 initWithValue:entry->value
		 size:entry->size
		 address:0
		 type:ZGByteArray
		 qualifier:0
		 pointerSize:is64Bit ? sizeof(int64_t) : sizeof(int32_t)
		 description:[[NSAttributedString alloc] initWithString:ZGUnwrapNullableObject(@(entry->name))]];
		
		[registerVariables addObject:variable];
	}
	
	return registerVariables;
}

@end
