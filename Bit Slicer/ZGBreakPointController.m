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
#import "ZGRegisterUtilities.h"
#import "ZGVariable.h"
#import "ZGProcess.h"
#import "ZGDebugThread.h"
#import "ZGBreakPoint.h"
#import "ZGInstruction.h"
#import "ZGDebuggerController.h"
#import "ZGProcessList.h"
#import "ZGRunningProcess.h"
#import "ZGScriptManager.h"
#import "ZGRegistersController.h"
#import "ZGUtilities.h"
#import "NSArrayAdditions.h"

#import <mach/task.h>
#import <mach/thread_act.h>
#import <mach/mach_port.h>
#import <mach/mach.h>

@interface ZGBreakPointController ()

@property (readwrite, nonatomic) mach_port_t exceptionPort;
@property (nonatomic) BOOL delayedTermination;

@end

@implementation ZGBreakPointController

extern boolean_t mach_exc_server(mach_msg_header_t *InHeadP, mach_msg_header_t *OutHeadP);

#define RESTORE_BREAKPOINT_IN_DEBUG_REGISTERS(type) \
	if (debugRegisterIndex == 0) { debugState.uds.type.__dr0 = 0x0; } \
	else if (debugRegisterIndex == 1) { debugState.uds.type.__dr1 = 0x0; } \
	else if (debugRegisterIndex == 2) { debugState.uds.type.__dr2 = 0x0; } \
	else if (debugRegisterIndex == 3) { debugState.uds.type.__dr3 = 0x0; } \
	\
	debugState.uds.type.__dr6 &= ~(1 << debugRegisterIndex); \
	\
	debugState.uds.type.__dr7 &= ~(1 << (2*debugRegisterIndex)); \
	debugState.uds.type.__dr7 &= ~(1 << (2*debugRegisterIndex+1)); \
	\
	debugState.uds.type.__dr7 &= ~(1 << (16 + 4*debugRegisterIndex)); \
	debugState.uds.type.__dr7 &= ~(1 << (16 + 4*debugRegisterIndex+1)); \
	\
	debugState.uds.type.__dr7 &= ~(1 << (18 + 4*debugRegisterIndex)); \
	debugState.uds.type.__dr7 &= ~(1 << (18 + 4*debugRegisterIndex+1)); \

- (void)removeWatchPoint:(ZGBreakPoint *)breakPoint
{
	thread_act_array_t threadList = NULL;
	mach_msg_type_number_t threadListCount = 0;
	if (task_threads(breakPoint.process.processTask, &threadList, &threadListCount) != KERN_SUCCESS)
	{
		NSLog(@"ERROR: task_threads failed on removing watchpoint");
		return;
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
		mach_msg_type_number_t stateCount;
		if (!ZGGetDebugThreadState(&debugState, debugThread.thread, &stateCount))
		{
			NSLog(@"ERROR: Grabbing debug state failed in removeWatchPoint: continuing...");
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
		
		if (!ZGSetDebugThreadState(&debugState, debugThread.thread, stateCount))
		{
			NSLog(@"ERROR: Failure in setting thread state registers in removeWatchPoint:");
		}
	}
	
	if (!ZGDeallocateMemory(current_task(), (mach_vm_address_t)threadList, threadListCount * sizeof(thread_act_t)))
	{
		NSLog(@"Failed to deallocate thread list in removeWatchPoint...");
	}
	
	// we may still catch exceptions momentarily for our breakpoint if the data is being acccessed frequently, so do not remove it immediately
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
		[self removeBreakPoint:breakPoint];
	});
}

#define IS_DEBUG_REGISTER_AND_STATUS_ENABLED(debugState, debugRegisterIndex, type) \
	(((debugState.uds.type.__dr6 & (1 << debugRegisterIndex)) != 0) && ((debugState.uds.type.__dr7 & (1 << 2*debugRegisterIndex)) != 0))

