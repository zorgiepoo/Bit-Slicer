/*
 * This file is part of Bit Slicer.
 *
 * Bit Slicer is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 
 * Bit Slicer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 
 * You should have received a copy of the GNU General Public License
 * along with Bit Slicer.  If not, see <http://www.gnu.org/licenses/>.
 * 
 * Created by Mayur Pawashe on 8/18/10.
 * Copyright 2010 zgcoder. All rights reserved.
 */

#import "ZGComparisonFunctions.h"

inline BOOL lessThanFunction(ZGSearchData *searchData, const void *variableValue, const void *compareValue, ZGVariableType type, ZGMemorySize size)
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
			if (searchData->rangeValue && isLessThan)
			{
				isLessThan = *((int8_t *)variableValue) > *((int8_t *)searchData->rangeValue);
			}
			break;
		case ZGInt16:
			isLessThan = *((int16_t *)variableValue) < *((int16_t *)compareValue);
			if (searchData->rangeValue && isLessThan)
			{
				isLessThan = *((int16_t *)variableValue) > *((int16_t *)searchData->rangeValue);
			}
			break;
		case ZGInt32:
		INT32_LESS_THAN:
			isLessThan = *((int32_t *)variableValue) < *((int32_t *)compareValue);
			if (searchData->rangeValue && isLessThan)
			{
				isLessThan = *((int32_t *)variableValue) > *((int32_t *)searchData->rangeValue);
			}
			break;
		case ZGInt64:
		INT64_LESS_THAN:
			isLessThan = *((int64_t *)variableValue) < *((int64_t *)compareValue);
			if (searchData->rangeValue && isLessThan)
			{
				isLessThan = *((int64_t *)variableValue) > *((int64_t *)searchData->rangeValue);
			}
			break;
		case ZGFloat:
			isLessThan = *((float *)variableValue) < *((float *)compareValue);
			if (searchData->rangeValue && isLessThan)
			{
				isLessThan = *((float *)variableValue) > *((float *)searchData->rangeValue);
			}
			break;
		case ZGDouble:
			isLessThan = *((double *)variableValue) < *((double *)compareValue);
			if (searchData->rangeValue && isLessThan)
			{
				isLessThan = *((double *)variableValue) > *((double *)searchData->rangeValue);
			}
			break;
		default:
			break;
	}
	
	return isLessThan;
}

inline BOOL greaterThanFunction(ZGSearchData *searchData, const void *variableValue, const void *compareValue, ZGVariableType type, ZGMemorySize size)
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
			if (searchData->rangeValue && isGreaterThan)
			{
				isGreaterThan = *((int8_t *)variableValue) < *((int8_t *)searchData->rangeValue);
			}
			break;
		case ZGInt16:
			isGreaterThan = *((int16_t *)variableValue) > *((int16_t *)compareValue);
			if (searchData->rangeValue && isGreaterThan)
			{
				isGreaterThan = *((int16_t *)variableValue) < *((int16_t *)searchData->rangeValue);
			}
			break;
		case ZGInt32:
		INT32_GREATER_THAN:
			isGreaterThan = *((int32_t *)variableValue) > *((int32_t *)compareValue);
			if (searchData->rangeValue && isGreaterThan)
			{
				isGreaterThan = *((int32_t *)variableValue) < *((int32_t *)searchData->rangeValue);
			}
			break;
		case ZGInt64:
		INT64_GREATER_THAN:
			isGreaterThan = *((int64_t *)variableValue) > *((int64_t *)compareValue);
			if (searchData->rangeValue && isGreaterThan)
			{
				isGreaterThan = *((int64_t *)variableValue) < *((int64_t *)searchData->rangeValue);
			}
			break;
		case ZGFloat:
			isGreaterThan = *((float *)variableValue) > *((float *)compareValue);
			if (searchData->rangeValue && isGreaterThan)
			{
				isGreaterThan = *((float *)variableValue) < *((float *)searchData->rangeValue);
			}
			break;
		case ZGDouble:
			isGreaterThan = *((double *)variableValue) > *((double *)compareValue);
			if (searchData->rangeValue && isGreaterThan)
			{
				isGreaterThan = *((double *)variableValue) < *((double *)searchData->rangeValue);
			}
			break;
		default:
			break;
	}
	
	return isGreaterThan;
}

