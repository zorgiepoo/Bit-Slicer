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

#import "ZGFunctionTypes.h"

BOOL ZGIsFunctionTypeStore(ZGFunctionType functionType)
{
	BOOL isFunctionTypeStore;
	
	switch (functionType)
	{
		case ZGEqualsStored:
		case ZGNotEqualsStored:
		case ZGGreaterThanStored:
		case ZGLessThanStored:
		case ZGEqualsStoredLinear:
		case ZGNotEqualsStoredLinear:
		case ZGGreaterThanStoredLinear:
		case ZGLessThanStoredLinear:
			isFunctionTypeStore = YES;
			break;
		case ZGEquals:
		case ZGNotEquals:
		case ZGGreaterThan:
		case ZGLessThan:
			isFunctionTypeStore = NO;
	}
	
	return isFunctionTypeStore;
}

BOOL ZGIsFunctionTypeLinear(ZGFunctionType functionType)
{
	BOOL isFunctionTypeLinear;
	
	switch (functionType)
	{
		case ZGEqualsStoredLinear:
		case ZGNotEqualsStoredLinear:
		case ZGGreaterThanStoredLinear:
		case ZGLessThanStoredLinear:
			isFunctionTypeLinear = YES;
			break;
		case ZGEquals:
		case ZGNotEquals:
		case ZGGreaterThan:
		case ZGLessThan:
		case ZGEqualsStored:
		case ZGNotEqualsStored:
		case ZGGreaterThanStored:
		case ZGLessThanStored:
			isFunctionTypeLinear = NO;
	}
	
	return isFunctionTypeLinear;
}

BOOL ZGIsFunctionTypeEquals(ZGFunctionType functionType)
{
	BOOL isFunctionTypeEquals;
	
	switch (functionType)
	{
		case ZGEquals:
		case ZGEqualsStored:
		case ZGEqualsStoredLinear:
			isFunctionTypeEquals = YES;
			break;
		case ZGNotEquals:
		case ZGNotEqualsStored:
		case ZGNotEqualsStoredLinear:
		case ZGGreaterThan:
		case ZGLessThan:
		case ZGGreaterThanStored:
		case ZGGreaterThanStoredLinear:
		case ZGLessThanStored:
		case ZGLessThanStoredLinear:
			isFunctionTypeEquals = NO;
	}
	
	return isFunctionTypeEquals;
}

BOOL ZGIsFunctionTypeNotEquals(ZGFunctionType functionType)
{
	BOOL isFunctionTypeNotEquals;
	
	switch (functionType)
	{
		case ZGNotEquals:
		case ZGNotEqualsStored:
		case ZGNotEqualsStoredLinear:
			isFunctionTypeNotEquals = YES;
			break;
		case ZGEquals:
		case ZGEqualsStored:
		case ZGEqualsStoredLinear:
		case ZGGreaterThan:
		case ZGGreaterThanStored:
		case ZGGreaterThanStoredLinear:
		case ZGLessThan:
		case ZGLessThanStored:
		case ZGLessThanStoredLinear:
			isFunctionTypeNotEquals = NO;
	}
	
	return isFunctionTypeNotEquals;
}

BOOL ZGIsFunctionTypeGreaterThan(ZGFunctionType functionType)
{
	BOOL isFunctionTypeGreaterThan;
	
	switch (functionType)
	{
		case ZGGreaterThan:
		case ZGGreaterThanStored:
		case ZGGreaterThanStoredLinear:
			isFunctionTypeGreaterThan = YES;
			break;
		case ZGEquals:
		case ZGEqualsStored:
		case ZGEqualsStoredLinear:
		case ZGNotEquals:
		case ZGNotEqualsStored:
		case ZGNotEqualsStoredLinear:
		case ZGLessThan:
		case ZGLessThanStored:
		case ZGLessThanStoredLinear:
			isFunctionTypeGreaterThan = NO;
	}
	
	return isFunctionTypeGreaterThan;
}

BOOL ZGIsFunctionTypeLessThan(ZGFunctionType functionType)
{
	BOOL isFunctionTypeLessThan;
	
	switch (functionType)
	{
		case ZGLessThan:
		case ZGLessThanStored:
		case ZGLessThanStoredLinear:
			isFunctionTypeLessThan = YES;
			break;
		case ZGEquals:
		case ZGNotEquals:
		case ZGNotEqualsStoredLinear:
		case ZGNotEqualsStored:
		case ZGEqualsStored:
		case ZGEqualsStoredLinear:
		case ZGGreaterThan:
		case ZGGreaterThanStored:
		case ZGGreaterThanStoredLinear:
			isFunctionTypeLessThan = NO;
	}
	
	return isFunctionTypeLessThan;
}

BOOL ZGSupportsSwappingBeforeSearch(ZGFunctionType functionType, ZGVariableType dataType)
{
	return (functionType == ZGEquals || functionType == ZGNotEquals) && (dataType == ZGInt16 || dataType == ZGInt32 || dataType == ZGInt64 || dataType == ZGPointer || dataType == ZGString16);
}

BOOL ZGSupportsEndianness(ZGVariableType dataType)
{
	BOOL supportsEndianness;
	switch (dataType)
	{
		case ZGInt8:
		case ZGString8:
		case ZGByteArray:
		case ZGScript:
			supportsEndianness = NO;
			break;
		case ZGInt16:
		case ZGInt32:
		case ZGInt64:
		case ZGFloat:
		case ZGDouble:
		case ZGString16:
		case ZGPointer:
			supportsEndianness = YES;
			break;
	}
	return supportsEndianness;
}
