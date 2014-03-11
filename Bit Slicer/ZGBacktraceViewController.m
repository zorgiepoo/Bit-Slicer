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
#import "ZGMemoryViewerController.h"
#import "ZGBacktrace.h"

@interface ZGBacktraceViewController ()

@property (nonatomic, weak) id <ZGBacktraceViewControllerDelegate> delegate;

@property (nonatomic, assign) IBOutlet NSTableView *tableView;

@property (assign, nonatomic) BOOL shouldIgnoreTableSelection;

@end

@implementation ZGBacktraceViewController

#pragma mark Birth

- (id)initWithDelegate:(id <ZGBacktraceViewControllerDelegate>)delegate
{
	self = [super initWithNibName:NSStringFromClass([self class]) bundle:nil];
	if (self != nil)
	{
		self.delegate = delegate;
	}
	return self;
}

- (void)loadView
{
	[super loadView];
	
	self.tableView.target = self;
	self.tableView.doubleAction = @selector(changeInstructionSelection:);
	
	[self setNextResponder:[self.tableView nextResponder]];
	[self.tableView setNextResponder:self];
	
	[self.tableView registerForDraggedTypes:@[ZGVariablePboardType]];
}

#pragma mark Backtrace

- (void)setBacktrace:(ZGBacktrace *)backtrace
{
	_backtrace = backtrace;
	
	[self.tableView reloadData];
	if (self.backtrace.instructions.count > 0)
	{
		self.shouldIgnoreTableSelection = YES;
		[self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
	}
}

- (IBAction)changeInstructionSelection:(id)sender
{
	if (self.tableView.selectedRowIndexes.count > 0 && (NSUInteger)self.tableView.selectedRow < self.backtrace.instructions.count)
	{
		ZGInstruction *selectedInstruction = [self.backtrace.instructions objectAtIndex:(NSUInteger)self.tableView.selectedRow];
		[self.delegate backtraceSelectionChangedToAddress:selectedInstruction.variable.address];
	}
}

#pragma mark Table View

- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard
{
	NSArray *variables = [[self.backtrace.instructions objectsAtIndexes:rowIndexes] valueForKey:@"variable"];
	return [pboard setData:[NSKeyedArchiver archivedDataWithRootObject:variables] forType:ZGVariablePboardType];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return self.backtrace.instructions.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	id result = nil;
	if (rowIndex >= 0 && (NSUInteger)rowIndex < self.backtrace.instructions.count)
	{
		ZGInstruction *instruction = [self.backtrace.instructions objectAtIndex:rowIndex];
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
		[self changeInstructionSelection:nil];
	}
	else
	{
		self.shouldIgnoreTableSelection = NO;
	}
}

- (BOOL)selectionShouldChangeInTableView:(NSTableView *)aTableView
{
	return [self.delegate backtraceSelectionShouldChange];
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

#pragma mark Selection

- (NSArray *)selectedInstructions
{
	NSIndexSet *tableIndexSet = self.tableView.selectedRowIndexes;
	NSInteger clickedRow = self.tableView.clickedRow;
	
	NSIndexSet *selectionIndexSet = (clickedRow != -1 && ![tableIndexSet containsIndex:clickedRow]) ? [NSIndexSet indexSetWithIndex:clickedRow] : tableIndexSet;
	
	return [self.backtrace.instructions objectsAtIndexes:selectionIndexSet];
}

@end
