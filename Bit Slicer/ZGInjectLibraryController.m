/*
 * Created by Mayur Pawashe on 2/21/15.
 *
 * Copyright (c) 2015 zgcoder
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

#import "ZGInjectLibraryController.h"
#import "ZGBreakPointController.h"
#import "ZGUtilities.h"
#import "ZGThreadStates.h"
#import "ZGVirtualMemory.h"
#import "ZGMachBinary.h"
#import "ZGDebuggerUtilities.h"
#import "ZGBreakPoint.h"
#include <dlfcn.h>

@implementation ZGInjectLibraryController
{
	x86_thread_state_t _originalThreadState;
	mach_msg_type_number_t _threadStateCount;
	zg_x86_vector_state_t _originalVectorState;
	mach_msg_type_number_t _vectorStateCount;
	thread_act_array_t _threadList;
	mach_msg_type_number_t _threadListCount;
	
	ZGBreakPointController *_breakPointController;
	ZGInstruction *_haltedInstruction;
	NSString *_path;
	BOOL _secondPass;
}

// Pauses current execution of the process and adds a breakpoint at the current instruction pointer
// If we don't add a breakpoint, things will get screwy (presumably because the debug flags will not be set properly?)
- (void)injectDynamicLibraryAtPath:(NSString *)path inProcess:(ZGProcess *)process breakPointController:(ZGBreakPointController *)breakPointController
{
	_breakPointController = breakPointController;
	_path = [path copy];
	
	_secondPass = NO;
	
	ZGMemoryMap processTask = process.processTask;
	
	ZGSuspendTask(processTask);
	
	_threadList = NULL;
	_threadListCount = 0;
	if (task_threads(processTask, &_threadList, &_threadListCount) != KERN_SUCCESS)
	{
		ZG_LOG(@"ERROR: task_threads failed on removing watchpoint");
		return;
	}
	
	if (_threadListCount == 0)
	{
		ZG_LOG(@"ERROR: threadListCount is 0..");
		return;
	}
	
	thread_act_t mainThread = _threadList[0];
	
	x86_thread_state_t threadState;
	mach_msg_type_number_t threadStateCount;
	if (!ZGGetGeneralThreadState(&threadState, mainThread, &threadStateCount))
	{
		ZG_LOG(@"ERROR: Grabbing thread state failed %s", __PRETTY_FUNCTION__);
		return;
	}
	
	ZGMemoryAddress instructionPointer = process.is64Bit ? threadState.uts.ts64.__rip : threadState.uts.ts32.__eip;
	
	_haltedInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:instructionPointer + 0x1 inProcess:process withBreakPoints:breakPointController.breakPoints machBinaries:[ZGMachBinary machBinariesInProcess:process]];
	
	if (_haltedInstruction == nil)
	{
		ZG_LOG(@"Failed fetching current instruction at 0x%llX..", instructionPointer);
		return;
	}
	
	ZGMemoryAddress basePointer = process.is64Bit ? threadState.uts.ts64.__rbp : threadState.uts.ts32.__ebp;
	
	if (![breakPointController addBreakPointOnInstruction:_haltedInstruction inProcess:process thread:mainThread basePointer:basePointer delegate:self])
	{
		ZG_LOG(@"ERROR: Failed to set up breakpoint at IP %s", __PRETTY_FUNCTION__);
		return;
	}
	
	ZGResumeTask(processTask);
}

- (void)breakPointDidHit:(ZGBreakPoint *)breakPoint
{
	ZGProcess *process = breakPoint.process;
	ZGMemoryMap processTask = process.processTask;
	thread_act_t thread = breakPoint.thread;
	
	if (!_secondPass)
	{
		_secondPass = YES;
		
		// Inject our code that will call dlopen
		// After it's injected, change the stack and instruction pointers to our own
		
		const char *pathCString = [_path UTF8String];
		if (pathCString == NULL)
		{
			ZG_LOG(@"Failed to get C string from path string: %@", _path);
			return;
		}
		
		NSNumber *dlopenAddressNumber = [process findSymbol:@"dlopen" withPartialSymbolOwnerName:@"/usr/bin/dyld" requiringExactMatch:YES pastAddress:0x0 allowsWrappingToBeginning:NO];
		
		if (dlopenAddressNumber == nil)
		{
			ZG_LOG(@"Failed to find dlopen address");
			return;
		}
		
		size_t pathCStringLength = strlen(pathCString);
		
		ZGMemoryAddress pageSize = NSPageSize(); // default
		ZGPageSize(processTask, &pageSize);
		
		ZGMemoryAddress codeAddress = 0;
		ZGMemorySize codeSize = pageSize;
		if (!ZGAllocateMemory(processTask, &codeAddress, codeSize))
		{
			ZG_LOG(@"Failed allocating memory for code");
			return;
		}
		
		if (!ZGProtect(processTask, codeAddress, codeSize, VM_PROT_READ))
		{
			ZG_LOG(@"Failed setting memory protection for code");
			return;
		}
		
		ZGMemoryAddress stackAddress = 0;
		ZGMemorySize stackSize = pageSize * 16;
		if (!ZGAllocateMemory(processTask, &stackAddress, stackSize))
		{
			ZG_LOG(@"Failed allocating memory for stack");
			return;
		}
		
		if (!ZGProtect(processTask, stackAddress, stackSize, VM_PROT_READ | VM_PROT_WRITE))
		{
			ZG_LOG(@"Failed setting memory protection for stack");
			return;
		}
		
		ZGMemoryAddress dataAddress = 0;
		ZGMemorySize dataSize = 0x8;
		if (!ZGAllocateMemory(processTask, &dataAddress, dataSize))
		{
			ZG_LOG(@"Failed allocating memory for data");
			return;
		}
		
		if (!ZGProtect(processTask, dataAddress, dataSize, VM_PROT_READ | VM_PROT_WRITE))
		{
			ZG_LOG(@"Failed setting memory protection for data");
			return;
		}
		
		if (!ZGWriteBytes(processTask, dataAddress, pathCString, pathCStringLength + 1))
		{
			ZG_LOG(@"Failed writing C path string to memory");
			return;
		}
		
		void *nopBuffer = malloc(codeSize);
		memset(nopBuffer, 0x90, codeSize);
		
		if (!ZGWriteBytesIgnoringProtection(processTask, codeAddress, nopBuffer, codeSize))
		{
			ZG_LOG(@"Failed to NOP instruction bytes");
			return;
		}
		
		free(nopBuffer);
		
		thread_act_t mainThread = _threadList[0];
		
		x86_thread_state_t threadState;
		mach_msg_type_number_t threadStateCount;
		if (!ZGGetGeneralThreadState(&threadState, mainThread, &threadStateCount))
		{
			ZG_LOG(@"ERROR: Grabbing thread state failed %s", __PRETTY_FUNCTION__);
			return;
		}
		
		_originalThreadState = threadState;
		_threadStateCount = threadStateCount;
		
		zg_x86_vector_state_t vectorState;
		mach_msg_type_number_t vectorStateCount;
		if (!ZGGetVectorThreadState(&vectorState, mainThread, &vectorStateCount, process.is64Bit, NULL))
		{
			ZG_LOG(@"ERROR: Grabbing vector state failed %s", __PRETTY_FUNCTION__);
			return;
		}
		
		_originalVectorState = vectorState;
		_vectorStateCount = vectorStateCount;
		
//		for (mach_msg_type_number_t threadIndex = 0; threadIndex < _threadListCount; ++threadIndex)
//		{
//			if (threadIndex > 0 && thread_suspend(_threadList[threadIndex]) != KERN_SUCCESS)
//			{
//				NSLog(@"Failed suspending thread %u", _threadList[threadIndex]);
//			}
//		}
		
		const int dlopenMode = RTLD_NOW | RTLD_GLOBAL;
		
		NSArray *assemblyComponents = nil;
		if (!process.is64Bit)
		{
			assemblyComponents =
			@[@"sub esp, 0x8", [NSString stringWithFormat:@"push dword %d", dlopenMode], [NSString stringWithFormat:@"push dword %u", (ZG32BitMemoryAddress)dataAddress], [NSString stringWithFormat:@"call dword %u", dlopenAddressNumber.unsignedIntValue], @"add esp, 0x8"];
		}
		else
		{
			assemblyComponents =
			@[[NSString stringWithFormat:@"mov esi, %d", dlopenMode], [NSString stringWithFormat:@"mov rdi, qword %llu", dataAddress], [NSString stringWithFormat:@"mov rcx, qword %llu", dlopenAddressNumber.unsignedLongLongValue], @"call rcx"];
		}
		
		NSString *assembly = [assemblyComponents componentsJoinedByString:@"\n"];
		
		NSError *assemblingError = nil;
		NSData *codeData = [ZGDebuggerUtilities assembleInstructionText:assembly atInstructionPointer:codeAddress usingArchitectureBits:process.pointerSize * 8 error:&assemblingError];
		if (assemblingError != nil)
		{
			ZG_LOG(@"Assembly error: %@", assemblingError);
			return;
		}
		
		if (!ZGWriteBytesIgnoringProtection(processTask, codeAddress, codeData.bytes, codeData.length))
		{
			ZG_LOG(@"Failed to write code into memory");
			return;
		}
		
		ZGInstruction *endInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:codeAddress + codeData.length + 0x2 inProcess:process withBreakPoints:_breakPointController.breakPoints machBinaries:[ZGMachBinary machBinariesInProcess:process]];
		if (![_breakPointController addBreakPointOnInstruction:endInstruction inProcess:process condition:NULL delegate:self])
		{
			ZG_LOG(@"Failed to add breakpoint... :(");
		}
		
		if (!process.is64Bit)
		{
			threadState.uts.ts32.__eip = (ZG32BitMemoryAddress)codeAddress;
			threadState.uts.ts32.__esp = (ZG32BitMemoryAddress)(stackAddress + stackSize / 2);
		}
		else
		{
			threadState.uts.ts64.__rip = codeAddress;
			threadState.uts.ts64.__rsp = (stackAddress + stackSize / 2);
		}
		
		if (!ZGSetGeneralThreadState(&threadState, mainThread, threadStateCount))
		{
			ZG_LOG(@"Failed setting general thread state..");
		}
		
		[_breakPointController removeBreakPointOnInstruction:_haltedInstruction inProcess:process];
		_haltedInstruction = nil;
		
		[_breakPointController resumeFromBreakPoint:breakPoint];
	}
	else
	{
		// Restore everything to the way it was before we ran our code
		
		if (!ZGSetGeneralThreadState(&_originalThreadState, thread, _threadStateCount))
		{
			ZG_LOG(@"Failed to set thread state after breakpoint");
			return;
		}
		
		if (!ZGSetVectorThreadState(&_originalVectorState, thread, _vectorStateCount, breakPoint.process.is64Bit))
		{
			ZG_LOG(@"Failed to set vector state after breakpoint");
			return;
		}
		
		[_breakPointController resumeFromBreakPoint:breakPoint];
		
//		for (mach_msg_type_number_t threadIndex = 0; threadIndex < _threadListCount; ++threadIndex)
//		{
//			if (threadIndex > 0 && thread_resume(_threadList[threadIndex]) != KERN_SUCCESS)
//			{
//				NSLog(@"Failed resuming thread %u", _threadList[threadIndex]);
//			}
//		}
		
		if (!ZGDeallocateMemory(current_task(), (mach_vm_address_t)_threadList, _threadListCount * sizeof(thread_act_t)))
		{
			ZG_LOG(@"Failed to deallocate thread list in %s", __PRETTY_FUNCTION__);
		}
		
		//_breakPointController = nil;
		
		//	for (ZGMachBinary *machBinary in [ZGMachBinary machBinariesInProcess:breakPoint.process])
		//	{
		//		NSLog(@"0x%llX: %@", machBinary.headerAddress, [machBinary filePathInProcess:breakPoint.process]);
		//	}
	}
}

@end
