/*
 * Copyright (c) 2013 Mayur Pawashe
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

#import "ZGSearchResults.h"

@implementation ZGSearchResults

- (id)initWithResultSets:(NSArray<NSData *> *)resultSets dataSize:(ZGMemorySize)dataSize pointerSize:(ZGMemorySize)pointerSize
{
	self = [super init];
	if (self != nil)
	{
		_resultSets = resultSets;
		_pointerSize = pointerSize;
		for (NSData *result in _resultSets)
		{
			_addressCount += result.length / _pointerSize;
		}
		_dataSize = dataSize;
	}
	return self;
}

- (void)removeNumberOfAddresses:(ZGMemorySize)numberOfAddresses
{
	_addressIndex += numberOfAddresses;
	_addressCount -= numberOfAddresses;
	
	if (_addressCount == 0)
	{
		_resultSets = @[];
	}
}

- (void)enumerateInRange:(NSRange)range usingBlock:(zg_enumerate_search_results_t)addressCallback
{
	ZGMemoryAddress absoluteLocation = range.location * _pointerSize;
	ZGMemoryAddress absoluteLength = range.length * _pointerSize;
	
	BOOL setBeginOffset = NO;
	BOOL setEndOffset = NO;
	ZGMemoryAddress beginOffset = 0;
	ZGMemoryAddress endOffset = 0;
	ZGMemoryAddress accumulator = 0;
	
	BOOL shouldStopEnumerating = NO;
	
	ZGMemorySize pointerSize = _pointerSize;
	
	for (NSData *resultSet in _resultSets)
	{
		NSUInteger resultSetLength = resultSet.length;
		accumulator += resultSetLength;
		
		if (!setBeginOffset && accumulator > absoluteLocation)
		{
			beginOffset = resultSetLength - (accumulator - absoluteLocation);
			setBeginOffset = YES;
		}
		else if (setBeginOffset)
		{
			beginOffset = 0;
		}
		
		if (!setEndOffset && accumulator >= absoluteLocation + absoluteLength)
		{
			endOffset = resultSetLength - (accumulator - (absoluteLocation + absoluteLength));
			setEndOffset = YES;
		}
		else
		{
			endOffset = resultSetLength;
		}
		
		if (setBeginOffset)
		{
			const void *resultBytes = resultSet.bytes;
			for (ZGMemorySize offset = beginOffset; offset < endOffset; offset += pointerSize)
			{
				ZGMemoryAddress address;
				switch (pointerSize)
				{
					case sizeof(ZGMemoryAddress):
						address = *(const ZGMemoryAddress *)(const void *)((const uint8_t *)resultBytes + offset);
						break;
					case sizeof(ZG32BitMemoryAddress):
						address = *(const ZG32BitMemoryAddress *)(const void *)((const uint8_t *)resultBytes + offset);
						break;
					default:
						assert("Retrieved unexpected pointer size" == NULL);
				}
				
				addressCallback(address, &shouldStopEnumerating);
				
				if (shouldStopEnumerating)
				{
					break;
				}
			}
			
			if (setEndOffset || shouldStopEnumerating)
			{
				break;
			}
		}
	}
}

- (void)enumerateWithCount:(ZGMemorySize)addressCount usingBlock:(zg_enumerate_search_results_t)addressCallback
{
	[self enumerateInRange:NSMakeRange(_addressIndex, addressCount) usingBlock:addressCallback];
}

- (void)enumerateUsingBlock:(zg_enumerate_search_results_t)addressCallback
{
	[self enumerateWithCount:_addressCount usingBlock:addressCallback];
}

@end