- (BOOL)handleWatchPointsWithTask:(mach_port_t)task inThread:(mach_port_t)thread
{
	BOOL handledWatchPoint = NO;
	for (ZGBreakPoint *breakPoint in self.breakPoints)
	{
		if (breakPoint.type != ZGBreakPointWatchData)
		{
			continue;
		}
		
		if (breakPoint.task != task)
		{
			continue;
		}
		
		ZGSuspendTask(task);
		
		for (ZGDebugThread *debugThread in breakPoint.debugThreads)
		{
			if (debugThread.thread != thread)
			{
				continue;
			}
			
			x86_debug_state_t debugState;
			mach_msg_type_number_t debugStateCount;
			if (!ZGGetDebugThreadState(&debugState, thread, &debugStateCount))
			{
				continue;
			}
			
			int debugRegisterIndex = debugThread.registerNumber;
			
			BOOL isWatchPointAvailable = breakPoint.process.is64Bit ? IS_DEBUG_REGISTER_AND_STATUS_ENABLED(debugState, debugRegisterIndex, ds64) : IS_DEBUG_REGISTER_AND_STATUS_ENABLED(debugState, debugRegisterIndex, ds32);
			
			if (!isWatchPointAvailable)
			{
				continue;
			}
			
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
			
			if (!ZGSetDebugThreadState(&debugState, debugThread.thread, debugStateCount))
			{
				//NSLog(@"ERROR: Failure in setting debug thread registers for clearing dr6 in handle watchpoint...Not good.");
			}
			
			x86_thread_state_t threadState;
			if (!ZGGetGeneralThreadState(&threadState, thread, NULL))
			{
				continue;
			}
			
			ZGMemoryAddress instructionAddress = breakPoint.process.is64Bit ? (ZGMemoryAddress)threadState.uts.ts64.__rip : (ZGMemoryAddress)threadState.uts.ts32.__eip;
			
			zg_x86_vector_state_t vectorState;
			bool hasAVXSupport = NO;
			BOOL retrievedVectorState = ZGGetVectorThreadState(&vectorState, thread, NULL, breakPoint.process.is64Bit, &hasAVXSupport);
			
			breakPoint.generalPurposeThreadState = threadState;
			breakPoint.vectorState = vectorState;
			breakPoint.hasVectorState = retrievedVectorState;
			breakPoint.hasAVXSupport = hasAVXSupport;
			
			dispatch_async(dispatch_get_main_queue(), ^{
				@synchronized(self)
				{
					[breakPoint.delegate dataAccessedByBreakPoint:breakPoint fromInstructionPointer:instructionAddress];
				}
			});
		}
		
		ZGResumeTask(task);
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
	mach_msg_type_number_t threadStateCount;
	if (!ZGGetGeneralThreadState(&threadState, breakPoint.thread, &threadStateCount))
	{
			//NSLog(@"ERROR: Grabbing thread state failed in resumeFromBreakPoint:");
	}
	
	BOOL shouldSingleStep = NO;
	
	// Check if breakpoint still exists
	if (breakPoint.type == ZGBreakPointInstruction && [self.breakPoints containsObject:breakPoint])
	{
		// Restore our instruction
		ZGWriteBytesOverwritingProtection(breakPoint.process.processTask, breakPoint.variable.address, breakPoint.variable.value, sizeof(uint8_t));
		
		breakPoint.needsToRestore = YES;
		
		if (!breakPoint.dead)
		{
			// Ensure single-stepping, so on next instruction we can restore our breakpoint
			shouldSingleStep = YES;
		}
		else
		{
			[self removeBreakPoint:breakPoint];
		}
	}
	else
	{
		for (ZGBreakPoint *candidateBreakPoint in self.breakPoints)
		{
			if (candidateBreakPoint.type == ZGBreakPointSingleStepInstruction && candidateBreakPoint.thread == breakPoint.thread && candidateBreakPoint.task == breakPoint.task)
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
	
	if (!ZGSetGeneralThreadState(&threadState, breakPoint.thread, threadStateCount))
	{
		//NSLog(@"Failure in setting registers thread state for resumeFromBreakPoint: for thread %d", breakPoint.thread);
	}
	
	ZGResumeTask(breakPoint.process.processTask);
}

- (void)revertInstructionBackToNormal:(ZGBreakPoint *)breakPoint
{
	ZGWriteBytesOverwritingProtection(breakPoint.process.processTask, breakPoint.variable.address, breakPoint.variable.value, sizeof(uint8_t));
	ZGProtect(breakPoint.process.processTask, breakPoint.variable.address, breakPoint.variable.size, breakPoint.originalProtection);
}

- (void)removeInstructionBreakPoint:(ZGBreakPoint *)breakPoint
{
	if (breakPoint.condition != NULL)
	{
		// Mark breakpoint as dead. if the breakpoint is called frequently (esp. with a falsely evaluated condition), it will be removed when resuming from a breakpoint
		// We handle a breakpoint by reverting the instruction back to normal, single stepping, then reverting the instruction opcode back to being breaked
		// If we just removed the breakpoint immediately here, and the process single steps, the handler won't know why the exception was raised
		// Our work around here is giving the process a little delay (perhaps a better way might be to add a single-stepping breakpoint and remove it from there)
		breakPoint.dead = YES;
		
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^(void) {
			if ([self.breakPoints containsObject:breakPoint])
			{
				ZGSuspendTask(breakPoint.process.processTask);
				
				[self revertInstructionBackToNormal:breakPoint];
				[self removeBreakPoint:breakPoint];
				
				ZGResumeTask(breakPoint.process.processTask);
			}
			
			if (self.delayedTermination && self.breakPoints.count == 0)
			{
				[[ZGAppController sharedController] decreaseLivingCount];
			}
		});
	}
	else
	{
		[self revertInstructionBackToNormal:breakPoint];
		[self removeBreakPoint:breakPoint];
	}
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
	NSArray *breakPoints = self.breakPoints;
	
	ZGSuspendTask(task);
	
	x86_thread_state_t threadState;
	mach_msg_type_number_t threadStateCount;
	if (!ZGGetGeneralThreadState(&threadState, thread, &threadStateCount))
	{
		//NSLog(@"ERROR: Grabbing thread state failed in obtaining instruction address, skipping.");
	}
	
	BOOL hitBreakPoint = NO;
	NSMutableArray *breakPointsToNotify = [[NSMutableArray alloc] init];
	
	for (ZGBreakPoint *breakPoint in breakPoints)
	{
		if (breakPoint.type != ZGBreakPointInstruction)
		{
			continue;
		}
		
		if (breakPoint.task != task)
		{
			continue;
		}
		
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
		ZGMemoryAddress instructionPointer = breakPoint.process.is64Bit ? threadState.uts.ts64.__rip : threadState.uts.ts32.__eip;
		
		if (foundSingleStepBreakPoint)
		{
			foundInstructionAddress = instructionPointer;
		}
		else
		{
			NSNumber *instructionPointerNumber = @(instructionPointer);
			NSNumber *existingInstructionAddress = [breakPoint.cacheDictionary objectForKey:instructionPointerNumber];
			if (existingInstructionAddress == nil)
			{
				ZGInstruction *foundInstruction = [[[ZGAppController sharedController] debuggerController] findInstructionBeforeAddress:instructionPointer inProcess:breakPoint.process];
				foundInstructionAddress = foundInstruction.variable.address;
				[breakPoint.cacheDictionary setObject:@(foundInstructionAddress) forKey:instructionPointerNumber];
			}
			else
			{
				foundInstructionAddress = [existingInstructionAddress unsignedLongLongValue];
			}
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
			ZGWriteBytesOverwritingProtection(breakPoint.process.processTask, breakPoint.variable.address, &writeOpcode, sizeof(uint8_t));
			
			breakPoint.needsToRestore = NO;
			handledInstructionBreakPoint = YES;
		}
	}
	
	for (ZGBreakPoint *candidateBreakPoint in breakPoints)
	{
		if (candidateBreakPoint.type != ZGBreakPointSingleStepInstruction)
		{
			continue;
		}
		
		if (candidateBreakPoint.task != task || candidateBreakPoint.thread != thread)
		{
			continue;
		}
		
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
	
	if (handledInstructionBreakPoint)
	{
		if (!ZGSetGeneralThreadState(&threadState, thread, threadStateCount))
		{
			//NSLog(@"Failure in setting registers thread state for catching instruction breakpoint for thread %d", thread);
		}
	}
	
	ZGRegisterEntry registerEntries[ZG_MAX_REGISTER_ENTRIES];
	BOOL retrievedRegisterEntries = NO;
	BOOL retrievedVectorState = NO;
	bool hasAVXSupport = NO;
	zg_x86_vector_state_t vectorState;
	
	// We should notify delegates if a breakpoint hits after we modify thread states
	for (ZGBreakPoint *breakPoint in breakPointsToNotify)
	{
		BOOL canNotifyDelegate = !breakPoint.dead;
		
		if (canNotifyDelegate && !retrievedRegisterEntries)
		{
			BOOL is64Bit = breakPoint.process.is64Bit;
			
			int numberOfGeneralPurposeEntries = [ZGRegistersController getRegisterEntries:registerEntries fromGeneralPurposeThreadState:threadState is64Bit:is64Bit];
			
			retrievedVectorState = ZGGetVectorThreadState(&vectorState, thread, NULL, breakPoint.process.is64Bit, &hasAVXSupport);
			if (retrievedVectorState)
			{
				[ZGRegistersController getRegisterEntries:registerEntries + numberOfGeneralPurposeEntries fromVectorThreadState:vectorState is64Bit:is64Bit hasAVXSupport:hasAVXSupport];
			}
			
			retrievedRegisterEntries = YES;
		}
		
		if (canNotifyDelegate && breakPoint.condition != NULL)
		{
			NSError *error = nil;
			if (![ZGScriptManager evaluateCondition:breakPoint.condition process:breakPoint.process registerEntries:registerEntries error:&error])
			{
				if (error == nil)
				{
					canNotifyDelegate = NO;
				}
				else
				{
					breakPoint.error = error;
				}
			}
		}
		
		if (canNotifyDelegate)
		{
			breakPoint.generalPurposeThreadState = threadState;
			breakPoint.vectorState = vectorState;
			breakPoint.hasVectorState = retrievedVectorState;
			breakPoint.hasAVXSupport = hasAVXSupport;
			
			dispatch_async(dispatch_get_main_queue(), ^{
				@synchronized(self)
				{
					if (breakPoint.delegate != nil)
					{
						[breakPoint.delegate breakPointDidHit:breakPoint];
					}
					else
					{
						[self resumeFromBreakPoint:breakPoint];
					}
				}
			});
		}
		else
		{
			[self resumeFromBreakPoint:breakPoint];
		}
	}
	
	ZGResumeTask(task);
	
	return handledInstructionBreakPoint;
}

kern_return_t  catch_mach_exception_raise_state(mach_port_t exception_port, exception_type_t exception, exception_data_t code, mach_msg_type_number_t code_count, int *flavor, thread_state_t in_state, mach_msg_type_number_t in_state_count, thread_state_t out_state, mach_msg_type_number_t *out_state_count)
{
	return KERN_FAILURE;
}

kern_return_t   catch_mach_exception_raise_state_identity(mach_port_t exception_port, mach_port_t thread, mach_port_t task, exception_type_t exception, exception_data_t code, mach_msg_type_number_t code_count, int *flavor, thread_state_t in_state, mach_msg_type_number_t in_state_count, thread_state_t out_state, mach_msg_type_number_t *out_state_count)
{
	return KERN_FAILURE;
}

kern_return_t catch_mach_exception_raise(mach_port_t exception_port, mach_port_t thread, mach_port_t task, exception_type_t exception, exception_data_t code, mach_msg_type_number_t code_count)
{
	BOOL handledWatchPoint = NO;
	BOOL handledInstructionBreakPoint = NO;
	
	if (exception == EXC_BREAKPOINT)
	{
		handledWatchPoint = [[[ZGAppController sharedController] breakPointController] handleWatchPointsWithTask:task inThread:thread];
		handledInstructionBreakPoint = [[[ZGAppController sharedController] breakPointController] handleInstructionBreakPointsWithTask:task inThread:thread];
	}
	
	return (handledWatchPoint || handledInstructionBreakPoint) ? KERN_SUCCESS : KERN_FAILURE;
}

- (void)removeObserver:(id)observer
{
	[self removeObserver:observer runningProcess:nil withProcessID:-1 atAddress:0];
}

- (void)removeObserver:(id)observer withProcessID:(pid_t)processID atAddress:(ZGMemoryAddress)address
{
	[self removeObserver:observer runningProcess:nil withProcessID:processID atAddress:address];
}

- (void)removeObserver:(id)observer runningProcess:(ZGRunningProcess *)process
{
	[self removeObserver:observer runningProcess:process withProcessID:-1 atAddress:0];
}

- (void)removeObserver:(id)observer runningProcess:(ZGRunningProcess *)process withProcessID:(pid_t)processID atAddress:(ZGMemoryAddress)address
{
	@synchronized(self)
	{
		for (ZGBreakPoint *breakPoint in self.breakPoints)
		{
			if (processID <= 0 || (processID == breakPoint.process.processID && breakPoint.variable.address == address))
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
					
					breakPoint.delegate = nil;
					
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
						if (!self.delayedTermination && breakPoint.condition != NULL && [[ZGAppController sharedController] isTerminating])
						{
							self.delayedTermination = YES;
							[[ZGAppController sharedController] increaseLivingCount];
						}
						
						[self removeInstructionBreakPoint:breakPoint];
					}
				}
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
			if (!ZGDeallocatePort(self.exceptionPort))
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
				NSLog(@"mach_msg_server() returned on error!");
			}
		});
    });
	
	return YES;
}

