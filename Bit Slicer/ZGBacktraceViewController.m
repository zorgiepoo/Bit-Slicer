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

#import "ZGBacktraceViewController.h"
#import "ZGDebuggerController.h"

#import "ZGVirtualMemory.h"
#import "ZGProcess.h"
#import "ZGInstruction.h"
#import "ZGVariable.h"
#import "ZGAppController.h"
#import "ZGMemoryViewerController.h"

@interface ZGBacktraceViewController ()

@property (nonatomic, weak) ZGDebuggerController *debuggerController;

@property (nonatomic, assign) IBOutlet NSTableView *tableView;
@property (nonatomic) NSArray *instructions;
@property (nonatomic) NSArray *basePointers;

@property (assign, nonatomic) BOOL shouldIgnoreTableSelection;

@end

@implementation ZGBacktraceViewController

#pragma mark Birth

- (id)initWithDebuggerController:(ZGDebuggerController *)debuggerController
{
	self = [super initWithNibName:NSStringFromClass([self class]) bundle:nil];
	if (self != nil)
	{
		self.debuggerController = debuggerController;
	}
	return self;
}

- (void)loadView
{
	[super loadView];
	
	self.tableView.target = self;
	self.tableView.doubleAction = @selector(jumpToSelectedInstruction:);
	
	[self setNextResponder:[self.tableView nextResponder]];
	[self.tableView setNextResponder:self];
	
	[self.tableView registerForDraggedTypes:@[ZGVariablePboardType]];
}

#pragma mark Backtrace

- (NSArray *)backtraceWithBasePointer:(ZGMemoryAddress)basePointer instructionPointer:(ZGMemoryAddress)instructionPointer inProcess:(ZGProcess *)process
{
	NSMutableArray *newInstructions = [[NSMutableArray alloc] init];
	NSMutableArray *newBasePointers = [[NSMutableArray alloc] init];
	
	ZGInstruction *currentInstruction = [self.debuggerController findInstructionBeforeAddress:instructionPointer+1 inProcess:process];
	if (currentInstruction != nil)
	{
		[newInstructions addObject:currentInstruction];
		[newBasePointers addObject:@(basePointer)];
		
		while (basePointer > 0)
		{
			// Read return address
			void *returnAddressBytes = NULL;
			ZGMemorySize returnAddressSize = process.pointerSize;
			if (!ZGReadBytes(process.processTask, basePointer + process.pointerSize, &returnAddressBytes, &returnAddressSize))
			{
				break;
			}
			
			ZGMemoryAddress returnAddress;
			switch (returnAddressSize)
			{
				case sizeof(ZGMemoryAddress):
					returnAddress = *(ZGMemoryAddress *)returnAddressBytes;
					break;
				case sizeof(ZG32BitMemoryAddress):
					returnAddress = *(ZG32BitMemoryAddress *)returnAddressBytes;
					break;
				default:
					returnAddress = 0;
			}
			
			ZGFreeBytes(process.processTask, returnAddressBytes, returnAddressSize);
			
			ZGInstruction *instruction = [self.debuggerController findInstructionBeforeAddress:returnAddress inProcess:process];
			if (instruction == nil)
			{
				break;
			}
			
			[newInstructions addObject:instruction];
			
			// Read base pointer
			void *basePointerBytes = NULL;
			ZGMemorySize basePointerSize = process.pointerSize;
			if (!ZGReadBytes(process.processTask, basePointer, &basePointerBytes, &basePointerSize))
			{
				break;
			}
			
			switch (basePointerSize)
			{
				case sizeof(ZGMemoryAddress):
					basePointer = *(ZGMemoryAddress *)basePointerBytes;
					break;
				case sizeof(ZG32BitMemoryAddress):
					basePointer = *(ZG32BitMemoryAddress *)basePointerBytes;
					break;
				default:
					basePointer = 0;
			}
			
			[newBasePointers addObject:@(basePointer)];
			
			ZGFreeBytes(process.processTask, basePointerBytes, basePointerSize);
		}
	}
	
	return @[newInstructions, newBasePointers];
}

