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

@interface ZGBacktraceController ()

@property (assign) IBOutlet ZGDisassemblerController *disassemblerController;

@end

@implementation ZGBacktraceController

#pragma mark Birth

- (void)awakeFromNib
{
	self.tableView.target = self;
	self.tableView.doubleAction = @selector(jumpToSelectedInstruction:);
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
	
	[self.tableView reloadData];
	if (self.instructions.count > 0)
	{
		[self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
	}
}

- (IBAction)jumpToSelectedInstruction:(id)sender
{
	if (self.tableView.selectedRowIndexes.count > 0 && (NSUInteger)self.tableView.selectedRow < self.instructions.count)
	{
		ZGInstruction *selectedInstruction = [self.instructions objectAtIndex:(NSUInteger)self.tableView.selectedRow];
		[self.disassemblerController jumpToMemoryAddress:selectedInstruction.variable.address inProcess:self.disassemblerController.currentProcess];
	}
}

#pragma mark Table View

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
			if (instruction.symbols && ![instruction.symbols isEqualToString:@""])
			{
				result = instruction.symbols;
			}
			else
			{
				result = instruction.variable.addressStringValue;
			}
		}
	}
	
	return result;
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	[self jumpToSelectedInstruction:nil];
}

- (BOOL)selectionShouldChangeInTableView:(NSTableView *)aTableView
{
	return !self.disassemblerController.disassembling;
}

@end
