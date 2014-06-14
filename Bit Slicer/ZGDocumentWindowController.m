/*
 * Created by Mayur Pawashe on 8/9/13.
 *
 * Copyright (c) 2013 zgcoder
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
#import "ZGMemoryViewerController.h"
#import "ZGDocument.h"
#import "ZGVirtualMemory.h"
#import "ZGMachBinary.h"
#import "ZGMachBinaryInfo.h"
#import "APTokenSearchField.h"
#import "ZGSearchToken.h"
#import "ZGDocumentOptionsViewController.h"
#import "ZGWatchVariableWindowController.h"
#import "ZGUtilities.h"
#import "ZGTableView.h"
#import "ZGNavigationPost.h"
#import "NSArrayAdditions.h"

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

@interface ZGDocumentWindowController ()

@property (nonatomic) NSString *flagsStringValue;
@property (nonatomic) NSString *flagsLabelStringValue;

@property (nonatomic) ZGDebuggerController *debuggerController;
@property (nonatomic) ZGBreakPointController *breakPointController;
@property (nonatomic) ZGMemoryViewerController *memoryViewer;
@property (nonatomic) ZGLoggerWindowController *loggerWindowController;
@property (nonatomic) ZGHotKeyCenter *hotKeyCenter;

@property (nonatomic) ZGWatchVariableWindowController *watchVariableWindowController;

@property (nonatomic) ZGEditValueWindowController *editValueWindowController;
@property (nonatomic) ZGEditAddressWindowController *editAddressWindowController;
@property (nonatomic) ZGEditDescriptionWindowController *editDescriptionWindowController;
@property (nonatomic) ZGEditSizeWindowController *editSizeWindowController;

@property (nonatomic, assign) IBOutlet AGScopeBar *scopeBar;
@property (nonatomic, assign) IBOutlet NSView *scopeBarFlagsView;

@property (nonatomic) AGScopeBarGroup *protectionGroup;
@property (nonatomic) AGScopeBarGroup *qualifierGroup;
@property (nonatomic) AGScopeBarGroup *stringMatchingGroup;
@property (nonatomic) AGScopeBarGroup *endianGroup;

@property (nonatomic, assign) IBOutlet NSTextField *generalStatusTextField;
@property (nonatomic, assign) IBOutlet NSTextField *flagsTextField;
@property (nonatomic, assign) IBOutlet NSTextField *flagsLabel;

@property (nonatomic) NSPopover *advancedOptionsPopover;

@property (nonatomic) BOOL loadedDocumentBefore;

@end

@implementation ZGDocumentWindowController

- (id)initWithDocument:(ZGDocument *)document
{
	self = [super initWithProcessTaskManager:document.processTaskManager];
	if (self != nil)
	{
		self.lastChosenInternalProcessName = document.lastChosenInternalProcessName;
		
		self.debuggerController = document.debuggerController;
		self.breakPointController = document.breakPointController;
		self.loggerWindowController = document.loggerWindowController;
		self.hotKeyCenter = document.hotKeyCenter;
	}
	return self;
}

- (NSString *)windowNibName
{
	return @"MyDocument";
}

- (void)dealloc
{
	[self.searchController cleanUp];
	[self.tableController cleanUp];
	[self.scriptManager cleanup];
}

- (void)setupScopeBar
{
	self.protectionGroup = [self.scopeBar addGroupWithIdentifier:ZGProtectionGroup label:@"Protection:" items:nil];
	[self.protectionGroup addItemWithIdentifier:ZGProtectionItemAll title:@"All"];
	[self.protectionGroup addItemWithIdentifier:ZGProtectionItemWrite title:@"Write"];
	[self.protectionGroup addItemWithIdentifier:ZGProtectionItemExecute title:@"Execute"];
	self.protectionGroup.selectionMode = AGScopeBarGroupSelectOne;
	
	self.qualifierGroup = [[AGScopeBarGroup alloc] initWithIdentifier:ZGQualifierGroup];
	self.qualifierGroup.label = @"Qualifier:";
	[self.qualifierGroup addItemWithIdentifier:ZGQualifierSigned title:@"Signed"];
	[self.qualifierGroup addItemWithIdentifier:ZGQualifierUnsigned title:@"Unsigned"];
	self.qualifierGroup.selectionMode = AGScopeBarGroupSelectOne;
	
	self.stringMatchingGroup = [[AGScopeBarGroup alloc] initWithIdentifier:ZGStringMatchingGroup];
	self.stringMatchingGroup.label = @"Matching:";
	[self.stringMatchingGroup addItemWithIdentifier:ZGStringIgnoreCase title:@"Ignore Case"];
	[self.stringMatchingGroup addItemWithIdentifier:ZGStringNullTerminated title:@"Null Terminated"];
	self.stringMatchingGroup.selectionMode = AGScopeBarGroupSelectAny;
	
	self.endianGroup = [[AGScopeBarGroup alloc] initWithIdentifier:ZGEndianGroup];
	self.endianGroup.label = @"Endianness";
	[self.endianGroup addItemWithIdentifier:ZGEndianLittle title:@"Little"];
	[self.endianGroup addItemWithIdentifier:ZGEndianBig title:@"Big"];
	self.endianGroup.selectionMode = AGScopeBarGroupSelectOne;
	
	// Set delegate after setting up scope bar so we won't receive initial selection events beforehand
	self.scopeBar.delegate = self;
}

- (void)scopeBar:(AGScopeBar *)__unused scopeBar item:(AGScopeBarItem *)item wasSelected:(BOOL)selected
{
	if ([item.group.identifier isEqualToString:ZGProtectionGroup])
	{
		if (selected)
		{
			if ([item.identifier isEqualToString:ZGProtectionItemAll])
			{
				self.searchData.protectionMode = ZGProtectionAll;
			}
			else if ([item.identifier isEqualToString:ZGProtectionItemWrite])
			{
				self.searchData.protectionMode = ZGProtectionWrite;
			}
			else if ([item.identifier isEqualToString:ZGProtectionItemExecute])
			{
				self.searchData.protectionMode = ZGProtectionExecute;
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
			self.searchData.shouldIgnoreStringCase = selected;
		}
		else if ([item.identifier isEqualToString:ZGStringNullTerminated])
		{
			self.searchData.shouldIncludeNullTerminator = selected;
		}
		
		[self markDocumentChange];
	}
	else if ([item.group.identifier isEqualToString:ZGEndianGroup])
	{
		CFByteOrder newByteOrder = [item.identifier isEqualToString:ZGEndianLittle] ? CFByteOrderLittleEndian : CFByteOrderBigEndian;
		
		if (newByteOrder != self.documentData.byteOrderTag)
		{
			self.documentData.byteOrderTag = newByteOrder;
			
			for (ZGVariable *variable in self.documentData.variables)
			{
				variable.byteOrder = newByteOrder;
				if (ZGSupportsEndianness(variable.type))
				{
					[variable updateStringValue];
				}
			}
			
			[self.variablesTableView reloadData];
			[self markDocumentChange];
		}
	}
}

- (void)windowDidLoad
{
	[super windowDidLoad];
	
	self.documentData = [(ZGDocument *)self.document data];
	self.searchData = [self.document searchData];
	
	self.tableController = [[ZGDocumentTableController alloc] initWithWindowController:self];
	self.variableController = [[ZGVariableController alloc] initWithWindowController:self];
	self.searchController = [[ZGDocumentSearchController alloc] initWithWindowController:self];
	self.scriptManager = [[ZGScriptManager alloc] initWithWindowController:self];
	
	self.tableController.variablesTableView = self.variablesTableView;
	
	self.searchValueTextField.cell.sendsSearchStringImmediately = NO;
	self.searchValueTextField.cell.sendsSearchStringOnlyAfterReturn = YES;
	
	[self setupScopeBar];
	
	[self.storeValuesButton.image setTemplate:YES];
	[[NSImage imageNamed:@"container_filled"] setTemplate:YES];
	
	[self.generalStatusTextField.cell setBackgroundStyle:NSBackgroundStyleRaised];

	[self setupProcessListNotifications];
	[self loadDocumentUserInterface];

	self.loadedDocumentBefore = YES;
}

- (void)currentProcessChangedWithOldProcess:(ZGProcess *)oldProcess newProcess:(ZGProcess *)newProcess
{
	for (ZGVariable *variable in self.documentData.variables)
	{
		if (variable.enabled)
		{
			if (variable.type == ZGScript)
			{
				[self.scriptManager stopScriptForVariable:variable];
			}
			else if (variable.isFrozen)
			{
				variable.enabled = NO;
			}
		}
	}

	[self.undoManager removeAllActions];

	[self.tableController clearCache];

	for (ZGVariable *variable in self.documentData.variables)
	{
		variable.finishedEvaluatingDynamicAddress = NO;
		variable.rawValue = NULL;
	}

	if (oldProcess.is64Bit != newProcess.is64Bit)
	{
		for (ZGVariable *variable in self.documentData.variables)
		{
			if (variable.type == ZGPointer)
			{
				variable.pointerSize = self.currentProcess.pointerSize;
			}
		}
	}

	if (oldProcess.valid && newProcess.valid)
	{
		[self markDocumentChange];
	}

	[self.tableController updateWatchVariablesTimer];

	[self.tableController.variablesTableView reloadData];

	self.storeValuesButton.enabled = newProcess.valid;

	if (oldProcess.valid && !newProcess.valid)
	{
		if (self.searchController.canCancelTask && !self.searchController.searchProgress.shouldCancelSearch)
		{
			[self.searchController cancelTask];
		}

		[[NSNotificationCenter defaultCenter]
		 postNotificationName:ZGTargetProcessDiedNotification
		 object:oldProcess];
	}
}

- (BOOL)hasDefaultUpdateDisplayTimer
{
	return NO;
}

- (void)startProcessActivity
{
	[self.tableController updateWatchVariablesTimer];
	[super startProcessActivity];
}

- (void)stopProcessActivity
{
	BOOL shouldKeepWatchVariablesTimer = [self.tableController updateWatchVariablesTimer];
	if (!shouldKeepWatchVariablesTimer && self.searchController.canStartTask)
	{
		BOOL foundRunningScript = [self.documentData.variables zgHasObjectMatchingCondition:^(ZGVariable *variable) {
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
	[self.generalStatusTextField setStringValue:statusString];
}

- (void)updateNumberOfValuesDisplayedStatus
{
	NSUInteger variableCount = self.documentData.variables.count + self.searchController.searchResults.addressCount;
	
	NSNumberFormatter *numberOfVariablesFormatter = [[NSNumberFormatter alloc] init];
	numberOfVariablesFormatter.format = @"#,###";
	
	NSString *valuesDisplayedString = [NSString stringWithFormat:@"Displaying %@ value", [numberOfVariablesFormatter stringFromNumber:@(variableCount)]];
	
	if (variableCount != 1)
	{
		valuesDisplayedString = [valuesDisplayedString stringByAppendingString:@"s"];
	}
	
	[self setStatusString:valuesDisplayedString];
}

- (void)setDesiredProcessInternalName:(NSString *)desiredProcessInternalName
{
	BOOL needsToMarkDocumentChange = self.loadedDocumentBefore && (self.desiredProcessInternalName == nil || ![self.desiredProcessInternalName isEqualToString:desiredProcessInternalName]);
	
	[super setDesiredProcessInternalName:desiredProcessInternalName];

	if (needsToMarkDocumentChange)
	{
		[self markDocumentChange];
	}

	self.documentData.desiredProcessInternalName = desiredProcessInternalName;
}

- (void)loadDocumentUserInterface
{
	self.desiredProcessInternalName = (self.documentData.desiredProcessInternalName != nil) ? self.documentData.desiredProcessInternalName : self.lastChosenInternalProcessName;

	[self updateRunningProcesses];
	[self setAndPostLastChosenInternalProcessName];

	[self updateNumberOfValuesDisplayedStatus];
	
	[self.variableController disableHarmfulVariables:self.documentData.variables];
	[self updateVariables:self.documentData.variables searchResults:nil];
	
	switch (self.searchData.protectionMode)
	{
		case ZGProtectionAll:
			[self.protectionGroup setSelected:YES forItemWithIdentifier:ZGProtectionItemAll];
			break;
		case ZGProtectionWrite:
			[self.protectionGroup setSelected:YES forItemWithIdentifier:ZGProtectionItemWrite];
			break;
		case ZGProtectionExecute:
			[self.protectionGroup setSelected:YES forItemWithIdentifier:ZGProtectionItemExecute];
			break;
	}
	
	if (self.documentData.qualifierTag == ZGSigned)
	{
		[self.qualifierGroup setSelected:YES forItemWithIdentifier:ZGQualifierSigned];
	}
	else
	{
		[self.qualifierGroup setSelected:YES forItemWithIdentifier:ZGQualifierUnsigned];
	}
	
	if (self.searchData.shouldIgnoreStringCase)
	{
		[self.stringMatchingGroup setSelected:YES forItemWithIdentifier:ZGStringIgnoreCase];
	}
	
	if (self.searchData.shouldIncludeNullTerminator)
	{
		[self.stringMatchingGroup setSelected:YES forItemWithIdentifier:ZGStringNullTerminated];
	}
	
	[self.endianGroup setSelected:YES forItemWithIdentifier:self.documentData.byteOrderTag == CFByteOrderBigEndian ? ZGEndianBig : ZGEndianLittle];
	
	if (self.advancedOptionsPopover != nil)
	{
		ZGDocumentOptionsViewController *optionsViewController = (id)self.advancedOptionsPopover.contentViewController;
		[optionsViewController reloadInterface];
	}
	
	self.searchValueTextField.objectValue = self.documentData.searchValue;
	[self.window makeFirstResponder:self.searchValueTextField];
	
	[self.dataTypesPopUpButton selectItemWithTag:self.documentData.selectedDatatypeTag];
	[self selectDataTypeWithTag:(ZGVariableType)self.documentData.selectedDatatypeTag recordUndo:NO];
	
	[self.functionPopUpButton selectItemWithTag:self.documentData.functionTypeTag];
	[self updateOptions];
	
	[self.scriptManager loadCachedScriptsFromVariables:self.documentData.variables];
}

#pragma mark Selected Variables

- (NSIndexSet *)selectedVariableIndexes
{
	NSIndexSet *tableIndexSet = self.tableController.variablesTableView.selectedRowIndexes;
	NSInteger clickedRow = self.tableController.variablesTableView.clickedRow;
	
	return (clickedRow >= 0 && ![tableIndexSet containsIndex:(NSUInteger)clickedRow]) ? [NSIndexSet indexSetWithIndex:(NSUInteger)clickedRow] : tableIndexSet;
}

- (NSArray *)selectedVariables
{
	return [self.documentData.variables objectsAtIndexes:[self selectedVariableIndexes]];
}

- (HFRange)preferredMemoryRequestRange
{
	NSArray *selectedVariables = [[self selectedVariables] zgFilterUsingBlock:^(ZGVariable *variable) { return (BOOL)(variable.type != ZGScript); }];
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
	return [(ZGDocument *)self.document undoManager];
}

- (void)markDocumentChange
{
	[self.document markChange];
}

- (IBAction)undoDocument:(id)__unused sender
{
	[self.undoManager undo];
}

- (IBAction)redoDocument:(id)__unused sender
{
	[self.undoManager redo];
}

#pragma mark Watching other applications

- (BOOL)isClearable
{
	return (self.documentData.variables.count > 0 && [self.searchController canStartTask]);
}

- (void)changeIntegerQualifier:(ZGVariableQualifier)newQualifier
{
	ZGVariableQualifier oldQualifier = (ZGVariableQualifier)self.documentData.qualifierTag;
	if (oldQualifier != newQualifier)
	{
		for (ZGVariable *variable in self.documentData.variables)
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
		
		[self.tableController.variablesTableView reloadData];
		[self markDocumentChange];
		
		self.documentData.qualifierTag = newQualifier;
	}
}

- (void)setFlagsLabelStringValue:(NSString *)flagsLabelStringValue
{
	_flagsLabelStringValue = [flagsLabelStringValue copy];
	[self.flagsLabel setStringValue:_flagsLabelStringValue];
}

- (void)setFlagsStringValue:(NSString *)flagsStringValue
{
	_flagsStringValue = [flagsStringValue copy];
	[self.flagsTextField setStringValue:_flagsStringValue];
}

- (IBAction)changeFlags:(id)sender
{
	[self setFlagsStringValue:[sender stringValue]];
}

- (void)updateFlagsRangeTextField
{
	ZGFunctionType functionType = (ZGFunctionType)self.functionPopUpButton.selectedItem.tag;
	if (functionType == ZGGreaterThan || functionType == ZGGreaterThanStored || functionType == ZGGreaterThanStoredLinear)
	{
		self.flagsLabelStringValue = @"Below:";
		
		if (self.documentData.lastBelowRangeValue != nil)
		{
			self.flagsStringValue = self.documentData.lastBelowRangeValue;
		}
		else
		{
			self.flagsStringValue = @"";
		}
	}
	else if (functionType == ZGLessThan || functionType == ZGLessThanStored || functionType == ZGLessThanStoredLinear)
	{
		self.flagsLabelStringValue = @"Above:";
		
		if (self.documentData.lastAboveRangeValue != nil)
		{
			self.flagsStringValue = self.documentData.lastAboveRangeValue;
		}
		else
		{
			self.flagsStringValue = @"";
		}
	}
}

- (void)changeScopeBarGroup:(AGScopeBarGroup *)group shouldExist:(BOOL)shouldExist
{
	BOOL alreadyExists = [self.scopeBar.groups containsObject:group];
	if (alreadyExists)
	{
		[self.scopeBar removeGroupAtIndex:[self.scopeBar.groups indexOfObject:group]];
	}
	
	if (shouldExist)
	{
		[self.scopeBar insertGroup:group atIndex:self.scopeBar.groups.count];
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
			self.flagsLabelStringValue = @"Round Error:";
			if (self.documentData.lastEpsilonValue != nil)
			{
				self.flagsStringValue = self.documentData.lastEpsilonValue;
			}
			else
			{
				self.flagsStringValue = @"";
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
	
	[self.functionPopUpButton removeAllItems];
	
	[self.functionPopUpButton insertItemWithTitle:@"equals" atIndex:0];
	[[self.functionPopUpButton itemAtIndex:0] setTag:ZGEquals];
	
	[self.functionPopUpButton insertItemWithTitle:@"is not" atIndex:1];
	[[self.functionPopUpButton itemAtIndex:1] setTag:ZGNotEquals];
	
	if (dataType != ZGString8 && dataType != ZGString16 && dataType != ZGByteArray)
	{
		[self.functionPopUpButton insertItemWithTitle:@"is greater than" atIndex:2];
		[[self.functionPopUpButton itemAtIndex:2] setTag:ZGGreaterThan];
		
		[self.functionPopUpButton insertItemWithTitle:@"is less than" atIndex:3];
		[[self.functionPopUpButton itemAtIndex:3] setTag:ZGLessThan];
	}
	
	if (![self.functionPopUpButton selectItemWithTag:self.documentData.functionTypeTag])
	{
		self.documentData.functionTypeTag = self.functionPopUpButton.selectedTag;
	}
	
	BOOL needsEndianness = ZGSupportsEndianness(dataType);
	
	[self changeScopeBarGroup:self.qualifierGroup shouldExist:needsQualifier];
	[self changeScopeBarGroup:self.stringMatchingGroup shouldExist:needsStringMatching];
	[self changeScopeBarGroup:self.endianGroup shouldExist:needsEndianness];
	
	_showsFlags = needsFlags;
	self.scopeBar.accessoryView = _showsFlags ? self.scopeBarFlagsView : nil;
}

- (void)selectDataTypeWithTag:(ZGVariableType)newTag recordUndo:(BOOL)recordUndo
{
	ZGVariableType oldVariableTypeTag = (ZGVariableType)self.documentData.selectedDatatypeTag;
	
	self.documentData.selectedDatatypeTag = newTag;
	[self.dataTypesPopUpButton selectItemWithTag:newTag];
	
	self.functionPopUpButton.enabled = YES;
	
	[self updateOptions];
	
	if (recordUndo && oldVariableTypeTag != newTag)
	{
		[self.undoManager setActionName:@"Data Type Change"];
		[[self.undoManager prepareWithInvocationTarget:self]
		 selectDataTypeWithTag:oldVariableTypeTag
		 recordUndo:YES];
	}
}

- (IBAction)dataTypePopUpButtonRequest:(id)sender
{
	[self selectDataTypeWithTag:(ZGVariableType)[[sender selectedItem] tag] recordUndo:YES];
}

- (ZGVariableType)selectedDataType
{
	return (ZGVariableType)self.documentData.selectedDatatypeTag;
}

- (ZGFunctionType)selectedFunctionType
{
	self.documentData.searchValue = self.searchValueTextField.objectValue;
	
	BOOL isStoringValues = [self.documentData.searchValue zgHasObjectMatchingCondition:^(id searchValueObject) { return [searchValueObject isKindOfClass:[ZGSearchToken class]]; }];

	ZGFunctionType functionType = (ZGFunctionType)self.documentData.functionTypeTag;
	if (isStoringValues)
	{
		BOOL isLinearlyExpressedStoredValue = self.documentData.searchValue.count > 1;
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
	self.documentData.functionTypeTag = [self.functionPopUpButton selectedTag];
	[self updateOptions];
	[self markDocumentChange];
}

- (void)selectNewFunctionTypeAtIndex:(NSInteger)newIndex
{
	NSMenuItem *newItem = [self.functionPopUpButton itemAtIndex:newIndex];
	[self.functionPopUpButton selectItem:newItem];
	[self functionTypePopUpButtonRequest:nil];
}

- (IBAction)goBack:(id)__unused sender
{
	NSInteger selectedIndex = [self.functionPopUpButton indexOfSelectedItem];
	NSInteger newIndex = selectedIndex > 0 ? selectedIndex - 1 : [self.functionPopUpButton numberOfItems] - 1;
	[self selectNewFunctionTypeAtIndex:newIndex];
}

- (IBAction)goForward:(id)__unused sender
{
	NSInteger selectedIndex = [self.functionPopUpButton indexOfSelectedItem];
	NSInteger newIndex = selectedIndex < [self.functionPopUpButton numberOfItems] - 1 ? selectedIndex + 1 : 0;
	[self selectNewFunctionTypeAtIndex:newIndex];
}

#pragma mark Useful Methods

- (void)updateVariables:(NSArray *)newWatchVariablesArray searchResults:(ZGSearchResults *)searchResults
{
	if (self.undoManager.isUndoing || self.undoManager.isRedoing)
	{
		[[self.undoManager prepareWithInvocationTarget:self] updateVariables:self.documentData.variables searchResults:self.searchController.searchResults];
	}
	
	self.documentData.variables = newWatchVariablesArray;
	self.searchController.searchResults = searchResults;
	
	[self.tableController updateWatchVariablesTimer];
	[self.tableController.variablesTableView reloadData];
	
	[self updateNumberOfValuesDisplayedStatus];
}

#pragma mark Menu item validation

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)userInterfaceItem
{
	NSMenuItem *menuItem = (NSMenuItem *)userInterfaceItem;
	
	if (menuItem.action == @selector(clear:))
	{
		if ([self.variableController canClearSearch])
		{
			menuItem.title = @"Clear Search Variables";
		}
		else
		{
			menuItem.title = @"Clear Variables";
		}
		
		if (!self.isClearable)
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(storeAllValues:))
	{
		if (!self.currentProcess.valid || ![self.searchController canStartTask])
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(searchPointerToSelectedVariable:))
	{
		if (!self.currentProcess.valid || ![self.searchController canStartTask] || self.selectedVariables.count != 1)
		{
			return NO;
		}
		
		ZGVariable *variable = [self.selectedVariables objectAtIndex:0];
		if (variable.type == ZGScript)
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(insertStoredValueToken:))
	{
		if (self.searchData.savedData == nil)
		{
			return NO;
		}
		
		// I'd like to use self.documentData.searchValue but we don't update it instantly
		for (id object in self.searchValueTextField.objectValue)
		{
			if ([object isKindOfClass:[ZGSearchToken class]])
			{
				return NO;
			}
		}
	}
	
	else if (menuItem.action == @selector(removeSelectedSearchValues:))
	{
		if (self.selectedVariables.count == 0 || self.window.firstResponder != self.tableController.variablesTableView)
		{
			return NO;
		}
	}
	
	else if (userInterfaceItem.action == @selector(dumpAllMemory:) || userInterfaceItem.action == @selector(dumpMemoryInRange:) || userInterfaceItem.action == @selector(changeMemoryProtection:))
	{
		if (![self.searchController canStartTask])
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(freezeVariables:))
	{
		NSArray *selectedVariables = self.selectedVariables;
		if (selectedVariables.count > 0)
		{
			// All the variables selected need to either be all unfrozen or all frozen
			BOOL isFrozen = [[selectedVariables firstObject] isFrozen];
			
			menuItem.title = [NSString stringWithFormat:@"%@ Variable%@", isFrozen ? @"Unfreeze" : @"Freeze", selectedVariables.count != 1 ? @"s" : @""];

			if (!self.isClearable)
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
			menuItem.title = @"Freeze Variables";
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(addVariable:))
	{
		if (![self.searchController canStartTask])
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(copy:))
	{
		if (![self.selectedVariables zgHasObjectMatchingCondition:^(ZGVariable *variable) { return (BOOL)(variable.type != ZGScript); }])
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(copyAddress:))
	{
		if (self.selectedVariables.count != 1)
		{
			return NO;
		}
		
		if ([(ZGVariable *)[self.selectedVariables objectAtIndex:0] type] == ZGScript)
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(paste:))
	{
		if ([self.searchController canCancelTask] || ![NSPasteboard.generalPasteboard dataForType:ZGVariablePboardType])
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(requestEditingVariablesValue:))
	{
		menuItem.title = [NSString stringWithFormat:@"Edit Variable Value%@…", self.selectedVariables.count != 1 ? @"s" : @""];
		
		if ([self.searchController canCancelTask] || self.selectedVariables.count == 0 || !self.currentProcess.valid)
		{
			return NO;
		}
		
		for (ZGVariable *variable in self.selectedVariables)
		{
			if (variable.type == ZGScript)
			{
				return NO;
			}
		}
	}
	
	else if (menuItem.action == @selector(requestEditingVariableAddress:))
	{
		if ([self.searchController canCancelTask] || self.selectedVariables.count != 1 || !self.currentProcess.valid)
		{
			return NO;
		}
		
		if ([(ZGVariable *)[self.selectedVariables objectAtIndex:0] type] == ZGScript)
		{
			return NO;
		}
	}
    
    else if (menuItem.action == @selector(requestEditingVariablesSize:))
    {
		NSArray *selectedVariables = [self selectedVariables];
		menuItem.title = [NSString stringWithFormat:@"Edit Variable Size%@…", selectedVariables.count != 1 ? @"s" : @""];
		
		if ([self.searchController canCancelTask] || selectedVariables.count == 0 || !self.currentProcess.valid)
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
		NSArray *selectedVariables = [self selectedVariables];
		if ([self.searchController canCancelTask] || selectedVariables.count == 0 || !self.currentProcess.valid)
		{
			return NO;
		}
		
		menuItem.title = [NSString stringWithFormat:@"Relativize Variable%@", selectedVariables.count != 1 ? @"s" : @""];
		
		NSArray *machBinaries = [ZGMachBinary machBinariesInProcess:self.currentProcess];
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
		if ([self.searchController canCancelTask] || !self.currentProcess.valid || self.selectedVariables.count != 1)
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
		menuItem.title = [NSString stringWithFormat:@"NOP Variable%@", self.selectedVariables.count != 1 ? @"s" : @""];
		
		if ([self.searchController canCancelTask] || self.selectedVariables.count == 0 || !self.currentProcess.valid)
		{
			return NO;
		}
		
		if (![self.selectedVariables zgAllObjectsMatchingCondition:^(ZGVariable *variable) { return (BOOL)(variable.type == ZGByteArray && variable.rawValue != NULL); }])
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(showMemoryViewer:) || menuItem.action == @selector(showDebugger:))
	{
		if (self.selectedVariables.count != 1 || !self.currentProcess.valid)
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
			menuItem.title = @"Previous Operator";
		}
		else
		{
			menuItem.title = @"Next Operator";
		}
		
		if ([self.searchController canCancelTask])
		{
			return NO;
		}
	}
	
	return [super validateUserInterfaceItem:userInterfaceItem];
}

#pragma mark Search Field Tokens

- (void)deselectSearchField
{
	NSText *fieldEditor = [self.searchValueTextField currentEditor];
	if (fieldEditor != nil)
	{
		fieldEditor.selectedRange = NSMakeRange(fieldEditor.string.length, 0);
		[fieldEditor setNeedsDisplay:YES];
	}
}

- (IBAction)insertStoredValueToken:(id)__unused sender
{
	self.searchValueTextField.objectValue = @[[[ZGSearchToken alloc] initWithName:@"Stored Value"]];
	[self deselectSearchField];
}

- (id)tokenField:(NSTokenField *)__unused tokenField representedObjectForEditingString:(NSString *)editingString
{
	return editingString;
}

- (NSString *)tokenField:(NSTokenField *)__unused tokenField displayStringForRepresentedObject:(id)representedObject
{
	NSString *result = nil;
	if ([representedObject isKindOfClass:[NSString class]])
	{
		result = representedObject;
	}
	else if ([representedObject isKindOfClass:[ZGSearchToken class]])
	{
		result = [representedObject name];
	}
	
	return result;
}

- (NSTokenStyle)tokenField:(NSTokenField *)__unused tokenField styleForRepresentedObject:(id)representedObject
{
	return ([representedObject isKindOfClass:[ZGSearchToken class]]) ? NSRoundedTokenStyle : NSPlainTextTokenStyle;
}

- (NSString *)tokenField:(NSTokenField *)__unused tokenField editingStringForRepresentedObject:(id)representedObject
{
	return ([representedObject isKindOfClass:[ZGSearchToken class]]) ? nil : representedObject;
}

#pragma mark Search Handling

- (IBAction)clear:(id)__unused sender
{
	[self.variableController clear];
}

- (IBAction)clearSearchValues:(id)__unused sender
{
	[self.variableController clearSearch];
}

- (IBAction)searchValue:(id)__unused sender
{
	self.documentData.searchValue = self.searchValueTextField.objectValue;
	
	if (self.documentData.searchValue.count == 0 && self.searchController.canCancelTask)
	{
		[self.searchController cancelTask];
	}
	else if (self.documentData.searchValue.count == 0 && [self isClearable])
	{
		[self clearSearchValues:nil];
	}
	else if (self.documentData.searchValue.count > 0 && self.searchController.canStartTask && self.currentProcess.valid)
	{
		if (ZGIsFunctionTypeStore([self selectedFunctionType]) && self.searchData.savedData == nil)
		{
			NSRunAlertPanel(@"No Stored Values Available", @"There are no stored values to compare against. Please store values first before proceeding.", nil, nil, nil);
		}
		else
		{
			if (self.documentData.variables.count == 0)
			{
				[self.undoManager removeAllActions];
			}
			
			[self.searchController searchComponents:self.documentData.searchValue withDataType:self.selectedDataType functionType:self.selectedFunctionType allowsNarrowing:YES];
		}
	}
}

- (IBAction)searchPointerToSelectedVariable:(id)__unused sender
{
	ZGVariable *variable = [self.selectedVariables objectAtIndex:0];
	
	[self.searchController searchComponents:@[variable.addressStringValue] withDataType:ZGPointer functionType:ZGEquals allowsNarrowing:NO];
}

- (void)createSearchMenu
{
	NSMenu *searchMenu = [[NSMenu alloc] init];
	NSMenuItem *storedValuesMenuItem = [[NSMenuItem alloc] initWithTitle:@"Stored Value" action:@selector(insertStoredValueToken:) keyEquivalent:@""];
	[searchMenu addItem:storedValuesMenuItem];
	self.searchValueTextField.cell.searchMenu = searchMenu;
}

- (IBAction)storeAllValues:(id)__unused sender
{
	self.documentData.searchValue = self.searchValueTextField.objectValue;
	[self.searchController storeAllValues];
}

- (IBAction)showAdvancedOptions:(id)sender
{
	if (self.advancedOptionsPopover == nil)
	{
		self.advancedOptionsPopover = [[NSPopover alloc] init];
		self.advancedOptionsPopover.contentViewController = [[ZGDocumentOptionsViewController alloc] initWithDocument:self.document];
		self.advancedOptionsPopover.behavior = NSPopoverBehaviorTransient;
	}
	
	[self.advancedOptionsPopover showRelativeToRect:[sender bounds] ofView:sender preferredEdge:NSMaxYEdge];
}

#pragma mark Variables Handling

- (IBAction)freezeVariables:(id)__unused sender
{
	[self.variableController freezeVariables];
}

- (IBAction)copy:(id)__unused sender
{
	[self.variableController copyVariables];
}

- (IBAction)copyAddress:(id)__unused sender
{
	[self.variableController copyAddress];
}

- (IBAction)paste:(id)__unused sender
{
	[self.variableController pasteVariables];
}

- (IBAction)cut:(id)__unused sender
{
	[self.variableController copyVariables];
	[self removeSelectedSearchValues:nil];
}

- (IBAction)removeSelectedSearchValues:(id)__unused sender
{
	[self.variableController removeSelectedSearchValues];
}

- (IBAction)addVariable:(id)sender
{
	[self.variableController addVariable:sender];
}

- (IBAction)nopVariables:(id)__unused sender
{
	[self.variableController nopVariables:[self selectedVariables]];
}

- (IBAction)requestEditingVariablesValue:(id)__unused sender
{
	if (self.editValueWindowController == nil)
	{
		self.editValueWindowController = [[ZGEditValueWindowController alloc] initWithVariableController:self.variableController];
	}
	
	[self.editValueWindowController requestEditingValuesFromVariables:self.selectedVariables withProcessTask:self.currentProcess.processTask attachedToWindow:self.window scriptManager:self.scriptManager];
}

- (IBAction)requestEditingVariableDescription:(id)__unused sender
{
	if (self.editDescriptionWindowController == nil)
	{
		self.editDescriptionWindowController = [[ZGEditDescriptionWindowController alloc] initWithVariableController:self.variableController];
	}
	
	[self.editDescriptionWindowController requestEditingDescriptionFromVariable:[self.selectedVariables objectAtIndex:0] attachedToWindow:self.window];
}

- (IBAction)requestEditingVariableAddress:(id)__unused sender
{
	if (self.editAddressWindowController == nil)
	{
		self.editAddressWindowController = [[ZGEditAddressWindowController alloc] initWithVariableController:self.variableController];
	}
	
	[self.editAddressWindowController requestEditingAddressFromVariable:[self.selectedVariables objectAtIndex:0] attachedToWindow:self.window];
}

- (IBAction)requestEditingVariablesSize:(id)__unused sender
{
	if (self.editSizeWindowController == nil)
	{
		self.editSizeWindowController = [[ZGEditSizeWindowController alloc] initWithVariableController:self.variableController];
	}
	
	[self.editSizeWindowController requestEditingSizesFromVariables:self.selectedVariables attachedToWindow:self.window];
}

- (IBAction)relativizeVariablesAddress:(id)__unused sender
{
	[self.variableController relativizeVariables:[self selectedVariables]];
}

#pragma mark Variable Watching Handling

- (IBAction)watchVariable:(id)sender
{
	if (self.watchVariableWindowController == nil)
	{
		self.watchVariableWindowController = [[ZGWatchVariableWindowController alloc] initWithBreakPointController:self.breakPointController];
	}
	
	[self.watchVariableWindowController watchVariable:[self.selectedVariables objectAtIndex:0] withWatchPointType:(ZGWatchPointType)[sender tag] inProcess:self.currentProcess attachedToWindow:self.window completionHandler:^(NSArray *foundVariables) {
		if (foundVariables.count > 0)
		{
			NSIndexSet *rowIndexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, foundVariables.count)];
			[self.variableController addVariables:foundVariables atRowIndexes:rowIndexes];
			[ZGVariableController annotateVariables:foundVariables process:self.currentProcess];
			[self.tableController.variablesTableView scrollRowToVisible:0];
		}
	}];
}

#pragma mark Showing Other Controllers

- (IBAction)showMemoryViewer:(id)__unused sender
{
	ZGVariable *selectedVariable = [[self selectedVariables] objectAtIndex:0];
	
	[ZGNavigationPost
	 postShowMemoryViewerWithProcess:self.currentProcess
	 address:selectedVariable.address
	 selectionLength:selectedVariable.size > 0 ? selectedVariable.size : DEFAULT_MEMORY_VIEWER_SELECTION_LENGTH];
}

- (IBAction)showDebugger:(id)__unused sender
{
	ZGVariable *selectedVariable = [[self selectedVariables] firstObject];
	[ZGNavigationPost postShowDebuggerWithProcess:self.currentProcess address:selectedVariable.address];
}

@end
