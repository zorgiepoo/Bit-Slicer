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

- (void)freezeOrUnfreezeVariablesAtRowIndexes:(NSIndexSet *)rowIndexes
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

	[(ZGVariableController *)[windowController.undoManager prepareWithInvocationTarget:self] freezeOrUnfreezeVariablesAtRowIndexes:rowIndexes];
}

- (void)freezeVariables
{
	ZGDocumentWindowController *windowController = _windowController;
	[self freezeOrUnfreezeVariablesAtRowIndexes:windowController.selectedVariableIndexes];
}

#pragma mark Copying & Pasting

+ (void)copyVariableAddress:(ZGVariable *)variable
{
	[NSPasteboard.generalPasteboard
	 declareTypes:@[NSPasteboardTypeString]
	 owner:self];

	[NSPasteboard.generalPasteboard
	 setString:variable.addressFormula
	 forType:NSPasteboardTypeString];
}

- (void)copyAddress
{
	ZGDocumentWindowController *windowController = _windowController;
	[[self class] copyVariableAddress:windowController.selectedVariables[0]];
}

+ (void)copyVariableRawAddress:(ZGVariable *)variable
{
	[NSPasteboard.generalPasteboard
	 declareTypes:@[NSPasteboardTypeString]
	 owner:self];

	[NSPasteboard.generalPasteboard
	 setString:variable.addressStringValue
	 forType:NSPasteboardTypeString];
}

- (void)copyRawAddress
{
	ZGDocumentWindowController *windowController = _windowController;
	ZGVariable *variable = windowController.selectedVariables[0];

	[[self class] copyVariableRawAddress:variable];
}

+ (BOOL)copyVariablesToPasteboard:(NSArray<ZGVariable *> *)variables
{
	[NSPasteboard.generalPasteboard
	 declareTypes:@[NSPasteboardTypeString, ZGVariablePboardType]
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
	 forType:NSPasteboardTypeString];

	NSError *archiveError = nil;
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:variables requiringSecureCoding:YES error:&archiveError];
	if (data != nil)
	{
		[NSPasteboard.generalPasteboard
		 setData:data
		 forType:ZGVariablePboardType];
		return YES;
	}
	else
	{
		NSLog(@"Error: failed to copy variables to pasteboard: %@", archiveError);
		return NO;
	}
}

- (void)copyVariables
{
	ZGDocumentWindowController *windowController = _windowController;
	if (![[self class] copyVariablesToPasteboard:[windowController selectedVariables]])
	{
		ZGRunAlertPanelWithOKButton(@"Copy Failed", @"Failed to copy variables to pasteboard. There may be an issue with the data format.");
	}
}

- (void)pasteVariables
{
	NSData *pasteboardData = [NSPasteboard.generalPasteboard dataForType:ZGVariablePboardType];
	if (pasteboardData)
	{
		ZGDocumentWindowController *windowController = _windowController;

		NSError *unarchiveError = nil;
		NSArray<ZGVariable *> *variablesToInsertArray = [NSKeyedUnarchiver unarchivedObjectOfClasses:[NSSet setWithArray:@[[NSArray class], [ZGVariable class]]] fromData:pasteboardData error:&unarchiveError];
		if (variablesToInsertArray != nil)
		{
			NSUInteger currentIndex = windowController.selectedVariableIndexes.count == 0 ? 0 : windowController.selectedVariableIndexes.firstIndex + 1;

			NSIndexSet *indexesToInsert = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(currentIndex, variablesToInsertArray.count)];

			[self
			 addVariables:variablesToInsertArray
			 atRowIndexes:indexesToInsert];
		}
		else
		{
			NSLog(@"Error: failed to unarchive variables from pasteboard for pasting with error %@", unarchiveError);
			ZGRunAlertPanelWithOKButton(@"Paste Failed", @"Failed to paste variables from pasteboard. The data may be corrupted or in an incompatible format.");
		}
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

	BOOL removedAnyLabelVariable = NO;
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

		if (!removedAnyLabelVariable && variable.label.length > 0)
		{
			removedAnyLabelVariable = YES;
		}
	}

	[temporaryArray addObjectsFromArray:_documentData.variables];
	[temporaryArray removeObjectsAtIndexes:rowIndexes];

	_documentData.variables = [temporaryArray copy];

	[windowController.searchController fetchVariablesFromResults];

	[windowController updateNumberOfValuesDisplayedStatus];

	[self updateFrozenActivity];
	[windowController.tableController updateWatchVariablesTimer];
	[windowController.variablesTableView reloadData];

	NSUInteger firstRemovedIndex = rowIndexes.firstIndex;
	if (firstRemovedIndex > 0)
	{
		[windowController.variablesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:firstRemovedIndex - 1] byExtendingSelection:NO];
	}

	[windowController updateSearchAddressOptions];

	if (removedAnyLabelVariable)
	{
		// Re-annotate other variables that may be referencing variables that were just removed
		NSMutableArray<ZGVariable *> *variablesToAnnotate = [NSMutableArray array];
		for (ZGVariable *variable in _documentData.variables)
		{
			if (variable.usesDynamicLabelAddress)
			{
				[variablesToAnnotate addObject:variable];
			}
		}

		[self annotateVariablesAutomatically:variablesToAnnotate process:windowController.currentProcess];
	}
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

- (NSSet<NSString *> *)usedLabels
{
	NSMutableSet<NSString *> *labels = [[NSMutableSet alloc] init];
	for (ZGVariable *variable in _documentData.variables)
	{
		NSString *label = variable.label;
		if (label.length > 0)
		{
			[labels addObject:label];
		}
	}

	return labels;
}

- (nullable ZGVariable *)variableForLabel:(NSString *)label
{
	// We could maintain a dictionary cache for label -> variable lookups
	// However I don't believe the complexity of managing changes to this state is worth it
	// and it should not be a bottleneck realistically
	for (ZGVariable *variable in _documentData.variables)
	{
		if ([variable.label isEqualToString:label])
		{
			return variable;
		}
	}
	return nil;
}