#define IS_REGISTER_AVAILABLE(type) (!(debugState.uds.type.__dr7 & (1 << (2*registerIndex))) && !(debugState.uds.type.__dr7 & (1 << (2*registerIndex+1))))

#define WRITE_BREAKPOINT_IN_DEBUG_REGISTERS(debugRegisterIndex, debugState, variable, type, typecast) \
	if (debugRegisterIndex == 0) { debugState.uds.type.__dr0 = (typecast)variable.address; } \
	else if (debugRegisterIndex == 1) { debugState.uds.type.__dr1 = (typecast)variable.address; } \
	else if (debugRegisterIndex == 2) { debugState.uds.type.__dr2 = (typecast)variable.address; } \
	else if (debugRegisterIndex == 3) { debugState.uds.type.__dr3 = (typecast)variable.address; } \
	\
	debugState.uds.type.__dr7 |= (1 << (2*debugRegisterIndex)); \
	debugState.uds.type.__dr7 &= ~(1 << (2*debugRegisterIndex+1)); \
	\
	debugState.uds.type.__dr7 |= (1 << (16 + 4*debugRegisterIndex)); \
	\
	if (watchPointType == ZGWatchPointWrite) { debugState.uds.type.__dr7 &= ~(1 << (16 + 4*debugRegisterIndex+1)); } \
	else if (watchPointType == ZGWatchPointReadOrWrite) { debugState.uds.type.__dr7 |= (1 << (16 + 4*debugRegisterIndex+1)); } \
	\
	if (watchSize == 1) { debugState.uds.type.__dr7 &= ~(1 << (18 + 4*debugRegisterIndex)); debugState.uds.type.__dr7 &= ~(1 << (18 + 4*debugRegisterIndex+1)); } \
	else if (watchSize == 2) { debugState.uds.type.__dr7 |= (1 << (18 + 4*debugRegisterIndex)); debugState.uds.type.__dr7 &= ~(1 << (18 + 4*debugRegisterIndex+1)); } \
	else if (watchSize == 4) { debugState.uds.type.__dr7 |= (1 << (18 + 4*debugRegisterIndex)); debugState.uds.type.__dr7 |= (1 << (18 + 4*debugRegisterIndex+1)); } \
	else if (watchSize == 8) { debugState.uds.type.__dr7 &= ~(1 << (18 + 4*debugRegisterIndex)); debugState.uds.type.__dr7 |= (1 << (18 + 4*debugRegisterIndex+1)); }

