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

#import <Foundation/Foundation.h>
#import "ZGMemoryTypes.h"

@class ZGProcess;
@class ZGInstruction;
@class ZGDisassemblerObject;
@class ZGMachBinary;
@class ZGBreakPoint;

#define INJECTED_NOP_SLIDE_LENGTH 0x10
#define NOP_VALUE 0x90

#define ZGLocalizedStringFromDebuggerTable(string) NSLocalizedStringFromTable((string), @"[Code] Debugger", nil)

NS_ASSUME_NONNULL_BEGIN

@interface ZGDebuggerUtilities : NSObject

+ (nullable NSData *)readDataWithProcessTask:(ZGMemoryMap)processTask address:(ZGMemoryAddress)address size:(ZGMemorySize)size breakPoints:(NSArray<ZGBreakPoint *> *)breakPoints;
+ (BOOL)writeData:(NSData *)data atAddress:(ZGMemoryAddress)address processTask:(ZGMemoryMap)processTask breakPoints:(NSArray<ZGBreakPoint *> *)breakPoints;

+ (NSData *)assembleInstructionText:(NSString *)instructionText atInstructionPointer:(ZGMemoryAddress)instructionPointer usingArchitectureBits:(ZGMemorySize)numberOfBits error:(NSError **)error;

+ (nullable ZGDisassemblerObject *)disassemblerObjectWithProcessTask:(ZGMemoryMap)processTask pointerSize:(ZGMemorySize)pointerSize address:(ZGMemoryAddress)address size:(ZGMemorySize)size breakPoints:(NSArray<ZGBreakPoint *> *)breakPoints;

// This method is generally useful for a) finding instruction address when returning from a breakpoint where the program counter is set ahead of the instruction, and b) figuring out correct offsets of where instructions are aligned in memory
+ (nullable ZGInstruction *)findInstructionBeforeAddress:(ZGMemoryAddress)address inProcess:(ZGProcess *)process withBreakPoints:(NSArray<ZGBreakPoint *> *)breakPoints machBinaries:(NSArray<ZGMachBinary *> *)machBinaries;

+ (void)
replaceInstructions:(NSArray<ZGInstruction *> *)instructions
fromOldStringValues:(NSArray<NSString *> *)oldStringValues
toNewStringValues:(NSArray<NSString *> *)newStringValues
inProcess:(ZGProcess *)process
breakPoints:(NSArray<ZGBreakPoint *> *)breakPoints
undoManager:(nullable NSUndoManager *)undoManager
actionName:(nullable NSString *)actionName;

+ (void)nopInstructions:(NSArray<ZGInstruction *> *)instructions inProcess:(ZGProcess *)process breakPoints:(NSArray<ZGBreakPoint *> *)breakPoints undoManager:(nullable NSUndoManager *)undoManager actionName:(nullable NSString *)actionName;

+ (NSArray<ZGInstruction *> *)instructionsBeforeHookingIntoAddress:(ZGMemoryAddress)address injectingIntoDestination:(ZGMemoryAddress)destinationAddress inProcess:(ZGProcess *)process withBreakPoints:(NSArray<ZGBreakPoint *> *)breakPoints;

+ (BOOL)
injectCode:(NSData *)codeData
intoAddress:(ZGMemoryAddress)allocatedAddress
hookingIntoOriginalInstructions:(NSArray<ZGInstruction *> *)hookedInstructions
process:(ZGProcess *)process
breakPoints:(NSArray<ZGBreakPoint *> *)breakPoints
undoManager:(nullable NSUndoManager *)undoManager
error:(NSError  **)error;

@end

NS_ASSUME_NONNULL_END
