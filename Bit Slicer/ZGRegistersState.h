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
 * ZGRegistersState - Thread Register State Management
 * =================================================
 *
 * This module encapsulates the complete register state of a thread,
 * including both general purpose and vector registers.
 *
 * Component Interactions:
 * ---------------------
 *
 *                                 +----------------+
 *                                 | Breakpoint Hit |
 *                                 | or Debug Event |
 *                                 +--------+-------+
 *                                          |
 *                                          | (Suspend Thread)
 *                                          v
 *  +----------------+            +-------------------+
 *  | ZGThreadStates |----------->| Raw Thread State  |
 *  | (low-level API)|            | (CPU Registers)   |
 *  +----------------+            +-------------------+
 *          ^                              |
 *          |                              | (Encapsulate)
 *          |                              v
 *          |                     +-------------------+
 *          |                     | ZGRegistersState  |
 *          |                     | (OO Container)    |
 *          |                     +-------------------+
 *          |                              |
 *          |                              | (Use in)
 *          |                              v
 *          |                     +-------------------+
 *          |                     | Debug Operations: |
 *          |                     | - Backtrace       |
 *          |                     | - Register View   |
 *          |                     | - Modify Regs     |
 *          |                     +-------------------+
 *          |                              |
 *          |                              | (Apply Changes)
 *          +--------------<---------------+
 *
 * Register State Components:
 * ------------------------
 *
 *  +-------------------------------------+
 *  |          ZGRegistersState           |
 *  |-------------------------------------|
 *  | +-------------------------------+   |
 *  | | General Purpose Thread State  |   |
 *  | |-------------------------------|   |
 *  | | - Program Counter (PC/IP)     |   |
 *  | | - Stack Pointer (SP)          |   |
 *  | | - Base/Frame Pointer (BP/FP)  |   |
 *  | | - General Registers           |   |
 *  | | - Flags Register              |   |
 *  | +-------------------------------+   |
 *  |                                     |
 *  | +-------------------------------+   |
 *  | | Vector Thread State           |   |
 *  | |-------------------------------|   |
 *  | | - SIMD Registers (AVX/NEON)   |   |
 *  | | - Floating Point Registers    |   |
 *  | +-------------------------------+   |
 *  +-------------------------------------+
 *
 * Cross-Component Workflow:
 * -----------------------
 * 1. Breakpoint triggers -> Thread suspended
 * 2. ZGThreadStates retrieves raw register values
 * 3. ZGRegistersState encapsulates these values
 * 4. ZGBacktrace uses register values to generate stack trace
 * 5. ZGRegister objects provide UI access to register values
 * 6. Modified registers are written back via ZGThreadStates
 * 7. Thread resumes execution with updated state
 */

#import <Foundation/Foundation.h>
#import "ZGMemoryTypes.h"
#import "ZGThreadStates.h"
#import "ZGProcessTypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZGRegistersState : NSObject

- (id)initWithGeneralPurposeThreadState:(zg_thread_state_t)generalPurposeThreadState vectorState:(zg_vector_state_t)vectorState hasVectorState:(BOOL)hasVectorState hasAVXSupport:(BOOL)hasAVXSupport processType:(ZGProcessType)processType;

@property (nonatomic) zg_thread_state_t generalPurposeThreadState;
@property (nonatomic) zg_vector_state_t vectorState;

@property (nonatomic, readonly) BOOL hasVectorState;
@property (nonatomic, readonly) BOOL hasAVXSupport;
@property (nonatomic, readonly) ZGProcessType processType;

@end

NS_ASSUME_NONNULL_END
