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

#import "ZGRegistersViewController.h"

#import "ZGVariable.h"
#import "ZGBreakPoint.h"
#import "ZGRegistersState.h"
#import "ZGProcess.h"
#import "ZGDataValueExtracting.h"
#import "ZGLocalization.h"
#import "ZGRegister.h"
#import "ZGRegisterEntries.h"
#import "ZGNullability.h"
#import "NSArrayAdditions.h"
#import "ZGVariableDataInfo.h"
#import "ZGCalculator.h"

#define ZG_REGISTER_TYPES @"ZG_REGISTER_TYPES"
#define ZG_DEBUG_QUALIFIER @"ZG_DEBUG_QUALIFIER"

#define ZGLocalizedStringFromDebuggerRegistersTable(string) NSLocalizedStringFromTable((string), @"[Code] Debugger Registers", nil)

@implementation ZGRegistersViewController
{
	__weak id <ZGRegistersViewDelegate> _Nullable _delegate;
	NSUndoManager * _Nonnull _undoManager;
	NSArray<ZGRegister *> * _Nonnull _registers;
	ZGBreakPoint * _Nullable _breakPoint;
	ZGVariableQualifier _qualifier;

	IBOutlet NSTableView *_tableView;
	IBOutlet NSTableColumn *_dataTypeTableColumn;

	NSWindow *_window;
}

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSDictionary<NSString *, NSNumber *> *registeredDefaultTypes = @{@"rflags" : @(ZGByteArray), @"eflags" : @(ZGByteArray) };
		[[NSUserDefaults standardUserDefaults] registerDefaults:@{ZG_REGISTER_TYPES : registeredDefaultTypes, ZG_DEBUG_QUALIFIER : @0}];
	});
}

- (id)initWithWindow:(NSWindow *)window undoManager:(NSUndoManager *)undoManager delegate:(id <ZGRegistersViewDelegate>)delegate
{
	self = [super initWithNibName:@"Registers View" bundle:nil];
	if (self != nil)
	{
		_registers = @[];
		_window = window;
		_undoManager = undoManager;
		_delegate = delegate;
	}
	return self;
}

- (void)loadView
{
	[super loadView];

	[_tableView registerForDraggedTypes:@[ZGVariablePboardType]];

	ZGAdjustLocalizableWidthsForWindowAndTableColumns(_window, @[_dataTypeTableColumn], @{@"ru" : @[@80.0]});
}

- (void)setInstructionPointer:(ZGMemoryAddress)instructionPointer
{
	_instructionPointer = instructionPointer;

	id <ZGRegistersViewDelegate> delegate = _delegate;
	[delegate instructionPointerDidChange];
}

