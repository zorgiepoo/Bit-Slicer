/*
 * Created by Mayur Pawashe on 3/29/14.
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

#import <Foundation/Foundation.h>
#import "ZGMemoryTypes.h"

@class ZGProcess;
@class ZGInstruction;
@class ZGDisassemblerObject;

#define INJECTED_NOP_SLIDE_LENGTH 0x10
#define NOP_VALUE 0x90

#define ZGLocalizedStringFromDebuggerTable(string) NSLocalizedStringFromTable((string), @"[Code] Debugger", nil)

@interface ZGDebuggerUtilities : NSObject

+ (nullable NSData *)readDataWithProcessTask:(ZGMemoryMap)processTask address:(ZGMemoryAddress)address size:(ZGMemorySize)size breakPoints:(nonnull NSArray *)breakPoints;
+ (BOOL)writeData:(nonnull NSData *)data atAddress:(ZGMemoryAddress)address processTask:(ZGMemoryMap)processTask breakPoints:(nonnull NSArray *)breakPoints;

+ (nonnull NSData *)assembleInstructionText:(nonnull NSString *)instructionText atInstructionPointer:(ZGMemoryAddress)instructionPointer usingArchitectureBits:(ZGMemorySize)numberOfBits error:(NSError *__nullable * __nullable)error;

+ (nullable ZGDisassemblerObject *)disassemblerObjectWithProcessTask:(ZGMemoryMap)processTask pointerSize:(ZGMemorySize)pointerSize address:(ZGMemoryAddress)address size:(ZGMemorySize)size breakPoints:(nonnull NSArray *)breakPoints;

// This method is generally useful for a) finding instruction address when returning from a breakpoint where the program counter is set ahead of the instruction, and b) figuring out correct offsets of where instructions are aligned in memory
+ (nullable ZGInstruction *)findInstructionBeforeAddress:(ZGMemoryAddress)address inProcess:(nonnull ZGProcess *)process withBreakPoints:(nonnull NSArray *)breakPoints machBinaries:(nonnull NSArray *)machBinaries;

+ (void)
replaceInstructions:(nonnull NSArray *)instructions
fromOldStringValues:(nonnull NSArray *)oldStringValues
toNewStringValues:(nonnull NSArray *)newStringValues
inProcess:(nonnull ZGProcess *)process
breakPoints:(nonnull NSArray *)breakPoints
undoManager:(nullable NSUndoManager *)undoManager
actionName:(nullable NSString *)actionName;

+ (void)nopInstructions:(nonnull NSArray *)instructions inProcess:(nonnull ZGProcess *)process breakPoints:(nonnull NSArray *)breakPoints undoManager:(nullable NSUndoManager *)undoManager actionName:(nullable NSString *)actionName;

+ (nonnull NSArray *)instructionsBeforeHookingIntoAddress:(ZGMemoryAddress)address injectingIntoDestination:(ZGMemoryAddress)destinationAddress inProcess:(nonnull ZGProcess *)process withBreakPoints:(nonnull NSArray *)breakPoints;

+ (BOOL)
injectCode:(nonnull NSData *)codeData
intoAddress:(ZGMemoryAddress)allocatedAddress
hookingIntoOriginalInstructions:(nonnull NSArray *)hookedInstructions
process:(nonnull ZGProcess *)process
breakPoints:(nonnull NSArray *)breakPoints
undoManager:(nullable NSUndoManager *)undoManager
error:(NSError  * __nullable * __nullable)error;

@end
