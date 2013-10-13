/*
 * Created by Mayur Pawashe on 9/5/13.
 *
 * Copyright (c) 2013 zgcoder
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

#import "ZGPyDebugger.h"
#import "ZGAppController.h"
#import "ZGDebuggerController.h"
#import "ZGLoggerWindowController.h"
#import "ZGInstruction.h"
#import "ZGVariable.h"
#import "ZGDisassemblerObject.h"
#import "ZGVirtualMemory.h"
#import "ZGProcess.h"
#import "ZGScriptManager.h"
#import "ZGBreakPointController.h"
#import "ZGInstruction.h"
#import <Python/structmember.h>

@class ZGPyDebugger;

typedef struct
{
	PyObject_HEAD
	uint32_t processTask;
	int32_t processIdentifier;
	char is64Bit;
	__unsafe_unretained id <ZGBreakPointDelegate> breakPointDelegate;
} DebuggerClass;

static PyMemberDef Debugger_members[] =
{
	{NULL, 0, 0, 0, NULL}
};

#define declareDebugPrototypeMethod(name) static PyObject *Debugger_##name(DebuggerClass *self, PyObject *args);

declareDebugPrototypeMethod(log)

declareDebugPrototypeMethod(assemble)
declareDebugPrototypeMethod(disassemble)
declareDebugPrototypeMethod(readBytes)
declareDebugPrototypeMethod(writeBytes)
declareDebugPrototypeMethod(bytesBeforeInjection)
declareDebugPrototypeMethod(injectCode)
declareDebugPrototypeMethod(watchWriteAccesses)
declareDebugPrototypeMethod(watchReadAndWriteAccesses)
declareDebugPrototypeMethod(removeWatchAccesses)

#define declareDebugMethod2(name, argsType) {#name"", (PyCFunction)Debugger_##name, argsType, NULL},
#define declareDebugMethod(name) declareDebugMethod2(name, METH_VARARGS)

static PyMethodDef Debugger_methods[] =
{
	declareDebugMethod(log)
	declareDebugMethod(assemble)
	declareDebugMethod(disassemble)
	declareDebugMethod(readBytes)
	declareDebugMethod(writeBytes)
	declareDebugMethod(bytesBeforeInjection)
	declareDebugMethod(injectCode)
	declareDebugMethod(watchWriteAccesses)
	declareDebugMethod(watchReadAndWriteAccesses)
	declareDebugMethod(removeWatchAccesses)
	{NULL, NULL, 0, NULL}
};

static PyTypeObject DebuggerType =
{
	PyVarObject_HEAD_INIT(NULL, 0)
	"bitslicer.Debugger", // tp_name
	sizeof(DebuggerClass), // tp_basicsize
	0, // tp_itemsize
	0, // tp_dealloc
	0, // tp_print
	0, // tp_getattr
	0, // tp_setattr
	0, // tp_compare
	0, // tp_repr
	0, // tp_as_number
	0, // tp_as_sequence
	0, // tp_as_mapping
	0, // tp_hash
	0, // tp_call
	0, // tp_str
	0, // tp_getattro
	0, // tp_setattro
	0, // tp_as_buffer
	Py_TPFLAGS_DEFAULT, // tp_flags
	"Debugger objects", // tp_doc
	0, // tp_traverse
	0, // tp_clear
	0, // tp_richcompare
	0, // tp_weaklistoffset
	0, // tp_iter
	0, // tp_iternext
	Debugger_methods, // tp_methods
	Debugger_members, // tp_members
	0, // tp_getset
	0, // tp_base
	0, // tp_dict
	0, // tp_descr_get
	0, // tp_descr_set
	0, // tp_dictoffset
	0, // tp_init
	0, // tp_alloc
	0, // tp_new
	0, 0, 0, 0, 0, 0, 0, 0, 0 // the rest
};

@interface ZGPyDebugger ()

@property (nonatomic) NSMutableDictionary *cachedInstructionPointers;

@end

@implementation ZGPyDebugger

+ (void)loadPythonClassInMainModule:(PyObject *)module
{
	DebuggerType.tp_new = PyType_GenericNew;
	if (PyType_Ready(&DebuggerType) >= 0)
	{
		Py_INCREF(&DebuggerType);
		
		PyModule_AddObject(module, "Debugger", (PyObject *)&DebuggerType);
	}
	else
	{
		NSLog(@"Error: DebuggerType was not ready!");
	}
}

- (id)initWithProcess:(ZGProcess *)process scriptManager:(ZGScriptManager *)scriptManager
{
	self = [super init];
	if (self != nil)
	{
		PyTypeObject *type = &DebuggerType;
		self.object = (PyObject *)((DebuggerClass *)type->tp_alloc(type, 0));
		if (self.object == NULL)
		{
			return nil;
		}
		
		self.scriptManager = scriptManager;
		
		DebuggerClass *debuggerObject = (DebuggerClass *)self.object;
		debuggerObject->processIdentifier = process.processID;
		debuggerObject->processTask = process.processTask;
		debuggerObject->is64Bit = process.is64Bit;
		debuggerObject->breakPointDelegate = self;
		
		self.cachedInstructionPointers = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)setObject:(PyObject *)object
{
	if (Py_IsInitialized())
	{
		Py_XDECREF(_object);
	}
	_object = object;
}

- (void)dealloc
{
	[[[ZGAppController sharedController] breakPointController] removeObserver:((DebuggerClass *)self.object)->breakPointDelegate];
	self.object = NULL;
}

static PyObject *Debugger_log(DebuggerClass *self, PyObject *args)
{
	PyObject *objectToLog;
	if (!PyArg_ParseTuple(args, "O:log", &objectToLog))
	{
		return NULL;
	}
	
	PyObject *objectToLogString = PyObject_Str(objectToLog);
	PyObject *unicodeObject = PyUnicode_AsUTF8String(objectToLogString);
	char *stringToLog = PyBytes_AsString(unicodeObject);
	NSString *objcStringToLog = nil;
	if (stringToLog != NULL)
	{
		// Try a couple encodings..
		objcStringToLog = [[NSString alloc] initWithCString:stringToLog encoding:NSUTF8StringEncoding];
		
		if (objcStringToLog == nil)
		{
			objcStringToLog = [[NSString alloc] initWithCString:stringToLog encoding:NSASCIIStringEncoding];
		}
		
		if (objcStringToLog == nil)
		{
			ZGVariable *variable = [[ZGVariable alloc] initWithValue:stringToLog size:strlen(stringToLog)-1 address:0 type:ZGByteArray qualifier:0 pointerSize:0];
			objcStringToLog = [NSString stringWithFormat:@"<%@>", [[variable stringValue] copy]];
		}
	}
	
	Py_XDECREF(unicodeObject);
	Py_XDECREF(objectToLogString);
	
	dispatch_async(dispatch_get_main_queue(), ^{
		[[[ZGAppController sharedController] loggerController] writeLine:objcStringToLog];
	});
	
	return Py_BuildValue("");
}

static PyObject *Debugger_assemble(DebuggerClass *self, PyObject *args)
{
	PyObject *retValue = NULL;
	ZGMemoryAddress instructionPointer = 0;
	char *codeString = NULL;
	
	if (PyArg_ParseTuple(args, "s|K:assemble", &codeString, &instructionPointer))
	{
		NSError *error = nil;
		NSData *assembledData = [[[ZGAppController sharedController] debuggerController] assembleInstructionText:@(codeString) atInstructionPointer:instructionPointer usingArchitectureBits:self->is64Bit ? sizeof(int64_t)*8 : sizeof(int32_t)*8 error:&error];
		
		if (error == nil)
		{
			retValue = Py_BuildValue("y#", assembledData.bytes, assembledData.length);
		}
		else
		{
			NSLog(@"Error: couldn't assemble data");
			NSLog(@"%@", error);
			dispatch_async(dispatch_get_main_queue(), ^{
				[[[ZGAppController sharedController] loggerController] writeLine:[[error userInfo] objectForKey:@"reason"]];
				if ([[error userInfo] objectForKey:@"description"] != nil)
				{
					[[[ZGAppController sharedController] loggerController] writeLine:[[error userInfo] objectForKey:@"description"]];
				}
			});
		}
	}
	
	return retValue;
}

static PyObject *Debugger_disassemble(DebuggerClass *self, PyObject *args)
{
	PyObject *retValue = NULL;
	Py_buffer buffer;
	ZGMemoryAddress instructionPointer = 0;
	
	if (PyArg_ParseTuple(args, "s*|K:disassemble", &buffer, &instructionPointer))
	{
		if (!PyBuffer_IsContiguous(&buffer, 'C') || buffer.len <= 0)
		{
			PyBuffer_Release(&buffer);
			return NULL;
		}
		
		ZGDisassemblerObject *disassemblerObject = [[ZGDisassemblerObject alloc] initWithBytes:buffer.buf address:instructionPointer size:buffer.len pointerSize:self->is64Bit ? sizeof(int64_t) : sizeof(int32_t)];
		
		NSMutableArray *disassembledTexts = [[NSMutableArray alloc] init];
		[disassemblerObject enumerateWithBlock:^(ZGMemoryAddress instructionAddress, ZGMemorySize instructionSize, ud_mnemonic_code_t mnemonic, NSString *disassembledText, BOOL *stop) {
			[disassembledTexts addObject:disassembledText];
		}];
		
		NSString *disassembledString = [disassembledTexts componentsJoinedByString:@"\n"];
		retValue = Py_BuildValue("s", [disassembledString UTF8String]);
		
		PyBuffer_Release(&buffer);
	}
	
	return retValue;
}

static PyObject *Debugger_readBytes(DebuggerClass *self, PyObject *args)
{
	PyObject *retValue = NULL;
	ZGMemoryAddress address = 0x0;
	ZGMemorySize size = 0x0;
	if (PyArg_ParseTuple(args, "KK:readBytes", &address, &size))
	{
		NSData *readData = [[[ZGAppController sharedController] debuggerController] readDataWithTaskPort:self->processTask	address:address size:size];
		if (readData != nil)
		{
			retValue = Py_BuildValue("y#", readData.bytes, readData.length);
		}
		else
		{
			NSString *errorMessage = @"Error: Failed to read bytes using debug object";
			NSLog(@"%@", errorMessage);
			dispatch_async(dispatch_get_main_queue(), ^{
				[[[ZGAppController sharedController] loggerController] writeLine:errorMessage];
			});
		}
	}
	return retValue;
}

static PyObject *Debugger_writeBytes(DebuggerClass *self, PyObject *args)
{
	ZGMemoryAddress memoryAddress = 0x0;
	Py_buffer buffer;
	BOOL success = NO;
	
	if (PyArg_ParseTuple(args, "Ks*:writeBytes", &memoryAddress, &buffer))
	{
		if (!PyBuffer_IsContiguous(&buffer, 'C') || buffer.len <= 0)
		{
			PyBuffer_Release(&buffer);
			return NULL;
		}
		
		success = [[[ZGAppController sharedController] debuggerController] writeData:[NSData dataWithBytes:buffer.buf length:buffer.len] atAddress:memoryAddress inTaskPort:self->processTask is64Bit:self->is64Bit];
		
		PyBuffer_Release(&buffer);
	}
	
	return success ? Py_BuildValue("") : NULL;
}

static PyObject *Debugger_bytesBeforeInjection(DebuggerClass *self, PyObject *args)
{
	PyObject *retValue = NULL;
	ZGMemoryAddress sourceAddress = 0x0;
	ZGMemoryAddress destinationAddress = 0x0;
	if (PyArg_ParseTuple(args, "KK:bytesBeforeInjection", &sourceAddress, &destinationAddress))
	{
		NSArray *instructions = [[[ZGAppController sharedController] debuggerController] instructionsBeforeHookingIntoAddress:sourceAddress injectingIntoDestination:destinationAddress inTaskPort:self->processTask pointerSize:self->is64Bit ? sizeof(int64_t) : sizeof(int32_t)];
		ZGMemorySize bufferLength = 0;
		for (ZGInstruction *instruction in instructions)
		{
			bufferLength += instruction.variable.size;
		}
		if (bufferLength > 0)
		{
			char *buffer = malloc(bufferLength);
			char *bufferIterator = buffer;
			
			for (ZGInstruction *instruction in instructions)
			{
				memcpy(bufferIterator, instruction.variable.value, instruction.variable.size);
				bufferIterator += instruction.variable.size;
			}
			
			retValue = Py_BuildValue("y#", buffer, bufferLength);
			
			free(buffer);
		}
	}
	return retValue;
}

static PyObject *Debugger_injectCode(DebuggerClass *self, PyObject *args)
{
	ZGMemoryAddress sourceAddress = 0x0;
	ZGMemoryAddress destinationAddress = 0x0;
	Py_buffer newCode;
	if (PyArg_ParseTuple(args, "KKs*:injectCode", &sourceAddress, &destinationAddress, &newCode))
	{
		if (!PyBuffer_IsContiguous(&newCode, 'C') || newCode.len <= 0)
		{
			PyBuffer_Release(&newCode);
			return NULL;
		}
		
		NSError *error = nil;
		if (![[[ZGAppController sharedController] debuggerController]
		 injectCode:[NSData dataWithBytes:newCode.buf length:newCode.len]
		 intoAddress:destinationAddress
		 hookingIntoOriginalInstructions:[[[ZGAppController sharedController] debuggerController] instructionsBeforeHookingIntoAddress:sourceAddress injectingIntoDestination:destinationAddress inTaskPort:self->processTask pointerSize:self->is64Bit ? sizeof(int64_t) : sizeof(int32_t)]
		 inTaskPort:self->processTask
		 pointerSize:self->is64Bit ? sizeof(int64_t) : sizeof(int32_t)
		 recordUndo:NO
		 error:&error])
		{
			NSLog(@"Failed to inject code from script...");
			NSLog(@"%@", error);
			
			dispatch_async(dispatch_get_main_queue(), ^{
				[[[ZGAppController sharedController] loggerController] writeLine:[[error userInfo] objectForKey:@"reason"]];
				if ([[error userInfo] objectForKey:@"description"] != nil)
				{
					[[[ZGAppController sharedController] loggerController] writeLine:[[error userInfo] objectForKey:@"description"]];
				}
			});
			
			PyBuffer_Release(&newCode);
			return NULL;
		}
		
		PyBuffer_Release(&newCode);
	}
	return Py_BuildValue("");
}

- (void)dataAddress:(NSNumber *)dataAddress accessedByInstructionPointer:(NSNumber *)instructionPointer
{
	ZGMemoryAddress instructionAddress = 0;
	NSNumber *cachedInstructionAddress = [self.cachedInstructionPointers objectForKey:instructionPointer];
	if (cachedInstructionAddress == nil)
	{
		ZGInstruction *instruction = [[[ZGAppController sharedController] debuggerController] findInstructionBeforeAddress:[instructionPointer unsignedLongLongValue] inTaskPort:((DebuggerClass *)self.object)->processTask pointerSize:((DebuggerClass *)self.object)->is64Bit ? sizeof(int64_t) : sizeof(int32_t)];
	
		instructionAddress = instruction.variable.address;
		[self.cachedInstructionPointers setObject:@(instruction.variable.address) forKey:instructionPointer];
	}
	else
	{
		instructionAddress = [[self.cachedInstructionPointers objectForKey:instructionPointer] unsignedLongLongValue];
	}
	
	[self.scriptManager handleBreakPointDataAddress:[dataAddress unsignedLongLongValue] instructionAddress:instructionAddress sender:self];
}

static PyObject *watchAccess(DebuggerClass *self, PyObject *args, NSString *functionName, ZGWatchPointType watchPointType)
{
	PyObject *retValue = NULL;
	ZGMemoryAddress memoryAddress = 0;
	ZGMemorySize numberOfBytes = 0;
	if (PyArg_ParseTuple(args, [[NSString stringWithFormat:@"KK:%@", functionName] UTF8String], &memoryAddress, &numberOfBytes))
	{
		void *value = NULL;
		if (ZGReadBytes(self->processTask, memoryAddress, &value, &numberOfBytes))
		{
			ZGProcess *process = [[ZGProcess alloc] init];
			process.processTask = self->processTask;
			process.is64Bit = self->is64Bit;
			process.processID = self->processIdentifier;
			
			ZGVariable *variable = [[ZGVariable alloc] initWithValue:value size:numberOfBytes address:memoryAddress type:ZGByteArray qualifier:0 pointerSize:process.pointerSize];
			
			if ([[[ZGAppController sharedController] breakPointController] addWatchpointOnVariable:variable inProcess:process watchPointType:watchPointType delegate:self->breakPointDelegate getBreakPoint:NULL])
			{
				retValue = Py_BuildValue("");
			}
			else
			{
				NSLog(@"Failed to add breakpoint in %@...", functionName);
			}
			
			ZGFreeBytes(self->processTask, value, numberOfBytes);
		}
	}
	return retValue;
}

static PyObject *Debugger_watchWriteAccesses(DebuggerClass *self, PyObject *args)
{
	return watchAccess(self, args, @"watchWriteAccesses", ZGWatchPointWrite	);
}

static PyObject *Debugger_watchReadAndWriteAccesses(DebuggerClass *self, PyObject *args)
{
	return watchAccess(self, args, @"watchReadAndWriteAccesses", ZGWatchPointReadOrWrite);
}

static PyObject *Debugger_removeWatchAccesses(DebuggerClass *self, PyObject *args)
{
	PyObject *retValue = NULL;
	ZGMemoryAddress memoryAddress = 0;
	if (PyArg_ParseTuple(args, "K:removeWatchAccesses", &memoryAddress))
	{
		[[[ZGAppController sharedController] breakPointController] removeObserver:self->breakPointDelegate withProcessID:self->processIdentifier atAddress:memoryAddress];
		retValue = Py_BuildValue("");
	}
	return retValue;
}

@end
