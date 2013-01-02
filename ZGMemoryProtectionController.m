/*
 * Created by Mayur Pawashe on 7/19/12.
 *
 * Copyright (c) 2012 zgcoder
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

#import "ZGMemoryProtectionController.h"
#import "ZGDocument.h"
#import "ZGProcess.h"
#import "ZGCalculator.h"
#import "ZGVirtualMemory.h"
#import "ZGUtilities.h"
#import "ZGMemoryTypes.h"

@interface ZGMemoryProtectionController ()

@property (assign) IBOutlet ZGDocument *document;
@property (assign) IBOutlet NSWindow *changeProtectionWindow;
@property (assign) IBOutlet NSTextField *changeProtectionAddressTextField;
@property (assign) IBOutlet NSTextField *changeProtectionSizeTextField;
@property (assign) IBOutlet NSButton *changeProtectionReadButton;
@property (assign) IBOutlet NSButton *changeProtectionWriteButton;
@property (assign) IBOutlet NSButton *changeProtectionExecuteButton;

@end

@implementation ZGMemoryProtectionController

#pragma mark Memory Protection

- (IBAction)changeProtectionOkayButton:(id)sender
{
	NSString *addressExpression = [ZGCalculator evaluateExpression:self.changeProtectionAddressTextField.stringValue];
	ZGMemoryAddress address = memoryAddressFromExpression(addressExpression);
	
	NSString *sizeExpression = [ZGCalculator evaluateExpression:self.changeProtectionSizeTextField.stringValue];
	ZGMemorySize size = (ZGMemorySize)memoryAddressFromExpression(sizeExpression);
	
	if (size > 0 && ![addressExpression isEqualToString:@""] && ![sizeExpression isEqualToString:@""])
	{
		// First check if we can find the memory region the address resides in
		ZGMemoryAddress memoryAddress = address;
		ZGMemorySize memorySize = size;
		ZGMemoryProtection memoryProtection;
		if (!ZGMemoryProtectionInRegion(self.document.currentProcess.processTask, &memoryAddress, &memorySize, &memoryProtection))
		{
			NSRunAlertPanel(
							@"Memory Protection Change Failed",
							@"The specified memory address could not be located within a memory region.",
							@"OK", nil, nil);
		}
		else
		{
			ZGMemoryProtection protection = VM_PROT_NONE;
			
			if (self.changeProtectionReadButton.state == NSOnState)
			{
				protection |= VM_PROT_READ;
			}
			
			if (self.changeProtectionWriteButton.state == NSOnState)
			{
				protection |= VM_PROT_WRITE;
			}
			
			if (self.changeProtectionExecuteButton.state == NSOnState)
			{
				protection |= VM_PROT_EXECUTE;
			}
			
			if (!ZGProtect(self.document.currentProcess.processTask, address, size, protection))
			{
				NSRunAlertPanel(
								@"Memory Protection Change Failed",
								@"The memory's protection could not be changed to the specified permissions.",
								@"OK", nil, nil);
			}
			else
			{
				[NSApp endSheet:self.changeProtectionWindow];
				[self.changeProtectionWindow close];
			} 
		}
	}
	else
	{
		NSRunAlertPanel(
						@"Invalid range",
						@"Please make sure you typed in the addresses correctly.",
						@"OK", nil, nil);
	}
}

- (IBAction)changeProtectionCancelButton:(id)sender
{
	[NSApp endSheet:self.changeProtectionWindow];
	[self.changeProtectionWindow close];
}

- (void)changeMemoryProtectionRequest
{
	// guess what the user may want based on the selected variables
	NSArray *selectedVariables = self.document.selectedVariables;
	if (selectedVariables)
	{
		ZGVariable *firstVariable = [selectedVariables objectAtIndex:0];
		
		self.changeProtectionAddressTextField.stringValue = firstVariable.addressStringValue;
		self.changeProtectionSizeTextField.stringValue = [NSString stringWithFormat:@"%lld", firstVariable.size];
		
		ZGMemoryProtection memoryProtection;
		ZGMemoryAddress memoryAddress = firstVariable.address;
		ZGMemorySize memorySize;
		
		// Tell the user what the current memory protection is set as for the variable
		if (ZGMemoryProtectionInRegion(self.document.currentProcess.processTask, &memoryAddress, &memorySize, &memoryProtection) &&
            memoryAddress <= firstVariable.address && memoryAddress + memorySize >= firstVariable.address + firstVariable.size)
		{
			self.changeProtectionReadButton.state = memoryProtection & VM_PROT_READ;
			self.changeProtectionWriteButton.state = memoryProtection & VM_PROT_WRITE;
			self.changeProtectionExecuteButton.state = memoryProtection & VM_PROT_EXECUTE;
		}
		else
		{
			// Turn everything off if we couldn't find the current memory protection
			self.changeProtectionReadButton.state = NSOffState;
			self.changeProtectionWriteButton.state = NSOffState;
			self.changeProtectionExecuteButton.state = NSOffState;
		}
	}
	
	[NSApp
	 beginSheet:self.changeProtectionWindow
	 modalForWindow:self.document.watchWindow
	 modalDelegate:self
	 didEndSelector:nil
	 contextInfo:NULL];
}

@end
