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
	IBOutlet NSTextField *_searchValueLabel;
	IBOutlet NSTextField *_flagsLabel;
	IBOutlet NSButton *_optionsDisclosureButton;
	IBOutlet NSView *_optionsView;
	IBOutlet ZGMemoryDumpController *_memoryDumpController;
	IBOutlet ZGMemoryProtectionController *_memoryProtectionController;
	ZGTimer *_watchVariablesTimer;
}

@property (assign) IBOutlet NSWindow *watchWindow;
@property (assign) IBOutlet NSProgressIndicator *searchingProgressIndicator;
@property (assign) IBOutlet NSTextField *generalStatusTextField;
@property (assign) IBOutlet NSMatrix *variableQualifierMatrix;
@property (assign) IBOutlet NSPopUpButton *runningApplicationsPopUpButton;
@property (assign) IBOutlet NSPopUpButton *dataTypesPopUpButton;
@property (assign) IBOutlet NSButton *searchButton;
@property (assign) IBOutlet NSButton *clearButton;
@property (assign) IBOutlet NSTextField *searchValueTextField;
@property (assign) IBOutlet NSTextField *flagsTextField;
@property (assign) IBOutlet NSPopUpButton *functionPopUpButton;
@property (assign) IBOutlet NSButton *scanUnwritableValuesCheckBox;
@property (assign) IBOutlet NSButton *ignoreDataAlignmentCheckBox;
@property (assign) IBOutlet NSButton *ignoreCaseCheckBox;
@property (assign) IBOutlet NSButton *includeNullTerminatorCheckBox;
@property (assign) IBOutlet NSTextField *beginningAddressTextField;
@property (assign) IBOutlet NSTextField *endingAddressTextField;
@property (assign) IBOutlet NSTextField *beginningAddressLabel;
@property (assign) IBOutlet NSTextField *endingAddressLabel;

@property (assign) IBOutlet ZGDocumentTableController *tableController;
@property (assign) IBOutlet ZGVariableController *variableController;
@property (assign) IBOutlet ZGDocumentSearchController *searchController;

@property (readwrite, retain) NSArray *watchVariablesArray;
@property (readwrite, retain) ZGProcess *currentProcess;
@property (readwrite, copy) NSString *desiredProcessName;
@property (readwrite) ZGVariableType currentSearchDataType;
@property (readwrite, retain) ZGDocumentInfo *documentState;

- (IBAction)editVariablesAddress:(id)sender;

- (NSArray *)selectedVariables;
- (void)markDocumentChange;

- (void)updateClearButton;
- (void)updateFlags;

- (BOOL)doesFunctionTypeAllowSearchInput;
- (BOOL)isFunctionTypeStore;

- (void)setWatchVariablesArrayAndUpdateInterface:(NSArray *)newWatchVariablesArray;

- (void)removeRunningApplicationFromPopupButton:(NSRunningApplication *)oldRunningApplication;

@end
