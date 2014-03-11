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
#import "ZGMemoryViewerController.h"
#import "NSArrayAdditions.h"
#import "ZGVirtualMemory.h"
#import "ZGVirtualMemoryHelpers.h"
#import "ZGMachBinary.h"
#import "ZGMachBinaryInfo.h"
#import "CoreSymbolication.h"
#import "ZGTableView.h"
#import "ZGVariableController.h"
#import "ZGBacktrace.h"

#define ZGDebuggerSplitViewAutosaveName @"ZGDisassemblerHorizontalSplitter"
#define ZGRegistersAndBacktraceSplitViewAutosaveName @"ZGDisassemblerVerticalSplitter"

@interface ZGDebuggerController ()

@property (nonatomic) ZGBreakPointController *breakPointController;
@property (nonatomic, weak) ZGMemoryViewerController *memoryViewer;
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

@property (nonatomic) BOOL disassembling;

@property (nonatomic) NSArray *instructions;

@property (nonatomic) NSRange instructionBoundary;

@property (nonatomic) ZGCodeInjectionWindowController *codeInjectionController;

@property (nonatomic) NSArray *haltedBreakPoints;
@property (nonatomic, readonly) ZGBreakPoint *currentBreakPoint;

@property (nonatomic) NSPopover *breakPointConditionPopover;
@property (nonatomic) NSMutableArray *breakPointConditions;

@property (nonatomic) id breakPointActivity;

@property (nonatomic) CSSymbolicatorRef symbolicator;
@property (nonatomic) NSDictionary *lastSearchInfo;

@end

#define ZGDebuggerAddressField @"ZGDisassemblerAddressField"
#define ZGDebuggerProcessInternalName @"ZGDisassemblerProcessName"
#define ZGDebuggerOffsetFromBase @"ZGDebuggerOffsetFromBase"
#define ZGDebuggerMappedFilePath @"ZGDebuggerMappedFilePath"

#define NOP_VALUE 0x90
#define JUMP_REL32_INSTRUCTION_LENGTH 5

enum ZGStepExecution
{
	ZGStepIntoExecution,
	ZGStepOverExecution,
	ZGStepOutExecution
};

@implementation ZGDebuggerController

#pragma mark Birth & Death

- (id)initWithProcessTaskManager:(ZGProcessTaskManager *)processTaskManager breakPointController:(ZGBreakPointController *)breakPointController memoryViewer:(ZGMemoryViewerController *)memoryViewer loggerWindowController:(ZGLoggerWindowController *)loggerWindowController
{
	self = [super initWithProcessTaskManager:processTaskManager];
	
	if (self)
	{
		self.debuggerController = self;
		self.breakPointController = breakPointController;
		self.memoryViewer = memoryViewer;
		self.loggerWindowController = loggerWindowController;
		
		self.haltedBreakPoints = [[NSArray alloc] init];
		
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
	
	[self windowDidShow:nil];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
	
	[self setWindowAttributesWithIdentifier:ZGDebuggerIdentifier];
	
	[self setupProcessListNotificationsAndPopUpButton];
	
	[self.instructionsTableView registerForDraggedTypes:@[ZGVariablePboardType]];
	
	[self.statusTextField.cell setBackgroundStyle:NSBackgroundStyleRaised];
	
	[self.continueButton.image setTemplate:YES];
	[[self.stepExecutionSegmentedControl imageForSegment:ZGStepIntoExecution] setTemplate:YES];
	[[self.stepExecutionSegmentedControl imageForSegment:ZGStepOverExecution] setTemplate:YES];
	[[self.stepExecutionSegmentedControl imageForSegment:ZGStepOutExecution] setTemplate:YES];
	
	[self updateExecutionButtons];
	
	[self createSymbolicator];
	
	[self toggleBacktraceAndRegistersViews:NSOffState];
	
	// Don't set these in IB; can't trust setting these at the right time and not screwing up the saved positions
	self.splitView.autosaveName = ZGDebuggerSplitViewAutosaveName;
	self.registersAndBacktraceSplitView.autosaveName = ZGRegistersAndBacktraceSplitViewAutosaveName;
}

- (void)createSymbolicator
{
	if (!CSIsNull(self.symbolicator) && self.currentProcess.valid)
	{
		CSRelease(self.symbolicator);
	}
	
	if (self.currentProcess.valid)
	{
		self.symbolicator = CSSymbolicatorCreateWithTask(self.currentProcess.processTask);
	}
	else
	{
		self.symbolicator = kCSNull;
	}
}

- (void)windowDidAppearForFirstTime:(id)sender
{
	if (!sender)
	{
		[self readMemory:nil];
	}
}

#pragma mark Current Process Changed

- (void)currentProcessChanged
{
	[self createSymbolicator];
	
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
		[self readMemory:nil];
	}
}

#pragma mark Split Views

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex
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

- (BOOL)splitView:(NSSplitView *)splitView shouldHideDividerAtIndex:(NSInteger)dividerIndex
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
		CSSymbolRef symbol = CSSymbolicatorGetSymbolWithAddressAtTime(self.symbolicator, instruction.variable.address, kCSNow);
		if (!CSIsNull(symbol))
		{
			NSMutableString *symbolName = [NSMutableString string];
			
			const char *symbolNameCString = CSSymbolGetName(symbol);
			if (symbolNameCString != NULL)
			{
				[symbolName setString:@(symbolNameCString)];
			}
			
			CSRange symbolRange = CSSymbolGetRange(symbol);
			[symbolName appendFormat:@" + %llu", instruction.variable.address - symbolRange.location];
			
			instruction.symbols = symbolName;
		}
	}
}

- (BOOL)shouldUpdateSymbolsForInstructions:(NSArray *)instructions
{
	BOOL shouldUpdateSymbols = NO;
	
	if (!CSIsNull(self.symbolicator))
	{
		for (ZGInstruction *instruction in instructions)
		{
			if (instruction.symbols == nil)
			{
				shouldUpdateSymbols = YES;
				break;
			}
		}
	}
	
	return shouldUpdateSymbols;
}

#pragma mark Disassembling

+ (NSData *)readDataWithProcessTask:(ZGMemoryMap)processTask address:(ZGMemoryAddress)address size:(ZGMemorySize)size breakPoints:(NSArray *)breakPoints
{
	void *originalBytes = NULL;
	if (!ZGReadBytes(processTask, address, &originalBytes, &size))
	{
		return nil;
	}
	
	void *newBytes = malloc(size);
	memcpy(newBytes, originalBytes, size);
	
	ZGFreeBytes(processTask, originalBytes, size);
	
	for (ZGBreakPoint *breakPoint in breakPoints)
	{
		if (breakPoint.type == ZGBreakPointInstruction && breakPoint.task == processTask && breakPoint.variable.address >= address && breakPoint.variable.address < address + size)
		{
			memcpy(newBytes + (breakPoint.variable.address - address), breakPoint.variable.value, sizeof(uint8_t));
		}
	}
	
	return [NSData dataWithBytesNoCopy:newBytes length:size];
}

+ (ZGDisassemblerObject *)disassemblerObjectWithProcessTask:(ZGMemoryMap)processTask pointerSize:(ZGMemorySize)pointerSize address:(ZGMemoryAddress)address size:(ZGMemorySize)size breakPoints:(NSArray *)breakPoints
{
	ZGDisassemblerObject *newObject = nil;
	NSData *data = [self readDataWithProcessTask:processTask address:address size:size breakPoints:breakPoints];
	if (data != nil)
	{
		newObject = [[ZGDisassemblerObject alloc] initWithBytes:data.bytes address:address size:data.length pointerSize:pointerSize];
	}
	return newObject;
}