- (BOOL)addWatchpointOnVariable:(ZGVariable *)variable inProcess:(ZGProcess *)process watchPointType:(ZGWatchPointType)watchPointType delegate:(id <ZGBreakPointDelegate>)delegate getBreakPoint:(ZGBreakPoint **)returnedBreakPoint
{
	@synchronized(self)
	{
		if (![self setUpExceptionPortForProcess:process])
		{
			return NO;
		}
		
		ZGMemorySize watchSize = 0;
		if (variable.size <= 1)
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
			mach_msg_type_number_t stateCount;
			if (!ZGGetDebugThreadState(&debugState, threadList[threadIndex], &stateCount))
			{
				NSLog(@"ERROR: ZGGetDebugThreadState failed on adding watchpoint for thread %d", threadList[threadIndex]);
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
					WRITE_BREAKPOINT_IN_DEBUG_REGISTERS(debugRegisterIndex, debugState, variable, ds64, uint64_t);
				}
				else
				{
					WRITE_BREAKPOINT_IN_DEBUG_REGISTERS(debugRegisterIndex, debugState, variable, ds32, uint32_t);
				}
				
				if (!ZGSetDebugThreadState(&debugState, threadList[threadIndex], stateCount))
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
		
		if (!ZGDeallocateMemory(current_task(), (mach_vm_address_t)threadList, threadListCount * sizeof(thread_act_t)))
		{
			NSLog(@"Failed to deallocate thread list in addWatchpointOnVariable...");
		}
		
		ZGResumeTask(process.processTask);
		
		if (debugThreads.count == 0)
		{
			NSLog(@"ERROR: Failed to set watch variable.");
			return NO;
		}
		
		ZGBreakPoint *breakPoint = [[ZGBreakPoint alloc] initWithProcess:process type:ZGBreakPointWatchData delegate:delegate];
		breakPoint.debugThreads = [NSArray arrayWithArray:debugThreads];
		breakPoint.variable = variable;
		breakPoint.watchSize = watchSize;
		
		[self addBreakPoint:breakPoint];
		
		if (returnedBreakPoint)
		{
			*returnedBreakPoint = breakPoint;
		}
	}
	
	return YES;
}

