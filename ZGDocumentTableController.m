/*
 * Created by Mayur Pawashe on 7/21/12.
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

#import "ZGDocumentTableController.h"
#import "ZGDocument.h"
#import "ZGDocumentSearchController.h"
#import "ZGVariableController.h"
#import "ZGProcess.h"
#import "ZGSearchProgress.h"
#import "ZGCalculator.h"
#import "ZGVariable.h"
#import "NSStringAdditions.h"
#import "ZGSearchProgress.h"

@interface ZGDocumentTableController ()

@property (assign) IBOutlet ZGDocument *document;
@property (readwrite, strong, nonatomic) NSTimer *watchVariablesTimer;

@end

@implementation ZGDocumentTableController

#define ZGVariableReorderType @"ZGVariableReorderType"

#define WATCH_VARIABLES_UPDATE_TIME_INTERVAL 0.1

#pragma mark Birth & Death

- (void)awakeFromNib
{
	[self.watchVariablesTableView registerForDraggedTypes:@[ZGVariableReorderType, ZGVariablePboardType]];
	self.watchVariablesTimer =
		[NSTimer
		 scheduledTimerWithTimeInterval:WATCH_VARIABLES_UPDATE_TIME_INTERVAL
		 target:self
		 selector:@selector(updateWatchVariablesTable:)
		 userInfo:nil
		 repeats:YES];
}

- (void)cleanUp
{
	[self.watchVariablesTimer invalidate];
	self.watchVariablesTimer = nil;
	
	self.document = nil;
	self.watchVariablesTableView = nil;
}

#pragma mark Updating Table

- (void)updateWatchVariablesTable:(NSTimer *)timer
{
	if (!self.document.windowForSheet.isVisible)
	{
		return;
	}
    
	// First, update all the variable's addresses that are pointers
	// We don't want to update this when the user is editing something in the table
	if (self.document.currentProcess.valid && self.watchVariablesTableView.editedRow == -1)
	{
		[self.document.watchVariablesArray enumerateObjectsUsingBlock:^(ZGVariable * __unsafe_unretained variable, NSUInteger index, BOOL *stop)
		 {
			 if (variable.isPointer)
			 {
				 NSString *newAddressString =
					[ZGCalculator
					 evaluateAddress:[NSMutableString stringWithString:variable.addressFormula]
					 process:self.document.currentProcess];
				 
				 if (variable.address != newAddressString.zgUnsignedLongLongValue)
				 {
					 variable.addressStringValue = newAddressString;
					 [self.watchVariablesTableView reloadData];
				 }
			 }
			 
			 if (index >= MAX_TABLE_VIEW_ITEMS - 1)
			 {
				 *stop = YES;
			 }
		 }];
	}
	
	// Then check that the process is alive
	if (self.document.currentProcess.valid)
	{
		// Freeze all variables that need be frozen!
		[self.document.watchVariablesArray enumerateObjectsUsingBlock:^(ZGVariable * __unsafe_unretained variable, NSUInteger index, BOOL *stop)
		 {
			 if (variable.isFrozen && variable.freezeValue)
			 {
				 if (variable.size)
				 {
					 ZGWriteBytesIgnoringProtection(self.document.currentProcess.processTask, variable.address, variable.freezeValue, variable.size);
				 }
				 
				 if (variable.type == ZGUTF16String)
				 {
					 unichar terminatorValue = 0;
					 ZGWriteBytesIgnoringProtection(self.document.currentProcess.processTask, variable.address + variable.size, &terminatorValue, sizeof(unichar));
				 }
			 }
			 
			 if (index >= MAX_TABLE_VIEW_ITEMS - 1)
			 {
				 *stop = YES;
			 }
		 }];
	}
	
	// if any variables are changing, that means that we'll have to reload the table, and that'd be very bad
	// if the user is in the process of editing a variable's value, so don't do it then
	if (self.document.currentProcess.valid && self.watchVariablesTableView.editedRow == -1)
	{
		// Read all the variables and update them in the table view if needed
		NSRange visibleRowsRange = [self.watchVariablesTableView rowsInRect:self.watchVariablesTableView.visibleRect];
		
		if (visibleRowsRange.location + visibleRowsRange.length <= self.document.watchVariablesArray.count)
		{
			[[self.document.watchVariablesArray subarrayWithRange:visibleRowsRange] enumerateObjectsUsingBlock:^(ZGVariable *variable, NSUInteger index, BOOL *stop)
			 {
				 NSString *oldStringValue = [variable.stringValue copy];
				 if (!(variable.isFrozen && variable.freezeValue) && (variable.type == ZGUTF8String || variable.type == ZGUTF16String))
				 {
					 variable.size = ZGGetStringSize(self.document.currentProcess.processTask, variable.address, variable.type, variable.size);
				 }
				 
				 if (variable.size)
				 {
					 ZGMemorySize outputSize = variable.size;
					 void *value = NULL;
					 
					 if (ZGReadBytes(self.document.currentProcess.processTask, variable.address, &value, &outputSize))
					 {
						 variable.value = value;
						 if (![variable.stringValue isEqualToString:oldStringValue])
						 {
							 [self.watchVariablesTableView reloadData];
						 }
						 
						 ZGFreeBytes(self.document.currentProcess.processTask, value, outputSize);
					 }
					 else if (variable.value)
					 {
						 variable.value = NULL;
						 [self.watchVariablesTableView reloadData];
					 }
				 }
				 else if (variable.lastUpdatedSize)
				 {
					 variable.value = NULL;
					 [self.watchVariablesTableView reloadData];
				 }
				 
				 variable.lastUpdatedSize = variable.size;
			 }];
		}
	}
}

#pragma mark Table View Drag & Drop

- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id <NSDraggingInfo>)draggingInfo proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation
{
	if ([draggingInfo draggingSource] == self.watchVariablesTableView && [draggingInfo.draggingPasteboard.types containsObject:ZGVariableReorderType] && operation != NSTableViewDropOn)
	{
		return NSDragOperationMove;
	}
	else if ([draggingInfo.draggingPasteboard.types containsObject:ZGVariablePboardType] && operation != NSTableViewDropOn)
	{
		return NSDragOperationCopy;
	}
	
	return NSDragOperationNone;
}

- (void)reorderVariables:(NSArray *)newVariables
{
	self.document.undoManager.actionName = @"Move";
	[[self.document.undoManager prepareWithInvocationTarget:self] reorderVariables:self.document.watchVariablesArray];
	
	self.document.watchVariablesArray = [NSArray arrayWithArray:newVariables];
	
	[self.watchVariablesTableView reloadData];
}

- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id <NSDraggingInfo>)draggingInfo  row:(NSInteger)newRow dropOperation:(NSTableViewDropOperation)operation
{
	if ([draggingInfo draggingSource] == self.watchVariablesTableView && [draggingInfo.draggingPasteboard.types containsObject:ZGVariableReorderType])
	{
		NSMutableArray *variables = [NSMutableArray arrayWithArray:self.document.watchVariablesArray];
		NSArray *rows = [draggingInfo.draggingPasteboard propertyListForType:ZGVariableReorderType];
		
		// Fill in the current rows with null objects
		for (NSNumber *row in rows)
		{
			[variables
			 replaceObjectAtIndex:row.integerValue
			 withObject:NSNull.null];
		}
		
		// Insert the objects to the new position
		for (NSNumber *row in rows)
		{
			[variables
			 insertObject:[self.document.watchVariablesArray objectAtIndex:row.integerValue]
			 atIndex:newRow];
			
			newRow++;
		}
		
		// Remove all the old objects
		[variables removeObject:NSNull.null];
		
		// Set the new variables
		[self reorderVariables:variables];
	}
	else if ([draggingInfo.draggingPasteboard.types containsObject:ZGVariablePboardType])
	{
		NSArray *variables = [NSKeyedUnarchiver unarchiveObjectWithData:[[draggingInfo draggingPasteboard] dataForType:ZGVariablePboardType]];
		
		NSMutableIndexSet *rowIndexes = [NSMutableIndexSet indexSet];
		for (NSUInteger rowIndex = 0; rowIndex < variables.count; rowIndex++)
		{
			[rowIndexes addIndex:newRow + rowIndex];
		}
		
		[self.document.variableController addVariables:variables atRowIndexes:rowIndexes];
	}
	
	return YES;
}

- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pasteboard
{
	[pasteboard declareTypes:@[ZGVariableReorderType, ZGVariablePboardType] owner:self];
	
	NSMutableArray *rows = [[NSMutableArray alloc] init];
	[rowIndexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
		[rows addObject:@(index)];
	}];
	[pasteboard  setPropertyList:[NSArray arrayWithArray:rows] forType:ZGVariableReorderType];
	
	NSArray *variables = [self.document.watchVariablesArray objectsAtIndexes:rowIndexes];
	[pasteboard setData:[NSKeyedArchiver archivedDataWithRootObject:variables] forType:ZGVariablePboardType];
	
	return YES;
}

#pragma mark Table View Data Source Methods

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if (tableView == self.watchVariablesTableView && rowIndex >= 0 && (NSUInteger)rowIndex < self.document.watchVariablesArray.count)
	{
		if ([tableColumn.identifier isEqualToString:@"name"])
		{
			return [[[self.document watchVariablesArray] objectAtIndex:rowIndex] name];
		}
		else if ([tableColumn.identifier isEqualToString:@"address"])
		{
			return [[[self.document watchVariablesArray] objectAtIndex:rowIndex] addressStringValue];
		}
		else if ([tableColumn.identifier isEqualToString:@"value"])
		{
			return [[[self.document watchVariablesArray] objectAtIndex:rowIndex] stringValue];
		}
		else if ([tableColumn.identifier isEqualToString:@"shouldBeSearched"])
		{
			return @([[self.document.watchVariablesArray objectAtIndex:rowIndex] shouldBeSearched]);
		}
		else if ([tableColumn.identifier isEqualToString:@"type"])
		{
			ZGVariableType type = [(ZGVariable *)[self.document.watchVariablesArray objectAtIndex:rowIndex] type];
			return @([[tableColumn dataCell] indexOfItemWithTag:type]);
		}
	}
	
	return nil;
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if (tableView == self.watchVariablesTableView && rowIndex >= 0 && (NSUInteger)rowIndex < self.document.watchVariablesArray.count)
	{
		if ([tableColumn.identifier isEqualToString:@"name"])
		{
			[self.document.variableController
			 changeVariable:[self.document.watchVariablesArray objectAtIndex:rowIndex]
			 newName:object];
		}
		else if ([tableColumn.identifier isEqualToString:@"address"])
		{
			[self.document.variableController
			 changeVariable:[self.document.watchVariablesArray objectAtIndex:rowIndex]
			 newAddress:object];
		}
		else if ([tableColumn.identifier isEqualToString:@"value"])
		{
			[self.document.variableController
			 changeVariable:[self.document.watchVariablesArray objectAtIndex:rowIndex]
			 newValue:object
			 shouldRecordUndo:YES];
		}
		else if ([tableColumn.identifier isEqualToString:@"shouldBeSearched"])
		{
			[self.document.variableController
			 changeVariableShouldBeSearched:[object boolValue]
			 rowIndexes:self.document.selectedVariableIndexes];
		}
		else if ([tableColumn.identifier isEqualToString:@"type"])
		{
			[self.document.variableController
			 changeVariable:[self.document.watchVariablesArray objectAtIndex:rowIndex]
			 newType:(ZGVariableType)[[[tableColumn.dataCell itemArray] objectAtIndex:[object unsignedIntegerValue]] tag]
			 newSize:[(ZGVariable *)[self.document.watchVariablesArray objectAtIndex:rowIndex] size]];
		}
	}
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return MIN(MAX_TABLE_VIEW_ITEMS, self.document.watchVariablesArray.count);
}

#pragma mark Table View Delegate Methods

- (BOOL)selectionShouldChangeInTableView:(NSTableView *)aTableView
{
	if (self.shouldIgnoreTableViewSelectionChange)
	{
		self.shouldIgnoreTableViewSelectionChange = NO;
		return NO;
	}
	
	return YES;
}

- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if ([tableColumn.identifier isEqualToString:@"value"])
	{
		if ((![self.document.searchController canStartTask] && !self.document.searchController.searchProgress.isWatchingBreakPoint) || !self.document.currentProcess.valid)
		{
			NSBeep();
			return NO;
		}
        
		if (rowIndex >= 0 && (NSUInteger)rowIndex < self.document.watchVariablesArray.count)
		{
			ZGVariable *variable = [self.document.watchVariablesArray objectAtIndex:rowIndex];
			if (!variable)
			{
				return NO;
			}
			
			ZGMemoryProtection memoryProtection = 0;
			ZGMemoryAddress memoryAddress = [variable address];
			ZGMemorySize memorySize = [variable size];
			
			if (ZGMemoryProtectionInRegion(self.document.currentProcess.processTask, &memoryAddress, &memorySize, &memoryProtection))
			{
				// if the variable is within a single memory region and the memory region is not readable, then don't allow the variable to be writable
				// if it is not writable, our value changing methods will try to change the protection attributes before modifying the data
				if (memoryAddress <= variable.address && memoryAddress + memorySize >= variable.address + variable.size && !(memoryProtection & VM_PROT_READ))
				{
					NSBeep();
					return NO;
				}
			}
		}
	}
	else if ([tableColumn.identifier isEqualToString:@"address"])
	{
		if (rowIndex < 0 || (NSUInteger)rowIndex >= self.document.watchVariablesArray.count)
		{
			return NO;
		}
		
		ZGVariable *variable = [self.document.watchVariablesArray objectAtIndex:rowIndex];
		if (variable.isPointer)
		{
			[self.document editVariablesAddress:nil];
			return NO;
		}
	}
	
	return YES;
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if ([tableColumn.identifier isEqualToString:@"value"])
	{
		if (rowIndex >= 0 && (NSUInteger)rowIndex < self.document.watchVariablesArray.count)
		{
			[cell setTextColor:[[self.document.watchVariablesArray objectAtIndex:rowIndex] isFrozen] ? NSColor.redColor : NSColor.textColor];
		}
	}
}

- (NSString *)tableView:(NSTableView *)aTableView toolTipForCell:(NSCell *)aCell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)row mouseLocation:(NSPoint)mouseLocation
{
	NSMutableArray *displayComponents = [[NSMutableArray alloc] init];
	
	if (row >= 0 && (NSUInteger)row < self.document.watchVariablesArray.count)
	{
		ZGVariable *variable = [self.document.watchVariablesArray objectAtIndex:row];
		
		if (variable.name && ![variable.name isEqualToString:@""])
		{
			[displayComponents addObject:[NSString stringWithFormat:@"Name: %@", variable.name]];
		}
		if (variable.value)
		{
			[displayComponents addObject:[NSString stringWithFormat:@"Value: %@", variable.stringValue]];
		}
		[displayComponents addObject:[NSString stringWithFormat:@"Address: %@", variable.addressFormula]];
		[displayComponents addObject:[NSString stringWithFormat:@"Bytes: %@", variable.sizeStringValue]];
		
		if (self.document.currentProcess.valid)
		{
			ZGMemoryAddress memoryProtectionAddress = variable.address;
			ZGMemorySize memoryProtectionSize = variable.size;
			ZGMemoryProtection memoryProtection;
			if (ZGMemoryProtectionInRegion(self.document.currentProcess.processTask, &memoryProtectionAddress, &memoryProtectionSize, &memoryProtection))
			{
				if (variable.address >= memoryProtectionAddress && variable.address + variable.size <= memoryProtectionAddress + memoryProtectionSize)
				{
					NSMutableArray *protectionComponents = [[NSMutableArray alloc] init];
					if (memoryProtection & VM_PROT_READ) [protectionComponents addObject:@"Read"];
					if (memoryProtection & VM_PROT_WRITE) [protectionComponents addObject:@"Write"];
					if (memoryProtection & VM_PROT_EXECUTE) [protectionComponents addObject:@"Execute"];
					
					if (protectionComponents.count > 0)
					{
						[displayComponents addObject:[NSString stringWithFormat:@"Protection: %@", [protectionComponents componentsJoinedByString:@" | "]]];
					}
				}
			}
		}
	}
	
	NSString *valuesDisplayedString = @"";
	
	NSNumberFormatter *numberOfVariablesFormatter = [[NSNumberFormatter alloc] init];
	numberOfVariablesFormatter.format = @"#,###";
	
	if (self.document.watchVariablesArray.count <= MAX_TABLE_VIEW_ITEMS)
	{
		valuesDisplayedString = [NSString stringWithFormat:@"Displaying %@ value", [numberOfVariablesFormatter stringFromNumber:@(self.document.watchVariablesArray.count)]];
	}
	else
	{
		valuesDisplayedString = [NSString stringWithFormat:@"Displaying %@ of %@ value", [numberOfVariablesFormatter stringFromNumber:@(MAX_TABLE_VIEW_ITEMS)],[numberOfVariablesFormatter stringFromNumber:@(self.document.watchVariablesArray.count)]];
	}
	
	if (valuesDisplayedString && self.document.watchVariablesArray.count != 1)
	{
		valuesDisplayedString = [valuesDisplayedString stringByAppendingString:@"s"];
	}
	
	if (displayComponents.count > 0)
	{
		[displayComponents addObject:@""];
	}
	[displayComponents addObject:valuesDisplayedString];
	
	return [displayComponents componentsJoinedByString:@"\n"];
}

@end
