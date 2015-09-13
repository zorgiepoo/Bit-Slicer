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

#import "ZGBreakPointConditionViewController.h"
#import "ZGNullability.h"

@implementation ZGBreakPointConditionViewController
{
	__weak id <ZGBreakPointConditionDelegate> _Nullable _delegate;
	
	IBOutlet NSTextField *_conditionTextField;
}

- (id)initWithDelegate:(id <ZGBreakPointConditionDelegate>)delegate
{
	self = [self initWithNibName:@"Breakpoint Condition View" bundle:nil];
    if (self != nil)
	{
		_delegate = delegate;
    }
    return self;
}

- (void)updateConditionDisplay
{
	if (_condition != nil)
	{
		[_conditionTextField setStringValue:(NSString * _Nonnull)_condition];
	}
}

- (void)setCondition:(NSString *)condition
{
	_condition = condition;
	[self updateConditionDisplay];
}

- (IBAction)changeCondition:(id)__unused sender
{
	id <ZGBreakPointConditionDelegate> delegate = _delegate;
	[delegate breakPointCondition:_conditionTextField.stringValue didChangeAtAddress:_targetAddress];
}

- (IBAction)cancel:(id)__unused sender
{
	id <ZGBreakPointConditionDelegate> delegate = _delegate;
	[delegate breakPointConditionDidCancel];
}

#define BREAKPOINT_CONDITION_SCRIPTING @"https://github.com/zorgiepoo/Bit-Slicer/wiki/Setting-Breakpoints"
- (IBAction)showHelp:(id)__unused sender
{
	[[NSWorkspace sharedWorkspace] openURL:ZGUnwrapNullableObject([NSURL URLWithString:BREAKPOINT_CONDITION_SCRIPTING])];
}

@end
