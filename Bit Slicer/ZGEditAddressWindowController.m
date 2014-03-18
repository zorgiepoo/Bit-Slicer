/*
 * Created by Mayur Pawashe on 11/29/13.
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

#import "ZGEditAddressWindowController.h"
#import "ZGVariableController.h"
#import "ZGVariable.h"

@interface ZGEditAddressWindowController ()

@property (nonatomic) ZGVariableController *variableController;

@property (nonatomic, assign) IBOutlet NSTextField *addressTextField;
@property (nonatomic) ZGVariable *variable;

@end

@implementation ZGEditAddressWindowController

- (NSString *)windowNibName
{
	return NSStringFromClass([self class]);
}

- (id)initWithVariableController:(ZGVariableController *)variableController
{
	self = [super init];
	if (self != nil)
	{
		self.variableController = variableController;
	}
	return self;
}

- (void)requestEditingAddressFromVariable:(ZGVariable *)variable attachedToWindow:(NSWindow *)parentWindow
{
	[self window]; // ensure window is loaded
	
	self.variable = variable;
	self.addressTextField.stringValue = variable.addressFormula;
	
	[self.addressTextField selectText:nil];
	
	[NSApp
	 beginSheet:self.window
	 modalForWindow:parentWindow
	 modalDelegate:self
	 didEndSelector:nil
	 contextInfo:NULL];
}

- (IBAction)editAddress:(id)__unused sender
{
	[NSApp endSheet:self.window];
	[self.window close];
	
	[self.variableController
	 editVariable:self.variable
	 addressFormula:self.addressTextField.stringValue];
	
	self.variable = nil;
}

- (IBAction)cancelEditingAddress:(id)__unused sender
{
	[NSApp endSheet:self.window];
	[self.window close];
	
	self.variable = nil;
}

@end
