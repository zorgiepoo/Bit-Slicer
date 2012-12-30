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
#import "ZGBreakPointController.h"
#import "ZGAppController.h"
#import "ZGDocumentSearchController.h"
#import "ZGDissemblerController.h"
#import "ZGVariable.h"
#import "ZGProcess.h"

@interface ZGDocumentBreakPointController ()

@property (assign) IBOutlet ZGDocument *document;
@property (strong, nonatomic) ZGVariable *breakPointVariable;

@end

@implementation ZGDocumentBreakPointController

- (void)dealloc
{
	// TODO, remove delegate breakpoints
}

- (void)cancelTask
{
	self.document.generalStatusTextField.stringValue = @"";
	
	[self.document.searchingProgressIndicator stopAnimation:nil];
	self.document.searchingProgressIndicator.indeterminate = NO;
	
	self.document.currentProcess.isWatchingBreakPoint = NO;
	
	[self.document.searchController resumeFromTask];
}

- (void)breakPointDidHit:(NSNumber *)address
{
	ZGMemoryAddress memoryAddress = [address unsignedLongLongValue];
	
	self.document.generalStatusTextField.stringValue = [NSString stringWithFormat:@"Decoding instruction..."];
	
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		ZGMemoryAddress instructionAddress = [[[ZGAppController sharedController] dissemblerController] findInstructionAddressFromBreakPointAddress:memoryAddress inProcess:self.document.currentProcess];
		
		dispatch_async(dispatch_get_main_queue(), ^{
			NSLog(@"Instruction address is 0x%llX", instructionAddress);
			[self cancelTask];
		});
	});
}

- (void)requestVariableWatch
{
	ZGVariable *variable = [[self.document selectedVariables] objectAtIndex:0];
	
	if ([[[ZGAppController sharedController] breakPointController] addWatchpointOnVariable:variable inProcess:self.document.currentProcess delegate:self])
	{
		self.breakPointVariable = variable;
		
		[self.document.searchController prepareTask];
		
		self.document.currentProcess.isWatchingBreakPoint = YES;
		
		self.document.generalStatusTextField.stringValue = [NSString stringWithFormat:@"Waiting until %@ (%lld bytes) is hit...", [variable addressStringValue], variable.size];
		self.document.searchingProgressIndicator.indeterminate = YES;
		[self.document.searchingProgressIndicator startAnimation:nil];
	}
}

@end