- (BOOL)addBreakPointOnInstruction:(ZGInstruction *)instruction inProcess:(ZGProcess *)process condition:(PyObject *)condition delegate:(id)delegate
{
	return [self addBreakPointOnInstruction:instruction inProcess:process thread:0 basePointer:0 hidden:NO condition:condition delegate:delegate];
}

- (BOOL)addBreakPointOnInstruction:(ZGInstruction *)instruction inProcess:(ZGProcess *)process thread:(thread_act_t)thread basePointer:(ZGMemoryAddress)basePointer delegate:(id)delegate
{
	return [self addBreakPointOnInstruction:instruction inProcess:process thread:thread basePointer:basePointer hidden:YES condition:nil delegate:delegate];
}

- (BOOL)addBreakPointOnInstruction:(ZGInstruction *)instruction inProcess:(ZGProcess *)process thread:(thread_act_t)thread basePointer:(ZGMemoryAddress)basePointer hidden:(BOOL)isHidden condition:(PyObject *)condition delegate:(id)delegate
{
	if (![self setUpExceptionPortForProcess:process])
	{
		return NO;
	}
	
	BOOL breakPointAlreadyExists = NO;
	for (ZGBreakPoint *breakPoint in self.breakPoints)
	{
		if (breakPoint.type == ZGBreakPointInstruction && breakPoint.task == process.processTask && breakPoint.variable.address == instruction.variable.address && breakPoint.delegate == delegate)
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
	}
	
	if (!ZGProtect(process.processTask, protectionAddress, protectionSize, memoryProtection))
	{
		return NO;
	}
	
	ZGSuspendTask(process.processTask);
	
	ZGVariable *variable = [instruction.variable copy];
	
	uint8_t breakPointOpcode = INSTRUCTION_BREAKPOINT_OPCODE;
	
	ZGBreakPoint *breakPoint = [[ZGBreakPoint alloc] initWithProcess:process type:ZGBreakPointInstruction delegate:delegate];
	
	breakPoint.variable = variable;
	breakPoint.hidden = isHidden;
	breakPoint.thread = thread;
	breakPoint.basePointer = basePointer;
	breakPoint.originalProtection = memoryProtection;
	breakPoint.condition = condition;
	
	[self addBreakPoint:breakPoint];
	
	BOOL success = ZGWriteBytesIgnoringProtection(process.processTask, variable.address, &breakPointOpcode, sizeof(uint8_t));
	if (!success)
	{
		[self removeBreakPoint:breakPoint];
	}
	
	ZGResumeTask(process.processTask);
	
	return success;
}

