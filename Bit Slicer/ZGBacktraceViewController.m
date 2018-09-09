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

#import "ZGBacktraceViewController.h"
#import "ZGVirtualMemory.h"
#import "ZGProcess.h"
#import "ZGInstruction.h"
#import "ZGVariable.h"
#import "ZGMemoryViewerController.h"
#import "ZGBacktrace.h"
#import "NSArrayAdditions.h"

@implementation ZGBacktraceViewController
{
	__weak id <ZGBacktraceViewControllerDelegate> _Nullable _delegate;
	BOOL _shouldIgnoreTableSelection;
	
	IBOutlet NSTableView *_tableView;
}

#pragma mark Birth

- (id)initWithDelegate:(id <ZGBacktraceViewControllerDelegate>)delegate
{
	self = [super initWithNibName:@"Backtrace View" bundle:nil];
	if (self != nil)
	{
		_delegate = delegate;
	}
	return self;
}

- (void)loadView
{
	[super loadView];
	
	_tableView.target = self;
	_tableView.doubleAction = @selector(changeInstructionSelection:);
	
	[_tableView registerForDraggedTypes:@[ZGVariablePboardType]];
}

#pragma mark Backtrace

- (void)setBacktrace:(ZGBacktrace *)backtrace
{
	_backtrace = backtrace;
	
	[_tableView reloadData];
	if (_backtrace.instructions.count > 0)
	{
		_shouldIgnoreTableSelection = YES;
		[_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
	}
}

- (IBAction)changeInstructionSelection:(id)__unused sender
{
	if (_tableView.selectedRowIndexes.count > 0 && (NSUInteger)_tableView.selectedRow < _backtrace.instructions.count)
	{
		ZGInstruction *selectedInstruction = [_backtrace.instructions objectAtIndex:(NSUInteger)_tableView.selectedRow];
		id <ZGBacktraceViewControllerDelegate> delegate = _delegate;
		[delegate backtraceSelectionChangedToAddress:selectedInstruction.variable.address];
	}
}

#pragma mark Table View

- (BOOL)tableView:(NSTableView *)__unused tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard
{
	NSArray<ZGVariable *> *variables = [[_backtrace.instructions objectsAtIndexes:rowIndexes] zgMapUsingBlock:^(ZGInstruction *instruction) {
		return instruction.variable;
	}];
	return [pboard setData:[NSKeyedArchiver archivedDataWithRootObject:variables] forType:ZGVariablePboardType];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)__unused tableView
{
	return (NSInteger)_backtrace.instructions.count;
}

- (id)tableView:(NSTableView *)__unused tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	id result = nil;
	if (rowIndex >= 0 && (NSUInteger)rowIndex < _backtrace.instructions.count)
	{
		ZGInstruction *instruction = [_backtrace.instructions objectAtIndex:(NSUInteger)rowIndex];
		if ([tableColumn.identifier isEqualToString:@"backtrace"])
		{
			result = instruction.variable.fullAttributedDescription;
		}
	}
	
	return result;
}

- (void)tableViewSelectionDidChange:(NSNotification *)__unused aNotification
{
	// we should only ignore selection on the first row
	if (_shouldIgnoreTableSelection && ![[_tableView selectedRowIndexes] isEqualToIndexSet:[NSIndexSet indexSetWithIndex:0]])
	{
		_shouldIgnoreTableSelection = NO;
	}
	
	if (!_shouldIgnoreTableSelection)
	{
		[self changeInstructionSelection:nil];
	}
	else
	{
		_shouldIgnoreTableSelection = NO;
	}
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

- (NSArray<ZGInstruction *> *)selectedInstructions
{
	NSIndexSet *tableIndexSet = _tableView.selectedRowIndexes;
	NSInteger clickedRow = _tableView.clickedRow;
	
	NSIndexSet *selectionIndexSet = (clickedRow >= 0 && ![tableIndexSet containsIndex:(NSUInteger)clickedRow]) ? [NSIndexSet indexSetWithIndex:(NSUInteger)clickedRow] : tableIndexSet;
	
	return [_backtrace.instructions objectsAtIndexes:selectionIndexSet];
}

#pragma mark Actions

- (IBAction)copy:(id)__unused sender
{
	NSMutableArray<NSString *> *descriptionComponents = [[NSMutableArray alloc] init];
	NSMutableArray<ZGVariable *> *variablesArray = [[NSMutableArray alloc] init];
	
	for (ZGInstruction *instruction in [self selectedInstructions])
	{
		[descriptionComponents addObject:[@[instruction.variable.addressStringValue, instruction.text, instruction.variable.stringValue] componentsJoinedByString:@"\t"]];
		[variablesArray addObject:instruction.variable];
	}
	
	[[NSPasteboard generalPasteboard] declareTypes:@[NSStringPboardType, ZGVariablePboardType] owner:self];
	[[NSPasteboard generalPasteboard] setString:[descriptionComponents componentsJoinedByString:@"\n"] forType:NSStringPboardType];
	[[NSPasteboard generalPasteboard] setData:[NSKeyedArchiver archivedDataWithRootObject:variablesArray] forType:ZGVariablePboardType];
}

- (IBAction)copyAddress:(id)__unused sender
{
	ZGInstruction *selectedInstruction = [[self selectedInstructions] objectAtIndex:0];
	
	[[NSPasteboard generalPasteboard] declareTypes:@[NSStringPboardType] owner:self];
	[[NSPasteboard generalPasteboard] setString:selectedInstruction.variable.addressStringValue	forType:NSStringPboardType];
}

- (IBAction)showMemoryViewer:(id)__unused sender
{
	ZGInstruction *selectedInstruction = [[self selectedInstructions] objectAtIndex:0];
	
	id <ZGBacktraceViewControllerDelegate> delegate = _delegate;
	id <ZGShowMemoryWindow> showMemoryWindowController =  delegate.delegate;
	[showMemoryWindowController showMemoryViewerWindowWithProcess:_process address:selectedInstruction.variable.address selectionLength:selectedInstruction.variable.size];
}

@end
