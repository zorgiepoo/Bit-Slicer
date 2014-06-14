/*
 * Created by Mayur Pawashe on 12/27/12.
 *
 * Copyright (c) 2012 zgcoder
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
#import "ZGProcess.h"
#import "ZGRegion.h"
#import "ZGCalculator.h"
#import "ZGRunningProcess.h"
#import "ZGInstruction.h"
#import "ZGLoggerWindowController.h"
#import "ZGBreakPoint.h"
#import "ZGBreakPointController.h"
#import "ZGBreakPointCondition.h"
#import "ZGScriptManager.h"
#import "ZGDisassemblerObject.h"
#import "ZGUtilities.h"
#import "ZGRegistersViewController.h"
#import "ZGPreferencesController.h"
#import "NSArrayAdditions.h"
#import "ZGVirtualMemory.h"
#import "ZGVirtualMemoryHelpers.h"
#import "ZGMachBinary.h"
#import "ZGMachBinaryInfo.h"
#import "ZGTableView.h"
#import "ZGVariableController.h"
#import "ZGBacktrace.h"
#import "ZGNavigationPost.h"
#import "ZGHotKeyCenter.h"
#import "ZGHotKey.h"

#define ZGDebuggerSplitViewAutosaveName @"ZGDisassemblerHorizontalSplitter"
#define ZGRegistersAndBacktraceSplitViewAutosaveName @"ZGDisassemblerVerticalSplitter"

@interface ZGDebuggerController ()

@property (nonatomic) ZGBreakPointController *breakPointController;
@property (nonatomic) ZGLoggerWindowController *loggerWindowController;

@property (nonatomic, assign) IBOutlet ZGTableView *instructionsTableView;
@property (nonatomic, assign) IBOutlet NSSplitView *splitView;
@property (nonatomic, assign) IBOutlet NSSplitView *registersAndBacktraceSplitView;

@property (nonatomic, assign) IBOutlet NSView *registersView;
@property (nonatomic) ZGRegistersViewController *registersViewController;

@property (nonatomic, assign) IBOutlet NSView *backtraceView;
@property (nonatomic) ZGBacktraceViewController *backtraceViewController;

@property (nonatomic, assign) IBOutlet NSButton *continueButton;
@property (nonatomic, assign) IBOutlet NSSegmentedControl *stepExecutionSegmentedControl;

@property (nonatomic, assign) IBOutlet NSTextField *statusTextField;
@property (nonatomic) NSString *mappedFilePath;
@property (nonatomic) ZGMemoryAddress baseAddress;
@property (nonatomic) ZGMemoryAddress offsetFromBase;

@property (nonatomic) NSArray *instructions;

@property (nonatomic) NSRange instructionBoundary;

@property (nonatomic) ZGCodeInjectionWindowController *codeInjectionController;

@property (nonatomic) NSArray *haltedBreakPoints;
@property (nonatomic, readonly) ZGBreakPoint *currentBreakPoint;

@property (nonatomic) NSPopover *breakPointConditionPopover;
@property (nonatomic) NSMutableArray *breakPointConditions;

@property (nonatomic) id breakPointActivity;

@end

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

enum ZGStepExecution
{
	ZGStepIntoExecution,
	ZGStepOverExecution,
	ZGStepOutExecution
};

@implementation ZGDebuggerController

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

- (id)initWithProcessTaskManager:(ZGProcessTaskManager *)processTaskManager breakPointController:(ZGBreakPointController *)breakPointController hotKeyCenter:(ZGHotKeyCenter *)hotKeyCenter loggerWindowController:(ZGLoggerWindowController *)loggerWindowController
{
	self = [super initWithProcessTaskManager:processTaskManager];
	
	if (self != nil)
	{
		self.debuggerController = self;
		self.breakPointController = breakPointController;
		self.loggerWindowController = loggerWindowController;
		
		self.haltedBreakPoints = [[NSArray alloc] init];
		
		_pauseAndUnpauseHotKey = [NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:ZGPauseAndUnpauseHotKey]];
		_stepInHotKey = [NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:ZGStepInHotKey]];
		_stepOverHotKey = [NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:ZGStepOverHotKey]];
		_stepOutHotKey = [NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:ZGStepOutHotKey]];

		[hotKeyCenter registerHotKey:_pauseAndUnpauseHotKey delegate:self];
		[hotKeyCenter registerHotKey:_stepInHotKey delegate:self];
		[hotKeyCenter registerHotKey:_stepOverHotKey delegate:self];
		[hotKeyCenter registerHotKey:_stepOutHotKey delegate:self];

		[[NSNotificationCenter defaultCenter]
		 addObserver:self
		 selector:@selector(applicationWillTerminate:)
		 name:NSApplicationWillTerminateNotification
		 object:nil];
	}

	return self;
}

- (void)encodeRestorableStateWithCoder:(NSCoder *)coder
{
    [super encodeRestorableStateWithCoder:coder];
	
	[coder encodeObject:self.addressTextField.stringValue forKey:ZGDebuggerAddressField];
	[coder encodeObject:[self.runningApplicationsPopUpButton.selectedItem.representedObject internalName] forKey:ZGDebuggerProcessInternalName];
	[coder encodeObject:@(self.offsetFromBase) forKey:ZGDebuggerOffsetFromBase];
	[coder encodeObject:self.mappedFilePath == nil ? [NSNull null] : self.mappedFilePath forKey:ZGDebuggerMappedFilePath];
}

- (void)restoreStateWithCoder:(NSCoder *)coder
{
	[super restoreStateWithCoder:coder];
	
	NSString *addressField = [coder decodeObjectForKey:ZGDebuggerAddressField];
	if (addressField)
	{
		self.addressTextField.stringValue = addressField;
	}
	
	self.offsetFromBase = [[coder decodeObjectForKey:ZGDebuggerOffsetFromBase] unsignedLongLongValue];
	self.mappedFilePath = [coder decodeObjectForKey:ZGDebuggerMappedFilePath];
	if ((id)self.mappedFilePath == [NSNull null])
	{
		self.mappedFilePath = nil;
	}
	
	self.desiredProcessInternalName = [coder decodeObjectForKey:ZGDebuggerProcessInternalName];
	[self updateRunningProcesses];
	[self setAndPostLastChosenInternalProcessName];
	[self readMemory:nil];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
	
	[self setupProcessListNotifications];

	self.desiredProcessInternalName = self.lastChosenInternalProcessName;
	[self updateRunningProcesses];
	
	[self.instructionsTableView registerForDraggedTypes:@[ZGVariablePboardType]];
	
	[self.statusTextField.cell setBackgroundStyle:NSBackgroundStyleRaised];
	
	[self.continueButton.image setTemplate:YES];
	[[self.stepExecutionSegmentedControl imageForSegment:ZGStepIntoExecution] setTemplate:YES];
	[[self.stepExecutionSegmentedControl imageForSegment:ZGStepOverExecution] setTemplate:YES];
	[[self.stepExecutionSegmentedControl imageForSegment:ZGStepOutExecution] setTemplate:YES];
	
	[self updateExecutionButtons];
	
	[self toggleBacktraceAndRegistersViews:NSOffState];
	
	// Don't set these in IB; can't trust setting these at the right time and not screwing up the saved positions
	self.splitView.autosaveName = ZGDebuggerSplitViewAutosaveName;
	self.registersAndBacktraceSplitView.autosaveName = ZGRegistersAndBacktraceSplitViewAutosaveName;
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
							[ZGProcess pauseOrUnpauseProcessTask:processTask];
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
	
	if (self.currentBreakPoint != nil)
	{
		[self toggleBacktraceAndRegistersViews:NSOnState];
		[self updateRegisters];
		[self updateBacktrace];
		
		[self jumpToMemoryAddress:self.registersViewController.instructionPointer];
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
	return (self.currentBreakPoint == nil);
}

// For collapsing and uncollapsing, useful info: http://manicwave.com/blog/2009/12/31/unraveling-the-mysteries-of-nssplitview-part-2/
- (void)uncollapseBottomSubview
{
	NSView *topSubview = [self.splitView.subviews objectAtIndex:0];
	NSView *bottomSubview = [self.splitView.subviews objectAtIndex:1];
	
	[bottomSubview setHidden:NO];
	
	NSRect topFrame = topSubview.frame;
	NSRect bottomFrame = bottomSubview.frame;
	
	topFrame.size.height = topFrame.size.height - bottomFrame.size.height - self.splitView.dividerThickness;
	bottomFrame.origin.y = topFrame.size.height + self.splitView.dividerThickness;
	
	topSubview.frameSize = topFrame.size;
	bottomSubview.frame = bottomFrame;
	[self.splitView display];
}

- (void)collapseBottomSubview
{
	NSView *topSubview = [self.splitView.subviews objectAtIndex:0];
	NSView *bottomSubview = [self.splitView.subviews objectAtIndex:1];
	
	[bottomSubview setHidden:YES];
	[topSubview setFrameSize:NSMakeSize(topSubview.frame.size.width, self.splitView.frame.size.height)];
	[self.splitView display];
}

- (void)toggleBacktraceAndRegistersViews:(NSCellStateValue)state
{	
	switch (state)
	{
		case NSOnState:
			if ([self.splitView isSubviewCollapsed:[self.splitView.subviews objectAtIndex:1]])
			{
				[self uncollapseBottomSubview];
			}
			break;
		case NSOffState:
			if (![self.splitView isSubviewCollapsed:[self.splitView.subviews objectAtIndex:1]])
			{
				[self.undoManager removeAllActionsWithTarget:self.registersViewController];
				[self collapseBottomSubview];
			}
			break;
		default:
			break;
	}
}

#pragma mark Symbols

// prerequisite: should call shouldUpdateSymbolsForInstructions: beforehand
- (void)updateSymbolsForInstructions:(NSArray *)instructions
{
	for (ZGInstruction *instruction in instructions)
	{
		ZGMemoryAddress relativeProcedureOffset = 0x0;
		NSString *symbolName = [self.currentProcess symbolAtAddress:instruction.variable.address relativeOffset:&relativeProcedureOffset];

		instruction.symbols = (symbolName != nil) ? [NSString stringWithFormat:@"%@ + %llu", symbolName, relativeProcedureOffset] : @"";
	}
}

- (BOOL)shouldUpdateSymbolsForInstructions:(NSArray *)instructions
{
	return self.currentProcess.valid && [instructions zgHasObjectMatchingCondition:^(ZGInstruction *instruction){ return (BOOL)(instruction.symbols == nil); }];
}

#pragma mark Disassembling

- (void)updateInstructionValues
{
	// Check to see if anything in the window needs to be updated
	NSRange visibleRowsRange = [self.instructionsTableView rowsInRect:self.instructionsTableView.visibleRect];
	if (visibleRowsRange.location + visibleRowsRange.length <= self.instructions.count)
	{	
		BOOL needsToUpdateWindow = NO;
		
		for (ZGInstruction *instruction in [self.instructions subarrayWithRange:visibleRowsRange])
		{
			void *bytes = NULL;
			ZGMemorySize size = instruction.variable.size;
			if (ZGReadBytes(self.currentProcess.processTask, instruction.variable.address, &bytes, &size))
			{
				if (memcmp(bytes, instruction.variable.rawValue, size) != 0)
				{
					// Ignore trivial breakpoint changes
					BOOL foundBreakPoint = NO;
					if (*(uint8_t *)bytes == INSTRUCTION_BREAKPOINT_OPCODE && (size == sizeof(uint8_t) || memcmp(bytes+sizeof(uint8_t), instruction.variable.rawValue+sizeof(uint8_t), size-sizeof(uint8_t)) == 0))
					{
						foundBreakPoint = [self.breakPointController.breakPoints zgHasObjectMatchingCondition:^(ZGBreakPoint *breakPoint) {
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
			NSArray *machBinaries = nil;
			
			// Find a [start, end) range that we are allowed to remove from the table and insert in again with new instructions
			// Pick start and end such that they are aligned with the assembly instructions
			
			NSUInteger startRow = visibleRowsRange.location;
			
			do
			{
				if (startRow == 0) break;
				
				ZGInstruction *instruction = [self.instructions objectAtIndex:startRow];
				
				if (machBinaries == nil)
				{
					machBinaries = [ZGMachBinary machBinariesInProcess:self.currentProcess];
				}
				
				ZGInstruction *searchedInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:instruction.variable.address inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints machBinaries:machBinaries];
				
				startRow--;
				
				if (searchedInstruction.variable.address + searchedInstruction.variable.size == instruction.variable.address)
				{
					break;
				}
			}
			while (YES);
			
			ZGInstruction *startInstruction = [self.instructions objectAtIndex:startRow];
			ZGMemoryAddress startAddress = startInstruction.variable.address;
			
			// Extend past first row if necessary
			if (startRow == 0)
			{
				if (machBinaries == nil)
				{
					machBinaries = [ZGMachBinary machBinariesInProcess:self.currentProcess];
				}
				
				ZGInstruction *searchedInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:startInstruction.variable.address inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints machBinaries:machBinaries];
				
				if (searchedInstruction.variable.address + searchedInstruction.variable.size != startAddress)
				{
					startAddress = searchedInstruction.variable.address;
				}
			}
			
			NSUInteger endRow = visibleRowsRange.location + visibleRowsRange.length - 1;
			
			do
			{
				if (endRow >= self.instructions.count) break;
				
				ZGInstruction *instruction = [self.instructions objectAtIndex:endRow];
				
				if (machBinaries == nil)
				{
					machBinaries = [ZGMachBinary machBinariesInProcess:self.currentProcess];
				}
				
				ZGInstruction *searchedInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:instruction.variable.address + instruction.variable.size inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints machBinaries:machBinaries];
				
				endRow++;
				
				if (searchedInstruction.variable.address == instruction.variable.address)
				{
					break;
				}
			}
			while (YES);
			
			ZGInstruction *endInstruction = [self.instructions objectAtIndex:endRow-1];
			ZGMemoryAddress endAddress = endInstruction.variable.address + endInstruction.variable.size;
			
			// Extend past last row if necessary
			if (endRow >= self.instructions.count)
			{
				if (machBinaries == nil)
				{
					machBinaries = [ZGMachBinary machBinariesInProcess:self.currentProcess];
				}
				
				ZGInstruction *searchedInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:endInstruction.variable.address + endInstruction.variable.size inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints machBinaries:machBinaries];
				
				if (endInstruction.variable.address != searchedInstruction.variable.address)
				{
					endAddress = searchedInstruction.variable.address + searchedInstruction.variable.size;
				}
			}
			
			ZGMemorySize size = endAddress - startAddress;
			
			ZGDisassemblerObject *disassemblerObject = [ZGDebuggerUtilities disassemblerObjectWithProcessTask:self.currentProcess.processTask pointerSize:self.currentProcess.pointerSize address:startAddress size:size breakPoints:self.breakPointController.breakPoints];
			if (disassemblerObject != nil)
			{
				NSArray *instructionsToReplace = [disassemblerObject readInstructions];
				
				// Replace the visible instructions
				NSMutableArray *newInstructions = [[NSMutableArray alloc] initWithArray:self.instructions];
				[newInstructions replaceObjectsInRange:NSMakeRange(startRow, endRow - startRow) withObjectsFromArray:instructionsToReplace];
				self.instructions = [NSArray arrayWithArray:newInstructions];
				
				[self.instructionsTableView reloadData];
			}
		}
	}
}

- (void)updateVisibleInstructionSymbols
{
	NSRange visibleRowsRange = [self.instructionsTableView rowsInRect:self.instructionsTableView.visibleRect];
	if (visibleRowsRange.location + visibleRowsRange.length <= self.instructions.count)
	{
		NSArray *instructions = [self.instructions subarrayWithRange:visibleRowsRange];
		if ([self shouldUpdateSymbolsForInstructions:instructions])
		{
			[self updateSymbolsForInstructions:instructions];
			[self.instructionsTableView reloadData];
		}
	}
}

#define DESIRED_BYTES_TO_ADD_OFFSET 10000

- (void)addMoreInstructionsBeforeFirstRow
{
	ZGInstruction *endInstruction = [self.instructions objectAtIndex:0];
	ZGInstruction *startInstruction = nil;
	NSUInteger bytesBehind = DESIRED_BYTES_TO_ADD_OFFSET;
	
	if (endInstruction.variable.address <= self.instructionBoundary.location)
	{
		return;
	}
	
	NSArray *machBinaries = nil;
	
	while (startInstruction == nil && bytesBehind > 0)
	{
		if (machBinaries == nil)
		{
			machBinaries = [ZGMachBinary machBinariesInProcess:self.currentProcess];
		}
		
		startInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:endInstruction.variable.address - bytesBehind inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints machBinaries:machBinaries];
		
		if (startInstruction.variable.address < self.instructionBoundary.location)
		{
			// Try again
			startInstruction = nil;
		}
		
		bytesBehind /= 2;
	}
	
	if (startInstruction != nil)
	{
		ZGMemorySize size = endInstruction.variable.address - startInstruction.variable.address;
		
		ZGDisassemblerObject *disassemblerObject = [ZGDebuggerUtilities disassemblerObjectWithProcessTask:self.currentProcess.processTask pointerSize:self.currentProcess.pointerSize address:startInstruction.variable.address size:size breakPoints:self.breakPointController.breakPoints];
		
		if (disassemblerObject != nil)
		{
			NSMutableArray *instructionsToAdd = [NSMutableArray arrayWithArray:[disassemblerObject readInstructions]];
			
			NSUInteger numberOfInstructionsAdded = instructionsToAdd.count;
			NSRange visibleRowsRange = [self.instructionsTableView rowsInRect:self.instructionsTableView.visibleRect];
			
			[instructionsToAdd addObjectsFromArray:self.instructions];
			self.instructions = [NSArray arrayWithArray:instructionsToAdd];
			
			NSInteger previousSelectedRow = [self.instructionsTableView selectedRow];
			[self.instructionsTableView noteNumberOfRowsChanged];
			
			[self.instructionsTableView scrollRowToVisible:(NSInteger)MIN(numberOfInstructionsAdded + visibleRowsRange.length - 1, self.instructions.count)];
			
			if (previousSelectedRow >= 0)
			{
				[self.instructionsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)previousSelectedRow + numberOfInstructionsAdded] byExtendingSelection:NO];
			}
		}
	}
}

- (void)addMoreInstructionsAfterLastRow
{
	ZGInstruction *lastInstruction = self.instructions.lastObject;
	
	NSArray *machBinaries = [ZGMachBinary machBinariesInProcess:self.currentProcess];
	
	ZGInstruction *startInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:(lastInstruction.variable.address + lastInstruction.variable.size + 1) inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints machBinaries:machBinaries];
	
	if (startInstruction.variable.address + startInstruction.variable.size >= self.instructionBoundary.location +  self.instructionBoundary.length)
	{
		return;
	}
	
	if (startInstruction != nil)
	{
		ZGInstruction *endInstruction = nil;
		NSUInteger bytesAhead = DESIRED_BYTES_TO_ADD_OFFSET;
		while (endInstruction == nil && bytesAhead > 0)
		{
			endInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:(startInstruction.variable.address + startInstruction.variable.size + bytesAhead) inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints machBinaries:machBinaries];
			
			if (endInstruction.variable.address + endInstruction.variable.size > self.instructionBoundary.location +  self.instructionBoundary.length)
			{
				// Try again
				endInstruction = nil;
			}
			
			bytesAhead /= 2;
		}
		
		if (endInstruction != nil)
		{
			ZGMemorySize size = endInstruction.variable.address - startInstruction.variable.address;
			
			ZGDisassemblerObject *disassemblerObject = [ZGDebuggerUtilities disassemblerObjectWithProcessTask:self.currentProcess.processTask pointerSize:self.currentProcess.pointerSize address:startInstruction.variable.address size:size breakPoints:self.breakPointController.breakPoints];
			
			if (disassemblerObject != nil)
			{
				NSArray *instructionsToAdd = [disassemblerObject readInstructions];
				NSMutableArray *appendedInstructions = [NSMutableArray arrayWithArray:self.instructions];
				[appendedInstructions addObjectsFromArray:instructionsToAdd];
				
				self.instructions = [NSArray arrayWithArray:appendedInstructions];
				
				[self.instructionsTableView noteNumberOfRowsChanged];
			}
		}
	}
}

- (void)updateInstructionsBeyondTableView
{
	NSRange visibleRowsRange = [self.instructionsTableView rowsInRect:self.instructionsTableView.visibleRect];
	if (visibleRowsRange.location == 0)
	{
		[self addMoreInstructionsBeforeFirstRow];
	}
	else if (visibleRowsRange.location + visibleRowsRange.length >= self.instructions.count)
	{
		[self addMoreInstructionsAfterLastRow];
	}
}

- (void)updateDisplayTimer:(NSTimer *)__unused timer
{
	if (self.currentProcess.valid && self.instructionsTableView.editedRow == -1 && self.instructions.count > 0)
	{
		[self updateInstructionValues];
		[self updateVisibleInstructionSymbols];
		[self updateInstructionsBeyondTableView];
	}
}

- (void)updateDisassemblerWithAddress:(ZGMemoryAddress)address size:(ZGMemorySize)size selectionAddress:(ZGMemoryAddress)selectionAddress
{
	[self.addressTextField setEnabled:NO];
	[self.runningApplicationsPopUpButton setEnabled:NO];
	
	[self prepareNavigation];
	
	self.instructions = @[];
	[self.instructionsTableView reloadData];

	ZGDisassemblerObject *disassemblerObject = [ZGDebuggerUtilities disassemblerObjectWithProcessTask:self.currentProcess.processTask pointerSize:self.currentProcess.pointerSize address:address size:size breakPoints:self.breakPointController.breakPoints];
	NSArray *newInstructions = @[];

	if (disassemblerObject != nil)
	{
		newInstructions = [disassemblerObject readInstructions];
	}

	self.instructions = newInstructions;

	[self.instructionsTableView noteNumberOfRowsChanged];

	ZGInstruction *selectionInstruction = [self findInstructionInTableAtAddress:selectionAddress];
	if (selectionInstruction != nil)
	{
		[self scrollAndSelectRow:[self.instructions indexOfObject:selectionInstruction]];
	}

	[self.addressTextField setEnabled:YES];
	[self.runningApplicationsPopUpButton setEnabled:YES];

	if (self.window.firstResponder != self.backtraceViewController.tableView)
	{
		[self.window makeFirstResponder:self.instructionsTableView];
	}

	[self updateNavigationButtons];
	[self updateExecutionButtons];
	[self updateStatusBar];
}

#pragma mark Handling Processes

- (void)processListChanged:(NSDictionary *)change
{
	NSArray *oldRunningProcesses = [change objectForKey:NSKeyValueChangeOldKey];
	if (oldRunningProcesses)
	{
		for (ZGRunningProcess *runningProcess in oldRunningProcesses)
		{
			[self.breakPointController removeObserver:self runningProcess:runningProcess];
			for (ZGBreakPoint *haltedBreakPoint in self.haltedBreakPoints)
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
	if (![self.runningApplicationsPopUpButton.selectedItem.representedObject isEqual:self.currentProcess])
	{
		self.addressTextField.stringValue = addressStringValue;
		self.mappedFilePath = nil;
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
	
	ZGDisassemblerObject *disassemblerObject = [ZGDebuggerUtilities disassemblerObjectWithProcessTask:self.currentProcess.processTask pointerSize:self.currentProcess.pointerSize address:selectedInstruction.variable.address size:selectedInstruction.variable.size breakPoints:self.breakPointController.breakPoints];
	
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
	if (self.instructions.count > 0)
	{
		NSRange visibleRowsRange = [self.instructionsTableView rowsInRect:self.instructionsTableView.visibleRect];
		
		if (self.instructionsTableView.selectedRowIndexes.count > 0 && self.instructionsTableView.selectedRowIndexes.firstIndex >= visibleRowsRange.location && self.instructionsTableView.selectedRowIndexes.firstIndex < visibleRowsRange.location + visibleRowsRange.length && self.instructionsTableView.selectedRowIndexes.firstIndex < self.instructions.count)
		{
			ZGInstruction *selectedInstruction = [self.instructions objectAtIndex:self.instructionsTableView.selectedRowIndexes.firstIndex];
			[[self.navigationManager prepareWithInvocationTarget:self] jumpToMemoryAddress:selectedInstruction.variable.address];
		}
		else
		{
			NSUInteger centeredInstructionIndex = visibleRowsRange.location + visibleRowsRange.length / 2;
			if (centeredInstructionIndex < self.instructions.count)
			{
				ZGInstruction *centeredInstruction = [self.instructions objectAtIndex:centeredInstructionIndex];
				[[self.navigationManager prepareWithInvocationTarget:self] jumpToMemoryAddress:centeredInstruction.variable.address];
			}
		}
	}
}

- (void)updateStatusBar
{
	if (self.instructions.count == 0 || self.mappedFilePath.length == 0)
	{
		[self.statusTextField setStringValue:@""];
	}
	else if (self.selectedInstructions.count > 0)
	{
		ZGInstruction *firstSelectedInstruction = [self.selectedInstructions objectAtIndex:0];
		[self.statusTextField setStringValue:[NSString stringWithFormat:@"%@ + 0x%llX", self.mappedFilePath, firstSelectedInstruction.variable.address - self.baseAddress]];
	}
}

- (IBAction)readMemory:(id)sender
{
	void (^cleanupOnFailure)(void) = ^{
		self.instructions = [NSArray array];
		[self.instructionsTableView reloadData];
		[self updateStatusBar];
	};
	
	if (!self.currentProcess.valid || ![self.currentProcess hasGrantedAccess])
	{
		cleanupOnFailure();
		return;
	}
	
	NSArray *machBinaries = [ZGMachBinary machBinariesInProcess:self.currentProcess];
	ZGMachBinary *mainMachBinary = [ZGMachBinary mainMachBinaryFromMachBinaries:machBinaries];
	
	ZGMemoryAddress calculatedMemoryAddress = 0;

	if (self.mappedFilePath != nil && sender == nil)
	{
		NSError *error = nil;
		ZGMemoryAddress guessAddress = [[ZGMachBinary machBinaryWithPartialImageName:self.mappedFilePath inProcess:self.currentProcess fromCachedMachBinaries:machBinaries error:&error] headerAddress] + self.offsetFromBase;
		
		if (error == nil)
		{
			calculatedMemoryAddress = guessAddress;
			[self.addressTextField setStringValue:[NSString stringWithFormat:@"0x%llX", calculatedMemoryAddress]];
		}
	}
	else
	{
		NSString *userInput = self.addressTextField.stringValue;
		ZGMemoryAddress selectedAddress = ((ZGInstruction *)[self.selectedInstructions lastObject]).variable.address;
		NSError *error = nil;
		NSString *calculatedMemoryAddressExpression = [ZGCalculator evaluateAndSymbolicateExpression:userInput process:self.currentProcess currentAddress:selectedAddress error:&error];
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
		self.offsetFromBase = calculatedMemoryAddress - self.baseAddress;
		[self prepareNavigation];
		[self scrollAndSelectRow:[self.instructions indexOfObject:foundInstructionInTable]];
		if (self.window.firstResponder != self.backtraceViewController.tableView)
		{
			[self.window makeFirstResponder:self.instructionsTableView];
		}
		
		[self updateNavigationButtons];
		[self invalidateRestorableState];
		
		return;
	}
	
	NSArray *memoryRegions = [ZGRegion regionsFromProcessTask:self.currentProcess.processTask];
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
		NSArray *submapRegions =  [ZGRegion submapRegionsFromProcessTask:self.currentProcess.processTask region:chosenRegion];
		
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
	
	self.mappedFilePath = mappedFilePath;
	self.baseAddress = baseAddress;
	self.offsetFromBase = calculatedMemoryAddress - baseAddress;
	
	// Make sure disassembler won't show anything before this address
	self.instructionBoundary = NSMakeRange(firstInstructionAddress, maxInstructionsSize);
	
	// Disassemble within a range from +- WINDOW_SIZE from selection address
	const NSUInteger WINDOW_SIZE = 2048;
	
	ZGMemoryAddress lowBoundAddress = calculatedMemoryAddress - WINDOW_SIZE;
	if (lowBoundAddress <= firstInstructionAddress)
	{
		lowBoundAddress = firstInstructionAddress;
	}
	else
	{
		lowBoundAddress = [ZGDebuggerUtilities findInstructionBeforeAddress:lowBoundAddress inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints machBinaries:machBinaries].variable.address;
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
		highBoundAddress = [ZGDebuggerUtilities findInstructionBeforeAddress:highBoundAddress inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints machBinaries:machBinaries].variable.address;
		if (highBoundAddress <= chosenRegion.address || highBoundAddress > chosenRegion.address + chosenRegion.size)
		{
			highBoundAddress = chosenRegion.address + chosenRegion.size;
		}
	}
	
	[self.undoManager removeAllActions];
	[self updateDisassemblerWithAddress:lowBoundAddress size:highBoundAddress - lowBoundAddress selectionAddress:calculatedMemoryAddress];
	
	[self invalidateRestorableState];
}

#pragma mark Useful methods for the world

- (NSIndexSet *)selectedInstructionIndexes
{
	NSIndexSet *tableIndexSet = self.instructionsTableView.selectedRowIndexes;
	NSInteger clickedRow = self.instructionsTableView.clickedRow;
	
	return (clickedRow >= 0 && ![tableIndexSet containsIndex:(NSUInteger)clickedRow]) ? [NSIndexSet indexSetWithIndex:(NSUInteger)clickedRow] : tableIndexSet;
}

- (NSArray *)selectedInstructions
{
	return [self.instructions objectsAtIndexes:[self selectedInstructionIndexes]];
}

- (HFRange)preferredMemoryRequestRange
{
	NSArray *selectedInstructions = [self selectedInstructions];
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
		
		if (![targetMenuItem.representedObject isEqual:self.currentProcess])
		{
			[self.runningApplicationsPopUpButton selectItem:targetMenuItem];
			
			self.instructions = @[];
			[self.instructionsTableView reloadData];
			
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
	return self.currentBreakPoint != nil;
}

- (BOOL)canStepOverExecution
{
	if (self.currentBreakPoint == nil)
	{
		return NO;
	}
	
	NSArray *machBinaries = [ZGMachBinary machBinariesInProcess:self.currentProcess];
	
	ZGInstruction *currentInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:self.registersViewController.instructionPointer + 1 inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints machBinaries:machBinaries];
	if (!currentInstruction)
	{
		return NO;
	}
	
	if ([ZGDisassemblerObject isCallMnemonic:currentInstruction.mnemonic])
	{
		ZGInstruction *nextInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:currentInstruction.variable.address + currentInstruction.variable.size + 1 inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints machBinaries:machBinaries];
		if (!nextInstruction)
		{
			return NO;
		}
	}
	
	return YES;
}

- (BOOL)canStepOutOfExecution
{
	if (self.currentBreakPoint == nil)
	{
		return NO;
	}
	
	if (self.backtraceViewController.backtrace.instructions.count <= 1 || self.backtraceViewController.backtrace.basePointers.count <= 1)
	{
		return NO;
	}
	
	ZGInstruction *outterInstruction = [self.backtraceViewController.backtrace.instructions objectAtIndex:1];
	ZGInstruction *returnInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:outterInstruction.variable.address + outterInstruction.variable.size + 1 inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints machBinaries:[ZGMachBinary machBinariesInProcess:self.currentProcess]];
	
	if (!returnInstruction)
	{
		return NO;
	}
	
	return YES;
}

- (void)updateExecutionButtons
{
	[self.continueButton setEnabled:[self canContinueOrStepIntoExecution]];
	
	[self.stepExecutionSegmentedControl setEnabled:[self canContinueOrStepIntoExecution] forSegment:ZGStepIntoExecution];
	[self.stepExecutionSegmentedControl setEnabled:[self canStepOverExecution] forSegment:ZGStepOverExecution];
	[self.stepExecutionSegmentedControl setEnabled:[self canStepOutOfExecution] forSegment:ZGStepOutExecution];
}

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)userInterfaceItem
{
	NSMenuItem *menuItem = [(NSObject *)userInterfaceItem isKindOfClass:[NSMenuItem class]] ? (NSMenuItem *)userInterfaceItem : nil;
	
	if (userInterfaceItem.action == @selector(nopVariables:))
	{
		[menuItem setTitle:[NSString stringWithFormat:@"NOP Instruction%@", self.selectedInstructions.count == 1 ? @"" : @"s"]];
		
		if (self.selectedInstructions.count == 0 || !self.currentProcess.valid || self.instructionsTableView.editedRow != -1)
		{
			return NO;
		}
	}
	else if (userInterfaceItem.action == @selector(copy:))
	{
		if (self.selectedInstructions.count == 0)
		{
			return NO;
		}
	}
	else if (userInterfaceItem.action == @selector(copyAddress:))
	{
		if (self.selectedInstructions.count != 1)
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
		if (self.selectedInstructions.count == 0)
		{
			return NO;
		}
		
		BOOL shouldValidate = YES;
		BOOL isBreakPoint = [self isBreakPointAtInstruction:[self.selectedInstructions objectAtIndex:0]];
		BOOL didSkipFirstInstruction = NO;
		for (ZGInstruction *instruction in self.selectedInstructions)
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
		
		[menuItem setTitle:[NSString stringWithFormat:@"%@ Breakpoint%@", isBreakPoint ? @"Remove" : @"Add", self.selectedInstructions.count != 1 ? @"s" : @""]];
		
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
		if (self.currentBreakPoint == nil || self.selectedInstructions.count != 1)
		{
			return NO;
		}
	}
	else if (userInterfaceItem.action == @selector(jumpToOperandOffset:))
	{
		if (!self.currentProcess.valid)
		{
			return NO;
		}
		
		if (self.selectedInstructions.count != 1)
		{
			return NO;
		}
		
		ZGInstruction *selectedInstruction = [self.selectedInstructions objectAtIndex:0];
		if ([ZGDisassemblerObject isCallMnemonic:selectedInstruction.mnemonic])
		{
			[menuItem setTitle:@"Go to Call Address"];
		}
		else if ([ZGDisassemblerObject isJumpMnemonic:selectedInstruction.mnemonic])
		{
			[menuItem setTitle:@"Go to Branch Address"];
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

- (void)annotateInstructions:(NSArray *)instructions
{
	NSArray *variablesToAnnotate = [[instructions zgMapUsingBlock:^(ZGInstruction *instruction) { return instruction.variable; }]
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
	NSArray *selectedInstructions = self.selectedInstructions;
	
	[self annotateInstructions:selectedInstructions];
	
	NSMutableArray *descriptionComponents = [[NSMutableArray alloc] init];
	NSMutableArray *variablesArray = [[NSMutableArray alloc] init];
	
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
	ZGInstruction *selectedInstruction = [self.selectedInstructions objectAtIndex:0];
	[self annotateInstructions:@[selectedInstruction]];

	[[NSPasteboard generalPasteboard] declareTypes:@[NSStringPboardType] owner:self];
	[[NSPasteboard generalPasteboard] setString:selectedInstruction.variable.addressFormula forType:NSStringPboardType];
}

- (void)scrollAndSelectRow:(NSUInteger)selectionRow
{
	// Scroll such that the selected row is centered
	[self.instructionsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:selectionRow] byExtendingSelection:NO];
	NSRange visibleRowsRange = [self.instructionsTableView rowsInRect:self.instructionsTableView.visibleRect];
	if (visibleRowsRange.location + visibleRowsRange.length / 2 < selectionRow)
	{
		[self.instructionsTableView scrollRowToVisible:(NSInteger)MIN(selectionRow + visibleRowsRange.length / 2, self.instructions.count-1)];
	}
	else if (visibleRowsRange.location + visibleRowsRange.length / 2 > selectionRow)
	{
		// Make sure we don't go below 0 in unsigned arithmetic
		if (visibleRowsRange.length / 2 > selectionRow)
		{
			[self.instructionsTableView scrollRowToVisible:0];
		}
		else
		{
			[self.instructionsTableView scrollRowToVisible:(NSInteger)(selectionRow - visibleRowsRange.length / 2)];
		}
	}
}

#pragma mark TableView Methods

- (BOOL)tableView:(NSTableView *)__unused tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard
{
	NSArray *instructions = [self.instructions objectsAtIndexes:rowIndexes];
	[self annotateInstructions:instructions];
	
	return [pboard setData:[NSKeyedArchiver archivedDataWithRootObject:[instructions valueForKey:@"variable"]] forType:ZGVariablePboardType];
}

- (void)tableViewSelectionDidChange:(NSNotification *)__unused aNotification
{
	if (self.instructions.count > 0 && self.selectedInstructions.count > 0)
	{
		ZGInstruction *firstInstruction = [self.selectedInstructions objectAtIndex:0];
		[ZGNavigationPost postMemorySelectionChangeWithProcess:self.currentProcess selectionRange:NSMakeRange(firstInstruction.variable.address, firstInstruction.variable.size)];
	}
	[self updateStatusBar];
}

- (BOOL)isBreakPointAtInstruction:(ZGInstruction *)instruction
{
	return [self.breakPointController.breakPoints zgHasObjectMatchingCondition:^(ZGBreakPoint *breakPoint) {
		return (BOOL)(breakPoint.delegate == self && breakPoint.type == ZGBreakPointInstruction && breakPoint.task == self.currentProcess.processTask && breakPoint.variable.address == instruction.variable.address && !breakPoint.hidden);
	}];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)__unused tableView
{
	return (NSInteger)self.instructions.count;
}

- (id)tableView:(NSTableView *)__unused tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	id result = nil;
	if (rowIndex >= 0 && (NSUInteger)rowIndex < self.instructions.count)
	{
		ZGInstruction *instruction = [self.instructions objectAtIndex:(NSUInteger)rowIndex];
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
	if (rowIndex >= 0 && (NSUInteger)rowIndex < self.instructions.count)
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
			NSArray *targetInstructions = nil;
			NSArray *selectedInstructions = [self selectedInstructions];
			ZGInstruction *instruction = [self.instructions objectAtIndex:(NSUInteger)rowIndex];
			if (![selectedInstructions containsObject:instruction])
			{
				targetInstructions = @[instruction];
			}
			else
			{
				targetInstructions = selectedInstructions;
				if (targetInstructions.count > 1)
				{
					self.instructionsTableView.shouldIgnoreNextSelection = YES;
				}
			}
			
			if ([object boolValue])
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
	if ([tableColumn.identifier isEqualToString:@"address"] && rowIndex >= 0 && (NSUInteger)rowIndex < self.instructions.count)
	{
		ZGInstruction *instruction = [self.instructions objectAtIndex:(NSUInteger)rowIndex];
		BOOL isInstructionBreakPoint = (self.currentBreakPoint && self.registersViewController.instructionPointer == instruction.variable.address);
		
		[cell setTextColor:isInstructionBreakPoint ? NSColor.redColor : NSColor.textColor];
	}
}

- (NSString *)tableView:(NSTableView *)__unused tableView toolTipForCell:(NSCell *)__unused cell rect:(NSRectPointer)__unused rect tableColumn:(NSTableColumn *)__unused tableColumn row:(NSInteger)row mouseLocation:(NSPoint)__unused mouseLocation
{
	NSString *toolTip = nil;
	
	if (row >= 0 && (NSUInteger)row < self.instructions.count)
	{
		ZGInstruction *instruction = [self.instructions objectAtIndex:(NSUInteger)row];
		
		for (ZGBreakPointCondition *breakPointCondition in self.breakPointConditions)
		{
			if ([breakPointCondition.internalProcessName isEqualToString:self.currentProcess.internalName] && instruction.variable.address == breakPointCondition.address)
			{
				toolTip = [NSString stringWithFormat:@"Breakpoint Condition: %@", breakPointCondition.condition];
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
	ZGInstruction *firstInstruction = [self.instructions objectAtIndex:instructionIndex];
	NSData *data = [ZGDebuggerUtilities assembleInstructionText:instructionText atInstructionPointer:firstInstruction.variable.address usingArchitectureBits:self.currentProcess.pointerSize * 8 error:&error];
	if (data.length == 0)
	{
		if (error != nil)
		{
			ZG_LOG(@"%@", error);
			NSRunAlertPanel(@"Failed to Modify Instruction", @"An error occured trying to assemble \"%@\": %@", @"OK", nil, nil, instructionText, [error.userInfo objectForKey:@"reason"]);
		}
	}
	else
	{
		NSMutableData *outputData = [NSMutableData dataWithData:data];
		
		// Fill leftover bytes with NOP's so that the instructions won't 'slide'
		NSUInteger originalOutputLength = outputData.length;
		NSUInteger bytesRead = 0;
		NSUInteger numberOfInstructionsOverwritten = 0;
		
		for (ZGMemorySize currentInstructionIndex = instructionIndex; (bytesRead < originalOutputLength) && (currentInstructionIndex < self.instructions.count); currentInstructionIndex++)
		{
			ZGInstruction *currentInstruction = [self.instructions objectAtIndex:currentInstructionIndex];
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
			NSRunAlertPanel(@"Failed to Overwrite Instructions", @"This modification exceeds the boundary of instructions displayed.", @"OK", nil, nil);
		}
		else
		{
			BOOL shouldOverwriteInstructions = YES;
			if (numberOfInstructionsOverwritten > 1 && NSRunAlertPanel(@"Overwrite Instructions", @"This modification will overwrite %ld instructions. Are you sure you want to overwrite them?", @"Cancel", @"Overwrite", nil, numberOfInstructionsOverwritten) != NSAlertAlternateReturn)
			{
				shouldOverwriteInstructions = NO;
			}
			
			if (shouldOverwriteInstructions)
			{
				ZGVariable *newVariable = [[ZGVariable alloc] initWithValue:(void *)outputData.bytes size:outputData.length address:0 type:ZGByteArray qualifier:ZGSigned pointerSize:self.currentProcess.pointerSize];
				
				[self writeStringValue:newVariable.stringValue atInstructionFromIndex:instructionIndex];
			}
		}
	}
}

- (void)writeStringValue:(NSString *)stringValue atInstructionFromIndex:(NSUInteger)initialInstructionIndex
{
	ZGInstruction *instruction = [self.instructions objectAtIndex:initialInstructionIndex];
	
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
				while (writeIndex < newWriteSize && instructionIndex < self.instructions.count)
				{
					ZGInstruction *currentInstruction = [self.instructions objectAtIndex:instructionIndex];
					for (ZGMemorySize valueIndex = 0; (writeIndex < newWriteSize) && (valueIndex < currentInstruction.variable.size); valueIndex++, writeIndex++)
					{
						*(char *)(oldValue + writeIndex) = *(char *)(currentInstruction.variable.rawValue + valueIndex);
					}
					
					instructionIndex++;
				}
				
				if (writeIndex >= newWriteSize)
				{
					ZGVariable *newVariable = [[ZGVariable alloc] initWithValue:newWriteValue size:newWriteSize address:instruction.variable.address type:ZGByteArray qualifier:ZGSigned pointerSize:self.currentProcess.pointerSize];
					
					ZGVariable *oldVariable = [[ZGVariable alloc] initWithValue:oldValue size:newWriteSize address:instruction.variable.address type:ZGByteArray qualifier:ZGSigned pointerSize:self.currentProcess.pointerSize];
					
					[ZGDebuggerUtilities replaceInstructions:@[instruction] fromOldStringValues:@[oldVariable.stringValue] toNewStringValues:@[newVariable.stringValue] inProcess:self.currentProcess breakPoints:self.breakPointController.breakPoints undoManager:self.undoManager actionName:@"Instruction Change"];
				}
				
				free(oldValue);
			}
		}
		
		free(newWriteValue);
	}
}

- (IBAction)nopVariables:(id)__unused sender
{
	[ZGDebuggerUtilities nopInstructions:[self selectedInstructions] inProcess:self.currentProcess breakPoints:self.breakPointController.breakPoints undoManager:self.undoManager actionName:@"NOP Change"];
}

- (IBAction)requestCodeInjection:(id)__unused sender
{
	if (self.codeInjectionController == nil)
	{
		self.codeInjectionController = [[ZGCodeInjectionWindowController alloc] init];
	}
	
	[self.codeInjectionController
	 attachToWindow:self.window
	 process:self.currentProcess
	 instruction:[self.selectedInstructions objectAtIndex:0]
	 breakPoints:self.breakPointController.breakPoints
	 undoManager:self.undoManager];
}

#pragma mark Break Points

- (BOOL)hasBreakPoint
{
	return [self.breakPointController.breakPoints zgHasObjectMatchingCondition:^(ZGBreakPoint *breakPoint) { return (BOOL)(breakPoint.delegate == self); }];
}

- (void)startBreakPointActivity
{
	if (self.breakPointActivity == nil && [[NSProcessInfo processInfo] respondsToSelector:@selector(beginActivityWithOptions:reason:)]	)
	{
		self.breakPointActivity = [[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityBackground reason:@"Software Breakpoint"];
	}
}

- (void)stopBreakPointActivity
{
	if (self.breakPointActivity != nil)
	{
		[[NSProcessInfo processInfo] endActivity:self.breakPointActivity];
		self.breakPointActivity = nil;
	}
}

- (void)removeBreakPointsToInstructions:(NSArray *)instructions
{
	NSMutableArray *changedInstructions = [[NSMutableArray alloc] init];
	
	for (ZGInstruction *instruction in instructions)
	{
		if ([self isBreakPointAtInstruction:instruction])
		{
			[changedInstructions addObject:instruction];
			[self.breakPointController removeBreakPointOnInstruction:instruction inProcess:self.currentProcess];
		}
	}
	
	if (![self hasBreakPoint])
	{
		[self stopBreakPointActivity];
	}
	
	[self.undoManager setActionName:[NSString stringWithFormat:@"Add Breakpoint%@", changedInstructions.count != 1 ? @"s" : @""]];
	[[self.undoManager prepareWithInvocationTarget:self] addBreakPointsToInstructions:changedInstructions];
	
	[self.instructionsTableView reloadData];
}

- (void)conditionalInstructionBreakPointWasRemoved
{
	[self.instructionsTableView reloadData];
}

- (void)addBreakPointsToInstructions:(NSArray *)instructions
{
	NSMutableArray *changedInstructions = [[NSMutableArray alloc] init];
	
	BOOL addedAtLeastOneBreakPoint = NO;
	
	for (ZGInstruction *instruction in instructions)
	{
		if (![self isBreakPointAtInstruction:instruction])
		{
			[changedInstructions addObject:instruction];
			
			PyObject *compiledCondition = NULL;
			for (ZGBreakPointCondition *breakPointCondition in self.breakPointConditions)
			{
				if (breakPointCondition.address == instruction.variable.address && [breakPointCondition.internalProcessName isEqualToString:self.currentProcess.internalName])
				{
					compiledCondition = breakPointCondition.compiledCondition;
					break;
				}
			}
			
			if ([self.breakPointController addBreakPointOnInstruction:instruction inProcess:self.currentProcess condition:compiledCondition delegate:self])
			{
				addedAtLeastOneBreakPoint = YES;
			}
		}
	}
	
	if (addedAtLeastOneBreakPoint)
	{
		[self startBreakPointActivity];
		[self.undoManager setActionName:[NSString stringWithFormat:@"Remove Breakpoint%@", changedInstructions.count != 1 ? @"s" : @""]];
		[[self.undoManager prepareWithInvocationTarget:self] removeBreakPointsToInstructions:changedInstructions];
		[self.instructionsTableView reloadData];
	}
	else
	{
		NSRunAlertPanel(@"Failed to Add Breakpoint", @"A breakpoint could not be added. Please try again later.", @"OK", nil, nil);
	}
}

- (IBAction)toggleBreakPoints:(id)__unused sender
{
	if ([self isBreakPointAtInstruction:[self.selectedInstructions objectAtIndex:0]])
	{
		[self removeBreakPointsToInstructions:self.selectedInstructions];
	}
	else
	{
		[self addBreakPointsToInstructions:self.selectedInstructions];
	}
}

- (IBAction)removeAllBreakPoints:(id)__unused sender
{
	[self.breakPointController removeObserver:self];
	[self stopBreakPointActivity];
	[self.undoManager removeAllActions];
	[self.instructionsTableView reloadData];
}

- (void)addHaltedBreakPoint:(ZGBreakPoint *)breakPoint
{
	NSMutableArray *newBreakPoints = [[NSMutableArray alloc] initWithArray:self.haltedBreakPoints];
	[newBreakPoints addObject:breakPoint];
	self.haltedBreakPoints = [NSArray arrayWithArray:newBreakPoints];
	
	if (breakPoint.process.processID == self.currentProcess.processID)
	{
		[self.instructionsTableView reloadData];
	}
}

- (void)removeHaltedBreakPoint:(ZGBreakPoint *)breakPoint
{
	NSMutableArray *newBreakPoints = [[NSMutableArray alloc] initWithArray:self.haltedBreakPoints];
	[newBreakPoints removeObject:breakPoint];
	self.haltedBreakPoints = [NSArray arrayWithArray:newBreakPoints];
	
	if (breakPoint.process.processID == self.currentProcess.processID)
	{
		[self.instructionsTableView reloadData];
	}
}

- (ZGBreakPoint *)currentBreakPoint
{
	ZGBreakPoint *currentBreakPoint = nil;
	
	for (ZGBreakPoint *breakPoint in self.haltedBreakPoints)
	{
		if (breakPoint.process.processID == self.currentProcess.processID)
		{
			currentBreakPoint = breakPoint;
			break;
		}
	}
	
	return currentBreakPoint;
}

- (ZGInstruction *)findInstructionInTableAtAddress:(ZGMemoryAddress)targetAddress
{
	ZGInstruction *foundInstruction = [self.instructions zgBinarySearchUsingBlock:^NSComparisonResult(__unsafe_unretained ZGInstruction *instruction) {
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

- (void)moveInstructionPointerToAddress:(ZGMemoryAddress)newAddress
{
	if (self.currentBreakPoint != nil)
	{
		ZGMemoryAddress currentAddress = self.registersViewController.instructionPointer;
		[self.registersViewController changeInstructionPointer:newAddress];
		[[self.undoManager prepareWithInvocationTarget:self] moveInstructionPointerToAddress:currentAddress];
		[self.undoManager setActionName:@"Jump"];
	}
}

- (IBAction)jump:(id)__unused sender
{
	ZGInstruction *instruction = [self.selectedInstructions objectAtIndex:0];
	[self moveInstructionPointerToAddress:instruction.variable.address];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (object == self.registersViewController)
	{
		[self.instructionsTableView reloadData];
	}
	
	[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)updateRegisters
{
	[self.registersViewController updateRegistersFromBreakPoint:self.currentBreakPoint];
}

- (void)updateBacktrace
{
	ZGBacktrace *backtrace = [ZGBacktrace backtraceWithBasePointer:self.registersViewController.basePointer instructionPointer:self.registersViewController.instructionPointer process:self.currentProcess breakPoints:self.breakPointController.breakPoints machBinaries:[ZGMachBinary machBinariesInProcess:self.currentProcess]];
	
	if ([self shouldUpdateSymbolsForInstructions:backtrace.instructions])
	{
		[self updateSymbolsForInstructions:backtrace.instructions];
	}
	
	for (ZGInstruction *instruction in backtrace.instructions)
	{
		if (instruction.symbols.length == 0)
		{
			instruction.symbols = @""; // in case symbols is nil
			instruction.variable.fullAttributedDescription = [[NSAttributedString alloc] initWithString:instruction.variable.addressStringValue];
		}
		else
		{
			instruction.variable.fullAttributedDescription = [[NSAttributedString alloc] initWithString:instruction.symbols];
		}
	}
	
	self.backtraceViewController.backtrace = backtrace;
	self.backtraceViewController.process = [[ZGProcess alloc] initWithProcess:self.currentProcess];
}

- (void)backtraceSelectionChangedToAddress:(ZGMemoryAddress)address
{
	[self jumpToMemoryAddress:address inProcess:self.currentProcess];
}

- (void)breakPointDidHit:(ZGBreakPoint *)breakPoint
{	
	[self removeHaltedBreakPoint:self.currentBreakPoint];
	[self addHaltedBreakPoint:breakPoint];
	
	if (self.currentBreakPoint != nil)
	{
		if (!self.window.isVisible)
		{
			[self showWindow:nil];
		}
		
		if (self.registersViewController == nil)
		{
			self.registersViewController = [[ZGRegistersViewController alloc] initWithUndoManager:self.undoManager];
			[self.registersViewController addObserver:self forKeyPath:ZG_SELECTOR_STRING(self.registersViewController, instructionPointer) options:NSKeyValueObservingOptionNew context:NULL];
			
			[self.registersView addSubview:self.registersViewController.view];
			self.registersViewController.view.frame = self.registersView.bounds;
		}
		
		if (self.backtraceViewController == nil)
		{
			self.backtraceViewController = [[ZGBacktraceViewController alloc] initWithDelegate:self];
			
			[self.backtraceView addSubview:self.backtraceViewController.view];
			self.backtraceViewController.view.frame = self.backtraceView.bounds;
		}
		
		[self updateRegisters];
		
		[self toggleBacktraceAndRegistersViews:NSOnState];
		
		[self jumpToMemoryAddress:self.registersViewController.instructionPointer];
		
		[self updateBacktrace];
		
		BOOL shouldShowNotification = YES;
		
		if (self.currentBreakPoint.hidden)
		{
			if (breakPoint.basePointer == self.registersViewController.basePointer)
			{
				[self.breakPointController removeInstructionBreakPoint:breakPoint];
			}
			else
			{
				[self continueFromBreakPoint:self.currentBreakPoint];
				shouldShowNotification = NO;
			}
		}
		
		[self updateExecutionButtons];
		
		if (breakPoint.error == nil && shouldShowNotification)
		{
			ZGDeliverUserNotification(@"Hit Breakpoint", self.currentProcess.name, [NSString stringWithFormat:@"Stopped at breakpoint %@", self.currentBreakPoint.variable.addressStringValue]);
		}
		else if (breakPoint.error != nil)
		{
			NSString *scriptContents = @"N/A";
			for (ZGBreakPointCondition *breakPointCondition in self.breakPointConditions)
			{
				if ([breakPointCondition.internalProcessName isEqualToString:breakPoint.process.internalName] && breakPointCondition.address == breakPoint.variable.address)
				{
					scriptContents = breakPointCondition.condition;
					break;
				}
			}
			
			[self.loggerWindowController writeLine:[breakPoint.error.userInfo objectForKey:SCRIPT_PYTHON_ERROR]];
			
			NSRunAlertPanel(@"Condition Evaluation Error", @"\"%@\" failed to evaluate with the following reason: %@. Check Debug -> Logs in the menu bar for more information.", @"OK", nil, nil, scriptContents, [breakPoint.error.userInfo objectForKey:SCRIPT_EVALUATION_ERROR_REASON]);
			
			breakPoint.error = nil;
		}
	}
}

- (void)resumeBreakPoint:(ZGBreakPoint *)breakPoint
{
	[self.breakPointController resumeFromBreakPoint:breakPoint];
	[self removeHaltedBreakPoint:breakPoint];
	
	[self updateExecutionButtons];
}

- (void)continueFromBreakPoint:(ZGBreakPoint *)breakPoint
{
	[self.breakPointController removeSingleStepBreakPointsFromBreakPoint:breakPoint];
	[self resumeBreakPoint:breakPoint];
	[self toggleBacktraceAndRegistersViews:NSOffState];
}

- (IBAction)continueExecution:(id)__unused sender
{
	[self continueFromBreakPoint:self.currentBreakPoint];
}

- (IBAction)stepInto:(id)__unused sender
{
	[self.breakPointController addSingleStepBreakPointFromBreakPoint:self.currentBreakPoint];
	[self resumeBreakPoint:self.currentBreakPoint];
}

- (IBAction)stepOver:(id)__unused sender
{
	NSArray *machBinaries = [ZGMachBinary machBinariesInProcess:self.currentProcess];
	
	ZGInstruction *currentInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:self.registersViewController.instructionPointer + 1 inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints machBinaries:machBinaries];
	
	if ([ZGDisassemblerObject isCallMnemonic:currentInstruction.mnemonic])
	{
		ZGInstruction *nextInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:currentInstruction.variable.address + currentInstruction.variable.size + 1 inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints machBinaries:machBinaries];
		
		if ([self.breakPointController addBreakPointOnInstruction:nextInstruction inProcess:self.currentProcess thread:self.currentBreakPoint.thread basePointer:self.registersViewController.basePointer delegate:self])
		{
			[self continueExecution:nil];
		}
		else
		{
			NSRunAlertPanel(@"Failed to Step Over", @"Stepping over the instruction failed. Please try again.", @"OK", nil, nil);
		}
	}
	else
	{
		[self stepInto:nil];
	}
}

- (IBAction)stepOut:(id)__unused sender
{
	ZGInstruction *outerInstruction = [self.backtraceViewController.backtrace.instructions objectAtIndex:1];
	
	ZGInstruction *returnInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:outerInstruction.variable.address + outerInstruction.variable.size + 1 inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints machBinaries:[ZGMachBinary machBinariesInProcess:self.currentProcess]];

	if ([self.breakPointController addBreakPointOnInstruction:returnInstruction inProcess:self.currentProcess thread:self.currentBreakPoint.thread basePointer:[[self.backtraceViewController.backtrace.basePointers objectAtIndex:1] unsignedLongLongValue] delegate:self])
	{
		[self continueExecution:nil];
	}
	else
	{
		NSRunAlertPanel(@"Failed to Step Out", @"Stepping out of the function failed. Please try again.", @"OK", nil, nil);
	}
}

- (IBAction)stepExecution:(id)sender
{
	switch ((enum ZGStepExecution)[sender selectedSegment])
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

- (void)applicationWillTerminate:(NSNotification *)__unused notification
{
	[self cleanup];
}

- (void)cleanup
{
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		[self.breakPointController removeObserver:self];
		
		for (ZGBreakPoint *breakPoint in self.haltedBreakPoints)
		{
			[self continueFromBreakPoint:breakPoint];
		}
	});
}

- (BOOL)isProcessIdentifierHalted:(pid_t)processIdentifier
{
	return [self.haltedBreakPoints zgHasObjectMatchingCondition:^(ZGBreakPoint *breakPoint) { return (BOOL)(breakPoint.process.processID == processIdentifier); }];
}

#pragma mark Breakpoint Conditions

- (IBAction)showBreakPointCondition:(id)__unused sender
{
	if (self.breakPointConditionPopover == nil)
	{
		self.breakPointConditionPopover = [[NSPopover alloc] init];
		self.breakPointConditionPopover.contentViewController = [[ZGBreakPointConditionViewController alloc] initWithDelegate:self];
		self.breakPointConditionPopover.behavior = NSPopoverBehaviorSemitransient;
	}
	
	ZGInstruction *selectedInstruction = [self.selectedInstructions objectAtIndex:0];
	
	[(ZGBreakPointConditionViewController *)self.breakPointConditionPopover.contentViewController setTargetAddress:selectedInstruction.variable.address];
	
	NSString *displayedCondition = @"";
	for (ZGBreakPointCondition *breakPointCondition in self.breakPointConditions)
	{
		if ([breakPointCondition.internalProcessName isEqualToString:self.currentProcess.internalName] && breakPointCondition.address == selectedInstruction.variable.address)
		{
			displayedCondition = breakPointCondition.condition;
			break;
		}
	}
	
	[(ZGBreakPointConditionViewController *)self.breakPointConditionPopover.contentViewController setCondition:displayedCondition];
	
	NSUInteger selectedRow = [self.selectedInstructionIndexes firstIndex];
	
	NSRange visibleRowsRange = [self.instructionsTableView rowsInRect:self.instructionsTableView.visibleRect];
	if (visibleRowsRange.location > selectedRow || selectedRow >= visibleRowsRange.location + visibleRowsRange.length)
	{
		[self scrollAndSelectRow:selectedRow];
	}
	
	NSRect cellFrame = [self.instructionsTableView frameOfCellAtColumn:0 row:(NSInteger)selectedRow];
	[self.breakPointConditionPopover showRelativeToRect:cellFrame ofView:self.instructionsTableView preferredEdge:NSMaxYEdge];
}

- (void)breakPointConditionDidCancel
{
	[self.breakPointConditionPopover performClose:nil];
}

- (BOOL)changeBreakPointCondition:(NSString *)breakPointCondition atAddress:(ZGMemoryAddress)address error:(NSError * __autoreleasing *)error
{
	NSString *strippedCondition = [breakPointCondition stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	
	PyObject *newCompiledCondition = NULL;
	
	if (strippedCondition.length > 0)
	{
		newCompiledCondition = [ZGScriptManager compiledExpressionFromExpression:strippedCondition error:error];
		if (newCompiledCondition == NULL)
		{
			NSLog(@"Error: compiled expression %@ is NULL", strippedCondition);
			return NO;
		}
	}
	
	NSArray *breakPoints = self.breakPointController.breakPoints;
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
	for (ZGBreakPointCondition *breakCondition in self.breakPointConditions)
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
		if (self.breakPointConditions == nil)
		{
			self.breakPointConditions = [NSMutableArray array];
		}
		
		[self.breakPointConditions addObject:
		 [[ZGBreakPointCondition alloc]
		  initWithInternalProcessName:self.currentProcess.internalName
		  address:address
		  condition:strippedCondition
		  compiledCondition:newCompiledCondition]];
	}
	
	[[self.undoManager prepareWithInvocationTarget:self] changeBreakPointCondition:oldCondition atAddress:address error:error];
	
	return YES;
}

- (void)breakPointCondition:(NSString *)condition didChangeAtAddress:(ZGMemoryAddress)address
{
	NSError *error = nil;
	if (![self changeBreakPointCondition:condition atAddress:address error:&error])
	{
		[self.loggerWindowController writeLine:[error.userInfo objectForKey:SCRIPT_PYTHON_ERROR]];
		NSRunAlertPanel(@"Invalid Breakpoint Expression", @"%@", @"OK", nil, nil, [error.userInfo objectForKey:SCRIPT_COMPILATION_ERROR_REASON]);
	}
	else
	{
		[self.breakPointConditionPopover performClose:nil];
	}
}

#pragma mark Memory Viewer

- (IBAction)showMemoryViewer:(id)__unused sender
{
	ZGInstruction *selectedInstruction = [self.selectedInstructions objectAtIndex:0];
	
	[ZGNavigationPost postShowMemoryViewerWithProcess:self.currentProcess address:selectedInstruction.variable.address selectionLength:selectedInstruction.variable.size];
}

@end
