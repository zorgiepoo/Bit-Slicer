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

// For information about x86 debug registers, see:
// http://en.wikipedia.org/wiki/X86_debug_register

// General summary of watchpoints:
// We set up an exception handler for catching breakpoint's and run a server that listens for exceptions coming in
// We add a hardware watchpoint when the user requests it.
// Determine number of bytes we want to watch: 1, 2, 4, 8 (note: 32-bit processes cannot use byte-size of 8)
// Iterate through each thread's registers, and:
//		Checking for availability and enabling our breakpoint in dr7 (we always add a local breakpoint to every thread of a process).
//		Modifying bits in dr7 indicating our watchpoint byte length (again: 1, 2, 4, or 8)
//		Modifying dr0 - dr3 with our memory address of interest
// Any time we obtain or set thread information, we suspend the task before doing so and resume it when we're done (I suppose we could just only suspend the thread instead)
// We catch a breakpoint exception, make sure it matches with one of our breakpoints, restore what we've written to registers in all threads, and clear the dr6 status register
// Also grab the EIP (for 32-bit processes) or RIP (for 64-bit processes) program counters, this is the address of the instruction *after* the one we're interested in

// For instruction breakpoints, we modify the instruction's first byte to 0xCC, fake the disassembler values to the user.
// When a breakpoint hits, we suspend the task, and let the user decide to continue when he wants
// At continuation, we restore the breakpoint's first byte, turn on single-stepping by modifying flags register, and at the next step we restore our breakpoint and continue like usual
// Note: There are some trick cases if the user decides to jump to an address or manually single-step or step-over

#import "ZGBreakPointController.h"
#import "ZGAppController.h"
#import "ZGVirtualMemory.h"
#import "ZGVariable.h"
#import "ZGProcess.h"
#import "ZGDebugThread.h"
#import "ZGBreakPoint.h"
#import "ZGInstruction.h"
#import "ZGDebuggerController.h"
#import "ZGProcessList.h"
#import "ZGRunningProcess.h"

@interface ZGBreakPointController ()

@property (readwrite, nonatomic) mach_port_t exceptionPort;

@end

@implementation ZGBreakPointController

extern boolean_t mach_exc_server(mach_msg_header_t *InHeadP, mach_msg_header_t *OutHeadP);

// Unused
kern_return_t  catch_mach_exception_raise_state(mach_port_t exception_port, exception_type_t exception, exception_data_t code, mach_msg_type_number_t code_count, int *flavor, thread_state_t in_state, mach_msg_type_number_t in_state_count, thread_state_t out_state, mach_msg_type_number_t *out_state_count)
{
	return KERN_FAILURE;
}

// Unused
kern_return_t   catch_mach_exception_raise_state_identity(mach_port_t exception_port, mach_port_t thread, mach_port_t task, exception_type_t exception, exception_data_t code, mach_msg_type_number_t code_count, int *flavor, thread_state_t in_state, mach_msg_type_number_t in_state_count, thread_state_t out_state, mach_msg_type_number_t *out_state_count)
{
	return KERN_FAILURE;
}

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

