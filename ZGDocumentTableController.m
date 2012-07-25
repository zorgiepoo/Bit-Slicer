/*
 * This file is part of Bit Slicer.
 *
 * Bit Slicer is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 
 * Bit Slicer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 
 * You should have received a copy of the GNU General Public License
 * along with Bit Slicer.  If not, see <http://www.gnu.org/licenses/>.
 * 
 * Created by Mayur Pawashe on 7/21/12.
 * Copyright 2012 zgcoder. All rights reserved.
 */

#import "ZGDocumentTableController.h"
#import "ZGDocument.h"
#import "ZGDocumentSearchController.h"
#import "ZGVariableController.h"
#import "ZGProcess.h"
#import "ZGCalculator.h"
#import "NSStringAdditions.h"

@implementation ZGDocumentTableController

@synthesize watchVariablesTableView;
@synthesize shouldIgnoreTableViewSelectionChange;

#define ZGVariableReorderType @"ZGVariableReorderType"

#pragma mark Birth

- (void)awakeFromNib
{
	[watchVariablesTableView registerForDraggedTypes:[NSArray arrayWithObject:ZGVariableReorderType]];
}

#pragma mark Updating Table

- (void)updateWatchVariablesTable:(NSTimer *)timer
{
	if (![[document windowForSheet] isVisible])
	{
		return;
	}
    
	// First, update all the variable's addresses that are pointers
	// We don't want to update this when the user is editing something in the table
	if ([[document currentProcess] processID] != NON_EXISTENT_PID_NUMBER && [watchVariablesTableView editedRow] == -1)
	{
		[[document watchVariablesArray] enumerateObjectsUsingBlock:^(id object, NSUInteger index, BOOL *stop)
		 {
			 ZGVariable *variable = object;
			 if (variable->isPointer)
			 {
				 NSString *newAddress =
				 [ZGCalculator
				  evaluateAddress:[NSMutableString stringWithString:[variable addressFormula]]
				  process:[document currentProcess]];
				 
				 if (variable->address != [newAddress unsignedLongLongValue])
				 {
					 [variable setAddressStringValue:newAddress];
					 [watchVariablesTableView reloadData];
				 }
			 }
		 }];
	}
	
	// Then check that the process is alive
	if ([[document currentProcess] processID] != NON_EXISTENT_PID_NUMBER)
	{
		// Freeze all variables that need be frozen!
		[[document watchVariablesArray] enumerateObjectsUsingBlock:^(id object, NSUInteger index, BOOL *stop)
		 {
			 ZGVariable *variable = object;
			 if (variable->isFrozen && variable->freezeValue)
			 {
				 if (variable->size)
				 {
					 ZGWriteBytes([[document currentProcess] processTask], variable->address, variable->freezeValue, variable->size);
				 }
				 
				 if (variable->type == ZGUTF16String)
				 {
					 unichar terminatorValue = 0;
					 ZGWriteBytes([[document currentProcess] processTask], variable->address + variable->size, &terminatorValue, sizeof(unichar));
				 }
			 }
		 }];
	}
	
	// if any variables are changing, that means that we'll have to reload the table, and that'd be very bad
	// if the user is in the process of editing a variable's value, so don't do it then
	if ([[document currentProcess] processID] != NON_EXISTENT_PID_NUMBER && [watchVariablesTableView editedRow] == -1)
	{
		// Read all the variables and update them in the table view if needed
		NSRange visibleRowsRange = [watchVariablesTableView rowsInRect:[watchVariablesTableView visibleRect]];
		
		if (visibleRowsRange.location + visibleRowsRange.length <= [[document watchVariablesArray] count])
		{
			[[[document watchVariablesArray] subarrayWithRange:visibleRowsRange] enumerateObjectsUsingBlock:^(ZGVariable *variable, NSUInteger index, BOOL *stop)
			 {
				 NSString *oldStringValue = [[variable stringValue] copy];
				 if (variable->type == ZGUTF8String || variable->type == ZGUTF16String)
				 {
					 variable->size = ZGGetStringSize([[document currentProcess] processTask], variable->address, variable->type);
				 }
				 
				 if (variable->size)
				 {
					 ZGMemorySize outputSize = variable->size;
					 void *value = NULL;
					 
					 if (ZGReadBytes([[document currentProcess] processTask], variable->address, &value, &outputSize))
					 {
						 [variable setVariableValue:value];
						 if (![[variable stringValue] isEqualToString:oldStringValue])
						 {
							 [watchVariablesTableView reloadData];
						 }
						 
						 ZGFreeBytes([[document currentProcess] processTask], value, outputSize);
					 }
					 else if (variable->value)
					 {
						 [variable setVariableValue:NULL];
						 [watchVariablesTableView reloadData];
					 }
				 }
				 else if (variable->lastUpdatedSize)
				 {
					 [variable setVariableValue:NULL];
					 [watchVariablesTableView reloadData];
				 }
				 
				 variable->lastUpdatedSize = variable->size;
				 
				 [oldStringValue release];
			 }];
		}
	}
}