- (void)addVariables:(NSArray<ZGVariable *> *)variables atRowIndexes:(NSIndexSet *)rowIndexes
{
	ZGDocumentWindowController *windowController = _windowController;

	// Make sure we do not end up with duplicate labels
	// New variables that have a label that already exists have their labels removed
	NSSet<NSString *> *oldLabels = [self usedLabels];
	for (ZGVariable *variable in variables)
	{
		NSString *label = variable.label;
		if (label.length > 0)
		{
			if ([oldLabels containsObject:label])
			{
				variable.label = @"";
			}
		}
	}

	// Also make sure we don't end up with new cycles caused by labels
	BOOL addedLabeledVariable = NO;
	for (ZGVariable *variable in variables)
	{
		NSString *label = variable.label;
		if (label.length > 0)
		{
			NSArray<NSString *> *cycleInfo = nil;
			if ([ZGCalculator getVariableCycle:&cycleInfo variable:variable variableController:self])
			{
				NSLog(@"Error: failed to assign label '%@' to added variable ('%@') due to cycle '%@'", variable.label, variable.addressFormula, [cycleInfo componentsJoinedByString:@" → "]);
				variable.label = @"";
			}
			else
			{
				addedLabeledVariable = YES;
			}
		}
	}

	NSMutableArray<ZGVariable *> *temporaryArray = [[NSMutableArray alloc] initWithArray:_documentData.variables];
	[temporaryArray insertObjects:variables atIndexes:rowIndexes];

	[self disableHarmfulVariables:variables];

	_documentData.variables = [temporaryArray copy];

	[windowController.tableController updateWatchVariablesTimer];
	[windowController.variablesTableView reloadData];

	[windowController.variablesTableView selectRowIndexes:rowIndexes byExtendingSelection:NO];

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
	[windowController updateSearchAddressOptions];

	if (!addedLabeledVariable)
	{
		[self annotateVariablesAutomatically:variables process:windowController.currentProcess];
	}
	else
	{
		// Update annotations for all variables that reference labels as well as the variables we just added
		// It's possible any of these variables may be referencing a label to a variable we just added
		NSMutableOrderedSet<ZGVariable *> *variablesToAnnotate = [NSMutableOrderedSet orderedSetWithArray:variables];

		for (ZGVariable *variable in _documentData.variables)
		{
			if ([variablesToAnnotate containsObject:variable])
			{
				continue;
			}

			if (variable.usesDynamicLabelAddress)
			{
				[variablesToAnnotate addObject:variable];
			}
		}

		[self annotateVariablesAutomatically:variablesToAnnotate.array process:windowController.currentProcess];
	}
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
		 description:[[NSAttributedString alloc] initWithString:variableType == ZGScript ? ZGLocalizedStringFromVariableActionsTable(@"defaultScriptDescription") : @"" attributes:@{NSForegroundColorAttributeName : [NSColor textColor]}]
		 enabled:NO
		 byteOrder:byteOrder];

	if (variable.type == ZGScript)
	{
		BOOL usingTabs = [[NSUserDefaults standardUserDefaults] boolForKey:ZGScriptIndentationUsingTabsKey];
		NSUInteger spacesWidth = (NSUInteger)[[NSUserDefaults standardUserDefaults] integerForKey:ZGScriptIndentationSpacesWidthKey];
		NSString *indentationString =
		usingTabs ? @"\t" :
		[@"" stringByPaddingToLength:spacesWidth withString:@" " startingAtIndex:0]; // Creates a string with 'spacesWidth' number of spaces

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

	// If the selected variable is enabled, insert the variable at the top of the table
	// Otherwise insert the variable at one row above the selected variable row
	NSUInteger insertRowIndex;
	ZGVariable *selectedVariable = windowController.selectedVariables.firstObject;
	if (selectedVariable == nil || (selectedVariable.enabled && selectedVariable.type != ZGScript && !selectedVariable.isFrozen))
	{
		insertRowIndex = 0;
	}
	else
	{
		NSIndexSet *selectedVariableIndexes = windowController.selectedVariableIndexes;
		insertRowIndex = selectedVariableIndexes.firstIndex + 1;
	}

	[self
	 addVariables:@[variable]
	 atRowIndexes:[NSIndexSet indexSetWithIndex:insertRowIndex]];
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
		NSString *oldValue = variable.stringValue;
		[self changeVariable:variable newValue:[newValues objectAtIndex:variableIndex] shouldRecordUndo:NO];

		// Check if the value was actually changed
		if ([oldValue isEqualToString:variable.stringValue])
		{
			completeSuccess = NO;
		}
	}

	ZGDocumentWindowController *windowController = _windowController;
	windowController.undoManager.actionName = ZGLocalizedStringFromVariableActionsTable(@"undoNOPChangeAction");
	[(ZGVariableController *)[windowController.undoManager prepareWithInvocationTarget:self]
	 nopVariables:variables
	 withNewValues:oldValues];

	return completeSuccess;
}

