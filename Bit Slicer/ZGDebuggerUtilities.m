/*
 * Copyright (c) 2014 Mayur Pawashe
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

#import "ZGDebuggerUtilities.h"
#import "ZGVirtualMemory.h"
#import "ZGBreakPoint.h"
#import "ZGVariable.h"
#import "ZGDisassemblerObject.h"
#import "ZGProcess.h"
#import "ZGRegion.h"
#import "ZGMachBinary.h"
#import "ZGDebugLogging.h"
#import "ZGDataValueExtracting.h"

#define JUMP_REL32_INSTRUCTION_LENGTH 5
#define INDIRECT_JUMP_INSTRUCTIONS_LENGTH 14
#define POP_REGISTER_INSTRUCTION_LENGTH 1

@implementation ZGDebuggerUtilities

#pragma mark Reading & Writing Data

+ (NSData *)readDataWithProcessTask:(ZGMemoryMap)processTask address:(ZGMemoryAddress)address size:(ZGMemorySize)size breakPoints:(NSArray<ZGBreakPoint *> *)breakPoints
{
	void *originalBytes = NULL;
	if (!ZGReadBytes(processTask, address, &originalBytes, &size))
	{
		return nil;
	}
	
	void *newBytes = malloc(size);
	memcpy(newBytes, originalBytes, size);
	
	ZGFreeBytes(originalBytes, size);
	
	for (ZGBreakPoint *breakPoint in breakPoints)
	{
		if (breakPoint.type == ZGBreakPointInstruction && breakPoint.task == processTask && breakPoint.variable.address >= address && breakPoint.variable.address < address + size)
		{
			memcpy((uint8_t *)newBytes + (breakPoint.variable.address - address), breakPoint.variable.rawValue, sizeof(uint8_t));
		}
	}
	
	return [NSData dataWithBytesNoCopy:newBytes length:size];
}

+ (BOOL)writeData:(NSData *)data atAddress:(ZGMemoryAddress)address processTask:(ZGMemoryMap)processTask breakPoints:(NSArray<ZGBreakPoint *> *)breakPoints
{
	BOOL success = YES;
	pid_t processID = 0;
	if (!ZGPIDForTask(processTask, &processID))
	{
		NSLog(@"Error in writeStringValue: method for retrieving process ID");
		success = NO;
	}
	else
	{
		ZGBreakPoint *targetBreakPoint = nil;
		for (ZGBreakPoint *breakPoint in breakPoints)
		{
			if (breakPoint.process.processID == processID && breakPoint.variable.address >= address && breakPoint.variable.address < address + data.length)
			{
				targetBreakPoint = breakPoint;
				break;
			}
		}
		
		if (targetBreakPoint == nil)
		{
			if (!ZGWriteBytesIgnoringProtection(processTask, address, data.bytes, data.length))
			{
				success = NO;
			}
		}
		else
		{
			if (targetBreakPoint.variable.address - address > 0)
			{
				if (!ZGWriteBytesIgnoringProtection(processTask, address, data.bytes, targetBreakPoint.variable.address - address))
				{
					success = NO;
				}
			}
			
			if (address + data.length - targetBreakPoint.variable.address - 1 > 0)
			{
				if (!ZGWriteBytesIgnoringProtection(processTask, targetBreakPoint.variable.address + 1, (const uint8_t *)data.bytes + (targetBreakPoint.variable.address + 1 - address), address + data.length - targetBreakPoint.variable.address - 1))
				{
					success = NO;
				}
			}
			
			*(uint8_t *)targetBreakPoint.variable.rawValue = *((const uint8_t *)data.bytes + targetBreakPoint.variable.address - address);
		}
	}
	
	return success;
}

+ (void)writeStringValue:(NSString *)stringValue atAddress:(ZGMemoryAddress)address inProcess:(ZGProcess *)process breakPoints:(NSArray<ZGBreakPoint *> *)breakPoints
{
	ZGMemorySize newSize = 0;
	void *newValue = ZGValueFromString(process.is64Bit, stringValue, ZGByteArray, &newSize);
	
	[self writeData:[NSData dataWithBytesNoCopy:newValue length:newSize] atAddress:address processTask:process.processTask breakPoints:breakPoints];
}

#pragma mark Assembling & Disassembling

#define ASSEMBLER_ERROR_DOMAIN @"Assembling Failed"
+ (NSData *)assembleInstructionText:(NSString *)instructionText atInstructionPointer:(ZGMemoryAddress)instructionPointer usingArchitectureBits:(ZGMemorySize)numberOfBits error:(NSError * __autoreleasing *)error
{
	NSData *data = [NSData data];
	NSString *outputFileTemplate = [NSTemporaryDirectory() stringByAppendingPathComponent:@"assembler_output.XXXXXX"];
	const char *tempFileTemplateCString = [outputFileTemplate fileSystemRepresentation];
	size_t templateFileTemplateLength = strlen(tempFileTemplateCString);
	char *tempFileNameCString = malloc(templateFileTemplateLength + 1);
	strncpy(tempFileNameCString, tempFileTemplateCString, templateFileTemplateLength + 1);
	int fileDescriptor = mkstemp(tempFileNameCString);
	
	if (fileDescriptor != -1)
	{
		close(fileDescriptor);
		
		NSFileManager *fileManager = [[NSFileManager alloc] init];
		NSString *outputFilePath = [fileManager stringWithFileSystemRepresentation:tempFileNameCString length:strlen(tempFileNameCString)];
		
		NSTask *task = [[NSTask alloc] init];
		task.launchPath = [[[[NSBundle mainBundle] executablePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"yasm"];
		[task setArguments:@[@"--arch=x86", @"-", @"-o", outputFilePath]];
		
		NSPipe *inputPipe = [NSPipe pipe];
		[task setStandardInput:inputPipe];
		
		NSPipe *errorPipe = [NSPipe pipe];
		[task setStandardError:errorPipe];
		
		BOOL failedToLaunchTask = NO;
		
		@try
		{
			[task launch];
		}
		@catch (NSException *exception)
		{
			failedToLaunchTask = YES;
			if (error != nil)
			{
				NSString *exceptionReason = exception.reason != nil ? exception.reason : @"";
				*error = [NSError errorWithDomain:ASSEMBLER_ERROR_DOMAIN code:kCFStreamErrorDomainCustom userInfo:@{@"description" : [NSString stringWithFormat:@"%@: Name: %@, Reason: %@", ZGLocalizedStringFromDebuggerTable(@"failedLaunchYasm"), exception.name, exceptionReason], @"reason" : exceptionReason}];
			}
		}
		
		if (!failedToLaunchTask)
		{
			// yasm likes to be fed in an aligned instruction pointer for its org specifier, so we'll comply with that
			ZGMemoryAddress alignedInstructionPointer = instructionPointer - (instructionPointer % 4);
			NSUInteger numberOfNoppedInstructions = instructionPointer - alignedInstructionPointer;
			
			// clever way of @"nop" * numberOfNoppedInstructions, if it existed
			NSString *nopLine = @"nop\n";
			NSString *nopsString = [@"" stringByPaddingToLength:numberOfNoppedInstructions * nopLine.length withString:nopLine startingAtIndex:0];
			
			NSData *inputData = [[NSString stringWithFormat:@"BITS %lld\norg %lld\n%@%@\n", numberOfBits, alignedInstructionPointer, nopsString, instructionText] dataUsingEncoding:NSUTF8StringEncoding];
			
			[[inputPipe fileHandleForWriting] writeData:inputData];
			[[inputPipe fileHandleForWriting] closeFile];
			
			[task waitUntilExit];
			
			if ([task terminationStatus] == EXIT_SUCCESS)
			{
				NSData *tempData = [NSData dataWithContentsOfFile:outputFilePath];
				
				if (tempData.length <= numberOfNoppedInstructions)
				{
					if (error != nil)
					{
						*error = [NSError errorWithDomain:ASSEMBLER_ERROR_DOMAIN code:kCFStreamErrorDomainCustom userInfo:@{@"reason" : ZGLocalizedStringFromDebuggerTable(@"failedAssembleWithZeroBytes")}];
					}
				}
				else
				{
					data = [NSData dataWithBytes:(const uint8_t *)tempData.bytes + numberOfNoppedInstructions length:tempData.length - numberOfNoppedInstructions];
				}
			}
			else
			{
				NSData *errorData = [[errorPipe fileHandleForReading] readDataToEndOfFile];
				if (errorData != nil && error != nil)
				{
					NSString *errorString = [[[[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding] componentsSeparatedByString:@"\n"] objectAtIndex:0];
					*error = [NSError errorWithDomain:ASSEMBLER_ERROR_DOMAIN code:kCFStreamErrorDomainCustom userInfo:@{@"reason" : errorString}];
				}
			}
			
			if ([fileManager fileExistsAtPath:outputFilePath])
			{
				[fileManager removeItemAtPath:outputFilePath error:NULL];
			}
		}
	}
	else if (error != nil)
	{
		*error = [NSError errorWithDomain:ASSEMBLER_ERROR_DOMAIN code:kCFStreamErrorDomainCustom userInfo:@{@"reason" : [NSString stringWithFormat:ZGLocalizedStringFromDebuggerTable(@"failedAssembleWithBadFileDescriptor"), tempFileNameCString]}];
	}
	
	free(tempFileNameCString);
	
	return data;
}

+ (ZGDisassemblerObject *)disassemblerObjectWithProcessTask:(ZGMemoryMap)processTask pointerSize:(ZGMemorySize)pointerSize address:(ZGMemoryAddress)address size:(ZGMemorySize)size breakPoints:(NSArray<ZGBreakPoint *> *)breakPoints
{
	ZGDisassemblerObject *newObject = nil;
	NSData *data = [self readDataWithProcessTask:processTask address:address size:size breakPoints:breakPoints];
	if (data != nil)
	{
		newObject = [[ZGDisassemblerObject alloc] initWithBytes:data.bytes address:address size:data.length pointerSize:pointerSize];
	}
	return newObject;
}

#pragma mark Finding Instructions

+ (ZGInstruction *)findInstructionBeforeAddress:(ZGMemoryAddress)address inProcess:(ZGProcess *)process withBreakPoints:(NSArray<ZGBreakPoint *> *)breakPoints machBinaries:(NSArray<ZGMachBinary *> *)machBinaries
{
	ZGInstruction *instruction = nil;
	
	ZGMemoryBasicInfo regionInfo;
	ZGRegion *targetRegion = [[ZGRegion alloc] initWithAddress:address size:1];
	if (!ZGRegionInfo(process.processTask, &targetRegion->_address, &targetRegion->_size, &regionInfo))
	{
		targetRegion = nil;
	}
	
	if (targetRegion != nil && address >= targetRegion.address && address <= targetRegion.address + targetRegion.size)
	{
		// Start an arbitrary number of bytes before our address and decode the instructions
		// Eventually they will converge into correct offsets
		// So retrieve the offset and size to the last instruction while decoding
		// We do this instead of starting at region.address due to this leading to better performance
		
		ZGMemoryAddress startAddress = address - 1024;
		if (startAddress < targetRegion.address)
		{
			startAddress = targetRegion.address;
		}
		
		// If we can find a close starting address in a mach binary, we should use it, otherwise we may disassemble the first instruction in it incorrectly
		ZGMachBinary *machBinary = [ZGMachBinary machBinaryNearestToAddress:address fromMachBinaries:machBinaries];
		ZGMemoryAddress firstInstructionAddress = [[machBinary machBinaryInfoInProcess:process] firstInstructionAddress];
		
		if (firstInstructionAddress != 0 && startAddress < firstInstructionAddress)
		{
			startAddress = firstInstructionAddress;
			if (address < startAddress)
			{
				return instruction;
			}
		}
		
		ZGMemorySize size = address - startAddress;
		// Read in more bytes to ensure we return the whole instruction
		ZGMemorySize readSize = size + 30;
		if (startAddress + readSize > targetRegion.address + targetRegion.size)
		{
			readSize = targetRegion.address + targetRegion.size - startAddress;
		}
		
		ZGDisassemblerObject *disassemblerObject = [self disassemblerObjectWithProcessTask:process.processTask pointerSize:process.pointerSize address:startAddress size:readSize breakPoints:breakPoints];
		
		instruction = [disassemblerObject readLastInstructionWithMaxSize:size];
	}
	
	return instruction;
}

#pragma mark Replacing Instructions

+ (void)
replaceInstructions:(NSArray<ZGInstruction *> *)instructions
fromOldStringValues:(NSArray<NSString *> *)oldStringValues
toNewStringValues:(NSArray<NSString *> *)newStringValues
inProcess:(ZGProcess *)process
breakPoints:(NSArray<ZGBreakPoint *> *)breakPoints
undoManager:(NSUndoManager *)undoManager
actionName:(NSString *)actionName
{
	for (NSUInteger index = 0; index < instructions.count; index++)
	{
		ZGInstruction *instruction = [instructions objectAtIndex:index];
		[self writeStringValue:[newStringValues objectAtIndex:index] atAddress:instruction.variable.address inProcess:process breakPoints:breakPoints];
	}
	
	if (undoManager != nil)
	{
		if (actionName != nil)
		{
			[undoManager setActionName:[actionName stringByAppendingFormat:@"%@", instructions.count == 1 ? @"" : @"s"]];
		}
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-messaging-id"
		// There's no way that I know of to typecast to an obj-c class so you can send that instance a class message, rather than an instance level one.
		[[undoManager prepareWithInvocationTarget:self] replaceInstructions:instructions fromOldStringValues:newStringValues toNewStringValues:oldStringValues inProcess:process breakPoints:breakPoints undoManager:undoManager actionName:actionName];
#pragma clang diagnostic pop
	}
}

+ (void)nopInstructions:(NSArray<ZGInstruction *> *)instructions inProcess:(ZGProcess *)process breakPoints:(NSArray<ZGBreakPoint *> *)breakPoints undoManager:(NSUndoManager *)undoManager actionName:(NSString *)actionName
{
	NSMutableArray<NSString *> *newStringValues = [[NSMutableArray alloc] init];
	NSMutableArray<NSString *> *oldStringValues = [[NSMutableArray alloc] init];
	
	for (NSUInteger instructionIndex = 0; instructionIndex < instructions.count; instructionIndex++)
	{
		ZGInstruction *instruction = [instructions objectAtIndex:instructionIndex];
		[oldStringValues addObject:instruction.variable.stringValue];
		
		NSMutableArray<NSString *> *nopComponents = [[NSMutableArray alloc] init];
		for (NSUInteger nopIndex = 0; nopIndex < instruction.variable.size; nopIndex++)
		{
			[nopComponents addObject:@"90"];
		}
		
		[newStringValues addObject:[nopComponents componentsJoinedByString:@" "]];
	}
	
	[self replaceInstructions:instructions fromOldStringValues:oldStringValues toNewStringValues:newStringValues inProcess:process breakPoints:breakPoints undoManager:undoManager actionName:actionName];
}

#pragma mark Code Injection

+ (BOOL)shouldInjectCodeWithRelativeBranchingWithProcess:(ZGProcess *)process sourceAddress:(ZGMemoryAddress)sourceAddress destinationAddress:(ZGMemoryAddress)destinationAddress
{
	return
		(process.pointerSize == sizeof(ZG32BitMemoryAddress) ||
		 (destinationAddress > sourceAddress && destinationAddress - sourceAddress <= INT32_MAX) ||
		 (sourceAddress > destinationAddress && sourceAddress - destinationAddress <= INT32_MAX));
}

#define INJECT_ERROR_DOMAIN @"INJECT_CODE_FAILED"
+ (BOOL)
injectCode:(NSData *)codeData
intoAddress:(ZGMemoryAddress)allocatedAddress
hookingIntoOriginalInstructions:(NSArray<ZGInstruction *> *)hookedInstructions
process:(ZGProcess *)process
breakPoints:(NSArray<ZGBreakPoint *> *)breakPoints
undoManager:(NSUndoManager *)undoManager
error:(NSError * __autoreleasing *)error
{
	if (hookedInstructions == nil)
	{
		return NO;
	}
	
	ZGSuspendTask(process.processTask);
	
	void *nopBuffer = malloc(codeData.length);
	memset(nopBuffer, NOP_VALUE, codeData.length);
	
	if (!ZGWriteBytesIgnoringProtection(process.processTask, allocatedAddress, nopBuffer, codeData.length))
	{
		ZG_LOG(@"Error: Failed to write nop buffer..");
		if (error != nil)
		{
			*error = [NSError errorWithDomain:INJECT_ERROR_DOMAIN code:kCFStreamErrorDomainCustom userInfo:@{@"reason" : ZGLocalizedStringFromDebuggerTable(@"failedNOPInstructionsForInjectingCode")}];
		}

		free(nopBuffer);
		ZGResumeTask(process.processTask);
		return NO;
	}
	
	free(nopBuffer);
	
	if (!ZGProtect(process.processTask, allocatedAddress, codeData.length, VM_PROT_READ | VM_PROT_EXECUTE))
	{
		ZG_LOG(@"Error: Failed to protect memory..");
		if (error != nil)
		{
			*error = [NSError errorWithDomain:INJECT_ERROR_DOMAIN code:kCFStreamErrorDomainCustom userInfo:@{@"reason" : ZGLocalizedStringFromDebuggerTable(@"failedChangeMemoryProtectionForInjectingCode")}];
		}
		
		ZGResumeTask(process.processTask);
		return NO;
	}
	
	[undoManager setActionName:@"Inject code"];
	
	[self nopInstructions:hookedInstructions inProcess:process breakPoints:breakPoints undoManager:undoManager actionName:nil];
	
	ZGMemorySize hookedInstructionsLength = 0;
	for (ZGInstruction *instruction in hookedInstructions)
	{
		hookedInstructionsLength += instruction.variable.size;
	}
	ZGInstruction *firstInstruction = [hookedInstructions objectAtIndex:0];

	BOOL usingRelativeBranching =
	[self shouldInjectCodeWithRelativeBranchingWithProcess:process sourceAddress:firstInstruction.variable.address destinationAddress:allocatedAddress] &&
	[self shouldInjectCodeWithRelativeBranchingWithProcess:process sourceAddress:allocatedAddress + codeData.length destinationAddress:firstInstruction.variable.address + hookedInstructionsLength];
	
	NSMutableData *newInstructionsData = [NSMutableData data];
	if (!usingRelativeBranching)
	{
		NSData *popRaxData = [self assembleInstructionText:@"pop rax" atInstructionPointer:allocatedAddress usingArchitectureBits:process.pointerSize*8 error:error];
		if (popRaxData.length == 0)
		{
			ZG_LOG(@"Error: Failed to assemble pop rax");
			ZGResumeTask(process.processTask);
			return NO;
		}
		[newInstructionsData appendData:popRaxData	];
	}
	while (newInstructionsData.length < INJECTED_NOP_SLIDE_LENGTH)
	{
		uint8_t nopValue = NOP_VALUE;
		[newInstructionsData appendBytes:&nopValue length:1];
	}
	[newInstructionsData appendData:codeData];

	NSData *jumpToIslandData =
	[[self class]
	 assembleInstructionText:usingRelativeBranching ? [NSString stringWithFormat:@"jmp %lld", allocatedAddress] : [NSString stringWithFormat:@"push rax\nmov rax, %lld\njmp rax\npop rax", allocatedAddress]
	 atInstructionPointer:firstInstruction.variable.address
	 usingArchitectureBits:process.pointerSize*8
	 error:error];
	
	if (jumpToIslandData.length == 0)
	{
		ZG_LOG(@"Error generating jumpToIslandData");
		ZGResumeTask(process.processTask);
		return NO;
	}
	
	ZGVariable *variable =
	[[ZGVariable alloc]
	 initWithValue:jumpToIslandData.bytes
	 size:jumpToIslandData.length
	 address:firstInstruction.variable.address
	 type:ZGByteArray
	 qualifier:0
	 pointerSize:process.pointerSize];
	
	[self
	 replaceInstructions:@[firstInstruction]
	 fromOldStringValues:@[firstInstruction.variable.stringValue]
	 toNewStringValues:@[variable.stringValue]
	 inProcess:process
	 breakPoints:breakPoints
	 undoManager:undoManager
	 actionName:nil];

	NSData *jumpFromIslandData =
	[[self class]
	 assembleInstructionText:usingRelativeBranching ? [NSString stringWithFormat:@"jmp %lld", firstInstruction.variable.address + hookedInstructionsLength] : [NSString stringWithFormat:@"push rax\nmov rax, %lld\njmp rax", firstInstruction.variable.address + jumpToIslandData.length - POP_REGISTER_INSTRUCTION_LENGTH]
	 atInstructionPointer:allocatedAddress + newInstructionsData.length
	 usingArchitectureBits:process.pointerSize*8
	 error:error];
	
	if (jumpFromIslandData.length == 0)
	{
		ZG_LOG(@"Error generating jumpFromIslandData");
		ZGResumeTask(process.processTask);
		return NO;
	}
	
	[newInstructionsData appendData:jumpFromIslandData];
	ZGWriteBytesIgnoringProtection(process.processTask, allocatedAddress, newInstructionsData.bytes, newInstructionsData.length);
	
	ZGResumeTask(process.processTask);

	return YES;
}

+ (NSArray<ZGInstruction *> *)instructionsBeforeHookingIntoAddress:(ZGMemoryAddress)address injectingIntoDestination:(ZGMemoryAddress)destinationAddress inProcess:(ZGProcess *)process withBreakPoints:(NSArray<ZGBreakPoint *> *)breakPoints
{
	int consumedLength =
	[self shouldInjectCodeWithRelativeBranchingWithProcess:process sourceAddress:address destinationAddress:destinationAddress] ?
	JUMP_REL32_INSTRUCTION_LENGTH :
	INDIRECT_JUMP_INSTRUCTIONS_LENGTH;
	
	NSArray<ZGMachBinary *> *machBinaries = [ZGMachBinary machBinariesInProcess:process];
	NSMutableArray<ZGInstruction *> *instructions = [[NSMutableArray alloc] init];
	while (consumedLength > 0)
	{
		ZGInstruction *newInstruction = [self findInstructionBeforeAddress:address+1 inProcess:process withBreakPoints:breakPoints machBinaries:machBinaries];
		if (newInstruction == nil)
		{
			instructions = nil;
			break;
		}
		[instructions addObject:newInstruction];
		consumedLength -= newInstruction.variable.size;
		address += newInstruction.variable.size;
	}
	
	return [instructions copy];
}

@end
