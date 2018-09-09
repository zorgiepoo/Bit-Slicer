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

#import "ZGVariableController.h"
#import "ZGDocumentTableController.h"
#import "ZGMemoryViewerController.h"
#import "ZGVariable.h"
#import "ZGProcess.h"
#import "NSStringAdditions.h"
#import "ZGCalculator.h"
#import "ZGRunAlertPanel.h"
#import "ZGInstruction.h"
#import "ZGVirtualMemory.h"
#import "ZGVirtualMemoryUserTags.h"
#import "ZGDocumentSearchController.h"
#import "ZGSearchResults.h"
#import "ZGDocumentWindowController.h"
#import "ZGDocumentData.h"
#import "ZGScriptManager.h"
#import "ZGMachBinary.h"
#import "ZGMachBinaryInfo.h"
#import "ZGTableView.h"
#import "NSArrayAdditions.h"
#import "ZGVariableDataInfo.h"
#import "ZGDataValueExtracting.h"
#import "ZGProtectionDescription.h"

#define ZGLocalizedStringFromVariableActionsTable(string) NSLocalizedStringFromTable((string), @"[Code] Variable Actions", nil)

NSString *ZGScriptIndentationUsingTabsKey = @"ZGScriptIndentationUsingTabsKey";
static NSString *ZGScriptIndentationSpacesWidthKey = @"ZGScriptIndentationSpacesWidthKey";

@implementation ZGVariableController
{
	__weak ZGDocumentWindowController * _Nullable _windowController;
	
	ZGDocumentData * _Nonnull _documentData;
	id _Nullable _frozenActivity;
}

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		[[NSUserDefaults standardUserDefaults] registerDefaults:@{ZGScriptIndentationUsingTabsKey : @NO, ZGScriptIndentationSpacesWidthKey : @4}];
	});
}

- (id)initWithWindowController:(ZGDocumentWindowController *)windowController
{
	self = [super init];
	if (self != nil)
	{
		_windowController = windowController;
		_documentData = windowController.documentData;
	}
	return self;
}

#pragma mark Freezing variables

