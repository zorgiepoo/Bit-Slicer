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

#import "ZGDisassemblerController.h"
#import "ZGAppController.h"
#import "ZGProcess.h"
#import "ZGCalculator.h"
#import "ZGUtilities.h"
#import "ZGProcessList.h"
#import "ZGRunningProcess.h"
#import "ZGInstruction.h"
#import "ZGBreakPoint.h"
#import "ZGBreakPointController.h"
#import "ZGDisassemblerObject.h"
#import "ZGUtilities.h"
#import "ZGRegistersController.h"
#import "ZGPreferencesController.h"
#import "ZGBacktraceController.h"

@interface ZGDisassemblerController ()

@property (assign) IBOutlet NSPopUpButton *runningApplicationsPopUpButton;
@property (assign) IBOutlet NSTextField *addressTextField;
@property (assign) IBOutlet NSTableView *instructionsTableView;
@property (assign) IBOutlet NSProgressIndicator *dissemblyProgressIndicator;
@property (assign) IBOutlet NSButton *stopButton;
@property (assign) IBOutlet NSSplitView *splitView;

@property (assign) IBOutlet ZGBacktraceController *backtraceController;
@property (assign) IBOutlet ZGRegistersController *registersController;

@property (readwrite) ZGMemoryAddress currentMemoryAddress;
@property (readwrite) ZGMemorySize currentMemorySize;

@property (nonatomic, strong) NSArray *instructions;

@property (readwrite, strong, nonatomic) NSTimer *updateInstructionsTimer;
@property (readwrite, nonatomic) BOOL windowDidAppear;

@property (nonatomic, copy) NSString *desiredProcessName;

@property (nonatomic, strong) NSArray *haltedBreakPoints;
@property (nonatomic, readonly) ZGBreakPoint *currentBreakPoint;

@property (nonatomic, assign) BOOL shouldIgnoreTableViewSelectionChange;

@end

#define ZGDisassemblerAddressField @"ZGDisassemblerAddressField"
#define ZGDisassemblerProcessName @"ZGDisassemblerProcessName"

@implementation ZGDisassemblerController

#pragma mark Birth & Death

- (id)init
{
	self = [super initWithWindowNibName:NSStringFromClass([self class])];
	
	self.undoManager = [[NSUndoManager alloc] init];
	self.haltedBreakPoints = [[NSArray alloc] init];
	
	[[NSNotificationCenter defaultCenter]
	 addObserver:self
	 selector:@selector(applicationWillTerminate:)
	 name:NSApplicationWillTerminateNotification
	 object:nil];
	
	return self;
}

- (void)encodeRestorableStateWithCoder:(NSCoder *)coder
{
    [super encodeRestorableStateWithCoder:coder];
	
	[coder encodeObject:self.addressTextField.stringValue forKey:ZGDisassemblerAddressField];
	[coder encodeObject:[self.runningApplicationsPopUpButton.selectedItem.representedObject name] forKey:ZGDisassemblerProcessName];
}

- (void)restoreStateWithCoder:(NSCoder *)coder
{
	[super restoreStateWithCoder:coder];
	
	NSString *disassemblerAddressField = [coder decodeObjectForKey:ZGDisassemblerAddressField];
	if (disassemblerAddressField)
	{
		self.addressTextField.stringValue = disassemblerAddressField;
	}
	
	self.desiredProcessName = [coder decodeObjectForKey:ZGDisassemblerProcessName];
	
	[self updateRunningProcesses];
	
	[self windowDidShow:nil];
}

- (void)markChanges
{
	if ([self respondsToSelector:@selector(invalidateRestorableState)])
	{
		[self invalidateRestorableState];
	}
}

- (void)setCurrentProcess:(ZGProcess *)newProcess
{
	BOOL shouldUpdate = NO;
	
	if (_currentProcess && _currentProcess.processID != newProcess.processID)
	{
		[[ZGProcessList sharedProcessList] removePriorityToProcessIdentifier:_currentProcess.processID];
		[[ZGProcessList sharedProcessList] addPriorityToProcessIdentifier:newProcess.processID];
		
		shouldUpdate = YES;
	}
	_currentProcess = newProcess;
	if (_currentProcess && ![_currentProcess hasGrantedAccess] && _currentProcess.valid)
	{
		if (![_currentProcess grantUsAccess])
		{
			shouldUpdate = YES;
			//NSLog(@"Debugger failed to grant access to PID %d", _currentProcess.processID);
		}
	}
	
	if (shouldUpdate && self.windowDidAppear)
	{
		[self updateRegisters];
		if (self.currentBreakPoint)
		{
			[self jumpToMemoryAddress:self.registersController.programCounter inProcess:self.currentProcess];
		}
		else
		{
			[self readMemory:nil];
		}
	}
}

