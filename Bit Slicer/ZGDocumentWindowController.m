/*
 * Copyright (c) 2013 Mayur Pawashe
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

#import "ZGDocumentWindowController.h"
#import "ZGDocumentTableController.h"
#import "ZGDocumentSearchController.h"
#import "ZGVariableController.h"
#import "ZGEditValueWindowController.h"
#import "ZGEditAddressWindowController.h"
#import "ZGEditDescriptionWindowController.h"
#import "ZGEditSizeWindowController.h"
#import "ZGScriptManager.h"
#import "ZGProcessList.h"
#import "ZGProcess.h"
#import "ZGVariableTypes.h"
#import "ZGRunningProcess.h"
#import "ZGPreferencesController.h"
#import "ZGDocumentData.h"
#import "ZGSearchData.h"
#import "ZGSearchProgress.h"
#import "ZGSearchResults.h"
#import "ZGDebuggerController.h"
#import "ZGBreakPointController.h"
#import "ZGScriptingInterpreter.h"
#import "ZGDocument.h"
#import "ZGVirtualMemory.h"
#import "ZGMachBinary.h"
#import "ZGMachBinaryInfo.h"
#import "ZGDocumentOptionsViewController.h"
#import "ZGWatchVariableWindowController.h"
#import "ZGRunAlertPanel.h"
#import "ZGLocalization.h"
#import "ZGTableView.h"
#import "NSArrayAdditions.h"
#import "ZGNullability.h"
#import <libproc.h>

#define ZGProtectionGroup @"ZGProtectionGroup"
#define ZGProtectionItemAll @"ZGProtectionAll"
#define ZGProtectionItemWrite @"ZGProtectionWrite"
#define ZGProtectionItemExecute @"ZGProtectionExecute"

#define ZGQualifierGroup @"ZGQualifierGroup"
#define ZGQualifierSigned @"ZGQualifierSigned"
#define ZGQualifierUnsigned @"ZGQualifierUnsigned"

#define ZGStringMatchingGroup @"ZGStringMatchingGroup"
#define ZGStringIgnoreCase @"ZGStringIgnoreCase"
#define ZGStringNullTerminated @"ZGStringNullTerminated"

#define ZGEndianGroup @"ZGEndianGroup"
#define ZGEndianLittle @"ZGEndianLittle"
#define ZGEndianBig @"ZGEndianBig"

@implementation ZGDocumentWindowController
{
	ZGDebuggerController * _Nonnull _debuggerController;
	ZGWatchVariableWindowController * _Nullable _watchVariableWindowController;
	
	BOOL _preferringNewTab;
	
	ZGEditValueWindowController * _Nullable _editValueWindowController;
	ZGEditAddressWindowController * _Nullable _editAddressWindowController;
	ZGEditDescriptionWindowController * _Nullable _editDescriptionWindowController;
	ZGEditSizeWindowController * _Nullable _editSizeWindowController;
	
	BOOL _loadedDocumentBefore;
	NSString * _Nullable _flagsLabelStringValue;
	
	AGScopeBarGroup * _Nullable _protectionGroup;
	AGScopeBarGroup * _Nullable _qualifierGroup;
	AGScopeBarGroup * _Nullable _stringMatchingGroup;
	AGScopeBarGroup * _Nullable _endianGroup;
	
	NSPopover * _Nullable _advancedOptionsPopover;
	
	IBOutlet NSTableColumn *_dataTypeTableColumn;
	IBOutlet NSTextField *_generalStatusTextField;
	IBOutlet NSTextField *_flagsTextField;
	IBOutlet NSTextField *_flagsLabel;
	IBOutlet AGScopeBar *_scopeBar;
	IBOutlet NSView *_scopeBarFlagsView;
	IBOutlet NSToolbar *_toolbar;
}

- (id)initWithProcessTaskManager:(ZGProcessTaskManager *)processTaskManager rootlessConfiguration:(nullable ZGRootlessConfiguration *)rootlessConfiguration debuggerController:(ZGDebuggerController *)debuggerController breakPointController:(ZGBreakPointController *)breakPointController scriptingInterpreter:(ZGScriptingInterpreter *)scriptingInterpreter hotKeyCenter:(ZGHotKeyCenter *)hotKeyCenter loggerWindowController:(ZGLoggerWindowController *)loggerWindowController lastChosenInternalProcessName:(nullable NSString *)lastChosenInternalProcessName preferringNewTab:(BOOL)preferringNewTab delegate:(id <ZGChosenProcessDelegate, ZGMemorySelectionDelegate, ZGShowMemoryWindow>)delegate
{
	self = [super initWithProcessTaskManager:processTaskManager rootlessConfiguration:rootlessConfiguration delegate:delegate];
	if (self != nil)
	{
		self.lastChosenInternalProcessName = lastChosenInternalProcessName;
		_preferringNewTab = preferringNewTab;
		
		_debuggerController = debuggerController;
		_breakPointController = breakPointController;
		_scriptingInterpreter = scriptingInterpreter;
		_loggerWindowController = loggerWindowController;
		_hotKeyCenter = hotKeyCenter;
	}
	return self;
}

- (NSString *)windowNibName
{
	return @"Search Document Window";
}

- (void)dealloc
{
	[_searchController cleanUp];
	[_tableController cleanUp];
	[_scriptManager cleanup];
}

- (void)restoreStateWithCoder:(NSCoder *)coder
{
	[super restoreStateWithCoder:coder];
	
	// On 10.12, when search document windows are restored, the separator is thicker
	// I don't know why this happens, but one workaround is just resetting the baseline separator property
	// to NO and then back to YES
	if (@available(macOS 10.12, *))
	{
		_toolbar.showsBaselineSeparator = NO;
		_toolbar.showsBaselineSeparator = YES;
	}
}

- (void)setupScopeBar
{
	_protectionGroup = [_scopeBar addGroupWithIdentifier:ZGProtectionGroup label:ZGLocalizableSearchDocumentString(@"scopeBarProtectionGroup") items:nil];
	[_protectionGroup
	 addItemWithIdentifier:ZGProtectionItemAll
	 title:ZGLocalizableSearchDocumentString(@"scopeBarProtectionAllItem")];
	[_protectionGroup
	 addItemWithIdentifier:ZGProtectionItemWrite
	 title:ZGLocalizableSearchDocumentString(@"scopeBarProtectionWriteItem")];
	[_protectionGroup
	 addItemWithIdentifier:ZGProtectionItemExecute
	 title:ZGLocalizableSearchDocumentString(@"scopeBarProtectionExecuteItem")];
	_protectionGroup.selectionMode = AGScopeBarGroupSelectOne;
	
	_qualifierGroup = [[AGScopeBarGroup alloc] initWithIdentifier:ZGQualifierGroup];
	_qualifierGroup.label = ZGLocalizableSearchDocumentString(@"scopeBarQualifierGroup");
	[_qualifierGroup addItemWithIdentifier:ZGQualifierSigned title:ZGLocalizableSearchDocumentString(@"scopeBarQualifierSignedItem")];
	[_qualifierGroup addItemWithIdentifier:ZGQualifierUnsigned title:ZGLocalizableSearchDocumentString(@"scopeBarQualifierUnsignedItem")];
	_qualifierGroup.selectionMode = AGScopeBarGroupSelectOne;
	
	_stringMatchingGroup = [[AGScopeBarGroup alloc] initWithIdentifier:ZGStringMatchingGroup];
	_stringMatchingGroup.label = ZGLocalizableSearchDocumentString(@"scopeBarStringMatchingGroup");
	[_stringMatchingGroup addItemWithIdentifier:ZGStringIgnoreCase title:ZGLocalizableSearchDocumentString(@"scopeBarStringMatchingIgnoreCaseItem")];
	[_stringMatchingGroup addItemWithIdentifier:ZGStringNullTerminated title:ZGLocalizableSearchDocumentString(@"scopeBarStringMatchingNullTerminatedItem")];
	_stringMatchingGroup.selectionMode = AGScopeBarGroupSelectAny;
	
	_endianGroup = [[AGScopeBarGroup alloc] initWithIdentifier:ZGEndianGroup];
	_endianGroup.label = ZGLocalizableSearchDocumentString(@"scopeBarEndiannessGroup");
	[_endianGroup addItemWithIdentifier:ZGEndianLittle title:ZGLocalizableSearchDocumentString(@"scopeBarEndianLittleItem")];
	[_endianGroup addItemWithIdentifier:ZGEndianBig title:ZGLocalizableSearchDocumentString(@"scopeBarEndianBigItem")];
	_endianGroup.selectionMode = AGScopeBarGroupSelectOne;
	
	// Set delegate after setting up scope bar so we won't receive initial selection events beforehand
	_scopeBar.delegate = self;
}

- (void)scopeBar:(AGScopeBar *)__unused scopeBar item:(AGScopeBarItem *)item wasSelected:(BOOL)selected
{
	if ([item.group.identifier isEqualToString:ZGProtectionGroup])
	{
		if (selected)
		{
			if ([item.identifier isEqualToString:ZGProtectionItemAll])
			{
				_searchData.protectionMode = ZGProtectionAll;
			}
			else if ([item.identifier isEqualToString:ZGProtectionItemWrite])
			{
				_searchData.protectionMode = ZGProtectionWrite;
			}
			else if ([item.identifier isEqualToString:ZGProtectionItemExecute])
			{
				_searchData.protectionMode = ZGProtectionExecute;
			}
			
			[self markDocumentChange];
		}
	}
	else if ([item.group.identifier isEqualToString:ZGQualifierGroup])
	{
		if (selected)
		{
			[self changeIntegerQualifier:[item.identifier isEqualToString:ZGQualifierSigned] ? ZGSigned : ZGUnsigned];
		}
	}
	else if ([item.group.identifier isEqualToString:ZGStringMatchingGroup])
	{
		if ([item.identifier isEqualToString:ZGStringIgnoreCase])
		{
			_searchData.shouldIgnoreStringCase = selected;
		}
		else if ([item.identifier isEqualToString:ZGStringNullTerminated])
		{
			_searchData.shouldIncludeNullTerminator = selected;
		}
		
		[self markDocumentChange];
	}
	else if ([item.group.identifier isEqualToString:ZGEndianGroup])
	{
		CFByteOrder newByteOrder = [item.identifier isEqualToString:ZGEndianLittle] ? CFByteOrderLittleEndian : CFByteOrderBigEndian;
		
		if (newByteOrder != _documentData.byteOrderTag)
		{
			_documentData.byteOrderTag = newByteOrder;
			
			for (ZGVariable *variable in _documentData.variables)
			{
				variable.byteOrder = newByteOrder;
				if (ZGSupportsEndianness(variable.type))
				{
					[variable updateStringValue];
				}
			}
			
			[_variablesTableView reloadData];
			[self markDocumentChange];
		}
	}
}

- (void)windowDidLoad
{
	[super windowDidLoad];
	
	if (_preferringNewTab)
	{
		// This code should only trigger if we are running on 10.12 or later
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
		self.window.tabbingMode = NSWindowTabbingModePreferred;
#pragma clang diagnostic pop
	}
	
	_documentData = [(ZGDocument *)self.document data];
	_searchData = [(ZGDocument *)self.document searchData];
	
	_tableController = [[ZGDocumentTableController alloc] initWithWindowController:self];
	_variableController = [[ZGVariableController alloc] initWithWindowController:self];
	_searchController = [[ZGDocumentSearchController alloc] initWithWindowController:self];
	_scriptManager = [[ZGScriptManager alloc] initWithWindowController:self];
	
	_searchValueTextField.target = self;
	_searchValueTextField.action = @selector(searchValue:);
	
	NSSearchFieldCell *searchFieldCell = _searchValueTextField.cell;
	searchFieldCell.cancelButtonCell.target = self;
	searchFieldCell.cancelButtonCell.action = @selector(clearSearchValues:);
	
	[self setupScopeBar];
	ZGAdjustLocalizableWidthsForWindowAndTableColumns(ZGUnwrapNullableObject(self.window), @[_dataTypeTableColumn], @{@"ru" : @[@60.0]});
	
	[_storeValuesButton.image setTemplate:YES];
	[[NSImage imageNamed:@"container_filled"] setTemplate:YES];
	
	_storeValuesButton.toolTip = ZGLocalizableSearchDocumentString(@"storeValuesButtonToolTip");
	
	[_generalStatusTextField.cell setBackgroundStyle:NSBackgroundStyleRaised];

	[self setupProcessListNotifications];
	[self loadDocumentUserInterface];

	_loadedDocumentBefore = YES;
}

- (void)cleanupWithAppTerminationState:(ZGAppTerminationState *)appTerminationState
{
	[_scriptManager cleanupWithAppTerminationState:appTerminationState];
	[_watchVariableWindowController cleanup];
	[super cleanup];
}

- (void)currentProcessChangedWithOldProcess:(ZGProcess *)oldProcess newProcess:(ZGProcess *)newProcess
{
	for (ZGVariable *variable in _documentData.variables)
	{
		if (variable.enabled)
		{
			if (variable.type == ZGScript)
			{
				[_scriptManager stopScriptForVariable:variable];
			}
			else if (variable.isFrozen)
			{
				variable.enabled = NO;
			}
		}
	}

	[[self undoManager] removeAllActions];

	[_tableController clearCache];

	for (ZGVariable *variable in _documentData.variables)
	{
		variable.finishedEvaluatingDynamicAddress = NO;
		variable.rawValue = NULL;
	}

	if (oldProcess.is64Bit != newProcess.is64Bit)
	{
		for (ZGVariable *variable in _documentData.variables)
		{
			if (variable.type == ZGPointer)
			{
				[variable changePointerSize:self.currentProcess.pointerSize];
			}
		}
	}

	if (oldProcess.valid && newProcess.valid)
	{
		[self markDocumentChange];
	}

	[_tableController updateWatchVariablesTimer];

	[_variablesTableView reloadData];

	_storeValuesButton.enabled = newProcess.valid;

	if (oldProcess.valid && !newProcess.valid)
	{
		if (_searchController.canCancelTask && !_searchController.searchProgress.shouldCancelSearch)
		{
			[_searchController cancelTask];
		}
		
		[_scriptManager triggerCurrentProcessChanged];
		[_watchVariableWindowController triggerCurrentProcessChanged];
	}
}

- (BOOL)hasDefaultUpdateDisplayTimer
{
	return NO;
}

- (void)startProcessActivity
{
	[_tableController updateWatchVariablesTimer];
	[super startProcessActivity];
}

- (void)stopProcessActivity
{
	BOOL shouldKeepWatchVariablesTimer = [_tableController updateWatchVariablesTimer];
	if (!shouldKeepWatchVariablesTimer && _searchController.canStartTask)
	{
		BOOL foundRunningScript = [_documentData.variables zgHasObjectMatchingCondition:^(ZGVariable *variable) {
			return (BOOL)(variable.enabled && variable.type == ZGScript);
		}];

		if (!foundRunningScript)
		{
			[super stopProcessActivity];
		}
	}
}

- (void)setStatusString:(NSString *)statusString
{
	[_generalStatusTextField setStringValue:statusString];
}

- (void)updateNumberOfValuesDisplayedStatus
{
	NSUInteger variableCount = _documentData.variables.count + _searchController.searchResults.addressCount;
	
	NSNumberFormatter *numberOfVariablesFormatter = [[NSNumberFormatter alloc] init];
	[numberOfVariablesFormatter setNumberStyle:NSNumberFormatterDecimalStyle];
	
	NSString *formattedNumber = [numberOfVariablesFormatter stringFromNumber:@(variableCount)];
	
	NSString *valuesDisplayedString = [[NSString stringWithFormat:ZGLocalizableSearchDocumentString(@"displayingValuesLabelFormat"), variableCount] stringByReplacingOccurrencesOfString:@"_NUM_" withString:formattedNumber];
	
	[self setStatusString:valuesDisplayedString];
}

- (void)setDesiredProcessInternalName:(NSString *)desiredProcessInternalName
{
	BOOL needsToMarkDocumentChange = _loadedDocumentBefore && (self.desiredProcessInternalName == nil || ![self.desiredProcessInternalName isEqualToString:desiredProcessInternalName]);
	
	[super setDesiredProcessInternalName:desiredProcessInternalName];

	if (needsToMarkDocumentChange)
	{
		[self markDocumentChange];
	}

	_documentData.desiredProcessInternalName = desiredProcessInternalName;
}

- (void)loadDocumentUserInterface
{
	self.desiredProcessInternalName = (_documentData.desiredProcessInternalName != nil) ? _documentData.desiredProcessInternalName : self.lastChosenInternalProcessName;

	[self updateRunningProcesses];
	[self setAndPostLastChosenInternalProcessName];

	[self updateNumberOfValuesDisplayedStatus];
	
	[_variableController disableHarmfulVariables:_documentData.variables];
	[self updateVariables:_documentData.variables searchResults:nil];
	
	switch (_searchData.protectionMode)
	{
		case ZGProtectionAll:
			[_protectionGroup setSelected:YES forItemWithIdentifier:ZGProtectionItemAll];
			break;
		case ZGProtectionWrite:
			[_protectionGroup setSelected:YES forItemWithIdentifier:ZGProtectionItemWrite];
			break;
		case ZGProtectionExecute:
			[_protectionGroup setSelected:YES forItemWithIdentifier:ZGProtectionItemExecute];
			break;
	}
	
	if (_documentData.qualifierTag == ZGSigned)
	{
		[_qualifierGroup setSelected:YES forItemWithIdentifier:ZGQualifierSigned];
	}
	else
	{
		[_qualifierGroup setSelected:YES forItemWithIdentifier:ZGQualifierUnsigned];
	}
	
	if (_searchData.shouldIgnoreStringCase)
	{
		[_stringMatchingGroup setSelected:YES forItemWithIdentifier:ZGStringIgnoreCase];
	}
	
	if (_searchData.shouldIncludeNullTerminator)
	{
		[_stringMatchingGroup setSelected:YES forItemWithIdentifier:ZGStringNullTerminated];
	}
	
	[_endianGroup setSelected:YES forItemWithIdentifier:_documentData.byteOrderTag == CFByteOrderBigEndian ? ZGEndianBig : ZGEndianLittle];
	
	if (_advancedOptionsPopover != nil)
	{
		ZGDocumentOptionsViewController *optionsViewController = (id)_advancedOptionsPopover.contentViewController;
		[optionsViewController reloadInterface];
	}
	
	_searchValueTextField.stringValue = _documentData.searchValue;
	
	[self.window makeFirstResponder:_searchValueTextField];
	
	[_dataTypesPopUpButton selectItemWithTag:_documentData.selectedDatatypeTag];
	[self selectDataTypeWithTag:(ZGVariableType)_documentData.selectedDatatypeTag recordUndo:NO];
	
	[_functionPopUpButton selectItemWithTag:_documentData.functionTypeTag];
	[self updateOptions];
	
	[_scriptManager loadCachedScriptsFromVariables:_documentData.variables];
}

#pragma mark Selected Variables

- (NSIndexSet *)selectedVariableIndexes
{
	NSIndexSet *tableIndexSet = _variablesTableView.selectedRowIndexes;
	NSInteger clickedRow = _variablesTableView.clickedRow;
	
	return (clickedRow >= 0 && ![tableIndexSet containsIndex:(NSUInteger)clickedRow]) ? [NSIndexSet indexSetWithIndex:(NSUInteger)clickedRow] : tableIndexSet;
}

- (NSArray<ZGVariable *> *)selectedVariables
{
	return [_documentData.variables objectsAtIndexes:[self selectedVariableIndexes]];
}

- (HFRange)preferredMemoryRequestRange
{
	NSArray<ZGVariable *> *selectedVariables = [[self selectedVariables] zgFilterUsingBlock:^(ZGVariable *variable) { return (BOOL)(variable.type != ZGScript); }];
	ZGVariable *firstVariable = [selectedVariables firstObject];
	ZGVariable *lastVariable = [selectedVariables lastObject];
	
	if (firstVariable == nil)
	{
		return [super preferredMemoryRequestRange];
	}
	
	return HFRangeMake(firstVariable.address, lastVariable.address + lastVariable.size - firstVariable.address);
}

#pragma mark Undo Manager

- (NSUndoManager *)windowWillReturnUndoManager:(id)__unused sender
{
	return [(ZGDocument *)self.document undoManager];
}

- (id)undoManager
{
	return ZGUnwrapNullableObject([(ZGDocument *)self.document undoManager]);
}

- (void)markDocumentChange
{
	[(ZGDocument *)self.document markChange];
}

- (IBAction)undoDocument:(id)__unused sender
{
	[[self undoManager] undo];
}

- (IBAction)redoDocument:(id)__unused sender
{
	[[self undoManager] redo];
}

#pragma mark Watching other applications

- (BOOL)isClearable
{
	return (_documentData.variables.count > 0 && [_searchController canStartTask]);
}

- (void)changeIntegerQualifier:(ZGVariableQualifier)newQualifier
{
	ZGVariableQualifier oldQualifier = (ZGVariableQualifier)_documentData.qualifierTag;
	if (oldQualifier != newQualifier)
	{
		for (ZGVariable *variable in _documentData.variables)
		{
			variable.qualifier = newQualifier;
			switch (variable.type)
			{
				case ZGInt8:
				case ZGInt16:
				case ZGInt32:
				case ZGInt64:
					[variable updateStringValue];
					break;
				case ZGString8:
				case ZGString16:
				case ZGByteArray:
				case ZGScript:
				case ZGPointer:
				case ZGFloat:
				case ZGDouble:
					break;
			}
		}
		
		[_variablesTableView reloadData];
		[self markDocumentChange];
		
		_documentData.qualifierTag = newQualifier;
	}
}

- (void)setFlagsLabelStringValue:(NSString *)flagsLabelStringValue
{
	_flagsLabelStringValue = [flagsLabelStringValue copy];
	[_flagsLabel setStringValue:flagsLabelStringValue];
}

- (void)setFlagsStringValue:(NSString *)flagsStringValue
{
	_flagsStringValue = [flagsStringValue copy];
	[_flagsTextField setStringValue:_flagsStringValue];
}

- (IBAction)changeFlags:(id)sender
{
	[self setFlagsStringValue:[(NSControl *)sender stringValue]];
}

- (void)updateFlagsRangeTextField
{
	ZGFunctionType functionType = (ZGFunctionType)_functionPopUpButton.selectedItem.tag;
	if (functionType == ZGGreaterThan || functionType == ZGGreaterThanStored || functionType == ZGGreaterThanStoredLinear)
	{
		[self setFlagsLabelStringValue:[ZGLocalizableSearchDocumentString(@"searchBelowLabel") stringByAppendingString:@":"]];
		
		if (_documentData.lastBelowRangeValue != nil)
		{
			[self setFlagsStringValue:_documentData.lastBelowRangeValue];
		}
		else
		{
			[self setFlagsStringValue:@""];
		}
	}
	else if (functionType == ZGLessThan || functionType == ZGLessThanStored || functionType == ZGLessThanStoredLinear)
	{
		[self setFlagsLabelStringValue:[ZGLocalizableSearchDocumentString(@"searchAboveLabel") stringByAppendingString:@":"]];
		
		if (_documentData.lastAboveRangeValue != nil)
		{
			[self setFlagsStringValue:_documentData.lastAboveRangeValue];
		}
		else
		{
			[self setFlagsStringValue:@""];
		}
	}
}

- (void)changeScopeBarGroup:(AGScopeBarGroup *)group shouldExist:(BOOL)shouldExist
{
	BOOL alreadyExists = [_scopeBar.groups containsObject:group];
	if (alreadyExists)
	{
		[_scopeBar removeGroupAtIndex:[_scopeBar.groups indexOfObject:group]];
	}
	
	if (shouldExist)
	{
		[_scopeBar insertGroup:group atIndex:_scopeBar.groups.count];
	}
}

- (void)updateOptions
{
	ZGVariableType dataType = [self selectedDataType];
	ZGFunctionType functionType = [self selectedFunctionType];
	
	BOOL needsFlags = NO;
	BOOL needsQualifier = NO;
	BOOL needsStringMatching = NO;
	
	if (dataType == ZGFloat || dataType == ZGDouble)
	{
		if (ZGIsFunctionTypeEquals(functionType) || ZGIsFunctionTypeNotEquals(functionType))
		{
			// epsilon
			[self setFlagsLabelStringValue:[ZGLocalizableSearchDocumentString(@"searchRoundErrorLabel") stringByAppendingString:@":"]];
			if (_documentData.lastEpsilonValue != nil)
			{
				[self setFlagsStringValue:_documentData.lastEpsilonValue];
			}
			else
			{
				[self setFlagsStringValue:@""];
			}
		}
		else
		{
			// range
			[self updateFlagsRangeTextField];
		}
		
		needsFlags = YES;
	}
	else if (dataType == ZGString8 || dataType == ZGString16)
	{
		needsStringMatching = YES;
	}
	else if (dataType != ZGByteArray)
	{
		if (!ZGIsFunctionTypeEquals(functionType) && !ZGIsFunctionTypeNotEquals(functionType))
		{
			// range
			[self updateFlagsRangeTextField];
			
			needsFlags = YES;
		}
		
		if (dataType != ZGPointer)
		{
			needsQualifier = YES;
		}
	}
	
	[_functionPopUpButton removeAllItems];
	
	[_functionPopUpButton insertItemWithTitle:ZGLocalizableSearchDocumentString(@"equalsOperatorTitle") atIndex:0];
	[[_functionPopUpButton itemAtIndex:0] setTag:ZGEquals];
	
	[_functionPopUpButton insertItemWithTitle:ZGLocalizableSearchDocumentString(@"notEqualsOperatorTitle") atIndex:1];
	[[_functionPopUpButton itemAtIndex:1] setTag:ZGNotEquals];
	
	if (dataType != ZGString8 && dataType != ZGString16 && dataType != ZGByteArray)
	{
		[_functionPopUpButton insertItemWithTitle:ZGLocalizableSearchDocumentString(@"greaterThanOperatorTitle") atIndex:2];
		[[_functionPopUpButton itemAtIndex:2] setTag:ZGGreaterThan];
		
		[_functionPopUpButton insertItemWithTitle:ZGLocalizableSearchDocumentString(@"lessThanOperatorTitle") atIndex:3];
		[[_functionPopUpButton itemAtIndex:3] setTag:ZGLessThan];
	}
	
	if (![_functionPopUpButton selectItemWithTag:_documentData.functionTypeTag])
	{
		_documentData.functionTypeTag = _functionPopUpButton.selectedTag;
	}
	
	BOOL needsEndianness = ZGSupportsEndianness(dataType);
	
	[self changeScopeBarGroup:_qualifierGroup shouldExist:needsQualifier];
	[self changeScopeBarGroup:_stringMatchingGroup shouldExist:needsStringMatching];
	[self changeScopeBarGroup:_endianGroup shouldExist:needsEndianness];
	
	_showsFlags = needsFlags;
	_scopeBar.accessoryView = _showsFlags ? _scopeBarFlagsView : nil;
}

- (void)selectDataTypeWithTag:(ZGVariableType)newTag recordUndo:(BOOL)recordUndo
{
	ZGVariableType oldVariableTypeTag = (ZGVariableType)_documentData.selectedDatatypeTag;
	
	_documentData.selectedDatatypeTag = newTag;
	[_dataTypesPopUpButton selectItemWithTag:newTag];
	
	_functionPopUpButton.enabled = YES;
	
	[self updateOptions];
	
	if (recordUndo && oldVariableTypeTag != newTag)
	{
		[[self undoManager] setActionName:ZGLocalizableSearchDocumentString(@"undoDataTypeChangeAction")];
		[(ZGDocumentWindowController *)[[self undoManager] prepareWithInvocationTarget:self]
		 selectDataTypeWithTag:oldVariableTypeTag
		 recordUndo:YES];
	}
}

- (IBAction)dataTypePopUpButtonRequest:(id)sender
{
	[self selectDataTypeWithTag:(ZGVariableType)[[(NSPopUpButton *)sender selectedItem] tag] recordUndo:YES];
}

- (ZGVariableType)selectedDataType
{
	return (ZGVariableType)_documentData.selectedDatatypeTag;
}

- (ZGFunctionType)selectedFunctionType
{
	_documentData.searchValue = _searchValueTextField.stringValue;
	
	BOOL isLinearlyExpressedStoredValue = NO;
	BOOL isStoringValues = [[_searchController class] hasStoredValueTokenFromExpression:_documentData.searchValue isLinearlyExpressed:&isLinearlyExpressedStoredValue];

	ZGFunctionType functionType = (ZGFunctionType)_documentData.functionTypeTag;
	if (isStoringValues)
	{
		switch (functionType)
		{
			case ZGEquals:
				functionType = isLinearlyExpressedStoredValue ? ZGEqualsStoredLinear : ZGEqualsStored;
				break;
			case ZGNotEquals:
				functionType = isLinearlyExpressedStoredValue ? ZGNotEqualsStoredLinear : ZGNotEqualsStored;
				break;
			case ZGGreaterThan:
				functionType = isLinearlyExpressedStoredValue ? ZGGreaterThanStoredLinear : ZGGreaterThanStored;
				break;
			case ZGLessThan:
				functionType = isLinearlyExpressedStoredValue ? ZGLessThanStoredLinear : ZGLessThanStored;
				break;
			case ZGEqualsStored:
			case ZGNotEqualsStored:
			case ZGGreaterThanStored:
			case ZGLessThanStored:
			case ZGEqualsStoredLinear:
			case ZGNotEqualsStoredLinear:
			case ZGGreaterThanStoredLinear:
			case ZGLessThanStoredLinear:
				break;
		}
	}
	
	return functionType;
}

- (IBAction)functionTypePopUpButtonRequest:(id)__unused sender
{
	_documentData.functionTypeTag = [_functionPopUpButton selectedTag];
	[self updateOptions];
	[self markDocumentChange];
}

- (void)selectNewFunctionTypeAtIndex:(NSInteger)newIndex
{
	NSMenuItem *newItem = [_functionPopUpButton itemAtIndex:newIndex];
	[_functionPopUpButton selectItem:newItem];
	[self functionTypePopUpButtonRequest:nil];
}

- (IBAction)goBack:(id)__unused sender
{
	NSInteger selectedIndex = [_functionPopUpButton indexOfSelectedItem];
	NSInteger newIndex = selectedIndex > 0 ? selectedIndex - 1 : [_functionPopUpButton numberOfItems] - 1;
	[self selectNewFunctionTypeAtIndex:newIndex];
}

- (IBAction)goForward:(id)__unused sender
{
	NSInteger selectedIndex = [_functionPopUpButton indexOfSelectedItem];
	NSInteger newIndex = selectedIndex < [_functionPopUpButton numberOfItems] - 1 ? selectedIndex + 1 : 0;
	[self selectNewFunctionTypeAtIndex:newIndex];
}

#pragma mark Useful Methods

- (void)updateVariables:(NSArray<ZGVariable *> *)newWatchVariablesArray searchResults:(ZGSearchResults *)searchResults
{
	if ([self undoManager].isUndoing || [self undoManager].isRedoing)
	{
		[(ZGDocumentWindowController *)[[self undoManager] prepareWithInvocationTarget:self] updateVariables:_documentData.variables searchResults:_searchController.searchResults];
	}
	
	_documentData.variables = newWatchVariablesArray;
	_searchController.searchResults = searchResults;
	
	[_tableController updateWatchVariablesTimer];
	[_variablesTableView reloadData];
	
	[self updateNumberOfValuesDisplayedStatus];
}

- (BOOL)isProcessIdentifierHalted:(pid_t)processIdentifier
{
	return [super isProcessIdentifier:processIdentifier inHaltedBreakPoints:_debuggerController.haltedBreakPoints];
}

#pragma mark Menu item validation

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)userInterfaceItem
{
	NSMenuItem *menuItem = (NSMenuItem *)userInterfaceItem;
	
	if (menuItem.action == @selector(clear:))
	{
		if ([_variableController canClearSearch])
		{
			menuItem.title = ZGLocalizableSearchDocumentString(@"clearSearchVariablesTitle");
		}
		else
		{
			menuItem.title = ZGLocalizableSearchDocumentString(@"clearVariablesTitle");
		}
		
		if (![self isClearable])
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(storeAllValues:))
	{
		if (!self.currentProcess.valid || ![_searchController canStartTask])
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(searchPointerToSelectedVariable:))
	{
		if (!self.currentProcess.valid || ![_searchController canStartTask] || self.selectedVariables.count != 1)
		{
			return NO;
		}
		
		ZGVariable *variable = [self selectedVariables][0];
		if (variable.type == ZGScript)
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(removeSelectedSearchValues:) || menuItem.action == @selector(cut:))
	{
		if ([self selectedVariables].count == 0 || [_searchController canCancelTask])
		{
			return NO;
		}
	}
	
	else if (userInterfaceItem.action == @selector(dumpAllMemory:) || userInterfaceItem.action == @selector(dumpMemoryInRange:) || userInterfaceItem.action == @selector(changeMemoryProtection:))
	{
		if (![_searchController canStartTask])
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(freezeVariables:))
	{
		NSArray<ZGVariable *> *selectedVariables = [self selectedVariables];
		if (selectedVariables.count > 0)
		{
			// All the variables selected need to either be all unfrozen or all frozen
			BOOL isFrozen = [[selectedVariables firstObject] isFrozen];
			
			if (isFrozen)
			{
				if (selectedVariables.count != 1)
				{
					menuItem.title = ZGLocalizableSearchDocumentString(@"unfreezeMultipleVariablesTitle");
				}
				else
				{
					menuItem.title = ZGLocalizableSearchDocumentString(@"unfreezeSingleVariableTitle");
				}
			}
			else
			{
				if (selectedVariables.count != 1)
				{
					menuItem.title = ZGLocalizableSearchDocumentString(@"freezeMulitipleVariablesTitle");
				}
				else
				{
					menuItem.title = ZGLocalizableSearchDocumentString(@"freezeSingleVariableTitle");
				}
			}

			if (![self isClearable])
			{
				return NO;
			}
			
			if ([selectedVariables zgHasObjectMatchingCondition:^(ZGVariable *variable) {
				return (BOOL)(variable.type == ZGScript || variable.isFrozen != isFrozen || variable.rawValue == NULL);
			}])
			{
				return NO;
			}
		}
		else
		{
			menuItem.title = ZGLocalizableSearchDocumentString(@"freezeMulitipleVariablesTitle");
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(addVariable:))
	{
		if (![_searchController canStartTask])
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(copy:) || menuItem.action == @selector(cut:))
	{
		if (![[self selectedVariables] zgHasObjectMatchingCondition:^(ZGVariable *variable) { return (BOOL)(variable.type != ZGScript); }])
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(copyAddress:))
	{
		if ([self selectedVariables].count != 1)
		{
			return NO;
		}
		
		if ([(ZGVariable *)[self selectedVariables][0] type] == ZGScript)
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(paste:))
	{
		if ([_searchController canCancelTask] || ![NSPasteboard.generalPasteboard dataForType:ZGVariablePboardType])
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(requestEditingVariablesValue:))
	{
		menuItem.title = ([self selectedVariables].count != 1) ? ZGLocalizableSearchDocumentString(@"editMultipleVariableValuesTitle") : ZGLocalizableSearchDocumentString(@"editSingleVariableValueTitle");
		
		if ([_searchController canCancelTask] || [self selectedVariables].count == 0 || !self.currentProcess.valid)
		{
			return NO;
		}
		
		for (ZGVariable *variable in [self selectedVariables])
		{
			if (variable.type == ZGScript)
			{
				return NO;
			}
		}
	}
	
	else if (menuItem.action == @selector(requestEditingVariableAddress:))
	{
		if ([_searchController canCancelTask] || [self selectedVariables].count != 1 || !self.currentProcess.valid)
		{
			return NO;
		}
		
		if ([(ZGVariable *)[self selectedVariables][0] type] == ZGScript)
		{
			return NO;
		}
	}
    
    else if (menuItem.action == @selector(requestEditingVariablesSize:))
    {
		NSArray<ZGVariable *> *selectedVariables = [self selectedVariables];
		menuItem.title = (selectedVariables.count != 1) ? ZGLocalizableSearchDocumentString(@"editMultipleVariableSizesTitle") : ZGLocalizableSearchDocumentString(@"editSingleVariableSizeTitle");
		
		if ([_searchController canCancelTask] || selectedVariables.count == 0 || !self.currentProcess.valid)
		{
			return NO;
		}
		
		// All selected variables must be Byte Array's
		for (ZGVariable *variable in selectedVariables)
		{
			if (variable.type != ZGByteArray)
			{
				return NO;
			}
		}
	}
	
	else if (menuItem.action == @selector(relativizeVariablesAddress:))
	{
		NSArray<ZGVariable *> *selectedVariables = [self selectedVariables];
		
		menuItem.title = (selectedVariables.count != 1) ? ZGLocalizableSearchDocumentString(@"relativizeMultipleVariablesTitle") : ZGLocalizableSearchDocumentString(@"relativizeSingleVariableTitle");
		
		if ([_searchController canCancelTask] || selectedVariables.count == 0 || !self.currentProcess.valid)
		{
			return NO;
		}
		
		NSArray<ZGMachBinary *> *machBinaries = [ZGMachBinary machBinariesInProcess:self.currentProcess];
		ZGMachBinary *mainMachBinary = [ZGMachBinary mainMachBinaryFromMachBinaries:machBinaries];
		for (ZGVariable *variable in selectedVariables)
		{
			if (variable.type == ZGScript)
			{
				return NO;
			}
			
			if (variable.usesDynamicAddress)
			{
				return NO;
			}
			
			ZGMachBinary *machBinary = [ZGMachBinary machBinaryNearestToAddress:variable.address fromMachBinaries:machBinaries];
			if (machBinary == nil)
			{
				return NO;
			}
			
			ZGMachBinaryInfo *machBinaryInfo = [machBinary machBinaryInfoInProcess:self.currentProcess];
			if (machBinaryInfo.slide == 0 && machBinary.headerAddress == mainMachBinary.headerAddress)
			{
				return NO;
			}
		}
	}
	
	else if (menuItem.action == @selector(watchVariable:))
	{
		if ([_searchController canCancelTask] || !self.currentProcess.valid || [self selectedVariables].count != 1)
		{
			return NO;
		}
		
		ZGVariable *selectedVariable = [[self selectedVariables] objectAtIndex:0];
		
		if (selectedVariable.type == ZGScript)
		{
			return NO;
		}
		
		ZGMemoryAddress memoryAddress = selectedVariable.address;
		ZGMemorySize memorySize = selectedVariable.size;
		ZGMemoryProtection memoryProtection;
		
		if (!ZGMemoryProtectionInRegion(self.currentProcess.processTask, &memoryAddress, &memorySize, &memoryProtection))
		{
			return NO;
		}
		
		if (memoryAddress + memorySize < selectedVariable.address || memoryAddress > selectedVariable.address + selectedVariable.size)
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(nopVariables:))
	{
		menuItem.title = ([self selectedVariables].count != 1) ? ZGLocalizableSearchDocumentString(@"nopMultipleVariablesTitle") : ZGLocalizableSearchDocumentString(@"nopSingleVariableTitle");
		
		if ([_searchController canCancelTask] || [self selectedVariables].count == 0 || !self.currentProcess.valid)
		{
			return NO;
		}
		
		if (![[self selectedVariables] zgAllObjectsMatchingCondition:^(ZGVariable *variable) { return (BOOL)(variable.type == ZGByteArray && variable.rawValue != NULL); }])
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(showMemoryViewer:) || menuItem.action == @selector(showDebugger:))
	{
		if ([self selectedVariables].count != 1 || !self.currentProcess.valid)
		{
			return NO;
		}
		
		ZGVariable *selectedVariable = [[self selectedVariables] objectAtIndex:0];
		
		if (selectedVariable.type == ZGScript)
		{
			return NO;
		}
		
		ZGMemoryAddress memoryAddress = selectedVariable.address;
		ZGMemorySize memorySize = selectedVariable.size;
		ZGMemoryProtection memoryProtection;
		
		if (!ZGMemoryProtectionInRegion(self.currentProcess.processTask, &memoryAddress, &memorySize, &memoryProtection))
		{
			return NO;
		}
		
		if (memoryAddress > selectedVariable.address || memoryAddress + memorySize <= selectedVariable.address)
		{
			return NO;
		}
		
		if (!(memoryProtection & VM_PROT_READ))
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(goBack:) || menuItem.action == @selector(goForward:))
	{
		if (menuItem.action == @selector(goBack:))
		{
			menuItem.title = ZGLocalizableSearchDocumentString(@"previousOperatorMenuItem");
		}
		else
		{
			menuItem.title = ZGLocalizableSearchDocumentString(@"nextOperatorMenuItem");
		}
		
		if ([_searchController canCancelTask])
		{
			return NO;
		}
	}
	
	return [super validateUserInterfaceItem:userInterfaceItem];
}

#pragma mark Stored Value Tokens

- (void)deselectSearchField
{
	NSText *fieldEditor = [_searchValueTextField currentEditor];
	if (fieldEditor != nil)
	{
		fieldEditor.selectedRange = NSMakeRange(fieldEditor.string.length, 0);
		[fieldEditor setNeedsDisplay:YES];
	}
}

- (void)insertStoredValueToken
{
	_searchValueTextField.stringValue = ZGLocalizableSearchDocumentString(@"storedValueTokenName");
	[self deselectSearchField];
}

#pragma mark Search Handling

- (IBAction)clear:(id)__unused sender
{
	[_variableController clear];
}

- (IBAction)clearSearchValues:(id)__unused sender
{
	if (_searchController.canCancelTask)
	{
		[_searchController cancelTask];
	}
	else
	{
		if ([self isClearable])
		{
			[_variableController clearSearch];
		}
		
		_searchValueTextField.stringValue = @"";
		_documentData.searchValue = _searchValueTextField.stringValue;
	}
}

- (IBAction)searchValue:(id)__unused sender
{
	_documentData.searchValue = _searchValueTextField.stringValue;
	
	BOOL hasEmptyExpression = (_documentData.searchValue.length == 0);
	if (!hasEmptyExpression && _searchController.canStartTask && self.currentProcess.valid)
	{
		if (self.currentProcess.hasGrantedAccess)
		{
			ZGFunctionType functionType = [self selectedFunctionType];
			if (ZGIsFunctionTypeStore(functionType) && _searchData.savedData == nil)
			{
				ZGRunAlertPanelWithOKButton(ZGLocalizableSearchDocumentString(@"noStoredValuesAlertTitle"), ZGLocalizableSearchDocumentString(@"noStoredValuesAlertMessage"));
			}
			else
			{
				if (_documentData.variables.count == 0)
				{
					[[self undoManager] removeAllActions];
				}
				
				[_searchController searchVariablesWithString:_documentData.searchValue withDataType:[self selectedDataType] functionType:functionType allowsNarrowing:YES];
			}
		}
		else
		{
			// We failed to grant access to this process the user is trying to search in
			// Notify the user why this may be the case
			if ([self isCurrentProcessProtectedByEntitlement])
			{
				ZGRunAlertPanelWithOKButtonAndHelp(ZGLocalizableSearchDocumentString(@"searchFailureAlertTitle"), [NSString stringWithFormat:ZGLocalizableSearchDocumentString(@"searchFailureSystemProtectionAlertMessageFormat"), self.currentProcess.name], self);
			}
			else
			{
				// While we don't show apps that are running as root user, some processes can still require the debugger running as root to access them
				ZGRunAlertPanelWithOKButton(ZGLocalizableSearchDocumentString(@"searchFailureAlertTitle"), [NSString stringWithFormat:ZGLocalizableSearchDocumentString(@"searchFailureElevatedPrivilegesAlertMessageFormat"), self.currentProcess.name]);
			}
		}
	}
}

- (BOOL)isCurrentProcessProtectedByEntitlement
{
	char pathBuffer[PROC_PIDPATHINFO_MAXSIZE] = {0};
	int numberOfBytesRead = proc_pidpath(self.currentProcess.processID, pathBuffer, sizeof(pathBuffer));
	if (numberOfBytesRead > 0)
	{
		NSString *path = [[NSString alloc] initWithBytes:pathBuffer length:(NSUInteger)numberOfBytesRead encoding:NSUTF8StringEncoding];
		if (path != nil)
		{
			NSString *codesignPath = @"/usr/bin/codesign";
			if ([[NSFileManager defaultManager] fileExistsAtPath:codesignPath])
			{
				NSTask *codesignTask = [[NSTask alloc] init];
				codesignTask.launchPath = codesignPath;
				codesignTask.arguments = @[@"-dv", path];
				
				NSPipe *outputPipe = [NSPipe pipe];
				codesignTask.standardError = outputPipe;
				
				@try
				{
					[codesignTask launch];
					[codesignTask waitUntilExit];
					
					NSFileHandle *fileHandle = [outputPipe fileHandleForReading];
					NSData *dataRead = [fileHandle readDataToEndOfFile];
					if (dataRead != nil)
					{
						__block BOOL foundProtection = NO;
						NSString *contents = [[NSString alloc] initWithData:dataRead encoding:NSUTF8StringEncoding];
						[contents enumerateLinesUsingBlock:^(NSString * _Nonnull line, BOOL * _Nonnull stop) {
							NSString *trimmedLine = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
							// Google Chrome opted into restrict bit a couple years before 10.14 came about
							// Apps opting in notarization will have the runtime bit set
							if ([trimmedLine hasPrefix:@"CodeDirectory"])
							{
								if (([trimmedLine containsString:@"restrict"] || [trimmedLine containsString:@"runtime"]))
								{
									foundProtection = YES;
								}
								*stop = YES;
							}
						}];
						return foundProtection;
					}
				}
				@catch (NSException *exception)
				{
					NSLog(@"Failed to execute codesign verification command: %@", exception);
				}
			}
		}
	}
	return NO;
}

// Show help for being unable to search likely due to security protections
#define SECURITY_PROTECTIONS_HELP_URL @"https://github.com/zorgiepoo/Bit-Slicer/wiki/Security-Protections"
- (BOOL)alertShowHelp:(NSAlert *)__unused alert
{
	[[NSWorkspace sharedWorkspace] openURL:ZGUnwrapNullableObject([NSURL URLWithString:SECURITY_PROTECTIONS_HELP_URL])];
	// Don't know if YES or NO should be returned -- doesn't seem to matter either way
	return NO;
}

- (IBAction)searchPointerToSelectedVariable:(id)__unused sender
{
	ZGVariable *variable = [[self selectedVariables] objectAtIndex:0];
	[_searchController searchVariablesWithString:variable.addressStringValue withDataType:ZGPointer functionType:ZGEquals allowsNarrowing:NO];
}

- (IBAction)storeAllValues:(id)__unused sender
{
	_documentData.searchValue = _searchValueTextField.stringValue;
	[_searchController storeAllValues];
}

- (IBAction)showAdvancedOptions:(id)sender
{
	if (_advancedOptionsPopover == nil)
	{
		_advancedOptionsPopover = [[NSPopover alloc] init];
		_advancedOptionsPopover.contentViewController = [[ZGDocumentOptionsViewController alloc] initWithDocument:ZGUnwrapNullableObject(self.document)];
		_advancedOptionsPopover.behavior = NSPopoverBehaviorTransient;
	}
	
	[_advancedOptionsPopover showRelativeToRect:[(NSControl *)sender bounds] ofView:sender preferredEdge:NSMaxYEdge];
}

#pragma mark Variables Handling

- (IBAction)freezeVariables:(id)__unused sender
{
	[_variableController freezeVariables];
}

- (IBAction)copy:(id)__unused sender
{
	[_variableController copyVariables];
}

- (IBAction)copyAddress:(id)__unused sender
{
	[_variableController copyAddress];
}

- (IBAction)paste:(id)__unused sender
{
	[_variableController pasteVariables];
}

- (IBAction)cut:(id)__unused sender
{
	[_variableController copyVariables];
	[self removeSelectedSearchValues:nil];
}

- (IBAction)removeSelectedSearchValues:(id)__unused sender
{
	[_variableController removeSelectedSearchValues];
}

- (IBAction)addVariable:(id)sender
{
	[_variableController addVariable:sender];
}

- (IBAction)nopVariables:(id)__unused sender
{
	[_variableController nopVariables:[self selectedVariables]];
}

- (IBAction)requestEditingVariablesValue:(id)__unused sender
{
	if (_editValueWindowController == nil)
	{
		_editValueWindowController = [[ZGEditValueWindowController alloc] initWithVariableController:_variableController];
	}
	
	[_editValueWindowController requestEditingValuesFromVariables:[self selectedVariables] withProcessTask:self.currentProcess.processTask attachedToWindow:ZGUnwrapNullableObject(self.window) scriptManager:_scriptManager];
}

- (IBAction)requestEditingVariableDescription:(id)__unused sender
{
	if (_editDescriptionWindowController == nil)
	{
		_editDescriptionWindowController = [[ZGEditDescriptionWindowController alloc] initWithVariableController:_variableController];
	}
	
	[_editDescriptionWindowController requestEditingDescriptionFromVariable:[self selectedVariables][0] attachedToWindow:ZGUnwrapNullableObject(self.window)];
}

- (IBAction)requestEditingVariableAddress:(id)__unused sender
{
	if (_editAddressWindowController == nil)
	{
		_editAddressWindowController = [[ZGEditAddressWindowController alloc] initWithVariableController:_variableController];
	}
	
	[_editAddressWindowController requestEditingAddressFromVariable:[self selectedVariables][0] attachedToWindow:ZGUnwrapNullableObject(self.window)];
}

- (IBAction)requestEditingVariablesSize:(id)__unused sender
{
	if (_editSizeWindowController == nil)
	{
		_editSizeWindowController = [[ZGEditSizeWindowController alloc] initWithVariableController:_variableController];
	}
	
	[_editSizeWindowController requestEditingSizesFromVariables:[self selectedVariables] attachedToWindow:ZGUnwrapNullableObject(self.window)];
}

- (IBAction)relativizeVariablesAddress:(id)__unused sender
{
	[_variableController relativizeVariables:[self selectedVariables]];
}

#pragma mark Variable Watching Handling

- (IBAction)watchVariable:(id)sender
{
	if (_watchVariableWindowController == nil)
	{
		_watchVariableWindowController = [[ZGWatchVariableWindowController alloc] initWithBreakPointController:_breakPointController delegate:self.delegate];
	}
	
	[_watchVariableWindowController watchVariable:[self selectedVariables][0] withWatchPointType:(ZGWatchPointType)[(NSControl *)sender tag] inProcess:self.currentProcess attachedToWindow:ZGUnwrapNullableObject(self.window) completionHandler:^(NSArray<ZGVariable *> *foundVariables) {
		if (foundVariables.count > 0)
		{
			NSIndexSet *rowIndexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, foundVariables.count)];
			[self->_variableController addVariables:foundVariables atRowIndexes:rowIndexes];
			[ZGVariableController annotateVariables:foundVariables process:self.currentProcess];
			[self->_variablesTableView scrollRowToVisible:0];
		}
	}];
}

#pragma mark Showing Other Controllers

- (IBAction)showMemoryViewer:(id)__unused sender
{
	ZGVariable *selectedVariable = [[self selectedVariables] objectAtIndex:0];
	id <ZGShowMemoryWindow> delegate = self.delegate;
	[delegate showMemoryViewerWindowWithProcess:self.currentProcess address:selectedVariable.address selectionLength:selectedVariable.size > 0 ? selectedVariable.size : DEFAULT_MEMORY_VIEWER_SELECTION_LENGTH];
}

- (IBAction)showDebugger:(id)__unused sender
{
	ZGVariable *selectedVariable = [[self selectedVariables] firstObject];
	id <ZGShowMemoryWindow> delegate = self.delegate;
	[delegate showDebuggerWindowWithProcess:self.currentProcess address:selectedVariable.address];
}

@end
