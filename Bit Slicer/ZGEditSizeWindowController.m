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

#import "ZGEditSizeWindowController.h"
#import "ZGVariableController.h"
#import "ZGCalculator.h"
#import "NSStringAdditions.h"
#import "ZGUtilities.h"

@interface ZGEditSizeWindowController ()

@property (nonatomic) ZGVariableController *variableController;
@property (nonatomic) NSArray *variables;

@property (nonatomic, assign) IBOutlet NSTextField *sizeTextField;

@end

@implementation ZGEditSizeWindowController

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

- (void)requestEditingSizesFromVariables:(NSArray *)variables attachedToWindow:(NSWindow *)parentWindow
{
	[self window]; // ensure window is loaded
	
	ZGVariable *firstVariable = [variables objectAtIndex:0];
	self.sizeTextField.stringValue = firstVariable.sizeStringValue;
	
	[self.sizeTextField selectText:nil];
	
	self.variables = variables;
	
	[NSApp
	 beginSheet:self.window
	 modalForWindow:parentWindow
	 modalDelegate:self
	 didEndSelector:nil
	 contextInfo:NULL];
}

- (IBAction)editVariablesSizes:(id)__unused sender
{
	NSString *sizeExpression = [ZGCalculator evaluateExpression:self.sizeTextField.stringValue];
	
	ZGMemorySize requestedSize = 0;
	if (sizeExpression.zgIsHexRepresentation)
	{
		[[NSScanner scannerWithString:sizeExpression] scanHexLongLong:&requestedSize];
	}
	else
	{
		requestedSize = sizeExpression.zgUnsignedLongLongValue;
	}
	
	if (!ZGIsValidNumber(sizeExpression))
	{
		NSRunAlertPanel(@"Invalid size", @"The size you have supplied is not valid.", nil, nil, nil);
	}
	else if (requestedSize <= 0)
	{
		NSRunAlertPanel(@"Failed to edit size", @"The size must be greater than 0.", nil, nil, nil);
	}
	else
	{
		[NSApp endSheet:self.window];
		[self.window close];
		
		NSMutableArray *requestedSizes = [[NSMutableArray alloc] init];
		
		NSUInteger variableIndex;
		for (variableIndex = 0; variableIndex < self.variables.count; variableIndex++)
		{
			[requestedSizes addObject:@(requestedSize)];
		}
		
		[self.variableController
		 editVariables:self.variables
		 requestedSizes:requestedSizes];
		
		self.variables = nil;
	}
}

- (IBAction)cancelEditingVariablesSizes:(id)__unused sender
{
	[NSApp endSheet:self.window];
	[self.window close];
	
	self.variables = nil;
}

@end
