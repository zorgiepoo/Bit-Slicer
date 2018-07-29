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

#import <Foundation/Foundation.h>
#import "Python/Python.h"
#import "VDKQueue.h"
#import "ZGMemoryTypes.h"
#import "ZGRegisterEntries.h"
#import "ZGScriptPromptDelegate.h"

@class ZGDocumentWindowController;
@class ZGVariable;
@class ZGProcess;
@class ZGBreakPoint;
@class ZGRegistersState;
@class ZGAppTerminationState;
@class ZGScriptPrompt;

#define SCRIPT_PYTHON_ERROR @"SCRIPT_PYTHON_ERROR"

#define ZGScriptNotificationTypeKey @"script_type"
#define ZGScriptNotificationPromptHashKey @"ZGScriptNotificationPromptHashKey"

NS_ASSUME_NONNULL_BEGIN

extern NSString *ZGScriptDefaultApplicationEditorKey;

@interface ZGScriptManager : NSObject <VDKQueueDelegate, NSUserNotificationCenterDelegate>

- (id)initWithWindowController:(ZGDocumentWindowController *)windowController;

- (void)cleanup;
- (void)cleanupWithAppTerminationState:(ZGAppTerminationState *)appTerminationState;

- (void)triggerCurrentProcessChanged;

- (void)loadCachedScriptsFromVariables:(NSArray<ZGVariable *> *)variables;

- (void)openScriptForVariable:(ZGVariable *)variable;

- (void)runScriptForVariable:(ZGVariable *)variable;
- (void)stopScriptForVariable:(ZGVariable *)variable;
- (void)removeScriptForVariable:(ZGVariable *)variable;

- (BOOL)hasAttachedPrompt;
- (void)showScriptPrompt:(ZGScriptPrompt *)scriptPrompt delegate:(id <ZGScriptPromptDelegate>)delegate;
- (void)handleScriptPrompt:(ZGScriptPrompt *)scriptPrompt withAnswer:(NSString *)answer sender:(id)sender;
- (void)handleScriptPromptHash:(NSNumber *)scriptPromptHash withUserNotificationReply:(nullable NSString *)reply;

- (void)handleDataAddress:(ZGMemoryAddress)dataAddress accessedFromInstructionAddress:(ZGMemoryAddress)instructionAddress registersState:(ZGRegistersState *)registersState callback:(PyObject *)callback sender:(id)sender;
- (void)handleInstructionBreakPoint:(ZGBreakPoint *)breakPoint withRegistersState:(ZGRegistersState *)registersState callback:(nullable PyObject *)callback sender:(id)sender;

- (void)handleHotKeyTriggerWithInternalID:(UInt32)hotKeyID callback:(PyObject *)callback sender:(id)sender;

@end

NS_ASSUME_NONNULL_END