+ (ZGInstruction *)findInstructionBeforeAddress:(ZGMemoryAddress)address inProcess:(ZGProcess *)process withBreakPoints:(NSArray *)breakPoints
{
	ZGInstruction *instruction = nil;
	
	ZGMemoryBasicInfo regionInfo;
	ZGRegion *targetRegion = [[ZGRegion alloc] initWithAddress:address size:1];
	if (!ZGRegionInfo(process.processTask, &targetRegion->_address, &targetRegion->_size, &regionInfo))
	{
		targetRegion = nil;
	}
	
	if (targetRegion != nil && address >= targetRegion.address && address <= targetRegion.address + targetRegion.size)
	{
		// Start an arbitrary number of bytes before our address and decode the instructions
		// Eventually they will converge into correct offsets
		// So retrieve the offset and size to the last instruction while decoding
		// We do this instead of starting at region.address due to this leading to better performance
		
		ZGMemoryAddress startAddress = address - 1024;
		if (startAddress < targetRegion.address)
		{
			startAddress = targetRegion.address;
		}
		
		ZGMachBinary *machBinary = [ZGMachBinary machBinaryNearestToAddress:address fromMachBinaries:[ZGMachBinary machBinariesInProcess:process]];
		ZGMemoryAddress firstInstructionAddress = [[machBinary machBinaryInfoInProcess:process] firstInstructionAddress];
		
		if (firstInstructionAddress != 0 && startAddress < firstInstructionAddress)
		{
			startAddress = firstInstructionAddress;
			if (address < startAddress)
			{
				return instruction;
			}
		}
		
		ZGMemorySize size = address - startAddress;
		// Read in more bytes to ensure we return the whole instruction
		ZGMemorySize readSize = size + 30;
		if (startAddress + readSize > targetRegion.address + targetRegion.size)
		{
			readSize = targetRegion.address + targetRegion.size - startAddress;
		}
		
		ZGDisassemblerObject *disassemblerObject = [self disassemblerObjectWithProcessTask:process.processTask pointerSize:process.pointerSize address:startAddress size:readSize breakPoints:breakPoints];
		
		instruction = [disassemblerObject readLastInstructionWithMaxSize:size];
	}
	
	return instruction;
}

