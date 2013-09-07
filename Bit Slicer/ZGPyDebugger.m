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
#import <Python/structmember.h>

typedef struct
{
	PyObject_HEAD
	uint32_t processTask;
	char is64Bit;
} DebuggerClass;

static PyMemberDef Debugger_members[] =
{
	{NULL, 0, 0, 0, NULL}
};

#define declareDebugPrototypeMethod(name) static PyObject *Debugger_##name(DebuggerClass *self, PyObject *args);

declareDebugPrototypeMethod(assemble)
declareDebugPrototypeMethod(readBytes)
declareDebugPrototypeMethod(writeBytes)
declareDebugPrototypeMethod(bytesBeforeInjection)
declareDebugPrototypeMethod(injectCode)

#define declareDebugMethod2(name, argsType) {#name"", (PyCFunction)Debugger_##name, argsType, NULL},
#define declareDebugMethod(name) declareDebugMethod2(name, METH_VARARGS)

static PyMethodDef Debugger_methods[] =
{
	declareDebugMethod(assemble)
	declareDebugMethod(readBytes)
	declareDebugMethod(writeBytes)
	declareDebugMethod(bytesBeforeInjection)
	declareDebugMethod(injectCode)
	{NULL, NULL, 0, NULL}
};

static PyTypeObject DebuggerType =
{
	PyObject_HEAD_INIT(NULL)
	0, // ob_size
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

- (id)initWithProcessTask:(ZGMemoryMap)processTask is64Bit:(BOOL)is64Bit
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
		DebuggerClass *debuggerObject = (DebuggerClass *)self.object;
		debuggerObject->processTask = processTask;
		debuggerObject->is64Bit = is64Bit;
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
	self.object = NULL;
}

static PyObject *Debugger_assemble(DebuggerClass *self, PyObject *args)
{
	PyObject *retValue = NULL;
	ZGMemoryAddress instructionPointer = 0;
	char *codeString = NULL;
	
	if (PyArg_ParseTuple(args, "sK", &codeString, &instructionPointer))
	{
		NSError *error = nil;
		NSData *assembledData = [[[ZGAppController sharedController] debuggerController] assembleInstructionText:@(codeString) atInstructionPointer:instructionPointer usingArchitectureBits:self->is64Bit ? sizeof(int64_t)*8 : sizeof(int32_t)*8 error:&error];
		
		if (error == nil)
		{
			retValue = Py_BuildValue("s#", assembledData.bytes, assembledData.length);
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

static PyObject *Debugger_readBytes(DebuggerClass *self, PyObject *args)
{
	PyObject *retValue = NULL;
	ZGMemoryAddress address = 0x0;
	ZGMemorySize size = 0x0;
	if (PyArg_ParseTuple(args, "KK", &address, &size))
	{
		NSData *readData = [[[ZGAppController sharedController] debuggerController] readDataWithTaskPort:self->processTask	address:address size:size];
		if (readData != nil)
		{
			retValue = Py_BuildValue("s#", readData.bytes, readData.length);
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
	
	if (PyArg_ParseTuple(args, "Ks*", &memoryAddress, &buffer))
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
	ZGMemoryAddress memoryAddress = 0x0;
	if (PyArg_ParseTuple(args, "K", &memoryAddress))
	{
		NSArray *instructions = [[[ZGAppController sharedController] debuggerController] instructionsAtMemoryAddress:memoryAddress consumingLength:JUMP_REL32_INSTRUCTION_LENGTH inTaskPort:self->processTask pointerSize:self->is64Bit ? sizeof(int64_t) : sizeof(int32_t)];
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
			
			retValue = Py_BuildValue("s#", buffer, bufferLength);
			
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
	if (PyArg_ParseTuple(args, "KKs*", &sourceAddress, &destinationAddress, &newCode))
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
		 hookingIntoOriginalInstructions:[[[ZGAppController sharedController] debuggerController] instructionsAtMemoryAddress:sourceAddress consumingLength:JUMP_REL32_INSTRUCTION_LENGTH inTaskPort:self->processTask pointerSize:self->is64Bit ? sizeof(int64_t) : sizeof(int32_t)]
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

@end