- (ZGMemoryAddress)removeWatchPoint:(ZGBreakPoint *)breakPoint
{
	ZGMemoryAddress instructionAddress = 0x0;
	
	thread_act_array_t threadList = NULL;
	mach_msg_type_number_t threadListCount = 0;
	if (task_threads(breakPoint.process.processTask, &threadList, &threadListCount) != KERN_SUCCESS)
	{
		NSLog(@"ERROR: task_threads failed on removing watchpoint");
		return instructionAddress;
	}
	
	for (ZGDebugThread *debugThread in breakPoint.debugThreads)
	{
		BOOL foundDebugThread = NO;
		for (mach_msg_type_number_t threadIndex = 0; threadIndex < threadListCount; threadIndex++)
		{
			if (threadList[threadIndex] == debugThread.thread)
			{
				foundDebugThread = YES;
				break;
			}
		}
		
		if (!foundDebugThread)
		{
			continue;
		}
		
		x86_debug_state_t debugState;
		mach_msg_type_number_t stateCount = x86_DEBUG_STATE_COUNT;
		kern_return_t error = 0;
		if ((error = thread_get_state(debugThread.thread, x86_DEBUG_STATE, (thread_state_t)&debugState, &stateCount)) != KERN_SUCCESS)
		{
			NSLog(@"ERROR: Grabbing debug state failed in removeWatchPoint:, %d, continuing...", error);
			continue;
		}
		
		int debugRegisterIndex = debugThread.registerNumber;
		
		if (breakPoint.process.is64Bit)
		{
			RESTORE_BREAKPOINT_IN_DEBUG_REGISTERS(ds64);
		}
		else
		{
			RESTORE_BREAKPOINT_IN_DEBUG_REGISTERS(ds32);
		}
		
		if ((error = thread_set_state(debugThread.thread, x86_DEBUG_STATE, (thread_state_t)&debugState, stateCount)) != KERN_SUCCESS)
		{
			NSLog(@"ERROR: Failure in setting thread state registers, %d, in removeWatchPoint:", error);
		}
	}
	
	if (mach_vm_deallocate(current_task(), (mach_vm_address_t)threadList, threadListCount * sizeof(thread_act_t)) != KERN_SUCCESS)
	{
		NSLog(@"Failed to deallocate thread list in removeWatchPoint...");
	}
	
	dispatch_async(dispatch_get_main_queue(), ^{
		[[[ZGAppController sharedController] breakPointController] removeBreakPoint:breakPoint];
	});
	
	return instructionAddress;
}

#define GET_DEBUG_REGISTER_ADDRESS(type) \
	if (debugRegisterIndex == 0 && debugState.uds.type.__dr6 & (1 << 0) && debugState.uds.type.__dr7 & (1 << 2*0)) { debugAddress = debugState.uds.type.__dr0; } \
	else if (debugRegisterIndex == 1 && debugState.uds.type.__dr6 & (1 << 1) && debugState.uds.type.__dr7 & (1 << 2*1)) { debugAddress = debugState.uds.type.__dr1; } \
	else if (debugRegisterIndex == 2 && debugState.uds.type.__dr6 & (1 << 2) && debugState.uds.type.__dr7 & (1 << 2*2)) { debugAddress = debugState.uds.type.__dr2; } \
	else if (debugRegisterIndex == 3 && debugState.uds.type.__dr6 & (1 << 3) && debugState.uds.type.__dr7 & (1 << 2*3)) { debugAddress = debugState.uds.type.__dr3; } \

