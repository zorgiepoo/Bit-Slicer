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
#import "ZGDocumentSearchController.h"
#import "ZGSearchResults.h"
#import "ZGDocumentWindowController.h"
#import "ZGDocumentData.h"

@interface ZGVariableController ()

@property (assign) ZGDocumentWindowController *windowController;
@property (assign) ZGDocumentData *documentData;

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

- (void)freezeOrUnfreezeVariablesAtRoxIndexes:(NSIndexSet *)rowIndexes
{
	[rowIndexes enumerateIndexesUsingBlock:^(NSUInteger rowIndex, BOOL *stop)
	 {
		 ZGVariable *variable = [self.documentData.variables objectAtIndex:rowIndex];
		 variable.isFrozen = !variable.isFrozen;
		 
		 if (variable.isFrozen)
		 {
			 variable.freezeValue = variable.value;
		 }
	 }];
	
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

- (void)copyAddress
{
	ZGVariable *selectedVariable = [[self.windowController selectedVariables] objectAtIndex:0];
	[NSPasteboard.generalPasteboard
	 declareTypes:@[NSStringPboardType]
	 owner:self];
	
	[NSPasteboard.generalPasteboard
	 setString:selectedVariable.addressStringValue
	 forType:NSStringPboardType];
}

- (void)copyVariables
{
	[NSPasteboard.generalPasteboard
	 declareTypes:@[NSStringPboardType, ZGVariablePboardType]
	 owner:self];
	
	NSMutableArray *linesToWrite = [[NSMutableArray alloc] init];
	NSArray *variablesArray = [self.windowController selectedVariables];
	
	for (ZGVariable *variable in variablesArray)
	{
		[linesToWrite addObject:[@[variable.name, variable.addressStringValue, variable.stringValue] componentsJoinedByString:@"\t"]];
	}
	
	[NSPasteboard.generalPasteboard
	 setString:[linesToWrite componentsJoinedByString:@"\n"]
	 forType:NSStringPboardType];
	
	[NSPasteboard.generalPasteboard
	 setData:[NSKeyedArchiver archivedDataWithRootObject:variablesArray]
	 forType:ZGVariablePboardType];
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
	[[self.windowController.undoManager prepareWithInvocationTarget:self]
	 addVariables:[self.documentData.variables objectsAtIndexes:rowIndexes]
	 atRowIndexes:rowIndexes];
	
	[temporaryArray addObjectsFromArray:self.documentData.variables];
	[temporaryArray removeObjectsAtIndexes:rowIndexes];
	
	self.documentData.variables = [NSArray arrayWithArray:temporaryArray];
	[self.windowController.searchController fetchVariablesFromResults];
	
	[self.windowController.tableController.variablesTableView reloadData];
	
	[self.windowController updateClearButton];
}

- (void)addVariables:(NSArray *)variables atRowIndexes:(NSIndexSet *)rowIndexes
{
	NSMutableArray *temporaryArray = [[NSMutableArray alloc] initWithArray:self.documentData.variables];
	[temporaryArray insertObjects:variables atIndexes:rowIndexes];
	
	self.documentData.variables = [NSArray arrayWithArray:temporaryArray];
	
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
	
	self.windowController.generalStatusTextField.stringValue = @"";
	
	[self.windowController updateClearButton];
}

- (void)removeSelectedSearchValues
{
	[self removeVariablesAtRowIndexes:self.windowController.selectedVariableIndexes];
	self.windowController.generalStatusTextField.stringValue = @"";
}

- (void)addVariable:(id)sender
{
	ZGVariableQualifier qualifier = (ZGVariableQualifier)self.documentData.qualifierTag;
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
		 name:@""
		 enabled:NO];
	
	[self
	 addVariables:@[variable]
	 atRowIndexes:[NSIndexSet indexSetWithIndex:0]];
	
	// have the user edit the variable's address
	[self.windowController.tableController.variablesTableView
	 editColumn:[self.windowController.tableController.variablesTableView columnWithIdentifier:@"address"]
	 row:0
	 withEvent:nil
	 select:YES];
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

- (void)changeVariable:(ZGVariable *)variable newName:(NSString *)newName
{
	self.windowController.undoManager.actionName = @"Name Change";
	[[self.windowController.undoManager prepareWithInvocationTarget:self]
	 changeVariable:variable
	 newName:variable.name];
	
	variable.name = newName;
	
	if (self.windowController.undoManager.isUndoing || self.windowController.undoManager.isRedoing)
	{
		[self.windowController.tableController.variablesTableView reloadData];
	}
}

- (void)changeVariable:(ZGVariable *)variable newAddress:(NSString *)newAddress
{
	self.windowController.undoManager.actionName = @"Address Change";
	[[self.windowController.undoManager prepareWithInvocationTarget:self]
	 changeVariable:variable
	 newAddress:variable.addressStringValue];
	
	variable.addressStringValue = [ZGCalculator evaluateExpression:newAddress];
	
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
	
	if (variable.type != ZGUTF8String && variable.type != ZGUTF16String && variable.type != ZGByteArray)
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
		case ZGUTF8String:
			newValue = (void *)[stringObject cStringUsingEncoding:NSUTF8StringEncoding];
			variable.size = strlen(newValue) + 1;
			writeSize = variable.size;
			break;
		case ZGUTF16String:
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
			NSArray *bytesArray = [stringObject componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
			
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
				ZGVariable *oldVariable = [[ZGVariable alloc] initWithValue:oldData size:oldSize address:variable.address type:ZGByteArray qualifier:ZGSigned pointerSize:self.windowController.currentProcess.pointerSize];
				
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
			
			if (successfulWrite && variable.type == ZGUTF16String)
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
}

- (void)changeVariableEnabled:(BOOL)enabled rowIndexes:(NSIndexSet *)rowIndexes
{
	NSUInteger currentIndex = rowIndexes.firstIndex;
	while (currentIndex != NSNotFound)
	{
		[[self.documentData.variables objectAtIndex:currentIndex] setEnabled:enabled];
		currentIndex = [rowIndexes indexGreaterThanIndex:currentIndex];
	}
	
	if (!self.windowController.undoManager.isUndoing && !self.windowController.undoManager.isRedoing && rowIndexes.count > 1)
	{
		self.windowController.tableController.shouldIgnoreTableViewSelectionChange = YES;
	}
	
	// the table view always needs to be reloaded because of being able to select multiple indexes
	[self.windowController.tableController.variablesTableView reloadData];
	
	self.windowController.undoManager.actionName = [NSString stringWithFormat:@"Search Variable%@ Change", (rowIndexes.count > 1) ? @"s" : @""];
	[[self.windowController.undoManager prepareWithInvocationTarget:self]
	 changeVariableEnabled:!enabled
	 rowIndexes:rowIndexes];
}

#pragma mark Edit Variables Values

- (void)editVariablesValueCancelButton
{
	[NSApp endSheet:self.windowController.editVariablesValueWindow];
	[self.windowController.editVariablesValueWindow close];
}

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

- (void)editVariablesValueOkayButton
{
	[NSApp endSheet:self.windowController.editVariablesValueWindow];
	[self.windowController.editVariablesValueWindow close];
	
	NSArray *variables = [self.windowController selectedVariables];
	NSMutableArray *validVariables = [[NSMutableArray alloc] init];
	
	for (ZGVariable *variable in variables)
	{
		ZGMemoryProtection memoryProtection;
		ZGMemoryAddress memoryAddress = variable.address;
		ZGMemorySize memorySize = variable.size;
		
		if (ZGMemoryProtectionInRegion(self.windowController.currentProcess.processTask, &memoryAddress, &memorySize, &memoryProtection))
		{
			// if !(the variable is within a single memory region and the memory region is not writable), then the variable is editable
			if (!(memoryAddress <= variable.address && memoryAddress + memorySize >= variable.address + variable.size && !(memoryProtection & VM_PROT_WRITE)))
			{
				[validVariables addObject:variable];
			}
		}
	}
	
	if (validVariables.count == 0)
	{
		NSRunAlertPanel(@"Writing Variables Failed", @"The selected variables could not be overwritten. Perhaps try to change the memory protection on the variable?", nil, nil, nil);
	}
	else
	{
		NSMutableArray *valuesArray = [[NSMutableArray alloc] init];
		
		NSUInteger variableIndex;
		for (variableIndex = 0; variableIndex < validVariables.count; variableIndex++)
		{
			[valuesArray addObject:self.windowController.editVariablesValueTextField.stringValue];
		}
		
		[self
		 editVariables:validVariables
		 newValues:valuesArray];
	}
}

- (void)editVariablesValueRequest
{
	self.windowController.editVariablesValueTextField.stringValue = [[self.documentData.variables objectAtIndex:self.windowController.tableController.variablesTableView.selectedRow] stringValue];
	
	[NSApp
	 beginSheet:self.windowController.editVariablesValueWindow
	 modalForWindow:self.windowController.window
	 modalDelegate:self
	 didEndSelector:nil
	 contextInfo:NULL];
}

#pragma mark Edit Variables Address

- (void)editVariablesAddressCancelButton
{
	[NSApp endSheet:self.windowController.editVariablesAddressWindow];
	[self.windowController.editVariablesAddressWindow close];
}

- (void)editVariable:(ZGVariable *)variable addressFormula:(NSString *)newAddressFormula
{
	self.windowController.undoManager.actionName = @"Address Change";
	[[self.windowController.undoManager prepareWithInvocationTarget:self]
	 editVariable:variable
	 addressFormula:variable.addressFormula];
	
	variable.addressFormula = newAddressFormula;
	if ([newAddressFormula rangeOfString:@"["].location != NSNotFound && [newAddressFormula rangeOfString:@"]"].location != NSNotFound)
	{
		variable.isPointer = YES;
	}
	else
	{
		variable.isPointer = NO;
		variable.addressStringValue = [ZGCalculator evaluateExpression:newAddressFormula];
		[self.windowController.tableController.variablesTableView reloadData];
	}
}

- (void)editVariablesAddressOkayButton
{
	[NSApp endSheet:self.windowController.editVariablesAddressWindow];
	[self.windowController.editVariablesAddressWindow close];
	
	[self
	 editVariable:[self.documentData.variables objectAtIndex:self.windowController.tableController.variablesTableView.selectedRow]
	 addressFormula:self.windowController.editVariablesAddressTextField.stringValue];
}

- (void)editVariablesAddressRequest
{
	ZGVariable *variable = [self.documentData.variables objectAtIndex:self.windowController.tableController.variablesTableView.selectedRow];
	self.windowController.editVariablesAddressTextField.stringValue = variable.addressFormula;
	
	[NSApp
	 beginSheet:self.windowController.editVariablesAddressWindow
	 modalForWindow:self.windowController.window
	 modalDelegate:self
	 didEndSelector:nil
	 contextInfo:NULL];
}

#pragma mark Edit Variables Sizes (Byte Arrays)

- (void)editVariablesSizeCancelButton
{
	[NSApp endSheet:self.windowController.editVariablesSizeWindow];
	[self.windowController.editVariablesSizeWindow close];
}

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

- (void)editVariablesSizeOkayButton
{
	NSString *sizeExpression = [ZGCalculator evaluateExpression:self.windowController.editVariablesSizeTextField.stringValue];
	
	ZGMemorySize requestedSize = 0;
	if (sizeExpression.zgIsHexRepresentation)
	{
		[[NSScanner scannerWithString:sizeExpression] scanHexLongLong:&requestedSize];
	}
	else
	{
		requestedSize = sizeExpression.zgUnsignedLongLongValue;
	}
	
	if (!isValidNumber(sizeExpression))
	{
		NSRunAlertPanel(@"Invalid size", @"The size you have supplied is not valid.", nil, nil, nil);
	}
	else if (requestedSize <= 0)
	{
		NSRunAlertPanel(@"Failed to edit size", @"The size must be greater than 0.", nil, nil, nil);
	}
	else
	{
		[NSApp endSheet:self.windowController.editVariablesSizeWindow];
		[self.windowController.editVariablesSizeWindow close];
		
		NSArray *variables = [self.windowController selectedVariables];
		NSMutableArray *requestedSizes = [[NSMutableArray alloc] init];
		
		NSUInteger variableIndex;
		for (variableIndex = 0; variableIndex < variables.count; variableIndex++)
		{
			[requestedSizes addObject:@(requestedSize)];
		}
		
		[self
		 editVariables:variables
		 requestedSizes:requestedSizes];
	}
}

- (void)editVariablesSizeRequest
{
	ZGVariable *firstVariable = [self.documentData.variables objectAtIndex:self.windowController.tableController.variablesTableView.selectedRow];
	self.windowController.editVariablesSizeTextField.stringValue = firstVariable.sizeStringValue;
	
	[NSApp
	 beginSheet:self.windowController.editVariablesSizeWindow
	 modalForWindow:self.windowController.window
	 modalDelegate:self
	 didEndSelector:nil
	 contextInfo:NULL];
}

@end