- (void)updateInstructionValues
{
	// Check to see if anything in the window needs to be updated
	NSRange visibleRowsRange = [self.instructionsTableView rowsInRect:self.instructionsTableView.visibleRect];
	if (visibleRowsRange.location + visibleRowsRange.length <= self.instructions.count)
	{
		__block ZGMemoryAddress regionAddress = 0x0;
		__block ZGMemorySize regionSize = 0x0;
		__block BOOL foundRegion = NO;
		
		__block BOOL needsToUpdateWindow = NO;
		[[self.instructions subarrayWithRange:visibleRowsRange] enumerateObjectsUsingBlock:^(ZGInstruction *instruction, NSUInteger index, BOOL *stop)
		 {
			 void *bytes = NULL;
			 ZGMemorySize size = instruction.variable.size;
			 if (ZGReadBytes(self.currentProcess.processTask, instruction.variable.address, &bytes, &size))
			 {
				 if (memcmp(bytes, instruction.variable.value, size) != 0)
				 {
					 // Ignore trivial breakpoint changes
					 BOOL foundBreakPoint = NO;
					 if (*(uint8_t *)bytes == INSTRUCTION_BREAKPOINT_OPCODE && (size == sizeof(uint8_t) || memcmp(bytes+sizeof(uint8_t), instruction.variable.value+sizeof(uint8_t), size-sizeof(uint8_t)) == 0))
					 {
						 for (ZGBreakPoint *breakPoint in self.breakPointController.breakPoints)
						 {
							 if (breakPoint.type == ZGBreakPointInstruction && breakPoint.variable.address == instruction.variable.address && *(uint8_t *)breakPoint.variable.value == *(uint8_t *)instruction.variable.value)
							 {
								 foundBreakPoint = YES;
								 break;
							 }
						 }
					 }
					 
					 if (!foundBreakPoint)
					 {
						 // Find the region our instruction is in
						 ZGMemoryBasicInfo unusedInfo;
						 regionAddress = instruction.variable.address;
						 regionSize = instruction.variable.size;
						 foundRegion = ZGRegionInfo(self.currentProcess.processTask, &regionAddress, &regionSize, &unusedInfo);
						 needsToUpdateWindow = YES;
						 *stop = YES;
					 }
				 }
				 
				 ZGFreeBytes(self.currentProcess.processTask, bytes, size);
			 }
		 }];
		
		if (needsToUpdateWindow)
		{
			// Find a [start, end) range that we are allowed to remove from the table and insert in again with new instructions
			// Pick start and end such that they are aligned with the assembly instructions
			
			NSUInteger startRow = visibleRowsRange.location;
			
			do
			{
				if (startRow == 0) break;
				
				ZGInstruction *instruction = [self.instructions objectAtIndex:startRow];
				ZGInstruction *searchedInstruction = [[self class] findInstructionBeforeAddress:instruction.variable.address inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints];
				
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
				ZGInstruction *searchedInstruction = [[self class] findInstructionBeforeAddress:startInstruction.variable.address inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints];
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
				ZGInstruction *searchedInstruction = [[self class] findInstructionBeforeAddress:instruction.variable.address + instruction.variable.size inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints];
				
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
				ZGInstruction *searchedInstruction = [[self class] findInstructionBeforeAddress:endInstruction.variable.address + endInstruction.variable.size inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints];
				if (endInstruction.variable.address != searchedInstruction.variable.address)
				{
					endAddress = searchedInstruction.variable.address + searchedInstruction.variable.size;
				}
			}
			
			ZGMemorySize size = endAddress - startAddress;
			
			ZGDisassemblerObject *disassemblerObject = [[self class] disassemblerObjectWithProcessTask:self.currentProcess.processTask pointerSize:self.currentProcess.pointerSize address:startAddress size:size breakPoints:self.breakPointController.breakPoints];
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
	static BOOL isUpdatingSymbols = NO;
	
	NSRange visibleRowsRange = [self.instructionsTableView rowsInRect:self.instructionsTableView.visibleRect];
	if (visibleRowsRange.location + visibleRowsRange.length <= self.instructions.count)
	{
		NSArray *instructions = [self.instructions subarrayWithRange:visibleRowsRange];
		if ([self shouldUpdateSymbolsForInstructions:instructions] && !isUpdatingSymbols)
		{
			isUpdatingSymbols = YES;
			[self updateSymbolsForInstructions:instructions];
			[self.instructionsTableView reloadData];
			isUpdatingSymbols = NO;
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
	
	while (startInstruction == nil && bytesBehind > 0)
	{
		startInstruction = [[self class] findInstructionBeforeAddress:endInstruction.variable.address - bytesBehind inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints];
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
		
		ZGDisassemblerObject *disassemblerObject = [[self class] disassemblerObjectWithProcessTask:self.currentProcess.processTask pointerSize:self.currentProcess.pointerSize address:startInstruction.variable.address size:size breakPoints:self.breakPointController.breakPoints];
		
		if (disassemblerObject != nil)
		{
			NSMutableArray *instructionsToAdd = [NSMutableArray arrayWithArray:[disassemblerObject readInstructions]];
			
			NSUInteger numberOfInstructionsAdded = instructionsToAdd.count;
			NSRange visibleRowsRange = [self.instructionsTableView rowsInRect:self.instructionsTableView.visibleRect];
			
			[instructionsToAdd addObjectsFromArray:self.instructions];
			self.instructions = [NSArray arrayWithArray:instructionsToAdd];
			
			NSInteger previousSelectedRow = [self.instructionsTableView selectedRow];
			[self.instructionsTableView noteNumberOfRowsChanged];
			
			[self.instructionsTableView scrollRowToVisible:MIN(numberOfInstructionsAdded + visibleRowsRange.length - 1, self.instructions.count)];
			
			if (previousSelectedRow >= 0)
			{
				[self.instructionsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:previousSelectedRow + numberOfInstructionsAdded] byExtendingSelection:NO];
			}
		}
	}
}

- (void)addMoreInstructionsAfterLastRow
{
	ZGInstruction *lastInstruction = self.instructions.lastObject;
	ZGInstruction *startInstruction = [[self class] findInstructionBeforeAddress:(lastInstruction.variable.address + lastInstruction.variable.size + 1) inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints];
	
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
			endInstruction = [[self class] findInstructionBeforeAddress:(startInstruction.variable.address + startInstruction.variable.size + bytesAhead) inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints];
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
			
			ZGDisassemblerObject *disassemblerObject = [[self class] disassemblerObjectWithProcessTask:self.currentProcess.processTask pointerSize:self.currentProcess.pointerSize address:startInstruction.variable.address size:size breakPoints:self.breakPointController.breakPoints];
			
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

- (void)updateDisplayTimer:(NSTimer *)timer
{
	if (self.currentProcess.valid && self.instructionsTableView.editedRow == -1 && !self.disassembling && self.instructions.count > 0)
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
	
	self.currentMemoryAddress = address;
	self.currentMemorySize = 0;
	
	self.disassembling = YES;
	
	id disassemblingActivity = nil;
	if ([[NSProcessInfo processInfo] respondsToSelector:@selector(beginActivityWithOptions:reason:)])
	{
		disassemblingActivity = [[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiated reason:@"Disassembling Data"];
	}
	
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		ZGDisassemblerObject *disassemblerObject = [[self class] disassemblerObjectWithProcessTask:self.currentProcess.processTask pointerSize:self.currentProcess.pointerSize address:address size:size breakPoints:self.breakPointController.breakPoints];
		NSArray *newInstructions = @[];
		
		if (disassemblerObject != nil)
		{
			newInstructions = [disassemblerObject readInstructions];
		}
		
		dispatch_async(dispatch_get_main_queue(), ^{
			self.instructions = newInstructions;
			self.currentMemorySize = self.instructions.count;
			
			[self.instructionsTableView noteNumberOfRowsChanged];
			
			ZGInstruction *selectionInstruction = [self findInstructionInTableAtAddress:selectionAddress];
			if (selectionInstruction != nil)
			{
				[self scrollAndSelectRow:[self.instructions indexOfObject:selectionInstruction]];
			}
			
			self.disassembling = NO;
			if (disassemblingActivity != nil)
			{
				[[NSProcessInfo processInfo] endActivity:disassemblingActivity];
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
		});
	});
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

- (void)switchProcessMenuItemAndSelectAddress:(ZGMemoryAddress)address
{
	if ([self.runningApplicationsPopUpButton.selectedItem.representedObject processID] != self.currentProcess.processID)
	{
		self.addressTextField.stringValue = [NSString stringWithFormat:@"0x%llX", address];
		self.mappedFilePath = nil;
		[self switchProcess];
	}
}

- (IBAction)runningApplicationsPopUpButton:(id)sender
{
	[self switchProcessMenuItemAndSelectAddress:0x0];
}

#pragma mark Changing disassembler view

- (BOOL)canEnableNavigationButtons
{
	return !self.disassembling && [super canEnableNavigationButtons];
}

- (IBAction)jumpToOperandOffset:(id)sender
{
	ZGInstruction *selectedInstruction = [[self selectedInstructions] objectAtIndex:0];
	
	ZGDisassemblerObject *disassemblerObject = [[self class] disassemblerObjectWithProcessTask:self.currentProcess.processTask pointerSize:self.currentProcess.pointerSize address:selectedInstruction.variable.address size:selectedInstruction.variable.size breakPoints:self.breakPointController.breakPoints];
	
	if (disassemblerObject != nil)
	{
		[self jumpToMemoryAddress:[disassemblerObject readBranchImmediateOperand]];
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
	
	ZGMemoryAddress calculatedMemoryAddress = 0;
	if (self.mappedFilePath != nil && sender == nil)
	{
		NSError *error = nil;
		ZGMemoryAddress guessAddress = [[ZGMachBinary machBinaryWithPartialImageName:self.mappedFilePath inProcess:self.currentProcess error:&error] headerAddress] + self.offsetFromBase;
		
		if (error == nil)
		{
			calculatedMemoryAddress = guessAddress;
			[self.addressTextField setStringValue:[NSString stringWithFormat:@"0x%llX", calculatedMemoryAddress]];
		}
	}
	else
	{
		NSString *userInput = self.addressTextField.stringValue;
		NSError *error = nil;
		NSString *calculatedMemoryAddressExpression = [ZGCalculator evaluateExpression:userInput process:self.currentProcess failedImages:nil symbolicator:self.symbolicator lastSearchInfo:self.lastSearchInfo error:&error];
		if (error != nil)
		{
			NSLog(@"Encountered error when reading memory from debugger:");
			NSLog(@"%@", error);
			return;
		}
		if (ZGIsValidNumber(calculatedMemoryAddressExpression))
		{
			calculatedMemoryAddress = ZGMemoryAddressFromExpression(calculatedMemoryAddressExpression);
			
			self.lastSearchInfo = @{userInput : @(calculatedMemoryAddress)};
		}
	}
	
	BOOL shouldUseFirstInstruction = NO;
	
	ZGMachBinaryInfo *firstMachBinaryInfo = [self.currentProcess.mainMachBinary machBinaryInfoInProcess:self.currentProcess];
	NSRange machInstructionRange = NSMakeRange(firstMachBinaryInfo.firstInstructionAddress, firstMachBinaryInfo.textSegmentRange.length - (firstMachBinaryInfo.firstInstructionAddress - firstMachBinaryInfo.textSegmentRange.location));
	
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
		
		return;
	}
	
	NSArray *memoryRegions = [ZGRegion regionsFromProcessTaskRecursively:self.currentProcess.processTask];
	if (memoryRegions.count == 0)
	{
		cleanupOnFailure();
		return;
	}
	
	ZGRegion *chosenRegion = nil;
	for (ZGRegion *region in memoryRegions)
	{
		if ((region.protection & VM_PROT_READ) && (calculatedMemoryAddress >= region.address && calculatedMemoryAddress < region.address + region.size))
		{
			chosenRegion = region;
			break;
		}
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
		NSArray *machBinaries = [ZGMachBinary machBinariesInProcess:self.currentProcess];
		ZGMachBinary *machBinary = [ZGMachBinary machBinaryNearestToAddress:calculatedMemoryAddress fromMachBinaries:machBinaries];
		ZGMachBinaryInfo *machBinaryInfo = [machBinary machBinaryInfoInProcess:self.currentProcess];
		NSRange instructionRange = NSMakeRange(machBinaryInfo.firstInstructionAddress, machBinaryInfo.textSegmentRange.length - (machBinaryInfo.firstInstructionAddress - machBinaryInfo.textSegmentRange.location));
		
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
		mappedFilePath = [self.currentProcess.mainMachBinary filePathInProcess:self.currentProcess];
		baseAddress = self.currentProcess.mainMachBinary.headerAddress;
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
		lowBoundAddress = [[self class] findInstructionBeforeAddress:lowBoundAddress inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints].variable.address;
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
		highBoundAddress = [[self class] findInstructionBeforeAddress:highBoundAddress inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints].variable.address;
		if (highBoundAddress <= chosenRegion.address || highBoundAddress > chosenRegion.address + chosenRegion.size)
		{
			highBoundAddress = chosenRegion.address + chosenRegion.size;
		}
	}
	
	[self.undoManager removeAllActions];
	[self updateDisassemblerWithAddress:lowBoundAddress size:highBoundAddress - lowBoundAddress selectionAddress:calculatedMemoryAddress];
}

#pragma mark Useful methods for the world

- (NSIndexSet *)selectedInstructionIndexes
{
	NSIndexSet *tableIndexSet = self.instructionsTableView.selectedRowIndexes;
	NSInteger clickedRow = self.instructionsTableView.clickedRow;
	
	return (clickedRow != -1 && ![tableIndexSet containsIndex:clickedRow]) ? [NSIndexSet indexSetWithIndex:clickedRow] : tableIndexSet;
}

- (NSArray *)selectedInstructions
{
	return [self.instructions objectsAtIndexes:[self selectedInstructionIndexes]];
}

- (void)jumpToMemoryAddress:(ZGMemoryAddress)address
{
	[self jumpToMemoryAddress:address inProcess:self.currentProcess];
}

- (void)jumpToMemoryAddress:(ZGMemoryAddress)address inProcess:(ZGProcess *)requestedProcess
{
	NSMenuItem *targetMenuItem = nil;
	for (NSMenuItem *menuItem in self.runningApplicationsPopUpButton.menu.itemArray)
	{
		ZGProcess *process = menuItem.representedObject;
		if ([process processID] == requestedProcess.processID)
		{
			targetMenuItem = menuItem;
			break;
		}
	}
	
	if (targetMenuItem != nil)
	{
		self.addressTextField.stringValue = [NSString stringWithFormat:@"0x%llX", address];
		
		if ([targetMenuItem.representedObject processID] != self.currentProcess.processID)
		{
			[self.runningApplicationsPopUpButton selectItem:targetMenuItem];
			
			self.instructions = @[];
			[self.instructionsTableView reloadData];
			
			[self switchProcessMenuItemAndSelectAddress:address];
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
	return self.currentBreakPoint != nil && !self.disassembling;
}

- (BOOL)canStepOverExecution
{
	if (!self.currentBreakPoint || self.disassembling)
	{
		return NO;
	}
	
	ZGInstruction *currentInstruction = [[self class] findInstructionBeforeAddress:self.registersViewController.instructionPointer + 1 inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints];
	if (!currentInstruction)
	{
		return NO;
	}
	
	if ([ZGDisassemblerObject isCallMnemonic:currentInstruction.mnemonic])
	{
		ZGInstruction *nextInstruction = [[self class] findInstructionBeforeAddress:currentInstruction.variable.address + currentInstruction.variable.size + 1 inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints];
		if (!nextInstruction)
		{
			return NO;
		}
	}
	
	return YES;
}

- (BOOL)canStepOutOfExecution
{
	if (!self.currentBreakPoint || self.disassembling)
	{
		return NO;
	}
	
	if (self.backtraceViewController.backtrace.instructions.count <= 1 || self.backtraceViewController.backtrace.basePointers.count <= 1)
	{
		return NO;
	}
	
	ZGInstruction *outterInstruction = [self.backtraceViewController.backtrace.instructions objectAtIndex:1];
	ZGInstruction *returnInstruction = [[self class] findInstructionBeforeAddress:outterInstruction.variable.address + outterInstruction.variable.size + 1 inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints];
	
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
		
		if (self.selectedInstructions.count == 0 || !self.currentProcess.valid || self.instructionsTableView.editedRow != -1 || self.disassembling)
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
		if (self.disassembling || self.selectedInstructions.count == 0)
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
		if (self.disassembling)
		{
			return NO;
		}
		
		if (![self hasBreakPoint])
		{
			return NO;
		}
	}
	else if (userInterfaceItem.action == @selector(jump:))
	{
		if (self.disassembling || !self.currentBreakPoint || self.selectedInstructions.count != 1)
		{
			return NO;
		}
	}
	else if (userInterfaceItem.action == @selector(jumpToOperandOffset:))
	{
		if (self.disassembling || !self.currentProcess.valid)
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
	NSMutableArray *variablesToAnnotate = [NSMutableArray array];
	for (ZGInstruction *instruction in instructions)
	{
		if (!instruction.variable.usesDynamicAddress)
		{
			[variablesToAnnotate addObject:instruction.variable];
		}
	}
	
	[ZGVariableController annotateVariables:variablesToAnnotate process:self.currentProcess];
	
	for (ZGInstruction *instruction in instructions)
	{
		if ([instruction.variable.description length] == 0)
		{
			instruction.variable.description = instruction.text;
		}
		else if ([variablesToAnnotate containsObject:instruction.variable])
		{
			NSMutableAttributedString *newDescription = [[NSMutableAttributedString alloc] initWithString:[instruction.text stringByAppendingString:@"\n"]];
			[newDescription appendAttributedString:instruction.variable.description];
			instruction.variable.description = newDescription;
		}
	}
}

- (IBAction)copy:(id)sender
{
	NSArray *selectedInstructions = (self.window.firstResponder == self.backtraceViewController.tableView) ? self.backtraceViewController.selectedInstructions : self.selectedInstructions;
	
	if (self.window.firstResponder == self.instructionsTableView)
	{
		[self annotateInstructions:selectedInstructions];
	}
	
	NSMutableArray *descriptionComponents = [[NSMutableArray alloc] init];
	NSMutableArray *variablesArray = [[NSMutableArray alloc] init];
	
	for (ZGInstruction *instruction in selectedInstructions)
	{
		[descriptionComponents addObject:[@[instruction.variable.addressStringValue, instruction.text, instruction.variable.stringValue] componentsJoinedByString:@"\t"]];
		[variablesArray addObject:instruction.variable];
	}
	
	[[NSPasteboard generalPasteboard] declareTypes:@[NSStringPboardType, ZGVariablePboardType] owner:self];
	[[NSPasteboard generalPasteboard] setString:[descriptionComponents componentsJoinedByString:@"\n"] forType:NSStringPboardType];
	[[NSPasteboard generalPasteboard] setData:[NSKeyedArchiver archivedDataWithRootObject:variablesArray] forType:ZGVariablePboardType];
}

- (IBAction)copyAddress:(id)sender
{
	NSArray *selectedInstructions = (self.window.firstResponder == self.backtraceViewController.tableView) ? self.backtraceViewController.selectedInstructions : self.selectedInstructions;
	ZGInstruction *selectedInstruction = [selectedInstructions objectAtIndex:0];
	[[NSPasteboard generalPasteboard] declareTypes:@[NSStringPboardType] owner:self];
	[[NSPasteboard generalPasteboard] setString:selectedInstruction.variable.addressStringValue	forType:NSStringPboardType];
}

- (void)scrollAndSelectRow:(NSUInteger)selectionRow
{
	// Scroll such that the selected row is centered
	[self.instructionsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:selectionRow] byExtendingSelection:NO];
	NSRange visibleRowsRange = [self.instructionsTableView rowsInRect:self.instructionsTableView.visibleRect];
	if (visibleRowsRange.location + visibleRowsRange.length / 2 < selectionRow)
	{
		[self.instructionsTableView scrollRowToVisible:MIN(selectionRow + visibleRowsRange.length / 2, self.instructions.count-1)];
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
			[self.instructionsTableView scrollRowToVisible:selectionRow - visibleRowsRange.length / 2];
		}
	}
}

#pragma mark TableView Methods

- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard
{
	NSArray *instructions = [self.instructions objectsAtIndexes:rowIndexes];
	[self annotateInstructions:instructions];
	
	return [pboard setData:[NSKeyedArchiver archivedDataWithRootObject:[instructions valueForKey:@"variable"]] forType:ZGVariablePboardType];
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	[self updateStatusBar];
}

- (BOOL)isBreakPointAtInstruction:(ZGInstruction *)instruction
{
	BOOL answer = NO;
	
	for (ZGBreakPoint *breakPoint in self.breakPointController.breakPoints)
	{
		if (breakPoint.type == ZGBreakPointInstruction && breakPoint.task == self.currentProcess.processTask && breakPoint.variable.address == instruction.variable.address && !breakPoint.hidden && breakPoint.delegate == self)
		{
			answer = YES;
			break;
		}
	}
	
	return answer;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return self.instructions.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	id result = nil;
	if (rowIndex >= 0 && (NSUInteger)rowIndex < self.instructions.count)
	{
		ZGInstruction *instruction = [self.instructions objectAtIndex:rowIndex];
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

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
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
			ZGInstruction *instruction = [self.instructions objectAtIndex:rowIndex];
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

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if ([tableColumn.identifier isEqualToString:@"address"] && rowIndex >= 0 && (NSUInteger)rowIndex < self.instructions.count)
	{
		ZGInstruction *instruction = [self.instructions objectAtIndex:rowIndex];
		BOOL isInstructionBreakPoint = (self.currentBreakPoint && self.registersViewController.instructionPointer == instruction.variable.address);
		
		[cell setTextColor:isInstructionBreakPoint ? NSColor.redColor : NSColor.textColor];
	}
}

- (NSString *)tableView:(NSTableView *)tableView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row mouseLocation:(NSPoint)mouseLocation
{
	NSString *toolTip = nil;
	
	if (row >= 0 && (NSUInteger)row < self.instructions.count)
	{
		ZGInstruction *instruction = [self.instructions objectAtIndex:row];
		
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

#define ASSEMBLER_ERROR_DOMAIN @"Assembling Failed"
+ (NSData *)assembleInstructionText:(NSString *)instructionText atInstructionPointer:(ZGMemoryAddress)instructionPointer usingArchitectureBits:(ZGMemorySize)numberOfBits error:(NSError * __autoreleasing *)error
{
	NSData *data = [NSData data];
	NSString *outputFileTemplate = [NSTemporaryDirectory() stringByAppendingPathComponent:@"assembler_output.XXXXXX"];
	const char *tempFileTemplateCString = [outputFileTemplate fileSystemRepresentation];
	char *tempFileNameCString = malloc(strlen(tempFileTemplateCString) + 1);
	strcpy(tempFileNameCString, tempFileTemplateCString);
	int fileDescriptor = mkstemp(tempFileNameCString);
	
	if (fileDescriptor != -1)
	{
		close(fileDescriptor);
		
		NSFileManager *fileManager = [[NSFileManager alloc] init];
		NSString *outputFilePath = [fileManager stringWithFileSystemRepresentation:tempFileNameCString length:strlen(tempFileNameCString)];
		
		NSTask *task = [[NSTask alloc] init];
		[task setLaunchPath:[[NSBundle mainBundle] pathForResource:@"yasm" ofType:nil]];
		[task setArguments:@[@"--arch=x86", @"-", @"-o", outputFilePath]];
		
		NSPipe *inputPipe = [NSPipe pipe];
		[task setStandardInput:inputPipe];
		
		NSPipe *errorPipe = [NSPipe pipe];
		[task setStandardError:errorPipe];
		
		BOOL failedToLaunchTask = NO;
		
		@try
		{
			[task launch];
		}
		@catch (NSException *exception)
		{
			failedToLaunchTask = YES;
			if (error != nil)
			{
				*error = [NSError errorWithDomain:ASSEMBLER_ERROR_DOMAIN code:kCFStreamErrorDomainCustom userInfo:@{@"description" : [NSString stringWithFormat:@"yasm task failed to launch: Name: %@, Reason: %@", exception.name, exception.reason], @"reason" : exception.reason}];
			}
		}
		
		if (!failedToLaunchTask)
		{
			// yasm likes to be fed in an aligned instruction pointer for its org specifier, so we'll comply with that
			ZGMemoryAddress alignedInstructionPointer = instructionPointer - (instructionPointer % 4);
			NSUInteger numberOfNoppedInstructions = instructionPointer - alignedInstructionPointer;
			
			// clever way of @"nop" * numberOfNoppedInstructions, if it existed
			NSString *nopLine = @"nop\n";
			NSString *nopsString = [@"" stringByPaddingToLength:numberOfNoppedInstructions * nopLine.length withString:nopLine startingAtIndex:0];
			
			NSData *inputData = [[NSString stringWithFormat:@"BITS %lld\norg %lld\n%@%@\n", numberOfBits, alignedInstructionPointer, nopsString, instructionText] dataUsingEncoding:NSUTF8StringEncoding];
			
			[[inputPipe fileHandleForWriting] writeData:inputData];
			[[inputPipe fileHandleForWriting] closeFile];
			
			[task waitUntilExit];
			
			if ([task terminationStatus] == EXIT_SUCCESS)
			{
				NSData *tempData = [NSData dataWithContentsOfFile:outputFilePath];
				
				if (tempData.length <= numberOfNoppedInstructions)
				{
					if (error != nil)
					{
						*error = [NSError errorWithDomain:ASSEMBLER_ERROR_DOMAIN code:kCFStreamErrorDomainCustom userInfo:@{@"reason" : @"nothing was assembled (0 bytes)."}];
					}
				}
				else
				{
					data = [NSData dataWithBytes:tempData.bytes + numberOfNoppedInstructions length:tempData.length - numberOfNoppedInstructions];
				}
			}
			else
			{
				NSData *errorData = [[errorPipe fileHandleForReading] readDataToEndOfFile];
				if (errorData != nil && error != nil)
				{
					NSString *errorString = [[[[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding] componentsSeparatedByString:@"\n"] objectAtIndex:0];
					*error = [NSError errorWithDomain:ASSEMBLER_ERROR_DOMAIN code:kCFStreamErrorDomainCustom userInfo:@{@"reason" : errorString}];
				}
			}
			
			if ([fileManager fileExistsAtPath:outputFilePath])
			{
				[fileManager removeItemAtPath:outputFilePath error:NULL];
			}
		}
	}
	else if (error != nil)
	{
		*error = [NSError errorWithDomain:ASSEMBLER_ERROR_DOMAIN code:kCFStreamErrorDomainCustom userInfo:@{@"reason" : [NSString stringWithFormat:@"failed to open file descriptor on %s.", tempFileNameCString]}];
	}
	
	free(tempFileNameCString);
	
	return data;
}

- (void)writeInstructionText:(NSString *)instructionText atInstructionFromIndex:(NSUInteger)instructionIndex
{
	NSError *error = nil;
	ZGInstruction *firstInstruction = [self.instructions objectAtIndex:instructionIndex];
	NSData *data = [[self class] assembleInstructionText:instructionText atInstructionPointer:firstInstruction.variable.address usingArchitectureBits:self.currentProcess.pointerSize * 8 error:&error];
	if (data.length == 0)
	{
		if (error != nil)
		{
			NSLog(@"%@", error);
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
				const int8_t nopValue = NOP_VALUE;
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
						*(char *)(oldValue + writeIndex) = *(char *)(currentInstruction.variable.value + valueIndex);
					}
					
					instructionIndex++;
				}
				
				if (writeIndex >= newWriteSize)
				{
					ZGVariable *newVariable = [[ZGVariable alloc] initWithValue:newWriteValue size:newWriteSize address:instruction.variable.address type:ZGByteArray qualifier:ZGSigned pointerSize:self.currentProcess.pointerSize];
					
					ZGVariable *oldVariable = [[ZGVariable alloc] initWithValue:oldValue size:newWriteSize address:instruction.variable.address type:ZGByteArray qualifier:ZGSigned pointerSize:self.currentProcess.pointerSize];
					
					[[self class] replaceInstructions:@[instruction] fromOldStringValues:@[oldVariable.stringValue] toNewStringValues:@[newVariable.stringValue] inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints undoManager:self.undoManager actionName:@"Instruction Change"];
				}
				
				free(oldValue);
			}
		}
		
		free(newWriteValue);
	}
}

+ (void)
	replaceInstructions:(NSArray *)instructions
	fromOldStringValues:(NSArray *)oldStringValues
	toNewStringValues:(NSArray *)newStringValues
	inProcess:(ZGProcess *)process
	withBreakPoints:(NSArray *)breakPoints
	undoManager:(NSUndoManager *)undoManager
	actionName:(NSString *)actionName
{
	[self replaceInstructions:instructions fromOldStringValues:oldStringValues toNewStringValues:newStringValues processTask:process.processTask is64Bit:process.is64Bit breakPoints:breakPoints undoManager:undoManager actionName:actionName];
}

+ (void)
	replaceInstructions:(NSArray *)instructions
	fromOldStringValues:(NSArray *)oldStringValues
	toNewStringValues:(NSArray *)newStringValues
	processTask:(ZGMemoryMap)processTask
	is64Bit:(BOOL)is64Bit
	breakPoints:(NSArray *)breakPoints
	undoManager:(NSUndoManager *)undoManager
	actionName:(NSString *)actionName
{
	for (NSUInteger index = 0; index < instructions.count; index++)
	{
		ZGInstruction *instruction = [instructions objectAtIndex:index];
		[self writeStringValue:[newStringValues objectAtIndex:index] atAddress:instruction.variable.address processTask:processTask is64Bit:is64Bit breakPoints:breakPoints];
	}
	
	if (undoManager != nil)
	{
		if (actionName != nil)
		{
			[undoManager setActionName:[actionName stringByAppendingFormat:@"%@", instructions.count == 1 ? @"" : @"s"]];
		}
		
		[[undoManager prepareWithInvocationTarget:self] replaceInstructions:instructions fromOldStringValues:newStringValues toNewStringValues:oldStringValues processTask:processTask is64Bit:is64Bit breakPoints:breakPoints undoManager:undoManager actionName:actionName];
	}
}

+ (void)writeStringValue:(NSString *)stringValue atAddress:(ZGMemoryAddress)address inProcess:(ZGProcess *)process breakPoints:(NSArray *)breakPoints
{
	[self writeStringValue:stringValue atAddress:address processTask:process.processTask is64Bit:process.is64Bit breakPoints:breakPoints];
}

+ (void)writeStringValue:(NSString *)stringValue atAddress:(ZGMemoryAddress)address processTask:(ZGMemoryMap)processTask is64Bit:(BOOL)is64Bit breakPoints:(NSArray *)breakPoints
{
	ZGMemorySize newSize = 0;
	void *newValue = ZGValueFromString(is64Bit, stringValue, ZGByteArray, &newSize);
	
	[self writeData:[NSData dataWithBytesNoCopy:newValue length:newSize] atAddress:address processTask:processTask is64Bit:is64Bit breakPoints:breakPoints];
}

+ (BOOL)writeData:(NSData *)data atAddress:(ZGMemoryAddress)address processTask:(ZGMemoryMap)processTask is64Bit:(BOOL)is64Bit breakPoints:(NSArray *)breakPoints
{
	BOOL success = YES;
	pid_t processID = 0;
	if (!ZGPIDForTask(processTask, &processID))
	{
		NSLog(@"Error in writeStringValue: method for retrieving process ID");
		success = NO;
	}
	else
	{
		ZGBreakPoint *targetBreakPoint = nil;
		for (ZGBreakPoint *breakPoint in breakPoints)
		{
			if (breakPoint.process.processID == processID && breakPoint.variable.address >= address && breakPoint.variable.address < address + data.length)
			{
				targetBreakPoint = breakPoint;
				break;
			}
		}
		
		if (targetBreakPoint == nil)
		{
			if (!ZGWriteBytesIgnoringProtection(processTask, address, data.bytes, data.length))
			{
				success = NO;
			}
		}
		else
		{
			if (targetBreakPoint.variable.address - address > 0)
			{
				if (!ZGWriteBytesIgnoringProtection(processTask, address, data.bytes, targetBreakPoint.variable.address - address))
				{
					success = NO;
				}
			}
			
			if (address + data.length - targetBreakPoint.variable.address - 1 > 0)
			{
				if (!ZGWriteBytesIgnoringProtection(processTask, targetBreakPoint.variable.address + 1, data.bytes + (targetBreakPoint.variable.address + 1 - address), address + data.length - targetBreakPoint.variable.address - 1))
				{
					success = NO;
				}
			}
			
			*(uint8_t *)targetBreakPoint.variable.value = *(uint8_t *)(data.bytes + targetBreakPoint.variable.address - address);
		}
	}
	
	return success;
}

+ (void)nopInstructions:(NSArray *)instructions inProcess:(ZGProcess *)process withBreakPoints:(NSArray *)breakPoints undoManager:(NSUndoManager *)undoManager actionName:(NSString *)actionName
{
	[self nopInstructions:instructions processTask:process.processTask is64Bit:process.is64Bit breakPoints:breakPoints undoManager:undoManager actionName:actionName];
}

+ (void)nopInstructions:(NSArray *)instructions processTask:(ZGMemoryMap)processTask is64Bit:(BOOL)is64Bit breakPoints:(NSArray *)breakPoints undoManager:(NSUndoManager *)undoManager actionName:(NSString *)actionName
{
	NSMutableArray *newStringValues = [[NSMutableArray alloc] init];
	NSMutableArray *oldStringValues = [[NSMutableArray alloc] init];
	
	for (NSUInteger instructionIndex = 0; instructionIndex < instructions.count; instructionIndex++)
	{
		ZGInstruction *instruction = [instructions objectAtIndex:instructionIndex];
		[oldStringValues addObject:instruction.variable.stringValue];
		
		NSMutableArray *nopComponents = [[NSMutableArray alloc] init];
		for (NSUInteger nopIndex = 0; nopIndex < instruction.variable.size; nopIndex++)
		{
			[nopComponents addObject:@"90"];
		}
		
		[newStringValues addObject:[nopComponents componentsJoinedByString:@" "]];
	}
	
	[self replaceInstructions:instructions fromOldStringValues:oldStringValues toNewStringValues:newStringValues processTask:processTask is64Bit:is64Bit breakPoints:breakPoints undoManager:undoManager actionName:actionName];
}

- (IBAction)nopVariables:(id)sender
{
	[[self class] nopInstructions:[self selectedInstructions] inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints undoManager:self.undoManager actionName:@"NOP Change"];
}

#define INJECT_ERROR_DOMAIN @"INJECT_CODE_FAILED"
+ (BOOL)
	injectCode:(NSData *)codeData
	intoAddress:(ZGMemoryAddress)allocatedAddress
	hookingIntoOriginalInstructions:(NSArray *)hookedInstructions
	process:(ZGProcess *)process
	breakPoints:(NSArray *)breakPoints
	undoManager:(NSUndoManager *)undoManager
	error:(NSError * __autoreleasing *)error
{
	BOOL success = NO;
	
	if (hookedInstructions != nil)
	{
		NSMutableData *newInstructionsData = [NSMutableData dataWithData:codeData];
		
		ZGSuspendTask(process.processTask);
		
		void *nopBuffer = malloc(codeData.length);
		memset(nopBuffer, NOP_VALUE, codeData.length);
		
		if (!ZGWriteBytesIgnoringProtection(process.processTask, allocatedAddress, nopBuffer, codeData.length))
		{
			NSLog(@"Error: Failed to write nop buffer..");
			if (error != nil)
			{
				*error = [NSError errorWithDomain:INJECT_ERROR_DOMAIN code:kCFStreamErrorDomainCustom userInfo:@{@"reason" : @"failed to NOP current instructions"}];
			}
		}
		else
		{
			if (!ZGProtect(process.processTask, allocatedAddress, codeData.length, VM_PROT_READ | VM_PROT_EXECUTE))
			{
				NSLog(@"Error: Failed to protect memory..");
				if (error != nil)
				{
					*error = [NSError errorWithDomain:INJECT_ERROR_DOMAIN code:kCFStreamErrorDomainCustom userInfo:@{@"reason" : @"failed to change memory protection on new instructions"}];
				}
			}
			else
			{
				[undoManager setActionName:@"Inject code"];
				
				[self nopInstructions:hookedInstructions processTask:process.processTask is64Bit:process.pointerSize == sizeof(int64_t) breakPoints:breakPoints undoManager:undoManager actionName:nil];
				
				ZGMemorySize hookedInstructionsLength = 0;
				for (ZGInstruction *instruction in hookedInstructions)
				{
					hookedInstructionsLength += instruction.variable.size;
				}
				ZGInstruction *firstInstruction = [hookedInstructions objectAtIndex:0];
				
				NSData *jumpToIslandData = [[self class] assembleInstructionText:[NSString stringWithFormat:@"jmp %lld", allocatedAddress] atInstructionPointer:firstInstruction.variable.address usingArchitectureBits:process.pointerSize*8 error:error];
				
				if (jumpToIslandData.length > 0)
				{
					ZGVariable *variable = [[ZGVariable alloc] initWithValue:(void *)jumpToIslandData.bytes size:jumpToIslandData.length address:firstInstruction.variable.address type:ZGByteArray qualifier:0 pointerSize:process.pointerSize];
					
					[self replaceInstructions:@[firstInstruction] fromOldStringValues:@[firstInstruction.variable.stringValue] toNewStringValues:@[variable.stringValue] processTask:process.processTask is64Bit:(process.pointerSize == sizeof(int64_t)) breakPoints:breakPoints undoManager:undoManager actionName:nil];
					
					NSData *jumpFromIslandData = [[self class] assembleInstructionText:[NSString stringWithFormat:@"jmp %lld", firstInstruction.variable.address + hookedInstructionsLength] atInstructionPointer:allocatedAddress + newInstructionsData.length usingArchitectureBits:process.pointerSize*8 error:error];
					if (jumpFromIslandData.length > 0)
					{
						[newInstructionsData appendData:jumpFromIslandData];
						
						ZGWriteBytesIgnoringProtection(process.processTask, allocatedAddress, newInstructionsData.bytes, newInstructionsData.length);
						
						success = YES;
					}
				}
			}
		}
		
		free(nopBuffer);
		
		ZGResumeTask(process.processTask);
	}
	
	return success;
}

+ (NSArray *)instructionsBeforeHookingIntoAddress:(ZGMemoryAddress)address injectingIntoDestination:(ZGMemoryAddress)destinationAddress inProcess:(ZGProcess *)process withBreakPoints:(NSArray *)breakPoints
{
	NSMutableArray *instructions = nil;
	
	if (process.pointerSize == sizeof(ZG32BitMemoryAddress) || !((destinationAddress > address && destinationAddress - address > INT_MAX) || (address > destinationAddress && address - destinationAddress > INT_MAX)))
	{
		instructions = [[NSMutableArray alloc] init];
		int consumedLength = JUMP_REL32_INSTRUCTION_LENGTH;
		while (consumedLength > 0)
		{
			ZGInstruction *newInstruction = [self findInstructionBeforeAddress:address+1 inProcess:process withBreakPoints:breakPoints];
			if (newInstruction == nil)
			{
				instructions = nil;
				break;
			}
			[instructions addObject:newInstruction];
			consumedLength -= newInstruction.variable.size;
			address += newInstruction.variable.size;
		}
	}
	
	return [instructions copy];
}

- (IBAction)requestCodeInjection:(id)sender
{
	ZGMemoryAddress allocatedAddress = 0;
	ZGMemorySize numberOfAllocatedBytes = NSPageSize(); // sane default
	ZGPageSize(self.currentProcess.processTask, &numberOfAllocatedBytes);
	
	if (ZGAllocateMemory(self.currentProcess.processTask, &allocatedAddress, numberOfAllocatedBytes))
	{
		void *nopBuffer = malloc(numberOfAllocatedBytes);
		memset(nopBuffer, NOP_VALUE, numberOfAllocatedBytes);
		if (!ZGWriteBytesIgnoringProtection(self.currentProcess.processTask, allocatedAddress, nopBuffer, numberOfAllocatedBytes))
		{
			NSLog(@"Failed to nop allocated memory for code injection");
		}
		free(nopBuffer);
		
		ZGInstruction *firstInstruction = [[self selectedInstructions] objectAtIndex:0];
		NSArray *instructions = [[self class] instructionsBeforeHookingIntoAddress:firstInstruction.variable.address injectingIntoDestination:allocatedAddress inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints];
		
		if (instructions != nil)
		{
			NSMutableString *suggestedCode = [NSMutableString stringWithFormat:@"; Injected code will be allocated at 0x%llX\n", allocatedAddress];
			for (ZGInstruction *instruction in instructions)
			{
				NSMutableString *instructionText = [NSMutableString stringWithString:[instruction text]];
				if (self.currentProcess.is64Bit && [instructionText rangeOfString:@"rip"].location != NSNotFound)
				{
					NSString *ripReplacement = nil;
					if (allocatedAddress > firstInstruction.variable.address)
					{
						ripReplacement = [NSString stringWithFormat:@"rip-0x%llX", allocatedAddress + (instruction.variable.address - firstInstruction.variable.address) - instruction.variable.address];
					}
					else
					{
						ripReplacement = [NSString stringWithFormat:@"rip+0x%llX", instruction.variable.address + (instruction.variable.address - firstInstruction.variable.address) - allocatedAddress];
					}
					
					[instructionText replaceOccurrencesOfString:@"rip" withString:ripReplacement options:NSLiteralSearch range:NSMakeRange(0, instructionText.length)];
				}
				[suggestedCode appendString:instructionText];
				[suggestedCode appendString:@"\n"];
			}
			
			if (self.codeInjectionController == nil)
			{
				self.codeInjectionController = [[ZGCodeInjectionWindowController alloc] init];
			}
			
			[self.codeInjectionController setSuggestedCode:suggestedCode];
			[self.codeInjectionController attachToWindow:self.window completionHandler:^(NSString *injectedCodeString, BOOL canceled, BOOL *succeeded) {
				if (!canceled)
				{
					NSError *error = nil;
					NSData *injectedCode = [[self class] assembleInstructionText:injectedCodeString atInstructionPointer:allocatedAddress usingArchitectureBits:self.currentProcess.pointerSize*8 error:&error];
					
					if (injectedCode.length == 0 || error != nil || ![[self class] injectCode:injectedCode intoAddress:allocatedAddress hookingIntoOriginalInstructions:instructions process:self.currentProcess breakPoints:self.breakPointController.breakPoints undoManager:self.undoManager error:&error])
					{
						NSLog(@"Error while injecting code");
						NSLog(@"%@", error);
						
						if (!ZGDeallocateMemory(self.currentProcess.processTask, &allocatedAddress, numberOfAllocatedBytes))
						{
							NSLog(@"Error: Failed to deallocate VM memory after failing to inject code..");
						}
						
						*succeeded = NO;
						NSRunAlertPanel(@"Failed to Inject Code", @"An error occured assembling the new code: %@", @"OK", nil, nil, [error.userInfo objectForKey:@"reason"]);
					}
				}
				else
				{
					if (!ZGDeallocateMemory(self.currentProcess.processTask, &allocatedAddress, numberOfAllocatedBytes))
					{
						NSLog(@"Error: Failed to deallocate VM memory after canceling from injecting code..");
					}
				}
			}];
		}
		else
		{
			if (!ZGDeallocateMemory(self.currentProcess.processTask, &allocatedAddress, numberOfAllocatedBytes))
			{
				NSLog(@"Error: Failed to deallocate VM memory after failing to fetch enough instructions..");
			}
			
			NSLog(@"Error: not enough instructions to override, or allocated memory address was too far away. Source: 0x%llX, destination: 0x%llX", firstInstruction.variable.address, allocatedAddress);
			NSRunAlertPanel(@"Failed to Inject Code", @"There was not enough space to override this instruction, or the newly allocated address was too far away", @"OK", nil, nil);
		}
	}
	else
	{
		NSLog(@"Failed to allocate code for code injection");
		NSRunAlertPanel(@"Failed to Allocate Memory", @"An error occured trying to allocate new memory into the process", @"OK", nil, nil);
	}
}

#pragma mark Break Points

- (BOOL)hasBreakPoint
{
	BOOL hasBreakPoint = NO;
	for (ZGBreakPoint *breakPoint in self.breakPointController.breakPoints)
	{
		if (breakPoint.delegate == self)
		{
			hasBreakPoint = YES;
			break;
		}
	}
	return hasBreakPoint;
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
			
			addedAtLeastOneBreakPoint = [self.breakPointController addBreakPointOnInstruction:instruction inProcess:self.currentProcess condition:compiledCondition delegate:self] || addedAtLeastOneBreakPoint;
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

- (IBAction)toggleBreakPoints:(id)sender
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

- (IBAction)removeAllBreakPoints:(id)sender
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
		if (instruction.variable.address < targetAddress)
		{
			return NSOrderedAscending;
		}
		else if (instruction.variable.address > targetAddress)
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
	if (self.currentBreakPoint != nil && !self.disassembling)
	{
		ZGMemoryAddress currentAddress = self.registersViewController.instructionPointer;
		[self.registersViewController changeInstructionPointer:newAddress];
		[[self.undoManager prepareWithInvocationTarget:self] moveInstructionPointerToAddress:currentAddress];
		[self.undoManager setActionName:@"Jump"];
	}
}

- (IBAction)jump:(id)sender
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
	ZGBacktrace *backtrace = [ZGBacktrace backtraceWithBasePointer:self.registersViewController.basePointer instructionPointer:self.registersViewController.instructionPointer process:self.currentProcess breakPoints:self.breakPointController.breakPoints];
	
	if ([self shouldUpdateSymbolsForInstructions:backtrace.instructions])
	{
		[self updateSymbolsForInstructions:backtrace.instructions];
	}
	
	for (ZGInstruction *instruction in backtrace.instructions)
	{
		if (instruction.symbols.length == 0)
		{
			instruction.symbols = @""; // in case symbols is nil
			instruction.variable.description = instruction.variable.addressStringValue;
		}
		else
		{
			instruction.variable.description = instruction.symbols;
		}
	}
	
	self.backtraceViewController.backtrace = backtrace;
}

- (void)backtraceSelectionChangedToAddress:(ZGMemoryAddress)address
{
	[self jumpToMemoryAddress:address inProcess:self.currentProcess];
}

- (BOOL)backtraceSelectionShouldChange
{
	return !self.disassembling;
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
			[self.registersViewController addObserver:self forKeyPath:@"instructionPointer" options:NSKeyValueObservingOptionNew context:NULL];
			
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

- (IBAction)continueExecution:(id)sender
{
	[self continueFromBreakPoint:self.currentBreakPoint];
}

- (IBAction)stepInto:(id)sender
{
	[self.breakPointController addSingleStepBreakPointFromBreakPoint:self.currentBreakPoint];
	[self resumeBreakPoint:self.currentBreakPoint];
}

- (IBAction)stepOver:(id)sender
{
	ZGInstruction *currentInstruction = [[self class] findInstructionBeforeAddress:self.registersViewController.instructionPointer + 1 inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints];
	if ([ZGDisassemblerObject isCallMnemonic:currentInstruction.mnemonic])
	{
		ZGInstruction *nextInstruction = [[self class] findInstructionBeforeAddress:currentInstruction.variable.address + currentInstruction.variable.size + 1 inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints];
		
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

- (IBAction)stepOut:(id)sender
{
	ZGInstruction *outterInstruction = [self.backtraceViewController.backtrace.instructions objectAtIndex:1];
	ZGInstruction *returnInstruction = [[self class] findInstructionBeforeAddress:outterInstruction.variable.address + outterInstruction.variable.size + 1 inProcess:self.currentProcess withBreakPoints:self.breakPointController.breakPoints];
	
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

- (void)applicationWillTerminate:(NSNotification *)notification
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
	BOOL foundProcess = NO;
	for (ZGBreakPoint *breakPoint in self.haltedBreakPoints)
	{
		if (breakPoint.process.processID == processIdentifier)
		{
			foundProcess = YES;
			break;
		}
	}
	return foundProcess;
}

#pragma mark Breakpoint Conditions

- (IBAction)showBreakPointCondition:(id)sender
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
	
	NSRect cellFrame = [self.instructionsTableView frameOfCellAtColumn:0 row:selectedRow];
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
	for (ZGBreakPointCondition *breakPointCondition in self.breakPointConditions)
	{
		if ([breakPointCondition.internalProcessName isEqualToString:self.currentProcess.internalName] && breakPointCondition.address == address)
		{
			oldCondition = breakPointCondition.condition;
			breakPointCondition.condition = strippedCondition;
			breakPointCondition.compiledCondition = newCompiledCondition;
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

- (IBAction)showMemoryViewer:(id)sender
{
	NSArray *selectedInstructions = (self.window.firstResponder == self.backtraceViewController.tableView) ? self.backtraceViewController.selectedInstructions : self.selectedInstructions;
	ZGInstruction *selectedInstruction = [selectedInstructions objectAtIndex:0];
	
	[self.memoryViewer jumpToMemoryAddress:selectedInstruction.variable.address withSelectionLength:selectedInstruction.variable.size inProcess:self.currentProcess];
}

@end
