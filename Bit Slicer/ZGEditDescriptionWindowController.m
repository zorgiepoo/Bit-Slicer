/*
 * Copyright (c) 2013 Mayur Pawashe
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

#import "ZGEditDescriptionWindowController.h"
#import "ZGVariableController.h"
#import "ZGNullability.h"

@implementation ZGEditDescriptionWindowController
{
	ZGVariableController * _Nonnull _variableController;
	ZGVariable * _Nullable _variable;
	
	IBOutlet NSTextView *_descriptionTextView;
}

- (NSString *)windowNibName
{
	return @"Edit Description Dialog";
}

- (id)initWithVariableController:(ZGVariableController *)variableController
{
	self = [super init];
	if (self != nil)
	{
		_variableController = variableController;
	}
	return self;
}

- (void)requestEditingDescriptionFromVariable:(ZGVariable *)variable attachedToWindow:(NSWindow *)parentWindow
{
	NSWindow *window = ZGUnwrapNullableObject([self window]); // ensure window is loaded
	
	[_descriptionTextView.textStorage setAttributedString:variable.fullAttributedDescription];
	[_descriptionTextView scrollRangeToVisible:NSMakeRange(0, 0)];
	_variable = variable;
	
	[parentWindow beginSheet:window completionHandler:^(NSModalResponse __unused returnCode) {
	}];
}

- (IBAction)editVariableDescription:(id)__unused sender
{
	NSAttributedString *newDescription = [_descriptionTextView.textStorage copy];
	if (newDescription != nil)
	{
		[_variableController changeVariable:ZGUnwrapNullableObject(_variable) newDescription:newDescription];
		
		NSWindow *window = ZGUnwrapNullableObject([self window]);
		[NSApp endSheet:window];
		[window close];
	}
}

- (IBAction)cancelEditingVariableDescription:(id)__unused sender
{
	NSWindow *window = ZGUnwrapNullableObject([self window]);
	[NSApp endSheet:window];
	[window close];
}

// Make this controller the only one that can use the font and color panels, since nobody else needs it

- (IBAction)zgOrderFrontFontPanel:(id)sender
{
	[[NSFontManager sharedFontManager] orderFrontFontPanel:sender];
}

- (IBAction)zgOrderFrontColorPanel:(id)__unused sender
{
	[[NSColorPanel sharedColorPanel] orderFront:nil];
}

@end
