/*
 * Created by Mayur Pawashe on 2/22/15.
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

#import "ZGSpeedModifierWindowController.h"
#import "ZGProcess.h"
#import "ZGVirtualMemory.h"
#import "ZGUtilities.h"
#import "ZGInjectLibraryController.h"
#import "ZGBreakPointController.h"
#import "ZGMachBinary.h"
#import "ZGDebuggerUtilities.h"
#import "ZGInstruction.h"
#import "ZGDisassemblerObject.h"

@implementation ZGSpeedModifierWindowController
{
	IBOutlet NSTextField *_speedTextField;
	ZGMemoryAddress _speedAddress;
	ZGProcess *_process;
	ZGInjectLibraryController *_injectLibraryController;
	ZGBreakPointController *_breakPointController;
}

- (NSString *)windowNibName
{
	return @"Modify Speed Dialog";
}

- (void)attachToWindow:(NSWindow *)parentWindow process:(ZGProcess *)process breakPointController:(ZGBreakPointController *)breakPointController undoManager:(NSUndoManager *)__unused undoManager
{
	NSNumber *speedMultiplierAddress = [process findSymbol:@"gSpeedMultiplier" withPartialSymbolOwnerName:@"inject.dylib" requiringExactMatch:YES pastAddress:0x0 allowsWrappingToBeginning:NO];
	
	_process = process;
	_breakPointController = breakPointController;
	
	[self window]; // load window
	_speedTextField.doubleValue = 1.0;
	
	if (speedMultiplierAddress != nil)
	{
		_speedAddress = speedMultiplierAddress.unsignedLongLongValue;
		
		double *speed = NULL;
		ZGMemorySize size = sizeof(*speed);
		if (ZGReadBytes(process.processTask, _speedAddress, (void **)&speed, &size))
		{
			_speedTextField.doubleValue = *speed;
			ZGFreeBytes(speed, size);
		}
	}
	else
	{
		_speedAddress = 0x0;
	}
	
	[NSApp
	 beginSheet:self.window
	 modalForWindow:parentWindow
	 modalDelegate:nil
	 didEndSelector:nil
	 contextInfo:NULL];
}

- (void)replaceLocalStubWithName:(NSString *)stubName newFunctionName:(NSString *)newFunctionName process:(ZGProcess *)process machBinaries:(NSArray *)machBinaries
{
	NSArray *symbolRanges = [process findSymbolsWithName:[NSString stringWithFormat:@"DYLD-STUB$$%@", stubName] partialSymbolOwnerName:nil requiringExactMatch:YES];
	
	NSNumber *newFunctionAddressNumber = [process findSymbol:newFunctionName withPartialSymbolOwnerName:@"inject.dylib" requiringExactMatch:YES pastAddress:0x0 allowsWrappingToBeginning:NO];
	
	if (newFunctionAddressNumber == nil)
	{
		ZG_LOG(@"Error: new function name %@ is nil", newFunctionAddressNumber);
		return;
	}
	
	ZGMemoryAddress newFunctionAddress = newFunctionAddressNumber.unsignedLongLongValue;
	
	NSString *sharedPath = nil;
	NSRunningApplication *runningApplication = [NSRunningApplication runningApplicationWithProcessIdentifier:process.processID];
	
	if (runningApplication != nil)
	{
		sharedPath = [runningApplication.bundleURL.path stringByDeletingLastPathComponent];
	}
	else
	{
		sharedPath = [[machBinaries[0] filePathInProcess:process] stringByDeletingLastPathComponent];
	}
	
	if (sharedPath == nil)
	{
		ZG_LOG(@"Error: shared file path is nil..");
		return;
	}
	
	for (NSValue *symbolRangeValue in symbolRanges)
	{
		NSRange symbolRange = [symbolRangeValue rangeValue];
		ZGMachBinary *machBinary = [ZGMachBinary machBinaryNearestToAddress:symbolRange.location fromMachBinaries:machBinaries];
		
		if (machBinary == nil)
		{
			continue;
		}
		
		NSString *filePath = [machBinary filePathInProcess:process];
		if (![filePath hasPrefix:sharedPath])
		{
			continue;
		}
		
		ZGInstruction *foundInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:symbolRange.location + 0x1 inProcess:process withBreakPoints:_breakPointController.breakPoints machBinaries:machBinaries];
		
		if (foundInstruction == nil)
		{
			ZG_LOG(@"Failed to disassemble instruction");
			continue;
		}
		
		NSString *assembly = nil;
		if ([ZGDisassemblerObject isCallMnemonic:foundInstruction.mnemonic])
		{
			assembly = [NSString stringWithFormat:@"call %llu", newFunctionAddress];
		}
		else if ([ZGDisassemblerObject isJumpMnemonic:foundInstruction.mnemonic])
		{
			assembly = [NSString stringWithFormat:@"jmp %llu", newFunctionAddress];
		}
		else
		{
			ZG_LOG(@"Encountered unknown instruction mnemonic (%d) for %@", foundInstruction.mnemonic, foundInstruction.text);
			
			continue;
		}
		
		NSError *error = nil;
		NSData *assemblyData = [ZGDebuggerUtilities assembleInstructionText:assembly atInstructionPointer:symbolRange.location usingArchitectureBits:process.pointerSize * 8 error:&error];
		
		if (error != nil)
		{
			ZG_LOG(@"Encountered bad assembly error: %@, %@", error, assembly);
			continue;
		}
		
		if (assemblyData.length > foundInstruction.variable.size)
		{
			ZG_LOG(@"Assembled data is too large for instruction: %@, %@", foundInstruction.text, assembly);
			continue;
		}
		
		if (!ZGWriteBytesIgnoringProtection(process.processTask, symbolRange.location, assemblyData.bytes, assemblyData.length))
		{
			ZG_LOG(@"Failed to write data bytes at 0x%lX: %@", symbolRange.location, assemblyData);
			continue;
		}
		
		if (assemblyData.length < foundInstruction.variable.size)
		{
			size_t nopSize = foundInstruction.variable.size - assemblyData.length;
			void *nopBytes = malloc(nopSize);
			assert(nopBytes != NULL);
			
			memset(nopBytes, NOP_VALUE, nopSize);
			
			if (!ZGWriteBytesIgnoringProtection(process.processTask, symbolRange.location + assemblyData.length, nopBytes, nopSize))
			{
				ZG_LOG(@"Failed to write NOP bytes at 0x%lX", symbolRange.location + assemblyData.length);
				continue;
			}
			
			free(nopBytes);
		}
	}
}

- (IBAction)setSpeed:(id)__unused sender
{
	// todo: make sure _injectLibraryController != nil
	
	double newSpeed = [_speedTextField doubleValue];
	
	if (_speedAddress != 0x0)
	{
		NSNumber *initializedMachAbsoluteTimeAddress = [_process findSymbol:@"gInitializedMachAbsoluteTime" withPartialSymbolOwnerName:@"inject.dylib" requiringExactMatch:YES pastAddress:0x0 allowsWrappingToBeginning:NO];
		
		NSNumber *initializedGetTimeOfDayAddress = [_process findSymbol:@"gInitializedGetTimeOfDay" withPartialSymbolOwnerName:@"inject.dylib" requiringExactMatch:YES pastAddress:0x0 allowsWrappingToBeginning:NO];
		
		if (initializedMachAbsoluteTimeAddress != nil && initializedGetTimeOfDayAddress != nil)
		{
			if (ZGWriteBytes(_process.processTask, _speedAddress, &newSpeed, sizeof(newSpeed)))
			{
				uint8_t initialized = 0;
				
				if (!ZGWriteBytes(_process.processTask, initializedMachAbsoluteTimeAddress.unsignedLongLongValue, &initialized, sizeof(initialized)))
				{
					ZG_LOG(@"Failed to write mach_absolute_time initialization");
				}
				
				if (!ZGWriteBytes(_process.processTask, initializedGetTimeOfDayAddress.unsignedLongLongValue, &initialized, sizeof(initialized)))
				{
					ZG_LOG(@"Failed to write gettimeofday initialization");
				}
			}
		}
		else
		{
			ZG_LOG(@"Error: Failed to find modded mach_absolute_time or gettimeofday");
		}
	}
	else
	{
		_injectLibraryController = [[ZGInjectLibraryController alloc] init];
		[_injectLibraryController
		 injectDynamicLibraryAtPath:[[NSBundle mainBundle] pathForResource:@"inject" ofType:@"dylib"]
		 inProcess:_process
		 breakPointController:_breakPointController
		 completionHandler:^(BOOL success, ZGMachBinary *__unused injectedBinary) {
			 if (success)
			 {
				 [self->_process resymbolicate];
				 
				 ZGSuspendTask(self->_process.processTask);
				 
				 NSNumber *speedMultiplierAddress = [self->_process findSymbol:@"gSpeedMultiplier" withPartialSymbolOwnerName:@"inject.dylib" requiringExactMatch:YES pastAddress:0x0 allowsWrappingToBeginning:NO];
				 
				 if (speedMultiplierAddress != nil)
				 {
					 if (ZGWriteBytes(self->_process.processTask, speedMultiplierAddress.unsignedLongLongValue, &newSpeed, sizeof(newSpeed)))
					 {
						 
						 NSArray *machBinaries = [ZGMachBinary machBinariesInProcess:self->_process];
						 
						 if (machBinaries.count == 0)
						 {
							 ZG_LOG(@"Error: No Mach Binaries were found!");
						 }
						 else
						 {
							 [self replaceLocalStubWithName:@"gettimeofday" newFunctionName:@"my_gettimeofday" process:self->_process machBinaries:machBinaries];
							 
							 [self replaceLocalStubWithName:@"mach_absolute_time" newFunctionName:@"my_mach_absolute_time" process:self->_process machBinaries:machBinaries];
						 }
					 }
					 else
					 {
						 ZG_LOG(@"Failed setting speed modifier upon initial injection");
					 }
				 }
				 
				 ZGResumeTask(self->_process.processTask);
			 }
			 self->_injectLibraryController = nil;
		}];
	}
	
	[NSApp endSheet:self.window];
	[self.window close];
}

- (IBAction)cancel:(id)__unused sender
{
	[NSApp endSheet:self.window];
	[self.window close];
}

@end
