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
#import "ZGVirtualMemory.h"
#import "ZGThreadStates.h"
#import "ZGVariable.h"
#import "ZGProcess.h"
#import "ZGDebugThread.h"
#import "ZGBreakPoint.h"
#import "ZGRegistersState.h"
#import "ZGInstruction.h"
#import "ZGDebuggerUtilities.h"
#import "ZGProcessList.h"
#import "ZGRunningProcess.h"
#import "ZGScriptingInterpreter.h"
#import "ZGScriptManager.h"
#import "ZGDebugLogging.h"
#import "NSArrayAdditions.h"
#import "ZGRegisterEntries.h"
#import "ZGMachBinary.h"
#import "ZGAppTerminationState.h"

#import <mach/task.h>
#import <mach/thread_act.h>
#import <mach/mach_port.h>
#import <mach/mach.h>

extern boolean_t mach_exc_server(mach_msg_header_t *InHeadP, mach_msg_header_t *OutHeadP);

@implementation ZGBreakPointController
{
	NSArray<ZGBreakPoint *> *_breakPoints;
	mach_port_t _exceptionPort;
	ZGScriptingInterpreter * _Nonnull _scriptingInterpreter;
	dispatch_source_t _Nullable _watchPointTimer;
	BOOL _delayedTermination;
}

static ZGBreakPointController *gBreakPointController;
+ (instancetype)createBreakPointControllerOnceWithScriptingInterpreter:(ZGScriptingInterpreter *)scriptingInterpreter
{
	assert(gBreakPointController == nil);
	
	gBreakPointController = [(ZGBreakPointController *)[self alloc] initWithScriptingInterpreter:scriptingInterpreter];
	return gBreakPointController;
}

- (id)initWithScriptingInterpreter:(ZGScriptingInterpreter *)scriptingInterpreter
{
	self = [super init];
	if (self != nil)
	{
		_breakPoints = @[];
		_scriptingInterpreter = scriptingInterpreter;
	}
	return self;
}

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
		ZG_LOG(@"ERROR: task_threads failed on removing watchpoint");
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
			ZG_LOG(@"ERROR: Grabbing debug state failed in %s: continuing...", __PRETTY_FUNCTION__);
			continue;
		}
		
		uint8_t debugRegisterIndex = debugThread.registerIndex;
		
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
			ZG_LOG(@"ERROR: Failure in setting thread state registers in %s", __PRETTY_FUNCTION__);
		}
	}
	
	if (!ZGDeallocateMemory(current_task(), (mach_vm_address_t)threadList, threadListCount * sizeof(thread_act_t)))
	{
		ZG_LOG(@"Failed to deallocate thread list in %s", __PRETTY_FUNCTION__);
	}
	
	// we may still catch exceptions momentarily for our breakpoint if the data is being acccessed frequently, so do not remove it immediately
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
		if (self->_watchPointTimer != NULL)
		{
			BOOL shouldKeepTimer = [[self breakPoints] zgHasObjectMatchingCondition:^(ZGBreakPoint *watchPoint){ return (BOOL)(watchPoint.type != ZGBreakPointWatchData && watchPoint != breakPoint); }];
			if (!shouldKeepTimer)
			{
				dispatch_source_cancel((dispatch_source_t _Nonnull)self->_watchPointTimer);
				self->_watchPointTimer = NULL;
			}
		}
		[self removeBreakPoint:breakPoint];
	});
}

#define IS_DEBUG_REGISTER_AND_STATUS_ENABLED(debugState, debugRegisterIndex, type) \
	(((debugState.uds.type.__dr6 & (1 << debugRegisterIndex)) != 0) && ((debugState.uds.type.__dr7 & (1 << 2*debugRegisterIndex)) != 0))

