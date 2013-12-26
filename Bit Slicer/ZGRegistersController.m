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

#define ADD_GENERAL_REGISTER(array, threadState, registerSize, registerName, structureType) \
[array addObject:[[ZGVariable alloc] initWithValue:&threadState.uts.structureType.__##registerName size:registerSize address:threadState.uts.structureType.__##registerName type:ZGByteArray qualifier:0 pointerSize:registerSize name:@(#registerName) enabled:NO]]

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
	
	x86_thread_state_t threadState;
	mach_msg_type_number_t threadStateCount = x86_THREAD_STATE_COUNT;
	if (thread_get_state(self.breakPoint.thread, x86_THREAD_STATE, (thread_state_t)&threadState, &threadStateCount) == KERN_SUCCESS)
	{
		NSArray *registerVariables = [[self class] registerVariablesFromGeneralPurposeThreadState:threadState is64Bit:breakPoint.process.is64Bit];
		NSMutableArray *registers = [[NSMutableArray alloc] init];
		
		ZGMemorySize pointerSize = breakPoint.process.pointerSize;
		NSDictionary *registerDefaultsDictionary = [[NSUserDefaults standardUserDefaults] objectForKey:ZG_REGISTER_TYPES];
		for (ZGVariable *registerVariable in registerVariables)
		{
			ZGRegister *newRegister = [[ZGRegister alloc] initWithVariable:registerVariable];
			
			NSNumber *registerDefaultType = [registerDefaultsDictionary objectForKey:registerVariable.name];
			if (registerDefaultType != nil && [registerDefaultType intValue] != ZGByteArray)
			{
				[registerVariable setType:[registerDefaultType intValue] requestedSize:pointerSize pointerSize:pointerSize];
			}
			
			[registerVariable setQualifier:self.qualifier];
			
			if (pointerSize >= registerVariable.size)
			{
				[registerVariable setValue:newRegister.value];
			}
			
			[registers addObject:newRegister];
		}
		
		self.registers = [NSArray arrayWithArray:registers];
		
		if (breakPoint.process.is64Bit)
		{
			self.programCounter = threadState.uts.ts64.__rip;
		}
		else
		{
			self.programCounter = threadState.uts.ts32.__eip;
		}
	}
	else
	{
		self.registers = nil;
	}
	
	self.programCounterChangeBlock = programCounterChangeBlock;
	
	[self.tableView reloadData];
}

- (void)changeRegister:(ZGRegister *)theRegister oldType:(ZGVariableType)oldType newType:(ZGVariableType)newType
{
	[theRegister.variable
	 setType:newType
	 requestedSize:self.breakPoint.process.pointerSize
	 pointerSize:self.breakPoint.process.pointerSize];
	
	if (self.breakPoint.process.pointerSize >= theRegister.variable.size)
	{
		[theRegister.variable setValue:theRegister.value];
	}
	
	NSMutableDictionary *registerTypesDictionary = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] objectForKey:ZG_REGISTER_TYPES]];
	[registerTypesDictionary setObject:@(theRegister.variable.type) forKey:theRegister.variable.name];
	[[NSUserDefaults standardUserDefaults] setObject:registerTypesDictionary forKey:ZG_REGISTER_TYPES];
	
	[[self.debuggerController.undoManager prepareWithInvocationTarget:self] changeRegister:theRegister oldType:newType newType:oldType];
	[self.debuggerController.undoManager setActionName:@"Register Type Change"];
	
	[self.tableView reloadData];
}

- (void)changeRegister:(ZGRegister *)theRegister oldVariable:(ZGVariable *)oldVariable newVariable:(ZGVariable *)newVariable
{
	x86_thread_state_t threadState;
	mach_msg_type_number_t threadStateCount = x86_THREAD_STATE_COUNT;
	if (thread_get_state(self.breakPoint.thread, x86_THREAD_STATE, (thread_state_t)&threadState, &threadStateCount) == KERN_SUCCESS)
	{
		BOOL shouldWriteRegister = NO;
		if (self.breakPoint.process.is64Bit)
		{
			NSArray *registers64 = @[@"rax", @"rbx", @"rcx", @"rdx", @"rdi", @"rsi", @"rbp", @"rsp", @"r8", @"r9", @"r10", @"r11", @"r12", @"r13", @"r14", @"r15", @"rip", @"rflags", @"cs", @"fs", @"gs"];
			if ([registers64 containsObject:theRegister.variable.name])
			{
				memcpy((uint64_t *)&threadState.uts.ts64 + [registers64 indexOfObject:theRegister.variable.name], newVariable.value, newVariable.size);
				shouldWriteRegister = YES;
			}
		}
		else
		{
			NSArray *registers32 = @[@"eax", @"ebx", @"ecx", @"edx", @"edi", @"esi", @"ebp", @"esp", @"ss", @"eflags", @"eip", @"cs", @"ds", @"es", @"fs", @"gs"];
			if ([registers32 containsObject:theRegister.variable.name])
			{
				memcpy((uint32_t *)&threadState.uts.ts32 + [registers32 indexOfObject:theRegister.variable.name], newVariable.value, newVariable.size);
				shouldWriteRegister = YES;
			}
		}
		
		if (shouldWriteRegister)
		{
			if (thread_set_state(self.breakPoint.thread, x86_THREAD_STATE, (thread_state_t)&threadState, threadStateCount) != KERN_SUCCESS)
			{
				NSLog(@"Failure in setting registers thread state for writing register value: %d", self.breakPoint.thread);
			}
			else
			{
				theRegister.variable = newVariable;
				memcpy(theRegister.value, theRegister.variable.value, theRegister.variable.size);
				
				if ([theRegister.variable.name isEqualToString:@"rip"])
				{
					self.programCounter = *(uint64_t *)theRegister.value;
				}
				else if ([theRegister.variable.name isEqualToString:@"eip"])
				{
					self.programCounter = *(uint32_t *)theRegister.value;
				}
				
				[[self.debuggerController.undoManager prepareWithInvocationTarget:self] changeRegister:theRegister oldVariable:newVariable newVariable:oldVariable];
				[self.debuggerController.undoManager setActionName:@"Register Value Change"];
				
				[self.tableView reloadData];
			}
		}
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
			if (newValue)
			{
				if (size <= self.breakPoint.process.pointerSize)
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
				}
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
