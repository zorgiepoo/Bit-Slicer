/*
 * Created by Mayur Pawashe on 3/8/13.
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
#import "ZGMemoryTypes.h"
#import <HexFiend/HFTypes.h>
#import <HexFiend/HFFunctions.h>

extern NSString *ZGLastChosenInternalProcessNameNotification;
extern NSString *ZGLastChosenInternalProcessNameKey;

@class ZGProcess;
@class ZGProcessTaskManager;
@class ZGProcessList;

@interface ZGMemoryWindowController : NSWindowController
{
	ZGProcess *_currentProcess;
}

- (id)initWithProcessTaskManager:(ZGProcessTaskManager *)processTaskManager;

@property (nonatomic) ZGProcessTaskManager *processTaskManager;
@property (nonatomic) ZGProcessList *processList;

@property (nonatomic, copy) NSString *lastChosenInternalProcessName;

@property (nonatomic, assign) id debuggerController;

@property (nonatomic, assign) IBOutlet NSPopUpButton *runningApplicationsPopUpButton;

@property (nonatomic) NSUndoManager *undoManager;

@property (nonatomic) ZGProcess *currentProcess;
@property (nonatomic, copy) NSString *desiredProcessInternalName;

@property (nonatomic) NSTimer *updateDisplayTimer;

@property (nonatomic, readonly) BOOL isOccluded;

- (IBAction)pauseOrUnpauseProcess:(id)sender;

- (void)updateWindow;

- (void)setAndPostLastChosenInternalProcessName;

- (void)windowWillClose:(NSNotification *)notification;

- (void)setupProcessListNotifications;

- (BOOL)hasDefaultUpdateDisplayTimer;
- (void)updateOcclusionActivity;

- (void)startProcessActivity;
- (void)stopProcessActivity;

- (void)currentProcessChangedWithOldProcess:(ZGProcess *)oldProcess newProcess:(ZGProcess *)newProcess;
- (void)processListChanged:(NSDictionary *)change;
- (void)updateRunningProcesses;
- (void)runningApplicationsPopUpButtonWillPopUp:(NSNotification *)notification;

- (void)switchProcess;

- (IBAction)runningApplicationsPopUpButton:(id)__unused sender;

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)userInterfaceItem;

- (HFRange)preferredMemoryRequestRange;
- (IBAction)dumpAllMemory:(id)sender;
- (IBAction)dumpMemoryInRange:(id)sender;
- (IBAction)changeMemoryProtection:(id)sender;

@end
