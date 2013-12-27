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
#import "ZGRegister.h"
#import "ZGPreferencesController.h"
#import "ZGUtilities.h"
#import "ZGDebuggerController.h"

#import <mach/thread_act.h>

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

#define ADD_FLOATING_POINT_REGISTER(array, floatState, pointerSize, registerName) \
[array addObject:[[ZGVariable alloc] initWithValue:&floatState.ufs.fs64.__fpu_##registerName size:sizeof(floatState.ufs.fs64.__fpu_##registerName) address:0 type:ZGByteArray qualifier:0 pointerSize:pointerSize name:@(#registerName) enabled:NO]]

+ (NSArray *)registerVariablesFromFloatingPointThreadState:(x86_float_state_t)floatState is64Bit:(BOOL)is64Bit
{
	NSMutableArray *registerVariables = [[NSMutableArray alloc] init];
	ZGMemorySize pointerSize = is64Bit ? sizeof(int64_t) : sizeof(int32_t);
	
	ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, fcw); // FPU control word
	ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, fsw); // FPU status word
	ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, ftw); // FPU tag word
	ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, fop); // FPU Opcode
	
	// Instruction Pointer
	ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, ip); // offset
	ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, cs); // selector
	
	// Instruction operand (data) pointer
	ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, dp); // offset
	ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, ds); // selector
	
	ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, mxcsr); // MXCSR Register state
	ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, mxcsrmask); // MXCSR mask
	
	// STX/MMX
	ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, stmm0);
	ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, stmm1);
	ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, stmm2);
	ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, stmm3);
	ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, stmm4);
	ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, stmm5);
	ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, stmm6);
	ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, stmm7);
	
	// XMM 0 through 7
	ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, xmm0);
	ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, xmm1);
	ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, xmm2);
	ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, xmm3);
	ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, xmm4);
	ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, xmm5);
	ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, xmm6);
	ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, xmm7);
	
	if (is64Bit)
	{
		// XMM 8 through 15
		ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, xmm8);
		ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, xmm9);
		ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, xmm10);
		ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, xmm11);
		ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, xmm12);
		ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, xmm13);
		ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, xmm14);
		ADD_FLOATING_POINT_REGISTER(registerVariables, floatState, pointerSize, xmm15);
	}
	
	return registerVariables;
}

