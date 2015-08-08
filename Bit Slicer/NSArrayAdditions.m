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

#import "NSArrayAdditions.h"

@implementation NSArray (NSArrayAdditions)

- (NSArray *)zgFilterUsingBlock:(zg_array_filter_t)shouldKeep
{
	NSMutableArray *newResults = [[NSMutableArray alloc] init];
	
	for (id item in self)
	{
		if (shouldKeep(item))
		{
			[newResults addObject:item];
		}
	}
	
	return [NSArray arrayWithArray:newResults];
}

- (NSArray *)zgMapUsingBlock:(zg_map_t)map
{
	NSMutableArray *newResults = [[NSMutableArray alloc] init];
	
	for (id item in self)
	{
		[newResults addObject:map(item)];
	}
	
	return newResults;
}

- (id)zgFirstObjectThatMatchesCondition:(zg_array_filter_t)matchingCondition
{
	for (id item in self)
	{
		if (matchingCondition(item))
		{
			return item;
		}
	}
	return nil;
}

- (BOOL)zgHasObjectMatchingCondition:(zg_array_filter_t)matchingCondition
{
	for (id item in self)
	{
		if (matchingCondition(item))
		{
			return YES;
		}
	}
	return NO;
}

- (BOOL)zgAllObjectsMatchingCondition:(zg_array_filter_t)matchingCondition
{
	return [self zgFilterUsingBlock:matchingCondition].count == self.count;
}

// our's first, their's later
- (id)zgBinarySearchUsingBlock:(zg_binary_search_t)comparator
{
	NSUInteger end = self.count;
	NSUInteger start = 0;
	while (end > start)
	{
		NSUInteger middleIndex = start + (end - start) / 2; // writing this as (start + end) / 2 can fail for large values of start & end
		id __unsafe_unretained object = [self objectAtIndex:middleIndex];
		
		switch (comparator(object))
		{
			case NSOrderedAscending:
				start = middleIndex + 1;
				break;
			case NSOrderedDescending:
				end = middleIndex;
				break;
			case NSOrderedSame:
				return object;
		}
	}
	
	return nil;
}

@end
