/*
 * Copyright (c) 2013 Mayur Pawashe
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
#import "ZGScriptingInterpreter.h"
#import "ZGDebuggerUtilities.h"
#import "ZGLoggerWindowController.h"
#import "ZGInstruction.h"
#import "ZGVariable.h"
#import "ZGDisassemblerObject.h"
#import "ZGVirtualMemory.h"
#import "ZGProcess.h"
#import "ZGScriptManager.h"
#import "ZGBreakPointController.h"
#import "ZGBreakPoint.h"
#import "ZGRegistersState.h"
#import "ZGInstruction.h"
#import "ZGThreadStates.h"
#import "ZGRegisterEntries.h"
#import "ZGMachBinary.h"
#import "Python/structmember.h"
#import "ZGDeliverUserNotifications.h"
#import "ZGPyVirtualMemory.h"
#import "ZGBacktrace.h"
#import "NSArrayAdditions.h"
#import "ZGHotKeyCenter.h"
#import "ZGHotKey.h"
#import "ZGScriptPrompt.h"
#import "ZGNullability.h"

@class ZGPyDebugger;

typedef struct
{
	PyObject_HEAD
	uint32_t processTask;
	int32_t processIdentifier;
	int8_t is64Bit;
	PyObject *virtualMemoryException;
	PyObject *debuggerException;
	__unsafe_unretained ZGPyDebugger *objcSelf;
	__unsafe_unretained id <ZGBreakPointDelegate> breakPointDelegate;
} DebuggerClass;

static PyMemberDef Debugger_members[] =
{
	{NULL, 0, 0, 0, NULL}
};

#define declareDebugPrototypeMethod(name) static PyObject *Debugger_##name(DebuggerClass *self, PyObject *args);

declareDebugPrototypeMethod(log)
declareDebugPrototypeMethod(notify)
declareDebugPrototypeMethod(prompt)
declareDebugPrototypeMethod(activate)
declareDebugPrototypeMethod(registerHotkey)
declareDebugPrototypeMethod(unregisterHotkey)
declareDebugPrototypeMethod(isRegisteredHotkey)

declareDebugPrototypeMethod(assemble)
declareDebugPrototypeMethod(disassemble)
declareDebugPrototypeMethod(readBytes)
declareDebugPrototypeMethod(writeBytes)
declareDebugPrototypeMethod(findSymbol)
declareDebugPrototypeMethod(symbolAt)
declareDebugPrototypeMethod(bytesBeforeInjection)
declareDebugPrototypeMethod(injectCode)
declareDebugPrototypeMethod(watchWriteAccesses)
declareDebugPrototypeMethod(watchReadAndWriteAccesses)
declareDebugPrototypeMethod(removeWatchAccesses)
declareDebugPrototypeMethod(addBreakpoint)
declareDebugPrototypeMethod(removeBreakpoint)
declareDebugPrototypeMethod(resume)
declareDebugPrototypeMethod(stepIn)
declareDebugPrototypeMethod(stepOver)
declareDebugPrototypeMethod(stepOut)
declareDebugPrototypeMethod(backtrace)
declareDebugPrototypeMethod(writeRegisters)

#define declareDebugMethod2(name, argsType) {#name"", (PyCFunction)Debugger_##name, argsType, NULL},
#define declareDebugMethod(name) declareDebugMethod2(name, METH_VARARGS)

static PyMethodDef Debugger_methods[] =
{
	declareDebugMethod(log)
	declareDebugMethod(notify)
	declareDebugMethod(prompt)
	declareDebugMethod(activate)
	declareDebugMethod(registerHotkey)
	declareDebugMethod(unregisterHotkey)
	declareDebugMethod(isRegisteredHotkey)
	declareDebugMethod(assemble)
	declareDebugMethod(disassemble)
	declareDebugMethod(findSymbol)
	declareDebugMethod(symbolAt)
	declareDebugMethod(readBytes)
	declareDebugMethod(writeBytes)
	declareDebugMethod(bytesBeforeInjection)
	declareDebugMethod(injectCode)
	declareDebugMethod(watchWriteAccesses)
	declareDebugMethod(watchReadAndWriteAccesses)
	declareDebugMethod(removeWatchAccesses)
	declareDebugMethod(addBreakpoint)
	declareDebugMethod(removeBreakpoint)
	declareDebugMethod(resume)
	declareDebugMethod(stepIn)
	declareDebugMethod(stepOver)
	declareDebugMethod(stepOut)
	declareDebugMethod(backtrace)
	declareDebugMethod(writeRegisters)
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
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0 // the rest
};

@implementation ZGPyDebugger
{
	ZGScriptingInterpreter * _Nonnull _scriptingInterpreter;
	
	__weak ZGScriptManager * _Nullable _scriptManager;
	ZGBreakPointController * _Nonnull _breakPointController;
	ZGLoggerWindowController * _Nonnull _loggerWindowController;
	NSMutableDictionary<NSNumber *, NSNumber *> * _Nonnull _cachedInstructionPointers;
	ZGHotKeyCenter * _Nonnull _hotKeyCenter;
	ZGProcess * _Nonnull _process;
	ZGBreakPoint * _Nullable _haltedBreakPoint;
	NSDictionary<NSString *, NSValue *> * _Nullable _generalPurposeRegisterOffsetsDictionary;
	NSDictionary<NSString *, NSValue *> * _Nullable _vectorRegisterOffsetsDictionary;
}

+ (PyObject *)loadPythonClassInMainModule:(PyObject *)module
{
	PyObject *debuggerException = NULL;
	DebuggerType.tp_new = PyType_GenericNew;
	if (PyType_Ready(&DebuggerType) >= 0)
	{
		Py_INCREF(&DebuggerType);
		
		PyModule_AddObject(module, "Debugger", (PyObject *)&DebuggerType);
		
		const char *debuggerExceptionName = "DebuggerError";
		NSString *exceptionNameWithModule = [NSString stringWithFormat:@"%s.%s", PyModule_GetName(module), debuggerExceptionName];
		
		debuggerException = PyErr_NewException([exceptionNameWithModule UTF8String], NULL, NULL);
		if (PyModule_AddObject(module, debuggerExceptionName, debuggerException) != 0)
		{
			NSLog(@"Failed to add Debugger to Python Module");
		}
	}
	else
	{
		NSLog(@"Error: DebuggerType was not ready!");
	}
	
	return debuggerException;
}

- (id)initWithProcess:(ZGProcess *)process scriptingInterpreter:(ZGScriptingInterpreter *)scriptingInterpreter scriptManager:(ZGScriptManager *)scriptManager breakPointController:(ZGBreakPointController *)breakPointController hotKeyCenter:(ZGHotKeyCenter *)hotKeyCenter loggerWindowController:(ZGLoggerWindowController *)loggerWindowController
{
	self = [super init];
	if (self != nil)
	{
		PyTypeObject *type = &DebuggerType;
		[self setObject:(PyObject *)((DebuggerClass *)type->tp_alloc(type, 0))];
		if (_object == NULL)
		{
			return nil;
		}
		
		_scriptManager = scriptManager;
		_scriptingInterpreter = scriptingInterpreter;
		_process = [[ZGProcess alloc] initWithProcess:process];
		_breakPointController = breakPointController;
		_loggerWindowController = loggerWindowController;
		_hotKeyCenter = hotKeyCenter;
		
		DebuggerClass *debuggerObject = (DebuggerClass *)_object;
		debuggerObject->objcSelf = self;
		debuggerObject->processIdentifier = process.processID;
		debuggerObject->processTask = process.processTask;
		debuggerObject->is64Bit = process.is64Bit;
		debuggerObject->virtualMemoryException = scriptingInterpreter.virtualMemoryException;
		debuggerObject->debuggerException = scriptingInterpreter.debuggerException;
		debuggerObject->breakPointDelegate = self;
		
		_cachedInstructionPointers = [[NSMutableDictionary alloc] init];
	}
	return self;
}

// Use cleanup method instead of dealloc since the break point controller's weak delegate reference may be nil by that time
- (void)cleanup
{
	__block NSArray<ZGHotKey *> *unregisteredHotKeys = nil;
	dispatch_async(dispatch_get_main_queue(), ^{
		unregisteredHotKeys = [self->_hotKeyCenter unregisterHotKeysWithDelegate:self];
	});
	
	if (Py_IsInitialized())
	{
		for (ZGHotKey *hotKey in unregisteredHotKeys)
		{
			PyObject *callback = hotKey.userData;
			Py_XDECREF(callback);
		}
	}
	
	if (_haltedBreakPoint != nil)
	{
		_haltedBreakPoint.dead = YES;
		[_breakPointController resumeFromBreakPoint:(ZGBreakPoint * _Nonnull)_haltedBreakPoint];
	}
	
	NSArray<ZGBreakPoint *> *removedBreakPoints = [_breakPointController removeObserver:self];
	if (Py_IsInitialized())
	{
		for (ZGBreakPoint *breakPoint in removedBreakPoints)
		{
			PyObject *callback = breakPoint.callback;
			if (callback != NULL)
			{
				Py_DecRef(callback);
				breakPoint.callback = NULL;
			}
		}
	}
	
	[self setObject:NULL];
}

- (void)setObject:(PyObject *)object
{
	if (Py_IsInitialized())
	{
		Py_XDECREF(_object);
	}
	_object = object;
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
	
	ZGPyDebugger *debugger = self->objcSelf;
	dispatch_async(dispatch_get_main_queue(), ^{
		[debugger->_loggerWindowController writeLine:objcStringToLog];
	});
	
	return Py_BuildValue("");
}

static PyObject *Debugger_notify(DebuggerClass * __unused self, PyObject *args)
{
	Py_buffer title, informativeText;
	if (!PyArg_ParseTuple(args, "s*s*:notify", &title, &informativeText))
	{
		return NULL;
	}
	
	PyObject *retValue = NULL;
	
	if (!PyBuffer_IsContiguous(&title, 'C') || !PyBuffer_IsContiguous(&informativeText, 'C'))
	{
		PyErr_SetString(PyExc_BufferError, "debug.notify can't take in non-contiguous buffer");
	}
	else
	{
		NSString *titleString = [[NSString alloc] initWithBytes:title.buf length:(NSUInteger)title.len encoding:NSUTF8StringEncoding];
		NSString *informativeTextString = [[NSString alloc] initWithBytes:informativeText.buf length:(NSUInteger)informativeText.len encoding:NSUTF8StringEncoding];
		
		dispatch_async(dispatch_get_main_queue(), ^{
			ZGDeliverUserNotification(titleString, nil, informativeTextString, @{ZGScriptNotificationTypeKey : @(YES)});
		});
		
		retValue = Py_BuildValue("");
	}
	
	PyBuffer_Release(&title);
	PyBuffer_Release(&informativeText);
	
	return retValue;
}

- (void)scriptPrompt:(ZGScriptPrompt *)scriptPrompt didReceiveAnswer:(NSString *)answer
{
	ZGScriptManager *scriptManager = _scriptManager;
	[_scriptingInterpreter dispatchAsync:^{
		[scriptManager handleScriptPrompt:scriptPrompt withAnswer:answer sender:self];
	}];
}

static PyObject *Debugger_prompt(DebuggerClass *self, PyObject *args)
{
	Py_buffer text;
	Py_buffer defaultAnswer;
	PyObject *callback = NULL;
	
	if (!PyArg_ParseTuple(args, "s*s*O:prompt", &text, &defaultAnswer, &callback))
	{
		return NULL;
	}
	
	if (!PyBuffer_IsContiguous(&text, 'C') || !PyBuffer_IsContiguous(&defaultAnswer, 'C'))
	{
		PyErr_SetString(PyExc_BufferError, "debug.prompt can't take in non-contiguous buffer");
		
		PyBuffer_Release(&text);
		PyBuffer_Release(&defaultAnswer);
		return NULL;
	}
	
	if (PyCallable_Check(callback) == 0)
	{
		PyErr_SetString(PyExc_ValueError, "debug.prompt failed because callback is not callable");
		
		PyBuffer_Release(&text);
		PyBuffer_Release(&defaultAnswer);
		return NULL;
	}
	
	ZGPyDebugger *selfReference = self->objcSelf;
	ZGScriptManager *scriptManager = selfReference.scriptManager;
	
	__block BOOL attachedPrompt = NO;
	dispatch_sync(dispatch_get_main_queue(), ^{
		attachedPrompt = scriptManager.hasAttachedPrompt;
	});
	
	if (attachedPrompt)
	{
		PyErr_SetString(self->debuggerException, "debug.prompt failed because a prompt is already visible");
		return NULL;
	}
	
	NSString *textString = [[NSString alloc] initWithBytes:text.buf length:(NSUInteger)text.len encoding:NSUTF8StringEncoding];
	NSString *defaultAnswerString = [[NSString alloc] initWithBytes:defaultAnswer.buf length:(NSUInteger)defaultAnswer.len encoding:NSUTF8StringEncoding];
	
	Py_XINCREF(callback);
	
	// We can't async here because we want to prevent showing a prompt when another prompt from this or another script is already visible
	dispatch_sync(dispatch_get_main_queue(), ^{
		[scriptManager
		 showScriptPrompt:[[ZGScriptPrompt alloc] initWithMessage:textString defaultAnswer:defaultAnswerString userData:callback]
		 delegate:selfReference];
	});
	
	PyBuffer_Release(&text);
	PyBuffer_Release(&defaultAnswer);
	
	return Py_BuildValue("");
}

static PyObject *Debugger_activate(DebuggerClass *self, PyObject *__unused args)
{
	NSRunningApplication *runningApplication = [NSRunningApplication runningApplicationWithProcessIdentifier:self->processIdentifier];
	if (runningApplication == nil)
	{
		Py_RETURN_FALSE;
	}
	
	BOOL didActivate = [runningApplication activateWithOptions:NSApplicationActivateAllWindows];
	return PyBool_FromLong(didActivate);
}

- (void)hotKeyDidTrigger:(ZGHotKey *)hotKey
{
	UInt32 hotKeyID = hotKey.internalID;
	PyObject *callback = hotKey.userData;
	
	ZGScriptManager *scriptManager = _scriptManager;
	[_scriptingInterpreter dispatchAsync:^{
		[scriptManager handleHotKeyTriggerWithInternalID:hotKeyID callback:callback sender:self];
	}];
}

static PyObject *Debugger_registerHotkey(DebuggerClass *self, PyObject *args)
{
	UInt32 keyCode = 0;
	UInt32 modifierFlags = 0;
	PyObject *callback = NULL;
	ZGHotKey *hotKey = nil;
	if (!PyArg_ParseTuple(args, "IIO:registerHotKey", &keyCode, &modifierFlags, &callback))
	{
		return NULL;
	}
	
	if (PyCallable_Check(callback) == 0)
	{
		PyErr_SetString(PyExc_ValueError, [[NSString stringWithFormat:@"debug.registerHotKey failed registering code = 0x%X, flags = 0x%X because callback is not callable", keyCode, modifierFlags] UTF8String]);
		return NULL;
	}
	
	__block BOOL registeredHotKey = NO;
	hotKey = [ZGHotKey hotKeyWithKeyCombo:(KeyCombo){.code = keyCode, .flags = modifierFlags}];
	
	dispatch_sync(dispatch_get_main_queue(), ^{
		registeredHotKey = [self->objcSelf->_hotKeyCenter registerHotKey:hotKey delegate:self->objcSelf];
	});
	
	if (!registeredHotKey)
	{
		PyErr_SetString(self->debuggerException, [[NSString stringWithFormat:@"debug.registerHotKey failed to register code = 0x%X, flags = 0x%X. Perhaps it is already being in use?", keyCode, modifierFlags] UTF8String]);
		return NULL;
	}
	
	hotKey.userData = callback;
	Py_XINCREF(callback);
	
	return Py_BuildValue("I", hotKey.internalID);
}

static PyObject *Debugger_unregisterHotkey(DebuggerClass *self, PyObject *args)
{
	UInt32 hotKeyID = 0;
	if (!PyArg_ParseTuple(args, "I:unregisterHotKey", &hotKeyID))
	{
		return NULL;
	}
	
	__block ZGHotKey *unregisteredHotKey = nil;
	dispatch_sync(dispatch_get_main_queue(), ^{
		unregisteredHotKey = [self->objcSelf->_hotKeyCenter unregisterHotKeyWithInternalID:hotKeyID];
	});
	
	if (unregisteredHotKey == nil)
	{
		PyErr_SetString(self->debuggerException, [[NSString stringWithFormat:@"debug.unregisterHotKey failed to unregister hot key with ID %d", hotKeyID] UTF8String]);
		return NULL;
	}
	
	PyObject *callback = unregisteredHotKey.userData;
	Py_XDECREF(callback);
	
	return Py_BuildValue("");
}

static PyObject *Debugger_isRegisteredHotkey(DebuggerClass *self, PyObject *args)
{
	UInt32 keyCode = 0;
	UInt32 modifierFlags = 0;
	if (!PyArg_ParseTuple(args, "II:isRegisteredHotKey", &keyCode, &modifierFlags))
	{
		return NULL;
	}
	
	__block BOOL isRegistered = NO;
	dispatch_sync(dispatch_get_main_queue(), ^{
		isRegistered = [self->objcSelf->_hotKeyCenter isRegisteredHotKey:[ZGHotKey hotKeyWithKeyCombo:(KeyCombo){.code = keyCode, .flags = modifierFlags}]];
	});
	
	if (!isRegistered)
	{
		Py_RETURN_FALSE;
	}
	
	Py_RETURN_TRUE;
}

static PyObject *Debugger_assemble(DebuggerClass *self, PyObject *args)
{
	PyObject *retValue = NULL;
	ZGMemoryAddress instructionPointer = 0;
	char *codeString = NULL;
	
	if (PyArg_ParseTuple(args, "s|K:assemble", &codeString, &instructionPointer))
	{
		NSString *codeStringValue = @(codeString);
		if (codeStringValue != nil)
		{
			NSError *error = nil;
			NSData *assembledData = [ZGDebuggerUtilities assembleInstructionText:codeStringValue atInstructionPointer:instructionPointer usingArchitectureBits:self->is64Bit ? sizeof(int64_t)*8 : sizeof(int32_t)*8 error:&error];
			
			if (error == nil)
			{
				retValue = Py_BuildValue("y#", assembledData.bytes, assembledData.length);
			}
			else
			{
				PyErr_SetString(PyExc_ValueError, [[NSString stringWithFormat:@"debug.assemble failed to assemble:\n%s", codeString] UTF8String]);
				
				ZGPyDebugger *debugger = self->objcSelf;
				dispatch_async(dispatch_get_main_queue(), ^{
					[debugger->_loggerWindowController writeLine:[[error userInfo] objectForKey:@"reason"]];
					if ([[error userInfo] objectForKey:@"description"] != nil)
					{
						[debugger->_loggerWindowController writeLine:[[error userInfo] objectForKey:@"description"]];
					}
				});
			}
		}
		else
		{
			PyErr_SetString(PyExc_BufferError, "debug.assemble can't parse provided code string");
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
			PyErr_SetString(PyExc_BufferError, "debug.disassemble can't take in non-contiguous or 0-length buffer");
			
			PyBuffer_Release(&buffer);
			return NULL;
		}
		
		ZGDisassemblerObject *disassemblerObject = [[ZGDisassemblerObject alloc] initWithBytes:buffer.buf address:instructionPointer size:(ZGMemorySize)buffer.len pointerSize:self->is64Bit ? sizeof(int64_t) : sizeof(int32_t)];
		
		NSArray<ZGInstruction *> *instructions = [disassemblerObject readInstructions];
		
		NSString *disassembledString = [[instructions zgMapUsingBlock:^(ZGInstruction *instruction) { return instruction.text; }] componentsJoinedByString:@"\n"];
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
		NSData *readData = [ZGDebuggerUtilities readDataWithProcessTask:self->processTask address:address size:size breakPoints:self->objcSelf->_breakPointController.breakPoints];
		if (readData != nil)
		{
			retValue = Py_BuildValue("y#", readData.bytes, readData.length);
		}
		else
		{
			PyErr_SetString(self->virtualMemoryException, [[NSString stringWithFormat:@"debug.readBytes failed to read %llu byte(s) at 0x%llX", size, address] UTF8String]);
			
			NSString *errorMessage = @"Error: Failed to read bytes using debug object";
			ZGPyDebugger *debugger = self->objcSelf;
			dispatch_async(dispatch_get_main_queue(), ^{
				[debugger->_loggerWindowController writeLine:errorMessage];
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
			PyErr_SetString(PyExc_BufferError, "debug.writeBytes can't take in non-contiguous or 0-length buffer");
			
			PyBuffer_Release(&buffer);
			return NULL;
		}
		
		success = [ZGDebuggerUtilities writeData:[NSData dataWithBytes:buffer.buf length:(NSUInteger)buffer.len] atAddress:memoryAddress processTask:self->processTask breakPoints:self->objcSelf->_breakPointController.breakPoints];
		
		if (!success)
		{
			PyErr_SetString(self->virtualMemoryException, [[NSString stringWithFormat:@"debug.writeBytes failed to write %lu byte(s) at 0x%llX", buffer.len, memoryAddress] UTF8String]);
		}
		
		PyBuffer_Release(&buffer);
	}
	
	return success ? Py_BuildValue("") : NULL;
}

static PyObject *Debugger_findSymbol(DebuggerClass *self, PyObject *args)
{
	PyObject *retValue = NULL;
	char *symbolName = NULL;
	char *symbolOwner = NULL;
	if (PyArg_ParseTuple(args, "s|s:findSymbol", &symbolName, &symbolOwner))
	{
		NSString *symbolNameValue = @(symbolName);
		if (symbolNameValue != nil)
		{
			ZGProcess *process = self->objcSelf->_process;
			NSNumber *symbolAddressNumber = [process.symbolicator findSymbol:symbolNameValue withPartialSymbolOwnerName:symbolOwner == NULL ? nil : @(symbolOwner) requiringExactMatch:YES pastAddress:0x0 allowsWrappingToBeginning:NO];
			if (symbolAddressNumber != nil)
			{
				retValue = Py_BuildValue("K", [symbolAddressNumber unsignedLongLongValue]);
			}
			else
			{
				retValue = Py_BuildValue("");
			}
		}
		else
		{
			PyErr_SetString(PyExc_BufferError, "debug.findSymbol can't parse symbol name");
		}
	}
	return retValue;
}

static PyObject *Debugger_symbolAt(DebuggerClass *self, PyObject *args)
{
	PyObject *retValue = NULL;
	ZGMemoryAddress memoryAddress = 0x0;
	if (PyArg_ParseTuple(args, "K:symbolAt", &memoryAddress))
	{
		ZGProcess *process = self->objcSelf->_process;
		ZGMemoryAddress relativeOffset = 0x0;
		NSString *symbol = [process.symbolicator symbolAtAddress:memoryAddress relativeOffset:&relativeOffset];
		if (symbol != nil)
		{
			NSString *symbolWithRelativeOffset = [NSString stringWithFormat:@"%@ + %llu", symbol, relativeOffset];
			retValue = Py_BuildValue("s", [symbolWithRelativeOffset UTF8String]);
		}
		else
		{
			retValue = Py_BuildValue("");
		}
	}
	return retValue;
}

static PyObject *Debugger_bytesBeforeInjection(DebuggerClass *self, PyObject *args)
{
	PyObject *retValue = NULL;
	ZGMemoryAddress sourceAddress = 0x0;
	ZGMemoryAddress destinationAddress = 0x0;
	if (PyArg_ParseTuple(args, "KK:bytesBeforeInjection", &sourceAddress, &destinationAddress))
	{
		NSArray<ZGInstruction *> *instructions = [ZGDebuggerUtilities instructionsBeforeHookingIntoAddress:sourceAddress injectingIntoDestination:destinationAddress inProcess:self->objcSelf->_process withBreakPoints:self->objcSelf->_breakPointController.breakPoints];
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
				memcpy(bufferIterator, instruction.variable.rawValue, instruction.variable.size);
				bufferIterator += instruction.variable.size;
			}
			
			retValue = Py_BuildValue("y#", buffer, bufferLength);
			
			free(buffer);
		}
		else
		{
			PyErr_SetString(self->debuggerException, [[NSString stringWithFormat:@"debug.bytesBeforeInjection failed with source address: 0x%llX, destination address: 0x%llX", sourceAddress, destinationAddress] UTF8String]);
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
			PyErr_SetString(PyExc_BufferError, "debug.injectCode can't take in non-contiguous or 0-length buffer");
			
			PyBuffer_Release(&newCode);
			return NULL;
		}
		
		NSArray<ZGInstruction *> *originalInstructions = [ZGDebuggerUtilities instructionsBeforeHookingIntoAddress:sourceAddress injectingIntoDestination:destinationAddress inProcess:self->objcSelf->_process withBreakPoints:self->objcSelf->_breakPointController.breakPoints];
		
		NSError *error = nil;
		BOOL injectedCode =
		[ZGDebuggerUtilities
		 injectCode:[NSData dataWithBytes:newCode.buf length:(NSUInteger)newCode.len]
		 intoAddress:destinationAddress
		 hookingIntoOriginalInstructions:originalInstructions
		 process:self->objcSelf->_process
		 breakPoints:self->objcSelf->_breakPointController.breakPoints
		 undoManager:nil
		 error:&error];
		
		if (!injectedCode)
		{
			PyErr_SetString(self->debuggerException, [[NSString stringWithFormat:@"debug.injectCode failed with source address: 0x%llx, destination address: 0x%llX", sourceAddress, destinationAddress] UTF8String]);
			
			ZGPyDebugger *debugger = self->objcSelf;
			dispatch_async(dispatch_get_main_queue(), ^{
				[debugger->_loggerWindowController writeLine:[[error userInfo] objectForKey:@"reason"]];
				if ([[error userInfo] objectForKey:@"description"] != nil)
				{
					[debugger->_loggerWindowController writeLine:[[error userInfo] objectForKey:@"description"]];
				}
			});
			
			PyBuffer_Release(&newCode);
			return NULL;
		}
		
		PyBuffer_Release(&newCode);
	}
	return Py_BuildValue("");
}

- (void)dataAccessedByBreakPoint:(ZGBreakPoint *)breakPoint fromInstructionPointer:(ZGMemoryAddress)instructionPointer withRegistersState:(ZGRegistersState *)registersState
{
	ZGMemoryAddress dataAddress = breakPoint.variable.address;
	PyObject *callback = breakPoint.callback;
	ZGScriptManager *scriptManager = _scriptManager;
	
	[_scriptingInterpreter dispatchAsync:^{
		NSNumber *instructionPointerNumber = @(instructionPointer);
		ZGMemoryAddress instructionAddress = 0;
		NSNumber *cachedInstructionAddress = [self->_cachedInstructionPointers objectForKey:instructionPointerNumber];
		if (cachedInstructionAddress == nil)
		{
			ZGInstruction *instruction = [ZGDebuggerUtilities findInstructionBeforeAddress:[instructionPointerNumber unsignedLongLongValue] inProcess:self->_process withBreakPoints:self->_breakPointController.breakPoints machBinaries:[ZGMachBinary machBinariesInProcess:self->_process]];
			
			instructionAddress = instruction.variable.address;
			[self->_cachedInstructionPointers setObject:@(instruction.variable.address) forKey:instructionPointerNumber];
		}
		else
		{
			instructionAddress = [[self->_cachedInstructionPointers objectForKey:instructionPointerNumber] unsignedLongLongValue];
		}
		
		[scriptManager handleDataAddress:dataAddress accessedFromInstructionAddress:instructionAddress registersState:registersState callback:callback sender:self];
	}];
}

static PyObject *watchAccess(DebuggerClass *self, PyObject *args, NSString *functionName, ZGWatchPointType watchPointType)
{
	ZGMemoryAddress memoryAddress = 0;
	ZGMemorySize numberOfBytes = 0;
	PyObject *callback = NULL;
	if (!PyArg_ParseTuple(args, [[NSString stringWithFormat:@"KKO:%@", functionName] UTF8String], &memoryAddress, &numberOfBytes, &callback))
	{
		return NULL;
	}
	
	if (PyCallable_Check(callback) == 0)
	{
		PyErr_SetString(PyExc_ValueError, [[NSString stringWithFormat:@"debug.%@ failed adding watchpoint at 0x%llX (%llu byte(s)) because callback is not callable", functionName, memoryAddress, numberOfBytes] UTF8String]);
		
		return NULL;
	}

	ZGVariable *variable = [[ZGVariable alloc] initWithValue:NULL size:numberOfBytes address:memoryAddress type:ZGByteArray qualifier:0 pointerSize:self->objcSelf->_process.pointerSize];
	
	ZGBreakPoint *breakPoint = nil;
	if (![self->objcSelf->_breakPointController addWatchpointOnVariable:variable inProcess:self->objcSelf->_process watchPointType:watchPointType delegate:self->breakPointDelegate getBreakPoint:&breakPoint])
	{
		PyErr_SetString(self->debuggerException, [[NSString stringWithFormat:@"debug.%@ failed adding watchpoint at 0x%llX (%llu byte(s))", functionName, memoryAddress, numberOfBytes] UTF8String]);
		
		return NULL;
	}
	
	breakPoint.callback = callback;
	
	Py_XINCREF(callback);
	
	return Py_BuildValue("");
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
	ZGMemoryAddress memoryAddress = 0;
	if (!PyArg_ParseTuple(args, "K:removeWatchAccesses", &memoryAddress))
	{
		return NULL;
	}
	
	NSArray<ZGBreakPoint *> *breakPointsRemoved = [self->objcSelf->_breakPointController removeObserver:self->breakPointDelegate withProcessID:self->processIdentifier atAddress:memoryAddress];
	
	for (ZGBreakPoint *breakPoint in breakPointsRemoved)
	{
		if (breakPoint.callback != NULL)
		{
			Py_DecRef(breakPoint.callback);
			breakPoint.callback = NULL;
		}
	}
	
	return Py_BuildValue("");
}

static void resumeFromHaltedBreakPointInDebugger(DebuggerClass *self)
{
	[self->objcSelf->_breakPointController resumeFromBreakPoint:ZGUnwrapNullableObject(self->objcSelf->_haltedBreakPoint)];
	self->objcSelf->_haltedBreakPoint = nil;
}

static void continueFromHaltedBreakPointsInDebugger(DebuggerClass *self)
{
	NSArray<ZGBreakPoint *> *removedBreakPoints = [self->objcSelf->_breakPointController removeSingleStepBreakPointsFromBreakPoint:ZGUnwrapNullableObject(self->objcSelf->_haltedBreakPoint)];
	for (ZGBreakPoint *breakPoint in removedBreakPoints)
	{
		if (breakPoint.callback != NULL)
		{
			Py_DecRef(breakPoint.callback);
			breakPoint.callback = NULL;
		}
	}
	
	resumeFromHaltedBreakPointInDebugger(self);
}

- (void)breakPointDidHit:(ZGBreakPoint *)breakPoint
{
	ZGRegistersState *registersState = breakPoint.registersState;
	ZGMemoryAddress breakPointBasePointer = breakPoint.basePointer;
	BOOL hidden = breakPoint.hidden;
	ZGScriptManager *scriptManager = _scriptManager;
	
	[_scriptingInterpreter dispatchAsync:^{
		self->_haltedBreakPoint = breakPoint;
		
		if (hidden)
		{
			ZGMemoryAddress basePointer = breakPoint.process.is64Bit ? registersState.generalPurposeThreadState.uts.ts64.__rbp : registersState.generalPurposeThreadState.uts.ts32.__ebp;
			
			if (basePointer == breakPointBasePointer)
			{
				[self->_breakPointController removeInstructionBreakPoint:breakPoint];
				
				[scriptManager handleInstructionBreakPoint:breakPoint withRegistersState:registersState callback:breakPoint.callback sender:self];
			}
			else
			{
				continueFromHaltedBreakPointsInDebugger((DebuggerClass *)self->_object);
			}
		}
		else
		{
			[scriptManager handleInstructionBreakPoint:breakPoint withRegistersState:registersState callback:breakPoint.callback sender:self];
		}
	}];
}

static PyObject *Debugger_addBreakpoint(DebuggerClass *self, PyObject *args)
{
	ZGMemoryAddress memoryAddress = 0;
	PyObject *callback = NULL;
	
	if (!PyArg_ParseTuple(args, "KO:addBreakpoint", &memoryAddress, &callback))
	{
		return NULL;
	}
	
	if (PyCallable_Check(callback) == 0)
	{
		PyErr_SetString(PyExc_ValueError, [[NSString stringWithFormat:@"debug.addBreakpoint failed to add breakpoint at: 0x%llX because callback is not callable", memoryAddress] UTF8String]);
		return NULL;
	}
	
	ZGInstruction *instruction = [ZGDebuggerUtilities findInstructionBeforeAddress:memoryAddress + 1 inProcess:self->objcSelf->_process withBreakPoints:self->objcSelf->_breakPointController.breakPoints machBinaries:[ZGMachBinary machBinariesInProcess:self->objcSelf->_process]];
	
	if (instruction == nil)
	{
		PyErr_SetString(self->debuggerException, [[NSString stringWithFormat:@"debug.addBreakpoint failed to find instruction at: 0x%llX", memoryAddress] UTF8String]);
		return NULL;
	}
	
	if (![self->objcSelf->_breakPointController addBreakPointOnInstruction:instruction inProcess:self->objcSelf->_process callback:callback delegate:self->breakPointDelegate])
	{
		PyErr_SetString(self->debuggerException, [[NSString stringWithFormat:@"debug.addBreakpoint failed to add breakpoint at: 0x%llX", memoryAddress] UTF8String]);
		return NULL;
	}
	
	Py_XINCREF(callback);
	
	return Py_BuildValue("");
}

static PyObject *Debugger_removeBreakpoint(DebuggerClass *self, PyObject *args)
{
	ZGMemoryAddress memoryAddress = 0;
	
	if (!PyArg_ParseTuple(args, "K:removeBreakpoint", &memoryAddress))
	{
		return NULL;
	}
	
	ZGInstruction *instruction = [ZGDebuggerUtilities findInstructionBeforeAddress:memoryAddress + 1 inProcess:self->objcSelf->_process withBreakPoints:self->objcSelf->_breakPointController.breakPoints machBinaries:[ZGMachBinary machBinariesInProcess:self->objcSelf->_process]];
	
	if (instruction == nil)
	{
		PyErr_SetString(self->debuggerException, [[NSString stringWithFormat:@"debug.removeBreakpoint failed to find instruction at: 0x%llX", memoryAddress] UTF8String]);
		return NULL;
	}
	
	ZGBreakPoint *breakPoint = [self->objcSelf->_breakPointController removeBreakPointOnInstruction:instruction inProcess:self->objcSelf->_process];
	
	PyObject *callback = breakPoint.callback;
	Py_XDECREF(callback);
	
	return Py_BuildValue("");
}

static void stepIntoDebuggerWithHaltedBreakPointAndCallback(DebuggerClass *self, PyObject *callback)
{
	ZGBreakPoint *singleStepBreakPoint = [self->objcSelf->_breakPointController addSingleStepBreakPointFromBreakPoint:ZGUnwrapNullableObject(self->objcSelf->_haltedBreakPoint)];
	
	singleStepBreakPoint.callback = callback;
	Py_XINCREF(callback);
}

static PyObject *Debugger_stepIn(DebuggerClass *self, PyObject *args)
{
	PyObject *callback = NULL;
	if (!PyArg_ParseTuple(args, "O:stepIn", &callback))
	{
		return NULL;
	}
	
	if (PyCallable_Check(callback) == 0)
	{
		PyErr_SetString(PyExc_ValueError, [@"debug.stepIn failed because callback is not callable" UTF8String]);
		return NULL;
	}
	
	if (self->objcSelf->_haltedBreakPoint == nil)
	{
		PyErr_SetString(self->debuggerException, "debug.stepIn called without a current breakpoint set");
		return NULL;
	}
	
	stepIntoDebuggerWithHaltedBreakPointAndCallback(self, callback);
	resumeFromHaltedBreakPointInDebugger(self);
	
	return Py_BuildValue("");
}

static PyObject *Debugger_stepOver(DebuggerClass *self, PyObject *args)
{
	PyObject *callback = NULL;
	if (!PyArg_ParseTuple(args, "O:stepOver", &callback))
	{
		return NULL;
	}
	
	if (PyCallable_Check(callback) == 0)
	{
		PyErr_SetString(PyExc_ValueError, "debug.stepOver failed because callback is not callable");
		return NULL;
	}
	
	if (self->objcSelf->_haltedBreakPoint == nil)
	{
		PyErr_SetString(self->debuggerException, "debug.stepOver called without a current breakpoint set");
		return NULL;
	}
	
	x86_thread_state_t threadState;
	if (!ZGGetGeneralThreadState(&threadState, self->objcSelf->_haltedBreakPoint.thread, NULL))
	{
		PyErr_SetString(self->debuggerException, "debug.stepOver failed to retrieve current general thread state");
		return NULL;
	}
	
	ZGMemoryAddress instructionPointer = self->is64Bit ? threadState.uts.ts64.__rip : threadState.uts.ts32.__eip;
	
	NSArray<ZGMachBinary *> *machBinaries = [ZGMachBinary machBinariesInProcess:self->objcSelf->_process];
	
	ZGInstruction *currentInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:instructionPointer + 1 inProcess:self->objcSelf->_process withBreakPoints:self->objcSelf->_breakPointController.breakPoints machBinaries:machBinaries];
	
	if (currentInstruction == nil)
	{
		PyErr_SetString(self->debuggerException, [[NSString stringWithFormat:@"debug.stepOver failed to retrieve instruction at 0x%llX", instructionPointer] UTF8String]);
		return NULL;
	}
	
	if ([ZGDisassemblerObject isCallMnemonic:currentInstruction.mnemonic])
	{
		ZGInstruction *nextInstruction = [ZGDebuggerUtilities findInstructionBeforeAddress:currentInstruction.variable.address + currentInstruction.variable.size + 1 inProcess:self->objcSelf->_process withBreakPoints:self->objcSelf->_breakPointController.breakPoints machBinaries:machBinaries];
		
		if (nextInstruction == nil)
		{
			PyErr_SetString(self->debuggerException, [[NSString stringWithFormat:@"debug.stepOver failed to retrieve instruction at 0x%llX", instructionPointer] UTF8String]);
			return NULL;
		}
		
		ZGMemoryAddress basePointer = self->is64Bit ? threadState.uts.ts64.__rbp : threadState.uts.ts32.__ebp;
		
		if (![self->objcSelf->_breakPointController addBreakPointOnInstruction:nextInstruction inProcess:self->objcSelf->_process thread:self->objcSelf->_haltedBreakPoint.thread basePointer:basePointer callback:callback delegate:self->objcSelf])
		{
			PyErr_SetString(self->debuggerException, [[NSString stringWithFormat:@"debug.stepOver failed to set breakpoint at 0x%llX", nextInstruction.variable.address] UTF8String]);
			return NULL;
		}
		
		Py_XINCREF(callback);
		
		continueFromHaltedBreakPointsInDebugger(self);
	}
	else
	{
		stepIntoDebuggerWithHaltedBreakPointAndCallback(self, callback);
		resumeFromHaltedBreakPointInDebugger(self);
	}
	
	return Py_BuildValue("");
}

static PyObject *Debugger_stepOut(DebuggerClass *self, PyObject *args)
{
	PyObject *callback = NULL;
	if (!PyArg_ParseTuple(args, "O:stepOut", &callback))
	{
		return NULL;
	}
	
	if (self->objcSelf->_haltedBreakPoint == nil)
	{
		PyErr_SetString(self->debuggerException, "debug.stepOut called without a current breakpoint set");
		return NULL;
	}
	
	x86_thread_state_t threadState;
	if (!ZGGetGeneralThreadState(&threadState, self->objcSelf->_haltedBreakPoint.thread, NULL))
	{
		PyErr_SetString(self->debuggerException, "debug.stepOut failed to retrieve current general thread state");
		return NULL;
	}
	
	ZGMemoryAddress instructionPointer = self->is64Bit ? threadState.uts.ts64.__rip : threadState.uts.ts32.__eip;
	ZGMemoryAddress basePointer = self->is64Bit ? threadState.uts.ts64.__rbp : threadState.uts.ts32.__ebp;
	
	NSArray<ZGMachBinary *> *machBinaries = [ZGMachBinary machBinariesInProcess:self->objcSelf->_process];
	
	ZGBacktrace *backtrace = [ZGBacktrace backtraceWithBasePointer:basePointer instructionPointer:instructionPointer process:self->objcSelf->_process breakPoints:self->objcSelf->_breakPointController.breakPoints machBinaries:machBinaries maxLimit:2];
	if (backtrace.instructions.count < 2)
	{
		PyErr_SetString(self->debuggerException, "debug.stepOut failed to find available instruction to step out to");
		return NULL;
	}
	
	ZGInstruction *outerInstruction = [backtrace.instructions objectAtIndex:1];
	NSNumber *outerBasePointer = [backtrace.basePointers objectAtIndex:1];

	ZGInstruction *returnInstruction =
	[ZGDebuggerUtilities
	 findInstructionBeforeAddress:outerInstruction.variable.address + outerInstruction.variable.size + 1
	 inProcess:self->objcSelf->_process
	 withBreakPoints:self->objcSelf->_breakPointController.breakPoints
	 machBinaries:machBinaries];

	if (![self->objcSelf->_breakPointController addBreakPointOnInstruction:returnInstruction inProcess:self->objcSelf->_process thread:self->objcSelf->_haltedBreakPoint.thread basePointer:outerBasePointer.unsignedLongLongValue callback:callback delegate:self->objcSelf])
	{
		PyErr_SetString(self->debuggerException, [[NSString stringWithFormat:@"debug.stepOut failed to set breakpoint at 0x%llX", outerInstruction.variable.address] UTF8String]);
		return NULL;
	}
	
	Py_XINCREF(callback);
	
	continueFromHaltedBreakPointsInDebugger(self);
	
	return Py_BuildValue("");
}

static PyObject *Debugger_backtrace(DebuggerClass *self, PyObject * __unused args)
{
	if (self->objcSelf->_haltedBreakPoint == nil)
	{
		PyErr_SetString(self->debuggerException, "debug.backtrace called without a current breakpoint set");
		return NULL;
	}
	
	x86_thread_state_t threadState;
	if (!ZGGetGeneralThreadState(&threadState, self->objcSelf->_haltedBreakPoint.thread, NULL))
	{
		PyErr_SetString(self->debuggerException, "debug.backtrace failed to retrieve current general thread state");
		return NULL;
	}
	
	ZGMemoryAddress instructionPointer = self->is64Bit ? threadState.uts.ts64.__rip : threadState.uts.ts32.__eip;
	ZGMemoryAddress basePointer = self->is64Bit ? threadState.uts.ts64.__rbp : threadState.uts.ts32.__ebp;
	
	ZGBacktrace *backtrace = [ZGBacktrace backtraceWithBasePointer:basePointer instructionPointer:instructionPointer process:self->objcSelf->_process breakPoints:self->objcSelf->_breakPointController.breakPoints machBinaries:[ZGMachBinary machBinariesInProcess:self->objcSelf->_process]];
	
	PyObject *pythonInstructionAddresses = PyList_New((Py_ssize_t)backtrace.instructions.count);
	Py_ssize_t instructionIndex = 0;
	for (ZGInstruction *instruction in backtrace.instructions)
	{
		PyList_SET_ITEM(pythonInstructionAddresses, instructionIndex, Py_BuildValue("K", instruction.variable.address));
		instructionIndex++;
	}
	
	return pythonInstructionAddresses;
}

static PyObject *Debugger_resume(DebuggerClass *self, PyObject * __unused args)
{
	if (self->objcSelf->_haltedBreakPoint == nil)
	{
		PyErr_SetString(self->debuggerException, "debug.resume called without a current breakpoint set");
		return NULL;
	}
	
	continueFromHaltedBreakPointsInDebugger(self);
	
	return Py_BuildValue("");
}

static NSDictionary<NSString *, NSValue *> *registerOffsetsCacheDictionary(ZGRegisterEntry *registerEntries)
{
	NSMutableDictionary<NSString *, NSValue *> *offsetsDictionary = [NSMutableDictionary dictionary];
	for (ZGRegisterEntry *registerEntry = registerEntries; !ZG_REGISTER_ENTRY_IS_NULL(registerEntry); registerEntry++)
	{
		NSString *registerEntryName = @(registerEntry->name);
		if (registerEntryName != nil)
		{
			[offsetsDictionary
			 setObject:[NSValue valueWithBytes:registerEntry objCType:@encode(ZGRegisterEntry)]
			 forKey:registerEntryName];
		}
	}
	
	return [NSDictionary dictionaryWithDictionary:offsetsDictionary];
}

static BOOL writeRegister(NSDictionary<NSString *, NSValue *> *registerOffsetsDictionary, const char *registerString, PyObject *value, void *registerStartPointer, BOOL *wroteValue)
{
	if (wroteValue != NULL) *wroteValue = NO;
	
	NSString *registerStringValue = @(registerString);
	if (registerStringValue == nil)
	{
		return YES;
	}
	
	NSValue *registerValue = registerOffsetsDictionary[registerStringValue];
	if (registerValue == nil)
	{
		return YES;
	}
	
	ZGRegisterEntry registerEntry;
	[registerValue getValue:&registerEntry];
	
	void *registerPointer = (uint8_t *)registerStartPointer + registerEntry.offset;
	
	if (PyByteArray_Check(value))
	{
		memcpy(registerPointer, PyByteArray_AsString(value), MIN((size_t)PyByteArray_Size(value), registerEntry.size));
		if (wroteValue != NULL) *wroteValue = YES;
	}
	else if (PyBytes_Check(value))
	{
		Py_buffer buffer;
		if (PyObject_GetBuffer(value, &buffer, PyBUF_SIMPLE) == 0)
		{
			memcpy(registerPointer, buffer.buf, MIN((size_t)buffer.len, registerEntry.size));
			if (wroteValue != NULL) *wroteValue = YES;
		}
	}
	else if (PyLong_Check(value))
	{
		unsigned PY_LONG_LONG integerValue = PyLong_AsUnsignedLongLongMask(value);
		memcpy(registerPointer, &integerValue, MIN(registerEntry.size, sizeof(PY_LONG_LONG)));
		if (wroteValue != NULL) *wroteValue = YES;
	}
	// it may be ambiguous if the register size is >= 8 bytes
	else if (registerEntry.size >= sizeof(float) && registerEntry.size < sizeof(double) && PyFloat_Check(value))
	{
		float floatValue = (float)PyFloat_AsDouble(value);
		*(float *)registerPointer = floatValue;
		if (wroteValue != NULL) *wroteValue = YES;
	}
	else
	{
		// Unexpected type...
		PyErr_SetString(PyExc_ValueError, [[NSString stringWithFormat:@"debug.writeRegisters encountered an unexpected value type for key %s", registerString] UTF8String]);
		return NO;
	}
	
	return YES;
}

static PyObject *Debugger_writeRegisters(DebuggerClass *self, PyObject *args)
{
	PyObject *registers = NULL;
	if (!PyArg_ParseTuple(args, "O:writeRegisters", &registers))
	{
		return NULL;
	}
	
	if (self->objcSelf->_haltedBreakPoint == nil)
	{
		PyErr_SetString(self->debuggerException, "debug.writeRegisters failed because we are not at a halted breakpoint");
		return NULL;
	}
	
	ZGSuspendTask(self->processTask);
	
	x86_thread_state_t threadState;
	mach_msg_type_number_t threadStateCount;
	if (!ZGGetGeneralThreadState(&threadState, self->objcSelf->_haltedBreakPoint.thread, &threadStateCount))
	{
		PyErr_SetString(self->debuggerException, "debug.writeRegisters failed retrieving target's thread state");
		ZGResumeTask(self->processTask);
		return NULL;
	}
	
	zg_x86_vector_state_t vectorState;
	mach_msg_type_number_t vectorStateCount;
	bool hasAVXSupport = NO;
	BOOL hasVectorRegisters = ZGGetVectorThreadState(&vectorState, self->objcSelf->_haltedBreakPoint.thread, &vectorStateCount, self->is64Bit, &hasAVXSupport);
	
	ZGResumeTask(self->processTask);
	
	if (self->objcSelf->_generalPurposeRegisterOffsetsDictionary == nil)
	{
		ZGRegisterEntry generalPurposeRegisterEntries[ZG_MAX_REGISTER_ENTRIES];
		[ZGRegisterEntries getRegisterEntries:generalPurposeRegisterEntries fromGeneralPurposeThreadState:threadState is64Bit:self->is64Bit];
		
		self->objcSelf->_generalPurposeRegisterOffsetsDictionary = registerOffsetsCacheDictionary(generalPurposeRegisterEntries);
	}
	
	if (hasVectorRegisters && self->objcSelf->_vectorRegisterOffsetsDictionary == nil)
	{
		ZGRegisterEntry vectorRegisterEntries[ZG_MAX_REGISTER_ENTRIES];
		[ZGRegisterEntries getRegisterEntries:vectorRegisterEntries fromVectorThreadState:vectorState is64Bit:self->is64Bit hasAVXSupport:hasAVXSupport];
		
		self->objcSelf->_vectorRegisterOffsetsDictionary = registerOffsetsCacheDictionary(vectorRegisterEntries);
	}
	
	BOOL success = YES;
	
	NSDictionary<NSString *, NSValue *> *generalPurposeRegisterOffsetsDictionary = self->objcSelf->_generalPurposeRegisterOffsetsDictionary;
	NSDictionary<NSString *, NSValue *> *vectorRegisterOffsetsDictionary = self->objcSelf->_vectorRegisterOffsetsDictionary;
	
	BOOL needsToWriteGeneralRegisters = NO;
	BOOL needsToWriteVectorRegisters = NO;
	
	PyObject *key = NULL;
	PyObject *value = NULL;
	Py_ssize_t position = 0;
	
	while (success && PyDict_Next(registers, &position, &key, &value))
	{
		PyObject *asciiRegisterKey = PyUnicode_AsASCIIString(key);
		if (asciiRegisterKey == NULL) continue;
		
		const char *registerString = PyBytes_AsString(asciiRegisterKey);
		if (registerString == NULL)
		{
			Py_XDECREF(asciiRegisterKey);
			continue;
		}
		
		BOOL wroteValue = NO;
		success = writeRegister(generalPurposeRegisterOffsetsDictionary, registerString, value, (uint8_t *)&threadState + sizeof(x86_state_hdr_t), &wroteValue);
		if (wroteValue) needsToWriteGeneralRegisters = YES;
		
		if (success && !wroteValue && hasVectorRegisters)
		{
			success = writeRegister(vectorRegisterOffsetsDictionary, registerString, value, (uint8_t *)&vectorState + sizeof(x86_state_hdr_t), &wroteValue);
			if (wroteValue) needsToWriteVectorRegisters = YES;
		}
		
		Py_XDECREF(asciiRegisterKey);
	}
	
	if (success && needsToWriteGeneralRegisters)
	{
		ZGSuspendTask(self->processTask);
		
		if (!ZGSetGeneralThreadState(&threadState, self->objcSelf->_haltedBreakPoint.thread, threadStateCount))
		{
			PyErr_SetString(self->debuggerException, "debug.writeRegisters failed to write the new thread state");
			success = NO;
		}
		
		ZGResumeTask(self->processTask);
	}
	
	if (success && needsToWriteVectorRegisters)
	{
		ZGSuspendTask(self->processTask);
		
		if (!ZGSetVectorThreadState(&vectorState, self->objcSelf->_haltedBreakPoint.thread, vectorStateCount, self->is64Bit))
		{
			PyErr_SetString(self->debuggerException, "debug.writeRegisters failed to write the new vector state");
			success = NO;
		}
		
		ZGResumeTask(self->processTask);
	}
	
	return success ? Py_BuildValue("") : NULL;
}

@end
