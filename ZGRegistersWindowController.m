/*
 * Created by Mayur Pawashe on 1/16/13.
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

#import "ZGRegistersWindowController.h"
#import "ZGBreakPoint.h"
#import "ZGVirtualMemory.h"
#import "ZGRegister.h"
#import "ZGProcess.h"
#import "ZGVariable.h"

@interface ZGRegistersWindowController ()

@property (assign) IBOutlet NSTableView *tableView;
@property (nonatomic, strong) NSArray *registers;

@end

@implementation ZGRegistersWindowController

- (id)init
{
	self = [super initWithWindowNibName:NSStringFromClass([self class])];
	
	return self;
}

- (void)showWindow:(id)sender
{
	[self.window orderFront:nil];
}

#define ADD_REGISTER(registerName, variableType, structureType) \
	[newRegisters addObject:[[ZGRegister alloc] initWithName:[NSString stringWithUTF8String:#registerName] variable:[[ZGVariable alloc] initWithValue:&threadState.uts.structureType.__##registerName size:registerSize address:threadState.uts.structureType.__##registerName type:variableType qualifier:ZGSigned pointerSize:registerSize]]]

#define ADD_REGISTER_32(registerName, variableType) ADD_REGISTER(registerName, variableType, ts32)
#define ADD_REGISTER_64(registerName, variableType) ADD_REGISTER(registerName, variableType, ts64)

- (void)updateRegistersFromBreakPoint:(ZGBreakPoint *)breakPoint
{
	NSMutableArray *newRegisters = [[NSMutableArray alloc] init];
	
	x86_thread_state_t threadState;
	mach_msg_type_number_t threadStateCount = x86_THREAD_STATE_COUNT;
	if (thread_get_state(breakPoint.thread, x86_THREAD_STATE, (thread_state_t)&threadState, &threadStateCount) == KERN_SUCCESS)
	{
		ZGMemorySize registerSize = breakPoint.process.pointerSize;
		
		if (breakPoint.process.is64Bit)
		{
			// General registers
			ADD_REGISTER_64(rax, ZGInt64);
			ADD_REGISTER_64(rbx, ZGInt64);
			ADD_REGISTER_64(rcx, ZGInt64);
			ADD_REGISTER_64(rdx, ZGInt64);
			
			// Index and pointers
			ADD_REGISTER_64(rdi, ZGByteArray);
			ADD_REGISTER_64(rsi, ZGByteArray);
			ADD_REGISTER_64(rbp, ZGPointer);
			ADD_REGISTER_64(rsp, ZGPointer);
			
			// Extra registers
			ADD_REGISTER_64(r8, ZGInt64);
			ADD_REGISTER_64(r9, ZGInt64);
			ADD_REGISTER_64(r10, ZGInt64);
			ADD_REGISTER_64(r11, ZGInt64);
			ADD_REGISTER_64(r12, ZGInt64);
			ADD_REGISTER_64(r13, ZGInt64);
			ADD_REGISTER_64(r14, ZGInt64);
			ADD_REGISTER_64(r15, ZGInt64);
			
			// Instruction pointer
			ADD_REGISTER_64(rip, ZGPointer);
			
			// Flags indicator
			ADD_REGISTER_64(rflags, ZGByteArray);
			
			// Segment registers
			ADD_REGISTER_64(cs, ZGByteArray);
			ADD_REGISTER_64(fs, ZGByteArray);
			ADD_REGISTER_64(gs, ZGByteArray);
		}
		else
		{
			// General registers
			ADD_REGISTER_32(eax, ZGInt32);
			ADD_REGISTER_32(ebx, ZGInt32);
			ADD_REGISTER_32(ecx, ZGInt32);
			ADD_REGISTER_32(edx, ZGInt32);
			
			// Index and pointers
			ADD_REGISTER_32(edi, ZGByteArray);
			ADD_REGISTER_32(esi, ZGByteArray);
			ADD_REGISTER_32(ebp, ZGPointer);
			ADD_REGISTER_32(esp, ZGPointer);
			
			// Segment register
			ADD_REGISTER_32(ss, ZGByteArray);
			
			// Flags indicator
			ADD_REGISTER_32(eflags, ZGByteArray);
			
			// Instruction pointer
			ADD_REGISTER_32(eip, ZGPointer);
			
			// Segment registers
			ADD_REGISTER_32(cs, ZGByteArray);
			ADD_REGISTER_32(ds, ZGByteArray);
			ADD_REGISTER_32(es, ZGByteArray);
			ADD_REGISTER_32(fs, ZGByteArray);
			ADD_REGISTER_32(gs, ZGByteArray);
		}
	}
	
	self.registers = [NSArray arrayWithArray:newRegisters];
	[self.tableView reloadData];
}

#pragma mark TableView Methods

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return self.registers.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	id result = nil;
	if (rowIndex >= 0 && (NSUInteger)rowIndex < self.registers.count)
	{
		ZGRegister *theRegister = [self.registers objectAtIndex:rowIndex];
		if ([tableColumn.identifier isEqualToString:@"name"])
		{
			result = theRegister.name;
		}
		else if ([tableColumn.identifier isEqualToString:@"value"])
		{
			result = [theRegister.variable stringValue];
		}
		else if ([tableColumn.identifier isEqualToString:@"type"])
		{
			return @([[tableColumn dataCell] indexOfItemWithTag:theRegister.variable.type]);
		}
	}
	
	return result;
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if (rowIndex >= 0 && (NSUInteger)rowIndex < self.registers.count)
	{
		//ZGRegister *theRegister = [self.registers objectAtIndex:rowIndex];
		if ([tableColumn.identifier isEqualToString:@"value"])
		{
		}
		else if ([tableColumn.identifier isEqualToString:@"type"])
		{
			//ZGVariableType newType =(ZGVariableType)[tableColumn.dataCell indexOfItemWithTag:[object integerValue]];
			/*
			 [theRegister.variable
			 setType:newType
			 requestedSize:theRegister.variable.size
			 pointerSize:4];
			 */
		}
	}
}

@end