- (void)windowDidLoad
{
    [super windowDidLoad];
	
	self.window.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
	
	if ([self.window respondsToSelector:@selector(setRestorable:)] && [self.window respondsToSelector:@selector(setRestorationClass:)])
	{
		self.window.restorable = YES;
		self.window.restorationClass = ZGAppController.class;
		self.window.identifier = ZGDisassemblerIdentifier;
		[self markChanges];
	}
    
	// Add processes to popup button
	self.desiredProcessName = [[ZGAppController sharedController] lastSelectedProcessName];
	[self updateRunningProcesses];
	
	[[ZGProcessList sharedProcessList]
	 addObserver:self
	 forKeyPath:@"runningProcesses"
	 options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew
	 context:NULL];
	
	[[NSNotificationCenter defaultCenter]
	 addObserver:self
	 selector:@selector(runningApplicationsPopUpButtonWillPopUp:)
	 name:NSPopUpButtonWillPopUpNotification
	 object:self.runningApplicationsPopUpButton];
	
	[self.instructionsTableView registerForDraggedTypes:@[ZGVariablePboardType]];
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex
{
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

- (void)toggleBacktraceView:(NSCellStateValue)state
{	
	switch (state)
	{
		case NSOnState:
			[self uncollapseBottomSubview];
			break;
		case NSOffState:
			[self.undoManager removeAllActionsWithTarget:self.registersController];
			[self collapseBottomSubview];
			break;
		default:
			break;
	}
}

// This is intended to be called when the window shows up - either from showWindow: or from window restoration
- (void)windowDidShow:(id)sender
{
	if (!self.updateInstructionsTimer)
	{
		self.updateInstructionsTimer =
			[NSTimer
			 scheduledTimerWithTimeInterval:0.5
			 target:self
			 selector:@selector(updateInstructionsTimer:)
			 userInfo:nil
			 repeats:YES];
	}
	
	if (!self.windowDidAppear)
	{
		self.windowDidAppear = YES;
		if (!sender)
		{
			[self readMemory:nil];
		}
		
		[self toggleBacktraceView:NSOffState];
	}
	
	if (self.currentProcess)
	{
		if (self.currentProcess.valid)
		{
			[[ZGProcessList sharedProcessList] addPriorityToProcessIdentifier:self.currentProcess.processID];
		}
		else
		{
			[[ZGProcessList sharedProcessList] requestPollingWithObserver:self];
		}
	}
}

- (IBAction)showWindow:(id)sender
{
	[super showWindow:sender];
	
	[self windowDidShow:sender];
}

- (void)windowWillClose:(NSNotification *)notification
{
	if ([notification object] == self.window)
	{
		[self.updateInstructionsTimer invalidate];
		self.updateInstructionsTimer = nil;
		
		if (self.currentProcess.valid)
		{
			[[ZGProcessList sharedProcessList] removePriorityToProcessIdentifier:self.currentProcess.processID];
		}
		
		[[ZGProcessList sharedProcessList] unrequestPollingWithObserver:self];
	}
}

#pragma mark Symbols

- (void)updateSymbolsForInstructions:(NSArray *)instructions
{
	NSString *atosPath = @"/usr/bin/atos";
	if ([[NSFileManager defaultManager] fileExistsAtPath:atosPath])
	{
		NSTask *atosTask = [[NSTask alloc] init];
		[atosTask setLaunchPath:atosPath];
		[atosTask setArguments:@[@"-p", [NSString stringWithFormat:@"%d", self.currentProcess.processID]]];
		
		NSPipe *inputPipe = [NSPipe pipe];
		[atosTask setStandardInput:inputPipe];
		
		NSPipe *outputPipe = [NSPipe pipe];
		[atosTask setStandardOutput:outputPipe];
		
		// Ignore error message saying that atos has RESTRICT section thus DYLD environment variables being ignored
		[atosTask setStandardError:[NSPipe pipe]];
		
		[atosTask launch];
		
		for (ZGInstruction *instruction in instructions)
		{
			[[inputPipe fileHandleForWriting] writeData:[[instruction.variable.addressStringValue stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
		}
		
		[[inputPipe fileHandleForWriting] closeFile];
		
		NSData *data = [[outputPipe fileHandleForReading] readDataToEndOfFile];
		if (data)
		{
			NSUInteger instructionIndex = 0;
			NSString *contents = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			for (NSString *line in [contents componentsSeparatedByString:@"\n"])
			{
				if ([line length] > 0 && ![line isEqualToString:@""] && ![line isEqualToString:@"\n"] && instructionIndex < instructions.count)
				{
					ZGInstruction *instruction = [instructions objectAtIndex:instructionIndex];
					instruction.symbols = line;
				}
				
				instructionIndex++;
			}
		}
	}
}

- (BOOL)shouldUpdateSymbolsForInstructions:(NSArray *)instructions
{
	BOOL shouldUpdateSymbols = NO;
	
	for (ZGInstruction *instruction in instructions)
	{
		if (!instruction.symbols)
		{
			shouldUpdateSymbols = YES;
			break;
		}
	}
	
	return shouldUpdateSymbols;
}

#pragma mark Disassembling

- (ZGInstruction *)findInstructionBeforeAddress:(ZGMemoryAddress)address inProcess:(ZGProcess *)process
{
	ZGInstruction *instruction = nil;
	
	for (ZGRegion *region in ZGRegionsForProcessTask(process.processTask))
	{
		if (address >= region.address && address <= region.address + region.size)
		{
			// Start an arbitrary number of bytes before our address and decode the instructions
			// Eventually they will converge into correct offsets
			// So retrieve the offset and size to the last instruction while decoding
			// We do this instead of starting at region.address due to this leading to better performance
			
			ZGMemoryAddress startAddress = address - 1024;
			if (startAddress < region.address)
			{
				startAddress = region.address;
			}
			
			ZGMemorySize size = address - startAddress;
			// Read in more bytes to ensure we return the whole instruction
			ZGMemorySize readSize = size + 30;
			if (startAddress + readSize > region.address + region.size)
			{
				readSize = region.address + region.size - startAddress;
			}
			
			void *bytes = NULL;
			if (ZGReadBytes(process.processTask, startAddress, &bytes, &readSize))
			{
				ZGDisassemblerObject *disassemblerObject = [[ZGDisassemblerObject alloc] initWithProcess:process address:startAddress size:readSize bytes:bytes breakPoints:[[[ZGAppController sharedController] breakPointController] breakPoints]];
				
				__block ZGMemoryAddress memoryOffset = 0;
				__block ZGMemorySize memorySize = 0;
				__block NSString *instructionText = nil;
				__block ud_mnemonic_code_t instructionMnemonic = 0;
				
				[disassemblerObject enumerateWithBlock:^(ZGMemoryAddress instructionAddress, ZGMemorySize instructionSize, ud_mnemonic_code_t mnemonic, NSString *disassembledText, BOOL *stop) {
					if ((instructionAddress - startAddress) + instructionSize >= size)
					{
						memoryOffset = instructionAddress - startAddress;
						memorySize = instructionSize;
						instructionText = disassembledText;
						instructionMnemonic = mnemonic;
						*stop = YES;
					}
				}];
				
				instruction = [[ZGInstruction alloc] init];
				instruction.text = instructionText;
				instruction.mnemonic = instructionMnemonic;
				ZGVariable *variable = [[ZGVariable alloc] initWithValue:disassemblerObject.bytes + memoryOffset size:memorySize address:startAddress + memoryOffset type:ZGByteArray qualifier:0 pointerSize:process.pointerSize name:instruction.text shouldBeSearched:NO];
				instruction.variable = variable;
				
				ZGFreeBytes(process.processTask, bytes, readSize);
			}
			
			break;
		}
	}
	
	return instruction;
}

- (void)updateInstructionValues
{
	// Check to see if anything in the window needs to be updated
	NSRange visibleRowsRange = [self.instructionsTableView rowsInRect:self.instructionsTableView.visibleRect];
	if (visibleRowsRange.location + visibleRowsRange.length <= self.instructions.count)
	{
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
						 for (ZGBreakPoint *breakPoint in [[[ZGAppController sharedController] breakPointController] breakPoints])
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
				ZGInstruction *searchedInstruction = [self findInstructionBeforeAddress:instruction.variable.address inProcess:self.currentProcess];
				
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
				ZGInstruction *searchedInstruction = [self findInstructionBeforeAddress:startInstruction.variable.address inProcess:self.currentProcess];
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
				ZGInstruction *searchedInstruction = [self findInstructionBeforeAddress:instruction.variable.address + instruction.variable.size inProcess:self.currentProcess];
				
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
				ZGInstruction *searchedInstruction = [self findInstructionBeforeAddress:endInstruction.variable.address + endInstruction.variable.size inProcess:self.currentProcess];
				if (endInstruction.variable.address != searchedInstruction.variable.address)
				{
					endAddress = searchedInstruction.variable.address + searchedInstruction.variable.size;
				}
			}
			
			void *bytes = NULL;
			ZGMemorySize size = endAddress - startAddress;
			
			if (ZGReadBytes(self.currentProcess.processTask, startAddress, &bytes, &size))
			{
				ZGDisassemblerObject *disassemblerObject = [[ZGDisassemblerObject alloc] initWithProcess:self.currentProcess address:startAddress size:size bytes:bytes breakPoints:[[[ZGAppController sharedController] breakPointController] breakPoints]];
				
				NSMutableArray *instructionsToReplace = [[NSMutableArray alloc] init];
				
				[disassemblerObject enumerateWithBlock:^(ZGMemoryAddress instructionAddress, ZGMemorySize instructionSize, ud_mnemonic_code_t mnemonic, NSString *disassembledText, BOOL *stop)  {
					ZGInstruction *newInstruction = [[ZGInstruction alloc] init];
					newInstruction.text = disassembledText;
					newInstruction.variable = [[ZGVariable alloc] initWithValue:disassemblerObject.bytes + (instructionAddress - startAddress) size:instructionSize address:instructionAddress type:ZGByteArray qualifier:0 pointerSize:self.currentProcess.pointerSize name:newInstruction.text shouldBeSearched:NO];
					newInstruction.mnemonic = mnemonic;
					
					[instructionsToReplace addObject:newInstruction];
				}];
				
				// Replace the visible instructions
				NSMutableArray *newInstructions = [[NSMutableArray alloc] initWithArray:self.instructions];
				[newInstructions replaceObjectsInRange:NSMakeRange(startRow, endRow - startRow) withObjectsFromArray:instructionsToReplace];
				self.instructions = [NSArray arrayWithArray:newInstructions];
				
				[self.instructionsTableView reloadData];
				
				ZGFreeBytes(self.currentProcess.processTask, bytes, size);
			}
		}
	}
}

- (void)updateInstructionSymbols
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

- (void)updateInstructionsTimer:(NSTimer *)timer
{
	if (self.currentProcess.valid && self.instructionsTableView.editedRow == -1 && !self.disassembling)
	{
		[self updateInstructionValues];
		[self updateInstructionSymbols];
	}
}

- (IBAction)stopDisassembling:(id)sender
{
	self.disassembling = NO;
	[self.stopButton setEnabled:NO];
}

- (void)updateDisassemblerWithAddress:(ZGMemoryAddress)address size:(ZGMemorySize)theSize selectionAddress:(ZGMemoryAddress)selectionAddress
{
	[self.dissemblyProgressIndicator setMinValue:0];
	[self.dissemblyProgressIndicator setMaxValue:theSize];
	[self.dissemblyProgressIndicator setDoubleValue:0];
	[self.dissemblyProgressIndicator setHidden:NO];
	[self.addressTextField setEnabled:NO];
	[self.runningApplicationsPopUpButton setEnabled:NO];
	[self.stopButton setEnabled:YES];
	[self.stopButton setHidden:NO];
	
	self.instructions = @[];
	[self.instructionsTableView reloadData];
	
	self.currentMemoryAddress = address;
	self.currentMemorySize = 0;
	
	self.disassembling = YES;
	
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		void *bytes;
		ZGMemorySize size = theSize;
		if (ZGReadBytes(self.currentProcess.processTask, address, &bytes, &size))
		{
			ZGDisassemblerObject *disassemblerObject = [[ZGDisassemblerObject alloc] initWithProcess:self.currentProcess address:address size:size bytes:bytes breakPoints:[[[ZGAppController sharedController] breakPointController] breakPoints]];
			
			__block NSMutableArray *newInstructions = [[NSMutableArray alloc] init];
			
			// We add instructions to table in batches. First time 1000 variables will be added, 2nd time 1000*2, third time 1000*2*2, etc.
			__block NSUInteger thresholdCount = 1000;
			
			__block NSUInteger totalInstructionCount = 0;
			
			__block NSUInteger selectionRow = 0;
			
			// Block for adding a batch of instructions which will be used for later
			void (^addBatchOfInstructions)(void) = ^{
				NSArray *currentBatch = newInstructions;
				
				dispatch_async(dispatch_get_main_queue(), ^{
					NSMutableArray *appendedInstructions = [[NSMutableArray alloc] initWithArray:self.instructions];
					[appendedInstructions addObjectsFromArray:currentBatch];
					
					if (self.instructions.count == 0 && self.window.firstResponder != self.backtraceController.tableView)
					{
						[self.window makeFirstResponder:self.instructionsTableView];
					}
					self.instructions = [NSArray arrayWithArray:appendedInstructions];
					[self.instructionsTableView noteNumberOfRowsChanged];
					self.currentMemorySize = self.instructions.count;
				});
			};
			
			[disassemblerObject enumerateWithBlock:^(ZGMemoryAddress instructionAddress, ZGMemorySize instructionSize, ud_mnemonic_code_t mnemonic, NSString *disassembledText, BOOL *stop)  {
				ZGInstruction *instruction = [[ZGInstruction alloc] init];
				instruction.text = disassembledText;
				instruction.variable = [[ZGVariable alloc] initWithValue:disassemblerObject.bytes + (instructionAddress - address) size:instructionSize address:instructionAddress type:ZGByteArray qualifier:0 pointerSize:self.currentProcess.pointerSize name:instruction.text shouldBeSearched:NO];
				instruction.mnemonic = mnemonic;
				
				[newInstructions addObject:instruction];
				
				dispatch_async(dispatch_get_main_queue(), ^{
					self.dissemblyProgressIndicator.doubleValue += instruction.variable.size;
				});
				
				if (selectionAddress >= instruction.variable.address && selectionAddress < instruction.variable.address + instruction.variable.size)
				{
					selectionRow = totalInstructionCount;
				}
				
				if (!self.disassembling)
				{
					*stop = YES;
				}
				else
				{
					totalInstructionCount++;
					
					if (totalInstructionCount >= thresholdCount)
					{
						addBatchOfInstructions();
						newInstructions = [[NSMutableArray alloc] init];
						thresholdCount *= 2;
					}
				}
			}];
			
			// Add the leftover batch
			addBatchOfInstructions();
			
			dispatch_async(dispatch_get_main_queue(), ^{
				[self scrollAndSelectRow:selectionRow];
				
				self.disassembling = NO;
				[self.dissemblyProgressIndicator setHidden:YES];
				[self.addressTextField setEnabled:YES];
				[self.runningApplicationsPopUpButton setEnabled:YES];
				[self.stopButton setHidden:YES];
			});
			
			ZGFreeBytes(self.currentProcess.processTask, bytes, size);
		}
	});
}

#pragma mark Handling Processes

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (object == [ZGProcessList sharedProcessList])
	{
		[self updateRunningProcesses];
		
		NSArray *oldRunningProcesses = [change objectForKey:NSKeyValueChangeOldKey];
		
		if (oldRunningProcesses)
		{
			for (ZGRunningProcess *runningProcess in oldRunningProcesses)
			{
				[[[ZGAppController sharedController] breakPointController] removeObserver:self runningProcess:runningProcess];
				for (ZGBreakPoint *haltedBreakPoint in self.haltedBreakPoints)
				{
					if (haltedBreakPoint.process.processID == runningProcess.processIdentifier)
					{
						[self removeHaltedBreakPoint:haltedBreakPoint];
					}
				}
			}
		}
	}
}