- (BOOL)handleWatchPointsWithTask:(mach_port_t) task inThread:(mach_port_t)thread
{
	BOOL handledWatchPoint = NO;
	for (ZGBreakPoint *breakPoint in self.breakPoints)
	{
		if (breakPoint.type != ZGBreakPointWatchData)
		{
			continue;
		}
		
		if (breakPoint.task == task)
		{
			ZGSuspendTask(task);
			
			for (ZGDebugThread *debugThread in breakPoint.debugThreads)
			{
				if (debugThread.thread == thread)
				{
					x86_debug_state_t debugState;
					mach_msg_type_number_t debugStateCount = x86_DEBUG_STATE_COUNT;
					if (thread_get_state(thread, x86_DEBUG_STATE, (thread_state_t)&debugState, &debugStateCount) != KERN_SUCCESS)
					{
						NSLog(@"ERROR: Grabbing debug state failed when checking for breakpoint existance");
						continue;
					}
					
					ZGMemoryAddress debugAddress = 0x0;
					int debugRegisterIndex = debugThread.registerNumber;
					
					if (breakPoint.process.is64Bit)
					{
						GET_DEBUG_REGISTER_ADDRESS(ds64);
					}
					else
					{
						GET_DEBUG_REGISTER_ADDRESS(ds32);
					}
					
					if (debugAddress == breakPoint.variable.address)
					{
						x86_thread_state_t threadState;
						mach_msg_type_number_t threadStateCount = x86_THREAD_STATE_COUNT;
						if (thread_get_state(thread, x86_THREAD_STATE, (thread_state_t)&threadState, &threadStateCount) != KERN_SUCCESS)
						{
							NSLog(@"ERROR: Grabbing thread state failed in obtaining instruction address, skipping.");
							continue;
						}
						
						ZGMemoryAddress instructionAddress = breakPoint.process.is64Bit ? threadState.uts.ts64.__rip : threadState.uts.ts32.__eip;
						
						dispatch_async(dispatch_get_main_queue(), ^{
							if ([breakPoint.delegate respondsToSelector:@selector(breakPointDidHit:)])
							{
								[breakPoint.delegate performSelector:@selector(breakPointDidHit:) withObject:@(instructionAddress)];
							}
						});
						
						handledWatchPoint = YES;
						
						// Clear dr6 debug status
						if (breakPoint.process.is64Bit)
						{
							debugState.uds.ds64.__dr6 &= ~(1 << debugRegisterIndex);
						}
						else
						{
							debugState.uds.ds32.__dr6 &= ~(1 << debugRegisterIndex);
						}
						
						if (thread_set_state(debugThread.thread, x86_DEBUG_STATE, (thread_state_t)&debugState, debugStateCount) != KERN_SUCCESS)
						{
							NSLog(@"ERROR: Failure in setting debug thread registers for clearing dr6 in handle watchpoint");
						}
						
						break;
					}
				}
			}
			
			ZGResumeTask(task);
		}
	}
	
	return handledWatchPoint;
}

- (void)removeSingleStepBreakPointsFromBreakPoint:(ZGBreakPoint *)breakPoint
{
	for (ZGBreakPoint *candidateBreakPoint in self.breakPoints)
	{
		if (candidateBreakPoint.type == ZGBreakPointSingleStepInstruction && candidateBreakPoint.task == breakPoint.task && candidateBreakPoint.thread == breakPoint.thread)
		{
			[self removeBreakPoint:candidateBreakPoint];
		}
	}
}

- (void)resumeFromBreakPoint:(ZGBreakPoint *)breakPoint
{
	x86_thread_state_t threadState;
	mach_msg_type_number_t threadStateCount = x86_THREAD_STATE_COUNT;
	if (thread_get_state(breakPoint.thread, x86_THREAD_STATE, (thread_state_t)&threadState, &threadStateCount) != KERN_SUCCESS)
	{
		NSLog(@"ERROR: Grabbing thread state failed in resumeFromBreakPoint:");
	}
	
	BOOL shouldSingleStep = NO;
	
	// Check if breakpoint still exists
	if (breakPoint.type == ZGBreakPointInstruction && [self.breakPoints containsObject:breakPoint])
	{
		// Restore our instruction
		ZGWriteBytesIgnoringProtection(breakPoint.process.processTask, breakPoint.variable.address, breakPoint.variable.value, sizeof(uint8_t));
		
		breakPoint.needsToRestore = YES;
		
		// Ensure single-stepping, so on next instruction we can restore our breakpoint
		shouldSingleStep = YES;
	}
	else
	{
		for (ZGBreakPoint *candidateBreakPoint in self.breakPoints)
		{
			if (candidateBreakPoint.type == ZGBreakPointSingleStepInstruction && candidateBreakPoint.thread == breakPoint.thread && candidateBreakPoint.task == breakPoint.task && [self.breakPoints containsObject:candidateBreakPoint])
			{
				shouldSingleStep = YES;
				break;
			}
		}
	}
	
	if (shouldSingleStep)
	{
		if (breakPoint.process.is64Bit)
		{
			threadState.uts.ts64.__rflags |= (1 << 8);
		}
		else
		{
			threadState.uts.ts32.__eflags |= (1 << 8);
		}
	}
	
	if (thread_set_state(breakPoint.thread, x86_THREAD_STATE, (thread_state_t)&threadState, threadStateCount) != KERN_SUCCESS)
	{
		NSLog(@"Failure in setting registers thread state for resumeFromBreakPoint: for thread %d", breakPoint.thread);
	}
	
	ZGResumeTask(breakPoint.process.processTask);
}