- (void)changeInstructionPointer:(ZGMemoryAddress)newInstructionPointer
{
	if (_instructionPointer == newInstructionPointer)
	{
		return;
	}

	for (ZGRegister *theRegister in _registers)
	{
#if TARGET_CPU_ARM64
		if ([theRegister.variable.name isEqualToString:@"pc"])
		{
			ZGVariable *newVariable = [theRegister.variable copy];
			[newVariable setRawValue:&newInstructionPointer];

			[self changeRegister:theRegister oldVariable:theRegister.variable newVariable:newVariable];
			break;
		}
#else
		if ([@[@"eip", @"rip"] containsObject:theRegister.variable.name])
		{
			ZGVariable *newVariable = [theRegister.variable copy];

			if (ZG_PROCESS_TYPE_IS_X86_64(_breakPoint.process.type))
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
#endif
	}
}

- (ZGMemoryAddress)basePointer
{
	ZGMemoryAddress basePointer = 0x0;

	zg_thread_state_t threadState;
	mach_msg_type_number_t threadStateCount;
	if (ZGGetGeneralThreadState(&threadState, _breakPoint.thread, &threadStateCount))
	{
		basePointer = ZGBasePointerFromGeneralThreadState(&threadState, _breakPoint.process.type);
	}

	return basePointer;
}

- (ZGMemoryAddress)stackPointer
{
	ZGMemoryAddress stackPointer = 0x0;

	zg_thread_state_t threadState;
	mach_msg_type_number_t threadStateCount;
	if (ZGGetGeneralThreadState(&threadState, _breakPoint.thread, &threadStateCount))
	{
		stackPointer = ZGStackPointerFromGeneralThreadState(&threadState, _breakPoint.process.type);
	}

	return stackPointer;
}

- (void)updateRegistersFromBreakPoint:(ZGBreakPoint *)breakPoint
{
	_breakPoint = breakPoint;

	ZGRegistersState *registersState = breakPoint.registersState;

	ZGMemorySize pointerSize = breakPoint.process.pointerSize;
	NSDictionary<NSString *, NSNumber *> *registerDefaultsDictionary = [[NSUserDefaults standardUserDefaults] objectForKey:ZG_REGISTER_TYPES];

	NSMutableArray<ZGRegister *> *newRegisters = [NSMutableArray array];

	NSArray<ZGVariable *> *registerVariables = [ZGRegisterEntries registerVariablesFromGeneralPurposeThreadState:registersState.generalPurposeThreadState processType:registersState.processType];

	for (ZGVariable *registerVariable in registerVariables)
	{
		[registerVariable setQualifier:_qualifier];

		ZGRegister *newRegister = [[ZGRegister alloc] initWithRegisterType:ZGRegisterGeneralPurpose variable:registerVariable];

		NSNumber *registerDefaultType = registerDefaultsDictionary[registerVariable.name];
		ZGVariableType dataType = (registerDefaultType == nil) ? ZGPointer : (ZGVariableType)[registerDefaultType intValue];
		if (dataType != newRegister.variable.type)
		{
			[newRegister.variable setType:dataType requestedSize:newRegister.size pointerSize:pointerSize];
			[newRegister.variable setRawValue:newRegister.rawValue];
		}

		[newRegisters addObject:newRegister];
	}

	zg_thread_state_t generalPurposeThreadState = registersState.generalPurposeThreadState;
	[self setInstructionPointer:ZGInstructionPointerFromGeneralThreadState(&generalPurposeThreadState, registersState.processType)];

	if (registersState.hasVectorState)
	{
		NSArray<ZGVariable *> *registerVectorVariables = [ZGRegisterEntries registerVariablesFromVectorThreadState:registersState.vectorState processType:registersState.processType hasAVXSupport:registersState.hasAVXSupport];
		for (ZGVariable *registerVariable in registerVectorVariables)
		{
			ZGRegister *newRegister = [[ZGRegister alloc] initWithRegisterType:ZGRegisterVector variable:registerVariable];

			NSNumber *registerDefaultType = [registerDefaultsDictionary objectForKey:registerVariable.name];
			if (registerDefaultType != nil && [registerDefaultType intValue] != ZGByteArray)
			{
				[newRegister.variable setType:(ZGVariableType)[registerDefaultType intValue] requestedSize:newRegister.size pointerSize:pointerSize];
				[newRegister.variable setRawValue:newRegister.rawValue];
			}

			[newRegisters addObject:newRegister];
		}
	}

	_registers = [NSArray arrayWithArray:newRegisters];

	[_tableView reloadData];
}

- (void)changeRegister:(ZGRegister *)theRegister oldType:(ZGVariableType)oldType newType:(ZGVariableType)newType
{
	[theRegister.variable setType:newType requestedSize:theRegister.size pointerSize:_breakPoint.process.pointerSize];
	[theRegister.variable setRawValue:theRegister.rawValue];

	NSMutableDictionary<NSString *, NSNumber *> *registerTypesDictionary = [NSMutableDictionary dictionaryWithDictionary:ZGUnwrapNullableObject([[NSUserDefaults standardUserDefaults] objectForKey:ZG_REGISTER_TYPES])];
	[registerTypesDictionary setObject:@(theRegister.variable.type) forKey:theRegister.variable.name];
	[[NSUserDefaults standardUserDefaults] setObject:registerTypesDictionary forKey:ZG_REGISTER_TYPES];

	[(ZGRegistersViewController *)[_undoManager prepareWithInvocationTarget:self] changeRegister:theRegister oldType:newType newType:oldType];
	[_undoManager setActionName:ZGLocalizedStringFromDebuggerRegistersTable(@"undoRegisterTypeChange")];

	[_tableView reloadData];
}

#if TARGET_CPU_ARM64
#else
#define WRITE_VECTOR_STATE(vectorState, variable, registerName) memcpy(&vectorState.ufs.as64.__fpu_##registerName, variable.rawValue, MIN(variable.size, sizeof(vectorState.ufs.as64.__fpu_##registerName)))
#endif

- (BOOL)changeFloatingPointRegister:(ZGRegister *)theRegister newVariable:(ZGVariable *)newVariable
{
	ZGProcessType processType = _breakPoint.process.type;

	zg_vector_state_t vectorState;
	mach_msg_type_number_t vectorStateCount;
	if (!ZGGetVectorThreadState(&vectorState, _breakPoint.thread, &vectorStateCount, processType, NULL))
	{
		return NO;
	}

	NSString *registerName = theRegister.variable.name;

#if TARGET_CPU_ARM64
	NSArray<NSString *> *vectorRegisters = @[@"v0", @"v1", @"v2", @"v3", @"v4", @"v5", @"v6", @"v7", @"v8", @"v9", @"v10", @"v11", @"v12", @"v13", @"v14", @"v15", @"v16", @"v17", @"v18", @"v19", @"v20", @"v21", @"v22", @"v23", @"v24", @"v25", @"v26", @"v27", @"v28", @"v29", @"v30", @"v31"];

	if ([vectorRegisters containsObject:registerName])
	{
		memcpy((uint64_t *)&vectorState.__v + [vectorRegisters indexOfObject:registerName], newVariable.rawValue, MIN(newVariable.size, sizeof(*vectorState.__v)));
	}
	else if ([registerName isEqualToString:@"fpsr"])
	{
		memcpy((uint64_t *)&vectorState.__fpsr, newVariable.rawValue, MIN(newVariable.size, sizeof(vectorState.__fpsr)));
	}
	else if ([registerName isEqualToString:@"fpcr"])
	{
		memcpy((uint64_t *)&vectorState.__fpcr, newVariable.rawValue, MIN(newVariable.size, sizeof(vectorState.__fpcr)));
	}
	else
	{
		return NO;
	}
#else
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
#endif

	if (!ZGSetVectorThreadState(&vectorState, _breakPoint.thread, vectorStateCount, processType))
	{
		NSLog(@"Failure in setting registers thread state for writing register value (floating point): %u", _breakPoint.thread);
		return NO;
	}

	_breakPoint.registersState.vectorState = vectorState;

	theRegister.variable = newVariable;

	return YES;
}

- (BOOL)changeGeneralPurposeRegister:(ZGRegister *)theRegister newVariable:(ZGVariable *)newVariable
{
	zg_thread_state_t threadState;
	mach_msg_type_number_t threadStateCount;
	if (!ZGGetGeneralThreadState(&threadState, _breakPoint.thread, &threadStateCount))
	{
		return NO;
	}

	NSString *registerName = theRegister.variable.name;

	BOOL shouldWriteRegister = NO;
#if TARGET_CPU_ARM64
	NSArray<NSString *> *generalRegisters = @[@"x0", @"x1", @"x2", @"x3", @"x4", @"x5", @"x6", @"x7", @"x8", @"x9", @"x10", @"x11", @"x12", @"x13", @"x14", @"x15", @"x16", @"x17", @"x18", @"x19", @"x20", @"x21", @"x22", @"x23", @"x24", @"x25", @"x26", @"x27", @"x28"];

	if ([generalRegisters containsObject:registerName])
	{
		memcpy((uint64_t *)&threadState.__x + [generalRegisters indexOfObject:registerName], newVariable.rawValue, MIN(newVariable.size, sizeof(*threadState.__x)));
		shouldWriteRegister = YES;
	}
	else if ([registerName isEqualToString:@"fp"])
	{
		memcpy((uint64_t *)&threadState.__fp, newVariable.rawValue, MIN(newVariable.size, sizeof(threadState.__fp)));
		shouldWriteRegister = YES;
	}
	else if ([registerName isEqualToString:@"lr"])
	{
		memcpy((uint64_t *)&threadState.__lr, newVariable.rawValue, MIN(newVariable.size, sizeof(threadState.__lr)));
		shouldWriteRegister = YES;
	}
	else if ([registerName isEqualToString:@"sp"])
	{
		memcpy((uint64_t *)&threadState.__sp, newVariable.rawValue, MIN(newVariable.size, sizeof(threadState.__sp)));
		shouldWriteRegister = YES;
	}
	else if ([registerName isEqualToString:@"pc"])
	{
		memcpy((uint64_t *)&threadState.__pc, newVariable.rawValue, MIN(newVariable.size, sizeof(threadState.__pc)));
		shouldWriteRegister = YES;
	}
	else if ([registerName isEqualToString:@"cpsr"])
	{
		memcpy((uint64_t *)&threadState.__cpsr, newVariable.rawValue, MIN(newVariable.size, sizeof(threadState.__cpsr)));
		shouldWriteRegister = YES;
	}
#else
	if (ZG_PROCESS_TYPE_IS_X86_64(_breakPoint.registersState.processType))
	{
		NSArray<NSString *> *registers64 = @[@"rax", @"rbx", @"rcx", @"rdx", @"rdi", @"rsi", @"rbp", @"rsp", @"r8", @"r9", @"r10", @"r11", @"r12", @"r13", @"r14", @"r15", @"rip", @"rflags", @"cs", @"fs", @"gs"];
		if ([registers64 containsObject:registerName])
		{
			memcpy((uint64_t *)&threadState.uts.ts64 + [registers64 indexOfObject:registerName], newVariable.rawValue, MIN(newVariable.size, sizeof(uint64_t)));
			shouldWriteRegister = YES;
		}
	}
	else
	{
		NSArray<NSString *> *registers32 = @[@"eax", @"ebx", @"ecx", @"edx", @"edi", @"esi", @"ebp", @"esp", @"ss", @"eflags", @"eip", @"cs", @"ds", @"es", @"fs", @"gs"];
		if ([registers32 containsObject:registerName])
		{
			memcpy((uint32_t *)&threadState.uts.ts32 + [registers32 indexOfObject:registerName], newVariable.rawValue, MIN(newVariable.size, sizeof(uint32_t)));
			shouldWriteRegister = YES;
		}
	}
#endif

	if (!shouldWriteRegister) return NO;

	if (!ZGSetGeneralThreadState(&threadState, _breakPoint.thread, threadStateCount))
	{
		NSLog(@"Failure in setting registers thread state for writing register value (general purpose): %u", _breakPoint.thread);
		return NO;
	}

	_breakPoint.registersState.generalPurposeThreadState = threadState;

	theRegister.variable = newVariable;

#if TARGET_CPU_ARM64
	if ([registerName isEqualToString:@"pc"])
	{
		[self setInstructionPointer:*(uint64_t *)theRegister.rawValue];
	}
#else
	if ([registerName isEqualToString:@"rip"])
	{
		[self setInstructionPointer:*(uint64_t *)theRegister.rawValue];
	}
	else if ([registerName isEqualToString:@"eip"])
	{
		[self setInstructionPointer:*(uint32_t *)theRegister.rawValue];
	}
#endif

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
		[(ZGRegistersViewController *)[_undoManager prepareWithInvocationTarget:self] changeRegister:theRegister oldVariable:newVariable newVariable:oldVariable];
		[_undoManager setActionName:ZGLocalizedStringFromDebuggerRegistersTable(@"undoRegisterValueChange")];

		[_tableView reloadData];
	}
}

