/*
 * Copyright (c) 2026 Mayur Pawashe
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
#import "ZGCapstoneDisassemblerObject.h"
#import "ZGInstruction.h"
#import "ZGVariable.h"

@interface DisassemblerTest : XCTestCase

@end

@implementation DisassemblerTest

- (NSArray<ZGInstruction *> *)disassembleARM64Bytes:(const void *)bytes size:(ZGMemorySize)size address:(ZGMemoryAddress)address
{
	ZGCapstoneDisassemblerObject *disassembler = [[ZGCapstoneDisassemblerObject alloc] initWithBytes:bytes address:address size:size pointerSize:sizeof(int64_t) isARM64:YES];
	return [disassembler readInstructions];
}

// Regression test for issue #112: the ARMv8.3 (FEAT_LRCPC) load-acquire
// instruction LDAPRB was emitted as raw bytes in the debugger view with older
// versions of Capstone. Ensure it disassembles to a proper mnemonic so it does
// not silently regress on future Capstone updates.
- (void)testARM64LoadAcquireRCpcByte
{
	// LDAPRB w9, [x9]  ->  29 C1 BF 38  (encoding 0x38BFC129)
	uint8_t bytes[] = {0x29, 0xC1, 0xBF, 0x38};
	ZGMemoryAddress address = 0x100039970;

	NSArray<ZGInstruction *> *instructions = [self disassembleARM64Bytes:bytes size:sizeof(bytes) address:address];

	XCTAssertEqual(instructions.count, (NSUInteger)1);

	ZGInstruction *instruction = instructions.firstObject;
	XCTAssertEqualObjects(instruction.text, @"ldaprb w9, [x9]");
	XCTAssertEqual(instruction.variable.address, address);
	XCTAssertEqual(instruction.variable.size, (ZGMemorySize)sizeof(bytes));
}

@end