inline BOOL equalFunction(ZGSearchData *searchData, const void *variableValue, const void *compareValue, ZGVariableType type, ZGMemorySize size)
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
			isEqual = ABS(*((float *)variableValue) - *((float *)compareValue)) <= searchData->epsilon;
			break;
		case ZGDouble:
			isEqual = ABS(*((double *)variableValue) - *((double *)compareValue)) <= searchData->epsilon;
			break;
		case ZGUTF8String:
			// size - 1 to not include for the NULL character,
			// or size to include for the NULL terminator
			if (searchData->shouldIgnoreStringCase)
			{
				isEqual = (strncasecmp(variableValue, compareValue, (size_t)(size - !searchData->shouldIncludeNullTerminator)) == 0);
			}
			else
			{
				isEqual = (memcmp(variableValue, compareValue, (size_t)(size - !searchData->shouldIncludeNullTerminator)) == 0);
			}
			break;
		case ZGUTF16String:
			if (searchData->shouldIncludeNullTerminator)
			{
				size -= sizeof(unichar);
				// Check for the existing null terminator
				if (*((unichar *)(variableValue + size)) != 0)
				{
					break;
				}
			}
			
			if (searchData->shouldIgnoreStringCase)
			{
				UCCompareText(searchData->collator, variableValue, ((size_t)size) / sizeof(unichar), compareValue, ((size_t)size) / sizeof(unichar), (Boolean *)&isEqual, NULL);
			}
			else
			{
				isEqual = (memcmp(variableValue, compareValue, (size_t)size) == 0);
			}
			break;
		case ZGByteArray:
			if (!searchData->byteArrayFlags)
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
					if (!(searchData->byteArrayFlags[byteIndex] & 0xF0) && ((variableValueArray[byteIndex] & 0xF0) != (compareValueArray[byteIndex] & 0xF0)))
					{
						isEqual = NO;
						break;
					}
					
					if (!(searchData->byteArrayFlags[byteIndex] & 0x0F) && ((variableValueArray[byteIndex] & 0x0F) != (compareValueArray[byteIndex] & 0x0F)))
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

inline BOOL notEqualFunction(ZGSearchData *searchData, const void *variableValue, const void *compareValue, ZGVariableType type, ZGMemorySize size)
{
	return !equalFunction(searchData, variableValue, compareValue, type, size);
}

inline BOOL equalPlusFunction(ZGSearchData *searchData, const void *variableValue, const void *compareValue, ZGVariableType type, ZGMemorySize size)
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
				int8_t newCompareValue = *((int8_t *)compareValue) + *((int8_t *)searchData->compareOffset);
				return equalFunction(searchData, variableValue, &newCompareValue, type, size);
			}
		case ZGInt16:
			{
				int16_t newCompareValue = *((int16_t *)compareValue) + *((int16_t *)searchData->compareOffset);
				return equalFunction(searchData, variableValue, &newCompareValue, type, size);
			}
		case ZGInt32:
		INT32_EQUAL_TO_PLUS:
			{
				int32_t newCompareValue = *((int32_t *)compareValue) + *((int32_t *)searchData->compareOffset);
				return equalFunction(searchData, variableValue, &newCompareValue, type, size);
			}
		case ZGInt64:
		INT64_EQUAL_TO_PLUS:
			{
				int64_t newCompareValue = *((int64_t *)compareValue) + *((int64_t *)searchData->compareOffset);
				return equalFunction(searchData, variableValue, &newCompareValue, type, size);
			}
		case ZGFloat:
			{
				float newCompareValue = *((float *)compareValue) + *((float *)searchData->compareOffset);
				return equalFunction(searchData, variableValue, &newCompareValue, type, size);
			}
		case ZGDouble:
			{
				double newCompareValue = *((double *)compareValue) + *((double *)searchData->compareOffset);
				return equalFunction(searchData, variableValue, &newCompareValue, type, size);
			}
		default:
			break;
	}
	
	return NO;
}

inline BOOL notEqualPlusFunction(ZGSearchData *searchData, const void *variableValue, const void *compareValue, ZGVariableType type, ZGMemorySize size)
{
    return !equalPlusFunction(searchData, variableValue, compareValue, type, size);
}