- (void)updateRunningProcesses
{
	[self.runningApplicationsPopUpButton removeAllItems];
	
	NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"activationPolicy" ascending:YES];
	for (ZGRunningProcess *runningProcess in  [[[ZGProcessList sharedProcessList] runningProcesses] sortedArrayUsingDescriptors:@[sortDescriptor]])
	{
		if (runningProcess.processIdentifier != NSRunningApplication.currentApplication.processIdentifier)
		{
			NSMenuItem *menuItem = [[NSMenuItem alloc] init];
			menuItem.title = [NSString stringWithFormat:@"%@ (%d)", runningProcess.name, runningProcess.processIdentifier];
			NSImage *iconImage = [runningProcess.icon copy];
			iconImage.size = NSMakeSize(16, 16);
			menuItem.image = iconImage;
			ZGProcess *representedProcess =
				[[ZGProcess alloc]
				 initWithName:runningProcess.name
				 processID:runningProcess.processIdentifier
				 set64Bit:runningProcess.is64Bit];
			
			menuItem.representedObject = representedProcess;
			
			[self.runningApplicationsPopUpButton.menu addItem:menuItem];
			
			if (self.currentProcess.processID == runningProcess.processIdentifier || [self.desiredProcessName isEqualToString:runningProcess.name])
			{
				[self.runningApplicationsPopUpButton selectItem:self.runningApplicationsPopUpButton.lastItem];
			}
		}
	}
	
	// Handle dead process
	if (self.desiredProcessName && ![self.desiredProcessName isEqualToString:[self.runningApplicationsPopUpButton.selectedItem.representedObject name]])
	{
		NSMenuItem *menuItem = [[NSMenuItem alloc] init];
		menuItem.title = [NSString stringWithFormat:@"%@ (none)", self.desiredProcessName];
		NSImage *iconImage = [[NSImage imageNamed:@"NSDefaultApplicationIcon"] copy];
		iconImage.size = NSMakeSize(16, 16);
		menuItem.image = iconImage;
		menuItem.representedObject = [[ZGProcess alloc] initWithName:self.desiredProcessName set64Bit:YES];
		[self.runningApplicationsPopUpButton.menu addItem:menuItem];
		[self.runningApplicationsPopUpButton selectItem:self.runningApplicationsPopUpButton.lastItem];
		
		[[ZGProcessList sharedProcessList] requestPollingWithObserver:self];
	}
	else
	{
		[[ZGProcessList sharedProcessList] unrequestPollingWithObserver:self];
	}
	
	self.currentProcess = self.runningApplicationsPopUpButton.selectedItem.representedObject;
}

