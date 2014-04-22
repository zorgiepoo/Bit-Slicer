/*
 * Created by Mayur Pawashe on 8/19/13.
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

#import "ZGCodeInjectionWindowController.h"
#import "ZGProcess.h"
#import "ZGMemoryTypes.h"
#import "ZGVirtualMemory.h"
#import "ZGDebuggerUtilities.h"
#import "ZGInstruction.h"
#import "ZGVariable.h"

@interface ZGCodeInjectionWindowController ()

@property (assign, nonatomic) IBOutlet NSTextView *textView;
@property (nonatomic, copy) NSString *suggestedCode;
@property (nonatomic) NSUndoManager *undoManager;
@property (nonatomic) ZGMemoryAddress allocatedAddress;
@property (nonatomic) ZGMemorySize numberOfAllocatedBytes;
@property (nonatomic) ZGProcess *process;
@property (nonatomic) NSArray *instructions;
@property (nonatomic) NSArray *breakPoints;

@end

@implementation ZGCodeInjectionWindowController

- (NSString *)windowNibName
{
	return NSStringFromClass([self class]);
}

- (void)setSuggestedCode:(NSString *)suggestedCode
{
	_suggestedCode = [suggestedCode copy];
	[self.textView.textStorage.mutableString setString:_suggestedCode];
}

- (void)updateSuggestedCode
{
	_suggestedCode = [self.textView.textStorage.mutableString copy];
}

- (void)attachToWindow:(NSWindow *)parentWindow process:(ZGProcess *)process instruction:(ZGInstruction *)instruction breakPoints:(NSArray *)breakPoints undoManager:(NSUndoManager *)undoManager
{
	ZGMemoryAddress allocatedAddress = 0;
	ZGMemorySize numberOfAllocatedBytes = NSPageSize(); // sane default
	ZGPageSize(process.processTask, &numberOfAllocatedBytes);
	
	if (!ZGAllocateMemory(process.processTask, &allocatedAddress, numberOfAllocatedBytes))
	{
		NSLog(@"Failed to allocate code for code injection");
		NSRunAlertPanel(@"Failed to Allocate Memory", @"An error occured trying to allocate new memory into the process", @"OK", nil, nil);
		return;
	}
	
	void *nopBuffer = malloc(numberOfAllocatedBytes);
	memset(nopBuffer, NOP_VALUE, numberOfAllocatedBytes);
	if (!ZGWriteBytesIgnoringProtection(process.processTask, allocatedAddress, nopBuffer, numberOfAllocatedBytes))
	{
		NSLog(@"Failed to nop allocated memory for code injection"); // not a fatal error
	}
	free(nopBuffer);
	
	NSArray *instructions = [ZGDebuggerUtilities instructionsBeforeHookingIntoAddress:instruction.variable.address injectingIntoDestination:allocatedAddress inProcess:process withBreakPoints:breakPoints];
	
	if (instructions == nil)
	{
		if (!ZGDeallocateMemory(process.processTask, allocatedAddress, numberOfAllocatedBytes))
		{
			NSLog(@"Error: Failed to deallocate VM memory after failing to fetch enough instructions..");
		}
		
		NSLog(@"Error: not enough instructions to override, or allocated memory address was too far away. Source: 0x%llX, destination: 0x%llX", instruction.variable.address, allocatedAddress);
		NSRunAlertPanel(@"Failed to Inject Code", @"There was not enough space to override this instruction, or the newly allocated address was too far away", @"OK", nil, nil);
		
		return;
	}
	
	NSMutableString *suggestedCode = [NSMutableString stringWithFormat:@"; New code will be written at 0x%llX\n", allocatedAddress + INJECTED_NOP_SLIDE_LENGTH];
	
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
	
	[self window]; // Ensure window is loaded
	
	self.suggestedCode = suggestedCode;
	self.undoManager = undoManager;
	self.process = process;
	self.allocatedAddress = allocatedAddress;
	self.numberOfAllocatedBytes = numberOfAllocatedBytes;
	self.instructions = instructions;
	self.breakPoints = breakPoints;
	
	[NSApp
	 beginSheet:self.window
	 modalForWindow:parentWindow
	 modalDelegate:nil
	 didEndSelector:nil
	 contextInfo:NULL];
}

- (IBAction)injectCode:(id)__unused sender
{
	[self updateSuggestedCode];
	
	NSError *error = nil;
	NSData *injectedCode = [ZGDebuggerUtilities assembleInstructionText:self.suggestedCode atInstructionPointer:self.allocatedAddress usingArchitectureBits:self.process.pointerSize*8 error:&error];
	
	if (injectedCode.length == 0 || error != nil || ![ZGDebuggerUtilities injectCode:injectedCode intoAddress:self.allocatedAddress hookingIntoOriginalInstructions:self.instructions process:self.process breakPoints:self.breakPoints undoManager:self.undoManager error:&error])
	{
		NSLog(@"Error while injecting code");
		NSLog(@"%@", error);
		
		if (!ZGDeallocateMemory(self.process.processTask, self.allocatedAddress, self.numberOfAllocatedBytes))
		{
			NSLog(@"Error: Failed to deallocate VM memory after failing to inject code..");
		}
		
		NSRunAlertPanel(@"Failed to Inject Code", @"An error occured assembling the new code: %@", @"OK", nil, nil, [error.userInfo objectForKey:@"reason"]);
	}
	else
	{
		[NSApp endSheet:self.window];
		[self.window close];
	}
}

- (IBAction)cancel:(id)__unused sender
{
	if (!ZGDeallocateMemory(self.process.processTask, self.allocatedAddress, self.numberOfAllocatedBytes))
	{
		NSLog(@"Error: Failed to deallocate VM memory after canceling from injecting code..");
	}
	
	[NSApp endSheet:self.window];
	[self.window close];
}

@end
