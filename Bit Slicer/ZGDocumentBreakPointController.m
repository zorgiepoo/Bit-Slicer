/*
 * Created by Mayur Pawashe on 12/29/12.
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

#import "ZGDocumentBreakPointController.h"
#import "ZGVariableController.h"
#import "ZGAppController.h"
#import "ZGDocumentSearchController.h"
#import "ZGDocumentTableController.h"
#import "ZGDocumentWindowController.h"
#import "ZGDebuggerController.h"
#import "ZGVariable.h"
#import "ZGProcess.h"
#import "ZGSearchProgress.h"
#import "ZGInstruction.h"
#import "ZGBreakPoint.h"
#import "ZGDocumentData.h"
#import "ZGRegion.h"
#import "ZGVirtualMemory.h"
#import "ZGVirtualMemoryHelpers.h"
#import "ZGCalculator.h"

@interface ZGDocumentBreakPointController ()

@property (nonatomic) ZGProcess *watchProcess;
@property (nonatomic) NSMutableArray *foundBreakPointAddresses;
@property (assign, nonatomic) NSUInteger variableInsertionIndex;
@property (assign, nonatomic) ZGDocumentWindowController *windowController;
@property (nonatomic) id watchActivity;

@end

@implementation ZGDocumentBreakPointController

#pragma mark Birth & Death

- (id)initWithWindowController:(ZGDocumentWindowController *)windowController
{
	self = [super init];
	if (self)
	{
		[[NSNotificationCenter defaultCenter]
		 addObserver:self
		 selector:@selector(applicationWillTerminate:)
		 name:NSApplicationWillTerminateNotification
		 object:nil];
		
		self.windowController = windowController;
		self.foundBreakPointAddresses = [[NSMutableArray alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	[self stopWatchingBreakPoints];
}

#pragma mark When to Stop?

- (void)stopWatchingBreakPoints
{
	if (self.watchProcess != nil)
	{
		[[[ZGAppController sharedController] breakPointController] removeObserver:self];
		self.watchProcess = nil;
	}
}

- (void)cancelTask
{
	[self stopWatchingBreakPoints];
	self.windowController.generalStatusTextField.stringValue = @"";
	
	[self.windowController.searchingProgressIndicator stopAnimation:nil];
	self.windowController.searchingProgressIndicator.indeterminate = NO;
	
	[self.foundBreakPointAddresses removeAllObjects];
	
	[self.windowController.searchController resumeFromTaskAndMakeSearchFieldFirstResponder:NO];
	
	if (self.watchActivity != nil)
	{
		[[NSProcessInfo processInfo] endActivity:self.watchActivity];
		self.watchActivity = nil;
	}
	
	[self.windowController updateObservingProcessOcclusionState];
}

- (void)watchProcessDied:(NSNotification *)notification
{
	[self cancelTask];
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

#pragma mark Handling Break Points

- (void)dataAddress:(NSNumber *)dataAddress accessedByInstructionPointer:(NSNumber *)instructionAddress
{
	if (self.watchProcess.valid && ![self.foundBreakPointAddresses containsObject:instructionAddress])
	{
		[self.foundBreakPointAddresses addObject:instructionAddress];
		
		ZGInstruction *instruction = [[[ZGAppController sharedController] debuggerController] findInstructionBeforeAddress:[instructionAddress unsignedLongLongValue] inProcess:self.watchProcess];
		
		if (instruction != nil)
		{
			NSString *partialPath = nil;
			ZGMemoryAddress slide = 0;
			ZGMemoryAddress relativeOffset = ZGInstructionOffset(self.watchProcess.processTask, self.watchProcess.pointerSize, self.watchProcess.cacheDictionary, instruction.variable.address, instruction.variable.size, &slide, &partialPath);
			
			if (partialPath != nil && (slide > 0 || instruction.variable.address - relativeOffset > self.watchProcess.baseAddress))
			{
				instruction.variable.addressFormula = [NSString stringWithFormat:@"0x%llX + "ZGBaseAddressFunction@"(\"%@\")", relativeOffset, partialPath];
				instruction.variable.usesDynamicAddress = YES;
				instruction.variable.finishedEvaluatingDynamicAddress = YES;
			}
			
			if (self.variableInsertionIndex >= self.windowController.documentData.variables.count)
			{
				self.variableInsertionIndex = 0;
			}
			
			[self.windowController.variableController addVariables:@[instruction.variable] atRowIndexes:[NSIndexSet indexSetWithIndex:self.variableInsertionIndex]];
			[self.windowController.tableController.variablesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:self.variableInsertionIndex] byExtendingSelection:NO];
			[self.windowController.tableController.variablesTableView scrollRowToVisible:self.variableInsertionIndex];
			[self.windowController.window makeFirstResponder:self.windowController.tableController.variablesTableView];
			
			self.variableInsertionIndex++;
			
			NSString *addedInstructionStatus = [NSString stringWithFormat:@"Added %@-byte instruction at %@...", instruction.variable.sizeStringValue, instruction.variable.addressStringValue];
			self.windowController.generalStatusTextField.stringValue = [addedInstructionStatus stringByAppendingString:@" Stop when done."];
			
			if (NSClassFromString(@"NSUserNotification"))
			{
				NSUserNotification *userNotification = [[NSUserNotification alloc] init];
				userNotification.title = @"Found Instruction";
				userNotification.subtitle = self.windowController.currentProcess.name;
				userNotification.informativeText = addedInstructionStatus;
				[[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:userNotification];
			}
		}
		else
		{
			NSLog(@"ERROR: Couldn't parse instruction before 0x%llX", [instructionAddress unsignedLongLongValue]);
		}
	}
}

- (void)requestVariableWatch:(ZGWatchPointType)watchPointType
{
	ZGVariable *variable = [[[self.windowController selectedVariables] objectAtIndex:0] copy];
	ZGBreakPoint *breakPoint = nil;
	
	if ([[[ZGAppController sharedController] breakPointController] addWatchpointOnVariable:variable inProcess:self.windowController.currentProcess watchPointType:watchPointType delegate:self getBreakPoint:&breakPoint])
	{
		self.variableInsertionIndex = 0;
		
		[self.windowController.searchController prepareTaskWithEscapeTitle:@"Stop"];
		[self.windowController.searchController.searchProgress clear];
		self.windowController.searchController.searchProgress.progressType = ZGSearchProgressMemoryWatching;
		
		self.windowController.generalStatusTextField.stringValue = [NSString stringWithFormat:@"Waiting until instruction %@ %@ (%lld byte%@)", watchPointType == ZGWatchPointWrite ? @"writes" : @"reads or writes", variable.addressStringValue, breakPoint.watchSize, breakPoint.watchSize != 1 ? @"s" : @""];
		
		self.windowController.searchingProgressIndicator.indeterminate = YES;
		[self.windowController.searchingProgressIndicator startAnimation:nil];
		
		self.watchProcess = self.windowController.currentProcess;
		
		if ([[NSProcessInfo processInfo] respondsToSelector:@selector(beginActivityWithOptions:reason:)])
		{
			self.watchActivity = [[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiated reason:@"Watching Data Accesses"];
		}
	}
	else
	{
		NSRunAlertPanel(
						@"Failed to Watch Variable",
						@"A watchpoint could not be added for this variable at this time.",
						@"OK", nil, nil);
	}
}

@end
