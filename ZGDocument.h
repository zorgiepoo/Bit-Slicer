/*
 * Created by Mayur Pawashe on 10/25/09.
 *
 * Copyright (c) 2012 zgcoder
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

@class ZGProcess;
@class ZGVariableController;
@class ZGDocumentSearchController;
@class ZGDocumentTableController;
@class ZGDocumentBreakPointController;

#define NON_EXISTENT_PID_NUMBER -1

@interface ZGDocument : NSDocument

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

@property (strong) IBOutlet ZGDocumentTableController *tableController;
@property (strong) IBOutlet ZGVariableController *variableController;
@property (strong) IBOutlet ZGDocumentSearchController *searchController;
@property (assign) IBOutlet ZGDocumentBreakPointController *documentBreakPointController;

@property (readwrite, strong, nonatomic) NSArray *watchVariablesArray;
@property (readwrite, strong, nonatomic) ZGProcess *currentProcess;
@property (readwrite, copy, nonatomic) NSString *desiredProcessName;

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
