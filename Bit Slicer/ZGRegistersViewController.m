/*
 * Created by Mayur Pawashe on 2/22/14.
 *
 * Copyright (c) 2014 zgcoder
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

#import "ZGRegistersViewController.h"

#import "ZGVariable.h"
#import "ZGBreakPoint.h"
#import "ZGProcess.h"
#import "ZGUtilities.h"
#import "ZGRegister.h"
#import "ZGRegisterEntries.h"

#define ZG_REGISTER_TYPES @"ZG_REGISTER_TYPES"
#define ZG_DEBUG_QUALIFIER @"ZG_DEBUG_QUALIFIER"

@interface ZGRegistersViewController ()

@property (assign, nonatomic) IBOutlet NSTableView *tableView;
@property (weak, nonatomic) NSUndoManager *undoManager;

@property (nonatomic) NSArray *registers;
@property (nonatomic) ZGBreakPoint *breakPoint;
@property (nonatomic) ZGVariableQualifier qualifier;

@property (nonatomic) ZGMemoryAddress instructionPointer;

@end

@implementation ZGRegistersViewController

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		[[NSUserDefaults standardUserDefaults] registerDefaults:@{ZG_REGISTER_TYPES : @{}, ZG_DEBUG_QUALIFIER : @0}];
	});
}

- (id)initWithUndoManager:(NSUndoManager *)undoManager
{
	self = [super initWithNibName:NSStringFromClass([self class]) bundle:nil];
	if (self != nil)
	{
		self.undoManager = undoManager;
	}
	return self;
}

- (void)loadView
{
	[super loadView];
	
	[self setNextResponder:[self.tableView nextResponder]];
	[self.tableView setNextResponder:self];
	
	[self.tableView registerForDraggedTypes:@[ZGVariablePboardType]];
}

- (void)changeInstructionPointer:(ZGMemoryAddress)newInstructionPointer
{
	if (self.instructionPointer == newInstructionPointer)
	{
		return;
	}
	
	for (ZGRegister *theRegister in self.registers)
	{
		if ([@[@"eip", @"rip"] containsObject:theRegister.variable.name])
		{
			ZGVariable *newVariable = [theRegister.variable copy];
			
			if (self.breakPoint.process.is64Bit)
			{
				[newVariable setRawValue:&newInstructionPointer];
			}
			else
			{
				ZG32BitMemoryAddress memoryAddress = (ZG32BitMemoryAddress)newInstructionPointer;
				[newVariable setRawValue:&memoryAddress];
			}
			
			[self changeRegister:theRegister oldVariable:theRegister.variable newVariable:newVariable];
			break;
		}
	}
}

- (ZGMemoryAddress)basePointer
{
	ZGMemoryAddress basePointer = 0x0;
	
	x86_thread_state_t threadState;
	mach_msg_type_number_t threadStateCount;
	if (ZGGetGeneralThreadState(&threadState, self.breakPoint.thread, &threadStateCount))
	{
		basePointer = self.breakPoint.process.is64Bit ? threadState.uts.ts64.__rbp : threadState.uts.ts32.__ebp;
	}
	
	return basePointer;
}

- (void)updateRegistersFromBreakPoint:(ZGBreakPoint *)breakPoint
{
	self.breakPoint = breakPoint;
	
	ZGMemorySize pointerSize = breakPoint.process.pointerSize;
	NSDictionary *registerDefaultsDictionary = [[NSUserDefaults standardUserDefaults] objectForKey:ZG_REGISTER_TYPES];
	
	NSMutableArray *newRegisters = [NSMutableArray array];
	
	NSArray *registerVariables = [ZGRegisterEntries registerVariablesFromGeneralPurposeThreadState:breakPoint.generalPurposeThreadState is64Bit:breakPoint.process.is64Bit];
	
	for (ZGVariable *registerVariable in registerVariables)
	{
		[registerVariable setQualifier:self.qualifier];
		
		ZGRegister *newRegister = [[ZGRegister alloc] initWithRegisterType:ZGRegisterGeneralPurpose variable:registerVariable pointerSize:pointerSize];
		
		NSNumber *registerDefaultType = [registerDefaultsDictionary objectForKey:registerVariable.name];
		if (registerDefaultType != nil && [registerDefaultType intValue] != ZGByteArray)
		{
			[newRegister.variable setType:(ZGVariableType)[registerDefaultType intValue] requestedSize:newRegister.size pointerSize:pointerSize];
			[newRegister.variable setRawValue:newRegister.rawValue];
		}
		
		[newRegisters addObject:newRegister];
	}
	
	self.instructionPointer = breakPoint.process.is64Bit ? breakPoint.generalPurposeThreadState.uts.ts64.__rip : breakPoint.generalPurposeThreadState.uts.ts32.__eip;
	
	if (breakPoint.hasVectorState)
	{
		NSArray *registerVectorVariables = [ZGRegisterEntries registerVariablesFromVectorThreadState:breakPoint.vectorState is64Bit:breakPoint.process.is64Bit hasAVXSupport:breakPoint.hasAVXSupport];
		for (ZGVariable *registerVariable in registerVectorVariables)
		{
			ZGRegister *newRegister = [[ZGRegister alloc] initWithRegisterType:ZGRegisterVector variable:registerVariable pointerSize:pointerSize];
			
			NSNumber *registerDefaultType = [registerDefaultsDictionary objectForKey:registerVariable.name];
			if (registerDefaultType != nil && [registerDefaultType intValue] != ZGByteArray)
			{
				[newRegister.variable setType:(ZGVariableType)[registerDefaultType intValue] requestedSize:newRegister.size pointerSize:pointerSize];
				[newRegister.variable setRawValue:newRegister.rawValue];
			}
			
			[newRegisters addObject:newRegister];
		}
	}
	
	self.registers = [NSArray arrayWithArray:newRegisters];
	
	[self.tableView reloadData];
}

- (void)changeRegister:(ZGRegister *)theRegister oldType:(ZGVariableType)oldType newType:(ZGVariableType)newType
{
	[theRegister.variable setType:newType requestedSize:theRegister.size pointerSize:self.breakPoint.process.pointerSize];
	[theRegister.variable setRawValue:theRegister.rawValue];
	
	NSMutableDictionary *registerTypesDictionary = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] objectForKey:ZG_REGISTER_TYPES]];
	[registerTypesDictionary setObject:@(theRegister.variable.type) forKey:theRegister.variable.name];
	[[NSUserDefaults standardUserDefaults] setObject:registerTypesDictionary forKey:ZG_REGISTER_TYPES];
	
	NSUndoManager *undoManager = self.undoManager;
	[[undoManager prepareWithInvocationTarget:self] changeRegister:theRegister oldType:newType newType:oldType];
	[undoManager setActionName:@"Register Type Change"];
	
	[self.tableView reloadData];
}

#define WRITE_VECTOR_STATE(vectorState, variable, registerName) memcpy(&vectorState.ufs.as64.__fpu_##registerName, variable.rawValue, MIN(variable.size, sizeof(vectorState.ufs.as64.__fpu_##registerName)))

- (BOOL)changeFloatingPointRegister:(ZGRegister *)theRegister newVariable:(ZGVariable *)newVariable
{
	BOOL is64Bit = self.breakPoint.process.is64Bit;
	
	zg_x86_vector_state_t vectorState;
	mach_msg_type_number_t vectorStateCount;
	if (!ZGGetVectorThreadState(&vectorState, self.breakPoint.thread, &vectorStateCount, is64Bit, NULL))
	{
		return NO;
	}
	
	NSString *registerName = theRegister.variable.name;
	if ([registerName isEqualToString:@"fcw"])
	{
		WRITE_VECTOR_STATE(vectorState, newVariable, fcw);
	}
	else if ([registerName isEqualToString:@"fsw"])
	{
		WRITE_VECTOR_STATE(vectorState, newVariable, fsw);
	}
	else if ([registerName isEqualToString:@"fop"])
	{
		WRITE_VECTOR_STATE(vectorState, newVariable, fop);
	}
	else if ([registerName isEqualToString:@"ip"])
	{
		WRITE_VECTOR_STATE(vectorState, newVariable, ip);
	}
	else if ([registerName isEqualToString:@"cs"])
	{
		WRITE_VECTOR_STATE(vectorState, newVariable, cs);
	}
	else if ([registerName isEqualToString:@"dp"])
	{
		WRITE_VECTOR_STATE(vectorState, newVariable, dp);
	}
	else if ([registerName isEqualToString:@"ds"])
	{
		WRITE_VECTOR_STATE(vectorState, newVariable, ds);
	}
	else if ([registerName isEqualToString:@"mxcsr"])
	{
		WRITE_VECTOR_STATE(vectorState, newVariable, mxcsr);
	}
	else if ([registerName isEqualToString:@"mxcsrmask"])
	{
		WRITE_VECTOR_STATE(vectorState, newVariable, mxcsrmask);
	}
	else if ([registerName hasPrefix:@"stmm"])
	{
		int stmmIndexValue = [[registerName substringFromIndex:[@"stmm" length]] intValue];
		memcpy((_STRUCT_MMST_REG *)&vectorState.ufs.as64.__fpu_stmm0 + stmmIndexValue, newVariable.rawValue, MIN(newVariable.size, sizeof(_STRUCT_MMST_REG)));
	}
	else if ([registerName hasPrefix:@"xmm"])
	{
		int xmmIndexValue = [[registerName substringFromIndex:[@"xmm" length]] intValue];
		memcpy((_STRUCT_XMM_REG *)&vectorState.ufs.as64.__fpu_xmm0 + xmmIndexValue, newVariable.rawValue, MIN(newVariable.size, sizeof(_STRUCT_XMM_REG)));
	}
	else if ([registerName hasPrefix:@"ymmh"])
	{
		int ymmhIndexValue = [[registerName substringFromIndex:[@"ymmh" length]] intValue];
		memcpy((_STRUCT_XMM_REG *)&vectorState.ufs.as64.__fpu_ymmh0 + ymmhIndexValue, newVariable.rawValue, MIN(newVariable.size, sizeof(_STRUCT_XMM_REG)));
	}
	else
	{
		return NO;
	}
	
	if (!ZGSetVectorThreadState(&vectorState, self.breakPoint.thread, vectorStateCount, is64Bit))
	{
		NSLog(@"Failure in setting registers thread state for writing register value (floating point): %d", self.breakPoint.thread);
		return NO;
	}
	
	self.breakPoint.vectorState = vectorState;
	
	theRegister.variable = newVariable;
	
	return YES;
}

- (BOOL)changeGeneralPurposeRegister:(ZGRegister *)theRegister newVariable:(ZGVariable *)newVariable
{
	x86_thread_state_t threadState;
	mach_msg_type_number_t threadStateCount;
	if (!ZGGetGeneralThreadState(&threadState, self.breakPoint.thread, &threadStateCount))
	{
		return NO;
	}
	
	BOOL shouldWriteRegister = NO;
	if (self.breakPoint.process.is64Bit)
	{
		NSArray *registers64 = @[@"rax", @"rbx", @"rcx", @"rdx", @"rdi", @"rsi", @"rbp", @"rsp", @"r8", @"r9", @"r10", @"r11", @"r12", @"r13", @"r14", @"r15", @"rip", @"rflags", @"cs", @"fs", @"gs"];
		if ([registers64 containsObject:theRegister.variable.name])
		{
			memcpy((uint64_t *)&threadState.uts.ts64 + [registers64 indexOfObject:theRegister.variable.name], newVariable.rawValue, MIN(newVariable.size, sizeof(uint64_t)));
			shouldWriteRegister = YES;
		}
	}
	else
	{
		NSArray *registers32 = @[@"eax", @"ebx", @"ecx", @"edx", @"edi", @"esi", @"ebp", @"esp", @"ss", @"eflags", @"eip", @"cs", @"ds", @"es", @"fs", @"gs"];
		if ([registers32 containsObject:theRegister.variable.name])
		{
			memcpy((uint32_t *)&threadState.uts.ts32 + [registers32 indexOfObject:theRegister.variable.name], newVariable.rawValue, MIN(newVariable.size, sizeof(uint32_t)));
			shouldWriteRegister = YES;
		}
	}
	
	if (!shouldWriteRegister) return NO;
	
	if (!ZGSetGeneralThreadState(&threadState, self.breakPoint.thread, threadStateCount))
	{
		NSLog(@"Failure in setting registers thread state for writing register value (general purpose): %d", self.breakPoint.thread);
		return NO;
	}
	
	self.breakPoint.generalPurposeThreadState = threadState;
	
	theRegister.variable = newVariable;
	
	if ([theRegister.variable.name isEqualToString:@"rip"])
	{
		self.instructionPointer = *(uint64_t *)theRegister.rawValue;
	}
	else if ([theRegister.variable.name isEqualToString:@"eip"])
	{
		self.instructionPointer = *(uint32_t *)theRegister.rawValue;
	}
	
	return YES;
}

- (void)changeRegister:(ZGRegister *)theRegister oldVariable:(ZGVariable *)oldVariable newVariable:(ZGVariable *)newVariable
{
	BOOL success = NO;
	switch (theRegister.registerType)
	{
		case ZGRegisterGeneralPurpose:
			success = [self changeGeneralPurposeRegister:theRegister newVariable:newVariable];
			break;
		case ZGRegisterVector:
			success = [self changeFloatingPointRegister:theRegister newVariable:newVariable];
			break;
	}
	
	if (success)
	{
		NSUndoManager *undoManager = self.undoManager;
		[[undoManager prepareWithInvocationTarget:self] changeRegister:theRegister oldVariable:newVariable newVariable:oldVariable];
		[undoManager setActionName:@"Register Value Change"];
		
		[self.tableView reloadData];
	}
}

#pragma mark TableView Methods

- (BOOL)tableView:(NSTableView *)__unused tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard
{
	NSArray *variables = [[self.registers objectsAtIndexes:rowIndexes] valueForKey:@"variable"];
	return [pboard setData:[NSKeyedArchiver archivedDataWithRootObject:variables] forType:ZGVariablePboardType];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)__unused tableView
{
	return (NSInteger)self.registers.count;
}

- (id)tableView:(NSTableView *)__unused tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	id result = nil;
	if (rowIndex >= 0 && (NSUInteger)rowIndex < self.registers.count)
	{
		ZGRegister *theRegister = [self.registers objectAtIndex:(NSUInteger)rowIndex];
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

- (void)tableView:(NSTableView *)__unused tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if (rowIndex >= 0 && (NSUInteger)rowIndex < self.registers.count)
	{
		ZGRegister *theRegister = [self.registers objectAtIndex:(NSUInteger)rowIndex];
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
				  description:theRegister.variable.fullAttributedDescription
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

- (BOOL)tableView:(NSTableView *)__unused tableView shouldEditTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if ([tableColumn.identifier isEqualToString:@"value"])
	{
		if (rowIndex < 0 || (NSUInteger)rowIndex >= self.registers.count)
		{
			return NO;
		}
		
		ZGRegister *theRegister = [self.registers objectAtIndex:(NSUInteger)rowIndex];
		if (theRegister.variable.rawValue == nil)
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
		self.qualifier = (ZGVariableQualifier)[sender tag];
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
	
	NSIndexSet *selectionIndexSet = (clickedRow >= 0 && ![tableIndexSet containsIndex:(NSUInteger)clickedRow]) ? [NSIndexSet indexSetWithIndex:(NSUInteger)clickedRow] : tableIndexSet;
	
	return [self.registers objectsAtIndexes:selectionIndexSet];
}

- (IBAction)copy:(id)__unused sender
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