- (void)nopVariables:(NSArray<ZGVariable *> *)variables process:(ZGProcess *)process
{
	NSMutableArray<NSString *> *nopValues = [[NSMutableArray alloc] init];
	ZGProcessType processType = process.type;

	for (ZGVariable *variable in variables)
	{
		NSArray<NSString *> *nopComponents;

		if (ZG_PROCESS_TYPE_IS_ARM64(processType))
		{
			nopComponents = @[@"1F", @"20", @"03", @"D5"];
		}
		else
		{
			NSMutableArray<NSString *> *mutableNopComponents = [[NSMutableArray alloc] init];
			for (NSUInteger index = 0; index < variable.size; index++)
			{
				[mutableNopComponents addObject:@"90"];
			}
			nopComponents = mutableNopComponents;
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

	[windowController updateSearchAddressOptions];
}

- (const void *)prepareValueForNumericType:(ZGVariableType)variableType fromString:(NSString *)stringObject outValue:(void **)outAllocatedMemory
{
	void *allocatedMemory = NULL;
	const void *result = NULL;

	switch (variableType)
	{
		case ZGInt8:
		{
			int8_t *value = malloc(sizeof(int8_t));
			*value = (int8_t)stringObject.intValue;
			allocatedMemory = value;
			result = value;
			break;
		}
		case ZGInt16:
		{
			int16_t *value = malloc(sizeof(int16_t));
			*value = (int16_t)stringObject.intValue;
			allocatedMemory = value;
			result = value;
			break;
		}
		case ZGInt32:
		{
			int32_t *value = malloc(sizeof(int32_t));
			*value = stringObject.intValue;
			allocatedMemory = value;
			result = value;
			break;
		}
		case ZGFloat:
		{
			float *value = malloc(sizeof(float));
			*value = stringObject.floatValue;
			allocatedMemory = value;
			result = value;
			break;
		}
		case ZGInt64:
		{
			int64_t *value = malloc(sizeof(int64_t));
			[[NSScanner scannerWithString:stringObject] scanLongLong:value];
			allocatedMemory = value;
			result = value;
			break;
		}
		case ZGDouble:
		{
			double *value = malloc(sizeof(double));
			*value = stringObject.doubleValue;
			allocatedMemory = value;
			result = value;
			break;
		}
		default:
			break;
	}

	if (outAllocatedMemory != NULL) {
		*outAllocatedMemory = allocatedMemory;
	}

	return result;
}

- (const void *)prepareValueForString8Type:(NSString *)stringObject variable:(ZGVariable *)variable outWriteSize:(ZGMemorySize *)outWriteSize
{
	const void *newValue = (const void *)[stringObject cStringUsingEncoding:NSUTF8StringEncoding];
	variable.size = strlen(newValue) + 1;
	if (outWriteSize != NULL) {
		*outWriteSize = variable.size;
	}
	return newValue;
}

- (const void *)prepareValueForString16Type:(NSString *)stringObject variable:(ZGVariable *)variable outAllocatedMemory:(void **)outAllocatedMemory outWriteSize:(ZGMemorySize *)outWriteSize
{
	void *allocatedMemory = NULL;
	const void *result = NULL;

	variable.size = [stringObject length] * sizeof(unichar);
	ZGMemorySize writeSize = variable.size;

	if (variable.size > 0)
	{
		void *utf16Value = malloc((size_t)variable.size);
		result = utf16Value;
		allocatedMemory = utf16Value;
		[stringObject getCharacters:utf16Value range:NSMakeRange(0, stringObject.length)];
	}
	else
	{
		// String "" can be of 0 length
		void *utf16Value = malloc(sizeof(unichar));
		result = utf16Value;
		allocatedMemory = utf16Value;

		if (utf16Value != NULL)
		{
			unichar nullTerminator = 0;
			memcpy(utf16Value, &nullTerminator, sizeof(unichar));
		}
	}

	if (outAllocatedMemory != NULL) {
		*outAllocatedMemory = allocatedMemory;
	}

	if (outWriteSize != NULL) {
		*outWriteSize = writeSize;
	}

	return result;
}

- (const void *)prepareValueForByteArrayType:(NSString *)stringObject variable:(ZGVariable *)variable outAllocatedMemory:(void **)outAllocatedMemory outWriteSize:(ZGMemorySize *)outWriteSize
{
	ZGDocumentWindowController *windowController = _windowController;
	void *allocatedMemory = NULL;
	const void *result = NULL;
	ZGMemorySize writeSize = 0;

	NSArray<NSString *> *bytesArray = ZGByteArrayComponentsFromString(stringObject);

	if (variable.size != bytesArray.count)
	{
		// this is the size the user wants
		[self editVariables:@[variable] requestedSizes:@[@(bytesArray.count)]];
	}

	// Update old string value to be the same size as new string value, so that undo/redo's from one size to another will work more nicely
	NSString *oldStringValue = variable.stringValue;
	void *oldData = NULL;
	ZGMemorySize oldSize = variable.size;

	if (ZGReadBytes(windowController.currentProcess.processTask, variable.address, &oldData, &oldSize))
	{
		ZGVariable *oldVariable = [[ZGVariable alloc] initWithValue:oldData size:oldSize address:variable.address type:ZGByteArray qualifier:variable.qualifier pointerSize:windowController.currentProcess.pointerSize description:variable.fullAttributedDescription enabled:variable.enabled byteOrder:variable.byteOrder];

		oldStringValue = oldVariable.stringValue;

		ZGFreeBytes(oldData, oldSize);
	}

	// this is the maximum size allocated needed
	void *byteArrayValue = malloc((size_t)variable.size);
	result = byteArrayValue;
	allocatedMemory = byteArrayValue;

	if (byteArrayValue != NULL)
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

	if (outAllocatedMemory != NULL) {
		*outAllocatedMemory = allocatedMemory;
	}

	if (outWriteSize != NULL) {
		*outWriteSize = writeSize;
	}

	return result;
}

- (void)recordUndoForVariable:(ZGVariable *)variable oldValue:(NSString *)oldStringValue shouldRecordUndo:(BOOL)recordUndoFlag
{
	if (!recordUndoFlag) return;

	ZGDocumentWindowController *windowController = _windowController;
	NSString *actionName = variable.isFrozen ? 
		ZGLocalizedStringFromVariableActionsTable(@"undoFreezeValueChange") : 
		ZGLocalizedStringFromVariableActionsTable(@"undoValueChange");

	windowController.undoManager.actionName = actionName;
	[(ZGVariableController *)[windowController.undoManager prepareWithInvocationTarget:self]
	 changeVariable:variable
	 newValue:oldStringValue
	 shouldRecordUndo:YES];

	if (windowController.undoManager.isUndoing || windowController.undoManager.isRedoing)
	{
		[windowController.variablesTableView reloadData];
	}
}

- (void)changeVariable:(ZGVariable *)variable newValue:(NSString *)stringObject shouldRecordUndo:(BOOL)recordUndoFlag
{	
	const void *newValue = NULL;
	ZGMemorySize writeSize = variable.size; // specifically needed for byte arrays

	// It's important to retrieve this now instead of later as changing the variable's size may cause a bad side effect to this method
	NSString *oldStringValue = [variable.stringValue copy];

	void *allocatedMemory = NULL;

	if (ZGIsNumericalDataType(variable.type))
	{
		stringObject = [ZGCalculator evaluateExpression:stringObject];
	}

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

	// Handle different variable types
	switch (variableType)
	{
		case ZGInt8:
		case ZGInt16:
		case ZGInt32:
		case ZGFloat:
		case ZGInt64:
		case ZGDouble:
			newValue = [self prepareValueForNumericType:variableType fromString:stringObject outValue:&allocatedMemory];
			break;

		case ZGString8:
			newValue = [self prepareValueForString8Type:stringObject variable:variable outWriteSize:&writeSize];
			break;

		case ZGString16:
			newValue = [self prepareValueForString16Type:stringObject variable:variable outAllocatedMemory:&allocatedMemory outWriteSize:&writeSize];
			break;

		case ZGByteArray:
			newValue = [self prepareValueForByteArrayType:stringObject variable:variable outAllocatedMemory:&allocatedMemory outWriteSize:&writeSize];
			break;

		case ZGPointer:
		case ZGScript:
			break;
	}

	if (newValue != NULL)
	{
		void *swappedValue = NULL;
		if (variable.byteOrder != CFByteOrderGetCurrent())
		{
			swappedValue = ZGSwappedValue(windowController.currentProcess.type, newValue, variableType, writeSize);
			newValue = swappedValue;
		}

		if (variable.isFrozen)
		{
			variable.freezeValue = newValue;
			[self recordUndoForVariable:variable oldValue:oldStringValue shouldRecordUndo:recordUndoFlag];
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

			if (successfulWrite)
			{
				[self recordUndoForVariable:variable oldValue:oldStringValue shouldRecordUndo:recordUndoFlag];
			}
		}

		free(swappedValue);
	}

	free(allocatedMemory);
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

	[windowController updateSearchAddressOptions];

	if (undoableRowIndexes.count > 0)
	{
		NSString *activeChangeAction = (rowIndexes.count > 1) ? ZGLocalizedStringFromVariableActionsTable(@"undoMultipleActiveChange") : ZGLocalizedStringFromVariableActionsTable(@"undoSingleActiveChange");

		windowController.undoManager.actionName = activeChangeAction;

		[(ZGVariableController *)[windowController.undoManager prepareWithInvocationTarget:self]
		 changeVariableEnabled:!enabled
		 rowIndexes:undoableRowIndexes];
	}
}

- (void)relateVariables:(NSArray<ZGVariable *> *)variables toLabeledVariable:(ZGVariable *)labeledVariable
{
	ZGDocumentWindowController *windowController = _windowController;
	ZGProcess *process = windowController.currentProcess;

	ZGMemoryAddress mainBinaryHeaderAddress = process.mainMachBinary.headerAddress;

	// If there are any duplicate addresses or any address < mainBinaryHeaderAddress
	// we will assume the variable's addresses are not meaningful and can be overwritten based on stride
	// Otherwise we will assume the current addresses are meaningful and are relative to the labeled variable
	ZGMemoryAddress labeledVariableAddress = labeledVariable.address;
	NSMutableSet<NSNumber *> *visitedAddresses = [NSMutableSet set];
	BOOL currentAddressesRelatable = YES;
	for (ZGVariable *variable in variables)
	{
		if (variable.address < mainBinaryHeaderAddress)
		{
			currentAddressesRelatable = NO;
			break;
		}

		NSNumber *variableAddress = @(variable.address);
		if ([visitedAddresses containsObject:variableAddress])
		{
			currentAddressesRelatable = NO;
			break;
		}

		[visitedAddresses addObject:variableAddress];
	}

	NSMutableArray<NSString *> *newAddressFormulas = [NSMutableArray array];
	NSString *label = labeledVariable.label;
	if (!currentAddressesRelatable)
	{
		ZGMemoryAddress currentAddress = labeledVariableAddress + labeledVariable.size;

		ZGProcessType processType = process.type;
		for (ZGVariable *variable in variables)
		{
			ZGMemorySize variableSize = variable.size;

			// Fix any data potential data alignment
			ZGMemorySize dataAlignment = ZGDataAlignment(processType, variable.type, variableSize);
			ZGMemorySize unalignedSize = (currentAddress % dataAlignment);
			if (unalignedSize != 0)
			{
				currentAddress += dataAlignment - unalignedSize;
			}

			NSString *newAddressFormula = [NSString stringWithFormat:@"label(\"%@\") + 0x%llX", label, currentAddress - labeledVariableAddress];

			[newAddressFormulas addObject:newAddressFormula];

			currentAddress += variableSize;
		}
	}
	else
	{
		for (ZGVariable *variable in variables)
		{
			ZGMemoryAddress variableAddress = variable.address;
			NSString *newAddressFormula;
			if (variableAddress >= labeledVariableAddress)
			{
				newAddressFormula = [NSString stringWithFormat:@"label(\"%@\") + 0x%llX", label, variableAddress - labeledVariableAddress];
			}
			else
			{
				newAddressFormula = [NSString stringWithFormat:@"label(\"%@\") - 0x%llX", label, labeledVariableAddress - variableAddress];
			}

			[newAddressFormulas addObject:newAddressFormula];
		}
	}

	NSString *cycleInfo = nil;
	if (![self editVariables:variables addressFormulas:newAddressFormulas cycleInfo:&cycleInfo])
	{
		ZGRunAlertPanelWithOKButton(ZGLocalizedStringFromVariableActionsTable(@"failedRelateVariablesAlertTitle"), [NSString stringWithFormat:ZGLocalizedStringFromVariableActionsTable(@"failedRelateVariablesAlertMessageFormat"), cycleInfo]);
	}
}

#pragma mark Edit Variables Values

- (void)setupUndoWithActionName:(NSString *)actionName target:(id)target selector:(SEL)selector withObjects:(NSArray *)objects
{
	ZGDocumentWindowController *windowController = _windowController;
	windowController.undoManager.actionName = actionName;

	NSMethodSignature *signature = [target methodSignatureForSelector:selector];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
	[invocation setSelector:selector];
	[invocation setTarget:target];

	for (NSUInteger i = 0; i < objects.count; i++) {
		id object = objects[i];
		[invocation setArgument:&object atIndex:i + 2]; // +2 because first two args are self and _cmd
	}

	[[windowController.undoManager prepareWithInvocationTarget:self] forwardInvocation:invocation];
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
	[invocation invoke];
}

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

	[self setupUndoWithActionName:ZGLocalizedStringFromVariableActionsTable(@"undoEditVariablesChange")
						   target:self
						 selector:@selector(editVariables:newValues:)
					  withObjects:@[variables, oldValues]];
}

#pragma mark Edit Variables Address

- (BOOL)checkForCyclesInVariables:(NSArray<ZGVariable *> *)variables withNewAddressFormulas:(NSArray<NSString *> *)newAddressFormulas oldAddressFormulas:(NSArray<NSString *> *)oldAddressFormulas cycleInfo:(NSString * __autoreleasing *)outCycleInfo
{
	// Apply new address formulas
	NSUInteger variableIndex = 0;
	for (ZGVariable *variable in variables)
	{
		NSString *newAddressFormula = newAddressFormulas[variableIndex];
		variable.addressFormula = newAddressFormula;
		variableIndex++;
	}

	// Check for cycles
	for (ZGVariable *variable in variables)
	{
		NSArray *cycleInfo = nil;
		if ([ZGCalculator getVariableCycle:&cycleInfo variable:variable variableController:self])
		{
			NSString *cycleInfoString = [cycleInfo componentsJoinedByString:@" → "];
			NSLog(@"Error: found cycle (%@) while editing address of %@", cycleInfoString, variable.addressFormula);
			if (outCycleInfo != NULL)
			{
				*outCycleInfo = cycleInfoString;
			}

			// Restore old address formulas
			variableIndex = 0;
			for (ZGVariable *var in variables)
			{
				NSString *oldAddressFormula = oldAddressFormulas[variableIndex];
				var.addressFormula = oldAddressFormula;
				variableIndex++;
			}

			return YES; // Found cycle
		}
	}

	return NO; // No cycles found
}

- (void)updateVariableAddressProperties:(NSArray<ZGVariable *> *)variables
{
	ZGDocumentWindowController *windowController = _windowController;
	BOOL needsToReloadTable = NO;

	for (ZGVariable *variable in variables)
	{
		if (variable.usesDynamicPointerAddress || variable.usesDynamicBaseAddress || variable.usesDynamicSymbolAddress || variable.usesDynamicLabelAddress)
		{
			variable.usesDynamicAddress = YES;
		}
		else
		{
			variable.usesDynamicAddress = NO;
			variable.addressStringValue = [ZGCalculator evaluateExpression:variable.addressFormula];
			needsToReloadTable = YES;
		}
		variable.finishedEvaluatingDynamicAddress = NO;
	}

	if (needsToReloadTable)
	{
		[windowController.variablesTableView reloadData];
	}
}

- (void)annotateVariablesWithLabels:(NSArray<ZGVariable *> *)variables
{
	ZGDocumentWindowController *windowController = _windowController;
	NSMutableOrderedSet<ZGVariable *> *variablesToAnnotate = [NSMutableOrderedSet orderedSetWithArray:variables];

	// Check if any variable has a label
	BOOL anyVariableHasLabel = NO;
	for (ZGVariable *variable in variables)
	{
		if (variable.label.length > 0)
		{
			anyVariableHasLabel = YES;
			break;
		}
	}

	if (anyVariableHasLabel)
	{
		// Other variables may be referencing this variable
		// We will want to update their annotations too
		for (ZGVariable *otherVariable in _documentData.variables)
		{
			if ([variablesToAnnotate containsObject:otherVariable])
			{
				continue;
			}

			if (otherVariable.usesDynamicLabelAddress)
			{
				[variablesToAnnotate addObject:otherVariable];
			}
		}
	}

	[self annotateVariablesAutomatically:variablesToAnnotate.array process:windowController.currentProcess];
}

- (BOOL)editVariables:(NSArray<ZGVariable *> *)variables addressFormulas:(NSArray<NSString *> *)newAddressFormulas cycleInfo:(NSString * __autoreleasing *)outCycleInfo
{
	// Get old address formulas for undo
	NSArray<NSString *> *oldAddressFormulas = [variables zgMapUsingBlock:^id _Nonnull(ZGVariable *variable) {
		return variable.addressFormula;
	}];

	// Check for cycles
	if ([self checkForCyclesInVariables:variables withNewAddressFormulas:newAddressFormulas oldAddressFormulas:oldAddressFormulas cycleInfo:outCycleInfo])
	{
		return NO;
	}

	// Set up undo
	NSString *undoActionName = (variables.count == 1) ? 
		ZGLocalizedStringFromVariableActionsTable(@"undoAddressChange") : 
		ZGLocalizedStringFromVariableActionsTable(@"undoAddressChanges");

	[self setupUndoWithActionName:undoActionName
						   target:self
						 selector:@selector(editVariables:addressFormulas:cycleInfo:)
					  withObjects:@[variables, oldAddressFormulas, [NSNull null]]];

	// Update variable properties
	[self updateVariableAddressProperties:variables];

	// Annotate variables with labels
	[self annotateVariablesWithLabels:variables];

	// Update UI
	[_windowController updateSearchAddressOptions];

	return YES;
}

#pragma mark Edit Variable Labels

- (BOOL)checkForCyclesInVariablesWithLabels:(NSArray<ZGVariable *> *)variables oldLabels:(NSArray<NSString *> *)oldLabels cycleInfo:(NSString * __autoreleasing *)outCycleInfo
{
	for (ZGVariable *variable in variables)
	{
		NSArray<NSString *> *cycleInfo = nil;
		if ([ZGCalculator getVariableCycle:&cycleInfo variable:variable variableController:self])
		{
			NSString *cycleInfoString = [cycleInfo componentsJoinedByString:@" → "];
			NSLog(@"Error: detected cycle (%@) while assigning variable (%@) label '%@'", cycleInfoString, variable.addressFormula, variable.label);
			if (outCycleInfo != NULL)
			{
				*outCycleInfo = cycleInfoString;
			}

			// Restore old labels
			NSUInteger labelIndex = 0;
			for (ZGVariable *var in variables)
			{
				var.label = oldLabels[labelIndex];
				labelIndex++;
			}

			return YES; // Found cycle
		}
	}

	return NO; // No cycles found
}

- (BOOL)editVariables:(NSArray<ZGVariable *> *)variables requestedLabels:(NSArray<NSString *> *)requestedLabels cycleInfo:(NSString * __autoreleasing *)outCycleInfo
{
	// Get old labels for undo
	NSArray<NSString *> *oldLabels = [variables zgMapUsingBlock:^(ZGVariable *variable) {
		return variable.label;
	}];

	// Apply new labels
	NSUInteger labelIndex = 0;
	for (ZGVariable *variable in variables)
	{
		variable.label = requestedLabels[labelIndex];
		labelIndex++;
	}

	// Check for cycles
	if ([self checkForCyclesInVariablesWithLabels:variables oldLabels:oldLabels cycleInfo:outCycleInfo])
	{
		return NO;
	}

	// Set up undo
	[self setupUndoWithActionName:ZGLocalizedStringFromVariableActionsTable(@"undoLabelChange")
						   target:self
						 selector:@selector(editVariables:requestedLabels:cycleInfo:)
					  withObjects:@[variables, oldLabels, [NSNull null]]];

	// Annotate variables with labels
	[self annotateVariablesWithLabels:variables];

	return YES;
}

#pragma mark Relativizing Variable Addresses

- (void)relativizeVariables:(NSArray<ZGVariable *> *)variables
{
	ZGDocumentWindowController *windowController = _windowController;
	[self annotateVariablesAutomatically:variables process:windowController.currentProcess];
}

+ (BOOL)determineVariableAddressAndIndirectStatus:(ZGVariable *)variable 
                                                  process:(ZGProcess *)process 
                                       variableController:(ZGVariableController *)variableController 
                                             failedImages:(NSMutableArray<NSString *> *)failedImages 
                                            outIsIndirect:(BOOL *)outIsIndirect
                                          outVariableAddress:(ZGMemoryAddress *)outVariableAddress
{
	ZGMemoryAddress variableAddress;
	BOOL isIndirectVariable;

	if (variable.usesDynamicLabelAddress)
	{
		// It's not obvious if a variable that uses a label is indirect or not, so we will need
		// to try computing the indirect base address to find out
		ZGMemoryAddress baseAddress = 0x0;
		isIndirectVariable = [ZGCalculator extractIndirectBaseAddress:&baseAddress 
														   expression:variable.addressFormula 
															  process:process 
													variableController:variableController 
														 failedImages:failedImages];

		variableAddress = isIndirectVariable ? baseAddress : variable.address;
	}
	else if (variable.usesDynamicPointerAddress)
	{
		if (![ZGCalculator extractIndirectBaseAddress:&variableAddress 
										   expression:variable.addressFormula 
											  process:process 
									variableController:variableController 
										 failedImages:failedImages])
		{
			if (outVariableAddress != NULL)
			{
				*outVariableAddress = variable.address;
			}
			return NO;
		}

		isIndirectVariable = YES;
	}
	else
	{
		variableAddress = variable.address;
		isIndirectVariable = NO;
	}

	if (outVariableAddress != NULL)
	{
		*outVariableAddress = variableAddress;
	}

	if (outIsIndirect != NULL)
	{
		*outIsIndirect = isIndirectVariable;
	}

	return YES;
}

+ (NSString *)createBaseFormulaForVariable:(ZGVariable *)variable 
                              machBinaries:(NSArray<ZGMachBinary *> *)machBinaries
                        filePathDictionary:(NSDictionary<NSNumber *, NSString *> *)machFilePathDictionary
                                machBinary:(ZGMachBinary *)machBinary
                                machFilePath:(NSString *)machFilePath
                           variableAddress:(ZGMemoryAddress)variableAddress
                            isIndirectVariable:(BOOL)isIndirectVariable
{
	NSString *partialPath = [machFilePath lastPathComponent];

	if (variable.usesDynamicBaseAddress || variable.usesDynamicSymbolAddress || variable.usesDynamicLabelAddress)
	{
		return nil;
	}

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

	NSString *baseFormula = [NSString stringWithFormat:ZGBaseAddressFunction@"(%@) + 0x%llX", baseArgument, variableAddress - machBinary.headerAddress];

	if (isIndirectVariable)
	{
		NSString *pointerReference = [NSString stringWithFormat:@"[0x%llX]", variableAddress];
		variable.addressFormula = [variable.addressFormula stringByReplacingOccurrencesOfString:pointerReference withString:[NSString stringWithFormat:@"[%@]", baseFormula]];
	}
	else
	{
		variable.addressFormula = baseFormula;
	}

	variable.usesDynamicAddress = YES;
	variable.finishedEvaluatingDynamicAddress = !isIndirectVariable;

	return partialPath;
}

+ (NSString *)createDescriptionForPartialPath:(NSString *)partialPath 
                                machBinaryInfo:(ZGMachBinaryInfo *)machBinaryInfo
                              variableAddress:(ZGMemoryAddress)variableAddress
                           isIndirectVariable:(BOOL)isIndirectVariable
{
	if (partialPath == nil)
	{
		return isIndirectVariable ? @"Indirect" : nil;
	}

	NSString *segmentName = [machBinaryInfo segmentNameAtAddress:variableAddress];

	NSMutableString *newDescription = [[NSMutableString alloc] initWithString:partialPath];
	if (segmentName != nil)
	{
		[newDescription appendFormat:@" %@ ", segmentName];
	}
	else
	{
		[newDescription appendString:@" "];
	}
	[newDescription appendString:(isIndirectVariable ? @"(static, indirect)" : @"(static)")];

	return [newDescription copy];
}

+ (NSString *)relativizeVariable:(ZGVariable * __unsafe_unretained)variable withMachBinaries:(NSArray<ZGMachBinary *> *)machBinaries filePathDictionary:(NSDictionary<NSNumber *, NSString *> *)machFilePathDictionary process:(ZGProcess *)process variableController:(ZGVariableController *)variableController failedImages:(NSMutableArray<NSString *> *)failedImages getAddress:(ZGMemoryAddress *)outVariableAddress
{
	ZGMemoryAddress variableAddress;
	BOOL isIndirectVariable;

	// Step 1: Determine the variable address and if it's indirect
	if (![self determineVariableAddressAndIndirectStatus:variable 
												 process:process 
									  variableController:variableController 
												failedImages:failedImages 
											   outIsIndirect:&isIndirectVariable
										 outVariableAddress:&variableAddress])
	{
		if (outVariableAddress != NULL)
		{
			*outVariableAddress = variable.address;
		}
		return nil;
	}

	if (outVariableAddress != NULL)
	{
		*outVariableAddress = variableAddress;
	}

	// Step 2: Find the binary containing this address
	ZGMachBinary *machBinary = [ZGMachBinary machBinaryNearestToAddress:variableAddress fromMachBinaries:machBinaries];
	NSString *machFilePath = [machFilePathDictionary objectForKey:@(machBinary.filePathAddress)];

	if (machFilePath == nil)
	{
		return isIndirectVariable ? @"Indirect" : nil;
	}

	// Step 3: Check if the address is within the binary's segments
	ZGMachBinaryInfo *machBinaryInfo = [machBinary machBinaryInfoInProcess:process];
	NSRange totalSegmentRange = machBinaryInfo.totalSegmentRange;

	if (variableAddress < totalSegmentRange.location || 
		variableAddress >= totalSegmentRange.location + totalSegmentRange.length)
	{
		return isIndirectVariable ? @"Indirect" : nil;
	}

	// Step 4: Create base formula for the variable if needed
	NSString *partialPath = [self createBaseFormulaForVariable:variable 
												  machBinaries:machBinaries
											filePathDictionary:machFilePathDictionary
													machBinary:machBinary
													machFilePath:machFilePath
											   variableAddress:variableAddress
											isIndirectVariable:isIndirectVariable];

	// Step 5: Create the description
	return [self createDescriptionForPartialPath:partialPath ?: [machFilePath lastPathComponent]
									machBinaryInfo:machBinaryInfo
								  variableAddress:variableAddress
							   isIndirectVariable:isIndirectVariable];
}

- (void)annotateVariablesAutomatically:(NSArray<ZGVariable *> *)variables process:(ZGProcess *)process
{
	ZGDocumentWindowController *windowController = _windowController;
	ZGDocumentTableController *tableController = windowController.tableController;

	NSMutableArray<ZGVariable *> *variablesToAnnotate = [NSMutableArray array];

	for (ZGVariable *variable in variables)
	{
		if (!variable.userAnnotated)
		{
			// Clear the description so we can automatically fill it again
			variable.fullAttributedDescription = [[NSAttributedString alloc] initWithString:@"" attributes:@{NSForegroundColorAttributeName : [NSColor textColor]}];

			// Update the variable's address
			[tableController updateDynamicVariableAddress:variable];

			[variablesToAnnotate addObject:variable];
		}
	}

	// Re-annotate the variables
	[[self class] annotateVariables:variablesToAnnotate process:process variableController:self symbols:YES async:YES completionHandler:^{
		[windowController.variablesTableView reloadData];
	}];
}

+ (ZGMachBinaryAnnotationInfo)machBinaryAnnotationInfoForProcess:(ZGProcess *)process
{
	NSArray<ZGMachBinary *> *machBinaries = [ZGMachBinary machBinariesInProcess:process];
	NSMutableDictionary<NSNumber *, NSString *> *machFilePathDictionary = [[NSMutableDictionary alloc] init];

	NSArray<NSString *> *filePaths = [ZGMachBinary filePathsForMachBinaries:machBinaries inProcess:process];
	[machBinaries enumerateObjectsUsingBlock:^(ZGMachBinary * _Nonnull machBinary, NSUInteger index, BOOL * _Nonnull __unused stop) {
		NSString *filePath = [filePaths objectAtIndex:index];
		if (filePath.length > 0)
		{
			[machFilePathDictionary setObject:filePath forKey:@(machBinary.filePathAddress)];
		}
	}];

	ZGMachBinaryAnnotationInfo annotationInfo;
	annotationInfo.machBinaries = machBinaries;
	annotationInfo.machFilePathDictionary = machFilePathDictionary;
	return annotationInfo;
}

+ (void)annotateVariables:(NSArray<ZGVariable *> *)variables process:(ZGProcess *)process variableController:(ZGVariableController *)variableController symbols:(BOOL)requiresSymbols async:(BOOL)async completionHandler:(void (^)(void))completionHandler
{
	ZGMachBinaryAnnotationInfo annotationInfo = {0};

	[self annotateVariables:variables annotationInfo:annotationInfo process:process variableController:variableController symbols:requiresSymbols async:async completionHandler:completionHandler];
}

+ (NSArray<NSNumber *> *)relativizeVariablesWithMachBinaries:(NSArray<ZGMachBinary *> *)machBinaries 
                                        filePathDictionary:(NSDictionary<NSNumber *, NSString *> *)machFilePathDictionary
                                                variables:(NSArray<ZGVariable *> *)variables
                                                  process:(ZGProcess *)process
                                       variableController:(ZGVariableController *)variableController
                                             failedImages:(NSMutableArray<NSString *> *)failedImages
                                        staticDescriptions:(NSArray **)staticDescriptionsRef
{
	NSUInteger capacity = variables.count;
	NSMutableArray *staticDescriptions = [[NSMutableArray alloc] initWithCapacity:capacity];
	NSMutableArray<NSNumber *> *variableAddresses = [[NSMutableArray alloc] initWithCapacity:capacity];
	BOOL processIsValid = process.valid;

	for (ZGVariable *variable in variables)
	{
		if (processIsValid)
		{
			ZGMemoryAddress variableAddress;
			NSString *staticDescription = [self relativizeVariable:variable withMachBinaries:machBinaries filePathDictionary:machFilePathDictionary process:process variableController:variableController failedImages:failedImages getAddress:&variableAddress];

			[variableAddresses addObject:@(variableAddress)];
			[staticDescriptions addObject:staticDescription != nil ? staticDescription : [NSNull null]];
		}
		else
		{
			[variableAddresses addObject:@(variable.address)];
			[staticDescriptions addObject:[NSNull null]];
		}
	}

	*staticDescriptionsRef = staticDescriptions;
	return variableAddresses;
}

+ (NSArray *)retrieveSymbolsForAddresses:(NSArray<NSNumber *> *)variableAddresses process:(ZGProcess *)process
{
	NSUInteger capacity = variableAddresses.count;
	NSMutableArray *symbols = [[NSMutableArray alloc] initWithCapacity:capacity];
	BOOL processIsValid = process.valid;

	for (NSNumber *variableAddress in variableAddresses)
	{
		if (processIsValid)
		{
			NSString *symbol = [process.symbolicator symbolAtAddress:variableAddress.unsignedLongLongValue relativeOffset:NULL];
			[symbols addObject:symbol != nil ? symbol : [NSNull null]];
		}
		else
		{
			[symbols addObject:[NSNull null]];
		}
	}
	return symbols;
}

+ (void)finishAnnotatingVariables:(NSArray<ZGVariable *> *)variables 
                          symbols:(NSArray *)symbols 
                staticDescriptions:(NSArray *)staticDescriptions 
                 variableAddresses:(NSArray<NSNumber *> *)variableAddresses
                          process:(ZGProcess *)process
{
	ZGMemoryMap processTask = process.processTask;
	BOOL processIsValid = process.valid;
	__block ZGMemoryAddress cachedRegionAddress = 0;
	__block ZGMemorySize cachedRegionSize = 0;
	__block ZGMemoryExtendedInfo cachedInfo;

	[variables enumerateObjectsUsingBlock:^(ZGVariable * _Nonnull variable, NSUInteger index, BOOL * _Nonnull __unused stop) {
		id staticDescriptionObject = staticDescriptions[index];
		NSString *staticDescription = (staticDescriptionObject != [NSNull null]) ? staticDescriptionObject : nil;

		NSString *symbol;
		if (symbols != nil)
		{
			id symbolObject = symbols[index];
			symbol = (symbolObject != [NSNull null]) ? symbolObject : nil;
		}
		else
		{
			symbol = nil;
		}

		ZGMemoryAddress variableAddress = [variableAddresses[index] unsignedLongLongValue];

		NSString *userTagDescription = nil;
		NSString *protectionDescription = nil;
		if (processIsValid)
		{
			if (cachedRegionAddress >= variableAddress || cachedRegionAddress + cachedRegionSize <= variableAddress)
			{
				cachedRegionAddress = variableAddress;
				if (!ZGRegionExtendedInfo(processTask, &cachedRegionAddress, &cachedRegionSize, &cachedInfo))
				{
					cachedRegionAddress = 0;
					cachedRegionSize = 0;
				}
			}

			if (cachedRegionAddress <= variableAddress && cachedRegionAddress + cachedRegionSize >= variableAddress)
			{
				userTagDescription = ZGUserTagDescription(cachedInfo.user_tag);
				protectionDescription = ZGProtectionDescription(cachedInfo.protection);
			}
		}

		NSString *label = variable.label;

		NSMutableArray<NSString *> *validDescriptionComponents = [NSMutableArray array];
		if (label.length > 0)
		{
			[validDescriptionComponents addObject:[NSString stringWithFormat:@"Label %@", label]];
		}
		else if (variable.usesDynamicLabelAddress)
		{
			NSString *dependentLabel = [ZGCalculator extractFirstDependentLabelFromExpression:variable.addressFormula];

			if (dependentLabel != nil)
			{
				[validDescriptionComponents addObject:[NSString stringWithFormat:@"→ Label %@", dependentLabel]];
			}
		}

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
	}];
}

+ (void)processAnnotationWithMachBinaries:(NSArray<ZGMachBinary *> *)machBinaries
                       filePathDictionary:(NSDictionary<NSNumber *, NSString *> *)machFilePathDictionary
                                variables:(NSArray<ZGVariable *> *)variables
                                  process:(ZGProcess *)process
                       variableController:(ZGVariableController *)variableController
                           requiresSymbols:(BOOL)requiresSymbols
                         completionHandler:(void (^)(void))completionHandler
{
	NSMutableArray<NSString *> *failedImages = [NSMutableArray array];

	NSArray *staticDescriptions = nil;
	NSArray<NSNumber *> *variableAddresses = [self relativizeVariablesWithMachBinaries:machBinaries 
																   filePathDictionary:machFilePathDictionary
																		   variables:variables
																			 process:process
																	variableController:variableController
																		failedImages:failedImages
																   staticDescriptions:&staticDescriptions];

	NSArray *symbols = requiresSymbols ? [self retrieveSymbolsForAddresses:variableAddresses process:process] : nil;

	[self finishAnnotatingVariables:variables 
							symbols:symbols 
				  staticDescriptions:staticDescriptions 
				   variableAddresses:variableAddresses
							process:process];

	completionHandler();
}

+ (void)annotateVariables:(NSArray<ZGVariable *> *)variables annotationInfo:(ZGMachBinaryAnnotationInfo)annotationInfo process:(ZGProcess *)process variableController:(ZGVariableController *)variableController symbols:(BOOL)requiresSymbols async:(BOOL)async completionHandler:(void (^)(void))completionHandler
{
	// Get annotation info if not provided
	void (^getAnnotationInfo)(void (^)(NSArray<ZGMachBinary *> *, NSDictionary<NSNumber *, NSString *> *)) = ^(void (^callback)(NSArray<ZGMachBinary *> *, NSDictionary<NSNumber *, NSString *> *)) {
		if (annotationInfo.machBinaries != nil && annotationInfo.machFilePathDictionary != nil) {
			callback(annotationInfo.machBinaries, annotationInfo.machFilePathDictionary);
		} else {
			if (async) {
				dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
					ZGMachBinaryAnnotationInfo retrievedAnnotationInfo = [self machBinaryAnnotationInfoForProcess:process];
					dispatch_async(dispatch_get_main_queue(), ^{
						callback(retrievedAnnotationInfo.machBinaries, retrievedAnnotationInfo.machFilePathDictionary);
					});
				});
			} else {
				ZGMachBinaryAnnotationInfo retrievedAnnotationInfo = [self machBinaryAnnotationInfoForProcess:process];
				callback(retrievedAnnotationInfo.machBinaries, retrievedAnnotationInfo.machFilePathDictionary);
			}
		}
	};

	// Process the annotation
	if (async) {
		getAnnotationInfo(^(NSArray<ZGMachBinary *> *machBinaries, NSDictionary<NSNumber *, NSString *> *machFilePathDictionary) {
			NSMutableArray<NSString *> *failedImages = [NSMutableArray array];

			NSArray *staticDescriptions = nil;
			NSArray<NSNumber *> *variableAddresses = [self relativizeVariablesWithMachBinaries:machBinaries 
																		   filePathDictionary:machFilePathDictionary
																				   variables:variables
																					 process:process
																		  variableController:variableController
																				failedImages:failedImages
																		   staticDescriptions:&staticDescriptions];

			dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
				NSArray *symbols = requiresSymbols ? [self retrieveSymbolsForAddresses:variableAddresses process:process] : nil;

				dispatch_async(dispatch_get_main_queue(), ^{
					[self finishAnnotatingVariables:variables 
											symbols:symbols 
								  staticDescriptions:staticDescriptions 
								   variableAddresses:variableAddresses
											process:process];

					completionHandler();
				});
			});
		});
	} else {
		getAnnotationInfo(^(NSArray<ZGMachBinary *> *machBinaries, NSDictionary<NSNumber *, NSString *> *machFilePathDictionary) {
			[self processAnnotationWithMachBinaries:machBinaries
								 filePathDictionary:machFilePathDictionary
										  variables:variables
											process:process
								 variableController:variableController
									requiresSymbols:requiresSymbols
								  completionHandler:completionHandler];
		});
	}
}