- (void)switchProcessMenuItemAndSelectAddress:(ZGMemoryAddress)address
{
	if ([self.runningApplicationsPopUpButton.selectedItem.representedObject processID] != self.currentProcess.processID)
	{
		self.addressTextField.stringValue = [NSString stringWithFormat:@"0x%llX", address];
		self.desiredProcessName = [self.runningApplicationsPopUpButton.selectedItem.representedObject name];
		[[ZGAppController sharedController] setLastSelectedProcessName:self.desiredProcessName];
		self.currentProcess = self.runningApplicationsPopUpButton.selectedItem.representedObject;
	}
}

- (void)runningApplicationsPopUpButtonWillPopUp:(NSNotification *)notification
{
	[[ZGProcessList sharedProcessList] retrieveList];
}

- (IBAction)runningApplicationsPopUpButton:(id)sender
{
	[self switchProcessMenuItemAndSelectAddress:0x0];
}

#pragma mark Changing disassembler view

- (IBAction)readMemory:(id)sender
{
	BOOL success = NO;
	
	if (!self.currentProcess.valid || ![self.currentProcess hasGrantedAccess])
	{
		goto END_DEBUGGER_CHANGE;
	}
	
	// create scope block to allow for goto
	{
		NSString *calculatedMemoryAddressExpression = [ZGCalculator evaluateExpression:self.addressTextField.stringValue];
		
		ZGMemoryAddress calculatedMemoryAddress = 0;
		
		if (isValidNumber(calculatedMemoryAddressExpression))
		{
			calculatedMemoryAddress = memoryAddressFromExpression(calculatedMemoryAddressExpression);
		}
		
		NSArray *memoryRegions = ZGRegionsForProcessTask(self.currentProcess.processTask);
		if (memoryRegions.count == 0)
		{
			goto END_DEBUGGER_CHANGE;
		}
		
		ZGRegion *chosenRegion = nil;
		for (ZGRegion *region in memoryRegions)
		{
			if ((region.protection & VM_PROT_READ) && (calculatedMemoryAddress <= 0 || (calculatedMemoryAddress >= region.address && calculatedMemoryAddress < region.address + region.size)))
			{
				chosenRegion = region;
				break;
			}
		}
		
		if (!chosenRegion)
		{
			goto END_DEBUGGER_CHANGE;
		}
		
		if (calculatedMemoryAddress <= 0)
		{
			calculatedMemoryAddress = chosenRegion.address;
			[self.addressTextField setStringValue:[NSString stringWithFormat:@"0x%llX", calculatedMemoryAddress]];
		}
		
		// Dissemble within a range from +- WINDOW_SIZE from selection address
		const NSUInteger WINDOW_SIZE = 50000;
		
		ZGMemoryAddress lowBoundAddress = calculatedMemoryAddress - WINDOW_SIZE;
		if (lowBoundAddress <= chosenRegion.address)
		{
			lowBoundAddress = chosenRegion.address;
		}
		else
		{
			lowBoundAddress = [self findInstructionBeforeAddress:lowBoundAddress inProcess:self.currentProcess].variable.address;
			if (lowBoundAddress < chosenRegion.address)
			{
				lowBoundAddress = chosenRegion.address;
			}
		}
		
		ZGMemoryAddress highBoundAddress = calculatedMemoryAddress + WINDOW_SIZE;
		if (highBoundAddress >= chosenRegion.address + chosenRegion.size)
		{
			highBoundAddress = chosenRegion.address + chosenRegion.size;
		}
		else
		{
			highBoundAddress = [self findInstructionBeforeAddress:highBoundAddress inProcess:self.currentProcess].variable.address;
			if (highBoundAddress <= chosenRegion.address || highBoundAddress > chosenRegion.address + chosenRegion.size)
			{
				highBoundAddress = chosenRegion.address + chosenRegion.size;
			}
		}
		
		[self.undoManager removeAllActions];
		[self updateDisassemblerWithAddress:lowBoundAddress size:highBoundAddress - lowBoundAddress selectionAddress:calculatedMemoryAddress];
		
		success = YES;
	}
	
END_DEBUGGER_CHANGE:
	if (!success)
	{
		// clear data
		self.instructions = [NSArray array];
		[self.instructionsTableView reloadData];
	}
}