- (void)removeInstructionBreakPoint:(ZGBreakPoint *)breakPoint
{
	// Restore our instruction
	ZGWriteBytesIgnoringProtection(breakPoint.process.processTask, breakPoint.variable.address, breakPoint.variable.value, sizeof(uint8_t));
	
	[self removeBreakPoint:breakPoint];
}

- (void)removeBreakPointOnInstruction:(ZGInstruction *)instruction inProcess:(ZGProcess *)process
{
	ZGBreakPoint *targetBreakPoint = nil;
	for (ZGBreakPoint *breakPoint in self.breakPoints)
	{
		if (breakPoint.type == ZGBreakPointInstruction && breakPoint.process.processTask == process.processTask	&& breakPoint.variable.address == instruction.variable.address)
		{
			targetBreakPoint = breakPoint;
			break;
		}
	}
	
	if (targetBreakPoint)
	{
		[self removeInstructionBreakPoint:targetBreakPoint];
	}
}

- (BOOL)handleInstructionBreakPointsWithTask:(mach_port_t)task inThread:(mach_port_t)thread
{
	BOOL handledInstructionBreakPoint = NO;
	
	ZGSuspendTask(task);
	
	x86_thread_state_t threadState;
	mach_msg_type_number_t threadStateCount = x86_THREAD_STATE_COUNT;
	if (thread_get_state(thread, x86_THREAD_STATE, (thread_state_t)&threadState, &threadStateCount) != KERN_SUCCESS)
	{
		NSLog(@"ERROR: Grabbing thread state failed in obtaining instruction address, skipping.");
	}
	
	BOOL hitBreakPoint = NO;
	NSMutableArray *breakPointsToNotify = [[NSMutableArray alloc] init];
	
	for (ZGBreakPoint *breakPoint in self.breakPoints)
	{
		if (breakPoint.type != ZGBreakPointInstruction)
		{
			continue;
		}
		
		if (breakPoint.task == task)
		{
			breakPoint.thread = thread;
			
			// Remove single-stepping
			if (breakPoint.process.is64Bit)
			{
				threadState.uts.ts64.__rflags &= ~(1 << 8);
			}
			else
			{
				threadState.uts.ts32.__eflags &= ~(1 << 8);
			}
			
			// If we had single-stepped in here, use current program counter, otherwise use instruction address before program counter
			BOOL foundSingleStepBreakPoint = NO;
			for (ZGBreakPoint *candidateBreakPoint in self.breakPoints)
			{
				if (candidateBreakPoint.type == ZGBreakPointSingleStepInstruction && candidateBreakPoint.task == task && candidateBreakPoint.thread == thread)
				{
					foundSingleStepBreakPoint = YES;
					break;
				}
			}
			
			ZGMemoryAddress foundInstructionAddress = 0x0;
			
			if (foundSingleStepBreakPoint)
			{
				foundInstructionAddress = (breakPoint.process.is64Bit ? threadState.uts.ts64.__rip : threadState.uts.ts32.__eip);
			}
			else
			{
				ZGInstruction *foundInstruction = [[[ZGAppController sharedController] debuggerController] findInstructionBeforeAddress:(breakPoint.process.is64Bit ? threadState.uts.ts64.__rip : threadState.uts.ts32.__eip) inProcess:breakPoint.process];
				foundInstructionAddress = foundInstruction.variable.address;
			}
			
			if (foundInstructionAddress == breakPoint.variable.address)
			{
				uint8_t *opcode = NULL;
				ZGMemorySize opcodeSize = 0x1;
				
				if (ZGReadBytes(breakPoint.process.processTask, foundInstructionAddress, (void **)&opcode, &opcodeSize))
				{
					if (*opcode == INSTRUCTION_BREAKPOINT_OPCODE)
					{
						hitBreakPoint = YES;
						ZGSuspendTask(task);
						
						// Restore program counter
						if (breakPoint.process.is64Bit)
						{
							threadState.uts.ts64.__rip = breakPoint.variable.address;
						}
						else
						{
							threadState.uts.ts32.__eip = (uint32_t)breakPoint.variable.address;
						}
						
						[breakPointsToNotify addObject:breakPoint];
					}
					
					ZGFreeBytes(breakPoint.process.processTask, opcode, opcodeSize);
				}
				
				handledInstructionBreakPoint = YES;
			}
			
			if (breakPoint.needsToRestore)
			{
				// Restore our breakpoint
				uint8_t writeOpcode = INSTRUCTION_BREAKPOINT_OPCODE;
				ZGWriteBytesIgnoringProtection(breakPoint.process.processTask, breakPoint.variable.address, &writeOpcode, sizeof(uint8_t));
				
				breakPoint.needsToRestore = NO;
				handledInstructionBreakPoint = YES;
			}
		}
	}
	
	for (ZGBreakPoint *candidateBreakPoint in self.breakPoints)
	{
		if (candidateBreakPoint.type != ZGBreakPointSingleStepInstruction)
		{
			continue;
		}
		
		if (candidateBreakPoint.task == task && candidateBreakPoint.thread == thread)
		{
			// Remove single-stepping
			if (candidateBreakPoint.process.is64Bit)
			{
				threadState.uts.ts64.__rflags &= ~(1 << 8);
			}
			else
			{
				threadState.uts.ts32.__eflags &= ~(1 << 8);
			}
			
			if (!hitBreakPoint)
			{
				ZGSuspendTask(task);
				
				candidateBreakPoint.variable = [[ZGVariable alloc] initWithValue:NULL size:1 address:(candidateBreakPoint.process.is64Bit ? threadState.uts.ts64.__rip : threadState.uts.ts32.__eip) type:ZGByteArray qualifier:0 pointerSize:candidateBreakPoint.process.pointerSize];
				
				[breakPointsToNotify addObject:candidateBreakPoint];
				
				hitBreakPoint = YES;
			}
			
			[self removeBreakPoint:candidateBreakPoint];
			
			handledInstructionBreakPoint = YES;
		}
	}
	
	if (handledInstructionBreakPoint)
	{
		if (thread_set_state(thread, x86_THREAD_STATE, (thread_state_t)&threadState, threadStateCount) != KERN_SUCCESS)
		{
			NSLog(@"Failure in setting registers thread state for catching instruction breakpoint for thread %d", thread);
		}
	}
	
	// We should notify delegates if a breakpoint hits after we modify thread states
	if (breakPointsToNotify.count > 0)
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			for (ZGBreakPoint *breakPoint in breakPointsToNotify)
			{
				if ([breakPoint.delegate respondsToSelector:@selector(breakPointDidHit:)])
				{
					[breakPoint.delegate performSelector:@selector(breakPointDidHit:) withObject:breakPoint];
				}
			}
		});
	}
	
	ZGResumeTask(task);
	
	return handledInstructionBreakPoint;
}

