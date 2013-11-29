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

#import <Cocoa/Cocoa.h>

@class ZGDocumentTableController;
@class ZGVariableController;
@class ZGDocumentSearchController;
@class ZGDocumentBreakPointController;
@class ZGProcess;
@class ZGSearchResults;
@class ZGRunningProcess;
@class ZGDocumentData;
@class ZGSearchData;
@class ZGScriptManager;

#define ZGTargetProcessDiedNotification @"ZGTargetProcessDiedNotification"

@interface ZGDocumentWindowController : NSWindowController

@property (assign) IBOutlet NSTableView *variablesTableView;
@property (assign) IBOutlet NSProgressIndicator *deterministicProgressIndicator;
@property (assign) IBOutlet NSProgressIndicator *indeterministicProgressIndicator;
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
@property (assign) IBOutlet NSTextField *searchValueLabel;
@property (assign) IBOutlet NSTextField *flagsLabel;
@property (assign) IBOutlet NSButton *optionsDisclosureButton;
@property (assign) IBOutlet NSView *optionsView;

@property (strong) ZGDocumentTableController *tableController;
@property (strong) ZGVariableController *variableController;
@property (strong) ZGDocumentSearchController *searchController;
@property (strong) ZGDocumentBreakPointController *documentBreakPointController;
@property (strong) ZGScriptManager *scriptManager;

@property (nonatomic) BOOL isOccluded;

@property (strong, nonatomic) ZGProcess *currentProcess;

@property (assign, nonatomic) ZGDocumentData *documentData;
@property (assign, nonatomic) ZGSearchData *searchData;

- (void)loadDocumentUserInterface;

- (void)markDocumentChange;

- (void)setStatus:(id)status;

- (IBAction)requestEditingVariableAddress:(id)sender;

- (NSIndexSet *)selectedVariableIndexes;
- (NSArray *)selectedVariables;

- (void)updateClearButton;
- (void)updateFlagsAndSearchButtonTitle;

- (BOOL)functionTypeAllowsSearchInput;
- (BOOL)isFunctionTypeStore;

- (void)updateVariables:(NSArray *)newWatchVariablesArray searchResults:(ZGSearchResults *)searchResults;

- (void)updateObservingProcessOcclusionState;

- (void)removeRunningProcessFromPopupButton:(ZGRunningProcess *)oldRunningProcess;

@end
