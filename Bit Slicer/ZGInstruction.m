/*
 * Created by Mayur Pawashe on 12/27/12.
 *
 * Copyright (c) 2012 zgcoder
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
#import "ZGUtilities.h"

@interface ZGInstruction ()

@property (nonatomic) int mnemonic;
@property (nonatomic, copy) NSString *text;
@property (nonatomic) ZGVariable *variable;

@end

@implementation ZGInstruction

- (id)initWithVariable:(ZGVariable *)variable text:(NSString *)text mnemonic:(int)mnemonic
{
	self = [super init];
	if (self != nil)
	{
		self.variable = variable;
		self.text = text;
		self.mnemonic = mnemonic;
	}
	return self;
}

- (BOOL)isEqual:(id)object
{
	if (![object isKindOfClass:[ZGInstruction class]])
	{
		return NO;
	}
	
	ZGInstruction *instruction = object;
	
	if (self.variable.address == instruction.variable.address && (self.variable.rawValue == instruction.variable.rawValue || (self.variable.size == instruction.variable.size && memcmp(self.variable.rawValue, instruction.variable.rawValue, self.variable.size) == 0)))
	{
		return YES;
	}
	
	return NO;
}

@end
