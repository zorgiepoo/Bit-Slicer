/*
 * Created by Mayur Pawashe on 1/12/13.
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

#import "ZGDisassemblerObject.h"
#import "ZGVariable.h"
#import "ZGBreakPoint.h"
#import "ZGProcess.h"

@interface ZGDisassemblerObject ()

@property (nonatomic, readwrite) ud_t *object;
@property (nonatomic, readwrite) void *bytes;

@end

@implementation ZGDisassemblerObject

- (id)initWithProcess:(ZGProcess *)process address:(ZGMemoryAddress)address size:(ZGMemorySize)size bytes:(const void *)bytes breakPoints:(NSArray *)breakPoints
{
	self = [super init];
	if (self)
	{
		self.bytes = malloc(size);
		memcpy(self.bytes, bytes, size);
		
		for (ZGBreakPoint *breakPoint in breakPoints)
		{
			if (breakPoint.type == ZGBreakPointInstruction && breakPoint.task == process.processTask && breakPoint.variable.address >= address && breakPoint.variable.address < address + size)
			{
				memcpy(self.bytes + (breakPoint.variable.address - address), breakPoint.variable.value, sizeof(uint8_t));
			}
		}
		
		self.object = malloc(sizeof(ud_t));
		ud_init(self.object);
		ud_set_input_buffer(self.object, self.bytes, size);
		ud_set_mode(self.object, process.pointerSize * 8);
		ud_set_syntax(self.object, UD_SYN_INTEL);
		ud_set_pc(self.object, address);
	}
	return self;
}

- (void)dealloc
{
	free(self.object); self.object = NULL;
	free(self.bytes); self.bytes = NULL;
}

- (void)enumerateWithBlock:(void (^)(ZGMemoryAddress, ZGMemorySize, ud_mnemonic_code_t, NSString *, BOOL *))callback
{
	BOOL stop = NO;
	while (ud_disassemble(self.object) > 0)
	{
		callback(ud_insn_off(self.object), ud_insn_len(self.object), self.object->mnemonic, @(ud_insn_asm(self.object)), &stop);
		if (stop) break;
	}
}

@end
