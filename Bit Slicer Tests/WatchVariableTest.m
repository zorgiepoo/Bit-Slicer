/*
 * Copyright (c) 2025 Mayur Pawashe & Moreaki
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

#import <XCTest/XCTest.h>
#import "ZGWatchVariable.h"
#import "ZGInstruction.h"
#import "ZGRegistersState.h"
#import "ZGVirtualMemory.h"
#import "ZGBreakPoint.h"

#include <TargetConditionals.h>

/**
 * Tests for the memory watch variable functionality in Bit Slicer.
 *
 * These tests verify the proper creation, manipulation, and tracking
 * of watch variables, which monitor memory access during program execution.
 */
@interface WatchVariableTest : XCTestCase

@end

@implementation WatchVariableTest
{
    ZGMemoryMap _processTask;
}

- (void)setUp
{
    [super setUp];
    
#if TARGET_CPU_ARM64
    XCTSkip("Watch Variable Tests are not supported for arm64 yet");
#endif
    
    // We'll use our own process because it's a pain to use another one
    if (!ZGTaskForPID(getpid(), &_processTask))
    {
        XCTFail(@"Failed to grant access to task");
    }
}

- (void)tearDown
{
    ZGDeallocatePort(_processTask);
    [super tearDown];
}

/**
 * Tests the basic creation and properties of a ZGWatchVariable object.
 *
 * This test:
 * 1. Creates a ZGInstruction object to represent an instruction
 * 2. Creates a ZGRegistersState object to represent CPU state
 * 3. Creates a ZGWatchVariable with the instruction and registers state
 * 4. Verifies that the watch variable properties match the expected values
 *
 * Watch variable object structure:
 * ┌─────────────────────────────────────────────┐
 * │               ZGWatchVariable                │
 * ├─────────────────────────────────────────────┤
 * │ - instruction: ZGInstruction                 │
 * │ - registersState: ZGRegistersState           │
 * │ - accessCount: NSUInteger                    │
 * └─────────────────────────────────────────────┘
 */
- (void)testWatchVariableCreation
{
    // Create an instruction
    ZGMemoryAddress address = 0x1000;
    ZGMemorySize size = 4;
    NSString *mnemonic = @"mov";
    NSString *operands = @"eax, [ebx]";
    
    ZGInstruction *instruction = [[ZGInstruction alloc] initWithAddress:address size:size mnemonic:mnemonic operands:operands];
    
    // Create a registers state
    ZGRegistersState *registersState = [[ZGRegistersState alloc] init];
    
    // Create a watch variable
    ZGWatchVariable *watchVariable = [[ZGWatchVariable alloc] initWithInstruction:instruction registersState:registersState];
    
    // Verify watch variable properties
    XCTAssertEqualObjects(watchVariable.instruction, instruction);
    XCTAssertEqualObjects(watchVariable.registersState, registersState);
    XCTAssertEqual(watchVariable.accessCount, 0);
    
    // Test increasing access count
    [watchVariable increaseAccessCount];
    XCTAssertEqual(watchVariable.accessCount, 1);
    
    [watchVariable increaseAccessCount];
    [watchVariable increaseAccessCount];
    XCTAssertEqual(watchVariable.accessCount, 3);
}

/**
 * Tests the tracking of memory access with watch variables.
 *
 * This test:
 * 1. Creates multiple watch variables for different instructions
 * 2. Simulates memory access by increasing access counts
 * 3. Verifies that access counts are tracked correctly
 *
 * Memory access tracking:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │                      Memory Access Tracking                      │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                                                                  │
 * │  Instruction 1 (0x1000): mov eax, [ebx]                          │
 * │  Access Count: 3                                                 │
 * │                                                                  │
 * │  Instruction 2 (0x1008): add ecx, [edx+0x4]                      │
 * │  Access Count: 1                                                 │
 * │                                                                  │
 * │  Instruction 3 (0x1010): cmp [esi], 0x10                         │
 * │  Access Count: 2                                                 │
 * │                                                                  │
 * └─────────────────────────────────────────────────────────────────┘
 */