- (BOOL)handleWatchPointsWithTask:(mach_port_t)task inThread:(mach_port_t)thread
{
	BOOL handledWatchPoint = NO;
	for (ZGBreakPoint *breakPoint in [self breakPoints])
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

			// Normally I'd set this to YES after isWatchPointAvailable is YES below, however, it is possible this will miss a watchpoint just being removed.
			// To be safe, we will just pretend we handled the watchpoint so that we don't crash the target process
			handledWatchPoint = YES;

			x86_debug_state_t debugState;
			mach_msg_type_number_t debugStateCount;
			if (!ZGGetDebugThreadState(&debugState, thread, &debugStateCount))
			{
				continue;
			}
			
			uint8_t debugRegisterIndex = debugThread.registerIndex;
			
			BOOL isWatchPointAvailable = breakPoint.process.is64Bit ? IS_DEBUG_REGISTER_AND_STATUS_ENABLED(debugState, debugRegisterIndex, ds64) : IS_DEBUG_REGISTER_AND_STATUS_ENABLED(debugState, debugRegisterIndex, ds32);
			
			if (!isWatchPointAvailable)
			{
				continue;
			}
			
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
				ZG_LOG(@"ERROR: Failure in setting debug thread registers for clearing dr6 in handle watchpoint...Not good.");
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
			
			ZGRegistersState *registersState = [[ZGRegistersState alloc] initWithGeneralPurposeThreadState:threadState vectorState:vectorState hasVectorState:retrievedVectorState hasAVXSupport:hasAVXSupport is64Bit:breakPoint.process.is64Bit];
			
			dispatch_async(dispatch_get_main_queue(), ^{
				@synchronized(self)
				{
					id <ZGBreakPointDelegate> delegate = breakPoint.delegate;
					[delegate dataAccessedByBreakPoint:breakPoint fromInstructionPointer:instructionAddress withRegistersState:registersState];
				}
			});
		}
		
		ZGResumeTask(task);
	}
	
	return handledWatchPoint;
}

- (NSArray<ZGBreakPoint *> *)removeSingleStepBreakPointsFromBreakPoint:(ZGBreakPoint *)breakPoint
{
	NSMutableArray<ZGBreakPoint *> *removedBreakPoints = [NSMutableArray array];
	
	for (ZGBreakPoint *candidateBreakPoint in [self breakPoints])
	{
		if (candidateBreakPoint.type == ZGBreakPointSingleStepInstruction && candidateBreakPoint.task == breakPoint.task && candidateBreakPoint.thread == breakPoint.thread)
		{
			[removedBreakPoints addObject:candidateBreakPoint];
			[self removeBreakPoint:candidateBreakPoint];
		}
	}
	
	return removedBreakPoints;
}

- (void)resumeFromBreakPoint:(ZGBreakPoint *)breakPoint
{
	x86_thread_state_t threadState;
	mach_msg_type_number_t threadStateCount;
	if (!ZGGetGeneralThreadState(&threadState, breakPoint.thread, &threadStateCount))
	{
			ZG_LOG(@"ERROR: Grabbing thread state failed in %s", __PRETTY_FUNCTION__);
	}
	
	BOOL shouldSingleStep = NO;
	
	// Check if breakpoint still exists
	if (breakPoint.type == ZGBreakPointInstruction && [[self breakPoints] containsObject:breakPoint])
	{
		// Restore our instruction
		ZGWriteBytesOverwritingProtection(breakPoint.process.processTask, breakPoint.variable.address, breakPoint.variable.rawValue, sizeof(uint8_t));
		
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
		shouldSingleStep = [[self breakPoints] zgHasObjectMatchingCondition:^(ZGBreakPoint *candidateBreakPoint) {
			return (BOOL)(candidateBreakPoint.type == ZGBreakPointSingleStepInstruction && candidateBreakPoint.thread == breakPoint.thread && candidateBreakPoint.task == breakPoint.task);
		}];
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
		ZG_LOG(@"Failure in setting registers thread state for thread %d, %s", breakPoint.thread, __PRETTY_FUNCTION__);
	}
	
	ZGResumeTask(breakPoint.process.processTask);
}

- (void)revertInstructionBackToNormal:(ZGBreakPoint *)breakPoint
{
	ZGWriteBytesOverwritingProtection(breakPoint.process.processTask, breakPoint.variable.address, breakPoint.variable.rawValue, sizeof(uint8_t));
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
		
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 10), dispatch_get_main_queue(), ^(void) {
			if ([[self breakPoints] containsObject:breakPoint])
			{
				ZGSuspendTask(breakPoint.process.processTask);
				
				[self revertInstructionBackToNormal:breakPoint];
				[self removeBreakPoint:breakPoint];
				
				ZGResumeTask(breakPoint.process.processTask);
			}
			
			id <ZGBreakPointDelegate> delegate = breakPoint.delegate;
			if ([delegate respondsToSelector:@selector(conditionalInstructionBreakPointWasRemoved)])
			{
				[delegate conditionalInstructionBreakPointWasRemoved];
			}
			
			if (self->_delayedTermination && [self breakPoints].count == 0)
			{
				[self->_appTerminationState decreaseLifeCount];
			}
		});
	}
	else
	{
		[self revertInstructionBackToNormal:breakPoint];
		[self removeBreakPoint:breakPoint];
	}
}