#pragma mark Table View Drag & Drop

- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id <NSDraggingInfo>)draggingInfo proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation
{
	if ([[[draggingInfo draggingPasteboard] types] containsObject:ZGVariableReorderType] && operation != NSTableViewDropOn)
	{
		return NSDragOperationMove;
	}
	
	return NSDragOperationNone;
}

- (void)reorderVariables:(NSArray *)newVariables
{
	[[document undoManager] setActionName:@"Move"];
	[[[document undoManager] prepareWithInvocationTarget:self] reorderVariables:[document watchVariablesArray]];
	
	[document setWatchVariablesArray:[NSArray arrayWithArray:newVariables]];
	
	[watchVariablesTableView reloadData];
}

- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id <NSDraggingInfo>)draggingInfo  row:(NSInteger)newRow dropOperation:(NSTableViewDropOperation)operation
{	
	NSMutableArray *variables = [NSMutableArray arrayWithArray:[document watchVariablesArray]];
	NSArray *rows = [[draggingInfo draggingPasteboard] propertyListForType:ZGVariableReorderType];
	
	// Fill in the current rows with null objects
	for (NSNumber *row in rows)
	{
		[variables
		 replaceObjectAtIndex:[row integerValue]
		 withObject:[NSNull null]];
	}
	
	// Insert the objects to the new position
	for (NSNumber *row in rows)
	{
		[variables
		 insertObject:[[document watchVariablesArray] objectAtIndex:[row integerValue]]
		 atIndex:newRow];
		
		newRow++;
	}
	
	// Remove all the old objects
	[variables removeObject:[NSNull null]];
	
	// Set the new variables
	[self reorderVariables:variables];
	
	return YES;
}

- (BOOL)tableView:(NSTableView *)view writeRows:(NSArray *)rows toPasteboard:(NSPasteboard *)pasteboard
{
	[pasteboard declareTypes:[NSArray arrayWithObject:ZGVariableReorderType] owner:self];
	
	[pasteboard
	 setPropertyList:rows
	 forType:ZGVariableReorderType];
	
	return YES;
}

#pragma mark Table View Data Source Methods

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if (tableView == watchVariablesTableView && rowIndex >= 0 && (NSUInteger)rowIndex < [[document watchVariablesArray] count])
	{
		if ([[tableColumn identifier] isEqualToString:@"name"])
		{
			return [[[document watchVariablesArray] objectAtIndex:rowIndex] name];
		}
		else if ([[tableColumn identifier] isEqualToString:@"address"])
		{
			return [[[document watchVariablesArray] objectAtIndex:rowIndex] addressStringValue];
		}
		else if ([[tableColumn identifier] isEqualToString:@"value"])
		{
			return [[[document watchVariablesArray] objectAtIndex:rowIndex] stringValue];
		}
		else if ([[tableColumn identifier] isEqualToString:@"shouldBeSearched"])
		{
			return [NSNumber numberWithBool:[[[document watchVariablesArray] objectAtIndex:rowIndex] shouldBeSearched]];
		}
		else if ([[tableColumn identifier] isEqualToString:@"type"])
		{
			ZGVariableType type = ((ZGVariable *)[[document watchVariablesArray] objectAtIndex:rowIndex])->type;
			return [NSNumber numberWithInteger:[[tableColumn dataCell] indexOfItemWithTag:type]];
		}
	}
	
	return nil;
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if (tableView == watchVariablesTableView && rowIndex >= 0 && (NSUInteger)rowIndex < [[document watchVariablesArray] count])
	{
		if ([[tableColumn identifier] isEqualToString:@"name"])
		{
			[[document variableController]
			 changeVariable:[[document watchVariablesArray] objectAtIndex:rowIndex]
			 newName:object];
		}
		else if ([[tableColumn identifier] isEqualToString:@"address"])
		{
			[[document variableController]
			 changeVariable:[[document watchVariablesArray] objectAtIndex:rowIndex]
			 newAddress:object];
		}
		else if ([[tableColumn identifier] isEqualToString:@"value"])
		{
			[[document variableController]
			 changeVariable:[[document watchVariablesArray] objectAtIndex:rowIndex]
			 newValue:object
			 shouldRecordUndo:YES];
		}
		else if ([[tableColumn identifier] isEqualToString:@"shouldBeSearched"])
		{
			[[document variableController]
			 changeVariableShouldBeSearched:[object boolValue]
			 rowIndexes:[watchVariablesTableView selectedRowIndexes]];
		}
		else if (([[tableColumn identifier] isEqualToString:@"type"]))
		{
			[[document variableController]
			 changeVariable:[[document watchVariablesArray] objectAtIndex:rowIndex]
			 newType:(ZGVariableType)[[tableColumn dataCell] indexOfItemWithTag:[object integerValue]]
			 newSize:((ZGVariable *)([[document watchVariablesArray] objectAtIndex:rowIndex]))->size];
		}
	}
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return MIN(MAX_TABLE_VIEW_ITEMS, (NSInteger)[[document watchVariablesArray] count]);
}

