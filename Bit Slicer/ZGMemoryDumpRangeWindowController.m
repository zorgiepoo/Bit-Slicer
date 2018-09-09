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

#import "ZGMemoryDumpRangeWindowController.h"
#import "ZGProcess.h"
#import "ZGCalculator.h"
#import "ZGMemoryTypes.h"
#import "ZGVirtualMemory.h"
#import "ZGMemoryAddressExpressionParsing.h"
#import "ZGRunAlertPanel.h"
#import "ZGNullability.h"

#define ZGLocalizedStringFromDumpMemoryRangeTable(string) NSLocalizedStringFromTable((string), @"[Code] Dump Memory Range", nil)

@implementation ZGMemoryDumpRangeWindowController
{
	ZGProcess * _Nullable _process;
	NSWindow * _Nullable _parentWindow;
	
	IBOutlet NSTextField *_fromAddressTextField;
	IBOutlet NSTextField *_toAddressTextField;
}

- (NSString *)windowNibName
{
	return @"Dump Memory Range Dialog";
}

- (IBAction)dumpMemory:(id)__unused sender
{
	NSString *fromAddressExpression = [ZGCalculator evaluateExpression:_fromAddressTextField.stringValue];
	ZGMemoryAddress fromAddress = ZGMemoryAddressFromExpression(fromAddressExpression);
	
	NSString *toAddressExpression = [ZGCalculator evaluateExpression:_toAddressTextField.stringValue];
	ZGMemoryAddress toAddress = ZGMemoryAddressFromExpression(toAddressExpression);
	
	if (toAddress > fromAddress && fromAddressExpression.length > 0 && toAddressExpression.length > 0)
	{
		NSWindow *window = ZGUnwrapNullableObject(self.window);
		[NSApp endSheet:window];
		[window close];
		
		ZGProcess *process = ZGUnwrapNullableObject(_process);
		
		NSSavePanel *savePanel = NSSavePanel.savePanel;
		savePanel.nameFieldStringValue = [process.name stringByAppendingFormat:@" 0x%llX - 0x%llX", fromAddress, toAddress];
		
		[savePanel
		 beginSheetModalForWindow:ZGUnwrapNullableObject(_parentWindow)
		 completionHandler:^(NSInteger result) {
		 	if (result == NSFileHandlingPanelOKButton)
		 	{
		 		BOOL success = NO;
		 		ZGMemorySize size = toAddress - fromAddress;
		 		void *bytes = NULL;

				if (ZGReadBytes(process.processTask, fromAddress, &bytes, &size))
		 		{
		 			NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)size];
					success = [data writeToURL:ZGUnwrapNullableObject(savePanel.URL) atomically:YES];

		 			ZGFreeBytes(bytes, size);
		 		}
		 		else
		 		{
		 			NSLog(@"Failed to read memory from %@ at 0x%llX (0x%llX bytes)", self->_process.name, fromAddress, size);
		 		}

		 		if (!success)
		 		{
		 			ZGRunAlertPanelWithOKButton(ZGLocalizedStringFromDumpMemoryRangeTable(@"failedDumpingMemoryAlertTitle"), [NSString stringWithFormat:ZGLocalizedStringFromDumpMemoryRangeTable(@"failedDumpingMemoryAlertMessageFormat"), fromAddress, toAddress]);
		 		}
		 	}
		}];
	}
	else
	{
		ZGRunAlertPanelWithOKButton(ZGLocalizedStringFromDumpMemoryRangeTable(@"invalidAddressRangeAlertTitle"), ZGLocalizedStringFromDumpMemoryRangeTable(@"invalidAddressRangeAlertMessage"));
	}
}

- (IBAction)cancel:(id)__unused sender
{
	NSWindow *window = ZGUnwrapNullableObject(self.window);
	[NSApp endSheet:window];
	[window close];
}

- (void)attachToWindow:(NSWindow *)parentWindow withProcess:(ZGProcess *)process requestedAddressRange:(HFRange)requestedAddressRange
{
	_process = process;
	_parentWindow = parentWindow;
	
	NSWindow *window = ZGUnwrapNullableObject([self window]); // ensure window is loaded
	
	_fromAddressTextField.stringValue = [NSString stringWithFormat:@"0x%llX", requestedAddressRange.location];
	_toAddressTextField.stringValue = [NSString stringWithFormat:@"0x%llX", requestedAddressRange.location + requestedAddressRange.length];
	
	[parentWindow beginSheet:window completionHandler:^(NSModalResponse __unused returnCode) {
	}];
}

@end
