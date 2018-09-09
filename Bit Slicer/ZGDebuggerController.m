/*
 * Copyright (c) 2012 Mayur Pawashe
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

#import "ZGDebuggerController.h"
#import "ZGDebuggerUtilities.h"
#import "ZGProcessTaskManager.h"
#import "ZGProcess.h"
#import "ZGRegion.h"
#import "ZGCalculator.h"
#import "ZGRunningProcess.h"
#import "ZGInstruction.h"
#import "ZGLoggerWindowController.h"
#import "ZGBreakPoint.h"
#import "ZGBreakPointController.h"
#import "ZGBreakPointCondition.h"
#import "ZGScriptingInterpreter.h"
#import "ZGScriptManager.h"
#import "ZGDisassemblerObject.h"
#import "ZGDebugLogging.h"
#import "ZGDeliverUserNotifications.h"
#import "ZGRunAlertPanel.h"
#import "ZGPreferencesController.h"
#import "NSArrayAdditions.h"
#import "ZGVirtualMemory.h"
#import "ZGMachBinary.h"
#import "ZGMachBinaryInfo.h"
#import "ZGTableView.h"
#import "ZGVariableController.h"
#import "ZGBacktrace.h"
#import "ZGHotKeyCenter.h"
#import "ZGHotKey.h"
#import "ZGDataValueExtracting.h"
#import "ZGMemoryAddressExpressionParsing.h"
#import "ZGNullability.h"

#define ZGDebuggerSplitViewAutosaveName @"ZGDisassemblerHorizontalSplitter"
#define ZGRegistersAndBacktraceSplitViewAutosaveName @"ZGDisassemblerVerticalSplitter"

NSString *ZGStepInHotKey = @"ZGStepInHotKey";
NSString *ZGStepOverHotKey = @"ZGStepOverHotKey";
NSString *ZGStepOutHotKey = @"ZGStepOutHotKey";
NSString *ZGPauseAndUnpauseHotKey = @"ZGPauseAndUnpauseHotKey";

#define ZGOldPauseAndUnpauseHotKeyCode @"ZG_HOT_KEY_CODE"
#define ZGOldPauseAndUnpauseHotKeyFlags @"ZG_HOT_KEY_MODIFIER"

#define ZGDebuggerAddressField @"ZGDisassemblerAddressField"
#define ZGDebuggerProcessInternalName @"ZGDisassemblerProcessName"
#define ZGDebuggerOffsetFromBase @"ZGDebuggerOffsetFromBase"
#define ZGDebuggerMappedFilePath @"ZGDebuggerMappedFilePath"

typedef NS_ENUM(NSInteger, ZGStepExecution)
{
	ZGStepIntoExecution,
	ZGStepOverExecution,
	ZGStepOutExecution
};

@implementation ZGDebuggerController
{
	BOOL _cleanedUp;
	
	// We start a working activity whenever we have an instruction or watchpoint breakpoint set,
	// but I'm not sure if this is *actually* necessary
	id _Nullable _breakPointActivity;
	
	ZGBreakPointController *_breakPointController;
	ZGScriptingInterpreter *_scriptingInterpreter;
	ZGLoggerWindowController *_loggerWindowController;
	
	NSString * _Nullable _mappedFilePath;
	ZGMemoryAddress _baseAddress;
	ZGMemoryAddress _offsetFromBase;
	
	NSArray<ZGInstruction *> *_instructions;
	NSRange _instructionBoundary;
	
	ZGCodeInjectionWindowController * _Nullable _codeInjectionController;
	
	NSPopover * _Nullable _breakPointConditionPopover;
	NSMutableArray<ZGBreakPointCondition *> * _Nullable _breakPointConditions;
	
	IBOutlet ZGTableView *_instructionsTableView;
	IBOutlet NSSplitView *_splitView;
	IBOutlet NSSplitView *_registersAndBacktraceSplitView;
	
	IBOutlet NSView *_registersView;
	ZGRegistersViewController *_registersViewController;
	
	IBOutlet NSView *_backtraceView;
	ZGBacktraceViewController *_backtraceViewController;
	
	IBOutlet NSButton *_continueButton;
	IBOutlet NSSegmentedControl *_stepExecutionSegmentedControl;
	
	IBOutlet NSTextField *_statusTextField;
}

#pragma mark Birth & Death

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSData *emptyHotKeyData = [NSKeyedArchiver archivedDataWithRootObject:[ZGHotKey hotKey]];

		// Versions before 1.7 have pause/unpause hot key stored in different default keys, so do a migration
		NSNumber *oldPauseAndUnpauseHotKeyCode = [[NSUserDefaults standardUserDefaults] objectForKey:ZGOldPauseAndUnpauseHotKeyCode];
		NSNumber *oldPauseAndUnpauseHotKeyFlags = [[NSUserDefaults standardUserDefaults] objectForKey:ZGOldPauseAndUnpauseHotKeyFlags];
		if (oldPauseAndUnpauseHotKeyCode != nil && oldPauseAndUnpauseHotKeyFlags != nil)
		{
			NSUInteger oldFlags = oldPauseAndUnpauseHotKeyFlags.unsignedIntegerValue;
			NSInteger oldCode = oldPauseAndUnpauseHotKeyCode.integerValue;
			if (oldCode < INVALID_KEY_CODE) // versions before 1.6 stored invalid key code as -999
			{
				oldCode = INVALID_KEY_CODE;
			}

			[[NSUserDefaults standardUserDefaults]
			 registerDefaults:@{ZGPauseAndUnpauseHotKey : [NSKeyedArchiver archivedDataWithRootObject:[ZGHotKey hotKeyWithKeyCombo:(KeyCombo){.code = oldCode, .flags = oldFlags}]]}];

			[[NSUserDefaults standardUserDefaults] removeObjectForKey:ZGOldPauseAndUnpauseHotKeyCode];
			[[NSUserDefaults standardUserDefaults] removeObjectForKey:ZGOldPauseAndUnpauseHotKeyFlags];
		}
		else
		{
			[[NSUserDefaults standardUserDefaults] registerDefaults:@{ZGPauseAndUnpauseHotKey : emptyHotKeyData}];
		}

		[[NSUserDefaults standardUserDefaults] registerDefaults:@{ZGStepInHotKey : emptyHotKeyData}];
		[[NSUserDefaults standardUserDefaults] registerDefaults:@{ZGStepOverHotKey : emptyHotKeyData}];
		[[NSUserDefaults standardUserDefaults] registerDefaults:@{ZGStepOutHotKey : emptyHotKeyData}];
	});
}

- (id)initWithProcessTaskManager:(ZGProcessTaskManager *)processTaskManager rootlessConfiguration:(nullable ZGRootlessConfiguration *)rootlessConfiguration breakPointController:(ZGBreakPointController *)breakPointController scriptingInterpreter:(ZGScriptingInterpreter *)scriptingInterpreter hotKeyCenter:(ZGHotKeyCenter *)hotKeyCenter loggerWindowController:(ZGLoggerWindowController *)loggerWindowController delegate:(id <ZGChosenProcessDelegate, ZGMemorySelectionDelegate, ZGShowMemoryWindow>)delegate
{
	self = [super initWithProcessTaskManager:processTaskManager rootlessConfiguration:rootlessConfiguration delegate:delegate];
	
	if (self != nil)
	{
		_breakPointController = breakPointController;
		_scriptingInterpreter = scriptingInterpreter;
		_loggerWindowController = loggerWindowController;
		
		_instructions = @[];
		_haltedBreakPoints = [[NSMutableArray alloc] init];
		
		_pauseAndUnpauseHotKey = ZGUnwrapNullableObject([NSKeyedUnarchiver unarchiveObjectWithData:ZGUnwrapNullableObject([[NSUserDefaults standardUserDefaults] objectForKey:ZGPauseAndUnpauseHotKey])]);
		_stepInHotKey = ZGUnwrapNullableObject([NSKeyedUnarchiver unarchiveObjectWithData:ZGUnwrapNullableObject([[NSUserDefaults standardUserDefaults] objectForKey:ZGStepInHotKey])]);
		_stepOverHotKey = ZGUnwrapNullableObject([NSKeyedUnarchiver unarchiveObjectWithData:ZGUnwrapNullableObject([[NSUserDefaults standardUserDefaults] objectForKey:ZGStepOverHotKey])]);
		_stepOutHotKey = ZGUnwrapNullableObject([NSKeyedUnarchiver unarchiveObjectWithData:ZGUnwrapNullableObject([[NSUserDefaults standardUserDefaults] objectForKey:ZGStepOutHotKey])]);

		[hotKeyCenter registerHotKey:_pauseAndUnpauseHotKey delegate:self];
		[hotKeyCenter registerHotKey:_stepInHotKey delegate:self];
		[hotKeyCenter registerHotKey:_stepOverHotKey delegate:self];
		[hotKeyCenter registerHotKey:_stepOutHotKey delegate:self];
	}

	return self;
}

- (void)encodeRestorableStateWithCoder:(NSCoder *)coder
{
    [super encodeRestorableStateWithCoder:coder];
	
	[coder encodeObject:self.addressTextField.stringValue forKey:ZGDebuggerAddressField];
	[coder encodeObject:[(ZGProcess *)self.runningApplicationsPopUpButton.selectedItem.representedObject internalName] forKey:ZGDebuggerProcessInternalName];
	[coder encodeObject:@(_offsetFromBase) forKey:ZGDebuggerOffsetFromBase];
	[coder encodeObject:_mappedFilePath == nil ? [NSNull null] : _mappedFilePath forKey:ZGDebuggerMappedFilePath];
}

- (void)restoreStateWithCoder:(NSCoder *)coder
{
	[super restoreStateWithCoder:coder];
	
	NSString *addressField = [coder decodeObjectOfClass:[NSString class] forKey:ZGDebuggerAddressField];
	if (addressField != nil)
	{
		self.addressTextField.stringValue = addressField;
	}
	
	_offsetFromBase = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class] forKey:ZGDebuggerOffsetFromBase] unsignedLongLongValue];
	
	_mappedFilePath = [coder decodeObjectOfClass:[NSObject class] forKey:ZGDebuggerMappedFilePath];
	if ((id)_mappedFilePath == [NSNull null])
	{
		_mappedFilePath = nil;
	}
	
	self.desiredProcessInternalName = [coder decodeObjectForKey:ZGDebuggerProcessInternalName];
	[self updateRunningProcesses];
	[self setAndPostLastChosenInternalProcessName];
	[self readMemory:nil];
}

- (NSString *)windowNibName
{
	return @"Debugger Window";
}

- (void)windowDidLoad
{
    [super windowDidLoad];
	
	[self setupProcessListNotifications];

	self.desiredProcessInternalName = self.lastChosenInternalProcessName;
	[self updateRunningProcesses];
	
	[_instructionsTableView registerForDraggedTypes:@[ZGVariablePboardType]];
	
	[_statusTextField.cell setBackgroundStyle:NSBackgroundStyleRaised];
	
	[_continueButton.image setTemplate:YES];
	[[_stepExecutionSegmentedControl imageForSegment:ZGStepIntoExecution] setTemplate:YES];
	[[_stepExecutionSegmentedControl imageForSegment:ZGStepOverExecution] setTemplate:YES];
	[[_stepExecutionSegmentedControl imageForSegment:ZGStepOutExecution] setTemplate:YES];
	
	_continueButton.toolTip = ZGLocalizedStringFromDebuggerTable(@"continueButtonToolTip");
	
	[_stepExecutionSegmentedControl.cell
	 setToolTip:ZGLocalizedStringFromDebuggerTable(@"stepIntoSegmentToolTip")
	 forSegment:ZGStepIntoExecution];
	
	[_stepExecutionSegmentedControl.cell
	 setToolTip:ZGLocalizedStringFromDebuggerTable(@"stepOverSegmentToolTip")
	 forSegment:ZGStepOverExecution];
	
	[_stepExecutionSegmentedControl.cell
	 setToolTip:ZGLocalizedStringFromDebuggerTable(@"stepOutSegmentToolTip")
	 forSegment:ZGStepOutExecution];
	
	[self updateExecutionButtons];
	
	[self toggleBacktraceAndRegistersViews:NSOffState];
	
	// Don't set these in IB; can't trust setting these at the right time and not screwing up the saved positions
	_splitView.autosaveName = ZGDebuggerSplitViewAutosaveName;
	_registersAndBacktraceSplitView.autosaveName = ZGRegistersAndBacktraceSplitViewAutosaveName;
}

- (void)updateWindowAndReadMemory:(BOOL)shouldReadMemory
{
	[super updateWindow];
	
	if (shouldReadMemory)
	{
		[self readMemory:nil];
	}
}

#pragma mark Hot Keys

- (void)hotKeyDidTrigger:(ZGHotKey *)hotKey
{
	if (hotKey == _pauseAndUnpauseHotKey)
	{
		if ([self canContinueOrStepIntoExecution])
		{
			[self continueExecution:nil];
		}
		else
		{
			for (NSRunningApplication *runningApplication in [[NSWorkspace sharedWorkspace] runningApplications])
			{
				if (runningApplication.isActive)
				{
					if (runningApplication.processIdentifier != getpid() && ![self isProcessIdentifierHalted:runningApplication.processIdentifier])
					{
						ZGMemoryMap processTask = 0;
						if ([self.processTaskManager getTask:&processTask forProcessIdentifier:runningApplication.processIdentifier])
						{
							[[self class] pauseOrUnpauseProcessTask:processTask];
						}
						else
						{
							ZG_LOG(@"Failed to pause/unpause process with pid %d", runningApplication.processIdentifier);
						}
					}
					break;
				}
			}
		}
	}
	else if (hotKey == _stepInHotKey)
	{
		if ([self canContinueOrStepIntoExecution])
		{
			[self stepInto:nil];
		}
	}
	else if (hotKey == _stepOverHotKey)
	{
		if ([self canStepOverExecution])
		{
			[self stepOver:nil];
		}
	}
	else if (hotKey == _stepOutHotKey)
	{
		if ([self canStepOutOfExecution])
		{
			[self stepOut:nil];
		}
	}
}

#pragma mark Current Process Changed

- (void)currentProcessChangedWithOldProcess:(ZGProcess *)oldProcess newProcess:(ZGProcess *)__unused newProcess
{
	[self updateExecutionButtons];
	
	ZGBreakPoint *currentBreakpoint = [self currentBreakPoint];
	
	if (currentBreakpoint != nil)
	{
		[self toggleBacktraceAndRegistersViews:NSOnState];
		[_registersViewController updateRegistersFromBreakPoint:currentBreakpoint];
		[self updateBacktrace];
		
		[self jumpToMemoryAddress:_registersViewController.instructionPointer];
	}
	else
	{
		[self toggleBacktraceAndRegistersViews:NSOffState];
		if (oldProcess != nil)
		{
			[self readMemory:nil];
		}
	}
}

#pragma mark Split Views

- (CGFloat)splitView:(NSSplitView *)__unused splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)__unused dividerIndex
{
	// prevent bottom view from going all the way up
	return proposedMinimumPosition + 60;
}

- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview
{
	if ([splitView.subviews objectAtIndex:1] == subview)
	{
		return YES;
	}
	
	return NO;
}

- (BOOL)splitView:(NSSplitView *)__unused splitView shouldHideDividerAtIndex:(NSInteger)__unused dividerIndex
{
	return ([self currentBreakPoint] == nil);
}

// For collapsing and uncollapsing, useful info: http://manicwave.com/blog/2009/12/31/unraveling-the-mysteries-of-nssplitview-part-2/
- (void)uncollapseBottomSubview
{
	NSView *topSubview = [_splitView.subviews objectAtIndex:0];
	NSView *bottomSubview = [_splitView.subviews objectAtIndex:1];
	
	[bottomSubview setHidden:NO];
	
	NSRect topFrame = topSubview.frame;
	NSRect bottomFrame = bottomSubview.frame;
	
	topFrame.size.height = topFrame.size.height - bottomFrame.size.height - _splitView.dividerThickness;
	bottomFrame.origin.y = topFrame.size.height + _splitView.dividerThickness;
	
	topSubview.frameSize = topFrame.size;
	bottomSubview.frame = bottomFrame;
	[_splitView layout];
	[_splitView display];
}

- (void)collapseBottomSubview
{
	NSView *topSubview = [_splitView.subviews objectAtIndex:0];
	NSView *bottomSubview = [_splitView.subviews objectAtIndex:1];
	
	[bottomSubview setHidden:YES];
	[topSubview setFrameSize:NSMakeSize(topSubview.frame.size.width, _splitView.frame.size.height)];
	[_splitView layout];
	[_splitView display];
}

- (void)toggleBacktraceAndRegistersViews:(NSCellStateValue)state
{	
	switch (state)
	{
		case NSOnState:
			if ([_splitView isSubviewCollapsed:[_splitView.subviews objectAtIndex:1]])
			{
				[self uncollapseBottomSubview];
			}
			break;
		case NSOffState:
			if (![_splitView isSubviewCollapsed:[_splitView.subviews objectAtIndex:1]])
			{
				[self.undoManager removeAllActionsWithTarget:_registersViewController];
				[self collapseBottomSubview];
			}
			break;
		default:
			break;
	}
}

#pragma mark Symbols

// prerequisite: should call shouldUpdateSymbolsForInstructions: beforehand
- (void)updateSymbolsForInstructions:(NSArray<ZGInstruction *> *)instructions
{
	for (ZGInstruction *instruction in instructions)
	{
		ZGMemoryAddress relativeProcedureOffset = 0x0;
		NSString *symbolName = [self.currentProcess.symbolicator symbolAtAddress:instruction.variable.address relativeOffset:&relativeProcedureOffset];

		instruction.symbols = (symbolName != nil) ? [NSString stringWithFormat:@"%@ + %llu", symbolName, relativeProcedureOffset] : @"";
	}
}

- (BOOL)shouldUpdateSymbolsForInstructions:(NSArray<ZGInstruction *> *)instructions
{
	return self.currentProcess.valid && [instructions zgHasObjectMatchingCondition:^(ZGInstruction *instruction){ return (BOOL)(instruction.symbols == nil); }];
}

#pragma mark Disassembling

- (void)updateInstructionValues
{
	// Check to see if anything in the window needs to be updated
	NSRange visibleRowsRange = [_instructionsTableView rowsInRect:_instructionsTableView.visibleRect];
	if (visibleRowsRange.location + visibleRowsRange.length <= _instructions.count)
	{	
		BOOL needsToUpdateWindow = NO;
		
		for (ZGInstruction *instruction in [_instructions subarrayWithRange:visibleRowsRange])
		{
			void *bytes = NULL;
			ZGMemorySize size = instruction.variable.size;
			if (ZGReadBytes(self.currentProcess.processTask, instruction.variable.address, &bytes, &size))
			{
				if (memcmp(bytes, instruction.variable.rawValue, size) != 0)
				{
					// Ignore trivial breakpoint changes
					BOOL foundBreakPoint = NO;
					if (*(uint8_t *)bytes == INSTRUCTION_BREAKPOINT_OPCODE && (size == sizeof(uint8_t) || memcmp((uint8_t *)bytes + sizeof(uint8_t), (uint8_t *)instruction.variable.rawValue + sizeof(uint8_t), size - sizeof(uint8_t)) == 0))
					{
						foundBreakPoint = [_breakPointController.breakPoints zgHasObjectMatchingCondition:^(ZGBreakPoint *breakPoint) {
							return (BOOL)(breakPoint.type == ZGBreakPointInstruction && breakPoint.variable.address == instruction.variable.address && *(uint8_t *)breakPoint.variable.rawValue == *(uint8_t *)instruction.variable.rawValue);
						}];
					}
					
					if (!foundBreakPoint)
					{
						needsToUpdateWindow = YES;
						break;
					}
				}
				
				ZGFreeBytes(bytes, size);
			}
		}
		
		if (needsToUpdateWindow)
		{
			NSArray<ZGMachBinary *> *machBinaries = nil;
			
			// Find a [start, end) range that we are allowed to remove from the table and insert in again with new instructions
			// Pick start and end such that they are aligned with the assembly instructions
			
			NSUInteger startRow = visibleRowsRange.location;
			
			do
			{
				if (startRow == 0) break;
				
				ZGInstruction *instruction = [_instructions objectAtIndex:startRow];
				
				if (machBinaries == nil)
				{
					machBinaries = [ZGMachBinary machBinariesInProcess:self.currentProcess];
				}
				
				ZGInstruction *searchedInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:instruction.variable.address inProcess:self.currentProcess withBreakPoints:_breakPointController.breakPoints machBinaries:machBinaries];
				
				startRow--;
				
				if (searchedInstruction.variable.address + searchedInstruction.variable.size == instruction.variable.address)
				{
					break;
				}
			}
			while (YES);
			
			ZGInstruction *startInstruction = [_instructions objectAtIndex:startRow];
			ZGMemoryAddress startAddress = startInstruction.variable.address;
			
			// Extend past first row if necessary
			if (startRow == 0)
			{
				if (machBinaries == nil)
				{
					machBinaries = [ZGMachBinary machBinariesInProcess:self.currentProcess];
				}
				
				ZGInstruction *searchedInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:startInstruction.variable.address inProcess:self.currentProcess withBreakPoints:_breakPointController.breakPoints machBinaries:machBinaries];
				
				if (searchedInstruction.variable.address + searchedInstruction.variable.size != startAddress)
				{
					startAddress = searchedInstruction.variable.address;
				}
			}
			
			NSUInteger endRow = visibleRowsRange.location + visibleRowsRange.length - 1;
			
			do
			{
				if (endRow >= _instructions.count) break;
				
				ZGInstruction *instruction = [_instructions objectAtIndex:endRow];
				
				if (machBinaries == nil)
				{
					machBinaries = [ZGMachBinary machBinariesInProcess:self.currentProcess];
				}
				
				ZGInstruction *searchedInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:instruction.variable.address + instruction.variable.size inProcess:self.currentProcess withBreakPoints:_breakPointController.breakPoints machBinaries:machBinaries];
				
				endRow++;
				
				if (searchedInstruction.variable.address == instruction.variable.address)
				{
					break;
				}
			}
			while (YES);
			
			ZGInstruction *endInstruction = [_instructions objectAtIndex:endRow-1];
			ZGMemoryAddress endAddress = endInstruction.variable.address + endInstruction.variable.size;
			
			// Extend past last row if necessary
			if (endRow >= _instructions.count)
			{
				if (machBinaries == nil)
				{
					machBinaries = [ZGMachBinary machBinariesInProcess:self.currentProcess];
				}
				
				ZGInstruction *searchedInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:endInstruction.variable.address + endInstruction.variable.size inProcess:self.currentProcess withBreakPoints:_breakPointController.breakPoints machBinaries:machBinaries];
				
				if (endInstruction.variable.address != searchedInstruction.variable.address)
				{
					endAddress = searchedInstruction.variable.address + searchedInstruction.variable.size;
				}
			}
			
			ZGMemorySize size = endAddress - startAddress;
			
			ZGDisassemblerObject *disassemblerObject = [ZGDebuggerUtilities disassemblerObjectWithProcessTask:self.currentProcess.processTask pointerSize:self.currentProcess.pointerSize address:startAddress size:size breakPoints:_breakPointController.breakPoints];
			if (disassemblerObject != nil)
			{
				NSArray<ZGInstruction *> *instructionsToReplace = [disassemblerObject readInstructions];
				
				// Replace the visible instructions
				NSMutableArray<ZGInstruction *> *newInstructions = [[NSMutableArray alloc] initWithArray:_instructions];
				[newInstructions replaceObjectsInRange:NSMakeRange(startRow, endRow - startRow) withObjectsFromArray:instructionsToReplace];
				_instructions = [NSArray arrayWithArray:newInstructions];
				
				[_instructionsTableView reloadData];
			}
		}
	}
}

- (void)updateVisibleInstructionSymbols
{
	NSRange visibleRowsRange = [_instructionsTableView rowsInRect:_instructionsTableView.visibleRect];
	if (visibleRowsRange.location + visibleRowsRange.length <= _instructions.count)
	{
		NSArray<ZGInstruction *> *instructions = [_instructions subarrayWithRange:visibleRowsRange];
		if ([self shouldUpdateSymbolsForInstructions:instructions])
		{
			[self updateSymbolsForInstructions:instructions];
			[_instructionsTableView reloadData];
		}
	}
}

#define DESIRED_BYTES_TO_ADD_OFFSET 10000

- (void)addMoreInstructionsBeforeFirstRow
{
	ZGInstruction *endInstruction = [_instructions objectAtIndex:0];
	ZGInstruction *startInstruction = nil;
	NSUInteger bytesBehind = DESIRED_BYTES_TO_ADD_OFFSET;
	
	if (endInstruction.variable.address <= _instructionBoundary.location)
	{
		return;
	}
	
	NSArray<ZGMachBinary *> *machBinaries = nil;
	
	while (startInstruction == nil && bytesBehind > 0)
	{
		if (machBinaries == nil)
		{
			machBinaries = [ZGMachBinary machBinariesInProcess:self.currentProcess];
		}
		
		startInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:endInstruction.variable.address - bytesBehind inProcess:self.currentProcess withBreakPoints:_breakPointController.breakPoints machBinaries:machBinaries];
		
		if (startInstruction.variable.address < _instructionBoundary.location)
		{
			// Try again
			startInstruction = nil;
		}
		
		bytesBehind /= 2;
	}
	
	if (startInstruction != nil)
	{
		ZGMemorySize size = endInstruction.variable.address - startInstruction.variable.address;
		
		ZGDisassemblerObject *disassemblerObject = [ZGDebuggerUtilities disassemblerObjectWithProcessTask:self.currentProcess.processTask pointerSize:self.currentProcess.pointerSize address:startInstruction.variable.address size:size breakPoints:_breakPointController.breakPoints];
		
		if (disassemblerObject != nil)
		{
			NSMutableArray<ZGInstruction *> *instructionsToAdd = [NSMutableArray arrayWithArray:[disassemblerObject readInstructions]];
			
			NSUInteger numberOfInstructionsAdded = instructionsToAdd.count;
			NSRange visibleRowsRange = [_instructionsTableView rowsInRect:_instructionsTableView.visibleRect];
			
			[instructionsToAdd addObjectsFromArray:_instructions];
			_instructions = [NSArray arrayWithArray:instructionsToAdd];
			
			NSInteger previousSelectedRow = [_instructionsTableView selectedRow];
			[_instructionsTableView noteNumberOfRowsChanged];
			
			[_instructionsTableView scrollRowToVisible:(NSInteger)MIN(numberOfInstructionsAdded + visibleRowsRange.length - 1, _instructions.count)];
			
			if (previousSelectedRow >= 0)
			{
				[_instructionsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)previousSelectedRow + numberOfInstructionsAdded] byExtendingSelection:NO];
			}
		}
	}
}

- (void)addMoreInstructionsAfterLastRow
{
	ZGInstruction *lastInstruction = _instructions.lastObject;
	
	NSArray<ZGMachBinary *> *machBinaries = [ZGMachBinary machBinariesInProcess:self.currentProcess];
	
	ZGInstruction *startInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:(lastInstruction.variable.address + lastInstruction.variable.size + 1) inProcess:self.currentProcess withBreakPoints:_breakPointController.breakPoints machBinaries:machBinaries];
	
	if (startInstruction.variable.address + startInstruction.variable.size >= _instructionBoundary.location +  _instructionBoundary.length)
	{
		return;
	}
	
	if (startInstruction != nil)
	{
		ZGInstruction *endInstruction = nil;
		NSUInteger bytesAhead = DESIRED_BYTES_TO_ADD_OFFSET;
		while (endInstruction == nil && bytesAhead > 0)
		{
			endInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:(startInstruction.variable.address + startInstruction.variable.size + bytesAhead) inProcess:self.currentProcess withBreakPoints:_breakPointController.breakPoints machBinaries:machBinaries];
			
			if (endInstruction.variable.address + endInstruction.variable.size > _instructionBoundary.location +  _instructionBoundary.length)
			{
				// Try again
				endInstruction = nil;
			}
			
			bytesAhead /= 2;
		}
		
		if (endInstruction != nil)
		{
			ZGMemorySize size = endInstruction.variable.address - startInstruction.variable.address;
			
			ZGDisassemblerObject *disassemblerObject = [ZGDebuggerUtilities disassemblerObjectWithProcessTask:self.currentProcess.processTask pointerSize:self.currentProcess.pointerSize address:startInstruction.variable.address size:size breakPoints:_breakPointController.breakPoints];
			
			if (disassemblerObject != nil)
			{
				NSArray<ZGInstruction *> *instructionsToAdd = [disassemblerObject readInstructions];
				NSMutableArray<ZGInstruction *> *appendedInstructions = [NSMutableArray arrayWithArray:_instructions];
				[appendedInstructions addObjectsFromArray:instructionsToAdd];
				
				_instructions = [NSArray arrayWithArray:appendedInstructions];
				
				[_instructionsTableView noteNumberOfRowsChanged];
			}
		}
	}
}

- (void)updateInstructionsBeyondTableView
{
	NSRange visibleRowsRange = [_instructionsTableView rowsInRect:_instructionsTableView.visibleRect];
	if (visibleRowsRange.location == 0)
	{
		[self addMoreInstructionsBeforeFirstRow];
	}
	else if (visibleRowsRange.location + visibleRowsRange.length >= _instructions.count)
	{
		[self addMoreInstructionsAfterLastRow];
	}
}

- (void)updateDisplayTimer:(NSTimer *)__unused timer
{
	if (self.currentProcess.valid && _instructionsTableView.editedRow == -1 && _instructions.count > 0)
	{
		[self updateInstructionValues];
		[self updateVisibleInstructionSymbols];
		[self updateInstructionsBeyondTableView];
	}
}

- (void)updateDisassemblerWithAddress:(ZGMemoryAddress)address size:(ZGMemorySize)size selectionAddress:(ZGMemoryAddress)selectionAddress andChangeFirstResponder:(BOOL)shouldChangeFirstResponder
{
	[self.addressTextField setEnabled:NO];
	[self.runningApplicationsPopUpButton setEnabled:NO];
	
	[self prepareNavigation];
	
	_instructions = @[];
	[_instructionsTableView reloadData];

	ZGDisassemblerObject *disassemblerObject = [ZGDebuggerUtilities disassemblerObjectWithProcessTask:self.currentProcess.processTask pointerSize:self.currentProcess.pointerSize address:address size:size breakPoints:_breakPointController.breakPoints];
	NSArray<ZGInstruction *> *newInstructions = @[];

	if (disassemblerObject != nil)
	{
		newInstructions = [disassemblerObject readInstructions];
	}

	_instructions = newInstructions;

	[_instructionsTableView noteNumberOfRowsChanged];

	ZGInstruction *selectionInstruction = [self findInstructionInTableAtAddress:selectionAddress];
	if (selectionInstruction != nil)
	{
		[self scrollAndSelectRow:[_instructions indexOfObject:selectionInstruction]];
	}

	[self.addressTextField setEnabled:YES];
	[self.runningApplicationsPopUpButton setEnabled:YES];

	if (self.window.firstResponder != _backtraceViewController.tableView && shouldChangeFirstResponder)
	{
		[self.window makeFirstResponder:_instructionsTableView];
	}

	[self updateNavigationButtons];
	[self updateExecutionButtons];
	[self updateStatusBar];
}

#pragma mark Handling Processes

- (void)processListChanged:(NSDictionary<NSString *, id> *)change
{
	NSArray<ZGRunningProcess *> *oldRunningProcesses = [change objectForKey:NSKeyValueChangeOldKey];
	if (oldRunningProcesses)
	{
		for (ZGRunningProcess *runningProcess in oldRunningProcesses)
		{
			[_breakPointController removeObserver:self runningProcess:runningProcess];
			for (ZGBreakPoint *haltedBreakPoint in _haltedBreakPoints)
			{
				if (haltedBreakPoint.process.processID == runningProcess.processIdentifier)
				{
					[self removeHaltedBreakPoint:haltedBreakPoint];
				}
			}
			
			[self stopBreakPointActivity];
		}
	}
}

- (void)switchProcessMenuItemAndSelectAddressStringValue:(NSString *)addressStringValue
{
	if (![(ZGProcess *)self.runningApplicationsPopUpButton.selectedItem.representedObject isEqual:self.currentProcess])
	{
		self.addressTextField.stringValue = addressStringValue;
		_mappedFilePath = nil;
		[self switchProcess];
	}
}

- (IBAction)runningApplicationsPopUpButton:(id)__unused sender
{
	[self switchProcessMenuItemAndSelectAddressStringValue:@"0x0"];
}

#pragma mark Changing disassembler view

- (IBAction)jumpToOperandOffset:(id)__unused sender
{
	ZGInstruction *selectedInstruction = [[self selectedInstructions] objectAtIndex:0];
	
	ZGDisassemblerObject *disassemblerObject = [ZGDebuggerUtilities disassemblerObjectWithProcessTask:self.currentProcess.processTask pointerSize:self.currentProcess.pointerSize address:selectedInstruction.variable.address size:selectedInstruction.variable.size breakPoints:_breakPointController.breakPoints];
	
	if (disassemblerObject != nil)
	{
		NSString *branchDestination = [disassemblerObject readBranchOperand];
		if (branchDestination != nil)
		{
			[self jumpToMemoryAddressStringValue:branchDestination inProcess:self.currentProcess];
		}
		else
		{
			ZG_LOG(@"Failed to jump to branch address on %@", selectedInstruction.text);
		}
	}
	else
	{
		ZG_LOG(@"Failed to disassemble bytes to jump to branch address on %@", selectedInstruction.text);
	}
}

- (void)prepareNavigation
{
	if (_instructions.count > 0)
	{
		NSRange visibleRowsRange = [_instructionsTableView rowsInRect:_instructionsTableView.visibleRect];
		
		if (_instructionsTableView.selectedRowIndexes.count > 0 && _instructionsTableView.selectedRowIndexes.firstIndex >= visibleRowsRange.location && _instructionsTableView.selectedRowIndexes.firstIndex < visibleRowsRange.location + visibleRowsRange.length && _instructionsTableView.selectedRowIndexes.firstIndex < _instructions.count)
		{
			ZGInstruction *selectedInstruction = [_instructions objectAtIndex:_instructionsTableView.selectedRowIndexes.firstIndex];
			[(ZGDebuggerController *)[self.navigationManager prepareWithInvocationTarget:self] jumpToMemoryAddress:selectedInstruction.variable.address];
		}
		else
		{
			NSUInteger centeredInstructionIndex = visibleRowsRange.location + visibleRowsRange.length / 2;
			if (centeredInstructionIndex < _instructions.count)
			{
				ZGInstruction *centeredInstruction = [_instructions objectAtIndex:centeredInstructionIndex];
				[(ZGDebuggerController *)[self.navigationManager prepareWithInvocationTarget:self] jumpToMemoryAddress:centeredInstruction.variable.address];
			}
		}
	}
}

- (void)updateStatusBar
{
	if (_instructions.count == 0 || _mappedFilePath.length == 0)
	{
		[_statusTextField setStringValue:@""];
	}
	else
	{
		NSArray<ZGInstruction *> *selectedInstructions = [self selectedInstructions];
		if (selectedInstructions.count > 0)
		{
			ZGInstruction *firstSelectedInstruction = selectedInstructions[0];
			[_statusTextField setStringValue:[NSString stringWithFormat:@"%@ + 0x%llX", _mappedFilePath, firstSelectedInstruction.variable.address - _baseAddress]];
		}
	}
}

- (IBAction)readMemory:(id)sender
{
	void (^cleanupOnFailure)(void) = ^{
		self->_instructions = [NSArray array];
		[self->_instructionsTableView reloadData];
		[self updateStatusBar];
	};
	
	if (!self.currentProcess.valid || ![self.currentProcess hasGrantedAccess])
	{
		cleanupOnFailure();
		return;
	}
	
	NSArray<ZGMachBinary *> *machBinaries = [ZGMachBinary machBinariesInProcess:self.currentProcess];
	ZGMachBinary *mainMachBinary = [ZGMachBinary mainMachBinaryFromMachBinaries:machBinaries];
	
	ZGMemoryAddress calculatedMemoryAddress = 0;
	BOOL didFindSymbol = NO;

	if (_mappedFilePath != nil && sender == nil)
	{
		ZGMachBinary *targetBinary = [ZGMachBinary machBinaryWithPartialImageName:(NSString * _Nonnull)_mappedFilePath inProcess:self.currentProcess fromCachedMachBinaries:machBinaries error:NULL];
		
		if (targetBinary != nil)
		{
			calculatedMemoryAddress = targetBinary.headerAddress + _offsetFromBase;
			[self.addressTextField setStringValue:[NSString stringWithFormat:@"0x%llX", calculatedMemoryAddress]];
		}
	}
	else
	{
		NSString *userInput = self.addressTextField.stringValue;
		ZGMemoryAddress selectedAddress = ((ZGInstruction *)[[self selectedInstructions] lastObject]).variable.address;
		NSError *error = nil;
		NSString *calculatedMemoryAddressExpression = [ZGCalculator evaluateAndSymbolicateExpression:userInput process:self.currentProcess currentAddress:selectedAddress didSymbolicate:&didFindSymbol error:&error];
		if (error != nil)
		{
			NSLog(@"Encountered error when reading memory from debugger:");
			NSLog(@"%@", error);
			return;
		}
		if (ZGIsValidNumber(calculatedMemoryAddressExpression))
		{
			calculatedMemoryAddress = ZGMemoryAddressFromExpression(calculatedMemoryAddressExpression);
		}
	}
	
	BOOL shouldUseFirstInstruction = NO;
	
	ZGMachBinaryInfo *firstMachBinaryInfo = [mainMachBinary machBinaryInfoInProcess:self.currentProcess];
	NSRange machInstructionRange = NSMakeRange(firstMachBinaryInfo.firstInstructionAddress, firstMachBinaryInfo.totalSegmentRange.length - (firstMachBinaryInfo.firstInstructionAddress - firstMachBinaryInfo.totalSegmentRange.location));
	
	if (calculatedMemoryAddress == 0)
	{
		calculatedMemoryAddress = machInstructionRange.location;
		[self.addressTextField setStringValue:[NSString stringWithFormat:@"0x%llX", calculatedMemoryAddress]];
		shouldUseFirstInstruction = YES;
	}
	
	// See if the instruction is already in the table, if so, just go to it
	ZGInstruction *foundInstructionInTable = [self findInstructionInTableAtAddress:calculatedMemoryAddress];
	if (foundInstructionInTable != nil)
	{
		_offsetFromBase = calculatedMemoryAddress - _baseAddress;
		[self prepareNavigation];
		[self scrollAndSelectRow:[_instructions indexOfObject:foundInstructionInTable]];
		if (self.window.firstResponder != _backtraceViewController.tableView && !didFindSymbol)
		{
			[self.window makeFirstResponder:_instructionsTableView];
		}
		
		[self updateNavigationButtons];
		[self invalidateRestorableState];
		
		return;
	}
	
	NSArray<ZGRegion *> *memoryRegions = [ZGRegion regionsFromProcessTask:self.currentProcess.processTask];
	if (memoryRegions.count == 0)
	{
		cleanupOnFailure();
		return;
	}
	
	ZGRegion *chosenRegion = [memoryRegions zgFirstObjectThatMatchesCondition:^(ZGRegion *region) {
		return (BOOL)((region.protection & VM_PROT_READ) != 0 && (calculatedMemoryAddress >= region.address && calculatedMemoryAddress < region.address + region.size));
	}];
	
	if (chosenRegion != nil)
	{
		NSArray<ZGRegion *> *submapRegions =  [ZGRegion submapRegionsFromProcessTask:self.currentProcess.processTask region:chosenRegion];
		
		chosenRegion = [submapRegions zgFirstObjectThatMatchesCondition:^(ZGRegion *region) {
			return (BOOL)((region.protection & VM_PROT_READ) != 0 && (calculatedMemoryAddress >= region.address && calculatedMemoryAddress < region.address + region.size));
		}];
	}
	
	if (chosenRegion == nil)
	{
		cleanupOnFailure();
		return;
	}
	
	ZGMemoryAddress firstInstructionAddress = 0;
	ZGMemorySize maxInstructionsSize = 0;
	NSString *mappedFilePath = @"";
	ZGMemoryAddress baseAddress = 0;
	
	if (!shouldUseFirstInstruction)
	{
		ZGMachBinary *machBinary = [ZGMachBinary machBinaryNearestToAddress:calculatedMemoryAddress fromMachBinaries:machBinaries];
		ZGMachBinaryInfo *machBinaryInfo = [machBinary machBinaryInfoInProcess:self.currentProcess];
		NSRange instructionRange = NSMakeRange(machBinaryInfo.firstInstructionAddress, machBinaryInfo.totalSegmentRange.length - (machBinaryInfo.firstInstructionAddress - machBinaryInfo.totalSegmentRange.location));
		
		baseAddress = machBinary.headerAddress;
		mappedFilePath = [machBinary filePathInProcess:self.currentProcess];
		
		firstInstructionAddress = instructionRange.location;
		maxInstructionsSize = instructionRange.length;
		
		if (firstInstructionAddress + maxInstructionsSize < chosenRegion.address || firstInstructionAddress >= chosenRegion.address + chosenRegion.size)
		{
			// let's use the chosen region if the text section doesn't intersect with it
			firstInstructionAddress = chosenRegion.address;
			maxInstructionsSize = chosenRegion.size;
			mappedFilePath = @"";
			baseAddress = 0;
		}
		else if (calculatedMemoryAddress < firstInstructionAddress)
		{
			calculatedMemoryAddress = firstInstructionAddress;
			[self.addressTextField setStringValue:[NSString stringWithFormat:@"0x%llX", calculatedMemoryAddress]];
		}
	}
	else
	{
		firstInstructionAddress = calculatedMemoryAddress;
		maxInstructionsSize = machInstructionRange.length - (calculatedMemoryAddress - machInstructionRange.location);
		mappedFilePath = [mainMachBinary filePathInProcess:self.currentProcess];
		baseAddress = mainMachBinary.headerAddress;
	}
	
	_mappedFilePath = mappedFilePath;
	_baseAddress = baseAddress;
	_offsetFromBase = calculatedMemoryAddress - baseAddress;
	
	// Make sure disassembler won't show anything before this address
	_instructionBoundary = NSMakeRange(firstInstructionAddress, maxInstructionsSize);
	
	// Disassemble within a range from +- WINDOW_SIZE from selection address
	const NSUInteger WINDOW_SIZE = 512;
	
	ZGMemoryAddress lowBoundAddress = calculatedMemoryAddress - WINDOW_SIZE;
	if (lowBoundAddress <= firstInstructionAddress)
	{
		lowBoundAddress = firstInstructionAddress;
	}
	else
	{
		lowBoundAddress = [ZGDebuggerUtilities findInstructionBeforeAddress:lowBoundAddress inProcess:self.currentProcess withBreakPoints:_breakPointController.breakPoints machBinaries:machBinaries].variable.address;
		if (lowBoundAddress < firstInstructionAddress)
		{
			lowBoundAddress = firstInstructionAddress;
		}
	}
	
	ZGMemoryAddress highBoundAddress = calculatedMemoryAddress + WINDOW_SIZE;
	if (highBoundAddress >= chosenRegion.address + chosenRegion.size)
	{
		highBoundAddress = chosenRegion.address + chosenRegion.size;
	}
	else
	{
		highBoundAddress = [ZGDebuggerUtilities findInstructionBeforeAddress:highBoundAddress inProcess:self.currentProcess withBreakPoints:_breakPointController.breakPoints machBinaries:machBinaries].variable.address;
		if (highBoundAddress <= chosenRegion.address || highBoundAddress > chosenRegion.address + chosenRegion.size)
		{
			highBoundAddress = chosenRegion.address + chosenRegion.size;
		}
	}
	
	[self.undoManager removeAllActions];
	[self updateDisassemblerWithAddress:lowBoundAddress size:highBoundAddress - lowBoundAddress selectionAddress:calculatedMemoryAddress andChangeFirstResponder:!didFindSymbol];
	
	[self invalidateRestorableState];
}

#pragma mark Useful methods for the world

- (NSIndexSet *)selectedInstructionIndexes
{
	NSIndexSet *tableIndexSet = _instructionsTableView.selectedRowIndexes;
	NSInteger clickedRow = _instructionsTableView.clickedRow;
	
	return (clickedRow >= 0 && ![tableIndexSet containsIndex:(NSUInteger)clickedRow]) ? [NSIndexSet indexSetWithIndex:(NSUInteger)clickedRow] : tableIndexSet;
}

- (NSArray<ZGInstruction *> *)selectedInstructions
{
	return [_instructions objectsAtIndexes:[self selectedInstructionIndexes]];
}

- (HFRange)preferredMemoryRequestRange
{
	NSArray<ZGInstruction *> *selectedInstructions = [self selectedInstructions];
	ZGInstruction *firstInstruction = [selectedInstructions firstObject];
	ZGInstruction *lastInstruction = [selectedInstructions lastObject];
	
	if (firstInstruction == nil)
	{
		return [super preferredMemoryRequestRange];
	}
	
	return HFRangeMake(firstInstruction.variable.address, lastInstruction.variable.address + lastInstruction.variable.size - firstInstruction.variable.address);
}

- (void)jumpToMemoryAddress:(ZGMemoryAddress)address
{
	[self jumpToMemoryAddress:address inProcess:self.currentProcess];
}

- (void)jumpToMemoryAddress:(ZGMemoryAddress)address inProcess:(ZGProcess *)requestedProcess
{
	[self jumpToMemoryAddressStringValue:[NSString stringWithFormat:@"0x%llX", address] inProcess:requestedProcess];
}

- (void)jumpToMemoryAddressStringValue:(NSString *)memoryAddressStringValue inProcess:(ZGProcess *)requestedProcess
{
	NSMenuItem *targetMenuItem = nil;
	for (NSMenuItem *menuItem in self.runningApplicationsPopUpButton.menu.itemArray)
	{
		ZGProcess *process = menuItem.representedObject;
		if ([process isEqual:requestedProcess])
		{
			targetMenuItem = menuItem;
			break;
		}
	}
	
	if (targetMenuItem != nil)
	{
		self.addressTextField.stringValue = memoryAddressStringValue;
		
		if (![(ZGProcess *)targetMenuItem.representedObject isEqual:self.currentProcess])
		{
			[self.runningApplicationsPopUpButton selectItem:targetMenuItem];
			
			_instructions = @[];
			[_instructionsTableView reloadData];
			
			[self switchProcessMenuItemAndSelectAddressStringValue:memoryAddressStringValue];
		}
		else
		{
			[self readMemory:self];
		}
	}
	else
	{
		NSLog(@"Could not find target process!");
	}
}

- (BOOL)canContinueOrStepIntoExecution
{
	return [self currentBreakPoint] != nil;
}

- (BOOL)canStepOverExecution
{
	if ([self currentBreakPoint] == nil)
	{
		return NO;
	}
	
	NSArray<ZGMachBinary *> *machBinaries = [ZGMachBinary machBinariesInProcess:self.currentProcess];
	
	ZGInstruction *currentInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:_registersViewController.instructionPointer + 1 inProcess:self.currentProcess withBreakPoints:_breakPointController.breakPoints machBinaries:machBinaries];
	if (!currentInstruction)
	{
		return NO;
	}
	
	if ([ZGDisassemblerObject isCallMnemonic:currentInstruction.mnemonic])
	{
		ZGInstruction *nextInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:currentInstruction.variable.address + currentInstruction.variable.size + 1 inProcess:self.currentProcess withBreakPoints:_breakPointController.breakPoints machBinaries:machBinaries];
		if (!nextInstruction)
		{
			return NO;
		}
	}
	
	return YES;
}

- (BOOL)canStepOutOfExecution
{
	if ([self currentBreakPoint] == nil)
	{
		return NO;
	}
	
	if (_backtraceViewController.backtrace.instructions.count <= 1 || _backtraceViewController.backtrace.basePointers.count <= 1)
	{
		return NO;
	}
	
	ZGInstruction *outterInstruction = [_backtraceViewController.backtrace.instructions objectAtIndex:1];
	ZGInstruction *returnInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:outterInstruction.variable.address + outterInstruction.variable.size + 1 inProcess:self.currentProcess withBreakPoints:_breakPointController.breakPoints machBinaries:[ZGMachBinary machBinariesInProcess:self.currentProcess]];
	
	if (!returnInstruction)
	{
		return NO;
	}
	
	return YES;
}

- (void)updateExecutionButtons
{
	[_continueButton setEnabled:[self canContinueOrStepIntoExecution]];
	
	[_stepExecutionSegmentedControl setEnabled:[self canContinueOrStepIntoExecution] forSegment:ZGStepIntoExecution];
	[_stepExecutionSegmentedControl setEnabled:[self canStepOverExecution] forSegment:ZGStepOverExecution];
	[_stepExecutionSegmentedControl setEnabled:[self canStepOutOfExecution] forSegment:ZGStepOutExecution];
}

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)userInterfaceItem
{
	NSMenuItem *menuItem = [(NSObject *)userInterfaceItem isKindOfClass:[NSMenuItem class]] ? (NSMenuItem *)userInterfaceItem : nil;
	
	if (userInterfaceItem.action == @selector(nopVariables:))
	{
		NSArray<ZGInstruction *> *selectedInstructions = [self selectedInstructions];
		NSString *localizableKey = [NSString stringWithFormat:@"nopInstruction%@", selectedInstructions.count != 1 ? @"s" : @""];
		menuItem.title = ZGLocalizedStringFromDebuggerTable(localizableKey);
		
		if (selectedInstructions.count == 0 || !self.currentProcess.valid || _instructionsTableView.editedRow != -1)
		{
			return NO;
		}
	}
	else if (userInterfaceItem.action == @selector(copy:))
	{
		if ([self selectedInstructions].count == 0)
		{
			return NO;
		}
	}
	else if (userInterfaceItem.action == @selector(copyAddress:))
	{
		if ([self selectedInstructions].count != 1)
		{
			return NO;
		}
	}
	else if (userInterfaceItem.action == @selector(continueExecution:) || userInterfaceItem.action == @selector(stepInto:))
	{
		if (![self canContinueOrStepIntoExecution])
		{
			return NO;
		}
	}
	else if (userInterfaceItem.action == @selector(stepOver:))
	{
		if (![self canStepOverExecution])
		{
			return NO;
		}
	}
	else if (userInterfaceItem.action == @selector(stepOut:))
	{
		if (![self canStepOutOfExecution])
		{
			return NO;
		}
	}
	else if (userInterfaceItem.action == @selector(toggleBreakPoints:))
	{
		NSArray<ZGInstruction *> *selectedInstructions = [self selectedInstructions];
		if (selectedInstructions.count == 0)
		{
			menuItem.title = ZGLocalizedStringFromDebuggerTable(@"addBreakpoint");
			return NO;
		}
		
		BOOL shouldValidate = YES;
		BOOL isBreakPoint = [self isBreakPointAtInstruction:[selectedInstructions objectAtIndex:0]];
		BOOL didSkipFirstInstruction = NO;
		for (ZGInstruction *instruction in selectedInstructions)
		{
			if (!didSkipFirstInstruction)
			{
				didSkipFirstInstruction = YES;
			}
			else
			{
				if ([self isBreakPointAtInstruction:instruction] != isBreakPoint)
				{
					shouldValidate = NO;
					break;
				}
			}
		}
		
		NSString *localizableKey = [NSString stringWithFormat:@"%@Breakpoint%@", isBreakPoint ? @"remove" : @"add", selectedInstructions.count != 1 ? @"s" : @""];
		menuItem.title = ZGLocalizedStringFromDebuggerTable(localizableKey);
		
		return shouldValidate;
	}
	else if (userInterfaceItem.action == @selector(removeAllBreakPoints:))
	{
		if (![self hasBreakPoint])
		{
			return NO;
		}
	}
	else if (userInterfaceItem.action == @selector(jump:))
	{
		if ([self currentBreakPoint] == nil || [self selectedInstructions].count != 1)
		{
			return NO;
		}
	}
	else if (userInterfaceItem.action == @selector(jumpToOperandOffset:))
	{
		if (!self.currentProcess.valid)
		{
			menuItem.title = ZGLocalizedStringFromDebuggerTable(@"goToCallAddress");
			return NO;
		}
		
		NSArray<ZGInstruction *> *selectedInstructions = [self selectedInstructions];
		if (selectedInstructions.count != 1)
		{
			menuItem.title = ZGLocalizedStringFromDebuggerTable(@"goToCallAddress");
			return NO;
		}
		
		ZGInstruction *selectedInstruction = [selectedInstructions objectAtIndex:0];
		if ([ZGDisassemblerObject isCallMnemonic:selectedInstruction.mnemonic])
		{
			menuItem.title = ZGLocalizedStringFromDebuggerTable(@"goToCallAddress");
		}
		else if ([ZGDisassemblerObject isJumpMnemonic:selectedInstruction.mnemonic])
		{
			menuItem.title = ZGLocalizedStringFromDebuggerTable(@"goToBranchAddress");
		}
		else
		{
			return NO;
		}
	}
	else if (userInterfaceItem.action == @selector(showMemoryViewer:))
	{
		if ([[self selectedInstructions] count] == 0)
		{
			return NO;
		}
	}
	else if (userInterfaceItem.action == @selector(requestCodeInjection:))
	{
		if ([[self selectedInstructions] count] != 1)
		{
			return NO;
		}
	}
	else if (userInterfaceItem.action == @selector(showBreakPointCondition:))
	{
		if ([[self selectedInstructions] count] != 1)
		{
			return NO;
		}
	}
	
	return [super validateUserInterfaceItem:userInterfaceItem];
}

- (void)annotateInstructions:(NSArray<ZGInstruction *> *)instructions
{
	NSArray<ZGVariable *> *variablesToAnnotate = [[instructions zgMapUsingBlock:^(ZGInstruction *instruction) { return instruction.variable; }]
	 zgFilterUsingBlock:^(ZGVariable *variable) {
		 return (BOOL)(!variable.usesDynamicAddress);
	 }];
	
	[ZGVariableController annotateVariables:variablesToAnnotate process:self.currentProcess];
	
	for (ZGInstruction *instruction in instructions)
	{
		if (instruction.variable.fullAttributedDescription.length == 0)
		{
			instruction.variable.fullAttributedDescription = [[NSAttributedString alloc] initWithString:instruction.text];
		}
		else if ([variablesToAnnotate containsObject:instruction.variable])
		{
			NSMutableAttributedString *newDescription = [[NSMutableAttributedString alloc] initWithString:[instruction.text stringByAppendingString:@"\n"]];
			[newDescription appendAttributedString:instruction.variable.fullAttributedDescription];
			instruction.variable.fullAttributedDescription = newDescription;
		}
	}
}

- (IBAction)copy:(id)__unused sender
{
	NSArray<ZGInstruction *> *selectedInstructions = [self selectedInstructions];
	
	[self annotateInstructions:selectedInstructions];
	
	NSMutableArray<NSString *> *descriptionComponents = [[NSMutableArray alloc] init];
	NSMutableArray<ZGVariable *> *variablesArray = [[NSMutableArray alloc] init];
	
	for (ZGInstruction *instruction in selectedInstructions)
	{
		[descriptionComponents addObject:[@[instruction.variable.addressFormula, instruction.text, instruction.variable.stringValue] componentsJoinedByString:@"\t"]];
		[variablesArray addObject:instruction.variable];
	}
	
	[[NSPasteboard generalPasteboard] declareTypes:@[NSStringPboardType, ZGVariablePboardType] owner:self];
	[[NSPasteboard generalPasteboard] setString:[descriptionComponents componentsJoinedByString:@"\n"] forType:NSStringPboardType];
	[[NSPasteboard generalPasteboard] setData:[NSKeyedArchiver archivedDataWithRootObject:variablesArray] forType:ZGVariablePboardType];
}

- (IBAction)copyAddress:(id)__unused sender
{
	ZGInstruction *selectedInstruction = [[self selectedInstructions] objectAtIndex:0];
	[self annotateInstructions:@[selectedInstruction]];

	[[NSPasteboard generalPasteboard] declareTypes:@[NSStringPboardType] owner:self];
	[[NSPasteboard generalPasteboard] setString:selectedInstruction.variable.addressFormula forType:NSStringPboardType];
}

- (void)scrollAndSelectRow:(NSUInteger)selectionRow
{
	// Scroll such that the selected row is centered
	[_instructionsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:selectionRow] byExtendingSelection:NO];
	NSRange visibleRowsRange = [_instructionsTableView rowsInRect:_instructionsTableView.visibleRect];
	if (visibleRowsRange.location + visibleRowsRange.length / 2 < selectionRow)
	{
		[_instructionsTableView scrollRowToVisible:(NSInteger)MIN(selectionRow + visibleRowsRange.length / 2, _instructions.count-1)];
	}
	else if (visibleRowsRange.location + visibleRowsRange.length / 2 > selectionRow)
	{
		// Make sure we don't go below 0 in unsigned arithmetic
		if (visibleRowsRange.length / 2 > selectionRow)
		{
			[_instructionsTableView scrollRowToVisible:0];
		}
		else
		{
			[_instructionsTableView scrollRowToVisible:(NSInteger)(selectionRow - visibleRowsRange.length / 2)];
		}
	}
}

#pragma mark TableView Methods

- (BOOL)tableView:(NSTableView *)__unused tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard
{
	NSArray<ZGInstruction *> *instructions = [_instructions objectsAtIndexes:rowIndexes];
	[self annotateInstructions:instructions];
	
	NSArray<ZGVariable *> *variables = [instructions zgMapUsingBlock:^(ZGInstruction *instruction) {
		return instruction.variable;
	}];
	
	return [pboard setData:[NSKeyedArchiver archivedDataWithRootObject:variables] forType:ZGVariablePboardType];
}

- (void)tableViewSelectionDidChange:(NSNotification *)__unused aNotification
{
	if (_instructions.count > 0)
	{
		NSArray<ZGInstruction *> *selectedInstructions = [self selectedInstructions];
		if (selectedInstructions.count > 0)
		{
			ZGInstruction *firstInstruction = [selectedInstructions objectAtIndex:0];
			
			// I think the cast may be necessary due to a possible compiler bug
			id <ZGMemorySelectionDelegate> delegate = (id <ZGMemorySelectionDelegate>)(self.delegate);
			if (delegate != nil)
			{
				assert([delegate conformsToProtocol:@protocol(ZGMemorySelectionDelegate)]);
				[delegate memorySelectionDidChange:NSMakeRange(firstInstruction.variable.address, firstInstruction.variable.size) process:self.currentProcess];
			}
		}
	}
	[self updateStatusBar];
}

- (BOOL)isBreakPointAtInstruction:(ZGInstruction *)instruction
{
	return [_breakPointController.breakPoints zgHasObjectMatchingCondition:^(ZGBreakPoint *breakPoint) {
		return (BOOL)(breakPoint.delegate == self && breakPoint.type == ZGBreakPointInstruction && breakPoint.task == self.currentProcess.processTask && breakPoint.variable.address == instruction.variable.address && !breakPoint.hidden);
	}];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)__unused tableView
{
	return (NSInteger)_instructions.count;
}

- (id)tableView:(NSTableView *)__unused tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	id result = nil;
	if (rowIndex >= 0 && (NSUInteger)rowIndex < _instructions.count)
	{
		ZGInstruction *instruction = [_instructions objectAtIndex:(NSUInteger)rowIndex];
		if ([tableColumn.identifier isEqualToString:@"address"])
		{
			result = instruction.variable.addressStringValue;
		}
		else if ([tableColumn.identifier isEqualToString:@"instruction"])
		{
			result = instruction.text;
		}
		else if ([tableColumn.identifier isEqualToString:@"symbols"])
		{
			result = instruction.symbols;
		}
		else if ([tableColumn.identifier isEqualToString:@"bytes"])
		{
			result = instruction.variable.stringValue;
		}
		else if ([tableColumn.identifier isEqualToString:@"breakpoint"])
		{
			result = @([self isBreakPointAtInstruction:instruction]);
		}
	}
	
	return result;
}

- (void)tableView:(NSTableView *)__unused tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if (rowIndex >= 0 && (NSUInteger)rowIndex < _instructions.count)
	{
		if ([tableColumn.identifier isEqualToString:@"bytes"])
		{
			[self writeStringValue:object atInstructionFromIndex:(NSUInteger)rowIndex];
		}
		else if ([tableColumn.identifier isEqualToString:@"instruction"])
		{
			[self writeInstructionText:object atInstructionFromIndex:(NSUInteger)rowIndex];
		}
		else if ([tableColumn.identifier isEqualToString:@"breakpoint"])
		{
			NSArray<ZGInstruction *> *targetInstructions = nil;
			NSArray<ZGInstruction *> *selectedInstructions = [self selectedInstructions];
			ZGInstruction *instruction = [_instructions objectAtIndex:(NSUInteger)rowIndex];
			if (![selectedInstructions containsObject:instruction])
			{
				targetInstructions = @[instruction];
			}
			else
			{
				targetInstructions = selectedInstructions;
				if (targetInstructions.count > 1)
				{
					_instructionsTableView.shouldIgnoreNextSelection = YES;
				}
			}
			
			if ([(NSNumber *)object boolValue])
			{
				[self addBreakPointsToInstructions:targetInstructions];
			}
			else
			{
				[self removeBreakPointsToInstructions:targetInstructions];
			}
		}
	}
}

- (void)tableView:(NSTableView *)__unused tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if ([tableColumn.identifier isEqualToString:@"address"] && rowIndex >= 0 && (NSUInteger)rowIndex < _instructions.count)
	{
		ZGInstruction *instruction = [_instructions objectAtIndex:(NSUInteger)rowIndex];
		BOOL isInstructionBreakPoint = ([self currentBreakPoint] && _registersViewController.instructionPointer == instruction.variable.address);
		
		[(NSTextFieldCell *)cell setTextColor:isInstructionBreakPoint ? NSColor.systemRedColor : NSColor.controlTextColor];
	}
}

- (NSString *)tableView:(NSTableView *)__unused tableView toolTipForCell:(NSCell *)__unused cell rect:(NSRectPointer)__unused rect tableColumn:(NSTableColumn *)__unused tableColumn row:(NSInteger)row mouseLocation:(NSPoint)__unused mouseLocation
{
	NSString *toolTip = nil;
	
	if (row >= 0 && (NSUInteger)row < _instructions.count)
	{
		ZGInstruction *instruction = [_instructions objectAtIndex:(NSUInteger)row];
		
		for (ZGBreakPointCondition *breakPointCondition in _breakPointConditions)
		{
			if ([breakPointCondition.internalProcessName isEqualToString:self.currentProcess.internalName] && instruction.variable.address == breakPointCondition.address)
			{
				toolTip = [NSString stringWithFormat:@"%@: %@", ZGLocalizedStringFromDebuggerTable(@"breakpointConditionTooltipLabel"), breakPointCondition.condition];
				break;
			}
		}
	}
	
	return toolTip;
}

#pragma mark Modifying instructions

- (void)writeInstructionText:(NSString *)instructionText atInstructionFromIndex:(NSUInteger)instructionIndex
{
	NSError *error = nil;
	ZGInstruction *firstInstruction = [_instructions objectAtIndex:instructionIndex];
	NSData *data = [ZGDebuggerUtilities assembleInstructionText:instructionText atInstructionPointer:firstInstruction.variable.address usingArchitectureBits:self.currentProcess.pointerSize * 8 error:&error];
	if (data.length == 0)
	{
		if (error != nil)
		{
			ZG_LOG(@"%@", error);
			ZGRunAlertPanelWithOKButton(ZGLocalizedStringFromDebuggerTable(@"failedModifyInstructionAlertTitle"), [NSString stringWithFormat:@"%@ \"%@\": %@", ZGLocalizedStringFromDebuggerTable(@"failedModifyInstructionAlertMessage"), instructionText, [error.userInfo objectForKey:@"reason"]]);
		}
	}
	else
	{
		NSMutableData *outputData = [NSMutableData dataWithData:data];
		
		// Fill leftover bytes with NOP's so that the instructions won't 'slide'
		NSUInteger originalOutputLength = outputData.length;
		NSUInteger bytesRead = 0;
		NSUInteger numberOfInstructionsOverwritten = 0;
		
		for (ZGMemorySize currentInstructionIndex = instructionIndex; (bytesRead < originalOutputLength) && (currentInstructionIndex < _instructions.count); currentInstructionIndex++)
		{
			ZGInstruction *currentInstruction = [_instructions objectAtIndex:currentInstructionIndex];
			bytesRead += currentInstruction.variable.size;
			numberOfInstructionsOverwritten++;
			
			if (bytesRead > originalOutputLength)
			{
				const uint8_t nopValue = NOP_VALUE;
				for (ZGMemorySize byteIndex = currentInstruction.variable.address + currentInstruction.variable.size - (bytesRead - originalOutputLength); byteIndex < currentInstruction.variable.address + currentInstruction.variable.size; byteIndex++)
				{
					[outputData appendBytes:&nopValue length:sizeof(int8_t)];
				}
			}
		}
		
		if (bytesRead < originalOutputLength)
		{
			ZGRunAlertPanelWithOKButton(ZGLocalizedStringFromDebuggerTable(@"failedOverwriteInstructionsAlertTitle"), ZGLocalizedStringFromDebuggerTable(@"failedOverwriteInstructionsAlertMessage"));
		}
		else
		{
			BOOL shouldOverwriteInstructions = YES;
			if (numberOfInstructionsOverwritten > 1)
			{
				if (ZGRunAlertPanelWithDefaultAndCancelButton(ZGLocalizedStringFromDebuggerTable(@"overwriteConfirmationAlertTitle"), [NSString stringWithFormat:ZGLocalizedStringFromDebuggerTable(@"overwriteConfirmationAlertMessageFormat"), numberOfInstructionsOverwritten], ZGLocalizedStringFromDebuggerTable(@"overwrite")) == NSAlertSecondButtonReturn)
				{
					shouldOverwriteInstructions = NO;
				}
			}
			
			if (shouldOverwriteInstructions)
			{
				ZGVariable *newVariable = [[ZGVariable alloc] initWithValue:outputData.bytes size:outputData.length address:0 type:ZGByteArray qualifier:ZGSigned pointerSize:self.currentProcess.pointerSize];
				
				[self writeStringValue:newVariable.stringValue atInstructionFromIndex:instructionIndex];
			}
		}
	}
}

- (void)writeStringValue:(NSString *)stringValue atInstructionFromIndex:(NSUInteger)initialInstructionIndex
{
	ZGInstruction *instruction = [_instructions objectAtIndex:initialInstructionIndex];
	
	// Make sure the old and new value that we are writing have the same size in bytes, so that undo/redo will work correctly for different sizes
	
	ZGMemorySize newWriteSize = 0;
	void *newWriteValue = ZGValueFromString(self.currentProcess.is64Bit, stringValue, ZGByteArray, &newWriteSize);
	if (newWriteValue)
	{
		if (newWriteSize > 0)
		{
			void *oldValue = calloc(1, newWriteSize);
			if (oldValue)
			{
				NSUInteger instructionIndex = initialInstructionIndex;
				ZGMemorySize writeIndex = 0;
				while (writeIndex < newWriteSize && instructionIndex < _instructions.count)
				{
					ZGInstruction *currentInstruction = [_instructions objectAtIndex:instructionIndex];
					for (ZGMemorySize valueIndex = 0; (writeIndex < newWriteSize) && (valueIndex < currentInstruction.variable.size); valueIndex++, writeIndex++)
					{
						*((uint8_t *)oldValue + writeIndex) = *((uint8_t *)currentInstruction.variable.rawValue + valueIndex);
					}
					
					instructionIndex++;
				}
				
				if (writeIndex >= newWriteSize)
				{
					ZGVariable *newVariable = [[ZGVariable alloc] initWithValue:newWriteValue size:newWriteSize address:instruction.variable.address type:ZGByteArray qualifier:ZGSigned pointerSize:self.currentProcess.pointerSize];
					
					ZGVariable *oldVariable = [[ZGVariable alloc] initWithValue:oldValue size:newWriteSize address:instruction.variable.address type:ZGByteArray qualifier:ZGSigned pointerSize:self.currentProcess.pointerSize];
					
					[ZGDebuggerUtilities replaceInstructions:@[instruction] fromOldStringValues:@[oldVariable.stringValue] toNewStringValues:@[newVariable.stringValue] inProcess:self.currentProcess breakPoints:_breakPointController.breakPoints undoManager:self.undoManager actionName:ZGLocalizedStringFromDebuggerTable(@"undoInstructionChange")];
				}
				
				free(oldValue);
			}
		}
		
		free(newWriteValue);
	}
}

- (IBAction)nopVariables:(id)__unused sender
{
	[ZGDebuggerUtilities nopInstructions:[self selectedInstructions] inProcess:self.currentProcess breakPoints:_breakPointController.breakPoints undoManager:self.undoManager actionName:ZGLocalizedStringFromDebuggerTable(@"undoNOPChange")];
}

- (IBAction)requestCodeInjection:(id)__unused sender
{
	if (_codeInjectionController == nil)
	{
		_codeInjectionController = [[ZGCodeInjectionWindowController alloc] init];
	}
	
	[_codeInjectionController
	 attachToWindow:ZGUnwrapNullableObject(self.window)
	 process:self.currentProcess
	 instruction:[[self selectedInstructions] objectAtIndex:0]
	 breakPoints:_breakPointController.breakPoints
	 undoManager:self.undoManager];
}

#pragma mark Break Points

- (BOOL)hasBreakPoint
{
	return [_breakPointController.breakPoints zgHasObjectMatchingCondition:^(ZGBreakPoint *breakPoint) { return (BOOL)(breakPoint.delegate == self); }];
}

- (void)startBreakPointActivity
{
	if (_breakPointActivity == nil)
	{
		_breakPointActivity = [[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityBackground reason:@"Software Breakpoint"];
	}
}

- (void)stopBreakPointActivity
{
	if (_breakPointActivity != nil)
	{
		[[NSProcessInfo processInfo] endActivity:(id _Nonnull)_breakPointActivity];
		_breakPointActivity = nil;
	}
}

- (void)removeBreakPointsToInstructions:(NSArray<ZGInstruction *> *)instructions
{
	NSMutableArray<ZGInstruction *> *changedInstructions = [[NSMutableArray alloc] init];
	
	for (ZGInstruction *instruction in instructions)
	{
		if ([self isBreakPointAtInstruction:instruction])
		{
			[changedInstructions addObject:instruction];
			[_breakPointController removeBreakPointOnInstruction:instruction inProcess:self.currentProcess];
		}
	}
	
	if (![self hasBreakPoint])
	{
		[self stopBreakPointActivity];
	}
	
	NSString *localizableKey = [NSString stringWithFormat:@"addBreakpoint%@", changedInstructions.count != 1 ? @"s" : @""];
	[self.undoManager setActionName:ZGLocalizedStringFromDebuggerTable(localizableKey)];
	[(ZGDebuggerController *)[self.undoManager prepareWithInvocationTarget:self] addBreakPointsToInstructions:changedInstructions];
	
	[_instructionsTableView reloadData];
}

- (void)conditionalInstructionBreakPointWasRemoved
{
	[_instructionsTableView reloadData];
}

- (void)addBreakPointsToInstructions:(NSArray<ZGInstruction *> *)instructions
{
	NSMutableArray<ZGInstruction *> *changedInstructions = [[NSMutableArray alloc] init];
	
	BOOL addedAtLeastOneBreakPoint = NO;
	
	for (ZGInstruction *instruction in instructions)
	{
		if (![self isBreakPointAtInstruction:instruction])
		{
			[changedInstructions addObject:instruction];
			
			PyObject *compiledCondition = NULL;
			for (ZGBreakPointCondition *breakPointCondition in _breakPointConditions)
			{
				if (breakPointCondition.address == instruction.variable.address && [breakPointCondition.internalProcessName isEqualToString:self.currentProcess.internalName])
				{
					compiledCondition = breakPointCondition.compiledCondition;
					break;
				}
			}
			
			if ([_breakPointController addBreakPointOnInstruction:instruction inProcess:self.currentProcess condition:compiledCondition delegate:self])
			{
				addedAtLeastOneBreakPoint = YES;
			}
		}
	}
	
	if (addedAtLeastOneBreakPoint)
	{
		[self startBreakPointActivity];
		
		NSString *localizableKey = [NSString stringWithFormat:@"removeBreakpoint%@", changedInstructions.count != 1 ? @"s" : @""];
		[self.undoManager setActionName:ZGLocalizedStringFromDebuggerTable(localizableKey)];
		[(ZGDebuggerController *)[self.undoManager prepareWithInvocationTarget:self] removeBreakPointsToInstructions:changedInstructions];
		[_instructionsTableView reloadData];
	}
	else
	{
		ZGRunAlertPanelWithOKButton(ZGLocalizedStringFromDebuggerTable(@"failedAddBreakpointAlertTitle"), ZGLocalizedStringFromDebuggerTable(@"failedAddBreakpointAlertMessage"));
	}
}

- (IBAction)toggleBreakPoints:(id)__unused sender
{
	NSArray<ZGInstruction *> *selectedInstructions = [self selectedInstructions];
	if ([self isBreakPointAtInstruction:[selectedInstructions objectAtIndex:0]])
	{
		[self removeBreakPointsToInstructions:selectedInstructions];
	}
	else
	{
		[self addBreakPointsToInstructions:selectedInstructions];
	}
}

- (IBAction)removeAllBreakPoints:(id)__unused sender
{
	[_breakPointController removeObserver:self];
	[self stopBreakPointActivity];
	[self.undoManager removeAllActions];
	[_instructionsTableView reloadData];
}

- (void)addHaltedBreakPoint:(ZGBreakPoint *)breakPoint
{
	[_haltedBreakPoints addObject:breakPoint];
	
	if ([breakPoint.process isEqual:self.currentProcess])
	{
		[_instructionsTableView reloadData];
	}
}

- (void)removeHaltedBreakPoint:(ZGBreakPoint *)breakPoint
{
	[_haltedBreakPoints removeObject:breakPoint];
	
	if ([breakPoint.process isEqual:self.currentProcess])
	{
		[_instructionsTableView reloadData];
	}
}

- (ZGBreakPoint *)currentBreakPoint
{
	return [_haltedBreakPoints zgFirstObjectThatMatchesCondition:^BOOL(ZGBreakPoint *breakPoint) {
		return [breakPoint.process isEqual:self.currentProcess];
	}];
}

- (ZGInstruction *)findInstructionInTableAtAddress:(ZGMemoryAddress)targetAddress
{
	ZGInstruction *foundInstruction = [_instructions zgBinarySearchUsingBlock:^NSComparisonResult(__unsafe_unretained ZGInstruction *instruction) {
		if (targetAddress >= instruction.variable.address + instruction.variable.size)
		{
			return NSOrderedAscending;
		}
		else if (targetAddress < instruction.variable.address)
		{
			return NSOrderedDescending;
		}
		else
		{
			return NSOrderedSame;
		}
	}];
	
	return foundInstruction;
}

- (void)instructionPointerDidChange
{
	[_instructionsTableView reloadData];
}

- (void)moveInstructionPointerToAddress:(ZGMemoryAddress)newAddress
{
	if ([self currentBreakPoint] != nil)
	{
		ZGMemoryAddress currentAddress = _registersViewController.instructionPointer;
		[_registersViewController changeInstructionPointer:newAddress];
		[(ZGDebuggerController *)[self.undoManager prepareWithInvocationTarget:self] moveInstructionPointerToAddress:currentAddress];
		[self.undoManager setActionName:ZGLocalizedStringFromDebuggerTable(@"undoMoveInstructionPointer")];
	}
}

- (IBAction)jump:(id)__unused sender
{
	ZGInstruction *instruction = [[self selectedInstructions] objectAtIndex:0];
	[self moveInstructionPointerToAddress:instruction.variable.address];
}

- (void)updateBacktrace
{
	ZGBacktrace *backtrace = [ZGBacktrace backtraceWithBasePointer:_registersViewController.basePointer instructionPointer:_registersViewController.instructionPointer process:self.currentProcess breakPoints:_breakPointController.breakPoints machBinaries:[ZGMachBinary machBinariesInProcess:self.currentProcess]];
	
	if ([self shouldUpdateSymbolsForInstructions:backtrace.instructions])
	{
		[self updateSymbolsForInstructions:backtrace.instructions];
	}
	
	for (ZGInstruction *instruction in backtrace.instructions)
	{
		if (instruction.symbols.length == 0)
		{
			instruction.symbols = @""; // in case symbols is nil
			instruction.variable.fullAttributedDescription = [[NSAttributedString alloc] initWithString:instruction.variable.addressStringValue attributes:@{NSForegroundColorAttributeName : [NSColor textColor]}];
		}
		else
		{
			instruction.variable.fullAttributedDescription = [[NSAttributedString alloc] initWithString:(NSString * _Nonnull)instruction.symbols attributes:@{NSForegroundColorAttributeName : [NSColor textColor]}];
		}
	}
	
	_backtraceViewController.backtrace = backtrace;
	_backtraceViewController.process = [[ZGProcess alloc] initWithProcess:self.currentProcess];
}

- (void)backtraceSelectionChangedToAddress:(ZGMemoryAddress)address
{
	[self jumpToMemoryAddress:address inProcess:self.currentProcess];
}

- (void)breakPointDidHit:(ZGBreakPoint *)breakPoint
{
	[self removeHaltedBreakPoint:[self currentBreakPoint]];
	[self addHaltedBreakPoint:breakPoint];
	
	ZGBreakPoint *currentBreakPoint = [self currentBreakPoint];
	
	if (currentBreakPoint != nil)
	{
		NSWindow *window = ZGUnwrapNullableObject(self.window);
		if (!window.isVisible)
		{
			[self showWindow:nil];
		}
		
		if (_registersViewController == nil)
		{
			_registersViewController = [[ZGRegistersViewController alloc] initWithWindow:window undoManager:self.undoManager delegate:self];
			
			[_registersView addSubview:_registersViewController.view];
			_registersViewController.view.frame = _registersView.bounds;
		}
		
		if (_backtraceViewController == nil)
		{
			_backtraceViewController = [[ZGBacktraceViewController alloc] initWithDelegate:self];
			
			[_backtraceView addSubview:_backtraceViewController.view];
			_backtraceViewController.view.frame = _backtraceView.bounds;
		}
		
		[_registersViewController updateRegistersFromBreakPoint:breakPoint];
		
		[self toggleBacktraceAndRegistersViews:NSOnState];
		
		[self jumpToMemoryAddress:_registersViewController.instructionPointer];
		
		[self updateBacktrace];
		
		BOOL shouldShowNotification = YES;
		
		if (currentBreakPoint.hidden)
		{
			if (breakPoint.basePointer == _registersViewController.basePointer)
			{
				[_breakPointController removeInstructionBreakPoint:breakPoint];
			}
			else
			{
				[self continueFromBreakPoint:currentBreakPoint];
				shouldShowNotification = NO;
			}
		}
		
		[self updateExecutionButtons];
		
		if (breakPoint.error == nil && shouldShowNotification)
		{
			ZGDeliverUserNotification(ZGLocalizedStringFromDebuggerTable(@"hitBreakpointNotificationTitle"), self.currentProcess.name, [NSString stringWithFormat:@"%@ %@", ZGLocalizedStringFromDebuggerTable(@"hitBreakpointNotificationMessage"), currentBreakPoint.variable.addressStringValue], nil);
		}
		else if (breakPoint.error != nil)
		{
			NSString *scriptContents = @"N/A";
			for (ZGBreakPointCondition *breakPointCondition in _breakPointConditions)
			{
				if ([breakPointCondition.internalProcessName isEqualToString:breakPoint.process.internalName] && breakPointCondition.address == breakPoint.variable.address)
				{
					scriptContents = breakPointCondition.condition;
					break;
				}
			}
			
			[_loggerWindowController writeLine:[breakPoint.error.userInfo objectForKey:SCRIPT_PYTHON_ERROR]];
			
			ZGRunAlertPanelWithOKButton(ZGLocalizedStringFromDebuggerTable(@"failedExecuteBreakpointConditionAlertTitle"), [NSString stringWithFormat:ZGLocalizedStringFromDebuggerTable(@"failedExecuteBreakpointConditionAlertMessage"), scriptContents, [breakPoint.error.userInfo objectForKey:SCRIPT_EVALUATION_ERROR_REASON]]);
			
			breakPoint.error = nil;
		}
	}
}

- (void)resumeBreakPoint:(ZGBreakPoint *)breakPoint
{
	[_breakPointController resumeFromBreakPoint:breakPoint];
	[self removeHaltedBreakPoint:breakPoint];
	
	[self updateExecutionButtons];
}

- (void)continueFromBreakPoint:(ZGBreakPoint *)breakPoint
{
	[_breakPointController removeSingleStepBreakPointsFromBreakPoint:breakPoint];
	[self resumeBreakPoint:breakPoint];
	[self toggleBacktraceAndRegistersViews:NSOffState];
}

- (IBAction)continueExecution:(id)__unused sender
{
	[self continueFromBreakPoint:[self currentBreakPoint]];
}

- (IBAction)stepInto:(id)__unused sender
{
	ZGBreakPoint *currentBreakPoint = [self currentBreakPoint];
	[_breakPointController addSingleStepBreakPointFromBreakPoint:currentBreakPoint];
	[self resumeBreakPoint:currentBreakPoint];
}

- (IBAction)stepOver:(id)__unused sender
{
	NSArray<ZGMachBinary *> *machBinaries = [ZGMachBinary machBinariesInProcess:self.currentProcess];
	
	ZGInstruction *currentInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:_registersViewController.instructionPointer + 1 inProcess:self.currentProcess withBreakPoints:_breakPointController.breakPoints machBinaries:machBinaries];
	
	if ([ZGDisassemblerObject isCallMnemonic:currentInstruction.mnemonic])
	{
		ZGInstruction *nextInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:currentInstruction.variable.address + currentInstruction.variable.size + 1 inProcess:self.currentProcess withBreakPoints:_breakPointController.breakPoints machBinaries:machBinaries];
		
		if ([_breakPointController addBreakPointOnInstruction:nextInstruction inProcess:self.currentProcess thread:[self currentBreakPoint].thread basePointer:_registersViewController.basePointer delegate:self])
		{
			[self continueExecution:nil];
		}
		else
		{
			ZGRunAlertPanelWithOKButton(ZGLocalizedStringFromDebuggerTable(@"failedStepOverAlertTitle"), ZGLocalizedStringFromDebuggerTable(@"failedStepOverAlertMessage"));
		}
	}
	else
	{
		[self stepInto:nil];
	}
}

- (IBAction)stepOut:(id)__unused sender
{
	ZGInstruction *outerInstruction = [_backtraceViewController.backtrace.instructions objectAtIndex:1];
	
	ZGInstruction *returnInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:outerInstruction.variable.address + outerInstruction.variable.size + 1 inProcess:self.currentProcess withBreakPoints:_breakPointController.breakPoints machBinaries:[ZGMachBinary machBinariesInProcess:self.currentProcess]];

	if ([_breakPointController addBreakPointOnInstruction:returnInstruction inProcess:self.currentProcess thread:[self currentBreakPoint].thread basePointer:[[_backtraceViewController.backtrace.basePointers objectAtIndex:1] unsignedLongLongValue] delegate:self])
	{
		[self continueExecution:nil];
	}
	else
	{
		ZGRunAlertPanelWithOKButton(ZGLocalizedStringFromDebuggerTable(@"failedStepOutAlertTitle"), ZGLocalizedStringFromDebuggerTable(@"failedStepOutAlertMessage"));
	}
}

- (IBAction)stepExecution:(id)sender
{
	switch ((enum ZGStepExecution)[(NSSegmentedControl *)sender selectedSegment])
	{
		case ZGStepIntoExecution:
			[self stepInto:nil];
			break;
		case ZGStepOverExecution:
			[self stepOver:nil];
			break;
		case ZGStepOutExecution:
			[self stepOut:nil];
			break;
	}
}

- (void)cleanup
{
	if (!_cleanedUp)
	{
		[_breakPointController removeObserver:self];
		
		for (ZGBreakPoint *breakPoint in _haltedBreakPoints)
		{
			[self continueFromBreakPoint:breakPoint];
		}
		
		_cleanedUp = YES;
	}
	
	[super cleanup];
}

- (BOOL)isProcessIdentifierHalted:(pid_t)processIdentifier
{
	return [super isProcessIdentifier:processIdentifier inHaltedBreakPoints:_haltedBreakPoints];
}

#pragma mark Breakpoint Conditions

- (IBAction)showBreakPointCondition:(id)__unused sender
{
	if (_breakPointConditionPopover == nil)
	{
		_breakPointConditionPopover = [[NSPopover alloc] init];
		_breakPointConditionPopover.contentViewController = [[ZGBreakPointConditionViewController alloc] initWithDelegate:self];
		_breakPointConditionPopover.behavior = NSPopoverBehaviorSemitransient;
	}
	
	ZGInstruction *selectedInstruction = [[self selectedInstructions] objectAtIndex:0];
	
	[(ZGBreakPointConditionViewController *)_breakPointConditionPopover.contentViewController setTargetAddress:selectedInstruction.variable.address];
	
	NSString *displayedCondition = @"";
	for (ZGBreakPointCondition *breakPointCondition in _breakPointConditions)
	{
		if ([breakPointCondition.internalProcessName isEqualToString:self.currentProcess.internalName] && breakPointCondition.address == selectedInstruction.variable.address)
		{
			displayedCondition = breakPointCondition.condition;
			break;
		}
	}
	
	[(ZGBreakPointConditionViewController *)_breakPointConditionPopover.contentViewController setCondition:displayedCondition];
	
	NSUInteger selectedRow = [[self selectedInstructionIndexes] firstIndex];
	
	NSRange visibleRowsRange = [_instructionsTableView rowsInRect:_instructionsTableView.visibleRect];
	if (visibleRowsRange.location > selectedRow || selectedRow >= visibleRowsRange.location + visibleRowsRange.length)
	{
		[self scrollAndSelectRow:selectedRow];
	}
	
	NSRect cellFrame = [_instructionsTableView frameOfCellAtColumn:0 row:(NSInteger)selectedRow];
	[_breakPointConditionPopover showRelativeToRect:cellFrame ofView:_instructionsTableView preferredEdge:NSMaxYEdge];
}

- (void)breakPointConditionDidCancel
{
	[_breakPointConditionPopover performClose:nil];
}

- (BOOL)changeBreakPointCondition:(NSString *)breakPointCondition atAddress:(ZGMemoryAddress)address error:(NSError * __autoreleasing *)error
{
	NSString *strippedCondition = [breakPointCondition stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	
	PyObject *newCompiledCondition = NULL;
	
	if (strippedCondition.length > 0)
	{
		newCompiledCondition = [_scriptingInterpreter compiledExpressionFromExpression:strippedCondition error:error];
		if (newCompiledCondition == NULL)
		{
			NSLog(@"Error: compiled expression %@ is NULL", strippedCondition);
			return NO;
		}
	}
	
	NSArray<ZGBreakPoint *> *breakPoints = _breakPointController.breakPoints;
	for (ZGBreakPoint *breakPoint in breakPoints)
	{
		if (breakPoint.type == ZGBreakPointInstruction && [breakPoint.process.internalName isEqualToString:self.currentProcess.internalName] && breakPoint.variable.address == address)
		{
			breakPoint.condition = newCompiledCondition;
			break;
		}
	}
	
	NSString *oldCondition = @"";
	
	BOOL foundExistingCondition = NO;
	for (ZGBreakPointCondition *breakCondition in _breakPointConditions)
	{
		if ([breakCondition.internalProcessName isEqualToString:self.currentProcess.internalName] && breakCondition.address == address)
		{
			oldCondition = breakCondition.condition;
			breakCondition.condition = strippedCondition;
			breakCondition.compiledCondition = newCompiledCondition;
			foundExistingCondition = YES;
			break;
		}
	}
	
	if (!foundExistingCondition && newCompiledCondition != NULL)
	{
		if (_breakPointConditions == nil)
		{
			_breakPointConditions = [NSMutableArray array];
		}
		
		[_breakPointConditions addObject:
		 [[ZGBreakPointCondition alloc]
		  initWithInternalProcessName:self.currentProcess.internalName
		  address:address
		  condition:strippedCondition
		  compiledCondition:newCompiledCondition]];
	}
	
	[(ZGDebuggerController *)[self.undoManager prepareWithInvocationTarget:self] changeBreakPointCondition:oldCondition atAddress:address error:error];
	
	return YES;
}

- (void)breakPointCondition:(NSString *)condition didChangeAtAddress:(ZGMemoryAddress)address
{
	NSError *error = nil;
	if (![self changeBreakPointCondition:condition atAddress:address error:&error])
	{
		[_loggerWindowController writeLine:[error.userInfo objectForKey:SCRIPT_PYTHON_ERROR]];
		
		ZGRunAlertPanelWithOKButton(ZGLocalizedStringFromDebuggerTable(@"failedChangeBreakpointConditionAlertTitle"), [NSString stringWithFormat:ZGLocalizedStringFromDebuggerTable(@"failedChangeBreakpointConditionAlertMessageFormat"), condition]);
	}
	else
	{
		[_breakPointConditionPopover performClose:nil];
	}
}

#pragma mark Memory Viewer

- (IBAction)showMemoryViewer:(id)__unused sender
{
	ZGInstruction *selectedInstruction = [[self selectedInstructions] objectAtIndex:0];
	id <ZGShowMemoryWindow> delegate = self.delegate;
	[delegate showMemoryViewerWindowWithProcess:self.currentProcess address:selectedInstruction.variable.address selectionLength:selectedInstruction.variable.size];
}

@end