- (ZGBreakPoint *)removeBreakPointOnInstruction:(ZGInstruction *)instruction inProcess:(ZGProcess *)process
{
	ZGBreakPoint *targetBreakPoint = nil;
	for (ZGBreakPoint *breakPoint in [self breakPoints])
	{
		if (breakPoint.type == ZGBreakPointInstruction && breakPoint.process.processTask == process.processTask	&& breakPoint.variable.address == instruction.variable.address)
		{
			targetBreakPoint = breakPoint;
			break;
		}
	}
	
	if (targetBreakPoint != nil)
	{
		[self removeInstructionBreakPoint:targetBreakPoint];
	}
	
	return targetBreakPoint;
}

- (BOOL)handleInstructionBreakPointsWithTask:(mach_port_t)task inThread:(mach_port_t)thread
{
	BOOL handledInstructionBreakPoint = NO;
	NSArray<ZGBreakPoint *> *breakPoints = [self breakPoints];
	
	ZGSuspendTask(task);
	
	x86_thread_state_t threadState;
	mach_msg_type_number_t threadStateCount;
	if (!ZGGetGeneralThreadState(&threadState, thread, &threadStateCount))
	{
		ZG_LOG(@"ERROR: Grabbing thread state failed in obtaining instruction address, skipping. %s", __PRETTY_FUNCTION__);
	}
	
	BOOL hitBreakPoint = NO;
	NSMutableArray<ZGBreakPoint *> *breakPointsToNotify = [[NSMutableArray alloc] init];
	
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
			threadState.uts.ts64.__rflags &= ~(1U << 8);
		}
		else
		{
			threadState.uts.ts32.__eflags &= ~(1U << 8);
		}
		
		// If we had single-stepped in here, use current program counter, otherwise use instruction address before program counter
		BOOL foundSingleStepBreakPoint = [[self breakPoints] zgHasObjectMatchingCondition:^(ZGBreakPoint *candidateBreakPoint) {
			return (BOOL)((candidateBreakPoint.needsToRestore || candidateBreakPoint.type == ZGBreakPointSingleStepInstruction) && candidateBreakPoint.task == task && candidateBreakPoint.thread == thread);
		}];
		
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
				NSArray<ZGMachBinary *> *machBinaries = [ZGMachBinary machBinariesInProcess:breakPoint.process];
				ZGInstruction *foundInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:instructionPointer inProcess:breakPoint.process withBreakPoints:[self breakPoints] machBinaries:machBinaries];
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
				
				ZGFreeBytes(opcode, opcodeSize);
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
			threadState.uts.ts64.__rflags &= ~(1U << 8);
		}
		else
		{
			threadState.uts.ts32.__eflags &= ~(1U << 8);
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
			ZG_LOG(@"Failure in setting registers thread state for catching instruction breakpoint for thread %d, %s", thread, __PRETTY_FUNCTION__);
		}
	}
	
	ZGRegisterEntry registerEntries[ZG_MAX_REGISTER_ENTRIES];
	BOOL retrievedRegisterEntries = NO;
	BOOL retrievedVectorState = NO;
	bool hasAVXSupport = NO;
	zg_x86_vector_state_t vectorState = {};
	
	// We should notify delegates if a breakpoint hits after we modify thread states
	for (ZGBreakPoint *breakPoint in breakPointsToNotify)
	{
		BOOL canNotifyDelegate = !breakPoint.dead;
		
		if (canNotifyDelegate && !retrievedRegisterEntries)
		{
			BOOL is64Bit = breakPoint.process.is64Bit;
			
			int numberOfGeneralPurposeEntries = [ZGRegisterEntries getRegisterEntries:registerEntries fromGeneralPurposeThreadState:threadState is64Bit:is64Bit];
			
			retrievedVectorState = ZGGetVectorThreadState(&vectorState, thread, NULL, breakPoint.process.is64Bit, &hasAVXSupport);
			if (retrievedVectorState)
			{
				[ZGRegisterEntries getRegisterEntries:registerEntries + numberOfGeneralPurposeEntries fromVectorThreadState:vectorState is64Bit:is64Bit hasAVXSupport:hasAVXSupport];
			}
			
			retrievedRegisterEntries = YES;
		}
		
		if (canNotifyDelegate && breakPoint.condition != NULL)
		{
			NSError *error = nil;
			if (![_scriptingInterpreter evaluateCondition:(PyObject * _Nonnull)breakPoint.condition process:breakPoint.process registerEntries:registerEntries error:&error])
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
			BOOL is64Bit = breakPoint.process.is64Bit;
			
			dispatch_async(dispatch_get_main_queue(), ^{
				@synchronized(self)
				{
					id <ZGBreakPointDelegate> delegate = breakPoint.delegate;
					if (delegate != nil)
					{
						ZGRegistersState *registersState = [[ZGRegistersState alloc] initWithGeneralPurposeThreadState:threadState vectorState:vectorState hasVectorState:retrievedVectorState hasAVXSupport:hasAVXSupport is64Bit:is64Bit];
						
						breakPoint.registersState = registersState;
						
						[delegate breakPointDidHit:breakPoint];
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

kern_return_t  catch_mach_exception_raise_state(mach_port_t __unused exception_port, exception_type_t __unused exception, exception_data_t __unused code, mach_msg_type_number_t __unused code_count, int * __unused flavor, thread_state_t __unused in_state, mach_msg_type_number_t __unused in_state_count, thread_state_t __unused out_state, mach_msg_type_number_t * __unused out_state_count)
{
	return KERN_FAILURE;
}

kern_return_t  catch_mach_exception_raise_state_identity(mach_port_t __unused exception_port, mach_port_t __unused thread, mach_port_t __unused task, exception_type_t __unused exception, exception_data_t __unused code, mach_msg_type_number_t __unused code_count, int * __unused flavor, thread_state_t __unused in_state, mach_msg_type_number_t __unused in_state_count, thread_state_t __unused out_state, mach_msg_type_number_t * __unused out_state_count)
{
	return KERN_FAILURE;
}

kern_return_t catch_mach_exception_raise(mach_port_t __unused exception_port, mach_port_t thread, mach_port_t task, exception_type_t exception, exception_data_t __unused code, mach_msg_type_number_t __unused code_count)
{
	BOOL handledWatchPoint = NO;
	BOOL handledInstructionBreakPoint = NO;
	
	if (exception == EXC_BREAKPOINT)
	{
		@autoreleasepool
		{
			handledWatchPoint = [gBreakPointController handleWatchPointsWithTask:task inThread:thread];
			handledInstructionBreakPoint = [gBreakPointController handleInstructionBreakPointsWithTask:task inThread:thread];
		}
	}
	
	return (handledWatchPoint || handledInstructionBreakPoint) ? KERN_SUCCESS : KERN_FAILURE;
}

- (NSArray<ZGBreakPoint *> *)removeObserver:(id)observer
{
	return [self removeObserver:observer runningProcess:nil withProcessID:-1 atAddress:0];
}

- (NSArray<ZGBreakPoint *> *)removeObserver:(id)observer withProcessID:(pid_t)processID atAddress:(ZGMemoryAddress)address
{
	return [self removeObserver:observer runningProcess:nil withProcessID:processID atAddress:address];
}

- (NSArray<ZGBreakPoint *> *)removeObserver:(id)observer runningProcess:(ZGRunningProcess *)process
{
	return [self removeObserver:observer runningProcess:process withProcessID:-1 atAddress:0];
}

- (NSArray<ZGBreakPoint *> *)removeObserver:(id)observer runningProcess:(ZGRunningProcess *)process withProcessID:(pid_t)processID atAddress:(ZGMemoryAddress)address
{
	NSMutableArray<ZGBreakPoint *> *removedBreakPoints = [NSMutableArray array];
	@synchronized(self)
	{
		NSArray<ZGRunningProcess *> *runningProcesses = [[[ZGProcessList alloc] init] runningProcesses];
		for (ZGBreakPoint *breakPoint in [self breakPoints])
		{
			if (processID <= 0 || (processID == breakPoint.process.processID && breakPoint.variable.address == address))
			{
				if (breakPoint.delegate == observer && (!process || breakPoint.process.processID == process.processIdentifier))
				{
					BOOL isDead = ![runningProcesses zgHasObjectMatchingCondition:^(ZGRunningProcess *runningProcess) {
						return (BOOL)(runningProcess.processIdentifier == breakPoint.process.processID);
					}];
					
					breakPoint.delegate = nil;
					
					if (isDead || breakPoint.type == ZGBreakPointSingleStepInstruction)
					{
						[removedBreakPoints addObject:breakPoint];
						[self removeBreakPoint:breakPoint];
					}
					else if (breakPoint.type == ZGBreakPointWatchData)
					{
						[removedBreakPoints addObject:breakPoint];
						
						ZGSuspendTask(breakPoint.task);
						[self removeWatchPoint:breakPoint];
						ZGResumeTask(breakPoint.task);
					}
					else if (breakPoint.type == ZGBreakPointInstruction)
					{
						if (_appTerminationState != nil && !_delayedTermination && breakPoint.condition != NULL)
						{
							_delayedTermination = YES;
							[_appTerminationState increaseLifeCount];
						}
						
						[removedBreakPoints addObject:breakPoint];
						
						[self removeInstructionBreakPoint:breakPoint];
					}
				}
			}
		}
	}
	
	return removedBreakPoints;
}

- (BOOL)setUpExceptionPortForProcess:(ZGProcess *)process
{
	if (_exceptionPort == MACH_PORT_NULL)
	{
		if (mach_port_allocate(current_task(), MACH_PORT_RIGHT_RECEIVE, &_exceptionPort) != KERN_SUCCESS)
		{
			NSLog(@"ERROR: Could not allocate mach port for adding breakpoint");
			_exceptionPort = MACH_PORT_NULL;
			return NO;
		}
		
		if (mach_port_insert_right(current_task(), _exceptionPort, _exceptionPort, MACH_MSG_TYPE_MAKE_SEND) != KERN_SUCCESS)
		{
			NSLog(@"ERROR: Could not insert send right for watchpoint");
			if (!ZGDeallocatePort(_exceptionPort))
			{
				NSLog(@"ERROR: Could not deallocate exception port in adding breakpoint");
			}
			_exceptionPort = MACH_PORT_NULL;
			return NO;
		}
	}
	
	if (task_set_exception_ports(process.processTask, EXC_MASK_BREAKPOINT, _exceptionPort, (exception_behavior_t)(EXCEPTION_DEFAULT | MACH_EXCEPTION_CODES), MACHINE_THREAD_STATE) != KERN_SUCCESS)
	{
		NSLog(@"ERROR: task_set_exception_ports failed on adding breakpoint");
		return NO;
	}
	
	static dispatch_once_t once = 0;
	dispatch_once(&once, ^{
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			// Not exactly clear what to pass in for the size
			if (mach_msg_server(mach_exc_server, 2048, self->_exceptionPort, MACH_MSG_TIMEOUT_NONE) != MACH_MSG_SUCCESS)
			{
				NSLog(@"mach_msg_server() returned on error!");
			}
		});
    });
	
	return YES;
}

#define IS_REGISTER_AVAILABLE(debugState, registerIndex, type) (!(debugState.uds.type.__dr7 & (1 << (2*registerIndex))) && !(debugState.uds.type.__dr7 & (1 << (2*registerIndex+1))))

#define WRITE_BREAKPOINT_IN_DEBUG_REGISTERS(debugRegisterIndex, debugState, variable, watchSize, watchPointType, type, typecast) \
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

- (BOOL)updateThreadListInWatchpoint:(ZGBreakPoint *)watchPoint type:(ZGWatchPointType)watchPointType
{
	ZGMemoryMap processTask = watchPoint.process.processTask;
	BOOL is64Bit = watchPoint.process.is64Bit;
	ZGMemorySize watchSize = watchPoint.watchSize;
	ZGVariable *variable = watchPoint.variable;
	NSArray<ZGDebugThread *> *oldDebugThreads = watchPoint.debugThreads;
	
	ZGSuspendTask(processTask);
	
	thread_act_array_t threadList = NULL;
	mach_msg_type_number_t threadListCount = 0;
	if (task_threads(processTask, &threadList, &threadListCount) != KERN_SUCCESS)
	{
		ZG_LOG(@"ERROR: task_threads failed on adding watchpoint");
		ZGResumeTask(processTask);
		return NO;
	}
	
	NSMutableArray<ZGDebugThread *> *newDebugThreads = [[NSMutableArray alloc] init];
	
	for (mach_msg_type_number_t threadIndex = 0; threadIndex < threadListCount; threadIndex++)
	{
		ZGDebugThread *existingThread = nil;
		for (ZGDebugThread *debugThread in oldDebugThreads)
		{
			if (debugThread.thread == threadList[threadIndex])
			{
				existingThread = debugThread;
				break;
			}
		}
		
		if (existingThread != nil)
		{
			[newDebugThreads addObject:existingThread];
			continue;
		}
		
		x86_debug_state_t debugState;
		mach_msg_type_number_t stateCount;
		if (!ZGGetDebugThreadState(&debugState, threadList[threadIndex], &stateCount))
		{
			ZG_LOG(@"ERROR: ZGGetDebugThreadState failed on adding watchpoint for thread %d, %s", threadList[threadIndex], __PRETTY_FUNCTION__);
			continue;
		}
		
		BOOL foundRegisterIndex = NO;
		uint8_t debugRegisterIndex = 0;
		for (uint8_t registerIndex = 0; registerIndex < 4; registerIndex++)
		{
			if ((is64Bit && IS_REGISTER_AVAILABLE(debugState, registerIndex, ds64)) || (!is64Bit && IS_REGISTER_AVAILABLE(debugState, registerIndex, ds32)))
			{
				debugRegisterIndex = registerIndex;
				foundRegisterIndex = YES;
				break;
			}
		}
		
		if (!foundRegisterIndex)
		{
			ZG_LOG(@"Failed to find available debug register for thread %d, %s", threadList[threadIndex], __PRETTY_FUNCTION__);
			continue;
		}
		
		ZGDebugThread *debugThread = [[ZGDebugThread alloc] initWithThread:threadList[threadIndex] registerIndex:debugRegisterIndex];
		
		if (is64Bit)
		{
			WRITE_BREAKPOINT_IN_DEBUG_REGISTERS(debugRegisterIndex, debugState, variable, watchSize, watchPointType, ds64, uint64_t);
		}
		else
		{
			WRITE_BREAKPOINT_IN_DEBUG_REGISTERS(debugRegisterIndex, debugState, variable, watchSize, watchPointType, ds32, uint32_t);
		}
		
		if (!ZGSetDebugThreadState(&debugState, threadList[threadIndex], stateCount))
		{
			ZG_LOG(@"Failure in setting registers thread state for adding watchpoint for thread %d", threadList[threadIndex]);
			continue;
		}
		
		[newDebugThreads addObject:debugThread];
	}
	
	if (!ZGDeallocateMemory(current_task(), (mach_vm_address_t)threadList, threadListCount * sizeof(thread_act_t)))
	{
		ZG_LOG(@"Failed to deallocate thread list in %s...", __PRETTY_FUNCTION__);
	}
	
	ZGResumeTask(processTask);
	
	watchPoint.debugThreads = newDebugThreads;
	
	if (newDebugThreads.count == 0)
	{
		ZG_LOG(@"ERROR: Failed to set watch variable: no threads found.");
		return NO;
	}
	
	return YES;
}

- (BOOL)addWatchpointOnVariable:(ZGVariable *)variable inProcess:(ZGProcess *)process watchPointType:(ZGWatchPointType)watchPointType delegate:(id <ZGBreakPointDelegate>)delegate getBreakPoint:(ZGBreakPoint * __autoreleasing *)returnedBreakPoint
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
		
		ZGBreakPoint *breakPoint = [[ZGBreakPoint alloc] initWithProcess:process type:ZGBreakPointWatchData delegate:delegate];
		breakPoint.variable = variable;
		breakPoint.watchSize = watchSize;
		
		if (![self updateThreadListInWatchpoint:breakPoint type:watchPointType])
		{
			return NO;
		}

		if (self->_watchPointTimer == NULL && (self->_watchPointTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue())) != NULL)
		{
			dispatch_source_t watchPointTimer = self->_watchPointTimer;
			
			dispatch_source_set_timer(watchPointTimer, DISPATCH_TIME_NOW, NSEC_PER_SEC / 2, NSEC_PER_SEC / 10);
			dispatch_source_set_event_handler(watchPointTimer, ^{
				for (ZGBreakPoint *existingBreakPoint in [self breakPoints])
				{
					if (existingBreakPoint.type != ZGBreakPointWatchData)
					{
						continue;
					}
					
					if (!existingBreakPoint.dead && ![self updateThreadListInWatchpoint:existingBreakPoint type:watchPointType])
					{
						existingBreakPoint.dead = YES;
					}
				}
			});
			dispatch_resume(watchPointTimer);
		}

		[self addBreakPoint:breakPoint];
		
		if (returnedBreakPoint != NULL)
		{
			*returnedBreakPoint = breakPoint;
		}
	}
	
	return YES;
}

- (BOOL)addBreakPointOnInstruction:(ZGInstruction *)instruction inProcess:(ZGProcess *)process callback:(PyObject *)callback delegate:(id)delegate
{
	return [self addBreakPointOnInstruction:instruction inProcess:process thread:0 basePointer:0 hidden:NO condition:NULL callback:callback delegate:delegate];
}

- (BOOL)addBreakPointOnInstruction:(ZGInstruction *)instruction inProcess:(ZGProcess *)process condition:(PyObject *)condition delegate:(id)delegate
{
	return [self addBreakPointOnInstruction:instruction inProcess:process thread:0 basePointer:0 hidden:NO condition:condition callback:NULL delegate:delegate];
}

- (BOOL)addBreakPointOnInstruction:(ZGInstruction *)instruction inProcess:(ZGProcess *)process thread:(thread_act_t)thread basePointer:(ZGMemoryAddress)basePointer delegate:(id)delegate
{
	return [self addBreakPointOnInstruction:instruction inProcess:process thread:thread basePointer:basePointer hidden:YES condition:NULL callback:NULL delegate:delegate];
}

- (BOOL)addBreakPointOnInstruction:(ZGInstruction *)instruction inProcess:(ZGProcess *)process thread:(thread_act_t)thread basePointer:(ZGMemoryAddress)basePointer callback:(PyObject *)callback delegate:(id)delegate
{
	return [self addBreakPointOnInstruction:instruction inProcess:process thread:thread basePointer:basePointer hidden:YES condition:NULL callback:callback delegate:delegate];
}

- (BOOL)addBreakPointOnInstruction:(ZGInstruction *)instruction inProcess:(ZGProcess *)process thread:(thread_act_t)thread basePointer:(ZGMemoryAddress)basePointer hidden:(BOOL)isHidden condition:(PyObject *)condition callback:(PyObject *)callback delegate:(id)delegate
{
	if (![self setUpExceptionPortForProcess:process])
	{
		return NO;
	}
	
	BOOL breakPointAlreadyExists = [[self breakPoints] zgHasObjectMatchingCondition:^(ZGBreakPoint *breakPoint) {
		return (BOOL)(breakPoint.type == ZGBreakPointInstruction && breakPoint.task == process.processTask && breakPoint.variable.address == instruction.variable.address);
	}];
	
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
	breakPoint.callback = callback;
	
	[self addBreakPoint:breakPoint];
	
	BOOL success = ZGWriteBytesIgnoringProtection(process.processTask, variable.address, &breakPointOpcode, sizeof(uint8_t));
	if (!success)
	{
		[self removeBreakPoint:breakPoint];
	}
	
	ZGResumeTask(process.processTask);
	
	return success;
}

- (ZGBreakPoint *)addSingleStepBreakPointFromBreakPoint:(ZGBreakPoint *)breakPoint
{
	ZGBreakPoint *singleStepBreakPoint = [[ZGBreakPoint alloc] initWithProcess:breakPoint.process type:ZGBreakPointSingleStepInstruction delegate:breakPoint.delegate];
	singleStepBreakPoint.thread = breakPoint.thread;
	
	[self addBreakPoint:singleStepBreakPoint];
	
	return singleStepBreakPoint;
}

- (void)addBreakPoint:(ZGBreakPoint *)breakPoint
{
	@synchronized(self)
	{
		NSMutableArray<ZGBreakPoint *> *currentBreakPoints = [NSMutableArray arrayWithArray:[self breakPoints]];
		[currentBreakPoints addObject:breakPoint];
		_breakPoints = [NSArray arrayWithArray:currentBreakPoints];
	}
}

- (void)removeBreakPoint:(ZGBreakPoint *)breakPoint
{
	@synchronized(self)
	{
		NSMutableArray<ZGBreakPoint *> *currentBreakPoints = [NSMutableArray arrayWithArray:[self breakPoints]];
		[currentBreakPoints removeObject:breakPoint];
		_breakPoints = [NSArray arrayWithArray:currentBreakPoints];
	}
}

- (NSArray<ZGBreakPoint *> *)breakPoints
{
	@synchronized(self)
	{
		return _breakPoints;
	}
}

@end
