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
#import "ZGComparisonFunctions.h"

@class ZGProcess;
@class ZGTimer;
@class ZGVariableController;
@class ZGDocumentSearchController;
@class ZGDocumentTableController;
@class ZGMemoryDumpController;
@class ZGMemoryProtectionController;

#define NON_EXISTENT_PID_NUMBER -1

@interface ZGDocumentInfo : NSObject
{
	BOOL loadedFromSave;
	NSInteger selectedDatatypeTag;
	NSInteger qualifierTag;
	NSInteger functionTypeTag;
	BOOL scanUnwritableValues;
	BOOL ignoreDataAlignment;
	BOOL exactStringLength;
	BOOL ignoreStringCase;
	NSString *beginningAddress;
	NSString *endingAddress;
	NSString *searchValue;
	NSArray *watchVariablesArray;
}

@property (readwrite) BOOL loadedFromSave;
@property (readwrite) NSInteger selectedDatatypeTag;
@property (readwrite) NSInteger qualifierTag;
@property (readwrite) NSInteger functionTypeTag;
@property (readwrite) BOOL scanUnwritableValues;
@property (readwrite) BOOL ignoreDataAlignment;
@property (readwrite) BOOL exactStringLength;
@property (readwrite) BOOL ignoreStringCase;
@property (readwrite, copy) NSString *beginningAddress;
@property (readwrite, copy) NSString *endingAddress;
@property (readwrite, copy) NSString *searchValue;
@property (readwrite, retain) NSArray *watchVariablesArray;

@end

@interface ZGDocument : NSDocument
{
	IBOutlet NSPopUpButton *runningApplicationsPopUpButton;
	IBOutlet NSTextField *generalStatusTextField;
	IBOutlet NSTextField *searchValueTextField;
	IBOutlet NSTextField *searchValueLabel;
	IBOutlet NSTextField *flagsTextField;
	IBOutlet NSTextField *flagsLabel;
	IBOutlet NSProgressIndicator *searchingProgressIndicator;
	IBOutlet NSPopUpButton *dataTypesPopUpButton;
	IBOutlet NSPopUpButton *functionPopUpButton;
	IBOutlet NSButton *optionsDisclosureButton;
	IBOutlet NSView *optionsView;
	IBOutlet NSButton *clearButton;
	IBOutlet NSButton *searchButton;
	IBOutlet NSMatrix *variableQualifierMatrix;
	IBOutlet NSTextField *beginningAddressLabel;
	IBOutlet NSTextField *beginningAddressTextField;
	IBOutlet NSTextField *endingAddressLabel;
	IBOutlet NSTextField *endingAddressTextField;
	IBOutlet NSButton *scanUnwritableValuesCheckBox;
	IBOutlet NSButton *ignoreDataAlignmentCheckBox;
	IBOutlet NSButton *ignoreCaseCheckBox;
	IBOutlet NSButton *includeNullTerminatorCheckBox;
	IBOutlet NSWindow *watchWindow;
	IBOutlet ZGVariableController *variableController;
	IBOutlet ZGDocumentSearchController *searchController;
	IBOutlet ZGDocumentTableController *tableController;
	IBOutlet ZGMemoryDumpController *memoryDumpController;
	IBOutlet ZGMemoryProtectionController *memoryProtectionController;
	NSArray *watchVariablesArray;
	ZGProcess *currentProcess;
	NSString *desiredProcessName;
	ZGTimer *watchVariablesTimer;
	ZGVariableType currentSearchDataType;
	
	ZGDocumentInfo *documentState;
}

@property (readonly) IBOutlet NSWindow *watchWindow;
@property (readonly) IBOutlet NSProgressIndicator *searchingProgressIndicator;
@property (readonly) IBOutlet NSTextField *generalStatusTextField;
@property (readonly) IBOutlet NSMatrix *variableQualifierMatrix;
@property (readonly) IBOutlet NSPopUpButton *runningApplicationsPopUpButton;
@property (readonly) IBOutlet NSPopUpButton *dataTypesPopUpButton;
@property (readonly) IBOutlet NSButton *searchButton;
@property (readonly) IBOutlet NSButton *clearButton;
@property (readonly) IBOutlet NSTextField *searchValueTextField;
@property (readonly) IBOutlet NSTextField *flagsTextField;
@property (readonly) IBOutlet NSPopUpButton *functionPopUpButton;
@property (readonly) IBOutlet NSButton *scanUnwritableValuesCheckBox;
@property (readonly) IBOutlet NSButton *ignoreDataAlignmentCheckBox;
@property (readonly) IBOutlet NSButton *ignoreCaseCheckBox;
@property (readonly) IBOutlet NSButton *includeNullTerminatorCheckBox;
@property (readonly) IBOutlet NSTextField *beginningAddressTextField;
@property (readonly) IBOutlet NSTextField *endingAddressTextField;
@property (readonly) IBOutlet NSTextField *beginningAddressLabel;
@property (readonly) IBOutlet NSTextField *endingAddressLabel;

@property (readwrite, retain) NSArray *watchVariablesArray;
@property (readwrite, retain) ZGProcess *currentProcess;
@property (readwrite, copy) NSString *desiredProcessName;
@property (readwrite, retain) ZGDocumentInfo *documentState;
@property (readonly) IBOutlet ZGDocumentTableController *tableController;
@property (readonly) IBOutlet ZGVariableController *variableController;
@property (readonly) IBOutlet ZGDocumentSearchController *searchController;

- (NSArray *)selectedVariables;
- (void)markDocumentChange;

- (void)updateClearButton;
- (void)updateFlags;

- (BOOL)doesFunctionTypeAllowSearchInput;
- (BOOL)isFunctionTypeStore;

- (void)setWatchVariablesArrayAndUpdateInterface:(NSArray *)newWatchVariablesArray;

- (void)removeRunningApplicationFromPopupButton:(NSRunningApplication *)oldRunningApplication;

- (IBAction)runningApplicationsPopUpButtonRequest:(id)sender;
- (IBAction)dataTypePopUpButtonRequest:(id)sender;
- (IBAction)functionTypePopUpButtonRequest:(id)sender;
- (IBAction)qualifierMatrixButtonRequest:(id)sender;
- (IBAction)optionsDisclosureButton:(id)sender;
- (IBAction)searchValue:(id)sender;
- (IBAction)storeAllValues:(id)sender;
- (IBAction)clearSearchValues:(id)sender;
- (IBAction)removeSelectedSearchValues:(id)sender;
- (IBAction)addVariable:(id)sender;
- (IBAction)freezeVariables:(id)sender;

- (IBAction)editVariablesValue:(id)sender;
- (IBAction)editVariablesAddress:(id)sender;
- (IBAction)editVariablesSize:(id)sender;

- (IBAction)memoryDumpRangeRequest:(id)sender;
- (IBAction)memoryDumpAllRequest:(id)sender;

- (IBAction)changeMemoryProtection:(id)sender;

- (IBAction)pauseOrUnpauseProcess:(id)sender;

- (IBAction)copy:(id)sender;

@end
