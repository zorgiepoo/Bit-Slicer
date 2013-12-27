/*
 * Created by Mayur Pawashe on 12/25/13.
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

#import "ZGWatchVariableWindowController.h"
#import "ZGDocumentWindowController.h"
#import "ZGAppController.h"
#import "ZGBreakPointController.h"
#import "ZGDebuggerController.h"
#import "ZGInstruction.h"
#import "ZGBreakPoint.h"
#import "ZGVariable.h"
#import "ZGProcess.h"
#import "ZGCalculator.h"
#import "ZGVirtualMemory.h"
#import "ZGVirtualMemoryHelpers.h"

@interface ZGWatchVariableWindowController ()

@property (nonatomic, assign) IBOutlet NSProgressIndicator *progressIndicator;
@property (nonatomic, assign) IBOutlet NSTextField *statusTextField;

@property (nonatomic) ZGProcess *watchProcess;
@property (nonatomic) id watchActivity;
@property (nonatomic) NSMutableArray *foundBreakPointAddresses;
@property (nonatomic) NSMutableArray *foundVariables;
@property (nonatomic, copy) watch_variable_completion_t completionHandler;

@end

@implementation ZGWatchVariableWindowController

- (id)init
{
	self = [super init];
	if (self != nil)
	{
		[[NSNotificationCenter defaultCenter]
		 addObserver:self
		 selector:@selector(applicationWillTerminate:)
		 name:NSApplicationWillTerminateNotification
		 object:nil];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	self.watchProcess = nil;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	[[[ZGAppController sharedController] breakPointController] removeObserver:self];
}

- (NSString *)windowNibName
{
	return NSStringFromClass([self class]);
}

- (IBAction)stopWatching:(id)sender
{
	[[[ZGAppController sharedController] breakPointController] removeObserver:self];
	self.watchProcess = nil;
	
	[NSApp endSheet:self.window];
	[self.window close];
	
	if (self.watchActivity != nil)
	{
		[[NSProcessInfo processInfo] endActivity:self.watchActivity];
		self.watchActivity = nil;
	}
	
	[self.progressIndicator stopAnimation:nil];
	
	[self.foundBreakPointAddresses removeAllObjects];
	
	self.completionHandler(self.foundVariables);
	self.completionHandler = nil;
	self.foundVariables = nil;
	self.foundBreakPointAddresses = nil;
}

- (void)watchProcessDied:(NSNotification *)notification
{
	[self stopWatching:nil];
}

- (void)setWatchProcess:(ZGProcess *)watchProcess
{
	if (_watchProcess != nil)
	{
		[[NSNotificationCenter defaultCenter]
		 removeObserver:self
		 name:ZGTargetProcessDiedNotification
		 object:watchProcess];
	}
	
	_watchProcess = watchProcess;
	
	if (_watchProcess != nil)
	{
		[[NSNotificationCenter defaultCenter]
		 addObserver:self
		 selector:@selector(watchProcessDied:)
		 name:ZGTargetProcessDiedNotification
		 object:watchProcess];
	}
}

- (void)dataAddress:(NSNumber *)dataAddress accessedByInstructionPointer:(ZGMemoryAddress)instructionAddress
{
	NSNumber *instructionAddressNumber = @(instructionAddress);
	if (!self.watchProcess.valid || [self.foundBreakPointAddresses containsObject:instructionAddressNumber]) return;
	
	[self.foundBreakPointAddresses addObject:instructionAddressNumber];
	
	ZGInstruction *instruction = [[[ZGAppController sharedController] debuggerController] findInstructionBeforeAddress:instructionAddress inProcess:self.watchProcess];
	
	if (instruction == nil)
	{
		NSLog(@"ERROR: Couldn't parse instruction before 0x%llX", instructionAddress);
		return;
	}
	
	NSString *partialPath = nil;
	ZGMemoryAddress slide = 0;
	ZGMemoryAddress relativeOffset = ZGInstructionOffset(self.watchProcess.processTask, self.watchProcess.pointerSize, self.watchProcess.dylinkerBinary, self.watchProcess.cacheDictionary, instruction.variable.address, instruction.variable.size, &slide, &partialPath);
	
	if (partialPath != nil && (slide > 0 || instruction.variable.address - relativeOffset > self.watchProcess.baseAddress))
	{
		instruction.variable.addressFormula = [NSString stringWithFormat:ZGBaseAddressFunction@"(\"%@\") + 0x%llX", partialPath, relativeOffset];
		instruction.variable.usesDynamicAddress = YES;
		instruction.variable.finishedEvaluatingDynamicAddress = YES;
	}
	
	[self.foundVariables addObject:instruction.variable];
	
	NSString *foundInstructionStatus = [NSString stringWithFormat:@"Found instruction \"%@\"", instruction.text];
	
	self.statusTextField.stringValue = foundInstructionStatus;
	
	if (NSClassFromString(@"NSUserNotification"))
	{
		NSUserNotification *userNotification = [[NSUserNotification alloc] init];
		userNotification.title = @"Found Instruction";
		userNotification.subtitle = self.watchProcess.name;
		userNotification.informativeText = foundInstructionStatus;
		[[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:userNotification];
	}
}

- (void)watchVariable:(ZGVariable *)variable withWatchPointType:(ZGWatchPointType)watchPointType inProcess:(ZGProcess *)process attachedToWindow:(NSWindow *)parentWindow completionHandler:(watch_variable_completion_t)completionHandler
{
	ZGBreakPoint *breakPoint = nil;
	if (![[[ZGAppController sharedController] breakPointController] addWatchpointOnVariable:variable inProcess:process watchPointType:watchPointType delegate:self getBreakPoint:&breakPoint])
	{
		NSRunAlertPanel(
						@"Failed to Watch Variable",
						@"A watchpoint could not be added for this variable at this time.",
						@"OK", nil, nil);
		return;
	}
	
	[self window]; // ensure window is loaded
	
	self.statusTextField.stringValue = [NSString stringWithFormat:@"Watching %@ accesses at %@ (%lld byte%@)", watchPointType == ZGWatchPointWrite ? @"write" : @"read or write", variable.addressStringValue, breakPoint.watchSize, breakPoint.watchSize != 1 ? @"s" : @""];
	
	[self.progressIndicator startAnimation:nil];
	
	[NSApp
	 beginSheet:self.window
	 modalForWindow:parentWindow
	 modalDelegate:nil
	 didEndSelector:nil
	 contextInfo:NULL];
	
	self.watchProcess = process;
	self.completionHandler = completionHandler;
	
	self.foundVariables = [[NSMutableArray alloc] init];
	self.foundBreakPointAddresses = [[NSMutableArray alloc] init];
	
	if ([[NSProcessInfo processInfo] respondsToSelector:@selector(beginActivityWithOptions:reason:)])
	{
		self.watchActivity = [[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiated reason:@"Watching Data Accesses"];
	}
}

@end