#pragma mark Table View Delegate Methods

- (BOOL)selectionShouldChangeInTableView:(NSTableView *)aTableView
{
	if ([self shouldIgnoreTableViewSelectionChange])
	{
		[self setShouldIgnoreTableViewSelectionChange:NO];
		return NO;
	}
	
	return YES;
}

- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if ([[tableColumn identifier] isEqualToString:@"value"])
	{
		if (![[document searchController] canStartTask] || [[document currentProcess] processID] == NON_EXISTENT_PID_NUMBER)
		{
			NSBeep();
			return NO;
		}
        
		if (rowIndex >= 0 && (NSUInteger)rowIndex < [[document watchVariablesArray] count])
		{
			ZGVariable *variable = [[document watchVariablesArray] objectAtIndex:rowIndex];
			if (!variable)
			{
				return NO;
			}
			
			ZGMemoryProtection memoryProtection;
			ZGMemoryAddress memoryAddress = variable->address;
			ZGMemorySize memorySize;
			
			if (ZGMemoryProtectionInRegion([[document currentProcess] processTask], &memoryAddress, &memorySize, &memoryProtection))
			{
				// if the variable is within a single memory region and the memory region is not writable, then the variable is not editable
				if (memoryAddress <= variable->address && memoryAddress + memorySize >= variable->address + variable->size && !(memoryProtection & VM_PROT_WRITE))
				{
					NSBeep();
					return NO;
				}
			}
		}
	}
	else if ([[tableColumn identifier] isEqualToString:@"address"])
	{
		if (rowIndex < 0 || (NSUInteger)rowIndex >= [[document watchVariablesArray] count])
		{
			return NO;
		}
		
		ZGVariable *variable = [[document watchVariablesArray] objectAtIndex:rowIndex];
		if (variable && variable->isPointer)
		{
			[document editVariablesAddress:nil];
			return NO;
		}
	}
	
	return YES;
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if ([[tableColumn identifier] isEqualToString:@"address"])
	{
		if (rowIndex >= 0 && (NSUInteger)rowIndex < [[document watchVariablesArray] count])
		{
			if (((ZGVariable *)[[document watchVariablesArray] objectAtIndex:rowIndex])->isFrozen)
			{
				[cell setTextColor:[NSColor redColor]];
			}
			else
			{
				[cell setTextColor:[NSColor textColor]];
			}
		}
	}
}

- (NSString *)tableView:(NSTableView *)aTableView toolTipForCell:(NSCell *)aCell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)row mouseLocation:(NSPoint)mouseLocation
{
	NSString *displayString = nil;
	
	NSNumberFormatter *numberOfVariablesFormatter = [[NSNumberFormatter alloc] init];
	[numberOfVariablesFormatter setFormat:@"#,###"];
	
	if ([[document watchVariablesArray] count] <= MAX_TABLE_VIEW_ITEMS)
	{
		displayString = [NSString stringWithFormat:@"Displaying %@ value", [numberOfVariablesFormatter stringFromNumber:[NSNumber numberWithUnsignedInteger:[[document watchVariablesArray] count]]]];
	}
	else
	{
		displayString = [NSString stringWithFormat:@"Displaying %@ of %@ value", [numberOfVariablesFormatter stringFromNumber:[NSNumber numberWithUnsignedInt:MAX_TABLE_VIEW_ITEMS]],[numberOfVariablesFormatter stringFromNumber:[NSNumber numberWithUnsignedInteger:[[document watchVariablesArray] count]]]];
	}
	
	[numberOfVariablesFormatter release];
	
	if (displayString && [[document watchVariablesArray] count] != 1)
	{
		displayString = [displayString stringByAppendingString:@"s"];
	}
	
	return displayString;
}

@end