#pragma mark Useful methods for the world

- (NSArray *)selectedInstructions
{
	NSIndexSet *tableIndexSet = self.instructionsTableView.selectedRowIndexes;
	NSInteger clickedRow = self.instructionsTableView.clickedRow;
	
	NSIndexSet *selectionIndexSet = (clickedRow != -1 && ![tableIndexSet containsIndex:clickedRow]) ? [NSIndexSet indexSetWithIndex:clickedRow] : tableIndexSet;
	
	return [self.instructions objectsAtIndexes:selectionIndexSet];
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
	
	if (targetMenuItem)
	{
		self.addressTextField.stringValue = [NSString stringWithFormat:@"0x%llX", address];
		
		if ([targetMenuItem.representedObject processID] != self.currentProcess.processID)
		{
			[self.runningApplicationsPopUpButton selectItem:targetMenuItem];
			[self switchProcessMenuItemAndSelectAddress:address];
			self.instructions = @[];
			[self.instructionsTableView reloadData];
		}
		else
		{
			[self readMemory:nil];
		}
	}
	else
	{
		NSLog(@"Could not find target process!");
	}
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{	
	if (menuItem.action == @selector(nopVariables:))
	{
		[menuItem setTitle:[NSString stringWithFormat:@"NOP Instruction%@", self.selectedInstructions.count == 1 ? @"" : @"s"]];
		if (self.selectedInstructions.count == 0 || !self.currentProcess.valid || self.instructionsTableView.editedRow != -1 || self.disassembling)
		{
			return NO;
		}
	}
	else if (menuItem.action == @selector(copy:))
	{
		if (self.selectedInstructions.count == 0)
		{
			return NO;
		}
	}
	else if (menuItem.action == @selector(continueExecution:) || menuItem.action == @selector(stepInto:))
	{
		if (!self.currentBreakPoint || self.disassembling)
		{
			return NO;
		}
	}
	else if (menuItem.action == @selector(stepOver:))
	{
		if (!self.currentBreakPoint || self.disassembling)
		{
			return NO;
		}
		
		ZGInstruction *currentInstruction = [self findInstructionBeforeAddress:self.registersController.programCounter + 1 inProcess:self.currentProcess];
		if (!currentInstruction)
		{
			return NO;
		}
		
		if ([currentInstruction isCallMnemonic])
		{
			ZGInstruction *nextInstruction = [self findInstructionBeforeAddress:currentInstruction.variable.address + currentInstruction.variable.size + 1 inProcess:self.currentProcess];
			if (!nextInstruction)
			{
				return NO;
			}
			
			if (![[[ZGAppController sharedController] breakPointController] isInstructionExecutable:nextInstruction inProcess:self.currentProcess])
			{
				return NO;
			}
		}
	}
	else if (menuItem.action == @selector(stepOut:))
	{
		if (!self.currentBreakPoint || self.disassembling)
		{
			return NO;
		}
		
		if (self.backtraceController.instructions.count <= 1 || self.backtraceController.basePointers.count <= 1)
		{
			return NO;
		}
		
		ZGInstruction *outterInstruction = [self.backtraceController.instructions objectAtIndex:1];
		ZGInstruction *returnInstruction = [self findInstructionBeforeAddress:outterInstruction.variable.address + outterInstruction.variable.size + 1 inProcess:self.currentProcess];
		
		if (!returnInstruction)
		{
			return NO;
		}
		
		if (![[[ZGAppController sharedController] breakPointController] isInstructionExecutable:returnInstruction inProcess:self.currentProcess])
		{
			return NO;
		}
	}
	else if (menuItem.action == @selector(toggleBreakPoints:))
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
	else if (menuItem.action == @selector(removeAllBreakPoints:))
	{
		if (self.disassembling)
		{
			return NO;
		}
		
		BOOL shouldValidate = NO;
		
		for (ZGBreakPoint *breakPoint in [[[ZGAppController sharedController] breakPointController] breakPoints])
		{
			if (breakPoint.delegate == self)
			{
				shouldValidate = YES;
				break;
			}
		}
		
		return shouldValidate;
	}
	else if (menuItem.action == @selector(jump:))
	{
		if (self.disassembling || !self.currentBreakPoint || self.selectedInstructions.count != 1)
		{
			return NO;
		}
	}
	else if (menuItem.action == @selector(pauseOrUnpauseProcess:))
	{
		if (!self.currentProcess.valid)
		{
			return NO;
		}
		
		integer_t suspendCount;
		if (!ZGSuspendCount(self.currentProcess.processTask, &suspendCount))
		{
			return NO;
		}
		else
		{
			menuItem.title = [NSString stringWithFormat:@"%@ Target", suspendCount > 0 ? @"Unpause" : @"Pause"];
		}
		
		if ([self isProcessIdentifierHalted:self.currentProcess.processID])
		{
			return NO;
		}
	}
	
	return YES;
}

- (NSUndoManager *)windowWillReturnUndoManager:(id)sender
{
	return self.undoManager;
}

- (IBAction)copy:(id)sender
{
	NSMutableArray *descriptionComponents = [[NSMutableArray alloc] init];
	NSMutableArray *variablesArray = [[NSMutableArray alloc] init];
	
	for (ZGInstruction *instruction in self.selectedInstructions)
	{
		[descriptionComponents addObject:[@[instruction.variable.addressStringValue, instruction.text, instruction.variable.stringValue] componentsJoinedByString:@"\t"]];
		[variablesArray addObject:instruction.variable];
	}
	
	[[NSPasteboard generalPasteboard] declareTypes:@[NSStringPboardType] owner:self];
	[[NSPasteboard generalPasteboard] setString:[descriptionComponents componentsJoinedByString:@"\n"] forType:NSStringPboardType];
	[[NSPasteboard generalPasteboard] setData:[NSKeyedArchiver archivedDataWithRootObject:variablesArray] forType:ZGVariablePboardType];
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
	NSArray *variables = [[self.instructions objectsAtIndexes:rowIndexes] valueForKey:@"variable"];
	return [pboard setData:[NSKeyedArchiver archivedDataWithRootObject:variables] forType:ZGVariablePboardType];
}

- (BOOL)selectionShouldChangeInTableView:(NSTableView *)aTableView
{
	if (self.shouldIgnoreTableViewSelectionChange)
	{
		self.shouldIgnoreTableViewSelectionChange = NO;
		return NO;
	}
	
	return YES;
}

- (BOOL)isBreakPointAtInstruction:(ZGInstruction *)instruction
{
	BOOL answer = NO;
	
	for (ZGBreakPoint *breakPoint in [[[ZGAppController sharedController] breakPointController] breakPoints])
	{
		if (breakPoint.type == ZGBreakPointInstruction && breakPoint.task == self.currentProcess.processTask && breakPoint.variable.address == instruction.variable.address && !breakPoint.hidden)
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
		ZGInstruction *instruction = [self.instructions objectAtIndex:rowIndex];
		
		if ([tableColumn.identifier isEqualToString:@"bytes"])
		{
			[self replaceInstructions:@[instruction] fromOldStringValues:@[instruction.variable.stringValue] toNewStringValues:@[object] actionName:@"Instruction Change"];
		}
		else if ([tableColumn.identifier isEqualToString:@"breakpoint"])
		{
			if (self.selectedInstructions.count > 1)
			{
				self.shouldIgnoreTableViewSelectionChange = YES;
			}
			
			if ([object boolValue])
			{
				[self addBreakPointsToInstructions:self.selectedInstructions];
			}
			else
			{
				[self removeBreakPointsToInstructions:self.selectedInstructions];
			}
		}
	}
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if ([tableColumn.identifier isEqualToString:@"address"] && rowIndex >= 0 && (NSUInteger)rowIndex < self.instructions.count)
	{
		ZGInstruction *instruction = [self.instructions objectAtIndex:rowIndex];
		BOOL isInstructionBreakPoint = (self.currentBreakPoint && self.registersController.programCounter == instruction.variable.address);
		
		[cell setTextColor:isInstructionBreakPoint ? NSColor.redColor : NSColor.textColor];
	}
}

#pragma mark Modifying instructions

- (void)replaceInstructions:(NSArray *)instructions fromOldStringValues:(NSArray *)oldStringValues toNewStringValues:(NSArray *)newStringValues actionName:(NSString *)actionName
{
	for (NSUInteger index = 0; index < instructions.count; index++)
	{
		ZGInstruction *instruction = [instructions objectAtIndex:index];
		[self writeStringValue:[newStringValues objectAtIndex:index] atAddress:instruction.variable.address];
	}
	
	[self.undoManager setActionName:[actionName stringByAppendingFormat:@"%@", instructions.count == 1 ? @"" : @"s"]];
	
	[[self.undoManager prepareWithInvocationTarget:self] replaceInstructions:instructions fromOldStringValues:newStringValues toNewStringValues:oldStringValues actionName:actionName];
}

- (void)writeStringValue:(NSString *)stringValue atAddress:(ZGMemoryAddress)address
{
	ZGMemorySize newSize = 0;
	void *newValue = valueFromString(self.currentProcess, stringValue, ZGByteArray, &newSize);
	
	if (newValue)
	{
		ZGBreakPoint *targetBreakPoint = nil;
		for (ZGBreakPoint *breakPoint in [[[ZGAppController sharedController] breakPointController] breakPoints])
		{
			if (breakPoint.variable.address >= address && breakPoint.variable.address < address + newSize)
			{
				targetBreakPoint = breakPoint;
				break;
			}
		}
		
		if (!targetBreakPoint)
		{
			ZGWriteBytesIgnoringProtection(self.currentProcess.processTask, address, newValue, newSize);
		}
		else
		{
			if (targetBreakPoint.variable.address - address > 0)
			{
				ZGWriteBytesIgnoringProtection(self.currentProcess.processTask, address, newValue, targetBreakPoint.variable.address - address);
			}
			
			if (address + newSize - targetBreakPoint.variable.address - 1 > 0)
			{
				ZGWriteBytesIgnoringProtection(self.currentProcess.processTask, targetBreakPoint.variable.address + 1, newValue + (targetBreakPoint.variable.address + 1 - address), address + newSize - targetBreakPoint.variable.address - 1);
			}
			
			*(uint8_t *)targetBreakPoint.variable.value = *(uint8_t *)(newValue + targetBreakPoint.variable.address - address);
		}
		
		free(newValue);
	}
}

- (IBAction)nopVariables:(id)sender
{
	NSArray *selectedInstructions = [self selectedInstructions];
	NSMutableArray *newStringValues = [[NSMutableArray alloc] init];
	NSMutableArray *oldStringValues = [[NSMutableArray alloc] init];
	
	for (NSUInteger instructionIndex = 0; instructionIndex < selectedInstructions.count; instructionIndex++)
	{
		ZGInstruction *instruction = [selectedInstructions objectAtIndex:instructionIndex];
		[oldStringValues addObject:instruction.variable.stringValue];
		
		NSMutableArray *nopComponents = [[NSMutableArray alloc] init];
		for (NSUInteger nopIndex = 0; nopIndex < instruction.variable.size; nopIndex++)
		{
			[nopComponents addObject:@"90"];
		}
		
		[newStringValues addObject:[nopComponents componentsJoinedByString:@" "]];
	}
	
	[self replaceInstructions:selectedInstructions fromOldStringValues:oldStringValues toNewStringValues:newStringValues actionName:@"NOP Change"];
}

#pragma mark Break Points

- (void)removeBreakPointsToInstructions:(NSArray *)instructions
{
	NSMutableArray *changedInstructions = [[NSMutableArray alloc] init];
	
	for (ZGInstruction *instruction in instructions)
	{
		if ([self isBreakPointAtInstruction:instruction])
		{
			[changedInstructions addObject:instruction];
			[[[ZGAppController sharedController] breakPointController] removeBreakPointOnInstruction:instruction inProcess:self.currentProcess];
		}
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
			addedAtLeastOneBreakPoint = [[[ZGAppController sharedController] breakPointController] addBreakPointOnInstruction:instruction inProcess:self.currentProcess delegate:self] || addedAtLeastOneBreakPoint;
		}
	}
	
	if (addedAtLeastOneBreakPoint)
	{
		[self.undoManager setActionName:[NSString stringWithFormat:@"Remove Breakpoint%@", changedInstructions.count != 1 ? @"s" : @""]];
		[[self.undoManager prepareWithInvocationTarget:self] removeBreakPointsToInstructions:changedInstructions];
		[self.instructionsTableView reloadData];
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
	[[[ZGAppController sharedController] breakPointController] removeObserver:self];
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

- (void)goToCurrentBreakPoint
{	
	BOOL foundInstruction = NO;
	ZGMemoryAddress programCounter = self.registersController.programCounter;
	
	if (self.instructions.count > 0)
	{
		// Try to find the instruction in the table first, using a binary search
		NSUInteger maxInstructionIndex = self.instructions.count-1;
		NSUInteger minInstructionIndex = 0;
		
		while (maxInstructionIndex >= minInstructionIndex && !foundInstruction)
		{
			NSUInteger middleInstructionIndex = (minInstructionIndex + maxInstructionIndex) / 2;
			ZGInstruction *instruction = [self.instructions objectAtIndex:middleInstructionIndex];
			
			if (instruction.variable.address < programCounter)
			{
				if (middleInstructionIndex >= self.instructions.count-1) break;
				minInstructionIndex = middleInstructionIndex + 1;
			}
			else if (instruction.variable.address > programCounter)
			{
				if (middleInstructionIndex == 0) break;
				maxInstructionIndex = middleInstructionIndex - 1;
			}
			else
			{
				if (instruction.variable.address == programCounter)
				{
					[self scrollAndSelectRow:middleInstructionIndex];
					foundInstruction = YES;
				}
				else
				{
					break;
				}
			}
		}
	}
	
	if (!foundInstruction)
	{	
		[self jumpToMemoryAddress:programCounter inProcess:self.currentProcess];
	}
}

- (void)jumpToAddress:(ZGMemoryAddress)newAddress
{
	if (self.currentBreakPoint && !self.disassembling)
	{
		ZGMemoryAddress currentAddress = [self.registersController programCounter];
		[self.registersController changeProgramCounter:newAddress];
		[[self.undoManager prepareWithInvocationTarget:self] jumpToAddress:currentAddress];
		[self.undoManager setActionName:@"Jump"];
	}
}

- (IBAction)jump:(id)sender
{
	ZGInstruction *instruction = [self.selectedInstructions objectAtIndex:0];
	[self jumpToAddress:instruction.variable.address];
}

- (void)updateRegisters
{
	if (self.currentBreakPoint)
	{
		[self.registersController updateRegistersFromBreakPoint:self.currentBreakPoint programCounterChange:^{
			if (self.currentBreakPoint)
			{
				[self.instructionsTableView reloadData];
			}
		}];
	}
}

- (void)breakPointDidHit:(ZGBreakPoint *)breakPoint
{	
	[self removeHaltedBreakPoint:self.currentBreakPoint];
	[self addHaltedBreakPoint:breakPoint];
	
	if (self.currentBreakPoint)
	{
		if (!self.window.isVisible)
		{
			[self showWindow:nil];
		}
		
		[self updateRegisters];
		[self goToCurrentBreakPoint];
		
		[self toggleBacktraceView:NSOnState];
		[self.backtraceController	updateBacktraceWithBasePointer:self.registersController.basePointer instructionPointer:self.registersController.programCounter inProcess:self.currentProcess];
		
		BOOL shouldShowNotification = YES;
		
		if (self.currentBreakPoint.hidden)
		{
			if (breakPoint.basePointer == self.registersController.basePointer)
			{
				[[[ZGAppController sharedController] breakPointController] removeInstructionBreakPoint:breakPoint];
			}
			else
			{
				[self continueFromBreakPoint:self.currentBreakPoint];
				shouldShowNotification = NO;
			}
		}
		
		if (shouldShowNotification && NSClassFromString(@"NSUserNotification"))
		{
			NSUserNotification *userNotification = [[NSUserNotification alloc] init];
			userNotification.title = @"Hit Breakpoint";
			userNotification.subtitle = self.currentProcess.name;
			userNotification.informativeText = [NSString stringWithFormat:@"Stopped at breakpoint %@", self.currentBreakPoint.variable.addressStringValue];
			[[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:userNotification];
		}
	}
}

- (void)resumeBreakPoint:(ZGBreakPoint *)breakPoint
{
	[[[ZGAppController sharedController] breakPointController] resumeFromBreakPoint:breakPoint];
	[self removeHaltedBreakPoint:breakPoint];
}

- (void)continueFromBreakPoint:(ZGBreakPoint *)breakPoint
{
	[[[ZGAppController sharedController] breakPointController] removeSingleStepBreakPointsFromBreakPoint:breakPoint];
	[self resumeBreakPoint:breakPoint];
	[self toggleBacktraceView:NSOffState];
}

- (IBAction)continueExecution:(id)sender
{
	[self continueFromBreakPoint:self.currentBreakPoint];
}

- (IBAction)stepInto:(id)sender
{
	[[[ZGAppController sharedController] breakPointController] addSingleStepBreakPointFromBreakPoint:self.currentBreakPoint];
	[self resumeBreakPoint:self.currentBreakPoint];
}

- (IBAction)stepOver:(id)sender
{
	ZGInstruction *currentInstruction = [self findInstructionBeforeAddress:self.registersController.programCounter + 1 inProcess:self.currentProcess];
	if ([currentInstruction isCallMnemonic])
	{
		ZGInstruction *nextInstruction = [self findInstructionBeforeAddress:currentInstruction.variable.address + currentInstruction.variable.size + 1 inProcess:self.currentProcess];
		
		[[[ZGAppController sharedController] breakPointController] addBreakPointOnInstruction:nextInstruction inProcess:self.currentProcess thread:self.currentBreakPoint.thread basePointer:self.registersController.basePointer delegate:self];
		[self continueExecution:nil];
	}
	else
	{
		[self stepInto:nil];
	}
}

- (IBAction)stepOut:(id)sender
{
	ZGInstruction *outterInstruction = [self.backtraceController.instructions objectAtIndex:1];
	ZGInstruction *returnInstruction = [self findInstructionBeforeAddress:outterInstruction.variable.address + outterInstruction.variable.size + 1 inProcess:self.currentProcess];
	
	[[[ZGAppController sharedController] breakPointController] addBreakPointOnInstruction:returnInstruction inProcess:self.currentProcess thread:self.currentBreakPoint.thread basePointer:[[self.backtraceController.basePointers objectAtIndex:1] unsignedLongLongValue] delegate:self];
	
	[self continueExecution:nil];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	[[[ZGAppController sharedController] breakPointController] removeObserver:self];
	
	for (ZGBreakPoint *breakPoint in self.haltedBreakPoints)
	{
		[self continueFromBreakPoint:breakPoint];
	}
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

#pragma mark Pausing

- (IBAction)pauseOrUnpauseProcess:(id)sender
{
	[ZGProcess pauseOrUnpauseProcessTask:self.currentProcess.processTask];
}

@end
