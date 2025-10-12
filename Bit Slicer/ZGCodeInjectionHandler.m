/*
 * Copyright (c) 2022 Mayur Pawashe
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

#import "ZGCodeInjectionHandler.h"
#import "ZGBreakPointController.h"
#import "ZGBreakPoint.h"
#import "ZGInstruction.h"
#import "ZGVariable.h"
#import "ZGDebugLogging.h"
#import "ZGRegistersState.h"
#import "ZGProcess.h"
#import "ZGVirtualMemory.h"

@implementation ZGCodeInjectionHandler
{
	__weak ZGBreakPointController *_breakPointController;
	NSUndoManager *_undoManager;
	ZGInstruction *_toIslandInstruction;
	ZGInstruction *_fromIslandInstruction;
	ZGMemoryAddress _islandAddress;
	ZGProcessType _processType;
	ZGProcess *_process;
}

- (BOOL)addBreakPointWithToIslandInstruction:(ZGInstruction *)toIslandInstruction fromIslandInstruction:(ZGInstruction *)fromIslandInstruction islandAddress:(ZGMemoryAddress)islandAddress process:(ZGProcess *)process processType:(ZGProcessType)processType prefersHardwareBreakpoints:(BOOL)prefersHardwareBreakpoints breakPointController:(ZGBreakPointController *)breakPointController owner:(id)owner undoManager:(NSUndoManager *)undoManager
{
	_breakPointController = breakPointController;
	_undoManager = undoManager;
	_owner = owner;
	_toIslandInstruction = toIslandInstruction;
	_fromIslandInstruction = fromIslandInstruction;
	_islandAddress = islandAddress;
	_processType = processType;
	_usesHardwareBreakpoints = prefersHardwareBreakpoints;
	_process = process;
	
	return [self addCodeInjection];
}

- (BOOL)addCodeInjection
{
	[_undoManager registerUndoWithTarget:self handler:^(id  _Nonnull __unused target) {
		[self removeCodeInjection];
	}];
	
	return [_breakPointController addCodeInjectionHandler:self];
}

- (void)removeCodeInjection
{
	// Note: keep self retained until the undoManager is cleared because the breakpoint controller
	// will not be holding onto us anymore
	[_undoManager registerUndoWithTarget:self handler:^(id  _Nonnull __unused target) {
		[self addCodeInjection];
	}];
	
	[_breakPointController removeObserver:self];
}

- (void)breakPointDidHit:(ZGBreakPoint *)breakPoint
{
	ZGMemoryAddress breakPointAddress = breakPoint.variable.address;
	ZGMemoryMap processTask = _process.processTask;
	
	zg_thread_state_t threadState;
	mach_msg_type_number_t threadStateCount;
	thread_act_t thread = breakPoint.thread;
	if (!ZGGetGeneralThreadState(&threadState, thread, &threadStateCount))
	{
		ZG_LOG(@"Error: failed to retrieve general thread state set in code injection breakpoint handler");
		ZGResumeTask(processTask);
		return;
	}
	
	ZGMemoryAddress newInstructionAddress = (breakPointAddress == _toIslandInstruction.variable.address) ? _islandAddress : (_toIslandInstruction.variable.address + _toIslandInstruction.variable.size);
	
	ZGSetInstructionPointerFromGeneralThreadState(&threadState, newInstructionAddress, _processType);
	
	ZGSetGeneralThreadState(&threadState, thread, threadStateCount);
	
	ZGResumeTask(processTask);
}

@end