kern_return_t catch_mach_exception_raise(mach_port_t exception_port, mach_port_t thread, mach_port_t task, exception_type_t exception, exception_data_t code, mach_msg_type_number_t code_count)
{
	BOOL handledWatchPoint = [[[ZGAppController sharedController] breakPointController] handleWatchPointsWithTask:task inThread:thread];
	BOOL handledInstructionBreakPoint = [[[ZGAppController sharedController] breakPointController] handleInstructionBreakPointsWithTask:task inThread:thread];
	
	return (handledWatchPoint || handledInstructionBreakPoint) ? KERN_SUCCESS : KERN_FAILURE;
}

- (void)removeObserver:(id)observer
{
	[self removeObserver:observer runningProcess:nil];
}

- (void)removeObserver:(id)observer runningProcess:(ZGRunningProcess *)process
{
	for (ZGBreakPoint *breakPoint in self.breakPoints)
	{
		if (breakPoint.delegate == observer && (!process || breakPoint.process.processID == process.processIdentifier))
		{
			BOOL isDead = YES;
			
			for (ZGRunningProcess *runningProcess in [[ZGProcessList sharedProcessList] runningProcesses])
			{
				if (runningProcess.processIdentifier == breakPoint.process.processID)
				{
					isDead = NO;
					break;
				}
			}
			
			if (isDead || breakPoint.type == ZGBreakPointSingleStepInstruction)
			{
				[self removeBreakPoint:breakPoint];
			}
			else if (breakPoint.type == ZGBreakPointWatchData)
			{
				ZGSuspendTask(breakPoint.task);
				[self removeWatchPoint:breakPoint];
				ZGResumeTask(breakPoint.task);
			}
			else if (breakPoint.type == ZGBreakPointInstruction)
			{
				[self removeInstructionBreakPoint:breakPoint];
			}
		}
	}
}

