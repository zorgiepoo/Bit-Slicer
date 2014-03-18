/*
 * Created by Mayur Pawashe on 12/21/13.
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

#import "ZGDocumentOptionsViewController.h"
#import "ZGDocument.h"
#import "ZGDocumentData.h"
#import "ZGVariable.h"

@interface ZGDocumentOptionsViewController ()

@property (nonatomic, assign) ZGDocument *document;
@property (nonatomic, assign) IBOutlet NSButton *ignoreDataAlignmentCheckbox;
@property (nonatomic, assign) IBOutlet NSTextField *beginningAddressTextField;
@property (nonatomic, assign) IBOutlet NSTextField *endingAddressTextField;

@end

@implementation ZGDocumentOptionsViewController

- (id)initWithDocument:(ZGDocument *)document
{
	self = [self initWithNibName:NSStringFromClass([self class]) bundle:nil];
	if (self != nil)
	{
		self.document = document;
	}
	return self;
}

- (void)reloadInterface
{
	[self.ignoreDataAlignmentCheckbox setState:self.document.data.ignoreDataAlignment];
	self.beginningAddressTextField.stringValue = self.document.data.beginningAddressStringValue;
	self.endingAddressTextField.stringValue = self.document.data.endingAddressStringValue;
}

- (void)loadView
{
	[super loadView];
	
	[self reloadInterface];
}

- (IBAction)changeIgnoreDataAlignment:(id)sender
{
	self.document.data.ignoreDataAlignment = ([(NSCell *)sender state] == NSOnState);
	[self.document markChange];
}

- (IBAction)changeBeginningAddress:(id)__unused sender
{
	if (![self.document.data.beginningAddressStringValue isEqualToString:self.beginningAddressTextField.stringValue])
	{
		self.document.data.beginningAddressStringValue = self.beginningAddressTextField.stringValue;
		[self.document markChange];
	}
}

- (IBAction)changeEndingAddress:(id)__unused sender
{
	if (![self.document.data.endingAddressStringValue isEqualToString:self.endingAddressTextField.stringValue])
	{
		self.document.data.endingAddressStringValue = self.endingAddressTextField.stringValue;
		[self.document markChange];
	}
}

@end
