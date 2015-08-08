/*
 * Copyright (c) 2015 Mayur Pawashe
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

#import "ZGVariableDataInfo.h"

BOOL ZGIsNumericalDataType(ZGVariableType dataType)
{
	return (dataType != ZGByteArray && dataType != ZGString8 && dataType != ZGString16);
}

ZGMemorySize ZGDataSizeFromNumericalDataType(BOOL isProcess64Bit, ZGVariableType dataType)
{
	ZGMemorySize dataSize;
	switch (dataType)
	{
		case ZGInt8:
			dataSize = 1;
			break;
		case ZGInt16:
			dataSize = 2;
			break;
		case ZGInt32:
		case ZGFloat:
			dataSize = 4;
			break;
		case ZGInt64:
		case ZGDouble:
			dataSize = 8;
			break;
		case ZGPointer:
			dataSize = isProcess64Bit ? 8 : 4;
			break;
		case ZGString8:
		case ZGString16:
		case ZGByteArray:
		case ZGScript:
			dataSize = 0;
			break;
	}
	return dataSize;
}

ZGMemorySize ZGDataAlignment(BOOL isProcess64Bit, ZGVariableType dataType, ZGMemorySize dataSize)
{
	ZGMemorySize dataAlignment;
	
	if (dataType == ZGString8 || dataType == ZGByteArray)
	{
		dataAlignment = sizeof(int8_t);
	}
	else if (dataType == ZGString16)
	{
		dataAlignment = sizeof(int16_t);
	}
	else
	{
		// doubles and 64-bit integers are on 4 byte boundaries only in 32-bit processes, while every other integral type is on its own size of boundary
		dataAlignment = (!isProcess64Bit && dataSize == sizeof(int64_t)) ? sizeof(int32_t) : dataSize;
	}
	
	return dataAlignment;
}
