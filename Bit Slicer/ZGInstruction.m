/*
 * Copyright (c) 2012 Mayur Pawashe
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

#import "ZGInstruction.h"
#import "ZGVariable.h"

@implementation ZGInstruction

- (id)initWithVariable:(ZGVariable *)variable text:(NSString *)text mnemonic:(int)mnemonic
{
	self = [super init];
	if (self != nil)
	{
		_variable = variable;
		_text = [text copy];
		_mnemonic = mnemonic;
	}
	return self;
}

- (BOOL)isEqual:(id)object
{
	if (![(id<NSObject>)object isKindOfClass:[ZGInstruction class]])
	{
		return NO;
	}
	
	ZGInstruction *instruction = object;
	
	if (_variable.address == instruction.variable.address && (_variable.rawValue == instruction.variable.rawValue || (_variable.size == instruction.variable.size && memcmp(_variable.rawValue, instruction.variable.rawValue, _variable.size) == 0)))
	{
		return YES;
	}
	
	return NO;
}

- (NSUInteger)hash
{
	return [[NSString stringWithFormat:@"%llu_%llu", _variable.address, _variable.size] hash];
}

@end
