/*
 * Copyright (c) 2012 Mayur Pawashe
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
#import "ZGDocumentSearchController.h"
#import "ZGVariableController.h"
#import "ZGProcess.h"
#import "ZGSearchProgress.h"
#import "ZGCalculator.h"
#import "ZGVariable.h"
#import "NSStringAdditions.h"
#import "ZGSearchProgress.h"
#import "ZGSearchResults.h"
#import "ZGVirtualMemory.h"
#import "ZGVirtualMemoryUserTags.h"
#import "ZGVirtualMemoryStringReading.h"
#import "ZGMachBinary.h"
#import "ZGMachBinaryInfo.h"
#import "ZGDocumentData.h"
#import "ZGDocumentWindowController.h"
#import "ZGScriptManager.h"
#import "ZGTableView.h"
#import "NSArrayAdditions.h"
#import "ZGProtectionDescription.h"
#import "ZGNullability.h"

@implementation ZGDocumentTableController
{
	__weak ZGDocumentWindowController * _Nullable _windowController;
	NSTimer * _Nullable _watchVariablesTimer;
	NSMutableArray<NSString *> * _Nonnull _failedExecutableImages;
	NSDate * _Nullable _lastUpdatedDate;
	ZGDocumentData * _Nonnull _documentData;
	ZGTableView * _Nullable _variablesTableView;
}

#define ZGVariableReorderType @"ZGVariableReorderType"

#define WATCH_VARIABLES_UPDATE_TIME_INTERVAL 0.1

#define ZGLocalizableSearchTableString(string) NSLocalizedStringFromTable(string, @"[Code] Search Table", nil)

#pragma mark Birth & Death

- (id)initWithWindowController:(ZGDocumentWindowController *)windowController
{
	self = [super init];
	if (self != nil)
	{
		_windowController = windowController;
		_documentData = windowController.documentData;
		
		_failedExecutableImages = [[NSMutableArray alloc] init];
		[self setVariablesTableView:windowController.variablesTableView];
	}
	return self;
}

- (void)setVariablesTableView:(ZGTableView *)tableView
{
	_variablesTableView = tableView;
	[_variablesTableView setDataSource:self];
	[_variablesTableView setDelegate:self];
	[_variablesTableView registerForDraggedTypes:@[ZGVariableReorderType, ZGVariablePboardType]];
}

- (void)cleanUp
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	[_watchVariablesTimer invalidate];
	_watchVariablesTimer = nil;
	
	_windowController = nil;
	[self setVariablesTableView:nil];
}

#pragma mark Updating Table

- (BOOL)updateWatchVariablesTimer
{
	ZGDocumentWindowController *windowController = _windowController;
	if (windowController == nil)
	{
		return NO;
	}
	
	ZGProcess *process = windowController.currentProcess;
	
	BOOL hasVariablesThatNeedUpdating = process.valid && process.hasGrantedAccess && [_documentData.variables zgHasObjectMatchingCondition:^(ZGVariable *variable) { return (BOOL)(variable.type != ZGScript); }];
	BOOL shouldHaveTimer = hasVariablesThatNeedUpdating && (!windowController.isOccluded || [_documentData.variables zgHasObjectMatchingCondition:^(ZGVariable *variable) { return (BOOL)(variable.isFrozen && variable.enabled); }]);
	
	if (shouldHaveTimer && _watchVariablesTimer == nil)
	{
		_watchVariablesTimer =
		[NSTimer
		 scheduledTimerWithTimeInterval:WATCH_VARIABLES_UPDATE_TIME_INTERVAL
		 target:self
		 selector:@selector(updateWatchVariablesTable:)
		 userInfo:nil
		 repeats:YES];
	}
	else if (!shouldHaveTimer && _watchVariablesTimer != nil)
	{
		[_watchVariablesTimer invalidate];
		_watchVariablesTimer = nil;
	}
	
	return shouldHaveTimer;
}

- (BOOL)updateVariableValuesInRange:(NSRange)variableRange
{
	ZGDocumentWindowController *windowController = _windowController;
	if (windowController == nil)
	{
		return NO;
	}
	
	ZGProcess *currentProcess = windowController.currentProcess;
	BOOL needsToReloadTable = NO;
	if (variableRange.location + variableRange.length <= _documentData.variables.count)
	{
		for (ZGVariable *variable in [_documentData.variables subarrayWithRange:variableRange])
		{
			NSString *oldStringValue = [variable.stringValue copy];
			if (!(variable.isFrozen && variable.freezeValue) && (variable.type == ZGString8 || variable.type == ZGString16))
			{
				variable.size = ZGGetStringSize(currentProcess.processTask, variable.address, variable.type, variable.size, 1024);
			}
			
			if (variable.size)
			{
				ZGMemorySize outputSize = variable.size;
				void *value = NULL;
				
				if (ZGReadBytes(currentProcess.processTask, variable.address, &value, &outputSize))
				{
					variable.rawValue = value;
					if (![variable.stringValue isEqualToString:oldStringValue])
					{
						needsToReloadTable = YES;
					}
					
					ZGFreeBytes(value, outputSize);
				}
				else if (variable.rawValue != nil)
				{
					variable.rawValue = NULL;
					needsToReloadTable = YES;
				}
			}
			else if (variable.lastUpdatedSize)
			{
				variable.rawValue = NULL;
				needsToReloadTable = YES;
			}
			
			variable.lastUpdatedSize = variable.size;
		}
	}
	return needsToReloadTable;
}

- (void)clearCache
{
	[_failedExecutableImages removeAllObjects];
	_lastUpdatedDate = [NSDate date];
}

- (BOOL)updateDynamicVariableAddress:(ZGVariable *)variable
{
	BOOL needsToReload = NO;
	ZGDocumentWindowController *windowController = _windowController;
	if (windowController != nil && variable.usesDynamicAddress && !variable.finishedEvaluatingDynamicAddress)
	{
		NSError *error = nil;
		NSString *newAddressString =
			[ZGCalculator
			 evaluateExpression:[NSMutableString stringWithString:variable.addressFormula]
			 process:windowController.currentProcess
			 failedImages:_failedExecutableImages
			 error:&error];
		
		if (variable.address != newAddressString.zgUnsignedLongLongValue)
		{
			variable.addressStringValue = newAddressString;
			needsToReload = YES;
		}
		
		// We don't have to evaluate it more than once if we're not doing any pointer calculations
		if (error == nil && !variable.usesDynamicPointerAddress)
		{
			variable.finishedEvaluatingDynamicAddress = YES;
		}
	}
	return needsToReload;
}

- (void)updateWatchVariablesTable:(NSTimer *)__unused timer
{
	ZGDocumentWindowController *windowController = _windowController;
	if (windowController == nil)
	{
		return;
	}
	
	BOOL needsToReloadTable = NO;
	BOOL isOccluded = windowController.isOccluded;
	NSRange visibleRowsRange = {};
	
	if (!isOccluded)
	{
		visibleRowsRange = [_variablesTableView rowsInRect:_variablesTableView.visibleRect];
		
		if (windowController.searchController.canStartTask && windowController.searchController.searchResults.addressCount > 0 && visibleRowsRange.location + visibleRowsRange.length >= _documentData.variables.count)
		{
			[windowController.searchController fetchNumberOfVariables:MAX_NUMBER_OF_VARIABLES_TO_FETCH];
			needsToReloadTable = YES;
		}
	}
	
	// Don't look up executable images that have been known to fail frequently, otherwise it'd be a serious penalty cost
	if (windowController.currentProcess.hasGrantedAccess && _failedExecutableImages.count > 0 && (_lastUpdatedDate == nil || [[NSDate date] timeIntervalSinceDate:(NSDate * _Nonnull)_lastUpdatedDate] > 5.0))
	{
		[self clearCache];
	}
	
	// First, update all the variables that have dynamic addresses
	// We don't want to update this when the user is editing something in the table
	if (!isOccluded && windowController.currentProcess.hasGrantedAccess && _variablesTableView.editedRow == -1)
	{
		for (ZGVariable *variable in [_documentData.variables subarrayWithRange:visibleRowsRange])
		{
			if ([self updateDynamicVariableAddress:variable])
			{
				needsToReloadTable = YES;
			}
		}
	}
	
	// Then check that the process is alive
	if (windowController.currentProcess.hasGrantedAccess)
	{
		// Freeze all variables that need be frozen!
		NSUInteger variableIndex = 0;
		for (ZGVariable *variable in _documentData.variables)
		{
			if (variable.enabled && variable.isFrozen && variable.freezeValue != NULL)
			{
				// We have to make sure variable's address is up to date before proceeding
				if (isOccluded || variableIndex < visibleRowsRange.location || variableIndex >= visibleRowsRange.location + visibleRowsRange.length)
				{
					if ([self updateDynamicVariableAddress:variable])
					{
						needsToReloadTable = YES;
					}
				}
				
				if (variable.size)
				{
					ZGWriteBytesIgnoringProtection(windowController.currentProcess.processTask, variable.address, variable.freezeValue, variable.size);
				}
				
				if (variable.type == ZGString8 || variable.type == ZGString16)
				{
					unichar terminatorValue = 0;
					ZGWriteBytesIgnoringProtection(windowController.currentProcess.processTask, variable.address + variable.size, &terminatorValue, variable.type == ZGString8 ? sizeof(char) : sizeof(unichar));
				}
			}
			
			variableIndex++;
			
			// Prevent iterating through many many variables
			if (variableIndex >= MAX_NUMBER_OF_VARIABLES_TO_FETCH) break;
		}
	}
	
	if (!isOccluded)
	{
		// if any variables are changing, that means that we'll have to reload the table, and that'd be very bad
		// if the user is in the process of editing a variable's value, so don't do it then
		if (windowController.currentProcess.hasGrantedAccess && _variablesTableView.editedRow == -1)
		{
			// Read all the variables and update them in the table view if needed
			if ([self updateVariableValuesInRange:visibleRowsRange])
			{
				needsToReloadTable = YES;
			}
		}
		
		if (needsToReloadTable)
		{
			[_variablesTableView reloadData];
		}
	}
}

#pragma mark Table View Drag & Drop

- (NSDragOperation)tableView:(NSTableView *)__unused tableView validateDrop:(id <NSDraggingInfo>)draggingInfo proposedRow:(NSInteger)__unused row proposedDropOperation:(NSTableViewDropOperation)operation
{
	if ([draggingInfo draggingSource] == _variablesTableView && [draggingInfo.draggingPasteboard.types containsObject:ZGVariableReorderType] && operation != NSTableViewDropOn)
	{
		return NSDragOperationMove;
	}
	else if ([draggingInfo.draggingPasteboard.types containsObject:ZGVariablePboardType] && operation != NSTableViewDropOn)
	{
		return NSDragOperationCopy;
	}
	
	return NSDragOperationNone;
}

- (void)reorderVariables:(NSArray<ZGVariable *> *)newVariables
{
	ZGDocumentWindowController *windowController = _windowController;
	NSUndoManager *undoManager = windowController.undoManager;
	undoManager.actionName = ZGLocalizableSearchTableString(@"undoMoveAction");
	[(ZGDocumentTableController *)[undoManager prepareWithInvocationTarget:self] reorderVariables:_documentData.variables];
	
	_documentData.variables = [NSArray arrayWithArray:newVariables];
	
	[_variablesTableView reloadData];
}

- (BOOL)tableView:(NSTableView *)__unused tableView acceptDrop:(id <NSDraggingInfo>)draggingInfo row:(NSInteger)newRow dropOperation:(NSTableViewDropOperation)__unused operation
{
	if (newRow < 0)
	{
		return NO;
	}
	
	if ([draggingInfo draggingSource] == _variablesTableView && [draggingInfo.draggingPasteboard.types containsObject:ZGVariableReorderType])
	{
		NSMutableArray<ZGVariable *> *variables = [NSMutableArray arrayWithArray:_documentData.variables];
		NSArray<NSNumber *> *rows = [draggingInfo.draggingPasteboard propertyListForType:ZGVariableReorderType];
		
		// Fill in the current rows with null objects
		for (NSNumber *row in rows)
		{
			[variables
			 replaceObjectAtIndex:row.unsignedIntegerValue
			 withObject:(id)[NSNull null]];
		}
		
		// Insert the objects to the new position
		for (NSNumber *row in rows)
		{
			[variables
			 insertObject:[_documentData.variables objectAtIndex:row.unsignedIntegerValue]
			 atIndex:(NSUInteger)newRow];
			
			newRow++;
		}
		
		// Remove all the old objects
		[variables removeObject:(id)[NSNull null]];
		
		// Set the new variables
		[self reorderVariables:variables];
	}
	else if ([draggingInfo.draggingPasteboard.types containsObject:ZGVariablePboardType])
	{
		NSArray<ZGVariable *> *variables = [NSKeyedUnarchiver unarchiveObjectWithData:ZGUnwrapNullableObject([[draggingInfo draggingPasteboard] dataForType:ZGVariablePboardType])];
		
		NSMutableIndexSet *rowIndexes = [NSMutableIndexSet indexSet];
		for (NSUInteger rowIndex = 0; rowIndex < variables.count; rowIndex++)
		{
			[rowIndexes addIndex:(NSUInteger)newRow + rowIndex];
		}
		
		ZGDocumentWindowController *windowController = _windowController;
		[windowController.variableController addVariables:variables atRowIndexes:rowIndexes];
	}
	
	return YES;
}

- (BOOL)tableView:(NSTableView *)__unused tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pasteboard
{
	[pasteboard declareTypes:@[ZGVariableReorderType, ZGVariablePboardType] owner:self];
	
	NSMutableArray<NSNumber *> *rows = [[NSMutableArray alloc] init];
	[rowIndexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL * __unused stop) {
		[rows addObject:@(index)];
	}];
	[pasteboard  setPropertyList:[NSArray arrayWithArray:rows] forType:ZGVariableReorderType];
	
	NSArray<ZGVariable *> *variables = [_documentData.variables objectsAtIndexes:rowIndexes];
	[pasteboard setData:[NSKeyedArchiver archivedDataWithRootObject:variables] forType:ZGVariablePboardType];
	
	return YES;
}

#pragma mark Table View Data Source Methods

- (NSCell *)tableView:(NSTableView *)tableView dataCellForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if ([tableColumn.identifier isEqualToString:@"type"] && row >= 0)
	{
		ZGVariable *variable = [_documentData.variables objectAtIndex:(NSUInteger)row];
		if (variable.type == ZGScript)
		{
			// value data cell will do since it's a NSTextFieldCell
			return [[tableView tableColumnWithIdentifier:@"value"] dataCell];
		}
	}
	
	return [tableColumn dataCellForRow:row];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if (tableView == _variablesTableView && rowIndex >= 0 && (NSUInteger)rowIndex < _documentData.variables.count)
	{
		ZGVariable *variable = [_documentData.variables objectAtIndex:(NSUInteger)rowIndex];
		if ([tableColumn.identifier isEqualToString:@"description"])
		{
			return variable.shortDescription;
		}
		else if ([tableColumn.identifier isEqualToString:@"address"])
		{
			if (variable.type != ZGScript)
			{
				return variable.addressStringValue;
			}
		}
		else if ([tableColumn.identifier isEqualToString:@"value"])
		{
			if (variable.type == ZGScript)
			{
				NSArray<NSString *> *lines = [variable.scriptValue componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
				if (lines.count > 0)
				{
					return [lines objectAtIndex:0];
				}
			}
			return variable.stringValue;
		}
		else if ([tableColumn.identifier isEqualToString:@"enabled"])
		{
			ZGDocumentWindowController *windowController = _windowController;
			[(NSControl *)[tableColumn dataCellForRow:rowIndex] setEnabled:windowController.currentProcess.valid];
			return @(variable.enabled);
		}
		else if ([tableColumn.identifier isEqualToString:@"type"])
		{
			// Using a space to align the text field cell with the popup button cell
			return variable.type == ZGScript ? [@" " stringByAppendingString:ZGLocalizableSearchTableString(@"scriptVariableType")] : @([(NSPopUpButtonCell *)tableColumn.dataCell indexOfItemWithTag:variable.type]);
		}
	}
	
	return nil;
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if (tableView == _variablesTableView && rowIndex >= 0 && (NSUInteger)rowIndex < _documentData.variables.count)
	{
		ZGDocumentWindowController *windowController = _windowController;
		ZGVariable *variable = [_documentData.variables objectAtIndex:(NSUInteger)rowIndex];
		if ([tableColumn.identifier isEqualToString:@"value"])
		{
			[windowController.variableController
			 changeVariable:variable
			 newValue:object
			 shouldRecordUndo:YES];
		}
		else if ([tableColumn.identifier isEqualToString:@"enabled"])
		{
			[windowController.variableController
			 changeVariableEnabled:[(NSNumber *)object boolValue]
			 rowIndexes:windowController.selectedVariableIndexes];
		}
		else if ([tableColumn.identifier isEqualToString:@"type"])
		{
			[windowController.variableController
			 changeVariable:variable
			 newType:(ZGVariableType)[[[(NSPopUpButtonCell *)tableColumn.dataCell itemArray] objectAtIndex:[(NSNumber *)object unsignedIntegerValue]] tag]
			 newSize:variable.size];
		}
	}
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)__unused tableView
{
	return (NSInteger)_documentData.variables.count;
}

#pragma mark Table View Delegate Methods

- (BOOL)tableView:(NSTableView *)aTableView shouldEditTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	ZGTableView *tableView = (ZGTableView *)aTableView;
	if (rowIndex < 0 || (NSUInteger)rowIndex >= _documentData.variables.count)
	{
		return NO;
	}
	
	ZGDocumentWindowController *windowController = _windowController;
	
	ZGVariable *variable = [_documentData.variables objectAtIndex:(NSUInteger)rowIndex];
	
	if ([tableColumn.identifier isEqualToString:@"value"])
	{
		if (variable.type == ZGScript)
		{
			if (!tableView.shouldAvoidCustomEditing)
			{
				[windowController.scriptManager openScriptForVariable:variable];
			}
			return NO;
		}
		
		if (![windowController.searchController canStartTask] || !windowController.currentProcess.valid)
		{
			NSBeep();
			return NO;
		}
		
		ZGMemoryProtection memoryProtection = 0;
		ZGMemoryAddress memoryAddress = variable.address;
		ZGMemorySize memorySize = variable.size;
		
		if (ZGMemoryProtectionInRegion(windowController.currentProcess.processTask, &memoryAddress, &memorySize, &memoryProtection))
		{
			// if the variable is within a single memory region and the memory region is not readable, then don't allow the variable to be writable
			// if it is not writable, our value changing methods will try to change the protection attributes before modifying the data
			if ((memoryAddress > variable.address || memoryAddress + memorySize < variable.address + variable.size) || (memoryProtection & VM_PROT_READ) == 0)
			{
				NSBeep();
				return NO;
			}
		}
	}
	else if ([tableColumn.identifier isEqualToString:@"address"])
	{
		if (variable.type != ZGScript)
		{
			if (![windowController.searchController canStartTask])
			{
				NSBeep();
			}
			else if (!tableView.shouldAvoidCustomEditing)
			{
				[windowController requestEditingVariableAddress:nil];
			}
		}
		return NO;
	}
	else if ([tableColumn.identifier isEqualToString:@"description"])
	{
		if (![windowController.searchController canStartTask])
		{
			NSBeep();
		}
		else if (!tableView.shouldAvoidCustomEditing)
		{
			[windowController requestEditingVariableDescription:nil];
		}
		return NO;
	}
	
	return YES;
}

- (void)tableView:(NSTableView *)__unused tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if ([tableColumn.identifier isEqualToString:@"value"])
	{
		if (rowIndex >= 0 && (NSUInteger)rowIndex < _documentData.variables.count)
		{
			[(NSTextFieldCell *)cell setTextColor:[[_documentData.variables objectAtIndex:(NSUInteger)rowIndex] isFrozen] ? NSColor.systemRedColor : NSColor.controlTextColor];
		}
	}
}

- (NSString *)tableView:(NSTableView *)__unused aTableView toolTipForCell:(NSCell *)__unused aCell rect:(NSRectPointer)__unused rect tableColumn:(NSTableColumn *)__unused aTableColumn row:(NSInteger)row mouseLocation:(NSPoint)__unused mouseLocation
{
	NSMutableArray<NSString *> *displayComponents = [[NSMutableArray alloc] init];
	
	if (row >= 0 && (NSUInteger)row < _documentData.variables.count)
	{
		ZGVariable *variable = [_documentData.variables objectAtIndex:(NSUInteger)row];
		
		NSString *fullDescription = variable.fullAttributedDescription.string;
		NSUInteger fullDescriptionLength = fullDescription.length;
		if (variable.name.length < fullDescriptionLength)
		{
			NSArray<NSString *> *lines = [fullDescription componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
			NSArray<NSString *> *trimmedLines = [lines subarrayWithRange:NSMakeRange(0, MIN(lines.count, 6U))];
			NSString *descriptionFromTrimmedLines = [trimmedLines componentsJoinedByString:@"\n"];
			NSString *trimmedDescription = [descriptionFromTrimmedLines substringWithRange:NSMakeRange(0, MIN(descriptionFromTrimmedLines.length, 100U))];
			if (trimmedDescription.length < fullDescriptionLength)
			{
				trimmedDescription = [trimmedDescription stringByAppendingString:@"…"];
			}
			
			[displayComponents addObject:ZGLocalizableSearchTableString(@"descriptionTooltipLabel")];
			[displayComponents addObject:trimmedDescription];
			[displayComponents addObject:@""];
		}
		
		if (variable.usesDynamicAddress)
		{
			[displayComponents addObject:[NSString stringWithFormat:@"%@ %@", ZGLocalizableSearchTableString(@"addressTooltipLabel"), variable.addressFormula]];
		}
		
		if (variable.type == ZGByteArray)
		{
			[displayComponents addObject:[NSString stringWithFormat:@"%@ %@", ZGLocalizableSearchTableString(@"byteSizeTooltipLabel"), variable.sizeStringValue]];
		}
		
		ZGDocumentWindowController *windowController = _windowController;
		ZGProcess *currentProcess = windowController.currentProcess;
		if (variable.type != ZGScript && currentProcess.valid)
		{
			ZGMemoryAddress memoryProtectionAddress = variable.address;
			ZGMemorySize memoryProtectionSize = variable.size;
			ZGMemoryProtection memoryProtection;
			if (ZGMemoryProtectionInRegion(currentProcess.processTask, &memoryProtectionAddress, &memoryProtectionSize, &memoryProtection))
			{
				if (variable.address >= memoryProtectionAddress && variable.address + variable.size <= memoryProtectionAddress + memoryProtectionSize)
				{
					NSString *protectionDescription = ZGProtectionDescription(memoryProtection);
					if (protectionDescription != nil && [variable.name rangeOfString:protectionDescription].location == NSNotFound)
					{
						[displayComponents addObject:[NSString stringWithFormat:@"%@ %@", ZGLocalizableSearchTableString(@"protectionTooltipLabel"), protectionDescription]];
					}
				}
			}
			
			NSString *userTagDescription = ZGUserTagDescriptionFromAddress(currentProcess.processTask, variable.address, variable.size);
			
			ZGMachBinary *machBinary = [ZGMachBinary machBinaryNearestToAddress:variable.address fromMachBinaries:[ZGMachBinary machBinariesInProcess:currentProcess]];
			ZGMachBinaryInfo *machBinaryInfo = [machBinary machBinaryInfoInProcess:currentProcess];
			
			NSString *segmentName = [machBinaryInfo segmentNameAtAddress:variable.address];
			NSString *mappedFilePath = [machBinary filePathInProcess:currentProcess];
			
			BOOL needsUserTag = userTagDescription != nil && [variable.name rangeOfString:userTagDescription].location == NSNotFound;
			BOOL needsSegmentName = segmentName != nil && [variable.name rangeOfString:segmentName].location == NSNotFound;
			
			if (needsUserTag)
			{
				[displayComponents addObject:[NSString stringWithFormat:@"%@ %@", ZGLocalizableSearchTableString(@"tagTooltipLabel"), userTagDescription]];
			}
			
			if (mappedFilePath != nil)
			{
				[displayComponents addObject:[NSString stringWithFormat:@"%@ %@", ZGLocalizableSearchTableString(@"mappedTooltipLabel"), mappedFilePath]];
				if (!variable.usesDynamicAddress)
				{
					[displayComponents addObject:[NSString stringWithFormat:@"%@ 0x%llX", ZGLocalizableSearchTableString(@"offsetTooltipLabel"), variable.address - machBinary.headerAddress]];
				}
			}
			
			if (needsSegmentName)
			{
				[displayComponents addObject:[NSString stringWithFormat:@"%@ %@", ZGLocalizableSearchTableString(@"segmentTooltipLabel"), segmentName]];
			}
		}
	}
	
	return [[displayComponents componentsJoinedByString:@"\n"] stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
}

@end
