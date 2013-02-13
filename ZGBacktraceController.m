/*
 * Created by Mayur Pawashe on 2/6/13.
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

#import "ZGBacktraceController.h"
#import "ZGDisassemblerController.h"
#import "ZGVirtualMemory.h"
#import "ZGProcess.h"
#import "ZGInstruction.h"
#import "ZGVariable.h"
#import "ZGAppController.h"
#import "ZGMemoryViewer.h"

@interface ZGBacktraceController ()

@property (assign) IBOutlet ZGDisassemblerController *disassemblerController;

@property (assign, nonatomic) BOOL shouldIgnoreTableSelection;

@end

@implementation ZGBacktraceController

#pragma mark Birth

- (void)awakeFromNib
{
	self.tableView.target = self;
	self.tableView.doubleAction = @selector(jumpToSelectedInstruction:);
	
	[self setNextResponder:[self.tableView nextResponder]];
	[self.tableView setNextResponder:self];
	
	[self.tableView registerForDraggedTypes:@[ZGVariablePboardType]];
}

#pragma mark Updating Backtrace

- (void)updateBacktraceWithBasePointer:(ZGMemoryAddress)basePointer instructionPointer:(ZGMemoryAddress)instructionPointer inProcess:(ZGProcess *)process
{
	NSMutableArray *newInstructions = [[NSMutableArray alloc] init];
	NSMutableArray *newBasePointers = [[NSMutableArray alloc] init];
	
	ZGInstruction *currentInstruction = [self.disassemblerController findInstructionBeforeAddress:instructionPointer+1 inProcess:process];
	if (currentInstruction)
	{
		[newInstructions addObject:currentInstruction];
		[newBasePointers addObject:@(basePointer)];
		
		while (basePointer > 0)
		{
			// Read return address
			void *bytes = NULL;
			ZGMemorySize size = process.pointerSize;
			if (ZGReadBytes(process.processTask, basePointer + process.pointerSize, &bytes, &size))
			{
				ZGMemoryAddress returnAddress = 0;
				memcpy(&returnAddress, bytes, size);
				
				ZGFreeBytes(process.processTask, bytes, size);
				
				ZGInstruction *instruction = [self.disassemblerController findInstructionBeforeAddress:returnAddress inProcess:process];
				if (instruction)
				{
					[newInstructions addObject:instruction];
					
					// Read base pointer
					bytes = NULL;
					size = process.pointerSize;
					if (ZGReadBytes(process.processTask, basePointer, &bytes, &size))
					{
						basePointer = 0;
						memcpy(&basePointer, bytes, size);
						
						[newBasePointers addObject:@(basePointer)];
						
						ZGFreeBytes(process.processTask, bytes, size);
					}
					else
					{
						break;
					}
				}
				else
				{
					break;
				}
			}
			else
			{
				break;
			}
		}
	}
	
	self.instructions = [NSArray arrayWithArray:newInstructions];
	self.basePointers = [NSArray arrayWithArray:newBasePointers];
	
	[self.disassemblerController updateSymbolsForInstructions:self.instructions];
	
	for (ZGInstruction *instruction in self.instructions)
	{
		if (!instruction.symbols || [instruction.symbols isEqualToString:@""])
		{
			instruction.symbols = @"";
			instruction.variable.name = instruction.variable.addressStringValue;
		}
		else
		{
			instruction.variable.name = instruction.symbols;
		}
	}
	
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
		if (self.disassemblerController.disassembling)
		{
			NSBeep();
		}
		else
		{
			ZGInstruction *selectedInstruction = [self.instructions objectAtIndex:(NSUInteger)self.tableView.selectedRow];
			[self.disassemblerController jumpToMemoryAddress:selectedInstruction.variable.address inProcess:self.disassemblerController.currentProcess];
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
			result = instruction.variable.name;
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
	return !self.disassemblerController.disassembling;
}

#pragma mark Menu Item Validation

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
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
	[[[ZGAppController sharedController] memoryViewer] showWindow:self];
	[[[ZGAppController sharedController] memoryViewer] jumpToMemoryAddress:selectedInstruction.variable.address withSelectionLength:selectedInstruction.variable.size inProcess:self.disassemblerController.currentProcess];
}

@end
