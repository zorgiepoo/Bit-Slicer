/*
 * Created by Mayur Pawashe on 12/29/12.
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

#import "ZGBreakPointController.h"
#import "ZGAppController.h"
#import "ZGVirtualMemory.h"
#import "ZGVariable.h"
#import "ZGProcess.h"
#import "ZGDebugThread.h"
#import "ZGBreakPoint.h"

@interface ZGBreakPointController ()

@property (readwrite, nonatomic) mach_port_t exceptionPort;
@property (strong, nonatomic) NSArray *breakPoints;

@end

@implementation ZGBreakPointController

extern boolean_t mach_exc_server(mach_msg_header_t *InHeadP, mach_msg_header_t *OutHeadP);

kern_return_t  catch_mach_exception_raise_state(mach_port_t exception_port, exception_type_t exception, exception_data_t code, mach_msg_type_number_t code_count, int *flavor, thread_state_t in_state, mach_msg_type_number_t in_state_count, thread_state_t out_state, mach_msg_type_number_t *out_state_count)
{
	return KERN_SUCCESS;
}

kern_return_t   catch_mach_exception_raise_state_identity(mach_port_t exception_port, mach_port_t thread, mach_port_t task, exception_type_t exception, exception_data_t code, mach_msg_type_number_t code_count, int *flavor, thread_state_t in_state, mach_msg_type_number_t in_state_count, thread_state_t out_state, mach_msg_type_number_t *out_state_count)
{
	return KERN_SUCCESS;
}

kern_return_t catch_mach_exception_raise(mach_port_t exception_port, mach_port_t thread, mach_port_t task, exception_type_t exception, exception_data_t code, mach_msg_type_number_t code_count)
{
	NSArray *breakPoints = [[[ZGAppController sharedController] breakPointController] breakPoints];
	
	ZGBreakPoint *targetBreakPoint = nil;
	ZGDebugThread *targetDebugThread = nil;
	for (ZGBreakPoint *breakPoint in breakPoints)
	{
		if (breakPoint.task == task)
		{
			for (ZGDebugThread *debugThread in breakPoint.debugThreads)
			{
				if (debugThread.thread == thread)
				{
					targetBreakPoint = breakPoint;
					targetDebugThread = debugThread;
					break;
				}
			}
			if (targetBreakPoint) break;
		}
	}
	
	if (targetBreakPoint)
	{
		x86_thread_state_t threadState;
		mach_msg_type_number_t threadStateCount = x86_THREAD_STATE_COUNT;
		if (thread_get_state(thread, x86_THREAD_STATE, (thread_state_t)&threadState, &threadStateCount) != KERN_SUCCESS)
		{
			NSLog(@"ERROR: Grabbing thread state failed from catch exception");
		}
		else
		{
			x86_debug_state_t debugState;
			mach_msg_type_number_t stateCount = x86_DEBUG_STATE_COUNT;
			if (thread_get_state(thread, x86_DEBUG_STATE, (thread_state_t)&debugState, &stateCount) != KERN_SUCCESS)
			{
				NSLog(@"ERROR: Grabbing debug state failed from catch exception");
			}
			else
			{
				int debugRegisterIndex = targetDebugThread.registerNumber;
				
#define RESTORE_BREAKPOINT_IN_DEBUG_REGISTERS(type) \
	if (debugRegisterIndex == 0) { debugState.uds.type.__dr0 = 0x0; } \
	else if (debugRegisterIndex == 1) { debugState.uds.type.__dr1 = 0x0; } \
	else if (debugRegisterIndex == 2) { debugState.uds.type.__dr2 = 0x0; } \
	else if (debugRegisterIndex == 3) { debugState.uds.type.__dr3 = 0x0; } \
	\
	debugState.uds.type.__dr6 &= ~(1 << debugRegisterIndex); \
	\
	debugState.uds.type.__dr7 &= ~(1 << 2*debugRegisterIndex); \
	debugState.uds.type.__dr7 &= ~(1 << 2*debugRegisterIndex+1); \
	\
	debugState.uds.type.__dr7 &= ~(1 << 16 + 2*debugRegisterIndex); \
	debugState.uds.type.__dr7 &= ~(1 << 16 + 2*debugRegisterIndex+1); \
	\
	debugState.uds.type.__dr7 &= ~(1 << 18 + 2*debugRegisterIndex); \
	debugState.uds.type.__dr7 &= ~(1 << 18 + 2*debugRegisterIndex+1); \

				if (targetBreakPoint.process.is64Bit)
				{
					RESTORE_BREAKPOINT_IN_DEBUG_REGISTERS(ds64);
				}
				else
				{
					RESTORE_BREAKPOINT_IN_DEBUG_REGISTERS(ds32);
				}
				
				if (thread_set_state(thread, x86_DEBUG_STATE, (thread_state_t)&debugState, stateCount) != KERN_SUCCESS)
				{
					NSLog(@"ERROR: Failure in setting thread state registers from catch exception");
				}
				
				dispatch_async(dispatch_get_main_queue(), ^{
					NSMutableArray *newBreakPoints = [[NSMutableArray alloc] initWithArray:breakPoints];
					[newBreakPoints removeObject:targetBreakPoint];
					
					[[[ZGAppController sharedController] breakPointController] setBreakPoints:newBreakPoints];
					
					[targetBreakPoint.delegate performSelector:@selector(breakPointDidHit:) withObject:@((uint64_t)(targetBreakPoint.process.is64Bit ? threadState.uts.ts64.__rip : threadState.uts.ts32.__eip))];
				});
			}
		}
	}
	
	return KERN_SUCCESS;
}

- (BOOL)addWatchpointOnVariable:(ZGVariable *)variable inProcess:(ZGProcess *)process delegate:(id)delegate
{
	if (self.exceptionPort == MACH_PORT_NULL)
	{
		if (mach_port_allocate(current_task(), MACH_PORT_RIGHT_RECEIVE, &_exceptionPort) != KERN_SUCCESS)
		{
			NSLog(@"ERROR: Could not allocate mach port for watchpoint");
			self.exceptionPort = MACH_PORT_NULL;
			return NO;
		}
		
		if (mach_port_insert_right(current_task(), self.exceptionPort, self.exceptionPort, MACH_MSG_TYPE_MAKE_SEND) != KERN_SUCCESS)
		{
			NSLog(@"ERROR: Could not insert send right for watchpoint");
			if (mach_port_deallocate(current_task(), self.exceptionPort) != KERN_SUCCESS)
			{
				NSLog(@"ERROR: Could not deallocate exception port in watchpoint");
			}
			self.exceptionPort = MACH_PORT_NULL;
			return NO;
		}
	}
	
	if (task_set_exception_ports(process.processTask, EXC_MASK_BREAKPOINT, self.exceptionPort, EXCEPTION_DEFAULT | MACH_EXCEPTION_CODES, MACHINE_THREAD_STATE) != KERN_SUCCESS)
	{
		NSLog(@"ERROR: task_set_exception_ports failed on adding watchpoint");
		return NO;
	}
	
	ZGSuspendTask(process.processTask);

	thread_act_array_t threadList = NULL;
	mach_msg_type_number_t threadListCount = 0;
	if (task_threads(process.processTask, &threadList, &threadListCount) != KERN_SUCCESS)
	{
		NSLog(@"ERROR: task_threads failed on adding watchpoint");
		ZGResumeTask(process.processTask);
		return NO;
	}
	
	NSMutableArray *debugThreads = [[NSMutableArray alloc] init];
	
	for (mach_msg_type_number_t threadIndex = 0; threadIndex < threadListCount; threadIndex++)
	{
		x86_debug_state_t debugState;
		mach_msg_type_number_t stateCount = x86_DEBUG_STATE_COUNT;
		if (thread_get_state(threadList[threadIndex], x86_DEBUG_STATE, (thread_state_t)&debugState, &stateCount) != KERN_SUCCESS)
		{
			NSLog(@"ERROR: thread_get_state failed on adding watchpoint for thread %d", threadList[threadIndex]);
			continue;
		}
		
		int debugRegisterIndex = -1;
		
		for (int registerIndex = 0; registerIndex < 4; registerIndex++)
		{
#define IS_REGISTER_AVAILABLE(type) (!(debugState.uds.type.__dr7 & (1 << 2*registerIndex)) && !(debugState.uds.type.__dr7 & (1 << 2*registerIndex+1)))
			if ((process.is64Bit && IS_REGISTER_AVAILABLE(ds64)) || (!process.is64Bit && IS_REGISTER_AVAILABLE(ds32)))
			{
				debugRegisterIndex = registerIndex;
				break;
			}
		}
		
		if (debugRegisterIndex >= 0)
		{
			ZGDebugThread *debugThread = [[ZGDebugThread alloc] init];
			debugThread.registerNumber = debugRegisterIndex;
			debugThread.thread = threadList[threadIndex];
			
#define WRITE_BREAKPOINT_IN_DEBUG_REGISTERS(type) \
	if (debugRegisterIndex == 0) { debugState.uds.type.__dr0 = (uint32_t)variable.address; } \
	else if (debugRegisterIndex == 1) { debugState.uds.type.__dr1 = (uint32_t)variable.address; } \
	else if (debugRegisterIndex == 2) { debugState.uds.type.__dr2 = (uint32_t)variable.address; } \
	else if (debugRegisterIndex == 3) { debugState.uds.type.__dr3 = (uint32_t)variable.address; } \
	\
	debugState.uds.type.__dr7 |= (1 << 2*debugRegisterIndex); \
	debugState.uds.type.__dr7 &= ~(1 << 2*debugRegisterIndex+1); \
	\
	debugState.uds.type.__dr7 |= (1 << 16 + 2*debugRegisterIndex); \
	debugState.uds.type.__dr7 &= ~(1 << 16 + 2*debugRegisterIndex+1); \
	\
	if (variable.size <= 1) { debugState.uds.type.__dr7 &= ~(1 << 18 + 2*debugRegisterIndex); debugState.uds.type.__dr7 &= ~(1 << 18 + 2*debugRegisterIndex+1);} \
	else if (variable.size <= 2) { debugState.uds.type.__dr7 |= (1 << 18 + 2*debugRegisterIndex); debugState.uds.type.__dr7 &= ~(1 << 18 + 2*debugRegisterIndex+1); } \
	else if (variable.size <= 4) { debugState.uds.type.__dr7 |= (1 << 18 + 2*debugRegisterIndex); debugState.uds.type.__dr7 |= (1 << 18 + 2*debugRegisterIndex+1); } \
	else { debugState.uds.type.__dr7 &= ~(1 << 18 + 2*debugRegisterIndex); debugState.uds.type.__dr7 |= (1 << 18 + 2*debugRegisterIndex+1); } \
			
			if (process.is64Bit)
			{
				WRITE_BREAKPOINT_IN_DEBUG_REGISTERS(ds64);
			}
			else
			{
				WRITE_BREAKPOINT_IN_DEBUG_REGISTERS(ds32);
			}
			
			if (thread_set_state(threadList[threadIndex], x86_DEBUG_STATE, (thread_state_t)&debugState, stateCount) != KERN_SUCCESS)
			{
				NSLog(@"Failure in setting registers thread state for adding watchpoint for thread %d", threadList[threadIndex]);
				continue;
			}
			
			[debugThreads addObject:debugThread];
		}
		else
		{
			NSLog(@"Failed to find available debug register for thread %d", threadList[threadIndex]);
		}
	}
	
	ZGResumeTask(process.processTask);
	
	if (debugThreads.count == 0)
	{
		NSLog(@"ERROR: Failed to set watch variable.");
		return NO;
	}
	
	ZGBreakPoint *breakPoint = [[ZGBreakPoint alloc] init];
	breakPoint.task = process.processTask;
	breakPoint.delegate = delegate;
	breakPoint.debugThreads = [NSArray arrayWithArray:debugThreads];
	breakPoint.variable = variable;
	breakPoint.process = process;
	
	NSMutableArray *currentBreakPoints = [[NSMutableArray alloc] initWithArray:self.breakPoints];
	[currentBreakPoints addObject:breakPoint];
	self.breakPoints = [NSArray arrayWithArray:currentBreakPoints];
	
	static dispatch_once_t once = 0;
	dispatch_once(&once, ^{
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			if (mach_msg_server(mach_exc_server, 2048, self.exceptionPort, MACH_MSG_TIMEOUT_NONE) != MACH_MSG_SUCCESS)
			{
				NSLog(@"mach_msg_server_once() returned on error!");
			}
		});
    });
	
	return YES;
}

@end