- (BOOL)setUpExceptionPortForProcess:(ZGProcess *)process
{
	if (self.exceptionPort == MACH_PORT_NULL)
	{
		if (mach_port_allocate(current_task(), MACH_PORT_RIGHT_RECEIVE, &_exceptionPort) != KERN_SUCCESS)
		{
			NSLog(@"ERROR: Could not allocate mach port for adding breakpoint");
			self.exceptionPort = MACH_PORT_NULL;
			return NO;
		}
		
		if (mach_port_insert_right(current_task(), self.exceptionPort, self.exceptionPort, MACH_MSG_TYPE_MAKE_SEND) != KERN_SUCCESS)
		{
			NSLog(@"ERROR: Could not insert send right for watchpoint");
			if (mach_port_deallocate(current_task(), self.exceptionPort) != KERN_SUCCESS)
			{
				NSLog(@"ERROR: Could not deallocate exception port in adding breakpoint");
			}
			self.exceptionPort = MACH_PORT_NULL;
			return NO;
		}
	}
	
	if (task_set_exception_ports(process.processTask, EXC_MASK_BREAKPOINT, self.exceptionPort, EXCEPTION_DEFAULT | MACH_EXCEPTION_CODES, MACHINE_THREAD_STATE) != KERN_SUCCESS)
	{
		NSLog(@"ERROR: task_set_exception_ports failed on adding breakpoint");
		return NO;
	}
	
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

#define IS_REGISTER_AVAILABLE(type) (!(debugState.uds.type.__dr7 & (1 << 2*registerIndex)) && !(debugState.uds.type.__dr7 & (1 << 2*registerIndex+1)))

#define WRITE_BREAKPOINT_IN_DEBUG_REGISTERS(type, typecast) \
	if (debugRegisterIndex == 0) { debugState.uds.type.__dr0 = (typecast)variable.address; } \
	else if (debugRegisterIndex == 1) { debugState.uds.type.__dr1 = (typecast)variable.address; } \
	else if (debugRegisterIndex == 2) { debugState.uds.type.__dr2 = (typecast)variable.address; } \
	else if (debugRegisterIndex == 3) { debugState.uds.type.__dr3 = (typecast)variable.address; } \
	\
	debugState.uds.type.__dr7 |= (1 << 2*debugRegisterIndex); \
	debugState.uds.type.__dr7 &= ~(1 << 2*debugRegisterIndex+1); \
	\
	debugState.uds.type.__dr7 |= (1 << 16 + 2*debugRegisterIndex); \
	if (watchPointType == ZGWatchPointWrite) { debugState.uds.type.__dr7 &= ~(1 << 16 + 2*debugRegisterIndex+1); } \
	else if (watchPointType == ZGWatchPointReadOrWrite) { debugState.uds.type.__dr7 |= (1 << 16 + 2*debugRegisterIndex+1); } \
	\
	if (watchSize == 1) { debugState.uds.type.__dr7 &= ~(1 << 18 + 2*debugRegisterIndex); debugState.uds.type.__dr7 &= ~(1 << 18 + 2*debugRegisterIndex+1); } \
	else if (watchSize == 2) { debugState.uds.type.__dr7 |= (1 << 18 + 2*debugRegisterIndex); debugState.uds.type.__dr7 &= ~(1 << 18 + 2*debugRegisterIndex+1); } \
	else if (watchSize == 4) { debugState.uds.type.__dr7 |= (1 << 18 + 2*debugRegisterIndex); debugState.uds.type.__dr7 |= (1 << 18 + 2*debugRegisterIndex+1); } \
	else if (watchSize == 8) { debugState.uds.type.__dr7 &= ~(1 << 18 + 2*debugRegisterIndex); debugState.uds.type.__dr7 |= (1 << 18 + 2*debugRegisterIndex+1); }

- (BOOL)addWatchpointOnVariable:(ZGVariable *)variable inProcess:(ZGProcess *)process watchPointType:(ZGWatchPointType)watchPointType delegate:(id)delegate getBreakPoint:(ZGBreakPoint **)returnedBreakPoint
{
	if (![self setUpExceptionPortForProcess:process])
	{
		return NO;
	}
	
	ZGMemorySize watchSize = 0;
	if (variable.size == 1)
	{
		watchSize = 1;
	}
	else if (variable.size == 2)
	{
		watchSize = 2;
	}
	else if (variable.size <= 4 || !process.is64Bit)
	{
		watchSize = 4;
	}
	else
	{
		watchSize = 8;
	}
	
	for (ZGBreakPoint *breakPoint in self.breakPoints)
	{
		if (variable.address + watchSize > breakPoint.variable.address && variable.address < breakPoint.variable.address + breakPoint.watchSize)
		{
			NSLog(@"A watchpoint is already watching around this area");
			return NO;
		}
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
			
			if (process.is64Bit)
			{	
				WRITE_BREAKPOINT_IN_DEBUG_REGISTERS(ds64, uint64_t);
			}
			else
			{
				WRITE_BREAKPOINT_IN_DEBUG_REGISTERS(ds32, uint32_t);
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
	
	if (mach_vm_deallocate(current_task(), (mach_vm_address_t)threadList, threadListCount * sizeof(thread_act_t)) != KERN_SUCCESS)
	{
		NSLog(@"Failed to deallocate thread list in addWatchpointOnVariable...");
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
	breakPoint.watchSize = watchSize;
	breakPoint.process = process;
	breakPoint.type = ZGBreakPointWatchData;
	
	[self addBreakPoint:breakPoint];
	
	if (returnedBreakPoint)
	{
		*returnedBreakPoint = breakPoint;
	}
	
	return YES;
}

- (BOOL)addBreakPointOnInstruction:(ZGInstruction *)instruction inProcess:(ZGProcess *)process delegate:(id)delegate
{
	return [self addBreakPointOnInstruction:instruction inProcess:process thread:0 basePointer:0 hidden:NO delegate:delegate];
}

- (BOOL)addBreakPointOnInstruction:(ZGInstruction *)instruction inProcess:(ZGProcess *)process thread:(thread_act_t)thread basePointer:(ZGMemoryAddress)basePointer delegate:(id)delegate
{
	return [self addBreakPointOnInstruction:instruction inProcess:process thread:thread basePointer:basePointer hidden:YES delegate:delegate];
}

- (BOOL)addBreakPointOnInstruction:(ZGInstruction *)instruction inProcess:(ZGProcess *)process thread:(thread_act_t)thread basePointer:(ZGMemoryAddress)basePointer hidden:(BOOL)isHidden delegate:(id)delegate
{
	if (![self setUpExceptionPortForProcess:process])
	{
		return NO;
	}
	
	BOOL breakPointAlreadyExists = NO;
	for (ZGBreakPoint *breakPoint in self.breakPoints)
	{
		if (breakPoint.type == ZGBreakPointInstruction && breakPoint.task == process.processTask && breakPoint.variable.address == instruction.variable.address)
		{
			breakPointAlreadyExists = YES;
			break;
		}
	}
	
	if (breakPointAlreadyExists)
	{
		return NO;
	}
	
	// Find memory protection of instruction. If it's not executable, make it executable
	ZGMemoryAddress protectionAddress = instruction.variable.address;
	ZGMemorySize protectionSize = instruction.variable.size;
	ZGMemoryProtection memoryProtection = 0;
	if (!ZGMemoryProtectionInRegion(process.processTask, &protectionAddress, &protectionSize, &memoryProtection))
	{
		return NO;
	}
	
	if (protectionAddress > instruction.variable.address || protectionAddress + protectionSize < instruction.variable.address + instruction.variable.size)
	{
		return NO;
	}
	
	if (!(memoryProtection & VM_PROT_EXECUTE))
	{
		memoryProtection |= VM_PROT_EXECUTE;
		if (!ZGProtect(process.processTask, protectionAddress, protectionSize, memoryProtection))
		{
			return NO;
		}
	}
	
	ZGVariable *variable = [instruction.variable copy];
	
	uint8_t breakPointOpcode = INSTRUCTION_BREAKPOINT_OPCODE;
	BOOL success = ZGWriteBytesIgnoringProtection(process.processTask, variable.address, &breakPointOpcode, sizeof(uint8_t));
	if (success)
	{
		ZGBreakPoint *breakPoint = [[ZGBreakPoint alloc] init];
		breakPoint.delegate = delegate;
		breakPoint.task = process.processTask;
		breakPoint.variable = variable;
		breakPoint.process = process;
		breakPoint.type = ZGBreakPointInstruction;
		breakPoint.hidden = isHidden;
		breakPoint.thread = thread;
		breakPoint.basePointer = basePointer;
		
		[self addBreakPoint:breakPoint];
	}
	
	return success;
}

- (void)addSingleStepBreakPointFromBreakPoint:(ZGBreakPoint *)breakPoint
{
	ZGBreakPoint *singleStepBreakPoint = [[ZGBreakPoint alloc] init];
	singleStepBreakPoint.process = breakPoint.process;
	singleStepBreakPoint.delegate = breakPoint.delegate;
	singleStepBreakPoint.task = breakPoint.task;
	singleStepBreakPoint.thread = breakPoint.thread;
	singleStepBreakPoint.type = ZGBreakPointSingleStepInstruction;
	
	[self addBreakPoint:singleStepBreakPoint];
}

- (void)addBreakPoint:(ZGBreakPoint *)breakPoint
{
	NSMutableArray *currentBreakPoints = [NSMutableArray arrayWithArray:self.breakPoints];
	[currentBreakPoints addObject:breakPoint];
	self.breakPoints = [NSArray arrayWithArray:currentBreakPoints];
}

- (void)removeBreakPoint:(ZGBreakPoint *)breakPoint
{
	NSMutableArray *currentBreakPoints = [NSMutableArray arrayWithArray:self.breakPoints];
	[currentBreakPoints removeObject:breakPoint];
	self.breakPoints = [NSArray arrayWithArray:currentBreakPoints];
}

@end