- (void)updateFrozenActivity
{
	BOOL hasFrozenVariable = [_documentData.variables zgHasObjectMatchingCondition:^(ZGVariable *variable) { return (BOOL)(variable.isFrozen && variable.enabled); }];
	
	if (hasFrozenVariable && _frozenActivity == nil)
	{
		_frozenActivity = [[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiated reason:@"Freezing Variables"];
	}
	else if (!hasFrozenVariable && _frozenActivity != nil)
	{
		[[NSProcessInfo processInfo] endActivity:(id _Nonnull)_frozenActivity];
		_frozenActivity = nil;
	}
}

- (void)freezeOrUnfreezeVariablesAtRoxIndexes:(NSIndexSet *)rowIndexes
{
	for (ZGVariable *variable in [_documentData.variables objectsAtIndexes:rowIndexes])
	{
		variable.isFrozen = !variable.isFrozen;
		
		if (variable.isFrozen)
		{
			variable.freezeValue = variable.rawValue;
		}
	}
	
	[self updateFrozenActivity];
	
	ZGDocumentWindowController *windowController = _windowController;
	[windowController.variablesTableView reloadData];
	
	NSString *freezeActionName = ZGLocalizedStringFromVariableActionsTable(@"undoFreezeAction");
	NSString *unfreezeActionName = ZGLocalizedStringFromVariableActionsTable(@"undoUnfreezeAction");
	
	// check whether we want to use "Undo Freeze" or "Redo Freeze" or "Undo Unfreeze" or "Redo Unfreeze"
	if ([[_documentData.variables objectAtIndex:rowIndexes.firstIndex] isFrozen])
	{
		if (windowController.undoManager.isUndoing)
		{
			windowController.undoManager.actionName = unfreezeActionName;
		}
		else
		{
			windowController.undoManager.actionName = freezeActionName;
		}
	}
	else
	{
		if (windowController.undoManager.isUndoing)
		{
			windowController.undoManager.actionName = freezeActionName;
		}
		else
		{
			windowController.undoManager.actionName = unfreezeActionName;
		}
	}
	
	[(ZGVariableController *)[windowController.undoManager prepareWithInvocationTarget:self] freezeOrUnfreezeVariablesAtRoxIndexes:rowIndexes];
}

- (void)freezeVariables
{
	ZGDocumentWindowController *windowController = _windowController;
	[self freezeOrUnfreezeVariablesAtRoxIndexes:windowController.selectedVariableIndexes];
}

#pragma mark Copying & Pasting

+ (void)copyVariableAddress:(ZGVariable *)variable
{
	[NSPasteboard.generalPasteboard
	 declareTypes:@[NSStringPboardType]
	 owner:self];
	
	[NSPasteboard.generalPasteboard
	 setString:variable.addressFormula
	 forType:NSStringPboardType];
}

- (void)copyAddress
{
	ZGDocumentWindowController *windowController = _windowController;
	[[self class] copyVariableAddress:windowController.selectedVariables[0]];
}

+ (void)copyVariablesToPasteboard:(NSArray<ZGVariable *> *)variables
{
	[NSPasteboard.generalPasteboard
	 declareTypes:@[NSStringPboardType, ZGVariablePboardType]
	 owner:self];
	
	NSMutableArray<NSString *> *linesToWrite = [[NSMutableArray alloc] init];
	
	for (ZGVariable *variable in variables)
	{
		if (variable.type != ZGScript)
		{
			[linesToWrite addObject:[@[variable.shortDescription, variable.addressFormula, variable.stringValue] componentsJoinedByString:@"\t"]];
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
	ZGDocumentWindowController *windowController = _windowController;
	[[self class] copyVariablesToPasteboard:[windowController selectedVariables]];
}

- (void)pasteVariables
{
	NSData *pasteboardData = [NSPasteboard.generalPasteboard dataForType:ZGVariablePboardType];
	if (pasteboardData)
	{
		ZGDocumentWindowController *windowController = _windowController;
		NSArray<ZGVariable *> *variablesToInsertArray = [NSKeyedUnarchiver unarchiveObjectWithData:pasteboardData];
		NSUInteger currentIndex = windowController.selectedVariableIndexes.count == 0 ? 0 : windowController.selectedVariableIndexes.firstIndex + 1;
		
		NSIndexSet *indexesToInsert = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(currentIndex, variablesToInsertArray.count)];
		
		[self
		 addVariables:variablesToInsertArray
		 atRowIndexes:indexesToInsert];
	}
}

#pragma mark Adding & Removing Variables

- (void)clearSearchByFilteringForSearchVariables:(BOOL)shouldFilterForSearchVariables
{
	ZGDocumentWindowController *windowController = _windowController;
	
	[(ZGDocumentWindowController *)[windowController.undoManager prepareWithInvocationTarget:windowController] updateVariables:windowController.documentData.variables searchResults:windowController.searchController.searchResults];
	
	NSArray<ZGVariable *> *newVariables = nil;
	if (shouldFilterForSearchVariables)
	{
		newVariables = [_documentData.variables zgFilterUsingBlock:(zg_array_filter_t)^(ZGVariable *variable) {
			return (variable.type == ZGScript || variable.isFrozen || !variable.enabled);
		}];
	}
	else
	{
		newVariables = [NSArray array];
	}
	
	windowController.documentData.variables = newVariables;
	windowController.searchController.searchResults = nil;
	
	windowController.runningApplicationsPopUpButton.enabled = YES;
	windowController.dataTypesPopUpButton.enabled = YES;
	
	if (windowController.currentProcess.valid)
	{
		[windowController updateNumberOfValuesDisplayedStatus];
	}
	
	[windowController markDocumentChange];
	
	[windowController.variablesTableView reloadData];
}

- (void)clear
{
	if ([self canClearSearch])
	{
		[self clearSearch];
	}
	else
	{
		[self clearSearchByFilteringForSearchVariables:NO];
	}
}

- (BOOL)canClearSearch
{
	return [_documentData.variables zgHasObjectMatchingCondition:^(ZGVariable *variable) { return (BOOL)(variable.type != ZGScript && !variable.isFrozen && variable.enabled); }];
}

- (void)clearSearch
{
	[self clearSearchByFilteringForSearchVariables:YES];
}

- (void)removeVariablesAtRowIndexes:(NSIndexSet *)rowIndexes
{
	ZGDocumentWindowController *windowController = _windowController;
	NSMutableArray<ZGVariable *> *temporaryArray = [[NSMutableArray alloc] initWithCapacity:_documentData.variables.count];
	
	NSString *undoActionName = nil;
	if (windowController.undoManager.isUndoing)
	{
		undoActionName = (rowIndexes.count > 1) ? ZGLocalizedStringFromVariableActionsTable(@"undoAddVariables") : ZGLocalizedStringFromVariableActionsTable(@"undoAddVariable");
	}
	else
	{
		undoActionName = (rowIndexes.count > 1) ? ZGLocalizedStringFromVariableActionsTable(@"undoRemoveVariables") : ZGLocalizedStringFromVariableActionsTable(@"undoRemoveVariable");
	}
	
	windowController.undoManager.actionName = undoActionName;
	
	NSArray<ZGVariable *> *variablesToRemove = [_documentData.variables objectsAtIndexes:rowIndexes];
	
	[(ZGVariableController *)[windowController.undoManager prepareWithInvocationTarget:self]
	 addVariables:variablesToRemove
	 atRowIndexes:rowIndexes];
	
	for (ZGVariable *variable in variablesToRemove)
	{
		if (variable.enabled)
		{
			if (variable.type == ZGScript)
			{
				[windowController.scriptManager stopScriptForVariable:variable];
			}
			else if (variable.isFrozen)
			{
				// If the user undos this remove, the variable won't automatically rewrite values
				variable.isFrozen = NO;
			}
		}
	}
	
	[temporaryArray addObjectsFromArray:_documentData.variables];
	[temporaryArray removeObjectsAtIndexes:rowIndexes];
	
	_documentData.variables = [NSArray arrayWithArray:temporaryArray];
	[windowController.searchController fetchVariablesFromResults];
	
	[windowController updateNumberOfValuesDisplayedStatus];
	
	[self updateFrozenActivity];
	[windowController.tableController updateWatchVariablesTimer];
	[windowController.variablesTableView reloadData];
}

- (void)disableHarmfulVariables:(NSArray<ZGVariable *> *)variables
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

- (void)addVariables:(NSArray<ZGVariable *> *)variables atRowIndexes:(NSIndexSet *)rowIndexes
{
	ZGDocumentWindowController *windowController = _windowController;
	
	NSMutableArray<ZGVariable *> *temporaryArray = [[NSMutableArray alloc] initWithArray:_documentData.variables];
	[temporaryArray insertObjects:variables atIndexes:rowIndexes];
	
	[self disableHarmfulVariables:variables];
	
	_documentData.variables = [NSArray arrayWithArray:temporaryArray];
	
	[windowController.tableController updateWatchVariablesTimer];
	[windowController.variablesTableView reloadData];
	
	NSString *undoActionName = nil;
	if (windowController.undoManager.isUndoing)
	{
		undoActionName = (rowIndexes.count > 1) ? ZGLocalizedStringFromVariableActionsTable(@"undoRemoveVariables") : ZGLocalizedStringFromVariableActionsTable(@"undoRemoveVariable");
	}
	else
	{
		undoActionName = (rowIndexes.count > 1) ? ZGLocalizedStringFromVariableActionsTable(@"undoAddVariables") : ZGLocalizedStringFromVariableActionsTable(@"undoAddVariable");
	}
	
	windowController.undoManager.actionName = undoActionName;
	
	[(ZGVariableController *)[windowController.undoManager prepareWithInvocationTarget:self] removeVariablesAtRowIndexes:rowIndexes];
	
	[windowController updateNumberOfValuesDisplayedStatus];
}

- (void)removeSelectedSearchValues
{
	ZGDocumentWindowController *windowController = _windowController;
	
	[self removeVariablesAtRowIndexes:windowController.selectedVariableIndexes];
	[windowController updateNumberOfValuesDisplayedStatus];
}

- (void)addVariable:(id)sender
{
	ZGVariableQualifier qualifier = (ZGVariableQualifier)_documentData.qualifierTag;
	CFByteOrder byteOrder = _documentData.byteOrderTag;
	ZGVariableType variableType = (ZGVariableType)[(NSControl *)sender tag];
	
	ZGDocumentWindowController *windowController = _windowController;
	
	// Try to get an initial address from the debugger or the memory viewer's selection
	id <ZGMemorySelectionDelegate> memorySelectionDelegate = windowController.delegate;
	NSRange lastMemorySelectionRange = [memorySelectionDelegate lastMemorySelectionForProcess:windowController.currentProcess];
	ZGMemoryAddress initialAddress = lastMemorySelectionRange.location;
	ZGMemorySize initialSize = lastMemorySelectionRange.length;
	
	ZGVariable *variable =
		[[ZGVariable alloc]
		 initWithValue:NULL
		 size:initialSize
		 address:initialAddress
		 type:variableType
		 qualifier:qualifier
		 pointerSize:windowController.currentProcess.pointerSize
		 description:[[NSAttributedString alloc] initWithString:variableType == ZGScript ? ZGLocalizedStringFromVariableActionsTable(@"defaultScriptDescription") : @""]
		 enabled:NO
		 byteOrder:byteOrder];
	
	if (variable.type == ZGScript)
	{
		BOOL usingTabs = [[NSUserDefaults standardUserDefaults] boolForKey:ZGScriptIndentationUsingTabsKey];
		NSUInteger spacesWidth = (NSUInteger)[[NSUserDefaults standardUserDefaults] integerForKey:ZGScriptIndentationSpacesWidthKey];
		NSString *indentationString =
		usingTabs ? @"\t" :
		[@"" stringByPaddingToLength:spacesWidth withString:@" " startingAtIndex:0]; // equivalent to " " * spacesWidth in a sane language
		
		NSString *scriptValue =
		@"#Edit Me!\n"
		@"#Introduction to scripting: https://github.com/zorgiepoo/Bit-Slicer/wiki/Introduction-to-Scripting\n"
		@"from bitslicer import VirtualMemoryError, DebuggerError\n\n"
		@"class Script(object):\n"
		@"`def __init__(self):\n"
		@"``debug.log('Initialization..')\n"
		@"`#def execute(self, deltaTime):\n"
		@"``#write some interesting code, or not\n"
		@"`def finish(self):\n"
		@"``debug.log('Cleaning up..')\n";
		
		variable.scriptValue = [scriptValue stringByReplacingOccurrencesOfString:@"`" withString:indentationString];
	}

	[self
	 addVariables:@[variable]
	 atRowIndexes:[NSIndexSet indexSetWithIndex:0]];
	
	if (variable.type != ZGScript) {
		[self annotateVariableAutomatically:variable process:windowController.currentProcess];
	}
}

#pragma mark Changing Variables

- (BOOL)nopVariables:(NSArray<ZGVariable *> *)variables withNewValues:(NSArray<NSString *> *)newValues
{
	BOOL completeSuccess = YES;
	
	NSMutableArray<NSString *> *oldValues = [[NSMutableArray alloc] init];
	for (ZGVariable *variable in variables)
	{
		[oldValues addObject:variable.stringValue];
	}
	
	for (NSUInteger variableIndex = 0; variableIndex < variables.count; variableIndex++)
	{
		ZGVariable *variable = [variables objectAtIndex:variableIndex];
		[self changeVariable:variable newValue:[newValues objectAtIndex:variableIndex] shouldRecordUndo:NO];
	}
	
	ZGDocumentWindowController *windowController = _windowController;
	windowController.undoManager.actionName = ZGLocalizedStringFromVariableActionsTable(@"undoNOPChangeAction");
	[(ZGVariableController *)[windowController.undoManager prepareWithInvocationTarget:self]
	 nopVariables:variables
	 withNewValues:oldValues];
	
	return completeSuccess;
}

- (void)nopVariables:(NSArray<ZGVariable *> *)variables
{
	NSMutableArray<NSString *> *nopValues = [[NSMutableArray alloc] init];
	
	for (ZGVariable *variable in variables)
	{
		NSMutableArray<NSString *> *nopComponents = [[NSMutableArray alloc] init];
		for (NSUInteger index = 0; index < variable.size; index++)
		{
			[nopComponents addObject:@"90"];
		}
		[nopValues addObject:[nopComponents componentsJoinedByString:@" "]];
	}
	
	if (![self nopVariables:variables withNewValues:nopValues])
	{
		NSString *message = variables.count != 1 ? ZGLocalizedStringFromVariableActionsTable(@"nopMultipleErrorAlertMessage") : ZGLocalizedStringFromVariableActionsTable(@"nopSingleErrorAlertMessage");
		
		ZGRunAlertPanelWithOKButton(ZGLocalizedStringFromVariableActionsTable(@"nopErrorAlertTitle"), message);
	}
}

- (void)changeVariable:(ZGVariable *)variable newDescription:(NSAttributedString *)newDescription
{
	ZGDocumentWindowController *windowController = _windowController;
	
	windowController.undoManager.actionName = ZGLocalizedStringFromVariableActionsTable(@"undoDescriptionChange");
	[(ZGVariableController *)[windowController.undoManager prepareWithInvocationTarget:self]
	 changeVariable:variable
	 newDescription:variable.fullAttributedDescription];
	
	// Ignore formatting to detect if user has annotated anything of significance
	if (![variable.fullAttributedDescription.string isEqualToString:newDescription.string])
	{
		variable.userAnnotated = YES;
	}
	
	variable.fullAttributedDescription = newDescription;
	
	if (windowController.undoManager.isUndoing || windowController.undoManager.isRedoing)
	{
		[windowController.variablesTableView reloadData];
	}
}

- (void)changeVariable:(ZGVariable *)variable newType:(ZGVariableType)type newSize:(ZGMemorySize)size
{
	ZGDocumentWindowController *windowController = _windowController;
	
	windowController.undoManager.actionName = ZGLocalizedStringFromVariableActionsTable(@"undoTypeChange");
	[(ZGVariableController *)[windowController.undoManager prepareWithInvocationTarget:self]
	 changeVariable:variable
	 newType:variable.type
	 newSize:variable.size];
	
	[variable
	 setType:type
	 requestedSize:size
	 pointerSize:windowController.currentProcess.pointerSize];
	
	[windowController.tableController updateWatchVariablesTimer];
	[windowController.variablesTableView reloadData];
}

- (void)changeVariable:(ZGVariable *)variable newValue:(NSString *)stringObject shouldRecordUndo:(BOOL)recordUndoFlag
{	
	const void *newValue = NULL;
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
	
	ZGVariableType variableType;
	if (variable.type == ZGPointer)
	{
		variableType = (variable.size == sizeof(int32_t)) ? ZGInt32 : ZGInt64;
	}
	else
	{
		variableType = variable.type;
	}
	
	ZGDocumentWindowController *windowController = _windowController;
	
	switch (variableType)
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
		case ZGInt32:
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
			newValue = (const void *)[stringObject cStringUsingEncoding:NSUTF8StringEncoding];
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
				 getCharacters:utf16Value
				 range:NSMakeRange(0, stringObject.length)];
			}
			else
			{
				// String "" can be of 0 length
				utf16Value = malloc(sizeof(unichar));
				newValue = utf16Value;
				
				if (newValue != NULL)
				{
					unichar nullTerminator = 0;
					memcpy(utf16Value, &nullTerminator, sizeof(unichar));
				}
			}
			
			break;
			
		case ZGByteArray:
		{
			NSArray<NSString *> *bytesArray = ZGByteArrayComponentsFromString(stringObject);
			
			if (variable.size != bytesArray.count)
			{
				// this is the size the user wants
				[self editVariables:@[variable] requestedSizes:@[@(bytesArray.count)]];
			}
			
			// Update old string value to be the same size as new string value, so that undo/redo's from one size to another will work more nicely
			void *oldData = NULL;
			ZGMemorySize oldSize = variable.size;
			
			if (ZGReadBytes(windowController.currentProcess.processTask, variable.address, &oldData, &oldSize))
			{
				ZGVariable *oldVariable = [[ZGVariable alloc] initWithValue:oldData size:oldSize address:variable.address type:ZGByteArray qualifier:variable.qualifier pointerSize:windowController.currentProcess.pointerSize description:variable.fullAttributedDescription enabled:variable.enabled byteOrder:variable.byteOrder];
				
				oldStringValue = oldVariable.stringValue;
				
				ZGFreeBytes(oldData, oldSize);
			}
			
			// this is the maximum size allocated needed
			byteArrayValue = malloc((size_t)variable.size);
			newValue = byteArrayValue;
			
			if (newValue != NULL)
			{
				unsigned char *valuePtr = byteArrayValue;
				writeSize = 0;
				
				NSArray<NSString *> *oldComponents = ZGByteArrayComponentsFromString(oldStringValue);
				
				for (NSString *byteString in bytesArray)
				{
					// old string value will be same size as new string value so accessing this index is fine
					NSString *oldComponent = [oldComponents objectAtIndex:writeSize];
					
					unichar oldCharacters[2];
					[oldComponent getCharacters:oldCharacters];
					
					unichar newCharacters[2];
					[byteString getCharacters:newCharacters	];
					
					unichar replaceCharacters[2];
					replaceCharacters[0] = (newCharacters[0] == '?' || newCharacters[0] == '*') ? oldCharacters[0] : newCharacters[0];
					replaceCharacters[1] = (newCharacters[1] == '?' || newCharacters[1] == '*') ? oldCharacters[1] : newCharacters[1];
					
					unsigned int replaceValue = 0;
					[[NSScanner scannerWithString:[NSString stringWithCharacters:replaceCharacters length:2]] scanHexInt:&replaceValue];
					
					*valuePtr = (unsigned char)replaceValue;
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
		case ZGPointer:
		case ZGScript:
			break;
	}
	
	if (newValue != NULL)
	{
		if (variable.byteOrder != CFByteOrderGetCurrent())
		{
			swappedValue = ZGSwappedValue(windowController.currentProcess.is64Bit, newValue, variableType, writeSize);
			newValue = swappedValue;
		}
		
		if (variable.isFrozen)
		{
			variable.freezeValue = newValue;
			
			if (recordUndoFlag)
			{
				windowController.undoManager.actionName = ZGLocalizedStringFromVariableActionsTable(@"undoFreezeValueChange");
				[(ZGVariableController *)[windowController.undoManager prepareWithInvocationTarget:self]
				 changeVariable:variable
				 newValue:variable.stringValue
				 shouldRecordUndo:YES];
				
				if (windowController.undoManager.isUndoing || windowController.undoManager.isRedoing)
				{
					[windowController.variablesTableView reloadData];
				}
			}
		}
		else
		{
			BOOL successfulWrite = YES;
			
			if (writeSize)
			{
				if (!ZGWriteBytesIgnoringProtection(windowController.currentProcess.processTask, variable.address, newValue, writeSize))
				{
					successfulWrite = NO;
				}
			}
			else
			{
				successfulWrite = NO;
			}
			
			if (successfulWrite && variableType == ZGString16)
			{
				// Don't forget to write the null terminator
				unichar nullTerminator = 0;
				if (!ZGWriteBytesIgnoringProtection(windowController.currentProcess.processTask, variable.address + writeSize, &nullTerminator, sizeof(unichar)))
				{
					successfulWrite = NO;
				}
			}
			
			if (successfulWrite && recordUndoFlag)
			{
				windowController.undoManager.actionName = ZGLocalizedStringFromVariableActionsTable(@"undoValueChange");
				[(ZGVariableController *)[windowController.undoManager prepareWithInvocationTarget:self]
				 changeVariable:variable
				 newValue:oldStringValue
				 shouldRecordUndo:YES];
				
				if (windowController.undoManager.isUndoing || windowController.undoManager.isRedoing)
				{
					[windowController.variablesTableView reloadData];
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
	ZGDocumentWindowController *windowController = _windowController;
	
	NSMutableIndexSet *undoableRowIndexes = [[NSMutableIndexSet alloc] init];
	NSUInteger currentIndex = rowIndexes.firstIndex;
	
	while (currentIndex != NSNotFound)
	{
		ZGVariable *variable = [_documentData.variables objectAtIndex:currentIndex];
		variable.enabled = enabled;
		if (variable.type == ZGScript)
		{
			if (variable.enabled)
			{
				[windowController.scriptManager runScriptForVariable:variable];
			}
			else
			{
				[windowController.scriptManager stopScriptForVariable:variable];
			}
		}
		else
		{
			[undoableRowIndexes addIndex:currentIndex];
		}
		
		currentIndex = [rowIndexes indexGreaterThanIndex:currentIndex];
	}
	
	if (!windowController.undoManager.isUndoing && !windowController.undoManager.isRedoing && undoableRowIndexes.count > 1)
	{
		windowController.variablesTableView.shouldIgnoreNextSelection = YES;
	}
	
	[self updateFrozenActivity];
	
	// the table view always needs to be reloaded because of being able to select multiple indexes
	[windowController.variablesTableView reloadData];
	
	if (undoableRowIndexes.count > 0)
	{
		NSString *activeChangeAction = (rowIndexes.count > 1) ? ZGLocalizedStringFromVariableActionsTable(@"undoMultipleActiveChange") : ZGLocalizedStringFromVariableActionsTable(@"undoSingleActiveChange");
		
		windowController.undoManager.actionName = activeChangeAction;
		
		[(ZGVariableController *)[windowController.undoManager prepareWithInvocationTarget:self]
		 changeVariableEnabled:!enabled
		 rowIndexes:undoableRowIndexes];
	}
}

#pragma mark Edit Variables Values

- (void)editVariables:(NSArray<ZGVariable *> *)variables newValues:(NSArray<NSString *> *)newValues
{
	ZGDocumentWindowController *windowController = _windowController;
	
	NSMutableArray<NSString *> *oldValues = [[NSMutableArray alloc] init];
	
	[variables enumerateObjectsUsingBlock:^(ZGVariable *variable, NSUInteger index, BOOL * __unused stop) {
		[oldValues addObject:variable.stringValue];
		 
		 [self
		  changeVariable:variable
		  newValue:[newValues objectAtIndex:index]
		  shouldRecordUndo:NO];
	 }];
	
	[windowController.variablesTableView reloadData];
	
	windowController.undoManager.actionName = ZGLocalizedStringFromVariableActionsTable(@"undoEditVariablesChange");
	[(ZGVariableController *)[windowController.undoManager prepareWithInvocationTarget:self]
	 editVariables:variables
	 newValues:oldValues];
}

#pragma mark Edit Variables Address

- (void)editVariable:(ZGVariable *)variable addressFormula:(NSString *)newAddressFormula
{
	ZGDocumentWindowController *windowController = _windowController;
	
	windowController.undoManager.actionName = ZGLocalizedStringFromVariableActionsTable(@"undoAddressChange");
	[(ZGVariableController *)[windowController.undoManager prepareWithInvocationTarget:self]
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
		
		[windowController.variablesTableView reloadData];
	}
	variable.finishedEvaluatingDynamicAddress = NO;
	
	[self annotateVariableAutomatically:variable process:windowController.currentProcess];
}

#pragma mark Relativizing Variable Addresses

- (void)unrelativizeVariables:(NSArray<ZGVariable *> *)variables
{
	for (ZGVariable *variable in variables)
	{
		variable.addressFormula = variable.addressStringValue;
		variable.usesDynamicAddress = NO;
	}
	
	NSString *actionName = (variables.count == 1) ? ZGLocalizedStringFromVariableActionsTable(@"undoUnrelativizeSingleVariable") : ZGLocalizedStringFromVariableActionsTable(@"undoUnrelativizeMultipleVariables");
	
	ZGDocumentWindowController *windowController = _windowController;
	windowController.undoManager.actionName = actionName;
	[(ZGVariableController *)[windowController.undoManager prepareWithInvocationTarget:self] relativizeVariables:variables];
}

- (void)relativizeVariables:(NSArray<ZGVariable *> *)variables
{
	ZGDocumentWindowController *windowController = _windowController;
	[[self class] annotateVariables:variables process:windowController.currentProcess];
	
	NSString *actionName = (variables.count == 1) ? ZGLocalizedStringFromVariableActionsTable(@"undoRelativizeSingleVariable") : ZGLocalizedStringFromVariableActionsTable(@"undoRelativizeMultipleVariables");
	
	windowController.undoManager.actionName = actionName;
	[(ZGVariableController *)[windowController.undoManager prepareWithInvocationTarget:self] unrelativizeVariables:variables];
}

+ (NSString *)relativizeVariable:(ZGVariable * __unsafe_unretained)variable withMachBinaries:(NSArray<ZGMachBinary *> *)machBinaries filePathDictionary:(NSDictionary<NSNumber *, NSString *> *)machFilePathDictionary process:(ZGProcess *)process
{
	NSString *staticVariableDescription = nil;
	
	ZGMachBinary *machBinary = [ZGMachBinary machBinaryNearestToAddress:variable.address fromMachBinaries:machBinaries];
	
	NSString *machFilePath = [machFilePathDictionary objectForKey:@(machBinary.filePathAddress)];
	
	if (machFilePath != nil)
	{
		ZGMachBinaryInfo *machBinaryInfo = [machBinary machBinaryInfoInProcess:process];
		NSString *segmentName = [machBinaryInfo segmentNameAtAddress:variable.address];
		
		if (segmentName != nil)
		{
			NSString *partialPath = [machFilePath lastPathComponent];
			if (machBinaryInfo.slide > 0 && !variable.usesDynamicAddress)
			{
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
				
				variable.addressFormula = [NSString stringWithFormat:ZGBaseAddressFunction@"(%@) + 0x%llX", baseArgument, variable.address - machBinary.headerAddress];
				variable.usesDynamicAddress = YES;
				variable.finishedEvaluatingDynamicAddress = YES;
			}
			
			staticVariableDescription = [NSString stringWithFormat:@"%@ %@ (static)", partialPath, segmentName];
		}
	}
	
	return staticVariableDescription;
}

- (void)annotateVariableAutomatically:(ZGVariable *)variable process:(ZGProcess *)process
{
	if (!variable.userAnnotated)
	{
		// Clear the description so we can automatically fill it again
		variable.fullAttributedDescription = [[NSAttributedString alloc] initWithString:@"" attributes:@{NSForegroundColorAttributeName : [NSColor textColor]}];
		
		// Update the variable's address
		ZGDocumentWindowController *windowController = _windowController;
		[windowController.tableController updateDynamicVariableAddress:variable];
		
		// Re-annotate the variable
		[[self class] annotateVariables:@[variable] process:process];
		[windowController.variablesTableView reloadData];
	}
}

+ (void)annotateVariables:(NSArray<ZGVariable *> *)variables process:(ZGProcess *)process
{
	ZGMemoryMap processTask = process.processTask;
	NSArray<ZGMachBinary *> *machBinaries = [ZGMachBinary machBinariesInProcess:process];
	NSMutableDictionary<NSNumber *, NSString *> *machFilePathDictionary = [[NSMutableDictionary alloc] init];
	
	for (ZGMachBinary *machBinary in machBinaries)
	{
		NSString *filePath = [machBinary filePathInProcess:process];
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
		NSString *staticDescription = [self relativizeVariable:variable withMachBinaries:machBinaries filePathDictionary:machFilePathDictionary process:process];
		
		NSString *symbol = [process.symbolicator symbolAtAddress:variable.address relativeOffset:NULL];

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
		
		NSMutableArray<NSString *> *validDescriptionComponents = [NSMutableArray array];
		if (symbol.length > 0) [validDescriptionComponents addObject:symbol];
		if (staticDescription != nil) [validDescriptionComponents addObject:staticDescription];
		if (userTagDescription != nil) [validDescriptionComponents addObject:userTagDescription];
		if (protectionDescription != nil) [validDescriptionComponents addObject:protectionDescription];
		
		if (variable.fullAttributedDescription.length == 0)
		{
			variable.fullAttributedDescription = [[NSAttributedString alloc] initWithString:[validDescriptionComponents componentsJoinedByString:@", "] attributes:@{NSForegroundColorAttributeName : [NSColor textColor]}];
		}
		else
		{
			NSString *appendedString = [NSString stringWithFormat:@"\n\n%@", [validDescriptionComponents componentsJoinedByString:@"\n"]];
			NSMutableAttributedString *newDescription = [variable.fullAttributedDescription mutableCopy];
			[newDescription appendAttributedString:[[NSAttributedString alloc] initWithString:appendedString attributes:@{NSForegroundColorAttributeName : [NSColor textColor]}]];
			variable.fullAttributedDescription = newDescription;
		}
	}
}

#pragma mark Edit Variables Sizes (Byte Arrays)

- (void)editVariables:(NSArray<ZGVariable *> *)variables requestedSizes:(NSArray<NSNumber *> *)requestedSizes
{
	NSMutableArray<NSNumber *> *currentVariableSizes = [[NSMutableArray alloc] init];
	NSMutableArray<ZGVariable *> *validVariables = [[NSMutableArray alloc] init];
	
	ZGDocumentWindowController *windowController = _windowController;
	
	// Make sure the size changes are possible. Only change the ones that seem possible.
	[variables enumerateObjectsUsingBlock:^(ZGVariable *variable, NSUInteger index, BOOL * __unused stop)
	 {
		 ZGMemorySize size = [[requestedSizes objectAtIndex:index] unsignedLongLongValue];
		 void *buffer = NULL;
		 
		 if (ZGReadBytes(windowController.currentProcess.processTask, variable.address, &buffer, &size))
		 {
			 if (size == [[requestedSizes objectAtIndex:index] unsignedLongLongValue])
			 {
				 [validVariables addObject:variable];
				 [currentVariableSizes addObject:@(variable.size)];
			 }
			 
			 ZGFreeBytes(buffer, size);
		 }
	 }];
	
	if (validVariables.count > 0)
	{
		windowController.undoManager.actionName = ZGLocalizedStringFromVariableActionsTable(@"undoSizeChange");
		[(ZGVariableController *)[windowController.undoManager prepareWithInvocationTarget:self]
		 editVariables:validVariables
		 requestedSizes:currentVariableSizes];
		
		[validVariables enumerateObjectsUsingBlock:^(ZGVariable *variable, NSUInteger index, BOOL * __unused stop)
		 {
			 variable.size = [[requestedSizes objectAtIndex:index] unsignedLongLongValue];
		 }];
		
		[windowController.variablesTableView reloadData];
	}
	else
	{
		ZGRunAlertPanelWithOKButton(ZGLocalizedStringFromVariableActionsTable(@"failedChangeSizeAlertTitle"), ZGLocalizedStringFromVariableActionsTable(@"failedChangeSizeAlertMessage"));
	}
}

@end
