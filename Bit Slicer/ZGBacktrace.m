/*
 * Created by Mayur Pawashe on 2/22/14.
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

#import "ZGBacktrace.h"
#import "ZGProcess.h"
#import "ZGInstruction.h"
#import "ZGDebuggerUtilities.h"
#import "ZGMachBinary.h"
#import "ZGVirtualMemory.h"

@interface ZGBacktrace ()

@property (nonatomic) NSArray *instructions;
@property (nonatomic) NSArray *basePointers;

@end

@implementation ZGBacktrace

- (id)initWithInstructions:(NSArray *)instructions basePointers:(NSArray *)basePointers
{
	self = [super init];
	if (self != nil)
	{
		self.instructions = instructions;
		self.basePointers = basePointers;
	}
	return self;
}

+ (instancetype)backtraceWithBasePointer:(ZGMemoryAddress)basePointer instructionPointer:(ZGMemoryAddress)instructionPointer process:(ZGProcess *)process breakPoints:(NSArray *)breakPoints machBinaries:(NSArray *)machBinaries maxLimit:(NSUInteger)maxNumberOfInstructionsRetrieved
{
	NSMutableArray *newInstructions = [[NSMutableArray alloc] init];
	NSMutableArray *newBasePointers = [[NSMutableArray alloc] init];
	
	ZGInstruction *currentInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:instructionPointer+1 inProcess:process withBreakPoints:breakPoints machBinaries:machBinaries];
	if (currentInstruction != nil)
	{
		[newInstructions addObject:currentInstruction];
		[newBasePointers addObject:@(basePointer)];
		
		while (basePointer > 0 && (maxNumberOfInstructionsRetrieved == 0 || newInstructions.count < maxNumberOfInstructionsRetrieved))
		{
			// Read return address
			void *returnAddressBytes = NULL;
			ZGMemorySize returnAddressSize = process.pointerSize;
			if (!ZGReadBytes(process.processTask, basePointer + process.pointerSize, &returnAddressBytes, &returnAddressSize))
			{
				break;
			}
			
			ZGMemoryAddress returnAddress;
			switch (returnAddressSize)
			{
				case sizeof(ZGMemoryAddress):
					returnAddress = *(ZGMemoryAddress *)returnAddressBytes;
					break;
				case sizeof(ZG32BitMemoryAddress):
					returnAddress = *(ZG32BitMemoryAddress *)returnAddressBytes;
					break;
				default:
					returnAddress = 0;
			}
			
			ZGFreeBytes(returnAddressBytes, returnAddressSize);
			
			ZGInstruction *instruction = [ZGDebuggerUtilities findInstructionBeforeAddress:returnAddress inProcess:process withBreakPoints:breakPoints machBinaries:machBinaries];
			if (instruction == nil)
			{
				break;
			}
			
			[newInstructions addObject:instruction];
			
			// Read base pointer
			void *basePointerBytes = NULL;
			ZGMemorySize basePointerSize = process.pointerSize;
			if (!ZGReadBytes(process.processTask, basePointer, &basePointerBytes, &basePointerSize))
			{
				break;
			}
			
			switch (basePointerSize)
			{
				case sizeof(ZGMemoryAddress):
					basePointer = *(ZGMemoryAddress *)basePointerBytes;
					break;
				case sizeof(ZG32BitMemoryAddress):
					basePointer = *(ZG32BitMemoryAddress *)basePointerBytes;
					break;
				default:
					basePointer = 0;
			}
			
			[newBasePointers addObject:@(basePointer)];
			
			ZGFreeBytes(basePointerBytes, basePointerSize);
		}
	}
	
	return [[ZGBacktrace alloc] initWithInstructions:newInstructions basePointers:newBasePointers];
}

+ (instancetype)backtraceWithBasePointer:(ZGMemoryAddress)basePointer instructionPointer:(ZGMemoryAddress)instructionPointer process:(ZGProcess *)process breakPoints:(NSArray *)breakPoints machBinaries:(NSArray *)machBinaries
{
	return [self backtraceWithBasePointer:basePointer instructionPointer:instructionPointer process:process breakPoints:breakPoints machBinaries:machBinaries maxLimit:0];
}

@end
