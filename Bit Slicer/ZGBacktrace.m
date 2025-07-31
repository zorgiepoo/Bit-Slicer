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

/*
 * ZGBacktrace - Stack Trace Generation
 * ===================================
 *
 * This module generates stack traces (backtraces) for debugging purposes,
 * showing the call chain that led to the current execution point.
 *
 * Backtrace Generation Flow:
 * -------------------------
 *
 *                                 +----------------+
 *                                 | Thread Stopped |
 *                                 | at Breakpoint  |
 *                                 +--------+-------+
 *                                          |
 *                                          | (Get registers)
 *                                          v
 *  +----------------+            +-------------------+
 *  | ZGThreadStates |----------->| Base Pointer (BP) |
 *  | (get registers) |            | Instruction Ptr  |
 *  +----------------+            +-------------------+
 *                                          |
 *                                          | (Start backtrace)
 *                                          v
 *                                 +-------------------+
 *                                 | Find Current      |
 *                                 | Instruction       |
 *                                 +-------------------+
 *                                          |
 *                                          | (Add to backtrace)
 *                                          v
 *                                 +-------------------+
 *                                 | Stack Frame       |
 *                                 | Traversal Loop    |
 *                                 +-------------------+
 *                                          |
 *                                          | (For each frame)
 *                                          v
 *  +----------------+            +-------------------+
 *  | Read Memory at |<-----------| Read Return Addr  |
 *  | BP + ptr_size  |            | from Stack        |
 *  +----------------+            +-------------------+
 *          |                              |
 *          |                              | (Find corresponding instruction)
 *          |                              v
 *          |                     +-------------------+
 *          |                     | Find Instruction  |
 *          |                     | for Return Addr   |
 *          |                     +-------------------+
 *          |                              |
 *          |                              | (Add to backtrace)
 *          v                              v
 *  +----------------+            +-------------------+
 *  | Read Memory at |----------->| Read Next BP      |
 *  | BP             |            | from Stack        |
 *  +----------------+            +-------------------+
 *                                          |
 *                                          | (Continue until BP is 0 or limit reached)
 *                                          v
 *                                 +-------------------+
 *                                 | Complete          |
 *                                 | Backtrace         |
 *                                 +-------------------+
 *
 * Stack Frame Structure (x86/x64):
 * ------------------------------
 *
 * High Address
 *    |
 *    | Function parameters
 *    |
 *    | Return address
 *    |
 *    | Saved base pointer (BP) <-- Current BP points here
 *    |
 *    | Local variables
 *    |
 * Low Address
 *
 * Note: ARM64 uses a different approach with frame pointer (FP)
 * and link register (LR) instead of the traditional x86 approach.
 *
 * Memory Layout Examples:
 * ---------------------
 *
 * x86_64 Stack Frame Memory Layout:
 * +-----------------------------------------------------------------------+
 * | Address         | Value                | Description                  |
 * |-----------------|----------------------|------------------------------|
 * | rbp+0x18        | 0x00007fff5fc02000   | Function parameter 1         |
 * | rbp+0x10        | 0x00007fff5fc03000   | Function parameter 2         |
 * | rbp+0x08        | 0x00007fff5fc05000   | Return address               |
 * | rbp+0x00        | 0x00007fff5fc04000   | Saved base pointer (old rbp) |
 * | rbp-0x08        | 0x0000000000000001   | Local variable 1             |
 * | rbp-0x10        | 0x0000000000000002   | Local variable 2             |
 * | ...             | ...                  | ...                          |
 * +-----------------------------------------------------------------------+
 *
 * x86_64 Stack Memory Example (Multiple Frames):
 * +-----------------------------------------------------------------------+
 * | Address         | Value                | Description                  |
 * |-----------------|----------------------|------------------------------|
 * | 0x7fff5fc03f20  | 0x00007fff5fc02000   | main() param 1               |
 * | 0x7fff5fc03f18  | 0x00007fff5fc03000   | main() param 2               |
 * | 0x7fff5fc03f10  | 0x00007fff5fc05000   | Return to _start             |
 * | 0x7fff5fc03f08  | 0x00007fff5fc06000   | Saved rbp from _start        |
 * | 0x7fff5fc03f00  | 0x0000000000000001   | main() local var             |
 * | ...             | ...                  | ...                          |
 * | 0x7fff5fc03ef0  | 0x00007fff5fc02010   | func1() param 1              |
 * | 0x7fff5fc03ee8  | 0x00007fff5fc02020   | func1() param 2              |
 * | 0x7fff5fc03ee0  | 0x00007fff5fc05100   | Return to main()             |
 * | 0x7fff5fc03ed8  | 0x00007fff5fc03f08   | Saved rbp from main()        |
 * | 0x7fff5fc03ed0  | 0x0000000000000002   | func1() local var            |
 * | ...             | ...                  | ...                          |
 * | 0x7fff5fc03ec0  | 0x00007fff5fc02030   | func2() param 1              |
 * | 0x7fff5fc03eb8  | 0x00007fff5fc02040   | func2() param 2              |
 * | 0x7fff5fc03eb0  | 0x00007fff5fc05200   | Return to func1()            |
 * | 0x7fff5fc03ea8  | 0x00007fff5fc03ed8   | Saved rbp from func1()       |
 * | 0x7fff5fc03ea0  | 0x0000000000000003   | func2() local var            |
 * | ...             | ...                  | ...                          |
 * +-----------------------------------------------------------------------+
 *
 * x86_64 Backtrace Process:
 * 1. Start with current rbp = 0x7fff5fc03ea8, rip = 0x00007fff5fc05300
 * 2. Record current instruction at rip
 * 3. Read return address at rbp+0x08 = 0x00007fff5fc05200
 * 4. Read next rbp at rbp+0x00 = 0x00007fff5fc03ed8
 * 5. Record instruction at return address
 * 6. Continue with new rbp, repeating steps 3-5
 *
 * ARM64 Stack Frame Memory Layout:
 * +-----------------------------------------------------------------------+
 * | Address         | Value                | Description                  |
 * |-----------------|----------------------|------------------------------|
 * | fp+0x18         | 0x0000000016fe0000   | Function parameter 1         |
 * | fp+0x10         | 0x0000000000000010   | Function parameter 2         |
 * | fp+0x08         | 0x0000000016fd0004   | Return address (LR)          |
 * | fp+0x00         | 0x0000000016fe1000   | Saved frame pointer (old fp) |
 * | fp-0x08         | 0x0000000000000001   | Local variable 1             |
 * | fp-0x10         | 0x0000000000000002   | Local variable 2             |
 * | ...             | ...                  | ...                          |
 * +-----------------------------------------------------------------------+
 *
 * ARM64 Stack Memory Example (Multiple Frames):
 * +-----------------------------------------------------------------------+
 * | Address         | Value                | Description                  |
 * |-----------------|----------------------|------------------------------|
 * | 0x16fdff020     | 0x0000000016fe0000   | main() param 1               |
 * | 0x16fdff018     | 0x0000000000000010   | main() param 2               |
 * | 0x16fdff010     | 0x0000000016fd0004   | Return to _start             |
 * | 0x16fdff008     | 0x0000000016fe1000   | Saved fp from _start         |
 * | 0x16fdff000     | 0x0000000000000001   | main() local var             |
 * | ...             | ...                  | ...                          |
 * | 0x16fdfef20     | 0x0000000016fe0010   | func1() param 1              |
 * | 0x16fdfef18     | 0x0000000016fe0020   | func1() param 2              |
 * | 0x16fdfef10     | 0x0000000016fd0100   | Return to main()             |
 * | 0x16fdfef08     | 0x0000000016fdff008  | Saved fp from main()         |
 * | 0x16fdfef00     | 0x0000000000000002   | func1() local var            |
 * | ...             | ...                  | ...                          |
 * | 0x16fdfee20     | 0x0000000016fe0030   | func2() param 1              |
 * | 0x16fdfee18     | 0x0000000016fe0040   | func2() param 2              |
 * | 0x16fdfee10     | 0x0000000016fd0200   | Return to func1()            |
 * | 0x16fdfee08     | 0x0000000016fdfef08  | Saved fp from func1()        |
 * | 0x16fdfee00     | 0x0000000000000003   | func2() local var            |
 * | ...             | ...                  | ...                          |
 * +-----------------------------------------------------------------------+
 *
 * ARM64 Backtrace Process:
 * 1. Start with current fp = 0x0000000016fdfee08, pc = 0x0000000016fd0300
 * 2. Record current instruction at pc
 * 3. Read return address at fp+0x08 = 0x0000000016fd0200
 * 4. Read next fp at fp+0x00 = 0x0000000016fdfef08
 * 5. Record instruction at return address
 * 6. Continue with new fp, repeating steps 3-5
 *
 * Note: In ARM64, the link register (LR/x30) holds the return address for the
 * current function. When a function calls another function, the return address
 * is saved to the stack frame. The backtrace algorithm reads these saved return
 * addresses from the stack frames.
 */

