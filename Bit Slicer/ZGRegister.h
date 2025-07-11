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

/*
 * ZGRegister - CPU Register Management
 * ===================================
 *
 * This module provides an abstraction for CPU registers in the debugger.
 * It encapsulates register values and their metadata, supporting both
 * general purpose and vector (SIMD) registers.
 *
 * Register Hierarchy and Relationships:
 * -----------------------------------
 *
 *                   +----------------+
 *                   | ZGThreadStates |
 *                   +--------+-------+
 *                            |
 *                            | (provides raw register data)
 *                            v
 *  +----------------+    +-------------------+    +------------------+
 *  | ZGRegisterEntry|<---| ZGRegisterEntries |    | ZGRegistersState |
 *  | (struct)       |    | (collection)      |    | (thread context) |
 *  +-------+--------+    +-------------------+    +------------------+
 *          |                      ^                        ^
 *          | (converted to)       |                        |
 *          v                      |                        |
 *  +----------------+             |                        |
 *  | ZGVariable     |-------------+                        |
 *  | (data value)   |                                      |
 *  +-------+--------+                                      |
 *          |                                               |
 *          | (wrapped by)                                  |
 *          v                                               |
 *  +----------------+                                      |
 *  | ZGRegister     |--------------------------------------+
 *  | (UI object)    |           (references)
 *  +----------------+
 *
 * Register Types:
 * -------------
 * - General Purpose: Program counter, stack pointer, etc.
 * - Vector: SIMD registers (AVX, NEON)
 *
 * Register Flow During Debugging:
 * -----------------------------
 * 1. Thread is suspended (e.g., at breakpoint)
 * 2. ZGThreadStates retrieves raw register values
 * 3. ZGRegisterEntries converts to named entries
 * 4. ZGRegistersState maintains the context
 * 5. ZGRegister objects provide access to individual registers
 * 6. Modified registers are written back via ZGThreadStates
 */

#import <Foundation/Foundation.h>
#import "ZGVirtualMemory.h"

@class ZGVariable;

typedef NS_ENUM(uint8_t, ZGRegisterType)
{
	ZGRegisterGeneralPurpose,
	ZGRegisterVector
};

NS_ASSUME_NONNULL_BEGIN

@interface ZGRegister : NSObject

@property (nonatomic) ZGVariable *variable;

@property (nonatomic, readonly) void *rawValue;

@property (nonatomic, readonly) ZGMemorySize size;
@property (nonatomic, readonly) ZGRegisterType registerType;

- (id)initWithRegisterType:(ZGRegisterType)registerType variable:(ZGVariable *)variable;

@end

NS_ASSUME_NONNULL_END
