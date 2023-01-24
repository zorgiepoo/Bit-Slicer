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

#import "ZGVariable.h"
#import "ZGLabel.h"
#import "ZGVariableTypes.h"
#import "NSStringAdditions.h"
#import "ZGNullability.h"

#define ZGNameKey @"ZGNameKey"
#define ZGVariableKey @"ZGVariableKey"

@implementation ZGLabel
{
	NSString * _name;
	ZGVariable * _variable;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder
	 encodeObject:_name
	 forKey:ZGNameKey];

	[coder
	 encodeObject:_variable
	 forKey:ZGVariableKey];
}

- (id)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	if (self != nil)
	{
		NSString *_name = [coder decodeObjectOfClass:[NSString class] forKey:ZGNameKey];
		ZGVariable *_variable = [coder decodeObjectOfClass:[ZGVariable class] forKey:ZGVariableKey];
		
		if(_name == NULL || _variable == NULL) {
			return NULL;
		}
	}
	
	return self;
}

- (ZGMemoryAddress)address
{
	return _variable.address;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}

- (id)copyWithZone:(NSZone *)__unused zone
{
	NSData *archivedData = [NSKeyedArchiver archivedDataWithRootObject:self];
	return ZGUnwrapNullableObject([NSKeyedUnarchiver unarchiveObjectWithData:archivedData]);
}

- (id)initWithName:(NSString *)name address:(ZGMemoryAddress)address qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize
{
	if ((self = [super init]))
	{
		_name = name;
		_variable = [[ZGVariable alloc] initWithValue:NULL size:pointerSize address:address type:ZGPointer qualifier:qualifier pointerSize:pointerSize];
	}
}

- (id)initWithName:(NSString *)name variable:(ZGVariable *)variable pointerSize:(ZGMemorySize)pointerSize
{
	if ((self = [super init]))
	{
		_name = name;
		_variable = [[ZGVariable alloc] initWithValue:NULL size:pointerSize address:variable.address type:ZGPointer qualifier:variable.qualifier pointerSize:pointerSize];
		
		[_variable setAddressFormula:variable.addressFormula];
	}
}

@end
