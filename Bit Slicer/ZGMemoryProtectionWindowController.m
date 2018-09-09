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

#import "ZGMemoryProtectionWindowController.h"
#import "ZGProcess.h"
#import "ZGCalculator.h"
#import "ZGVirtualMemory.h"
#import "ZGRunAlertPanel.h"
#import "ZGMemoryAddressExpressionParsing.h"
#import "ZGMemoryTypes.h"
#import "ZGNullability.h"

#define ZGLocalizedStringFromMemoryProtectionTable(string) NSLocalizedStringFromTable((string), @"[Code] Memory Protection", nil)

@implementation ZGMemoryProtectionWindowController
{
	NSUndoManager * _Nullable _undoManager;
	ZGProcess * _Nullable _process;
	
	IBOutlet NSTextField *_addressTextField;
	IBOutlet NSTextField *_sizeTextField;
	
	IBOutlet NSButton *_readButton;
	IBOutlet NSButton *_writeButton;
	IBOutlet NSButton *_executeButton;
}

- (NSString *)windowNibName
{
	return @"Change Memory Protection Dialog";
}

- (BOOL)changeProtectionAtAddress:(ZGMemoryAddress)address size:(ZGMemorySize)size oldProtection:(ZGMemoryProtection)oldProtection newProtection:(ZGMemoryProtection)newProtection
{
	BOOL success = ZGProtect(_process.processTask, address, size, newProtection);
	
	if (!success)
	{
		ZGRunAlertPanelWithOKButton(
						ZGLocalizedStringFromMemoryProtectionTable(@"protectionChangeFailedAlertTitle"),
						ZGLocalizedStringFromMemoryProtectionTable(@"protectionChangeFailedAlertMessage"));
	}
	else
	{
		_undoManager.actionName = ZGLocalizedStringFromMemoryProtectionTable(@"undoProtectionChangeAction");
		[(ZGMemoryProtectionWindowController *)[_undoManager prepareWithInvocationTarget:self]
		 changeProtectionAtAddress:address size:size oldProtection:newProtection newProtection:oldProtection	];
	}
	
	return success;
}

- (IBAction)changeMemoryProtection:(id)__unused sender
{
	NSString *addressExpression = [ZGCalculator evaluateExpression:_addressTextField.stringValue];
	ZGMemoryAddress address = ZGMemoryAddressFromExpression(addressExpression);
	
	NSString *sizeExpression = [ZGCalculator evaluateExpression:_sizeTextField.stringValue];
	ZGMemorySize size = (ZGMemorySize)ZGMemoryAddressFromExpression(sizeExpression);
	
	if (size > 0 && addressExpression.length > 0 && sizeExpression.length > 0)
	{
		// First check if we can find the memory region the address resides in
		ZGMemoryAddress memoryAddress = address;
		ZGMemorySize memorySize = size;
		ZGMemoryProtection oldProtection;
		if (!ZGMemoryProtectionInRegion(_process.processTask, &memoryAddress, &memorySize, &oldProtection))
		{
			ZGRunAlertPanelWithOKButton(
							ZGLocalizedStringFromMemoryProtectionTable(@"protectionChangeFailedAlertTitle"),
							ZGLocalizedStringFromMemoryProtectionTable(@"findMemoryRegionFailedAlertMessage"));
		}
		else
		{
			ZGMemoryProtection protection = VM_PROT_NONE;
			
			if (_readButton.state == NSOnState)
			{
				protection |= VM_PROT_READ;
			}
			
			if (_writeButton.state == NSOnState)
			{
				protection |= VM_PROT_WRITE;
			}
			
			if (_executeButton.state == NSOnState)
			{
				protection |= VM_PROT_EXECUTE;
			}
			
			if ([self changeProtectionAtAddress:address size:size oldProtection:oldProtection newProtection:protection])
			{
				NSWindow *window = ZGUnwrapNullableObject(self.window);
				[NSApp endSheet:window];
				[window close];
			}
		}
	}
	else
	{
		ZGRunAlertPanelWithOKButton(
						ZGLocalizedStringFromMemoryProtectionTable(@"invalidAddressRangeAlertTitle"),
						ZGLocalizedStringFromMemoryProtectionTable(@"invalidAddressRangeAlertMessage"));
	}
}

- (IBAction)cancelMemoryProtectionChange:(id)__unused sender
{
	NSWindow *window = ZGUnwrapNullableObject(self.window);
	[NSApp endSheet:window];
	[window close];
}

- (void)attachToWindow:(NSWindow *)parentWindow withProcess:(ZGProcess *)process requestedAddressRange:(HFRange)requestedAddressRange undoManager:(NSUndoManager *)undoManager
{
	_process = process;
	_undoManager = undoManager;
	
	NSWindow *window = ZGUnwrapNullableObject([self window]); // ensure window is loaded
	
	if (requestedAddressRange.length > 0)
	{
		_addressTextField.stringValue = [NSString stringWithFormat:@"0x%llX", requestedAddressRange.location];
		_sizeTextField.stringValue = [NSString stringWithFormat:@"%llu", requestedAddressRange.length];
		
		ZGMemoryProtection memoryProtection;
		ZGMemoryAddress memoryAddress = requestedAddressRange.location;
		ZGMemorySize memorySize;
		
		// Tell the user what the current memory protection is set as
		if (ZGMemoryProtectionInRegion(_process.processTask, &memoryAddress, &memorySize, &memoryProtection) &&
            memoryAddress <= requestedAddressRange.location && memoryAddress + memorySize >= requestedAddressRange.location + requestedAddressRange.length)
		{
			_readButton.state = memoryProtection & VM_PROT_READ;
			_writeButton.state = memoryProtection & VM_PROT_WRITE;
			_executeButton.state = memoryProtection & VM_PROT_EXECUTE;
		}
		else
		{
			// Turn everything off if we couldn't find the current memory protection
			_readButton.state = NSOffState;
			_writeButton.state = NSOffState;
			_executeButton.state = NSOffState;
		}
	}
	
	[parentWindow beginSheet:window completionHandler:^(NSModalResponse __unused returnCode) {
	}];
}

@end
