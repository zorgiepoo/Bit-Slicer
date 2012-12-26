/*
 * Created by Mayur Pawashe on 8/18/10.
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

#import "ZGVariable.h"
#import "ZGVirtualMemory.h"
#import "ZGSearchData.h"

@class ZGSearchData;

typedef enum
{
	// Regular comparisons
	ZGEquals = 0,
	ZGNotEquals,
	ZGGreaterThan,
	ZGLessThan,
	// Stored comparisons
	ZGEqualsStored,
	ZGNotEqualsStored,
	ZGGreaterThanStored,
	ZGLessThanStored,
	// Special Stored comparisons
	ZGEqualsStoredPlus,
	ZGNotEqualsStoredPlus,
} ZGFunctionType;

inline BOOL equalFunction(ZGSearchData * __unsafe_unretained searchData, const void *variableValue, const void *compareValue, ZGVariableType type, ZGMemorySize size)
{
	BOOL isEqual = NO;
	
	switch (type)
	{
		case ZGPointer:
			if (size == sizeof(int32_t))
			{
				goto INT32_EQUAL_TO;
			}
			else if (size == sizeof(int64_t))
			{
				goto INT64_EQUAL_TO;
			}
			break;
		case ZGInt8:
			isEqual = *((int8_t *)variableValue) == *((int8_t *)compareValue);
			break;
		case ZGInt16:
			isEqual = *((int16_t *)variableValue) == *((int16_t *)compareValue);
			break;
		case ZGInt32:
		INT32_EQUAL_TO:
			isEqual = *((int32_t *)variableValue) == *((int32_t *)compareValue);
			break;
		case ZGInt64:
		INT64_EQUAL_TO:
			isEqual = *((int64_t *)variableValue) == *((int64_t *)compareValue);
			break;
		case ZGFloat:
			isEqual = ABS(*((float *)variableValue) - *((float *)compareValue)) <= searchData->_epsilon;
			break;
		case ZGDouble:
			isEqual = ABS(*((double *)variableValue) - *((double *)compareValue)) <= searchData->_epsilon;
			break;
		case ZGUTF8String:
			// size - 1 to not include for the NULL character,
			// or size to include for the NULL terminator
			if (searchData->_shouldIgnoreStringCase)
			{
				isEqual = (strncasecmp(variableValue, compareValue, (size_t)size) == 0);
			}
			else
			{
				isEqual = (memcmp(variableValue, compareValue, (size_t)size) == 0);
			}
			break;
		case ZGUTF16String:
			if (searchData->_shouldIncludeNullTerminator)
			{
				size -= sizeof(unichar);
				// Check for the existing null terminator
				if (*((unichar *)(variableValue + size)) != 0)
				{
					break;
				}
			}
			
			if (searchData->_shouldIgnoreStringCase)
			{
				UCCompareText(searchData->_collator, variableValue, ((size_t)size) / sizeof(unichar), compareValue, ((size_t)size) / sizeof(unichar), (Boolean *)&isEqual, NULL);
			}
			else
			{
				isEqual = (memcmp(variableValue, compareValue, (size_t)size) == 0);
			}
			break;
		case ZGByteArray:
			if (!searchData->_byteArrayFlags)
			{
				isEqual = (memcmp(variableValue, compareValue, (size_t)size) == 0);
			}
			else
			{
				const unsigned char *variableValueArray = variableValue;
				const unsigned char *compareValueArray = compareValue;
				
				isEqual = YES;
				
				unsigned int byteIndex;
				for (byteIndex = 0; byteIndex < size; byteIndex++)
				{
					if (!(searchData->_byteArrayFlags[byteIndex] & 0xF0) && ((variableValueArray[byteIndex] & 0xF0) != (compareValueArray[byteIndex] & 0xF0)))
					{
						isEqual = NO;
						break;
					}
					
					if (!(searchData->_byteArrayFlags[byteIndex] & 0x0F) && ((variableValueArray[byteIndex] & 0x0F) != (compareValueArray[byteIndex] & 0x0F)))
					{
						isEqual = NO;
						break;
					}
				}
			}
			break;
	}
	
	return isEqual;
}

inline BOOL lessThanFunction(ZGSearchData * __unsafe_unretained searchData, const void *variableValue, const void *compareValue, ZGVariableType type, ZGMemorySize size)
{
	BOOL isLessThan = NO;
	
	switch (type)
	{
		case ZGPointer:
			if (size == sizeof(int32_t))
			{
				goto INT32_LESS_THAN;
			}
			else if (size == sizeof(int64_t))
			{
				goto INT64_LESS_THAN;
			}
			break;
		case ZGInt8:
			isLessThan = *((int8_t *)variableValue) < *((int8_t *)compareValue);
			if (searchData->_rangeValue && isLessThan)
			{
				isLessThan = *((int8_t *)variableValue) > *((int8_t *)searchData->_rangeValue);
			}
			break;
		case ZGInt16:
			isLessThan = *((int16_t *)variableValue) < *((int16_t *)compareValue);
			if (searchData->_rangeValue && isLessThan)
			{
				isLessThan = *((int16_t *)variableValue) > *((int16_t *)searchData->_rangeValue);
			}
			break;
		case ZGInt32:
		INT32_LESS_THAN:
			isLessThan = *((int32_t *)variableValue) < *((int32_t *)compareValue);
			if (searchData->_rangeValue && isLessThan)
			{
				isLessThan = *((int32_t *)variableValue) > *((int32_t *)searchData->_rangeValue);
			}
			break;
		case ZGInt64:
		INT64_LESS_THAN:
			isLessThan = *((int64_t *)variableValue) < *((int64_t *)compareValue);
			if (searchData->_rangeValue && isLessThan)
			{
				isLessThan = *((int64_t *)variableValue) > *((int64_t *)searchData->_rangeValue);
			}
			break;
		case ZGFloat:
			isLessThan = *((float *)variableValue) < *((float *)compareValue);
			if (searchData->_rangeValue && isLessThan)
			{
				isLessThan = *((float *)variableValue) > *((float *)searchData->_rangeValue);
			}
			break;
		case ZGDouble:
			isLessThan = *((double *)variableValue) < *((double *)compareValue);
			if (searchData->_rangeValue && isLessThan)
			{
				isLessThan = *((double *)variableValue) > *((double *)searchData->_rangeValue);
			}
			break;
		default:
			break;
	}
	
	return isLessThan;
}

inline BOOL greaterThanFunction(ZGSearchData * __unsafe_unretained searchData, const void *variableValue, const void *compareValue, ZGVariableType type, ZGMemorySize size)
{
	BOOL isGreaterThan = NO;
	
	switch (type)
	{
		case ZGPointer:
			if (size == sizeof(int32_t))
			{
				goto INT32_GREATER_THAN;
			}
			else if (size == sizeof(int64_t))
			{
				goto INT64_GREATER_THAN;
			}
			break;
		case ZGInt8:
			isGreaterThan = *((int8_t *)variableValue) > *((int8_t *)compareValue);
			if (searchData->_rangeValue && isGreaterThan)
			{
				isGreaterThan = *((int8_t *)variableValue) < *((int8_t *)searchData->_rangeValue);
			}
			break;
		case ZGInt16:
			isGreaterThan = *((int16_t *)variableValue) > *((int16_t *)compareValue);
			if (searchData->_rangeValue && isGreaterThan)
			{
				isGreaterThan = *((int16_t *)variableValue) < *((int16_t *)searchData->_rangeValue);
			}
			break;
		case ZGInt32:
		INT32_GREATER_THAN:
			isGreaterThan = *((int32_t *)variableValue) > *((int32_t *)compareValue);
			if (searchData->_rangeValue && isGreaterThan)
			{
				isGreaterThan = *((int32_t *)variableValue) < *((int32_t *)searchData->_rangeValue);
			}
			break;
		case ZGInt64:
		INT64_GREATER_THAN:
			isGreaterThan = *((int64_t *)variableValue) > *((int64_t *)compareValue);
			if (searchData->_rangeValue && isGreaterThan)
			{
				isGreaterThan = *((int64_t *)variableValue) < *((int64_t *)searchData->_rangeValue);
			}
			break;
		case ZGFloat:
			isGreaterThan = *((float *)variableValue) > *((float *)compareValue);
			if (searchData->_rangeValue && isGreaterThan)
			{
				isGreaterThan = *((float *)variableValue) < *((float *)searchData->_rangeValue);
			}
			break;
		case ZGDouble:
			isGreaterThan = *((double *)variableValue) > *((double *)compareValue);
			if (searchData->_rangeValue && isGreaterThan)
			{
				isGreaterThan = *((double *)variableValue) < *((double *)searchData->_rangeValue);
			}
			break;
		default:
			break;
	}
	
	return isGreaterThan;
}

inline BOOL notEqualFunction(ZGSearchData * __unsafe_unretained searchData, const void *variableValue, const void *compareValue, ZGVariableType type, ZGMemorySize size)
{
	return !equalFunction(searchData, variableValue, compareValue, type, size);
}

inline BOOL equalPlusFunction(ZGSearchData * __unsafe_unretained searchData, const void *variableValue, const void *compareValue, ZGVariableType type, ZGMemorySize size)
{
	switch (type)
	{
		case ZGPointer:
			if (size == sizeof(int32_t))
			{
				goto INT32_EQUAL_TO_PLUS;
			}
			else if (size == sizeof(int64_t))
			{
				goto INT64_EQUAL_TO_PLUS;
			}
			break;
		case ZGInt8:
		{
			int8_t newCompareValue = *((int8_t *)compareValue) + *((int8_t *)searchData->_compareOffset);
			return equalFunction(searchData, variableValue, &newCompareValue, type, size);
		}
		case ZGInt16:
		{
			int16_t newCompareValue = *((int16_t *)compareValue) + *((int16_t *)searchData->_compareOffset);
			return equalFunction(searchData, variableValue, &newCompareValue, type, size);
		}
		case ZGInt32:
		INT32_EQUAL_TO_PLUS:
		{
			int32_t newCompareValue = *((int32_t *)compareValue) + *((int32_t *)searchData->_compareOffset);
			return equalFunction(searchData, variableValue, &newCompareValue, type, size);
		}
		case ZGInt64:
		INT64_EQUAL_TO_PLUS:
		{
			int64_t newCompareValue = *((int64_t *)compareValue) + *((int64_t *)searchData->_compareOffset);
			return equalFunction(searchData, variableValue, &newCompareValue, type, size);
		}
		case ZGFloat:
		{
			float newCompareValue = *((float *)compareValue) + *((float *)searchData->_compareOffset);
			return equalFunction(searchData, variableValue, &newCompareValue, type, size);
		}
		case ZGDouble:
		{
			double newCompareValue = *((double *)compareValue) + *((double *)searchData->_compareOffset);
			return equalFunction(searchData, variableValue, &newCompareValue, type, size);
		}
		default:
			break;
	}
	
	return NO;
}

inline BOOL notEqualPlusFunction(ZGSearchData * __unsafe_unretained searchData, const void *variableValue, const void *compareValue, ZGVariableType type, ZGMemorySize size)
{
    return !equalPlusFunction(searchData, variableValue, compareValue, type, size);
}