#pragma mark Edit Variables Sizes (Byte Arrays)

- (NSArray<ZGVariable *> *)validateSizeChangesForVariables:(NSArray<ZGVariable *> *)variables 
                                             requestedSizes:(NSArray<NSNumber *> *)requestedSizes
                                         outCurrentSizes:(NSMutableArray<NSNumber *> **)outCurrentSizes
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

	if (outCurrentSizes != NULL) {
		*outCurrentSizes = currentVariableSizes;
	}

	return validVariables;
}

- (void)applySizeChangesToVariables:(NSArray<ZGVariable *> *)variables requestedSizes:(NSArray<NSNumber *> *)requestedSizes
{
	[variables enumerateObjectsUsingBlock:^(ZGVariable *variable, NSUInteger index, BOOL * __unused stop)
	 {
		 variable.size = [[requestedSizes objectAtIndex:index] unsignedLongLongValue];
	 }];

	[_windowController.variablesTableView reloadData];
}

- (void)editVariables:(NSArray<ZGVariable *> *)variables requestedSizes:(NSArray<NSNumber *> *)requestedSizes
{
	// Validate size changes
	NSMutableArray<NSNumber *> *currentVariableSizes = nil;
	NSArray<ZGVariable *> *validVariables = [self validateSizeChangesForVariables:variables 
																  requestedSizes:requestedSizes 
																outCurrentSizes:&currentVariableSizes];

	if (validVariables.count > 0)
	{
		// Set up undo
		[self setupUndoWithActionName:ZGLocalizedStringFromVariableActionsTable(@"undoSizeChange")
							   target:self
							 selector:@selector(editVariables:requestedSizes:)
						  withObjects:@[validVariables, currentVariableSizes]];

		// Apply size changes
		[self applySizeChangesToVariables:validVariables requestedSizes:requestedSizes];
	}
	else
	{
		// Show error message
		ZGRunAlertPanelWithOKButton(ZGLocalizedStringFromVariableActionsTable(@"failedChangeSizeAlertTitle"), 
								   ZGLocalizedStringFromVariableActionsTable(@"failedChangeSizeAlertMessage"));
	}
}

@end