#import "ZGBacktrace.h"
#import "ZGProcess.h"
#import "ZGInstruction.h"
#import "ZGDebuggerUtilities.h"
#import "ZGMachBinary.h"
#import "ZGVirtualMemory.h"

@implementation ZGBacktrace

- (id)initWithInstructions:(NSArray<ZGInstruction *> *)instructions basePointers:(NSArray<NSNumber *> *)basePointers
{
	self = [super init];
	if (self != nil)
	{
		_instructions = instructions;
		_basePointers = basePointers;
	}
	return self;
}

+ (instancetype)backtraceWithBasePointer:(ZGMemoryAddress)basePointer instructionPointer:(ZGMemoryAddress)instructionPointer process:(ZGProcess *)process breakPoints:(NSArray<ZGBreakPoint *> *)breakPoints machBinaries:(NSArray<ZGMachBinary *> *)machBinaries maxLimit:(NSUInteger)maxNumberOfInstructionsRetrieved
{
	NSMutableArray<ZGInstruction *> *newInstructions = [[NSMutableArray alloc] init];
	NSMutableArray<NSNumber *> *newBasePointers = [[NSMutableArray alloc] init];

	ZGInstruction *currentInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:instructionPointer+1 inProcess:process withBreakPoints:breakPoints processType:process.type machBinaries:machBinaries];
	if (currentInstruction != nil)
	{
		[newInstructions addObject:currentInstruction];
		[newBasePointers addObject:@(basePointer)];

		// Rosetta processes don't use the base pointer register we retrieved, don't even try
		while (!process.translated && basePointer > 0 && (maxNumberOfInstructionsRetrieved == 0 || newInstructions.count < maxNumberOfInstructionsRetrieved))
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
					// Ignore bits which may be used for something other than the return address
					returnAddress = *(ZGMemoryAddress *)returnAddressBytes & 0x00007FFFFFFFFFFF;
					break;
				case sizeof(ZG32BitMemoryAddress):
					returnAddress = *(ZG32BitMemoryAddress *)returnAddressBytes;
					break;
				default:
					returnAddress = 0;
			}

			ZGFreeBytes(returnAddressBytes, returnAddressSize);

			ZGInstruction *instruction = [ZGDebuggerUtilities findInstructionBeforeAddress:returnAddress inProcess:process withBreakPoints:breakPoints processType:process.type machBinaries:machBinaries];
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

+ (instancetype)backtraceWithBasePointer:(ZGMemoryAddress)basePointer instructionPointer:(ZGMemoryAddress)instructionPointer process:(ZGProcess *)process breakPoints:(NSArray<ZGBreakPoint *> *)breakPoints machBinaries:(NSArray<ZGMachBinary *> *)machBinaries
{
	return [self backtraceWithBasePointer:basePointer instructionPointer:instructionPointer process:process breakPoints:breakPoints machBinaries:machBinaries maxLimit:0];
}

@end