#pragma mark TableView Methods

- (BOOL)tableView:(NSTableView *)__unused tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard
{
	NSArray<ZGVariable *> *variables = [[_registers objectsAtIndexes:rowIndexes] zgMapUsingBlock:^id _Nonnull(ZGRegister *theRegister) {
		return theRegister.variable;
	}];

	NSError *archiveError = nil;
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:variables requiringSecureCoding:YES error:&archiveError];
	if (data == nil)
	{
		NSLog(@"Error: failed to write registers to pasteboard: %@", archiveError);
		return NO;
	}

	return [pboard setData:data forType:ZGVariablePboardType];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)__unused tableView
{
	return (NSInteger)_registers.count;
}

- (id)tableView:(NSTableView *)__unused tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	id result = nil;
	if (rowIndex >= 0 && (NSUInteger)rowIndex < _registers.count)
	{
		ZGRegister *theRegister = [_registers objectAtIndex:(NSUInteger)rowIndex];
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
			return @([(NSPopUpButtonCell *)[tableColumn dataCell] indexOfItemWithTag:theRegister.variable.type]);
		}
	}

	return result;
}

- (void)tableView:(NSTableView *)__unused tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if (rowIndex >= 0 && (NSUInteger)rowIndex < _registers.count)
	{
		ZGRegister *theRegister = [_registers objectAtIndex:(NSUInteger)rowIndex];
		if ([tableColumn.identifier isEqualToString:@"value"])
		{
			ZGVariableType dataType = theRegister.variable.type;

			NSString *evaluatedString = !ZGIsNumericalDataType(dataType) ? object : [ZGCalculator evaluateExpression:object];

			ZGMemorySize size;
			void *newValue = ZGValueFromString(_breakPoint.process.type, evaluatedString, dataType, &size);
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
				  type:dataType
				  qualifier:theRegister.variable.qualifier
				  pointerSize:_breakPoint.process.pointerSize
				  description:theRegister.variable.fullAttributedDescription
				  enabled:NO]];

				free(newValue);
			}
		}
		else if ([tableColumn.identifier isEqualToString:@"type"])
		{
			ZGVariableType newType = (ZGVariableType)[[[(NSPopUpButtonCell *)tableColumn.dataCell itemArray] objectAtIndex:[(NSNumber *)object unsignedIntegerValue]] tag];
			[self changeRegister:theRegister oldType:theRegister.variable.type newType:newType];
		}
	}
}

