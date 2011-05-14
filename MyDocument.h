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
 * Created by Mayur Pawashe on 10/25/09.
 * Copyright 2010 zgcoder. All rights reserved.
 */

#import <Cocoa/Cocoa.h>
#import "ZGVariable.h"
#import "ZGSearching.h"
#import "ZGComparisonFunctions.h"
@class ZGSearchData;
@class ZGProcess;
@class ZGTimer;
@class ZGAdditionalTasksController;

#define USER_INTERFACE_UPDATE_TIME_INTERVAL	0.33

@interface MyDocument : NSDocument <NSTableViewDelegate>
{
	IBOutlet NSPopUpButton			*runningApplicationsPopUpButton;
	IBOutlet NSTextField			*generalStatusTextField;
	IBOutlet NSTextField			*searchValueTextField;
	IBOutlet NSTextField			*searchValueLabel;
	IBOutlet NSTextField			*flagsTextField;
	IBOutlet NSTextField			*flagsLabel;
	IBOutlet NSProgressIndicator	*searchingProgressIndicator;
	IBOutlet NSTableView			*watchVariablesTableView;
	IBOutlet NSPopUpButton			*dataTypesPopUpButton;
	IBOutlet NSPopUpButton			*functionPopUpButton;
	IBOutlet NSButton				*optionsDisclosureButton;
	IBOutlet NSView					*optionsView;
	IBOutlet NSButton				*clearButton;
	IBOutlet NSButton				*searchButton;
	IBOutlet NSMatrix				*variableQualifierMatrix;
	IBOutlet NSWindow				*editVariablesValueWindow;
	IBOutlet NSTextField			*editVariablesValueTextField;
	IBOutlet NSWindow				*editVariablesAddressWindow;
	IBOutlet NSTextField            *editVariablesAddressTextField;
	IBOutlet NSButton				*compareInitialValuesCheckBox;
	IBOutlet NSTextField			*beginningAddressLabel;
	IBOutlet NSTextField			*beginningAddressTextField;
	IBOutlet NSTextField			*endingAddressLabel;
	IBOutlet NSTextField			*endingAddressTextField;
	IBOutlet NSButton				*scanReadOnlyValuesCheckBox;
	IBOutlet NSButton				*ignoreDataAlignmentCheckBox;
	IBOutlet NSButton				*ignoreCaseCheckBox;
	IBOutlet NSButton				*includeNullTerminatorCheckBox;
	IBOutlet NSWindow				*watchWindow;
	IBOutlet ZGAdditionalTasksController *additionalTasksController;
	NSArray							*watchVariablesArray;
	ZGProcess						*currentProcess;
	NSString						*desiredProcessName;
	ZGTimer							*watchVariablesTimer;
	ZGTimer							*updateSearchUserInterfaceTimer;
	BOOL							shouldIgnoreTableViewSelectionChange;
	ZGVariableType					currentSearchDataType;
	ZGSearchData					*searchData;
	ZGSearchArguments				searchArguments;
	
	// For comparing unicode strings
	CollatorRef						collator;
}

- (ZGProcess *)currentProcess;
- (NSArray *)selectedVariables;
- (void)prepareDocumentTask;
- (void)resumeDocument;
- (BOOL)canStartTask;

- (IBAction)runningApplicationsPopUpButtonRequest:(id)sender;
- (IBAction)dataTypePopUpButtonRequest:(id)sender;
- (IBAction)functionTypePopUpButtonRequest:(id)sender;
- (IBAction)qualifierMatrixButtonRequest:(id)sender;
- (IBAction)compareInitialValuesCheckBoxRequest:(id)sender;
- (IBAction)lockTarget:(id)sender;
- (IBAction)optionsDisclosureButton:(id)sender;
- (IBAction)searchValue:(id)sender;
- (IBAction)getInitialValues:(id)sender;
- (IBAction)clearSearchValues:(id)sender;
- (IBAction)removeSelectedSearchValues:(id)sender;
- (IBAction)addVariable:(id)sender;
- (IBAction)freezeVariables:(id)sender;

- (IBAction)editVariablesValueCancelButton:(id)sender;
- (IBAction)editVariablesValueOkayButton:(id)sender;
- (IBAction)editVariablesValue:(id)sender;

- (IBAction)editVariablesAddressCancelButton:(id)sender;
- (IBAction)editVariablesAddressOkayButton:(id)sender;
- (IBAction)editVariablesAddress:(id)sender;

- (IBAction)memoryDumpRequest:(id)sender;
- (IBAction)memoryDumpAllRequest:(id)sender;
- (IBAction)changeMemoryProtection:(id)sender;

- (IBAction)pauseOrUnpauseProcess:(id)sender;

- (IBAction)copy:(id)sender;

@end
