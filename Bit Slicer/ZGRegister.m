/*
 * Created by Mayur Pawashe on 1/16/13.
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

#import "ZGRegister.h"
#import "ZGVariable.h"

@interface ZGRegister ()

@property (nonatomic) void *rawValue;

@property (nonatomic, assign) ZGMemorySize size;
@property (nonatomic, assign) ZGMemorySize internalSize;
@property (nonatomic, assign) ZGRegisterType registerType;

@end

@implementation ZGRegister

- (id)initWithRegisterType:(ZGRegisterType)registerType variable:(ZGVariable *)variable pointerSize:(ZGMemorySize)pointerSize
{
	self = [super init];
	if (self)
	{
		self.registerType = registerType;
		self.size = variable.size;
		// If variable's type is changed, ensure there is enough space for pointer size
		self.internalSize = MAX(pointerSize, self.size);
		self.variable = variable;
	}
	return self;
}

- (void)dealloc
{
	self.variable = nil;
}

- (void)setVariable:(ZGVariable *)variable
{
	_variable = variable;
	
	free(self.rawValue);
	
	if (_variable != nil)
	{
		self.rawValue = calloc(1, self.internalSize);
		memcpy(self.rawValue, _variable.rawValue, self.size);
	}
}

@end