#define ADD_GENERAL_REGISTER(array, threadState, _pointerSize, registerName, structureType) \
[array addObject:[[ZGVariable alloc] initWithValue:&threadState.uts.structureType.__##registerName size:sizeof(threadState.uts.structureType.__##registerName) address:threadState.uts.structureType.__##registerName type:ZGByteArray qualifier:0 pointerSize:_pointerSize name:@(#registerName) enabled:NO]]

#define ADD_GENERAL_REGISTER_32(array, threadState, registerName) ADD_GENERAL_REGISTER(array, threadState, sizeof(int32_t), registerName, ts32)
#define ADD_GENERAL_REGISTER_64(array, threadState, registerName) ADD_GENERAL_REGISTER(array, threadState, sizeof(int64_t), registerName, ts64)

+ (NSArray *)registerVariablesFromGeneralPurposeThreadState:(x86_thread_state_t)threadState is64Bit:(BOOL)is64Bit
{
	NSMutableArray *registerVariables = [[NSMutableArray alloc] init];
	
	if (is64Bit)
	{
		// General registers
		ADD_GENERAL_REGISTER_64(registerVariables, threadState, rax);
		ADD_GENERAL_REGISTER_64(registerVariables, threadState, rbx);
		ADD_GENERAL_REGISTER_64(registerVariables, threadState, rcx);
		ADD_GENERAL_REGISTER_64(registerVariables, threadState, rdx);
		
		// Index and pointers
		ADD_GENERAL_REGISTER_64(registerVariables, threadState, rdi);
		ADD_GENERAL_REGISTER_64(registerVariables, threadState, rsi);
		ADD_GENERAL_REGISTER_64(registerVariables, threadState, rbp);
		ADD_GENERAL_REGISTER_64(registerVariables, threadState, rsp);
		
		// Extra registers
		ADD_GENERAL_REGISTER_64(registerVariables, threadState, r8);
		ADD_GENERAL_REGISTER_64(registerVariables, threadState, r9);
		ADD_GENERAL_REGISTER_64(registerVariables, threadState, r10);
		ADD_GENERAL_REGISTER_64(registerVariables, threadState, r11);
		ADD_GENERAL_REGISTER_64(registerVariables, threadState, r12);
		ADD_GENERAL_REGISTER_64(registerVariables, threadState, r13);
		ADD_GENERAL_REGISTER_64(registerVariables, threadState, r14);
		ADD_GENERAL_REGISTER_64(registerVariables, threadState, r15);
		
		// Instruction pointer
		ADD_GENERAL_REGISTER_64(registerVariables, threadState, rip);
		
		// Flags indicator
		ADD_GENERAL_REGISTER_64(registerVariables, threadState, rflags);
		
		// Segment registers
		ADD_GENERAL_REGISTER_64(registerVariables, threadState, cs);
		ADD_GENERAL_REGISTER_64(registerVariables, threadState, fs);
		ADD_GENERAL_REGISTER_64(registerVariables, threadState, gs);
	}
	else
	{
		// General registers
		ADD_GENERAL_REGISTER_32(registerVariables, threadState, eax);
		ADD_GENERAL_REGISTER_32(registerVariables, threadState, ebx);
		ADD_GENERAL_REGISTER_32(registerVariables, threadState, ecx);
		ADD_GENERAL_REGISTER_32(registerVariables, threadState, edx);
		
		// Index and pointers
		ADD_GENERAL_REGISTER_32(registerVariables, threadState, edi);
		ADD_GENERAL_REGISTER_32(registerVariables, threadState, esi);
		ADD_GENERAL_REGISTER_32(registerVariables, threadState, ebp);
		ADD_GENERAL_REGISTER_32(registerVariables, threadState, esp);
		
		// Segment register
		ADD_GENERAL_REGISTER_32(registerVariables, threadState, ss);
		
		// Flags indicator
		ADD_GENERAL_REGISTER_32(registerVariables, threadState, eflags);
		
		// Instruction pointer
		ADD_GENERAL_REGISTER_32(registerVariables, threadState, eip);
		
		// Segment registers
		ADD_GENERAL_REGISTER_32(registerVariables, threadState, cs);
		ADD_GENERAL_REGISTER_32(registerVariables, threadState, ds);
		ADD_GENERAL_REGISTER_32(registerVariables, threadState, es);
		ADD_GENERAL_REGISTER_32(registerVariables, threadState, fs);
		ADD_GENERAL_REGISTER_32(registerVariables, threadState, gs);
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
	
	x86_thread_state_t threadState;
	mach_msg_type_number_t threadStateCount = x86_THREAD_STATE_COUNT;
	if (thread_get_state(self.breakPoint.thread, x86_THREAD_STATE, (thread_state_t)&threadState, &threadStateCount) == KERN_SUCCESS)
	{
		NSArray *registerVariables = [[self class] registerVariablesFromGeneralPurposeThreadState:threadState is64Bit:breakPoint.process.is64Bit];
		
		for (ZGVariable *registerVariable in registerVariables)
		{
			[registerVariable setQualifier:self.qualifier];
			
			ZGRegister *newRegister = [[ZGRegister alloc] initWithRegisterType:ZGRegisterGeneralPurpose variable:registerVariable pointerSize:pointerSize];
			
			NSNumber *registerDefaultType = [registerDefaultsDictionary objectForKey:registerVariable.name];
			if (registerDefaultType != nil && [registerDefaultType intValue] != ZGByteArray)
			{
				[newRegister.variable setType:[registerDefaultType intValue] requestedSize:newRegister.size pointerSize:pointerSize];
				[newRegister.variable setValue:[newRegister copyOfValue]];
			}
			
			[newRegisters addObject:newRegister];
		}
		
		if (breakPoint.process.is64Bit)
		{
			self.programCounter = threadState.uts.ts64.__rip;
		}
		else
		{
			self.programCounter = threadState.uts.ts32.__eip;
		}
	}
	
	x86_float_state_t floatState;
	mach_msg_type_number_t floatStateCount = x86_FLOAT_STATE_COUNT;
	if (thread_get_state(self.breakPoint.thread, x86_FLOAT_STATE, (thread_state_t)&floatState, &floatStateCount) == KERN_SUCCESS)
	{
		NSArray *registerVariables = [[self class] registerVariablesFromFloatingPointThreadState:floatState is64Bit:breakPoint.process.is64Bit];
		
		for (ZGVariable *registerVariable in registerVariables)
		{
			ZGRegister *newRegister = [[ZGRegister alloc] initWithRegisterType:ZGRegisterFloatingPoint variable:registerVariable pointerSize:pointerSize];
			
			NSNumber *registerDefaultType = [registerDefaultsDictionary objectForKey:registerVariable.name];
			if (registerDefaultType != nil && [registerDefaultType intValue] != ZGByteArray)
			{
				[newRegister.variable setType:[registerDefaultType intValue] requestedSize:newRegister.size pointerSize:pointerSize];
				[newRegister.variable setValue:[newRegister copyOfValue]];
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
	[theRegister.variable setValue:[theRegister copyOfValue]];
	
	NSMutableDictionary *registerTypesDictionary = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] objectForKey:ZG_REGISTER_TYPES]];
	[registerTypesDictionary setObject:@(theRegister.variable.type) forKey:theRegister.variable.name];
	[[NSUserDefaults standardUserDefaults] setObject:registerTypesDictionary forKey:ZG_REGISTER_TYPES];
	
	[[self.debuggerController.undoManager prepareWithInvocationTarget:self] changeRegister:theRegister oldType:newType newType:oldType];
	[self.debuggerController.undoManager setActionName:@"Register Type Change"];
	
	[self.tableView reloadData];
}

#define WRITE_FLOAT_STATE(floatState, variable, registerName) memcpy(&floatState.ufs.fs64.__fpu_##registerName, variable.value, MIN(variable.size, sizeof(floatState.ufs.fs64.__fpu_##registerName)))

- (BOOL)changeFloatingPointRegister:(ZGRegister *)theRegister oldVariable:(ZGVariable *)oldVariable newVariable:(ZGVariable *)newVariable
{
	x86_float_state_t floatState;
	mach_msg_type_number_t floatStateCount = x86_FLOAT_STATE_COUNT;
	if (thread_get_state(self.breakPoint.thread, x86_FLOAT_STATE, (thread_state_t)&floatState, &floatStateCount) != KERN_SUCCESS)
	{
		return NO;
	}
	
	NSString *registerName = theRegister.variable.name;
	if ([registerName isEqualToString:@"fcw"])
	{
		WRITE_FLOAT_STATE(floatState, newVariable, fcw);
	}
	else if ([registerName isEqualToString:@"fsw"])
	{
		WRITE_FLOAT_STATE(floatState, newVariable, fsw);
	}
	else if ([registerName isEqualToString:@"fop"])
	{
		WRITE_FLOAT_STATE(floatState, newVariable, fop);
	}
	else if ([registerName isEqualToString:@"ip"])
	{
		WRITE_FLOAT_STATE(floatState, newVariable, ip);
	}
	else if ([registerName isEqualToString:@"cs"])
	{
		WRITE_FLOAT_STATE(floatState, newVariable, cs);
	}
	else if ([registerName isEqualToString:@"dp"])
	{
		WRITE_FLOAT_STATE(floatState, newVariable, dp);
	}
	else if ([registerName isEqualToString:@"ds"])
	{
		WRITE_FLOAT_STATE(floatState, newVariable, ds);
	}
	else if ([registerName isEqualToString:@"mxcsr"])
	{
		WRITE_FLOAT_STATE(floatState, newVariable, mxcsr);
	}
	else if ([registerName isEqualToString:@"mxcsrmask"])
	{
		WRITE_FLOAT_STATE(floatState, newVariable, mxcsrmask);
	}
	else if ([registerName hasPrefix:@"stmm"])
	{
		int stmmIndexValue = [[registerName substringFromIndex:[@"stmm" length]] intValue];
		memcpy((_STRUCT_MMST_REG *)&floatState.ufs.fs64.__fpu_stmm0 + stmmIndexValue, newVariable.value, MIN(newVariable.size, sizeof(_STRUCT_MMST_REG)));
	}
	else if ([registerName hasPrefix:@"xmm"])
	{
		int xmmIndexValue = [[registerName substringFromIndex:[@"xmm" length]] intValue];
		memcpy((_STRUCT_XMM_REG *)&floatState.ufs.fs64.__fpu_xmm0 + xmmIndexValue, newVariable.value, MIN(newVariable.size, sizeof(_STRUCT_XMM_REG)));
	}
	else
	{
		return NO;
	}
	
	if (thread_set_state(self.breakPoint.thread, x86_FLOAT_STATE, (thread_state_t)&floatState, floatStateCount) != KERN_SUCCESS)
	{
		NSLog(@"Failure in setting registers thread state for writing register value (floating point): %d", self.breakPoint.thread);
		return NO;
	}
	
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
		case ZGRegisterFloatingPoint:
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
				  name:theRegister.variable.name
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