- (BOOL)tableView:(NSTableView *)__unused tableView shouldEditTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if ([tableColumn.identifier isEqualToString:@"value"])
	{
		if (rowIndex < 0 || (NSUInteger)rowIndex >= _registers.count)
		{
			return NO;
		}

		ZGRegister *theRegister = [_registers objectAtIndex:(NSUInteger)rowIndex];
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
	if (_qualifier != [(NSControl *)sender tag])
	{
		_qualifier = (ZGVariableQualifier)[(NSControl *)sender tag];
		[[NSUserDefaults standardUserDefaults] setInteger:_qualifier forKey:ZG_DEBUG_QUALIFIER];
		for (ZGRegister *theRegister in _registers)
		{
			theRegister.variable.qualifier = _qualifier;
		}

		[_tableView reloadData];
	}
}

- (BOOL)validateUserInterfaceItem:(NSMenuItem *)menuItem
{
	if (menuItem.action == @selector(changeQualifier:))
	{
		[menuItem setState:_qualifier == [menuItem tag]];
	}
	else if (menuItem.action == @selector(copy:))
	{
		if ([self selectedRegisters].count == 0)
		{
			return NO;
		}
	}

	return YES;
}

#pragma mark Copy

- (NSArray<ZGRegister *> *)selectedRegisters
{
	NSIndexSet *tableIndexSet = _tableView.selectedRowIndexes;
	NSInteger clickedRow = _tableView.clickedRow;

	NSIndexSet *selectionIndexSet = (clickedRow >= 0 && ![tableIndexSet containsIndex:(NSUInteger)clickedRow]) ? [NSIndexSet indexSetWithIndex:(NSUInteger)clickedRow] : tableIndexSet;

	return [_registers objectsAtIndexes:selectionIndexSet];
}

- (IBAction)copy:(id)__unused sender
{
	NSMutableArray<NSString *> *descriptionComponents = [[NSMutableArray alloc] init];
	NSMutableArray<ZGVariable *> *variablesArray = [[NSMutableArray alloc] init];

	for (ZGRegister *theRegister in [self selectedRegisters])
	{
		[descriptionComponents addObject:[@[theRegister.variable.name, theRegister.variable.stringValue] componentsJoinedByString:@"\t"]];
		[variablesArray addObject:theRegister.variable];
	}

	[[NSPasteboard generalPasteboard] declareTypes:@[NSPasteboardTypeString, ZGVariablePboardType] owner:self];
	[[NSPasteboard generalPasteboard] setString:[descriptionComponents componentsJoinedByString:@"\n"] forType:NSPasteboardTypeString];

	NSError *archiveError = nil;
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:variablesArray requiringSecureCoding:YES error:&archiveError];
	if (data != nil)
	{
		[[NSPasteboard generalPasteboard] setData:data forType:ZGVariablePboardType];
	}
	else
	{
		NSLog(@"Error: failed to copy registers data: %@", archiveError);
	}
}

@end
