/*
 * Copyright (c) 2014 Mayur Pawashe
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

#import "ZGScriptPromptWindowController.h"
#import "ZGScriptPrompt.h"
#import "ZGNullability.h"

@implementation ZGScriptPromptWindowController
{
	IBOutlet NSTextField *_messageTextField;
	IBOutlet NSTextField *_answerTextField;
}
 
- (NSString *)windowNibName
{
	return @"Script Prompt Dialog";
}

- (void)attachToWindow:(NSWindow *)parentWindow withScriptPrompt:(ZGScriptPrompt *)scriptPrompt delegate:(id <ZGScriptPromptDelegate>)delegate
{
	// Must load the window before setting text field values
	NSWindow *window = ZGUnwrapNullableObject([self window]);
	
	_messageTextField.stringValue = scriptPrompt.message;
	_answerTextField.stringValue = scriptPrompt.answer;
	
	[_answerTextField selectText:nil];
	
	[parentWindow beginSheet:window completionHandler:^(NSModalResponse __unused returnCode) {
	}];
	
	_scriptPrompt = scriptPrompt;
	_isAttached = YES;
	
	_delegate = delegate;
}

- (void)terminateSessionWithAnswer:(NSString *)answer
{
	id <ZGScriptPromptDelegate> delegate = _delegate;
	[delegate scriptPrompt:_scriptPrompt didReceiveAnswer:answer];
	[self terminateSession];
}

- (void)terminateSession
{
	if (_isAttached)
	{
		[NSApp endSheet:ZGUnwrapNullableObject(self.window)];
		[self.window close];
		
		_isAttached = NO;
		_delegate = nil;
	}
}

- (IBAction)hitDefaultButton:(id)__unused sender
{
	[self terminateSessionWithAnswer:_answerTextField.stringValue];
}

- (IBAction)hitAlternativeButton:(id)__unused sender
{
	[self terminateSessionWithAnswer:nil];
}

@end
