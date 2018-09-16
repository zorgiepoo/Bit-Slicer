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

#import <Cocoa/Cocoa.h>
#import "ZGSearchFunctions.h"
#import "AGScopeBar.h"
#import "ZGMemoryWindowController.h"

#define ZGLocalizableSearchDocumentString(string) NSLocalizedStringFromTable(string, @"[Code] Search Document", nil)

@class ZGDocumentTableController;
@class ZGVariableController;
@class ZGDocumentSearchController;
@class ZGVariable;
@class ZGProcess;
@class ZGSearchResults;
@class ZGRunningProcess;
@class ZGDocumentData;
@class ZGSearchData;
@class ZGScriptManager;
@class ZGTableView;
@class ZGDebuggerController;
@class ZGBreakPointController;
@class ZGScriptingInterpreter;
@class ZGLoggerWindowController;
@class ZGHotKeyCenter;
@class ZGDocument;
@class ZGAppTerminationState;

NS_ASSUME_NONNULL_BEGIN

@interface ZGDocumentWindowController : ZGMemoryWindowController <AGScopeBarDelegate, NSAlertDelegate>

@property (readonly, nonatomic) ZGBreakPointController *breakPointController;
@property (readonly, nonatomic) ZGScriptingInterpreter *scriptingInterpreter;
@property (readonly, nonatomic) ZGLoggerWindowController *loggerWindowController;
@property (readonly, nonatomic) ZGHotKeyCenter *hotKeyCenter;

@property (nonatomic) IBOutlet ZGTableView *variablesTableView;
@property (nonatomic) IBOutlet NSProgressIndicator *progressIndicator;
@property (nonatomic) IBOutlet NSPopUpButton *dataTypesPopUpButton;
@property (nonatomic) IBOutlet NSButton *storeValuesButton;
@property (nonatomic) IBOutlet NSSearchField *searchValueTextField;
@property (nonatomic) IBOutlet NSPopUpButton *functionPopUpButton;

@property (nonatomic, readonly) ZGDocumentTableController *tableController;
@property (nonatomic, readonly) ZGVariableController *variableController;
@property (nonatomic, readonly) ZGDocumentSearchController *searchController;
@property (nonatomic, readonly) ZGScriptManager *scriptManager;

@property (nonatomic, readonly) ZGDocumentData *documentData;
@property (nonatomic, readonly) ZGSearchData *searchData;

@property (nonatomic, readonly) NSString *flagsStringValue;
@property (nonatomic, readonly) BOOL showsFlags;

- (id)initWithProcessTaskManager:(ZGProcessTaskManager *)processTaskManager rootlessConfiguration:(nullable ZGRootlessConfiguration *)rootlessConfiguration debuggerController:(ZGDebuggerController *)debuggerController breakPointController:(ZGBreakPointController *)breakPointController scriptingInterpreter:(ZGScriptingInterpreter *)scriptingInterpreter hotKeyCenter:(ZGHotKeyCenter *)hotKeyCenter loggerWindowController:(ZGLoggerWindowController *)loggerWindowController lastChosenInternalProcessName:(nullable NSString *)lastChosenInternalProcessName preferringNewTab:(BOOL)preferringNewTab delegate:(nullable id <ZGChosenProcessDelegate, ZGMemorySelectionDelegate, ZGShowMemoryWindow>)delegate;

- (void)loadDocumentUserInterface;

- (void)cleanupWithAppTerminationState:(ZGAppTerminationState *)appTerminationState;

- (void)markDocumentChange;

- (void)updateNumberOfValuesDisplayedStatus;
- (void)setStatusString:(NSString *)statusString;

- (IBAction)requestEditingVariableDescription:(nullable id)sender;
- (IBAction)requestEditingVariableAddress:(nullable id)sender;

- (NSIndexSet *)selectedVariableIndexes;
- (NSArray<ZGVariable *> *)selectedVariables;

- (void)updateOptions;

- (ZGVariableType)selectedDataType;
- (ZGFunctionType)selectedFunctionType;

- (void)deselectSearchField;
- (void)insertStoredValueToken;

- (void)updateVariables:(NSArray<ZGVariable *> *)newWatchVariablesArray searchResults:(nullable ZGSearchResults *)searchResults;

@end

NS_ASSUME_NONNULL_END