- (void)addSingleStepBreakPointFromBreakPoint:(ZGBreakPoint *)breakPoint
{
	ZGBreakPoint *singleStepBreakPoint = [[ZGBreakPoint alloc] initWithProcess:breakPoint.process type:ZGBreakPointSingleStepInstruction delegate:breakPoint.delegate];
	singleStepBreakPoint.thread = breakPoint.thread;
	
	[self addBreakPoint:singleStepBreakPoint];
}

- (void)addBreakPoint:(ZGBreakPoint *)breakPoint
{
	@synchronized(self)
	{
		NSMutableArray *currentBreakPoints = [NSMutableArray arrayWithArray:self.breakPoints];
		[currentBreakPoints addObject:breakPoint];
		self.breakPoints = [NSArray arrayWithArray:currentBreakPoints];
	}
}

- (void)removeBreakPoint:(ZGBreakPoint *)breakPoint
{
	@synchronized(self)
	{
		NSMutableArray *currentBreakPoints = [NSMutableArray arrayWithArray:self.breakPoints];
		[currentBreakPoints removeObject:breakPoint];
		self.breakPoints = [NSArray arrayWithArray:currentBreakPoints];
	}
}

- (NSArray *)breakPoints
{
	@synchronized(self)
	{
		return _breakPoints;
	}
}

@end
