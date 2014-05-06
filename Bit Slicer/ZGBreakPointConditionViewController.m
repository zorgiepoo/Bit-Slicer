/*
 * Created by Mayur Pawashe on 1/12/14.
 *
 * Copyright (c) 2014 zgcoder
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

@interface ZGBreakPointConditionViewController ()

@property (nonatomic, weak) id <ZGBreakPointConditionDelegate> delegate;

@property (nonatomic, assign) IBOutlet NSTextField *conditionTextField;

@end

@implementation ZGBreakPointConditionViewController

- (id)initWithDelegate:(id <ZGBreakPointConditionDelegate>)delegate
{
	self = [self initWithNibName:NSStringFromClass([self class]) bundle:nil];
    if (self != nil)
	{
		self.delegate = delegate;
    }
    return self;
}

- (void)updateConditionDisplay
{
	if (self.condition != nil)
	{
		[self.conditionTextField setStringValue:self.condition];
	}
}

- (void)setCondition:(NSString *)condition
{
	_condition = condition;
	[self updateConditionDisplay];
}

- (IBAction)changeCondition:(id)__unused sender
{
	[self.delegate breakPointCondition:[self.conditionTextField stringValue] didChangeAtAddress:self.targetAddress];
}

- (IBAction)cancel:(id)__unused sender
{
	[self.delegate breakPointConditionDidCancel];
}

#define BREAKPOINT_CONDITION_SCRIPTING @"https://github.com/zorgiepoo/Bit-Slicer/wiki/Setting-Breakpoints"
- (IBAction)showHelp:(id)__unused sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:BREAKPOINT_CONDITION_SCRIPTING]];
}

@end
