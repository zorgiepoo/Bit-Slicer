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

#import "ZGEditSizeWindowController.h"
#import "ZGVariableController.h"
#import "ZGCalculator.h"
#import "NSStringAdditions.h"
#import "ZGMemoryAddressExpressionParsing.h"
#import "ZGRunAlertPanel.h"
#import "ZGNullability.h"

#define ZGEditSizeLocalizableTable @"[Code] Edit Variable Size"

@implementation ZGEditSizeWindowController
{
	ZGVariableController * _Nonnull _variableController;
	NSArray<ZGVariable *> * _Nullable _variables;
	
	IBOutlet NSTextField *_sizeTextField;
}

- (NSString *)windowNibName
{
	return @"Edit Size Dialog";
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

- (void)requestEditingSizesFromVariables:(NSArray<ZGVariable *> *)variables attachedToWindow:(NSWindow *)parentWindow
{
	NSWindow *window = ZGUnwrapNullableObject([self window]); // ensure window is loaded
	
	ZGVariable *firstVariable = [variables objectAtIndex:0];
	_sizeTextField.stringValue = firstVariable.sizeStringValue;
	
	[_sizeTextField selectText:nil];
	
	_variables = variables;
	
	[parentWindow beginSheet:window completionHandler:^(NSModalResponse __unused returnCode) {
	}];
}

- (IBAction)editVariablesSizes:(id)__unused sender
{
	NSString *sizeExpression = [ZGCalculator evaluateExpression:_sizeTextField.stringValue];
	
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
		ZGRunAlertPanelWithOKButton(NSLocalizedStringFromTable(@"invalidSizeAlertTitle", ZGEditSizeLocalizableTable, nil), NSLocalizedStringFromTable(@"invalidSizeAlertMessage", ZGEditSizeLocalizableTable, nil));
	}
	else if (requestedSize <= 0)
	{
		ZGRunAlertPanelWithOKButton(NSLocalizedStringFromTable(@"sizeIsTooSmallAlertTitle", ZGEditSizeLocalizableTable, nil), NSLocalizedStringFromTable(@"sizeIsTooSmallAlertMessage", ZGEditSizeLocalizableTable, nil));
	}
	else
	{
		NSWindow *window = ZGUnwrapNullableObject(self.window);
		[NSApp endSheet:window];
		[window close];
		
		NSMutableArray<NSNumber *> *requestedSizes = [[NSMutableArray alloc] init];
		
		NSUInteger variableIndex;
		for (variableIndex = 0; variableIndex < _variables.count; variableIndex++)
		{
			[requestedSizes addObject:@(requestedSize)];
		}
		
		[_variableController editVariables:ZGUnwrapNullableObject(_variables) requestedSizes:requestedSizes];
		
		_variables = nil;
	}
}

- (IBAction)cancelEditingVariablesSizes:(id)__unused sender
{
	NSWindow *window = ZGUnwrapNullableObject(self.window);
	[NSApp endSheet:window];
	[window close];
	
	_variables = nil;
}

@end