- (void)testWatchVariableAccessTracking
{
    // Create registers state
    ZGRegistersState *registersState = [[ZGRegistersState alloc] init];
    
    // Create multiple instructions and watch variables
    ZGInstruction *instruction1 = [[ZGInstruction alloc] initWithAddress:0x1000 size:4 mnemonic:@"mov" operands:@"eax, [ebx]"];
    ZGInstruction *instruction2 = [[ZGInstruction alloc] initWithAddress:0x1008 size:4 mnemonic:@"add" operands:@"ecx, [edx+0x4]"];
    ZGInstruction *instruction3 = [[ZGInstruction alloc] initWithAddress:0x1010 size:4 mnemonic:@"cmp" operands:@"[esi], 0x10"];
    
    ZGWatchVariable *watchVariable1 = [[ZGWatchVariable alloc] initWithInstruction:instruction1 registersState:registersState];
    ZGWatchVariable *watchVariable2 = [[ZGWatchVariable alloc] initWithInstruction:instruction2 registersState:registersState];
    ZGWatchVariable *watchVariable3 = [[ZGWatchVariable alloc] initWithInstruction:instruction3 registersState:registersState];
    
    // Simulate memory access
    [watchVariable1 increaseAccessCount];
    [watchVariable1 increaseAccessCount];
    [watchVariable1 increaseAccessCount];
    
    [watchVariable2 increaseAccessCount];
    
    [watchVariable3 increaseAccessCount];
    [watchVariable3 increaseAccessCount];
    
    // Verify access counts
    XCTAssertEqual(watchVariable1.accessCount, 3);
    XCTAssertEqual(watchVariable2.accessCount, 1);
    XCTAssertEqual(watchVariable3.accessCount, 2);
}

/**
 * Tests the integration between watch variables and breakpoints.
 *
 * This test:
 * 1. Creates a breakpoint for a memory address
 * 2. Simulates a breakpoint hit by creating a watch variable
 * 3. Verifies that the watch variable correctly tracks the memory access
 *
 * Breakpoint and watch variable integration:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │                 Breakpoint and Watch Variable                    │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                                                                  │
 * │  Memory Address: 0x2000                                          │
 * │  Breakpoint Type: Read/Write                                     │
 * │                                                                  │
 * │  When breakpoint triggers:                                       │
 * │  1. Instruction at 0x1000 accesses memory at 0x2000              │
 * │  2. CPU registers are captured                                   │
 * │  3. Watch variable is created with instruction and registers     │
 * │  4. Access count is incremented                                  │
 * │                                                                  │
 * └─────────────────────────────────────────────────────────────────┘
 */
- (void)testWatchVariableWithBreakpoint
{
    // Create a breakpoint for memory address 0x2000
    ZGMemoryAddress breakpointAddress = 0x2000;
    ZGMemorySize breakpointSize = 4;
    
    ZGBreakPoint *breakpoint = [[ZGBreakPoint alloc] initWithProcess:nil address:breakpointAddress size:breakpointSize type:ZGBreakPointReadWrite delegate:nil];
    
    // Create an instruction that accesses the memory at the breakpoint
    ZGInstruction *instruction = [[ZGInstruction alloc] initWithAddress:0x1000 size:4 mnemonic:@"mov" operands:@"eax, [0x2000]"];
    
    // Create a registers state
    ZGRegistersState *registersState = [[ZGRegistersState alloc] init];
    
    // Set the registers state in the breakpoint (simulating a breakpoint hit)
    breakpoint.registersState = registersState;
    
    // Create a watch variable from the breakpoint information
    ZGWatchVariable *watchVariable = [[ZGWatchVariable alloc] initWithInstruction:instruction registersState:breakpoint.registersState];
    
    // Verify the watch variable properties
    XCTAssertEqualObjects(watchVariable.instruction, instruction);
    XCTAssertEqualObjects(watchVariable.registersState, registersState);
    XCTAssertEqual(watchVariable.accessCount, 0);
    
    // Simulate memory access
    [watchVariable increaseAccessCount];
    
    // Verify access count
    XCTAssertEqual(watchVariable.accessCount, 1);
}

