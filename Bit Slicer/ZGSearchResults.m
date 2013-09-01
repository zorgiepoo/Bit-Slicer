/*
 * Created by Mayur Pawashe on 3/16/13.
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

#import "ZGSearchResults.h"

@interface ZGSearchResults ()

@property (nonatomic) ZGMemorySize addressIndex;
@property (nonatomic) NSArray *resultSets;
@property (nonatomic) ZGMemorySize addressCount;
@property (nonatomic) ZGMemorySize dataSize;
@property (nonatomic) ZGMemorySize pointerSize;

@end

@implementation ZGSearchResults

- (id)initWithResultSets:(NSArray *)resultSets dataSize:(ZGMemorySize)dataSize pointerSize:(ZGMemorySize)pointerSize
{
	self = [super init];
	if (self != nil)
	{
		self.resultSets = resultSets;
		self.pointerSize = pointerSize;
		for (NSData *result in self.resultSets)
		{
			self.addressCount += result.length / self.pointerSize;
		}
		self.dataSize = dataSize;
	}
	return self;
}

- (void)removeNumberOfAddresses:(ZGMemorySize)numberOfAddresses
{
	self.addressIndex += numberOfAddresses;
	self.addressCount -= numberOfAddresses;
	
	if (self.addressCount == 0)
	{
		self.resultSets = nil;
	}
}

- (void)enumerateInRange:(NSRange)range usingBlock:(zg_enumerate_search_results_t)addressCallback
{
	ZGMemoryAddress absoluteLocation = range.location * self.pointerSize;
	ZGMemoryAddress absoluteLength = range.length * self.pointerSize;
	
	BOOL setBeginOffset = NO;
	BOOL setEndOffset = NO;
	ZGMemoryAddress beginOffset = 0;
	ZGMemoryAddress endOffset = 0;
	ZGMemoryAddress accumulator = 0;
	
	BOOL shouldStopEnumerating = NO;
	
	ZGMemorySize pointerSize = self.pointerSize;
	
	for (NSData *resultSet in self.resultSets)
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
				switch (pointerSize)
				{
					case sizeof(ZGMemoryAddress):
						addressCallback(*(ZGMemoryAddress *)(resultBytes + offset), &shouldStopEnumerating);
						break;
					default:
						addressCallback(*(ZG32BitMemoryAddress *)(resultBytes + offset), &shouldStopEnumerating);
						break;
				}
				
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
	[self enumerateInRange:NSMakeRange(self.addressIndex, addressCount) usingBlock:addressCallback];
}

- (void)enumerateUsingBlock:(zg_enumerate_search_results_t)addressCallback
{
	[self enumerateWithCount:self.addressCount usingBlock:addressCallback];
}

@end
