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
 *
 * ZGDocumentWindowController
 * -------------------------
 * This class manages document windows in Bit Slicer, providing the main interface
 * for users to interact with memory variables. It handles:
 *
 * - Variable management (creating, editing, deleting variables)
 * - Memory searching operations
 * - User interface coordination
 * - Document state management
 * - Script execution and management
 *
 * Document Window Architecture:
 * +------------------------+     +------------------------+     +------------------------+
 * |  Document Window       |     |  Controller Components |     |  Data Management      |
 * |  Controller            |     |                        |     |                        |
 * |------------------------|     |------------------------|     |------------------------|
 * | - Manages UI elements  |     | - TableController      |     | - DocumentData        |
 * | - Coordinates between  | --> | - VariableController   | --> | - SearchData          |
 * |   controllers          |     | - SearchController     |     | - Variables           |
 * | - Handles user input   |     | - ScriptManager        |     | - Search Results      |
 * +------------------------+     +------------------------+     +------------------------+
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
@property (nonatomic) NSPopUpButton *searchTypePopUpButton;

@property (nonatomic, readonly) ZGDocumentTableController *tableController;
@property (nonatomic, readonly) ZGVariableController *variableController;
@property (nonatomic, readonly) ZGDocumentSearchController *searchController;
@property (nonatomic, readonly) ZGScriptManager *scriptManager;

@property (nonatomic, readonly) ZGDocumentData *documentData;
@property (nonatomic, readonly) ZGSearchData *searchData;

@property (nonatomic, readonly) NSString *flagsStringValue;
@property (nonatomic, readonly) BOOL showsFlags;

/**
 * Initializes a document window controller with all required dependencies
 *
 * This method creates a new document window controller with all the necessary components
 * and services it needs to function. It establishes relationships with other controllers
 * and initializes the document's state.
 *
 * @param processTaskManager Manager for process-related tasks
 * @param rootlessConfiguration Configuration for handling rootless processes (can be nil)
 * @param debuggerController Controller for debugging functionality
 * @param breakPointController Controller for managing breakpoints
 * @param scriptingInterpreter Interpreter for executing scripts
 * @param hotKeyCenter Manager for hotkey functionality
 * @param loggerWindowController Controller for the logging window
 * @param lastChosenInternalProcessName Name of the last selected process (can be nil)
 * @param preferringNewTab Whether to open in a new tab (macOS 10.12+)
 * @param delegate Object that will receive delegate callbacks
 * @return The initialized document window controller
 */
- (id)initWithProcessTaskManager:(ZGProcessTaskManager *)processTaskManager rootlessConfiguration:(nullable ZGRootlessConfiguration *)rootlessConfiguration debuggerController:(ZGDebuggerController *)debuggerController breakPointController:(ZGBreakPointController *)breakPointController scriptingInterpreter:(ZGScriptingInterpreter *)scriptingInterpreter hotKeyCenter:(ZGHotKeyCenter *)hotKeyCenter loggerWindowController:(ZGLoggerWindowController *)loggerWindowController lastChosenInternalProcessName:(nullable NSString *)lastChosenInternalProcessName preferringNewTab:(BOOL)preferringNewTab delegate:(nullable id <ZGChosenProcessDelegate, ZGMemorySelectionDelegate, ZGShowMemoryWindow>)delegate;

/**
 * Loads and initializes the document's user interface
 *
 * This method sets up the document window's UI elements, configures their initial state,
 * and prepares the window for user interaction.
 */
- (void)loadDocumentUserInterface;

/**
 * Performs cleanup operations when the application is terminating
 *
 * This method ensures that all resources used by the document window are properly
 * released, including stopping any running scripts, saving document state, and
 * cleaning up memory. It updates the termination state to indicate when cleanup is complete.
 *
 * @param appTerminationState Object tracking the application's termination progress
 */
- (void)cleanupWithAppTerminationState:(ZGAppTerminationState *)appTerminationState;

/**
 * Marks the document as having unsaved changes
 *
 * This method notifies the document system that the document has been modified
 * and needs to be saved. It triggers the display of an indicator (usually a dot in
 * the window's close button) to show the user that there are unsaved changes.
 */
- (void)markDocumentChange;

/**
 * Updates the status display showing the number of values found
 *
 * This method refreshes the status bar or other UI element that shows how many
 * values or variables are currently displayed in the document.
 */
- (void)updateNumberOfValuesDisplayedStatus;

/**
 * Sets a custom status message in the document window
 *
 * This method displays a message in the document window's status area,
 * which can be used to provide feedback to the user about operations or state.
 *
 * @param statusString The message to display in the status area
 */
- (void)setStatusString:(NSString *)statusString;

- (void)updateSearchAddressOptions;

- (IBAction)requestEditingVariableDescription:(nullable id)sender;
- (IBAction)requestEditingVariableAddress:(nullable id)sender;

- (NSIndexSet *)selectedVariableIndexes;
- (NSArray<ZGVariable *> *)selectedVariables;

- (void)updateOptions;

- (ZGVariableType)selectedDataType;
- (ZGFunctionType)selectedFunctionType;

- (void)deselectSearchField;
- (void)insertStoredValueToken;

/**
 * Updates the document's variables and search results
 *
 * This method is a core part of the document's functionality, responsible for:
 * 1. Updating the list of variables being watched or displayed
 * 2. Updating the search results from memory scanning operations
 * 3. Refreshing the UI to reflect the new data
 * 4. Handling any state changes resulting from the update
 *
 * This method is typically called after search operations complete or when
 * variables are added, removed, or modified.
 *
 * @param newWatchVariablesArray The new array of variables to display
 * @param searchResults The results from a memory search operation (can be nil)
 */
- (void)updateVariables:(NSArray<ZGVariable *> *)newWatchVariablesArray searchResults:(nullable ZGSearchResults *)searchResults;

@end

NS_ASSUME_NONNULL_END
