/*
 * Copyright (c) 2012 Mayur Pawashe
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
@class ZGBreakPoint;
@class ZGMachBinary;
@class ZGProcessTaskManager;
@class ZGBreakPointController;
@class ZGScriptingInterpreter;
@class ZGHotKeyCenter;
@class ZGLoggerWindowController;

NS_ASSUME_NONNULL_BEGIN

extern NSString *ZGPauseAndUnpauseHotKey;
extern NSString *ZGStepInHotKey;
extern NSString *ZGStepOverHotKey;
extern NSString *ZGStepOutHotKey;

@interface ZGDebuggerController : ZGMemoryNavigationWindowController <NSTableViewDataSource, ZGBreakPointDelegate, ZGBreakPointConditionDelegate, ZGBacktraceViewControllerDelegate, ZGHotKeyDelegate, ZGRegistersViewDelegate>

- (id)initWithProcessTaskManager:(ZGProcessTaskManager *)processTaskManager rootlessConfiguration:(nullable ZGRootlessConfiguration *)rootlessConfiguration breakPointController:(nonnull ZGBreakPointController *)breakPointController scriptingInterpreter:(ZGScriptingInterpreter *)scriptingInterpreter hotKeyCenter:(ZGHotKeyCenter *)hotKeyCenter loggerWindowController:(ZGLoggerWindowController *)loggerWindowController delegate:(nullable id <ZGChosenProcessDelegate, ZGMemorySelectionDelegate, ZGShowMemoryWindow>)delegate;

- (void)cleanup;

@property (nonatomic, readonly) NSMutableArray<ZGBreakPoint *> *haltedBreakPoints;

@property (nonatomic, readonly) ZGHotKey *pauseAndUnpauseHotKey;
@property (nonatomic, readonly) ZGHotKey *stepInHotKey;
@property (nonatomic, readonly) ZGHotKey *stepOverHotKey;
@property (nonatomic, readonly) ZGHotKey *stepOutHotKey;

- (void)updateWindowAndReadMemory:(BOOL)shouldReadMemory;

- (BOOL)isProcessIdentifierHalted:(pid_t)processIdentifier;

- (nonnull NSArray<ZGInstruction *> *)selectedInstructions;

- (void)jumpToMemoryAddress:(ZGMemoryAddress)address inProcess:(ZGProcess *)requestedProcess;

@end

NS_ASSUME_NONNULL_END
