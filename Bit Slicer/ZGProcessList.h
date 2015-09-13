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

#import <Foundation/Foundation.h>

@class ZGRunningProcess;
@class ZGProcessTaskManager;

NS_ASSUME_NONNULL_BEGIN

@interface ZGProcessList : NSObject

- (id)init;
- (id)initWithProcessTaskManager:(ZGProcessTaskManager *)processTaskManager;

// Observable for new and old changes via KVO
@property (nonatomic, readonly) NSArray<ZGRunningProcess *> *runningProcesses;

// Forces to fetch all process information
- (void)retrieveList;

// Request or unrequest if changes should be polled and checked frequently
// Not so efficient, but sometimes necessary
- (void)requestPollingWithObserver:(id)observer;
- (void)unrequestPollingWithObserver:(id)observer;

// Add or remove priority to a process id. Even if we aren't polling, we will make sure to let you know when a specific running process ID terminates. This is efficient.
- (void)addPriorityToProcessIdentifier:(pid_t)processIdentifier withObserver:(id)observer;
- (void)removePriorityToProcessIdentifier:(pid_t)processIdentifier withObserver:(id)observer;

@end

NS_ASSUME_NONNULL_END
