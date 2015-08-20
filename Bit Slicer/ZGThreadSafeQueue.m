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

#import "ZGThreadSafeQueue.h"

typedef NS_ENUM(NSInteger, ZGThreadSafeLockCondition)
{
	ZGThreadSafeEmptyCondition,
	ZGThreadSafeNonEmptyCondition
};

@implementation ZGThreadSafeQueue
{
	NSConditionLock *_lock;
	NSMutableArray *_queue;
}

- (instancetype)init
{
	self = [super init];
	if (self != nil)
	{
		_lock = [[NSConditionLock alloc] initWithCondition:ZGThreadSafeEmptyCondition];
		_queue = [NSMutableArray array];
	}
	return self;
}

- (void)enqueue:(id)object
{
	[_lock lock];
	
	[_queue addObject:object];

	[_lock unlockWithCondition:ZGThreadSafeNonEmptyCondition];
}

- (id)dequeue
{
	[_lock lockWhenCondition:ZGThreadSafeNonEmptyCondition];
	
	id object = _queue[0];
	[_queue removeObjectAtIndex:0];
	
	[_lock unlockWithCondition:_queue.count > 0 ? ZGThreadSafeNonEmptyCondition : ZGThreadSafeEmptyCondition];
	
	return object;
}

@end
