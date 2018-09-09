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

#import "ZGCodeInjectionWindowController.h"
#import "ZGProcess.h"
#import "ZGMemoryTypes.h"
#import "ZGVirtualMemory.h"
#import "ZGDebuggerUtilities.h"
#import "ZGInstruction.h"
#import "ZGVariable.h"
#import "ZGRunAlertPanel.h"
#import "ZGNullability.h"

@implementation ZGCodeInjectionWindowController
{
	IBOutlet NSTextView *_textView;
	NSString * _Nullable _suggestedCode;
	NSUndoManager * _Nullable _undoManager;
	ZGMemoryAddress _allocatedAddress;
	ZGMemorySize _numberOfAllocatedBytes;
	ZGProcess * _Nullable _process;
	NSArray<ZGInstruction *> *_instructions;
	NSArray<ZGBreakPoint *> *_breakPoints;
}

- (NSString *)windowNibName
{
	return @"Code Injection Window";
}

- (void)setSuggestedCode:(NSString *)suggestedCode
{
	_suggestedCode = [suggestedCode copy];
	[_textView.textStorage.mutableString setString:suggestedCode];
	[_textView.textStorage setForegroundColor:[NSColor textColor]];
}

- (void)updateSuggestedCode
{
	_suggestedCode = [_textView.textStorage.mutableString copy];
}

- (void)attachToWindow:(NSWindow *)parentWindow process:(ZGProcess *)process instruction:(ZGInstruction *)instruction breakPoints:(NSArray<ZGBreakPoint *> *)breakPoints undoManager:(NSUndoManager *)undoManager
{
	ZGMemoryAddress allocatedAddress = 0;
	ZGMemorySize numberOfAllocatedBytes = NSPageSize(); // sane default
	ZGPageSize(process.processTask, &numberOfAllocatedBytes);
	
	if (!ZGAllocateMemory(process.processTask, &allocatedAddress, numberOfAllocatedBytes))
	{
		NSLog(@"Failed to allocate code for code injection");
		ZGRunAlertPanelWithOKButton(ZGLocalizedStringFromDebuggerTable(@"failedAllocateMemoryForInjectingCodeAlertTitle"), ZGLocalizedStringFromDebuggerTable(@"failedAllocateMemoryForInjectingCodeAlertMessage"));
		return;
	}
	
	void *nopBuffer = malloc(numberOfAllocatedBytes);
	memset(nopBuffer, NOP_VALUE, numberOfAllocatedBytes);
	if (!ZGWriteBytesIgnoringProtection(process.processTask, allocatedAddress, nopBuffer, numberOfAllocatedBytes))
	{
		NSLog(@"Failed to nop allocated memory for code injection"); // not a fatal error
	}
	free(nopBuffer);
	
	NSArray<ZGInstruction *> *instructions = [ZGDebuggerUtilities instructionsBeforeHookingIntoAddress:instruction.variable.address injectingIntoDestination:allocatedAddress inProcess:process withBreakPoints:breakPoints];
	
	if (instructions == nil)
	{
		if (!ZGDeallocateMemory(process.processTask, allocatedAddress, numberOfAllocatedBytes))
		{
			NSLog(@"Error: Failed to deallocate VM memory after failing to fetch enough instructions..");
		}
		
		NSLog(@"Error: not enough instructions to override, or allocated memory address was too far away. Source: 0x%llX, destination: 0x%llX", instruction.variable.address, allocatedAddress);
		ZGRunAlertPanelWithOKButton(ZGLocalizedStringFromDebuggerTable(@"failedInjectCodeAlertTitle"), ZGLocalizedStringFromDebuggerTable(@"failedInjectCodeAlertMessage"));
		
		return;
	}
	
	NSMutableString *suggestedCode = [NSMutableString stringWithFormat:ZGLocalizedStringFromDebuggerTable(@"newlyCodeInjectedAtMessage"), allocatedAddress + INJECTED_NOP_SLIDE_LENGTH];
	
	for (ZGInstruction *suggestedInstruction in instructions)
	{
		NSMutableString *instructionText = [NSMutableString stringWithString:[suggestedInstruction text]];
		if (process.is64Bit && [instructionText rangeOfString:@"rip"].location != NSNotFound)
		{
			NSString *ripReplacement = nil;
			if (allocatedAddress > instruction.variable.address)
			{
				ripReplacement = [NSString stringWithFormat:@"rip-0x%llX", allocatedAddress + INJECTED_NOP_SLIDE_LENGTH + (suggestedInstruction.variable.address - instruction.variable.address) - suggestedInstruction.variable.address];
			}
			else
			{
				ripReplacement = [NSString stringWithFormat:@"rip+0x%llX", suggestedInstruction.variable.address + (suggestedInstruction.variable.address - instruction.variable.address) - allocatedAddress - INJECTED_NOP_SLIDE_LENGTH];
			}
			
			[instructionText replaceOccurrencesOfString:@"rip" withString:ripReplacement options:NSLiteralSearch range:NSMakeRange(0, instructionText.length)];
		}
		[suggestedCode appendString:instructionText];
		[suggestedCode appendString:@"\n"];
	}
	
	NSWindow *window = ZGUnwrapNullableObject([self window]); // Ensure window is loaded
	
	[self setSuggestedCode:suggestedCode];
	
	_undoManager = undoManager;
	_process = process;
	_allocatedAddress = allocatedAddress;
	_numberOfAllocatedBytes = numberOfAllocatedBytes;
	_instructions = instructions;
	_breakPoints = breakPoints;
	
	[parentWindow beginSheet:window completionHandler:^(NSModalResponse __unused returnCode) {
	}];
}

- (IBAction)injectCode:(id)__unused sender
{
	[self updateSuggestedCode];
	
	NSError *error = nil;
	NSData *injectedCode = [ZGDebuggerUtilities assembleInstructionText:ZGUnwrapNullableObject(_suggestedCode) atInstructionPointer:_allocatedAddress usingArchitectureBits:_process.pointerSize * 8 error:&error];
	
	if (injectedCode.length == 0 || error != nil || ![ZGDebuggerUtilities injectCode:injectedCode intoAddress:_allocatedAddress hookingIntoOriginalInstructions:_instructions process:ZGUnwrapNullableObject(_process) breakPoints:_breakPoints undoManager:_undoManager error:&error])
	{
		NSLog(@"Error while injecting code");
		NSLog(@"%@", error);
				
		ZGRunAlertPanelWithOKButton(ZGLocalizedStringFromDebuggerTable(@"failedInjectCodeAlertTitle"), [NSString stringWithFormat:@"%@: %@", ZGLocalizedStringFromDebuggerTable(@"failedAssemblingForInjectingCodeMessage"), [error.userInfo objectForKey:@"reason"]]);
	}
	else
	{
		NSWindow *window = ZGUnwrapNullableObject(self.window);
		[NSApp endSheet:window];
		[window close];
	}
}

- (IBAction)cancel:(id)__unused sender
{
	if (!ZGDeallocateMemory(_process.processTask, _allocatedAddress, _numberOfAllocatedBytes))
	{
		NSLog(@"Error: Failed to deallocate VM memory after canceling from injecting code..");
	}
	
	NSWindow *window = ZGUnwrapNullableObject(self.window);
	[NSApp endSheet:window];
	[window close];
}

@end
