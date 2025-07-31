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
#import "ZGRegister.h"
#import "ZGRegisterEntries.h"
#import "ZGRegistersState.h"
#import "ZGVariable.h"
#import "ZGVirtualMemory.h"

#include <TargetConditionals.h>

/**
 * Tests for the CPU register management functionality in Bit Slicer.
 *
 * These tests verify the proper creation, manipulation, and interaction
 * of register objects, ensuring they correctly represent CPU register state.
 */
@interface RegisterTest : XCTestCase

@end

@implementation RegisterTest
{
    ZGMemoryMap _processTask;
}

- (void)setUp
{
    [super setUp];
    
#if TARGET_CPU_ARM64
    XCTSkip("Register Tests are not supported for arm64 yet");
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
 * Tests the basic creation and properties of a ZGRegister object.
 *
 * This test:
 * 1. Creates a ZGVariable to represent a register value
 * 2. Creates a ZGRegister with the variable
 * 3. Verifies that the register properties match the expected values
 *
 * Register object structure:
 * ┌─────────────────────────────────────────────┐
 * │               ZGRegister                     │
 * ├─────────────────────────────────────────────┤
 * │ - variable: ZGVariable                       │
 * │ - rawValue: void*                            │
 * │ - size: ZGMemorySize                         │
 * │ - registerType: ZGRegisterType               │
 * └─────────────────────────────────────────────┘
 */
- (void)testRegisterCreation
{
    // Create a variable to represent a register value (e.g., RAX = 0x1234567890ABCDEF)
    uint64_t registerValue = 0x1234567890ABCDEF;
    void *bytes = malloc(sizeof(registerValue));
    if (bytes == NULL) {
        XCTFail(@"Failed to allocate memory for register value");
        return;
    }
    memcpy(bytes, &registerValue, sizeof(registerValue));
    
    ZGVariable *variable = [[ZGVariable alloc] initWithValue:bytes size:sizeof(registerValue) address:0 type:ZGInt64 qualifier:ZGSigned description:@"RAX" enabled:YES];
    
    // Create a register with the variable
    ZGRegister *register1 = [[ZGRegister alloc] initWithRegisterType:ZGRegisterGeneralPurpose variable:variable];
    
    // Verify register properties
    XCTAssertEqual(register1.registerType, ZGRegisterGeneralPurpose);
    XCTAssertEqual(register1.size, sizeof(registerValue));
    XCTAssertEqual(*(uint64_t *)register1.rawValue, registerValue);
    XCTAssertEqualObjects(register1.variable, variable);
    XCTAssertEqualObjects(register1.variable.description, @"RAX");
    
    free(bytes);
}

/**
 * Tests the creation and manipulation of register entries.
 *
 * This test:
 * 1. Creates register entries from thread state
 * 2. Verifies that the entries are correctly populated
 * 3. Accesses register values through the entries
 *
 * Register entries structure:
 * ┌─────────────────────────────────────────────┐
 * │            ZGRegisterEntry[]                 │
 * ├─────────────────────────────────────────────┤
 * │ Entry 1:                                     │
 * │  - name: "RAX"                               │
 * │  - value: 0x1234567890ABCDEF                 │
 * │  - size: 8                                   │
 * │  - type: ZGRegisterGeneralPurpose            │
 * ├─────────────────────────────────────────────┤
 * │ Entry 2:                                     │
 * │  - name: "RBX"                               │
 * │  - value: 0x...                              │
 * │  - size: 8                                   │
 * │  - type: ZGRegisterGeneralPurpose            │
 * ├─────────────────────────────────────────────┤
 * │ ...                                          │
 * └─────────────────────────────────────────────┘
 */
- (void)testRegisterEntries
{
    // Get thread state for the current thread
    zg_thread_state_t threadState;
    mach_msg_type_number_t stateCount = ZG_THREAD_STATE_COUNT;
    thread_t thread = pthread_mach_thread_np(pthread_self());
    
    kern_return_t error = thread_get_state(thread, ZG_THREAD_STATE, (thread_state_t)&threadState, &stateCount);
    if (error != KERN_SUCCESS) {
        XCTFail(@"Failed to get thread state: %d", error);
        return;
    }
    
    // Create register entries from thread state
    ZGRegisterEntry entries[ZG_MAX_REGISTER_ENTRIES];
    int numberOfEntries = [ZGRegisterEntries getRegisterEntries:entries fromGeneralPurposeThreadState:threadState is64Bit:YES];
    
    // Verify that we got some entries
    XCTAssertGreaterThan(numberOfEntries, 0);
    
    // Verify that the entries are correctly populated
    BOOL foundRIP = NO;
    for (int i = 0; i < numberOfEntries; i++) {
        ZGRegisterEntry *entry = &entries[i];
        
        // Check that the entry has a name
        XCTAssertNotNil([NSString stringWithUTF8String:entry->name]);
        
        // Check that the entry has a value
        void *value = ZGRegisterEntryValue(entry);
        XCTAssertNotNil((__bridge id)value);
        
        // Check that the entry has the correct type
        XCTAssertEqual(entry->type, ZGRegisterGeneralPurpose);
        
        // Look for the instruction pointer (RIP) register
        if (strcmp(entry->name, "rip") == 0) {
            foundRIP = YES;
            
            // The RIP should be a valid address (non-zero)
            uint64_t ripValue = *(uint64_t *)value;
            XCTAssertNotEqual(ripValue, 0);
        }
    }
    
    // We should have found the RIP register
    XCTAssertTrue(foundRIP);
}

/**
 * Tests the creation and properties of a ZGRegistersState object.
 *
 * This test:
 * 1. Creates a ZGRegistersState object
 * 2. Sets thread states
 * 3. Verifies that the states are correctly stored
 *
 * Registers state structure:
 * ┌─────────────────────────────────────────────┐
 * │            ZGRegistersState                  │
 * ├─────────────────────────────────────────────┤
 * │ - threadState: zg_thread_state_t             │
 * │ - vectorState: zg_vector_state_t             │
 * │ - hasThreadState: BOOL                       │
 * │ - hasVectorState: BOOL                       │
 * └─────────────────────────────────────────────┘
 */
- (void)testRegistersState
{
    // Create a registers state object
    ZGRegistersState *registersState = [[ZGRegistersState alloc] init];
    
    // Initially, it should not have any states
    XCTAssertFalse(registersState.hasThreadState);
    XCTAssertFalse(registersState.hasVectorState);
    
    // Get thread state for the current thread
    zg_thread_state_t threadState;
    mach_msg_type_number_t stateCount = ZG_THREAD_STATE_COUNT;
    thread_t thread = pthread_mach_thread_np(pthread_self());
    
    kern_return_t error = thread_get_state(thread, ZG_THREAD_STATE, (thread_state_t)&threadState, &stateCount);
    if (error != KERN_SUCCESS) {
        XCTFail(@"Failed to get thread state: %d", error);
        return;
    }
    
    // Set the thread state
    [registersState setGeneralPurposeThreadState:threadState];
    
    // Now it should have a thread state
    XCTAssertTrue(registersState.hasThreadState);
    
    // Get the thread state back and verify it matches
    zg_thread_state_t retrievedState;
    XCTAssertTrue([registersState getGeneralPurposeThreadState:&retrievedState]);
    
    // Compare the states (just check a few registers)
#if defined(__x86_64__)
    XCTAssertEqual(threadState.__rax, retrievedState.__rax);
    XCTAssertEqual(threadState.__rbx, retrievedState.__rbx);
    XCTAssertEqual(threadState.__rcx, retrievedState.__rcx);
    XCTAssertEqual(threadState.__rdx, retrievedState.__rdx);
    XCTAssertEqual(threadState.__rip, retrievedState.__rip);
#endif
}

/**
 * Tests the integration between register entries, variables, and register objects.
 *
 * This test:
 * 1. Creates register entries from thread state
 * 2. Converts entries to variables
 * 3. Creates register objects from variables
 * 4. Verifies the complete chain works correctly
 *
 * Register integration flow:
 * ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
 * │ ZGRegisterEntry │ --> │   ZGVariable    │ --> │   ZGRegister    │
 * │ (raw data)      │     │ (typed value)   │     │ (UI object)     │
 * └─────────────────┘     └─────────────────┘     └─────────────────┘
 */
- (void)testRegisterIntegration
{
    // Get thread state for the current thread
    zg_thread_state_t threadState;
    mach_msg_type_number_t stateCount = ZG_THREAD_STATE_COUNT;
    thread_t thread = pthread_mach_thread_np(pthread_self());
    
    kern_return_t error = thread_get_state(thread, ZG_THREAD_STATE, (thread_state_t)&threadState, &stateCount);
    if (error != KERN_SUCCESS) {
        XCTFail(@"Failed to get thread state: %d", error);
        return;
    }
    
    // Create register entries from thread state
    ZGRegisterEntry entries[ZG_MAX_REGISTER_ENTRIES];
    int numberOfEntries = [ZGRegisterEntries getRegisterEntries:entries fromGeneralPurposeThreadState:threadState is64Bit:YES];
    
    // Convert entries to variables
    NSArray<ZGVariable *> *variables = [ZGRegisterEntries registerVariablesFromGeneralPurposeThreadState:threadState is64Bit:YES];
    
    // Verify that we got the same number of variables as entries
    XCTAssertEqual(variables.count, numberOfEntries);
    
    // Create register objects from variables
    NSMutableArray<ZGRegister *> *registers = [NSMutableArray array];
    for (ZGVariable *variable in variables) {
        ZGRegister *reg = [[ZGRegister alloc] initWithRegisterType:ZGRegisterGeneralPurpose variable:variable];
        [registers addObject:reg];
    }
    
    // Verify that we got the same number of registers as variables
    XCTAssertEqual(registers.count, variables.count);
    
    // Verify that the registers have the correct properties
    for (NSUInteger i = 0; i < registers.count; i++) {
        ZGRegister *reg = registers[i];
        ZGVariable *var = variables[i];
        
        XCTAssertEqual(reg.registerType, ZGRegisterGeneralPurpose);
        XCTAssertEqualObjects(reg.variable, var);
        
        // For 64-bit registers, the size should be 8 bytes
        if ([var.description isEqualToString:@"rax"] ||
            [var.description isEqualToString:@"rbx"] ||
            [var.description isEqualToString:@"rcx"] ||
            [var.description isEqualToString:@"rdx"] ||
            [var.description isEqualToString:@"rsp"] ||
            [var.description isEqualToString:@"rbp"] ||
            [var.description isEqualToString:@"rsi"] ||
            [var.description isEqualToString:@"rdi"] ||
            [var.description isEqualToString:@"rip"]) {
            XCTAssertEqual(reg.size, 8);
        }
    }
}

@end