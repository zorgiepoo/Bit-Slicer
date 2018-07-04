/*
 * Copyright (c) 2015 OneSadCookie
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import "OSCSingleThreadQueue.h"

@implementation OSCSingleThreadQueue
{
	dispatch_queue_t _queue;
	dispatch_block_t _block;
	dispatch_semaphore_t _haveWork;
	dispatch_semaphore_t _needWork;
}

+ (instancetype)startWithPriority:(long)priority label:(char const *)label
{
	OSCSingleThreadQueue *stq = [(OSCSingleThreadQueue *)[self alloc] init];
	stq->_queue = dispatch_queue_create(label, DISPATCH_QUEUE_SERIAL);
	stq->_haveWork = dispatch_semaphore_create(0);
	stq->_needWork = dispatch_semaphore_create(0);
	dispatch_async(dispatch_get_global_queue(priority, 0), ^{
		while (YES)
		{
			@autoreleasepool
			{
				dispatch_semaphore_wait(stq->_haveWork, DISPATCH_TIME_FOREVER);
				assert(stq->_block != nil);
				stq->_block();
				stq->_block = nil;
				dispatch_semaphore_signal(stq->_needWork);
			}
		}
	});
	return stq;
}

- (void)dealloc __attribute__((noreturn))
{
	// since the thread retains self, we can't get here
	__builtin_unreachable();
}

- (void)_dispatch:(dispatch_block_t)block synchronously:(BOOL)sync
{
	(sync ? dispatch_sync : dispatch_async)(_queue, ^{
		assert(self->_block == nil);
		self->_block = block;
		dispatch_semaphore_signal(self->_haveWork);
		dispatch_semaphore_wait(self->_needWork, DISPATCH_TIME_FOREVER);
	});
}

- (void)dispatchSync:(dispatch_block_t)block
{
	[self _dispatch:block synchronously:YES];
}

- (void)dispatchAsync:(dispatch_block_t)block
{
	[self _dispatch:block synchronously:NO];
}

@end