/**
 * Tests the handling of multiple watch variables for the same memory address.
 *
 * This test:
 * 1. Creates multiple watch variables for different instructions accessing the same memory
 * 2. Simulates memory access by increasing access counts
 * 3. Verifies that each watch variable correctly tracks its own access count
 *
 * Multiple watch variables for same address:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │            Multiple Watch Variables for Same Address             │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                                                                  │
 * │  Memory Address: 0x2000                                          │
 * │                                                                  │
 * │  Instruction 1 (0x1000): mov eax, [0x2000]                       │
 * │  Access Count: 2                                                 │
 * │                                                                  │
 * │  Instruction 2 (0x1008): add ecx, [0x2000]                       │
 * │  Access Count: 1                                                 │
 * │                                                                  │
 * │  Instruction 3 (0x1010): cmp [0x2000], 0x10                      │
 * │  Access Count: 3                                                 │
 * │                                                                  │
 * └─────────────────────────────────────────────────────────────────┘
 */
- (void)testMultipleWatchVariablesForSameAddress
{
    // Create registers state
    ZGRegistersState *registersState = [[ZGRegistersState alloc] init];
    
    // Create multiple instructions accessing the same memory address
    ZGInstruction *instruction1 = [[ZGInstruction alloc] initWithAddress:0x1000 size:4 mnemonic:@"mov" operands:@"eax, [0x2000]"];
    ZGInstruction *instruction2 = [[ZGInstruction alloc] initWithAddress:0x1008 size:4 mnemonic:@"add" operands:@"ecx, [0x2000]"];
    ZGInstruction *instruction3 = [[ZGInstruction alloc] initWithAddress:0x1010 size:4 mnemonic:@"cmp" operands:@"[0x2000], 0x10"];
    
    // Create watch variables
    ZGWatchVariable *watchVariable1 = [[ZGWatchVariable alloc] initWithInstruction:instruction1 registersState:registersState];
    ZGWatchVariable *watchVariable2 = [[ZGWatchVariable alloc] initWithInstruction:instruction2 registersState:registersState];
    ZGWatchVariable *watchVariable3 = [[ZGWatchVariable alloc] initWithInstruction:instruction3 registersState:registersState];
    
    // Simulate memory access
    [watchVariable1 increaseAccessCount];
    [watchVariable1 increaseAccessCount];
    
    [watchVariable2 increaseAccessCount];
    
    [watchVariable3 increaseAccessCount];
    [watchVariable3 increaseAccessCount];
    [watchVariable3 increaseAccessCount];
    
    // Verify access counts
    XCTAssertEqual(watchVariable1.accessCount, 2);
    XCTAssertEqual(watchVariable2.accessCount, 1);
    XCTAssertEqual(watchVariable3.accessCount, 3);
    
    // Create a dictionary to simulate how the watch variable window controller would track variables
    NSMutableDictionary<NSNumber *, ZGWatchVariable *> *watchVariablesDictionary = [NSMutableDictionary dictionary];
    
    // Add watch variables to dictionary using instruction address as key
    watchVariablesDictionary[@(instruction1.address)] = watchVariable1;
    watchVariablesDictionary[@(instruction2.address)] = watchVariable2;
    watchVariablesDictionary[@(instruction3.address)] = watchVariable3;
    
    // Verify dictionary lookup
    XCTAssertEqualObjects(watchVariablesDictionary[@(0x1000)], watchVariable1);
    XCTAssertEqualObjects(watchVariablesDictionary[@(0x1008)], watchVariable2);
    XCTAssertEqualObjects(watchVariablesDictionary[@(0x1010)], watchVariable3);
    
    // Verify total access count
    NSUInteger totalAccessCount = 0;
    for (ZGWatchVariable *watchVariable in watchVariablesDictionary.allValues) {
        totalAccessCount += watchVariable.accessCount;
    }
    
    XCTAssertEqual(totalAccessCount, 6);
}

@end