- (void)updateBacktrace:(NSArray *)backtraceComponents
{
	self.instructions = [backtraceComponents objectAtIndex:0];
	self.basePointers = [backtraceComponents objectAtIndex:1];
	
	[self.tableView reloadData];
	if (self.instructions.count > 0)
	{
		self.shouldIgnoreTableSelection = YES;
		[self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
	}
}

- (IBAction)jumpToSelectedInstruction:(id)sender
{
	if (self.tableView.selectedRowIndexes.count > 0 && (NSUInteger)self.tableView.selectedRow < self.instructions.count)
	{
		if (self.debuggerController.disassembling)
		{
			NSBeep();
		}
		else
		{
			ZGInstruction *selectedInstruction = [self.instructions objectAtIndex:(NSUInteger)self.tableView.selectedRow];
			[self.debuggerController jumpToMemoryAddress:selectedInstruction.variable.address inProcess:self.debuggerController.currentProcess];
		}
	}
}

#pragma mark Table View

- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard
{
	NSArray *variables = [[self.instructions objectsAtIndexes:rowIndexes] valueForKey:@"variable"];
	return [pboard setData:[NSKeyedArchiver archivedDataWithRootObject:variables] forType:ZGVariablePboardType];
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
		if ([tableColumn.identifier isEqualToString:@"backtrace"])
		{
			result = instruction.variable.description;
		}
	}
	
	return result;
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	// we should only ignore selection on the first row
	if (self.shouldIgnoreTableSelection && ![[self.tableView selectedRowIndexes] isEqualToIndexSet:[NSIndexSet indexSetWithIndex:0]])
	{
		self.shouldIgnoreTableSelection = NO;
	}
	
	if (!self.shouldIgnoreTableSelection)
	{
		[self jumpToSelectedInstruction:nil];
	}
	else
	{
		self.shouldIgnoreTableSelection = NO;
	}
}

- (BOOL)selectionShouldChangeInTableView:(NSTableView *)aTableView
{
	return !self.debuggerController.disassembling;
}

#pragma mark Menu Item Validation

- (BOOL)validateUserInterfaceItem:(NSMenuItem *)menuItem
{
	if ([menuItem action] == @selector(showMemoryViewer:))
	{
		if ([[self selectedInstructions] count] == 0)
		{
			return NO;
		}
	}
	else if ([menuItem action] == @selector(copy:))
	{
		if ([[self selectedInstructions] count] == 0)
		{
			return NO;
		}
	}
	else if ([menuItem action] == @selector(copyAddress:))
	{
		if ([[self selectedInstructions] count] != 1)
		{
			return NO;
		}
	}
	
	return YES;
}

#pragma mark Copy

- (NSArray *)selectedInstructions
{
	NSIndexSet *tableIndexSet = self.tableView.selectedRowIndexes;
	NSInteger clickedRow = self.tableView.clickedRow;
	
	NSIndexSet *selectionIndexSet = (clickedRow != -1 && ![tableIndexSet containsIndex:clickedRow]) ? [NSIndexSet indexSetWithIndex:clickedRow] : tableIndexSet;
	
	return [self.instructions objectsAtIndexes:selectionIndexSet];
}

- (IBAction)copy:(id)sender
{
	NSMutableArray *descriptionComponents = [[NSMutableArray alloc] init];
	NSMutableArray *variablesArray = [[NSMutableArray alloc] init];
	
	for (ZGInstruction *instruction in self.selectedInstructions)
	{
		[descriptionComponents addObject:[@[instruction.text, instruction.symbols, instruction.variable.stringValue] componentsJoinedByString:@"\t"]];
		[variablesArray addObject:instruction.variable];
	}
	
	[[NSPasteboard generalPasteboard] declareTypes:@[NSStringPboardType, ZGVariablePboardType] owner:self];
	[[NSPasteboard generalPasteboard] setString:[descriptionComponents componentsJoinedByString:@"\n"] forType:NSStringPboardType];
	[[NSPasteboard generalPasteboard] setData:[NSKeyedArchiver archivedDataWithRootObject:variablesArray] forType:ZGVariablePboardType];
}

- (IBAction)copyAddress:(id)sender
{
	ZGInstruction *selectedInstruction = [self.selectedInstructions objectAtIndex:0];
	[[NSPasteboard generalPasteboard] declareTypes:@[NSStringPboardType] owner:self];
	[[NSPasteboard generalPasteboard] setString:selectedInstruction.variable.addressStringValue	forType:NSStringPboardType];
}

#pragma mark Memory Viewer

- (IBAction)showMemoryViewer:(id)sender
{
	ZGInstruction *selectedInstruction = [[self selectedInstructions] objectAtIndex:0];
	[[[ZGAppController sharedController] memoryViewer] jumpToMemoryAddress:selectedInstruction.variable.address withSelectionLength:selectedInstruction.variable.size inProcess:self.debuggerController.currentProcess];
}

@end
