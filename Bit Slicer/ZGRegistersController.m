/*
 * Created by Mayur Pawashe on 2/7/13.
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

#import "ZGRegistersController.h"
#import "ZGVariable.h"
#import "ZGBreakPoint.h"
#import "ZGProcess.h"
#import "ZGPreferencesController.h"
#import "ZGUtilities.h"
#import "ZGDebuggerController.h"

@interface ZGRegistersController ()

@property (assign) IBOutlet NSTableView *tableView;
@property (assign) IBOutlet ZGDebuggerController *debuggerController;

@property (nonatomic, strong) NSArray *registers;
@property (nonatomic, strong) ZGBreakPoint *breakPoint;
@property (nonatomic, assign) ZGVariableType qualifier;

@property (nonatomic, copy) program_counter_change_t programCounterChangeBlock;

@end

@implementation ZGRegistersController

- (void)awakeFromNib
{
	[self setNextResponder:[self.tableView nextResponder]];
	[self.tableView setNextResponder:self];
	
	[self.tableView registerForDraggedTypes:@[ZGVariablePboardType]];
}

- (void)setProgramCounter:(ZGMemoryAddress)programCounter
{
	if (_programCounter != programCounter)
	{
		_programCounter = programCounter;
		if (self.programCounterChangeBlock)
		{
			self.programCounterChangeBlock();
		}
	}
}

- (void)changeProgramCounter:(ZGMemoryAddress)newProgramCounter
{
	if (_programCounter != newProgramCounter)
	{
		x86_thread_state_t threadState;
		mach_msg_type_number_t threadStateCount = x86_THREAD_STATE_COUNT;
		if (thread_get_state(self.breakPoint.thread, x86_THREAD_STATE, (thread_state_t)&threadState, &threadStateCount) == KERN_SUCCESS)
		{
			if (self.breakPoint.process.is64Bit)
			{
				threadState.uts.ts64.__rip = newProgramCounter;
			}
			else
			{
				threadState.uts.ts32.__eip = (uint32_t)newProgramCounter;
			}
			
			if (thread_set_state(self.breakPoint.thread, x86_THREAD_STATE, (thread_state_t)&threadState, threadStateCount) == KERN_SUCCESS)
			{
				self.programCounter = newProgramCounter;
			}
		}
	}
}

- (ZGMemoryAddress)basePointer
{
	ZGMemoryAddress basePointer = 0x0;
	
	x86_thread_state_t threadState;
	mach_msg_type_number_t threadStateCount = x86_THREAD_STATE_COUNT;
	if (thread_get_state(self.breakPoint.thread, x86_THREAD_STATE, (thread_state_t)&threadState, &threadStateCount) == KERN_SUCCESS)
	{
		if (self.breakPoint.process.is64Bit)
		{
			basePointer = threadState.uts.ts64.__rbp;
		}
		else
		{
			basePointer = threadState.uts.ts32.__ebp;
		}
	}
	
	return basePointer;
}

#define ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, registerName) \
{ \
	strcpy((char *)&entries[entryIndex].name, #registerName); \
	entries[entryIndex].size = sizeof(avxState.ufs.as64.__fpu_##registerName); \
	entries[entryIndex].offset = offsetof(x86_avx_state64_t, __fpu_##registerName); \
	memcpy(&entries[entryIndex].value, &avxState.ufs.as64.__fpu_##registerName, entries[entryIndex].size); \
	entries[entryIndex].type = ZGRegisterAVX; \
	entryIndex++; \
}

+ (int)getRegisterEntries:(ZGFastRegisterEntry *)entries fromAVXThreadState:(x86_avx_state_t)avxState is64Bit:(BOOL)is64Bit
{
	int entryIndex = 0;
	
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, fcw); // FPU control word
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, fsw); // FPU status word
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, ftw); // FPU tag word
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, fop); // FPU Opcode
	
	// Instruction Pointer
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, ip); // offset
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, cs); // selector
	
	// Instruction operand (data) pointer
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, dp); // offset
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, ds); // selector
	
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, mxcsr); // MXCSR Register state
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, mxcsrmask); // MXCSR mask
	
	// STX/MMX
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, stmm0);
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, stmm1);
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, stmm2);
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, stmm3);
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, stmm4);
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, stmm5);
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, stmm6);
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, stmm7);
	
	// XMM 0 through 7
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, xmm0);
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, xmm1);
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, xmm2);
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, xmm3);
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, xmm4);
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, xmm5);
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, xmm6);
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, xmm7);
	
	if (is64Bit)
	{
		// XMM 8 through 15
		ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, xmm8);
		ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, xmm9);
		ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, xmm10);
		ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, xmm11);
		ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, xmm12);
		ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, xmm13);
		ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, xmm14);
		ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, xmm15);
	}
	
	// YMMH 0 through 7
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, ymmh0);
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, ymmh1);
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, ymmh2);
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, ymmh3);
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, ymmh4);
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, ymmh5);
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, ymmh6);
	ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, ymmh7);
	
	if (is64Bit)
	{
		// YMMH 8 through 15
		ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, ymmh8);
		ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, ymmh9);
		ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, ymmh10);
		ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, ymmh11);
		ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, ymmh12);
		ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, ymmh13);
		ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, ymmh14);
		ADD_FAST_AVX_REGISTER(entries, entryIndex, avxState, ymmh15);
	}
	
	entries[entryIndex].name[0] = 0;
	
	return entryIndex;
}

+ (NSArray *)registerVariablesFromAVXThreadState:(x86_avx_state_t)avxState is64Bit:(BOOL)is64Bit
{
	NSMutableArray *registerVariables = [[NSMutableArray alloc] init];
	
	ZGFastRegisterEntry entries[64];
	[self getRegisterEntries:entries fromAVXThreadState:avxState is64Bit:is64Bit];
	
	for (ZGFastRegisterEntry *entry = entries; !ZG_REGISTER_ENTRY_IS_NULL(*entry); entry++)
	{
		ZGVariable *variable =
		[[ZGVariable alloc]
		 initWithValue:entry->value
		 size:entry->size
		 address:0
		 type:ZGByteArray
		 qualifier:0
		 pointerSize:is64Bit
		 description:@(entry->name)];
		
		[registerVariables addObject:variable];
	}
	
	return registerVariables;
}

#define ADD_FAST_GENERAL_REGISTER(entries, entryIndex, threadState, registerName, structureType, structName, _prefersUnsigned) \
{ \
	strcpy((char *)&entries[entryIndex].name, #registerName); \
	entries[entryIndex].size = sizeof(threadState.uts.structureType.__##registerName); \
	memcpy(&entries[entryIndex].value, &threadState.uts.structureType.__##registerName, entries[entryIndex].size); \
	entries[entryIndex].offset = offsetof(structName, __##registerName); \
	entries[entryIndex].type = ZGRegisterGeneralPurpose; \
	entries[entryIndex].prefersUnsigned = _prefersUnsigned; \
	entryIndex++; \
}

#define ADD_FAST_GENERAL_REGISTER_32(entries, entryIndex, threadState, registerName, prefersUnsigned) ADD_FAST_GENERAL_REGISTER(entries, entryIndex, threadState, registerName, ts32, x86_thread_state32_t, prefersUnsigned)
#define ADD_FAST_GENERAL_REGISTER_64(entries, entryIndex, threadState, registerName, prefersUnsigned) ADD_FAST_GENERAL_REGISTER(entries, entryIndex, threadState, registerName, ts64, x86_thread_state64_t, prefersUnsigned)

+ (int)getRegisterEntries:(ZGFastRegisterEntry *)entries fromGeneralPurposeThreadState:(x86_thread_state_t)threadState is64Bit:(BOOL)is64Bit
{
	int entryIndex = 0;
	
	if (is64Bit)
	{
		// General registers
		ADD_FAST_GENERAL_REGISTER_64(entries, entryIndex, threadState, rax, NO);
		ADD_FAST_GENERAL_REGISTER_64(entries, entryIndex, threadState, rbx, NO);
		ADD_FAST_GENERAL_REGISTER_64(entries, entryIndex, threadState, rcx, NO);
		ADD_FAST_GENERAL_REGISTER_64(entries, entryIndex, threadState, rdx, NO);
		
		// Index and pointers
		ADD_FAST_GENERAL_REGISTER_64(entries, entryIndex, threadState, rdi, YES);
		ADD_FAST_GENERAL_REGISTER_64(entries, entryIndex, threadState, rsi, YES);
		ADD_FAST_GENERAL_REGISTER_64(entries, entryIndex, threadState, rbp, YES);
		ADD_FAST_GENERAL_REGISTER_64(entries, entryIndex, threadState, rsp, YES);
		
		// Extra registers
		ADD_FAST_GENERAL_REGISTER_64(entries, entryIndex, threadState, r8, NO);
		ADD_FAST_GENERAL_REGISTER_64(entries, entryIndex, threadState, r9, NO);
		ADD_FAST_GENERAL_REGISTER_64(entries, entryIndex, threadState, r10, NO);
		ADD_FAST_GENERAL_REGISTER_64(entries, entryIndex, threadState, r11, NO);
		ADD_FAST_GENERAL_REGISTER_64(entries, entryIndex, threadState, r12, NO);
		ADD_FAST_GENERAL_REGISTER_64(entries, entryIndex, threadState, r13, NO);
		ADD_FAST_GENERAL_REGISTER_64(entries, entryIndex, threadState, r14, NO);
		ADD_FAST_GENERAL_REGISTER_64(entries, entryIndex, threadState, r15, NO);
		
		// Instruction pointer
		ADD_FAST_GENERAL_REGISTER_64(entries, entryIndex, threadState, rip, YES);
		
		// Flags indicator
		ADD_FAST_GENERAL_REGISTER_64(entries, entryIndex, threadState, rflags, NO);
		
		// Segment registers
		ADD_FAST_GENERAL_REGISTER_64(entries, entryIndex, threadState, cs, NO);
		ADD_FAST_GENERAL_REGISTER_64(entries, entryIndex, threadState, fs, NO);
		ADD_FAST_GENERAL_REGISTER_64(entries, entryIndex, threadState, gs, NO);
	}
	else
	{
		// General registers
		ADD_FAST_GENERAL_REGISTER_32(entries, entryIndex, threadState, eax, NO);
		ADD_FAST_GENERAL_REGISTER_32(entries, entryIndex, threadState, ebx, NO);
		ADD_FAST_GENERAL_REGISTER_32(entries, entryIndex, threadState, ecx, NO);
		ADD_FAST_GENERAL_REGISTER_32(entries, entryIndex, threadState, edx, NO);
		
		// Index and pointers
		ADD_FAST_GENERAL_REGISTER_32(entries, entryIndex, threadState, edi, YES);
		ADD_FAST_GENERAL_REGISTER_32(entries, entryIndex, threadState, esi, YES);
		ADD_FAST_GENERAL_REGISTER_32(entries, entryIndex, threadState, ebp, YES);
		ADD_FAST_GENERAL_REGISTER_32(entries, entryIndex, threadState, esp, YES);
		
		// Segment register
		ADD_FAST_GENERAL_REGISTER_32(entries, entryIndex, threadState, ss, NO);
		
		// Flags indicator
		ADD_FAST_GENERAL_REGISTER_32(entries, entryIndex, threadState, eflags, NO);
		
		// Instruction pointer
		ADD_FAST_GENERAL_REGISTER_32(entries, entryIndex, threadState, eip, YES);
		
		// Segment registers
		ADD_FAST_GENERAL_REGISTER_32(entries, entryIndex, threadState, cs, NO);
		ADD_FAST_GENERAL_REGISTER_32(entries, entryIndex, threadState, ds, NO);
		ADD_FAST_GENERAL_REGISTER_32(entries, entryIndex, threadState, es, NO);
		ADD_FAST_GENERAL_REGISTER_32(entries, entryIndex, threadState, fs, NO);
		ADD_FAST_GENERAL_REGISTER_32(entries, entryIndex, threadState, gs, NO);
	}
	
	entries[entryIndex].name[0] = 0;
	
	return entryIndex;
}

+ (NSArray *)registerVariablesFromGeneralPurposeThreadState:(x86_thread_state_t)threadState is64Bit:(BOOL)is64Bit
{
	NSMutableArray *registerVariables = [[NSMutableArray alloc] init];
	
	ZGFastRegisterEntry entries[28];
	[self getRegisterEntries:entries fromGeneralPurposeThreadState:threadState is64Bit:is64Bit];
	
	for (ZGFastRegisterEntry *entry = entries; !ZG_REGISTER_ENTRY_IS_NULL(*entry); entry++)
	{
		ZGVariable *variable =
		[[ZGVariable alloc]
		 initWithValue:entry->value
		 size:entry->size
		 address:0
		 type:ZGByteArray
		 qualifier:0
		 pointerSize:is64Bit
		 description:@(entry->name)];
		
		[registerVariables addObject:variable];
	}
	
	return registerVariables;
}

- (void)updateRegistersFromBreakPoint:(ZGBreakPoint *)breakPoint programCounterChange:(program_counter_change_t)programCounterChangeBlock
{
	self.breakPoint = breakPoint;
	// initialize program counter with a sane value
	self.programCounter = self.breakPoint.variable.address;
	
	ZGMemorySize pointerSize = breakPoint.process.pointerSize;
	NSDictionary *registerDefaultsDictionary = [[NSUserDefaults standardUserDefaults] objectForKey:ZG_REGISTER_TYPES];
	
	NSMutableArray *newRegisters = [NSMutableArray array];
	
	NSArray *registerVariables = [[self class] registerVariablesFromGeneralPurposeThreadState:breakPoint.generalPurposeThreadState is64Bit:breakPoint.process.is64Bit];
	
	for (ZGVariable *registerVariable in registerVariables)
	{
		[registerVariable setQualifier:self.qualifier];
		
		ZGRegister *newRegister = [[ZGRegister alloc] initWithRegisterType:ZGRegisterGeneralPurpose variable:registerVariable pointerSize:pointerSize];
		
		NSNumber *registerDefaultType = [registerDefaultsDictionary objectForKey:registerVariable.name];
		if (registerDefaultType != nil && [registerDefaultType intValue] != ZGByteArray)
		{
			[newRegister.variable setType:[registerDefaultType intValue] requestedSize:newRegister.size pointerSize:pointerSize];
			[newRegister.variable setValue:newRegister.value];
		}
		
		[newRegisters addObject:newRegister];
	}
	
	if (breakPoint.process.is64Bit)
	{
		self.programCounter = breakPoint.generalPurposeThreadState.uts.ts64.__rip;
	}
	else
	{
		self.programCounter = breakPoint.generalPurposeThreadState.uts.ts32.__eip;
	}
	
	if (breakPoint.hasAVXState)
	{
		NSArray *registerVariables = [[self class] registerVariablesFromAVXThreadState:breakPoint.avxState is64Bit:breakPoint.process.is64Bit];
		for (ZGVariable *registerVariable in registerVariables)
		{
			ZGRegister *newRegister = [[ZGRegister alloc] initWithRegisterType:ZGRegisterAVX variable:registerVariable pointerSize:pointerSize];
			
			NSNumber *registerDefaultType = [registerDefaultsDictionary objectForKey:registerVariable.name];
			if (registerDefaultType != nil && [registerDefaultType intValue] != ZGByteArray)
			{
				[newRegister.variable setType:[registerDefaultType intValue] requestedSize:newRegister.size pointerSize:pointerSize];
				[newRegister.variable setValue:newRegister.value];
			}
			
			[newRegisters addObject:newRegister];
		}
	}
	
	self.registers = [NSArray arrayWithArray:newRegisters];
	
	self.programCounterChangeBlock = programCounterChangeBlock;
	
	[self.tableView reloadData];
}

- (void)changeRegister:(ZGRegister *)theRegister oldType:(ZGVariableType)oldType newType:(ZGVariableType)newType
{
	[theRegister.variable setType:newType requestedSize:theRegister.size pointerSize:self.breakPoint.process.pointerSize];
	[theRegister.variable setValue:theRegister.value];
	
	NSMutableDictionary *registerTypesDictionary = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] objectForKey:ZG_REGISTER_TYPES]];
	[registerTypesDictionary setObject:@(theRegister.variable.type) forKey:theRegister.variable.name];
	[[NSUserDefaults standardUserDefaults] setObject:registerTypesDictionary forKey:ZG_REGISTER_TYPES];
	
	[[self.debuggerController.undoManager prepareWithInvocationTarget:self] changeRegister:theRegister oldType:newType newType:oldType];
	[self.debuggerController.undoManager setActionName:@"Register Type Change"];
	
	[self.tableView reloadData];
}

#define WRITE_AVX_STATE(avxState, variable, registerName) memcpy(&avxState.ufs.as64.__fpu_##registerName, variable.value, MIN(variable.size, sizeof(avxState.ufs.as64.__fpu_##registerName)))

- (BOOL)changeFloatingPointRegister:(ZGRegister *)theRegister oldVariable:(ZGVariable *)oldVariable newVariable:(ZGVariable *)newVariable
{
	BOOL is64Bit = self.breakPoint.process.is64Bit;
	
	// For some bizarre reason, thread_set_state will not work later if I use x86_AVX_STATE, so I'm forced to explicitly use x86_AVX_STATE32 and x86_AVX_STATE64
	x86_avx_state_t avxState;
	mach_msg_type_number_t avxStateCount = is64Bit ? x86_AVX_STATE64_COUNT : x86_AVX_STATE32_COUNT;
	if (thread_get_state(self.breakPoint.thread, is64Bit ? x86_AVX_STATE64 : x86_AVX_STATE32, is64Bit ? (thread_state_t)&avxState.ufs.as64 : (thread_state_t)&avxState.ufs.as32, &avxStateCount) != KERN_SUCCESS)
	{
		return NO;
	}
	
	NSString *registerName = theRegister.variable.name;
	if ([registerName isEqualToString:@"fcw"])
	{
		WRITE_AVX_STATE(avxState, newVariable, fcw);
	}
	else if ([registerName isEqualToString:@"fsw"])
	{
		WRITE_AVX_STATE(avxState, newVariable, fsw);
	}
	else if ([registerName isEqualToString:@"fop"])
	{
		WRITE_AVX_STATE(avxState, newVariable, fop);
	}
	else if ([registerName isEqualToString:@"ip"])
	{
		WRITE_AVX_STATE(avxState, newVariable, ip);
	}
	else if ([registerName isEqualToString:@"cs"])
	{
		WRITE_AVX_STATE(avxState, newVariable, cs);
	}
	else if ([registerName isEqualToString:@"dp"])
	{
		WRITE_AVX_STATE(avxState, newVariable, dp);
	}
	else if ([registerName isEqualToString:@"ds"])
	{
		WRITE_AVX_STATE(avxState, newVariable, ds);
	}
	else if ([registerName isEqualToString:@"mxcsr"])
	{
		WRITE_AVX_STATE(avxState, newVariable, mxcsr);
	}
	else if ([registerName isEqualToString:@"mxcsrmask"])
	{
		WRITE_AVX_STATE(avxState, newVariable, mxcsrmask);
	}
	else if ([registerName hasPrefix:@"stmm"])
	{
		int stmmIndexValue = [[registerName substringFromIndex:[@"stmm" length]] intValue];
		memcpy((_STRUCT_MMST_REG *)&avxState.ufs.as64.__fpu_stmm0 + stmmIndexValue, newVariable.value, MIN(newVariable.size, sizeof(_STRUCT_MMST_REG)));
	}
	else if ([registerName hasPrefix:@"xmm"])
	{
		int xmmIndexValue = [[registerName substringFromIndex:[@"xmm" length]] intValue];
		memcpy((_STRUCT_XMM_REG *)&avxState.ufs.as64.__fpu_xmm0 + xmmIndexValue, newVariable.value, MIN(newVariable.size, sizeof(_STRUCT_XMM_REG)));
	}
	else if ([registerName hasPrefix:@"ymmh"])
	{
		int ymmhIndexValue = [[registerName substringFromIndex:[@"ymmh" length]] intValue];
		memcpy((_STRUCT_XMM_REG *)&avxState.ufs.as64.__fpu_ymmh0 + ymmhIndexValue, newVariable.value, MIN(newVariable.size, sizeof(_STRUCT_XMM_REG)));
	}
	else
	{
		return NO;
	}
	
	if (thread_set_state(self.breakPoint.thread, is64Bit ? x86_AVX_STATE64 : x86_AVX_STATE32, is64Bit ? (thread_state_t)&avxState.ufs.as64 : (thread_state_t)&avxState.ufs.as32, avxStateCount) != KERN_SUCCESS)
	{
		NSLog(@"Failure in setting registers thread state for writing register value (floating point): %d", self.breakPoint.thread);
		return NO;
	}
	
	self.breakPoint.avxState = avxState;
	
	theRegister.variable = newVariable;
	
	return YES;
}

- (BOOL)changeGeneralPurposeRegister:(ZGRegister *)theRegister oldVariable:(ZGVariable *)oldVariable newVariable:(ZGVariable *)newVariable
{
	x86_thread_state_t threadState;
	mach_msg_type_number_t threadStateCount = x86_THREAD_STATE_COUNT;
	if (thread_get_state(self.breakPoint.thread, x86_THREAD_STATE, (thread_state_t)&threadState, &threadStateCount) != KERN_SUCCESS)
	{
		return NO;
	}
	
	BOOL shouldWriteRegister = NO;
	if (self.breakPoint.process.is64Bit)
	{
		NSArray *registers64 = @[@"rax", @"rbx", @"rcx", @"rdx", @"rdi", @"rsi", @"rbp", @"rsp", @"r8", @"r9", @"r10", @"r11", @"r12", @"r13", @"r14", @"r15", @"rip", @"rflags", @"cs", @"fs", @"gs"];
		if ([registers64 containsObject:theRegister.variable.name])
		{
			memcpy((uint64_t *)&threadState.uts.ts64 + [registers64 indexOfObject:theRegister.variable.name], newVariable.value, MIN(newVariable.size, sizeof(uint64_t)));
			shouldWriteRegister = YES;
		}
	}
	else
	{
		NSArray *registers32 = @[@"eax", @"ebx", @"ecx", @"edx", @"edi", @"esi", @"ebp", @"esp", @"ss", @"eflags", @"eip", @"cs", @"ds", @"es", @"fs", @"gs"];
		if ([registers32 containsObject:theRegister.variable.name])
		{
			memcpy((uint32_t *)&threadState.uts.ts32 + [registers32 indexOfObject:theRegister.variable.name], newVariable.value, MIN(newVariable.size, sizeof(uint32_t)));
			shouldWriteRegister = YES;
		}
	}
	
	if (!shouldWriteRegister) return NO;
	
	if (thread_set_state(self.breakPoint.thread, x86_THREAD_STATE, (thread_state_t)&threadState, threadStateCount) != KERN_SUCCESS)
	{
		NSLog(@"Failure in setting registers thread state for writing register value (general purpose): %d", self.breakPoint.thread);
		return NO;
	}
	
	self.breakPoint.generalPurposeThreadState = threadState;
	
	theRegister.variable = newVariable;
	
	if ([theRegister.variable.name isEqualToString:@"rip"])
	{
		self.programCounter = *(uint64_t *)theRegister.value;
	}
	else if ([theRegister.variable.name isEqualToString:@"eip"])
	{
		self.programCounter = *(uint32_t *)theRegister.value;
	}
	
	return YES;
}

- (void)changeRegister:(ZGRegister *)theRegister oldVariable:(ZGVariable *)oldVariable newVariable:(ZGVariable *)newVariable
{
	BOOL success = NO;
	switch (theRegister.registerType)
	{
		case ZGRegisterGeneralPurpose:
			success = [self changeGeneralPurposeRegister:theRegister oldVariable:oldVariable newVariable:newVariable];
			break;
		case ZGRegisterAVX:
			success = [self changeFloatingPointRegister:theRegister oldVariable:oldVariable newVariable:newVariable];
			break;
	}
	
	if (success)
	{
		[[self.debuggerController.undoManager prepareWithInvocationTarget:self] changeRegister:theRegister oldVariable:newVariable newVariable:oldVariable];
		[self.debuggerController.undoManager setActionName:@"Register Value Change"];
		
		[self.tableView reloadData];
	}
}

#pragma mark TableView Methods

- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard
{
	NSArray *variables = [[self.registers objectsAtIndexes:rowIndexes] valueForKey:@"variable"];
	return [pboard setData:[NSKeyedArchiver archivedDataWithRootObject:variables] forType:ZGVariablePboardType];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return self.registers.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	id result = nil;
	if (rowIndex >= 0 && (NSUInteger)rowIndex < self.registers.count)
	{
		ZGRegister *theRegister = [self.registers objectAtIndex:rowIndex];
		if ([tableColumn.identifier isEqualToString:@"name"])
		{
			result = theRegister.variable.name;
		}
		else if ([tableColumn.identifier isEqualToString:@"value"])
		{
			result = [theRegister.variable stringValue];
		}
		else if ([tableColumn.identifier isEqualToString:@"type"])
		{
			return @([[tableColumn dataCell] indexOfItemWithTag:theRegister.variable.type]);
		}
	}
	
	return result;
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if (rowIndex >= 0 && (NSUInteger)rowIndex < self.registers.count)
	{
		ZGRegister *theRegister = [self.registers objectAtIndex:rowIndex];
		if ([tableColumn.identifier isEqualToString:@"value"])
		{
			ZGMemorySize size;
			void *newValue = ZGValueFromString(self.breakPoint.process.is64Bit, object, theRegister.variable.type, &size);
			if (newValue != NULL)
			{
				[self
				 changeRegister:theRegister
				 oldVariable:theRegister.variable
				 newVariable:
				 [[ZGVariable alloc]
				  initWithValue:newValue
				  size:size
				  address:theRegister.variable.address
				  type:theRegister.variable.type
				  qualifier:theRegister.variable.qualifier
				  pointerSize:self.breakPoint.process.pointerSize
				  description:theRegister.variable.description
				  enabled:NO]];
				
				free(newValue);
			}
		}
		else if ([tableColumn.identifier isEqualToString:@"type"])
		{
			ZGVariableType newType = (ZGVariableType)[[[tableColumn.dataCell itemArray] objectAtIndex:[object unsignedIntegerValue]] tag];
			[self changeRegister:theRegister oldType:theRegister.variable.type newType:newType];
		}
	}
}

- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if ([tableColumn.identifier isEqualToString:@"value"])
	{
		if (rowIndex < 0 || (NSUInteger)rowIndex >= self.registers.count)
		{
			return NO;
		}
		
		ZGRegister *theRegister = [self.registers objectAtIndex:rowIndex];
		if (!theRegister.variable.value)
		{
			return NO;
		}
	}
	
	return YES;
}

#pragma mark Menu Items

- (IBAction)changeQualifier:(id)sender
{
	if (self.qualifier != [sender tag])
	{
		self.qualifier = [sender tag];
		[[NSUserDefaults standardUserDefaults] setInteger:self.qualifier forKey:ZG_DEBUG_QUALIFIER];
		for (ZGRegister *theRegister in self.registers)
		{
			theRegister.variable.qualifier = self.qualifier;
		}
		
		[self.tableView reloadData];
	}
}

- (BOOL)validateUserInterfaceItem:(NSMenuItem *)menuItem
{
	if (menuItem.action == @selector(changeQualifier:))
	{
		[menuItem setState:self.qualifier == [menuItem tag]];
	}
	else if (menuItem.action == @selector(copy:))
	{
		if (self.selectedRegisters.count == 0)
		{
			return NO;
		}
	}
	
	return YES;
}

#pragma mark Copy

- (NSArray *)selectedRegisters
{
	NSIndexSet *tableIndexSet = self.tableView.selectedRowIndexes;
	NSInteger clickedRow = self.tableView.clickedRow;
	
	NSIndexSet *selectionIndexSet = (clickedRow != -1 && ![tableIndexSet containsIndex:clickedRow]) ? [NSIndexSet indexSetWithIndex:clickedRow] : tableIndexSet;
	
	return [self.registers objectsAtIndexes:selectionIndexSet];
}

- (IBAction)copy:(id)sender
{
	NSMutableArray *descriptionComponents = [[NSMutableArray alloc] init];
	NSMutableArray *variablesArray = [[NSMutableArray alloc] init];
	
	for (ZGRegister *theRegister in self.selectedRegisters)
	{
		[descriptionComponents addObject:[@[theRegister.variable.name, theRegister.variable.stringValue] componentsJoinedByString:@"\t"]];
		[variablesArray addObject:theRegister.variable];
	}
	
	[[NSPasteboard generalPasteboard] declareTypes:@[NSStringPboardType, ZGVariablePboardType] owner:self];
	[[NSPasteboard generalPasteboard] setString:[descriptionComponents componentsJoinedByString:@"\n"] forType:NSStringPboardType];
	[[NSPasteboard generalPasteboard] setData:[NSKeyedArchiver archivedDataWithRootObject:variablesArray] forType:ZGVariablePboardType];
}

@end
