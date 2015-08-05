/*
 * Created by Mayur Pawashe on 12/27/12.
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
#import "ZGMemoryTypes.h"
#import "ZGMemoryNavigationWindowController.h"
#import "ZGCodeInjectionWindowController.h"
#import "ZGBreakPointDelegate.h"
#import "ZGBreakPointConditionViewController.h"
#import "ZGBacktraceViewController.h"
#import "ZGHotKeyDelegate.h"
#import "ZGRegistersViewController.h"
#import "ZGMemorySelectionDelegate.h"

@class ZGProcess;
@class ZGInstruction;
@class ZGMachBinary;
@class ZGProcessTaskManager;
@class ZGBreakPointController;
@class ZGScriptingInterpreter;
@class ZGHotKeyCenter;
@class ZGLoggerWindowController;

extern NSString * __nonnull ZGPauseAndUnpauseHotKey;
extern NSString * __nonnull ZGStepInHotKey;
extern NSString * __nonnull ZGStepOverHotKey;
extern NSString * __nonnull ZGStepOutHotKey;

@interface ZGDebuggerController : ZGMemoryNavigationWindowController <NSTableViewDataSource, ZGBreakPointDelegate, ZGBreakPointConditionDelegate, ZGBacktraceViewControllerDelegate, ZGHotKeyDelegate, ZGRegistersViewDelegate>

- (nonnull id)initWithProcessTaskManager:(nonnull ZGProcessTaskManager *)processTaskManager rootlessConfiguration:(nullable ZGRootlessConfiguration *)rootlessConfiguration breakPointController:(nonnull ZGBreakPointController *)breakPointController scriptingInterpreter:(nonnull ZGScriptingInterpreter *)scriptingInterpreter hotKeyCenter:(nonnull ZGHotKeyCenter *)hotKeyCenter loggerWindowController:(nonnull ZGLoggerWindowController *)loggerWindowController delegate:(nullable id <ZGChosenProcessDelegate, ZGMemorySelectionDelegate, ZGShowMemoryWindow>)delegate;

- (void)cleanup;

@property (nonatomic, readonly, nonnull) NSMutableArray *haltedBreakPoints;

@property (nonatomic, readonly, nonnull) ZGHotKey *pauseAndUnpauseHotKey;
@property (nonatomic, readonly, nonnull) ZGHotKey *stepInHotKey;
@property (nonatomic, readonly, nonnull) ZGHotKey *stepOverHotKey;
@property (nonatomic, readonly, nonnull) ZGHotKey *stepOutHotKey;

- (void)updateWindowAndReadMemory:(BOOL)shouldReadMemory;

- (BOOL)isProcessIdentifierHalted:(pid_t)processIdentifier;

- (nonnull NSArray *)selectedInstructions;

- (void)jumpToMemoryAddress:(ZGMemoryAddress)address inProcess:(nonnull ZGProcess *)requestedProcess;

@end
