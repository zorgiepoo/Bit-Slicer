/*
 * Created by Mayur Pawashe on 7/20/12.
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

#import "ZGVariableController.h"
#import "ZGDocumentTableController.h"
#import "ZGAppController.h"
#import "ZGMemoryViewerController.h"
#import "ZGVariable.h"
#import "ZGProcess.h"
#import "NSStringAdditions.h"
#import "ZGCalculator.h"
#import "ZGUtilities.h"
#import "ZGDebuggerController.h"
#import "ZGInstruction.h"
#import "ZGVirtualMemory.h"
#import "ZGVirtualMemoryHelpers.h"
#import "ZGDocumentSearchController.h"
#import "ZGSearchResults.h"
#import "ZGDocumentWindowController.h"
#import "ZGDocumentData.h"
#import "ZGScriptManager.h"
#import "ZGMachBinary.h"
#import "ZGTableView.h"

@interface ZGVariableController ()

@property (assign) ZGDocumentWindowController *windowController;
@property (assign) ZGDocumentData *documentData;

@property (nonatomic) id frozenActivity;

@end

@implementation ZGVariableController

- (id)initWithWindowController:(ZGDocumentWindowController *)windowController
{
	self = [super init];
	if (self)
	{
		self.windowController = windowController;
		self.documentData = self.windowController.documentData;
	}
	return self;
}

#pragma mark Freezing variables

- (void)updateFrozenActivity
{
	BOOL hasFrozenVariable = NO;
	for (ZGVariable *variable in self.documentData.variables)
	{
		if (variable.isFrozen && variable.enabled)
		{
			hasFrozenVariable = YES;
			break;
		}
	}
	
	if (hasFrozenVariable && self.frozenActivity == nil && [[NSProcessInfo processInfo] respondsToSelector:@selector(beginActivityWithOptions:reason:)]	)
	{
		self.frozenActivity = [[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiated reason:@"Freezing Variables"];
	}
	else if (!hasFrozenVariable && self.frozenActivity != nil)
	{
		[[NSProcessInfo processInfo] endActivity:self.frozenActivity];
		self.frozenActivity = nil;
	}
}

- (void)freezeOrUnfreezeVariablesAtRoxIndexes:(NSIndexSet *)rowIndexes
{
	for (ZGVariable *variable in [self.documentData.variables objectsAtIndexes:rowIndexes])
	{
		variable.isFrozen = !variable.isFrozen;
		
		if (variable.isFrozen)
		{
			variable.freezeValue = variable.value;
		}
	}
	
	[self updateFrozenActivity];
	[self.windowController.tableController.variablesTableView reloadData];
	
	// check whether we want to use "Undo Freeze" or "Redo Freeze" or "Undo Unfreeze" or "Redo Unfreeze"
	if ([[self.documentData.variables objectAtIndex:rowIndexes.firstIndex] isFrozen])
	{
		if (self.windowController.undoManager.isUndoing)
		{
			self.windowController.undoManager.actionName = @"Unfreeze";
		}
		else
		{
			self.windowController.undoManager.actionName = @"Freeze";
		}
	}
	else
	{
		if (self.windowController.undoManager.isUndoing)
		{
			self.windowController.undoManager.actionName = @"Freeze";
		}
		else
		{
			self.windowController.undoManager.actionName = @"Unfreeze";
		}
	}
	
	[[self.windowController.undoManager prepareWithInvocationTarget:self] freezeOrUnfreezeVariablesAtRoxIndexes:rowIndexes];
}

- (void)freezeVariables
{
	[self freezeOrUnfreezeVariablesAtRoxIndexes:self.windowController.selectedVariableIndexes];
}

#pragma mark Copying & Pasting

+ (void)copyVariableAddress:(ZGVariable *)variable
{
	[NSPasteboard.generalPasteboard
	 declareTypes:@[NSStringPboardType]
	 owner:self];
	
	[NSPasteboard.generalPasteboard
	 setString:variable.addressStringValue
	 forType:NSStringPboardType];
}

- (void)copyAddress
{
	[[self class] copyVariableAddress:[[self.windowController selectedVariables] objectAtIndex:0]];
}

+ (void)copyVariablesToPasteboard:(NSArray *)variables
{
	[NSPasteboard.generalPasteboard
	 declareTypes:@[NSStringPboardType, ZGVariablePboardType]
	 owner:self];
	
	NSMutableArray *linesToWrite = [[NSMutableArray alloc] init];
	
	for (ZGVariable *variable in variables)
	{
		if (variable.type != ZGScript)
		{
			[linesToWrite addObject:[@[variable.shortDescription, variable.addressStringValue, variable.stringValue] componentsJoinedByString:@"\t"]];
		}
	}
	
	[NSPasteboard.generalPasteboard
	 setString:[linesToWrite componentsJoinedByString:@"\n"]
	 forType:NSStringPboardType];
	
	[NSPasteboard.generalPasteboard
	 setData:[NSKeyedArchiver archivedDataWithRootObject:variables]
	 forType:ZGVariablePboardType];
}

- (void)copyVariables
{
	[[self class] copyVariablesToPasteboard:[self.windowController selectedVariables]];
}

- (void)pasteVariables
{
	NSData *pasteboardData = [NSPasteboard.generalPasteboard dataForType:ZGVariablePboardType];
	if (pasteboardData)
	{
		NSArray *variablesToInsertArray = [NSKeyedUnarchiver unarchiveObjectWithData:pasteboardData];
		NSUInteger currentIndex = self.windowController.selectedVariableIndexes.count == 0 ? 0 : self.windowController.selectedVariableIndexes.firstIndex + 1;
		
		NSIndexSet *indexesToInsert = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(currentIndex, variablesToInsertArray.count)];
		
		[self
		 addVariables:variablesToInsertArray
		 atRowIndexes:indexesToInsert];
	}
}

#pragma mark Adding & Removing Variables

- (void)clear
{
	[[self.windowController.undoManager prepareWithInvocationTarget:self.windowController] updateVariables:self.windowController.documentData.variables searchResults:self.windowController.searchController.searchResults];
	
	for (ZGVariable *variable in self.documentData.variables)
	{
		if (variable.type == ZGScript)
		{
			[self.windowController.scriptManager removeScriptForVariable:variable];
		}
	}
	
	self.windowController.documentData.variables = [NSArray array];
	self.windowController.searchController.searchResults = nil;
	
	self.windowController.runningApplicationsPopUpButton.enabled = YES;
	self.windowController.dataTypesPopUpButton.enabled = YES;
	
	if (self.windowController.currentProcess.valid)
	{
		[self.windowController setStatus:nil];
	}
	
	[self.windowController markDocumentChange];
	
	[self.windowController.tableController.variablesTableView reloadData];
}

- (void)removeVariablesAtRowIndexes:(NSIndexSet *)rowIndexes
{
	NSMutableArray *temporaryArray = [[NSMutableArray alloc] initWithCapacity:self.documentData.variables.count];
	
	if (self.windowController.undoManager.isUndoing)
	{
		self.windowController.undoManager.actionName = [NSString stringWithFormat:@"Add Variable%@", rowIndexes.count > 1 ? @"s" : @""];
	}
	else
	{
		self.windowController.undoManager.actionName = [NSString stringWithFormat:@"Delete Variable%@", rowIndexes.count > 1 ? @"s" : @""];
	}
	
	NSArray *variablesToRemove = [self.documentData.variables objectsAtIndexes:rowIndexes];
	
	[[self.windowController.undoManager prepareWithInvocationTarget:self]
	 addVariables:variablesToRemove
	 atRowIndexes:rowIndexes];
	
	for (ZGVariable *variable in variablesToRemove)
	{
		if (variable.enabled)
		{
			if (variable.type == ZGScript)
			{
				[self.windowController.scriptManager stopScriptForVariable:variable];
			}
			else if (variable.isFrozen)
			{
				// If the user undos this remove, the variable won't automatically rewrite values
				variable.isFrozen = NO;
			}
		}
	}
	
	[temporaryArray addObjectsFromArray:self.documentData.variables];
	[temporaryArray removeObjectsAtIndexes:rowIndexes];
	
	self.documentData.variables = [NSArray arrayWithArray:temporaryArray];
	[self.windowController.searchController fetchVariablesFromResults];
	
	[self updateFrozenActivity];
	[self.windowController.tableController updateWatchVariablesTimer];
	[self.windowController.tableController.variablesTableView reloadData];
}

- (void)disableHarmfulVariables:(NSArray *)variables
{
	for (ZGVariable *variable in variables)
	{
		if ((variable.type == ZGScript || variable.isFrozen) && variable.enabled)
		{
			variable.enabled = NO;
		}
	}
	
	[self updateFrozenActivity];
}

- (void)addVariables:(NSArray *)variables atRowIndexes:(NSIndexSet *)rowIndexes
{
	NSMutableArray *temporaryArray = [[NSMutableArray alloc] initWithArray:self.documentData.variables];
	[temporaryArray insertObjects:variables atIndexes:rowIndexes];
	
	[self disableHarmfulVariables:variables];
	
	self.documentData.variables = [NSArray arrayWithArray:temporaryArray];
	
	[self.windowController.tableController updateWatchVariablesTimer];
	[self.windowController.tableController.variablesTableView reloadData];
	
	if (self.windowController.undoManager.isUndoing)
	{
		self.windowController.undoManager.actionName = [NSString stringWithFormat:@"Delete Variable%@", rowIndexes.count > 1 ? @"s" : @""];
	}
	else
	{
		self.windowController.undoManager.actionName = [NSString stringWithFormat:@"Add Variable%@", rowIndexes.count > 1 ? @"s" : @""];
	}
	[[self.windowController.undoManager prepareWithInvocationTarget:self] removeVariablesAtRowIndexes:rowIndexes];
	
	[self.windowController setStatus:nil];
}

- (void)removeSelectedSearchValues
{
	[self removeVariablesAtRowIndexes:self.windowController.selectedVariableIndexes];
	[self.windowController setStatus:nil];
}

- (void)addVariable:(id)sender
{
	ZGVariableQualifier qualifier = (ZGVariableQualifier)self.documentData.qualifierTag;
	CFByteOrder byteOrder = self.documentData.byteOrderTag;
	ZGVariableType variableType = (ZGVariableType)[sender tag];
	
	// Try to get an initial address from the debugger or the memory viewer's selection
	ZGMemoryAddress initialAddress = 0x0;
	ZGMemorySize initialSize = 0;
	
	if (variableType == ZGByteArray && [[[[ZGAppController sharedController] debuggerController] currentProcess] processID] == self.windowController.currentProcess.processID)
	{
		NSArray *selectedInstructions = [[[ZGAppController sharedController] debuggerController] selectedInstructions];
		if (selectedInstructions.count > 0)
		{
			ZGInstruction *selectedInstruction = [selectedInstructions objectAtIndex:0];
			initialAddress = selectedInstruction.variable.address;
			initialSize = selectedInstruction.variable.size;
		}
	}
	else if ([[[[ZGAppController sharedController] memoryViewer] currentProcess] processID] == self.windowController.currentProcess.processID)
	{
		initialAddress = [[[ZGAppController sharedController] memoryViewer] selectedAddressRange].location;
	}
	
	ZGVariable *variable =
		[[ZGVariable alloc]
		 initWithValue:NULL
		 size:initialSize
		 address:initialAddress
		 type:variableType
		 qualifier:qualifier
		 pointerSize:self.windowController.currentProcess.pointerSize
		 description:variableType == ZGScript ? @"My Script" : @""
		 enabled:NO
		 byteOrder:byteOrder];
	
	[self
	 addVariables:@[variable]
	 atRowIndexes:[NSIndexSet indexSetWithIndex:0]];
	
	if (variable.type != ZGScript)
	{
		// have the user edit the variable's address
		[self.windowController.tableController.variablesTableView
		 editColumn:[self.windowController.tableController.variablesTableView columnWithIdentifier:@"address"]
		 row:0
		 withEvent:nil
		 select:YES];
	}
}

#pragma mark Changing Variables

- (BOOL)nopVariables:(NSArray *)variables withNewValues:(NSArray *)newValues
{
	BOOL completeSuccess = YES;
	
	NSMutableArray *oldValues = [[NSMutableArray alloc] init];
	for (ZGVariable *variable in variables)
	{
		[oldValues addObject:variable.stringValue];
	}
	
	for (NSUInteger variableIndex = 0; variableIndex < variables.count; variableIndex++)
	{
		ZGVariable *variable = [variables objectAtIndex:variableIndex];
		[self changeVariable:variable newValue:[newValues objectAtIndex:variableIndex] shouldRecordUndo:NO];
	}
	
	self.windowController.undoManager.actionName = @"NOP Change";
	[[self.windowController.undoManager prepareWithInvocationTarget:self]
	 nopVariables:variables
	 withNewValues:oldValues];
	
	return completeSuccess;
}

- (void)nopVariables:(NSArray *)variables
{
	NSMutableArray *nopValues = [[NSMutableArray alloc] init];
	
	for (ZGVariable *variable in variables)
	{
		NSMutableArray *nopComponents = [[NSMutableArray alloc] init];
		for (NSUInteger index = 0; index < variable.size; index++)
		{
			[nopComponents addObject:@"90"];
		}
		[nopValues addObject:[nopComponents componentsJoinedByString:@" "]];
	}
	
	if (![self nopVariables:variables withNewValues:nopValues])
	{
		NSRunAlertPanel(@"NOP Error", @"An error may have occured with nopping the instruction%@", nil, nil, nil, variables.count != 1 ? @"s" : @"");
	}
}

- (void)changeVariable:(ZGVariable *)variable newDescription:(NSAttributedString *)newDescription
{
	self.windowController.undoManager.actionName = @"Description Change";
	[[self.windowController.undoManager prepareWithInvocationTarget:self]
	 changeVariable:variable
	 newDescription:variable.description];
	
	variable.description = newDescription;
	
	if (self.windowController.undoManager.isUndoing || self.windowController.undoManager.isRedoing)
	{
		[self.windowController.tableController.variablesTableView reloadData];
	}
}

- (void)changeVariable:(ZGVariable *)variable newType:(ZGVariableType)type newSize:(ZGMemorySize)size
{
	self.windowController.undoManager.actionName = @"Type Change";
	[[self.windowController.undoManager prepareWithInvocationTarget:self]
	 changeVariable:variable
	 newType:variable.type
	 newSize:variable.size];
	
	[variable
	 setType:type
	 requestedSize:size
	 pointerSize:self.windowController.currentProcess.pointerSize];
	
	[self.windowController.tableController updateWatchVariablesTimer];
	[self.windowController.tableController.variablesTableView reloadData];
}

- (void)changeVariable:(ZGVariable *)variable newValue:(NSString *)stringObject shouldRecordUndo:(BOOL)recordUndoFlag
{	
	void *newValue = NULL;
	ZGMemorySize writeSize = variable.size; // specifically needed for byte arrays
	
	// It's important to retrieve this now instead of later as changing the variable's size may cause a bad side effect to this method
	NSString *oldStringValue = [variable.stringValue copy];
	
	int8_t *int8Value = malloc(sizeof(int8_t));
	int16_t *int16Value = malloc(sizeof(int16_t));
	int32_t *int32Value = malloc(sizeof(int32_t));
	int64_t *int64Value = malloc(sizeof(int64_t));
	float *floatValue = malloc(sizeof(float));
	double *doubleValue = malloc(sizeof(double));
	void *utf16Value = NULL;
	void *byteArrayValue = NULL;
	void *swappedValue = NULL;
	
	if (ZGIsNumericalDataType(variable.type))
	{
		stringObject = [ZGCalculator evaluateExpression:stringObject];
	}
	
	BOOL stringIsAHexRepresentation = stringObject.zgIsHexRepresentation;
	
	switch (variable.type)
	{
		case ZGInt8:
			if (stringIsAHexRepresentation)
			{
				[[NSScanner scannerWithString:stringObject] scanHexInt:(unsigned int *)int32Value];
				*int8Value = (int8_t)*int32Value;
			}
			else
			{
				*int8Value = (int8_t)stringObject.intValue;
			}
			
			newValue = int8Value;
			break;
		case ZGInt16:
			if (stringIsAHexRepresentation)
			{
				[[NSScanner scannerWithString:stringObject] scanHexInt:(unsigned int *)int32Value];
				*int16Value = (int16_t)*int32Value;
			}
			else
			{
				*int16Value = (int16_t)stringObject.intValue;
			}
			
			newValue = int16Value;
			break;
		case ZGPointer:
			if (variable.size == sizeof(int32_t))
			{
				goto INT32_BIT_CHANGE_VARIABLE;
			}
			else if (variable.size == sizeof(int64_t))
			{
				goto INT64_BIT_CHANGE_VARIABLE;
			}
			
			break;
		case ZGInt32:
		INT32_BIT_CHANGE_VARIABLE:
			if (stringIsAHexRepresentation)
			{
				[[NSScanner scannerWithString:stringObject] scanHexInt:(unsigned int *)int32Value];
			}
			else
			{
				*int32Value = stringObject.intValue;
			}
			
			newValue = int32Value;
			break;
		case ZGFloat:
			if (stringIsAHexRepresentation)
			{
				[[NSScanner scannerWithString:stringObject] scanHexFloat:floatValue];
			}
			else
			{
				*floatValue = stringObject.floatValue;
			}
			
			newValue = floatValue;
			break;
		case ZGInt64:
		INT64_BIT_CHANGE_VARIABLE:
			if (stringIsAHexRepresentation)
			{
				[[NSScanner scannerWithString:stringObject] scanHexLongLong:(unsigned long long *)int64Value];
			}
			else
			{
				[[NSScanner scannerWithString:stringObject] scanLongLong:int64Value];
			}
			
			newValue = int64Value;
			break;
		case ZGDouble:
			if (stringIsAHexRepresentation)
			{
				[[NSScanner scannerWithString:stringObject] scanHexDouble:doubleValue];
			}
			else
			{
				*doubleValue = stringObject.doubleValue;
			}
			
			newValue = doubleValue;
			break;
		case ZGString8:
			newValue = (void *)[stringObject cStringUsingEncoding:NSUTF8StringEncoding];
			variable.size = strlen(newValue) + 1;
			writeSize = variable.size;
			break;
		case ZGString16:
			variable.size = [stringObject length] * sizeof(unichar);
			writeSize = variable.size;
			
			if (variable.size > 0)
			{
				utf16Value = malloc((size_t)variable.size);
				newValue = utf16Value;
				[stringObject
				 getCharacters:newValue
				 range:NSMakeRange(0, stringObject.length)];
			}
			else
			{
				// String "" can be of 0 length
				utf16Value = malloc(sizeof(unichar));
				newValue = utf16Value;
				
				if (newValue)
				{
					unichar nullTerminator = 0;
					memcpy(newValue, &nullTerminator, sizeof(unichar));
				}
			}
			
			break;
			
		case ZGByteArray:
		{
			NSArray *bytesArray = ZGByteArrayComponentsFromString(stringObject);
			
			if (variable.size != bytesArray.count)
			{
				// this is the size the user wants
				[self editVariables:@[variable] requestedSizes:@[@(bytesArray.count)]];
			}
			
			// Update old string value to be the same size as new string value, so that undo/redo's from one size to another will work more nicely
			void *oldData = NULL;
			ZGMemorySize oldSize = variable.size;
			
			if (ZGReadBytes(self.windowController.currentProcess.processTask, variable.address, &oldData, &oldSize))
			{
				ZGVariable *oldVariable = [[ZGVariable alloc] initWithValue:oldData size:oldSize address:variable.address type:ZGByteArray qualifier:variable.qualifier pointerSize:self.windowController.currentProcess.pointerSize description:variable.description enabled:variable.enabled byteOrder:variable.byteOrder];
				
				oldStringValue = oldVariable.stringValue;
				
				ZGFreeBytes(self.windowController.currentProcess.processTask, oldData, oldSize);
			}
			
			// this is the maximum size allocated needed
			byteArrayValue = malloc((size_t)variable.size);
			newValue = byteArrayValue;
			
			if (newValue != nil)
			{
				unsigned char *valuePtr = newValue;
				writeSize = 0;
				
				for (NSString *byteString in bytesArray)
				{
					unsigned int theValue = 0;
					[[NSScanner scannerWithString:byteString] scanHexInt:&theValue];
					*valuePtr = (unsigned char)theValue;
					valuePtr++;
					
					if ([byteString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length == 0)
					{
						break;
					}
					
					writeSize++;
				}
			}
			else
			{
				variable.size = writeSize;
			}
			
			break;
		}
		case ZGScript:
			break;
	}
	
	if (newValue != nil)
	{
		if (variable.byteOrder != CFByteOrderGetCurrent())
		{
			swappedValue = ZGSwappedValue(self.windowController.currentProcess.is64Bit, newValue, variable.type, writeSize);
			newValue = swappedValue;
		}
		
		if (variable.isFrozen)
		{
			variable.freezeValue = newValue;
			
			if (recordUndoFlag)
			{
				self.windowController.undoManager.actionName = @"Freeze Value Change";
				[[self.windowController.undoManager prepareWithInvocationTarget:self]
				 changeVariable:variable
				 newValue:variable.stringValue
				 shouldRecordUndo:YES];
				
				if (self.windowController.undoManager.isUndoing || self.windowController.undoManager.isRedoing)
				{
					[self.windowController.tableController.variablesTableView reloadData];
				}
			}
		}
		else
		{
			BOOL successfulWrite = YES;
			
			if (writeSize)
			{
				if (!ZGWriteBytesIgnoringProtection(self.windowController.currentProcess.processTask, variable.address, newValue, writeSize))
				{
					successfulWrite = NO;
				}
			}
			else
			{
				successfulWrite = NO;
			}
			
			if (successfulWrite && variable.type == ZGString16)
			{
				// Don't forget to write the null terminator
				unichar nullTerminator = 0;
				if (!ZGWriteBytesIgnoringProtection(self.windowController.currentProcess.processTask, variable.address + writeSize, &nullTerminator, sizeof(unichar)))
				{
					successfulWrite = NO;
				}
			}
			
			if (successfulWrite && recordUndoFlag)
			{
				self.windowController.undoManager.actionName = @"Value Change";
				[[self.windowController.undoManager prepareWithInvocationTarget:self]
				 changeVariable:variable
				 newValue:oldStringValue
				 shouldRecordUndo:YES];
				
				if (self.windowController.undoManager.isUndoing || self.windowController.undoManager.isRedoing)
				{
					[self.windowController.tableController.variablesTableView reloadData];
				}
			}
		}
	}
	
	free(int8Value);
	free(int16Value);
	free(int32Value);
	free(int64Value);
	free(floatValue);
	free(doubleValue);
	free(utf16Value);
	free(byteArrayValue);
	free(swappedValue);
}

- (void)changeVariableEnabled:(BOOL)enabled rowIndexes:(NSIndexSet *)rowIndexes
{
	NSMutableIndexSet *undoableRowIndexes = [[NSMutableIndexSet alloc] init];
	NSUInteger currentIndex = rowIndexes.firstIndex;
	
	BOOL needsToMarkChange = NO; // we may have to mark a document change even if we don't have any un-doable actions, i.e, scripts
	while (currentIndex != NSNotFound)
	{
		ZGVariable *variable = [self.documentData.variables objectAtIndex:currentIndex];
		variable.enabled = enabled;
		if (variable.type == ZGScript)
		{
			if (variable.enabled)
			{
				[self.windowController.scriptManager runScriptForVariable:variable];
			}
			else
			{
				[self.windowController.scriptManager stopScriptForVariable:variable];
			}
			needsToMarkChange = YES;
		}
		else
		{
			[undoableRowIndexes addIndex:currentIndex];
		}
		
		currentIndex = [rowIndexes indexGreaterThanIndex:currentIndex];
	}
	
	if (!self.windowController.undoManager.isUndoing && !self.windowController.undoManager.isRedoing && undoableRowIndexes.count > 1)
	{
		self.windowController.variablesTableView.shouldIgnoreNextSelection = YES;
	}
	
	[self updateFrozenActivity];
	
	// the table view always needs to be reloaded because of being able to select multiple indexes
	[self.windowController.tableController.variablesTableView reloadData];
	
	if (undoableRowIndexes.count > 0)
	{
		self.windowController.undoManager.actionName = [NSString stringWithFormat:@"Enabled Variable%@ Change", (rowIndexes.count > 1) ? @"s" : @""];
		[[self.windowController.undoManager prepareWithInvocationTarget:self]
		 changeVariableEnabled:!enabled
		 rowIndexes:undoableRowIndexes];
	}
	else if (needsToMarkChange)
	{
		[self.windowController markDocumentChange];
	}
}

#pragma mark Edit Variables Values

- (void)editVariables:(NSArray *)variables newValues:(NSArray *)newValues
{
	NSMutableArray *oldValues = [[NSMutableArray alloc] init];
	
	[variables enumerateObjectsUsingBlock:^(id object, NSUInteger index, BOOL *stop)
	 {
		 ZGVariable *variable = object;
		 
		 [oldValues addObject:variable.stringValue];
		 
		 [self
		  changeVariable:variable
		  newValue:[newValues objectAtIndex:index]
		  shouldRecordUndo:NO];
	 }];
	
	[self.windowController.tableController.variablesTableView reloadData];
	
	self.windowController.undoManager.actionName = @"Edit Variables";
	[[self.windowController.undoManager prepareWithInvocationTarget:self]
	 editVariables:variables
	 newValues:oldValues];
}

#pragma mark Edit Variables Address

- (void)editVariable:(ZGVariable *)variable addressFormula:(NSString *)newAddressFormula
{
	self.windowController.undoManager.actionName = @"Address Change";
	[[self.windowController.undoManager prepareWithInvocationTarget:self]
	 editVariable:variable
	 addressFormula:variable.addressFormula];
	
	variable.addressFormula = newAddressFormula;
	if (variable.usesDynamicPointerAddress || variable.usesDynamicBaseAddress)
	{
		variable.usesDynamicAddress = YES;
	}
	else
	{
		variable.usesDynamicAddress = NO;
		variable.addressStringValue = [ZGCalculator evaluateExpression:newAddressFormula];
		[self.windowController.tableController.variablesTableView reloadData];
	}
	variable.finishedEvaluatingDynamicAddress = NO;
}

#pragma mark Relativizing Variable Addresses

- (void)unrelativizeVariables:(NSArray *)variables
{
	for (ZGVariable *variable in variables)
	{
		variable.addressFormula = variable.addressStringValue;
		variable.usesDynamicAddress = NO;
	}
	
	self.windowController.undoManager.actionName = [NSString stringWithFormat:@"Unrelativize Variable%@", variables.count == 1 ? @"" : @"s"];
	[[self.windowController.undoManager prepareWithInvocationTarget:self] relativizeVariables:variables];
}

- (void)relativizeVariables:(NSArray *)variables
{
	ZGProcess *currentProcess = self.windowController.currentProcess;
	NSMutableDictionary *cacheDictionary = currentProcess.cacheDictionary;
	for (ZGVariable *variable in variables)
	{
		NSString *mappedFilePath = nil;
		ZGMemorySize relativeOffset = 0;
		if (ZGSectionName(currentProcess.processTask, currentProcess.pointerSize, currentProcess.dylinkerBinary, variable.address, variable.size, &mappedFilePath, &relativeOffset, NULL, cacheDictionary) != nil)
		{
			NSString *partialPath = [mappedFilePath lastPathComponent];
			NSError *error = nil;
			ZGMemoryAddress baseAddress = ZGFindExecutableImageWithCache(currentProcess.processTask, currentProcess.pointerSize, currentProcess.dylinkerBinary, partialPath, self.windowController.currentProcess.cacheDictionary, &error);
			NSString *pathToUse = (error == nil && baseAddress == variable.address - relativeOffset) ? partialPath : mappedFilePath;
			variable.addressFormula = [NSString stringWithFormat:ZGBaseAddressFunction@"(\"%@\") + 0x%llX", pathToUse, relativeOffset];
			variable.usesDynamicAddress = YES;
		}
	}
	
	self.windowController.undoManager.actionName = [NSString stringWithFormat:@"Relativize Variable%@", variables.count == 1 ? @"" : @"s"];
	[[self.windowController.undoManager prepareWithInvocationTarget:self] unrelativizeVariables:variables];
}

- (NSString *)relativizeVariable:(ZGVariable * __unsafe_unretained)variable withMachBinaries:(NSArray *)machBinaries filePathDictionary:(NSDictionary *)machFilePathDictionary
{
	NSString *staticVariableDescription = nil;
	
	NSDictionary *cacheDictionary = self.windowController.currentProcess.cacheDictionary;
	ZGMemoryMap processTask = self.windowController.currentProcess.processTask;
	ZGMemorySize pointerSize = self.windowController.currentProcess.pointerSize;
	
	ZGMachBinary *machBinary = ZGNearestMachBinary(machBinaries, variable.address);
	ZGMemoryAddress machHeaderAddress = machBinary.headerAddress;
	
	NSString *machFilePath = [machFilePathDictionary objectForKey:@(machBinary.filePathAddress)];
	
	if (machFilePath != nil)
	{
		ZGMemorySize slide = 0;
		ZGMemorySize textSize = 0;
		ZGMemorySize dataSize = 0;
		ZGMemorySize linkEditSize = 0;
		
		ZGGetMachBinaryInfo(processTask, pointerSize, machHeaderAddress, machFilePath, NULL, &slide, &textSize, &dataSize, &linkEditSize, cacheDictionary);
		
		if (variable.address >= machHeaderAddress && variable.address + variable.size <= machHeaderAddress + textSize + dataSize + linkEditSize)
		{
			if (slide > 0)
			{
				NSString *partialPath = [machFilePath lastPathComponent];
				NSString *pathToUse = nil;
				NSString *baseArgument = @"";
				
				if (machBinary != [machBinaries objectAtIndex:0])
				{
					if ([[machFilePath stringByDeletingLastPathComponent] length] > 0)
					{
						partialPath = [@"/" stringByAppendingString:partialPath];
					}
					
					int numberOfMatchingPaths = 0;
					for (ZGMachBinary *binaryImage in machBinaries)
					{
						NSString *mappedPath = [machFilePathDictionary objectForKey:@(binaryImage.filePathAddress)];
						if ([mappedPath hasSuffix:partialPath])
						{
							numberOfMatchingPaths++;
							if (numberOfMatchingPaths > 1) break;
						}
					}
					
					pathToUse = numberOfMatchingPaths > 1 ? machFilePath : partialPath;
					baseArgument = [NSString stringWithFormat:@"\"%@\"", pathToUse];
				}
				
				variable.addressFormula = [NSString stringWithFormat:ZGBaseAddressFunction@"(%@) + 0x%llX", baseArgument, variable.address - machHeaderAddress];
				variable.usesDynamicAddress = YES;
				variable.finishedEvaluatingDynamicAddress = YES;
				
				// Cache the path
				if (pathToUse != nil)
				{
					NSMutableDictionary *mappedPathDictionary = [cacheDictionary objectForKey:ZGMappedPathDictionary];
					if ([mappedPathDictionary objectForKey:pathToUse] == nil)
					{
						[mappedPathDictionary setObject:@(machHeaderAddress) forKey:pathToUse];
					}
				}
			}
			
			NSString *sectionName = nil;
			if (variable.address + variable.size <= machHeaderAddress + textSize)
			{
				sectionName = @"__TEXT";
			}
			else if (variable.address + variable.size <= machHeaderAddress + textSize + dataSize)
			{
				sectionName = @"__DATA";
			}
			else
			{
				sectionName = @"__LINKEDIT";
			}
			
			staticVariableDescription = [NSString stringWithFormat:@"static address (%@)", sectionName];
		}
	}
	
	return staticVariableDescription;
}

- (void)annotateVariables:(NSArray *)variables
{
	ZGProcess *currentProcess = self.windowController.currentProcess;
	ZGMemoryMap processTask = currentProcess.processTask;
	NSArray *machBinaries = ZGMachBinaries(processTask, currentProcess.pointerSize, currentProcess.dylinkerBinary);
	NSMutableDictionary *machFilePathDictionary = [[NSMutableDictionary alloc] init];
	
	for (ZGMachBinary *machBinary in machBinaries)
	{
		NSString *filePath = ZGFilePathAtAddress(processTask, machBinary.filePathAddress);
		if (filePath != nil)
		{
			[machFilePathDictionary setObject:filePath forKey:@(machBinary.filePathAddress)];
		}
	}
	
	ZGMemoryAddress cachedSubmapRegionAddress = 0;
	ZGMemorySize cachedSubmapRegionSize = 0;
	ZGMemorySubmapInfo cachedSubmapInfo;
	
	for (ZGVariable *variable in variables)
	{
		NSString *staticDescription = [self relativizeVariable:variable withMachBinaries:machBinaries filePathDictionary:machFilePathDictionary];
		
		if (cachedSubmapRegionAddress >= variable.address + variable.size || cachedSubmapRegionAddress + cachedSubmapRegionSize <= variable.address)
		{
			cachedSubmapRegionAddress = variable.address;
			if (!ZGRegionSubmapInfo(processTask, &cachedSubmapRegionAddress, &cachedSubmapRegionSize, &cachedSubmapInfo))
			{
				cachedSubmapRegionAddress = 0;
				cachedSubmapRegionSize = 0;
			}
		}
		
		NSString *userTagDescription = nil;
		NSString *protectionDescription = nil;
		
		if (cachedSubmapRegionAddress <= variable.address && cachedSubmapRegionAddress + cachedSubmapRegionSize >= variable.address + variable.size)
		{
			userTagDescription = ZGUserTagDescription(cachedSubmapInfo.user_tag);
			protectionDescription = ZGProtectionDescription(cachedSubmapInfo.protection);
		}
		
		NSMutableArray *validDescriptionComponents = [NSMutableArray array];
		if (staticDescription != nil) [validDescriptionComponents addObject:staticDescription];
		if (userTagDescription != nil) [validDescriptionComponents addObject:userTagDescription];
		if (protectionDescription != nil) [validDescriptionComponents addObject:protectionDescription];
		
		if ([variable.description length] == 0)
		{
			variable.description = [validDescriptionComponents componentsJoinedByString:@", "];
		}
		else
		{
			NSString *appendedString = [NSString stringWithFormat:@"\n\n%@", [validDescriptionComponents componentsJoinedByString:@"\n"]];
			[variable.description appendAttributedString:[[NSAttributedString alloc] initWithString:appendedString]];
		}
	}
}

#pragma mark Edit Variables Sizes (Byte Arrays)

- (void)editVariables:(NSArray *)variables requestedSizes:(NSArray *)requestedSizes
{
	NSMutableArray *currentVariableSizes = [[NSMutableArray alloc] init];
	NSMutableArray *validVariables = [[NSMutableArray alloc] init];
	
	// Make sure the size changes are possible. Only change the ones that seem possible.
	[variables enumerateObjectsUsingBlock:^(ZGVariable *variable, NSUInteger index, BOOL *stop)
	 {
		 ZGMemorySize size = [[requestedSizes objectAtIndex:index] unsignedLongLongValue];
		 void *buffer = NULL;
		 
		 if (ZGReadBytes(self.windowController.currentProcess.processTask, variable.address, &buffer, &size))
		 {
			 if (size == [[requestedSizes objectAtIndex:index] unsignedLongLongValue])
			 {
				 [validVariables addObject:variable];
				 [currentVariableSizes addObject:@(variable.size)];
			 }
			 
			 ZGFreeBytes(self.windowController.currentProcess.processTask, buffer, size);
		 }
	 }];
	
	if (validVariables.count > 0)
	{
		self.windowController.undoManager.actionName = @"Size Change";
		[[self.windowController.undoManager prepareWithInvocationTarget:self]
		 editVariables:validVariables
		 requestedSizes:currentVariableSizes];
		
		[validVariables enumerateObjectsUsingBlock:^(ZGVariable *variable, NSUInteger index, BOOL *stop)
		 {
			 variable.size = [[requestedSizes objectAtIndex:index] unsignedLongLongValue];
		 }];
		
		[self.windowController.tableController.variablesTableView reloadData];
	}
	else
	{
		NSRunAlertPanel(@"Failed to change size", @"The size that you have requested could not be changed. Perhaps it is too big of a value?", nil, nil, nil);
	}
}

@end
