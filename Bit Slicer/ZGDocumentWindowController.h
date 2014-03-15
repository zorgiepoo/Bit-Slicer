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
#import "ZGSearchFunctions.h"
#import "AGScopeBar.h"

@class ZGDocumentTableController;
@class ZGVariableController;
@class ZGDocumentSearchController;
@class ZGProcess;
@class ZGSearchResults;
@class ZGRunningProcess;
@class ZGDocumentData;
@class ZGSearchData;
@class ZGScriptManager;
@class APTokenSearchField;
@class ZGTableView;
@class ZGBreakPointController;
@class ZGLoggerWindowController;
@class ZGDocument;

#define ZGTargetProcessDiedNotification @"ZGTargetProcessDiedNotification"

@interface ZGDocumentWindowController : NSWindowController <AGScopeBarDelegate>

@property (readonly, nonatomic) ZGBreakPointController *breakPointController;
@property (readonly, nonatomic) ZGLoggerWindowController *loggerWindowController;

@property (nonatomic, assign) IBOutlet ZGTableView *variablesTableView;
@property (nonatomic, assign) IBOutlet NSProgressIndicator *progressIndicator;
@property (nonatomic, assign) IBOutlet NSPopUpButton *runningApplicationsPopUpButton;
@property (nonatomic, assign) IBOutlet NSPopUpButton *dataTypesPopUpButton;
@property (nonatomic, assign) IBOutlet NSButton *storeValuesButton;
@property (nonatomic, assign) IBOutlet APTokenSearchField *searchValueTextField;
@property (nonatomic, assign) IBOutlet NSTextField *flagsTextField;
@property (nonatomic, assign) IBOutlet NSPopUpButton *functionPopUpButton;

@property (nonatomic, assign) IBOutlet NSTextField *flagsLabel;

@property (nonatomic, assign) IBOutlet AGScopeBar *scopeBar;
@property (nonatomic, assign) IBOutlet NSView *scopeBarFlagsView;

@property (nonatomic) ZGDocumentTableController *tableController;
@property (nonatomic) ZGVariableController *variableController;
@property (nonatomic) ZGDocumentSearchController *searchController;
@property (nonatomic) ZGScriptManager *scriptManager;

@property (nonatomic) BOOL isOccluded;

@property (nonatomic) ZGProcess *currentProcess;

@property (assign, nonatomic) ZGDocumentData *documentData;
@property (assign, nonatomic) ZGSearchData *searchData;

- (id)initWithDocument:(ZGDocument *)document;

- (void)loadDocumentUserInterface;

- (void)markDocumentChange;

- (void)setStatus:(id)status;

- (IBAction)requestEditingVariableDescription:(id)sender;
- (IBAction)requestEditingVariableAddress:(id)sender;

- (NSIndexSet *)selectedVariableIndexes;
- (NSArray *)selectedVariables;

- (void)updateOptions;

- (ZGVariableType)selectedDataType;
- (ZGFunctionType)selectedFunctionType;

- (void)createSearchMenu;
- (void)deselectSearchField;
- (IBAction)insertStoredValueToken:(id)sender;

- (void)updateVariables:(NSArray *)newWatchVariablesArray searchResults:(ZGSearchResults *)searchResults;

- (void)updateObservingProcessOcclusionState;

- (void)removeRunningProcessFromPopupButton:(ZGRunningProcess *)oldRunningProcess;

@end
