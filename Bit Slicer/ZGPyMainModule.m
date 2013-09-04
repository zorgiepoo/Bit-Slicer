/*
 * Created by Mayur Pawashe on 9/2/13.
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

#import "ZGPyMainModule.h"
#import <Foundation/Foundation.h>
#import "ZGAppController.h"
#import "ZGLoggerWindowController.h"
#import "ZGVariable.h"

static PyObject *Main_writeLog(PyObject *self, PyObject *args);

static PyMethodDef moduleMethods[] =
{
	{"writeLog", (PyCFunction)Main_writeLog, METH_VARARGS, NULL},
	{NULL, NULL, NULL, NULL}
};

PyObject *loadMainPythonModule(void)
{
	return Py_InitModule("bitslicer", moduleMethods);
}

static PyObject *Main_writeLog(PyObject *self, PyObject *args)
{
	PyObject *objectToLog;
	if (!PyArg_ParseTuple(args, "O", &objectToLog))
	{
		return NULL;
	}
	
	PyObject *objectToLogString = PyObject_Str(objectToLog);
	
	char *stringToLog = PyString_AsString(objectToLogString);
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
	
	Py_XDECREF(objectToLogString);
	
	dispatch_async(dispatch_get_main_queue(), ^{
		[[[ZGAppController sharedController] loggerController] writeLine:objcStringToLog];
	});
	
	return Py_BuildValue("");
}
