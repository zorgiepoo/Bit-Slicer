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
#import "ZGDocument.h"
#import "ZGVariableController.h"
#import "ZGAppController.h"
#import "ZGDocumentSearchController.h"
#import "ZGDocumentTableController.h"
#import "ZGDisassemblerController.h"
#import "ZGVariable.h"
#import "ZGProcess.h"
#import "ZGInstruction.h"
#import "ZGBreakPoint.h"

@interface ZGDocumentBreakPointController ()

@property (assign) IBOutlet ZGDocument *document;
@property (strong, nonatomic) ZGProcess *watchProcess;
@property (strong, nonatomic) NSMutableArray *foundInstructions;

@end

@implementation ZGDocumentBreakPointController

#pragma mark Birth & Death

- (id)init
{
	self = [super init];
	if (self)
	{
		[[NSNotificationCenter defaultCenter]
		 addObserver:self
		 selector:@selector(applicationWillTerminate:)
		 name:NSApplicationWillTerminateNotification
		 object:nil];
		
		self.foundInstructions = [[NSMutableArray alloc] init];
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

#pragma mark When to Stop? Stop?

- (void)stopWatchingBreakPoints
{
	if (self.watchProcess)
	{
		[[[ZGAppController sharedController] breakPointController] removeObserver:self];
		self.watchProcess = nil;
	}
}

- (void)cancelTask
{
	self.document.generalStatusTextField.stringValue = @"";
	
	[self.document.searchingProgressIndicator stopAnimation:nil];
	self.document.searchingProgressIndicator.indeterminate = NO;
	
	[self stopWatchingBreakPoints];
	
	self.document.currentProcess.isWatchingBreakPoint = NO;
	
	[self.document.searchController resumeFromTask];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (object == self.watchProcess)
	{
		NSNumber *newProcessID = [change objectForKey:NSKeyValueChangeNewKey];
		NSNumber *oldProcessID = [change objectForKey:NSKeyValueChangeOldKey];
		
		if (![newProcessID isEqualToNumber:oldProcessID])
		{
			[self cancelTask];
		}
	}
}

- (void)setWatchProcess:(ZGProcess *)watchProcess
{
	NSString *keyPath = @"processID";
	[self.watchProcess removeObserver:self forKeyPath:keyPath];
	
	_watchProcess = watchProcess;
	
	[self.watchProcess addObserver:self forKeyPath:keyPath options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew context:NULL];
}

#pragma mark Handling Break Points

- (void)breakPointDidHit:(NSNumber *)address
{
	ZGMemoryAddress breakPointAddress = [address unsignedLongLongValue];
	ZGInstruction *instruction = [[[ZGAppController sharedController] disassemblerController] findInstructionBeforeAddress:breakPointAddress inProcess:self.watchProcess];
	
	if (![self.foundInstructions containsObject:instruction])
	{
		[self.foundInstructions addObject:instruction];
		
		[self.document.variableController addVariables:@[instruction.variable] atRowIndexes:[NSIndexSet indexSetWithIndex:0]];
		[self.document.tableController.watchVariablesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
		[self.document.tableController.watchVariablesTableView scrollRowToVisible:0];
		[self.document.watchWindow makeFirstResponder:self.document.tableController.watchVariablesTableView];
		
		NSString *addedInstructionStatus = [NSString stringWithFormat:@"Added %@-byte instruction at %@...", instruction.variable.sizeStringValue, instruction.variable.addressStringValue];
		self.document.generalStatusTextField.stringValue = [addedInstructionStatus stringByAppendingString:@" Stop when done."];
		
		if (NSClassFromString(@"NSUserNotification"))
		{
			NSUserNotification *userNotification = [[NSUserNotification alloc] init];
			userNotification.title = @"Found Instruction";
			userNotification.subtitle = self.document.currentProcess.name;
			userNotification.informativeText = addedInstructionStatus;
			[[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:userNotification];
		}
	}
}

- (void)requestVariableWatch:(ZGWatchPointType)watchPointType
{
	ZGVariable *variable = [[[self.document selectedVariables] objectAtIndex:0] copy];
	ZGBreakPoint *breakPoint = nil;
	
	if ([[[ZGAppController sharedController] breakPointController] addWatchpointOnVariable:variable inProcess:self.document.currentProcess watchPointType:watchPointType delegate:self getBreakPoint:&breakPoint])
	{		
		[self.document.searchController prepareTaskWithEscapeTitle:@"Stop"];
		
		self.document.currentProcess.isWatchingBreakPoint = YES;
		
		self.document.generalStatusTextField.stringValue = [NSString stringWithFormat:@"Waiting until instruction %@ %@ (%lld byte%@)", watchPointType == ZGWatchPointWrite ? @"writes" : @"reads or writes", variable.addressStringValue, breakPoint.watchSize, breakPoint.watchSize != 1 ? @"s" : @""];
		
		self.document.searchingProgressIndicator.indeterminate = YES;
		[self.document.searchingProgressIndicator startAnimation:nil];
		
		self.watchProcess = self.document.currentProcess;
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
