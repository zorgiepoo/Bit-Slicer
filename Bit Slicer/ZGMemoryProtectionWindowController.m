/*
 * Created by Mayur Pawashe on 4/5/14.
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

#import "ZGMemoryProtectionWindowController.h"
#import "ZGProcess.h"
#import "ZGCalculator.h"
#import "ZGVirtualMemory.h"
#import "ZGUtilities.h"
#import "ZGMemoryTypes.h"

@interface ZGMemoryProtectionWindowController ()

@property (nonatomic, assign) IBOutlet NSTextField *addressTextField;
@property (nonatomic, assign) IBOutlet NSTextField *sizeTextField;

@property (nonatomic, assign) IBOutlet NSButton *readButton;
@property (nonatomic, assign) IBOutlet NSButton *writeButton;
@property (nonatomic, assign) IBOutlet NSButton *executeButton;

@property (nonatomic) NSUndoManager *undoManager;
@property (nonatomic) ZGProcess *process;

@end

@implementation ZGMemoryProtectionWindowController

- (NSString *)windowNibName
{
	return NSStringFromClass([self class]);
}

- (BOOL)changeProtectionAtAddress:(ZGMemoryAddress)address size:(ZGMemorySize)size oldProtection:(ZGMemoryProtection)oldProtection newProtection:(ZGMemoryProtection)newProtection
{
	BOOL success = ZGProtect(self.process.processTask, address, size, newProtection);
	
	if (!success)
	{
		NSRunAlertPanel(
						@"Memory Protection Change Failed",
						@"The memory's protection could not be changed to the specified permissions.",
						@"OK", nil, nil);
	}
	else
	{
		self.undoManager.actionName = @"Protection Change";
		[[self.undoManager prepareWithInvocationTarget:self]
		 changeProtectionAtAddress:address size:size oldProtection:newProtection newProtection:oldProtection	];
	}
	
	return success;
}

- (IBAction)changeMemoryProtection:(id)__unused sender
{
	NSString *addressExpression = [ZGCalculator evaluateExpression:self.addressTextField.stringValue];
	ZGMemoryAddress address = ZGMemoryAddressFromExpression(addressExpression);
	
	NSString *sizeExpression = [ZGCalculator evaluateExpression:self.sizeTextField.stringValue];
	ZGMemorySize size = (ZGMemorySize)ZGMemoryAddressFromExpression(sizeExpression);
	
	if (size > 0 && addressExpression.length > 0 && sizeExpression.length > 0)
	{
		// First check if we can find the memory region the address resides in
		ZGMemoryAddress memoryAddress = address;
		ZGMemorySize memorySize = size;
		ZGMemoryProtection oldProtection;
		if (!ZGMemoryProtectionInRegion(self.process.processTask, &memoryAddress, &memorySize, &oldProtection))
		{
			NSRunAlertPanel(
							@"Memory Protection Change Failed",
							@"The specified memory address could not be located within a memory region.",
							@"OK", nil, nil);
		}
		else
		{
			ZGMemoryProtection protection = VM_PROT_NONE;
			
			if (self.readButton.state == NSOnState)
			{
				protection |= VM_PROT_READ;
			}
			
			if (self.writeButton.state == NSOnState)
			{
				protection |= VM_PROT_WRITE;
			}
			
			if (self.executeButton.state == NSOnState)
			{
				protection |= VM_PROT_EXECUTE;
			}
			
			if ([self changeProtectionAtAddress:address size:size oldProtection:oldProtection newProtection:protection])
			{
				[NSApp endSheet:self.window];
				[self.window close];
			}
		}
	}
	else
	{
		NSRunAlertPanel(
						@"Invalid Range",
						@"Please make sure you typed in the addresses correctly.",
						@"OK", nil, nil);
	}
}

- (IBAction)cancelMemoryProtectionChange:(id)__unused sender
{
	[NSApp endSheet:self.window];
	[self.window close];
}

- (void)attachToWindow:(NSWindow *)parentWindow withProcess:(ZGProcess *)process requestedAddressRange:(HFRange)requestedAddressRange undoManager:(NSUndoManager *)undoManager
{
	self.process = process;
	self.undoManager = undoManager;
	
	[self window]; // ensure window is loaded
	
	if (requestedAddressRange.length > 0)
	{
		self.addressTextField.stringValue = [NSString stringWithFormat:@"0x%llX", requestedAddressRange.location];
		self.sizeTextField.stringValue = [NSString stringWithFormat:@"%llu", requestedAddressRange.length];
		
		ZGMemoryProtection memoryProtection;
		ZGMemoryAddress memoryAddress = requestedAddressRange.location;
		ZGMemorySize memorySize;
		
		// Tell the user what the current memory protection is set as
		if (ZGMemoryProtectionInRegion(self.process.processTask, &memoryAddress, &memorySize, &memoryProtection) &&
            memoryAddress <= requestedAddressRange.location && memoryAddress + memorySize >= requestedAddressRange.location + requestedAddressRange.length)
		{
			self.readButton.state = memoryProtection & VM_PROT_READ;
			self.writeButton.state = memoryProtection & VM_PROT_WRITE;
			self.executeButton.state = memoryProtection & VM_PROT_EXECUTE;
		}
		else
		{
			// Turn everything off if we couldn't find the current memory protection
			self.readButton.state = NSOffState;
			self.writeButton.state = NSOffState;
			self.executeButton.state = NSOffState;
		}
	}
	
	[NSApp
	 beginSheet:self.window
	 modalForWindow:parentWindow
	 modalDelegate:self
	 didEndSelector:nil
	 contextInfo:NULL];
}

@end
