/*
 * This file is part of Bit Slicer.
 *
 * Bit Slicer is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 
 * Bit Slicer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 
 * You should have received a copy of the GNU General Public License
 * along with Bit Slicer.  If not, see <http://www.gnu.org/licenses/>.
 * 
 * Created by Mayur Pawashe on 7/19/12.
 * Copyright 2012 zgcoder. All rights reserved.
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
		ZGMemorySize memorySize;
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
