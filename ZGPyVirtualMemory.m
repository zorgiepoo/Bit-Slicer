/*
 * Created by Mayur Pawashe on 8/26/13.
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

#import "ZGPyVirtualMemory.h"
#import "ZGVirtualMemory.h"
#import <Python/structmember.h>

typedef struct
{
	PyObject_HEAD
	unsigned int processTask;
} VirtualMemory;

static PyMemberDef VirtualMemory_members[] =
{
	{"processTask", T_UINT, offsetof(VirtualMemory, processTask), 0, "process task"},
	{NULL, 0, 0, 0, NULL}
};

static PyObject *VirtualMemory_readInt16(VirtualMemory *self, PyObject *args);
static PyObject *VirtualMemory_readFloat(VirtualMemory *self, PyObject *args);
static PyObject *VirtualMemory_writeFloat(VirtualMemory *self, PyObject *args);

static PyMethodDef VirtualMemory_methods[] =
{
	{"readInt16", (PyCFunction)VirtualMemory_readInt16, METH_VARARGS, NULL},
	{"readFloat", (PyCFunction)VirtualMemory_readFloat, METH_VARARGS, NULL},
	{"writeFloat", (PyCFunction)VirtualMemory_writeFloat, METH_VARARGS, NULL},
	{NULL, NULL, 0, NULL}
};

static PyTypeObject VirtualMemoryType =
{
	PyObject_HEAD_INIT(NULL)
	0,                         /*ob_size*/
	"virtualmemory.VirtualMemory", /*tp_name*/
	sizeof(VirtualMemory), /*tp_basicsize*/
	0,                         /*tp_itemsize*/
	0,                         /*tp_dealloc*/
	0,                         /*tp_print*/
	0,                         /*tp_getattr*/
	0,                         /*tp_setattr*/
	0,                         /*tp_compare*/
	0,                         /*tp_repr*/
	0,                         /*tp_as_number*/
	0,                         /*tp_as_sequence*/
	0,                         /*tp_as_mapping*/
	0,                         /*tp_hash */
	0,                         /*tp_call*/
	0,                         /*tp_str*/
	0,                         /*tp_getattro*/
	0,                         /*tp_setattro*/
	0,                         /*tp_as_buffer*/
	Py_TPFLAGS_DEFAULT, /*tp_flags*/
	"VirtualMemory objects", /* tp_doc */
	0,		               /* tp_traverse */
	0,		               /* tp_clear */
	0,		               /* tp_richcompare */
	0,		               /* tp_weaklistoffset */
	0,		               /* tp_iter */
	0,		               /* tp_iternext */
	VirtualMemory_methods, /* tp_methods */
	VirtualMemory_members, /* tp_members */
	0,                         /* tp_getset */
	0,                         /* tp_base */
	0,                         /* tp_dict */
	0,                         /* tp_descr_get */
	0,                         /* tp_descr_set */
	0,                         /* tp_dictoffset */
	0,      /* tp_init */
	0,                         /* tp_alloc */
	0,                 /* tp_new */
	0, 0, 0, 0, 0, 0, 0, 0, 0 /* the rest */
};

@implementation ZGPyVirtualMemory

static PyObject *virtualMemoryModule;
+ (void)loadModule
{
	static PyMethodDef moduleMethods[] =
	{
		{NULL, NULL, 0, NULL}
	};
	
	VirtualMemoryType.tp_new = PyType_GenericNew;
	if (PyType_Ready(&VirtualMemoryType) >= 0)
	{
		Py_INCREF(&VirtualMemoryType);
		
		virtualMemoryModule = Py_InitModule("virtualmemory", moduleMethods);
		PyModule_AddObject(virtualMemoryModule, "VirtualMemory", (PyObject *)&VirtualMemoryType);
	}
	else
	{
		NSLog(@"Error: VirtualMemoryType was not ready!");
	}
}

- (id)initWithProcessTask:(ZGMemoryMap)processTask
{
	self = [super init];
	if (self != nil)
	{
		PyTypeObject *type = &VirtualMemoryType;
		self.vmObject = (PyObject *)((VirtualMemory *)type->tp_alloc(type, 0));
		if (self.vmObject == NULL)
		{
			return nil;
		}
		((VirtualMemory *)self.vmObject)->processTask = processTask;
	}
	return self;
}

- (void)setVmObject:(PyObject *)vmObject
{
	Py_XDECREF(_vmObject);
	_vmObject = vmObject;
}

- (void)dealloc
{
	self.vmObject = NULL;
}

static PyObject *VirtualMemory_readInt16(VirtualMemory *self, PyObject *args)
{
	PyObject *retValue = NULL;
	
	ZGMemoryAddress memoryAddress = 0x0;
	if (PyArg_ParseTuple(args, "K", &memoryAddress))
	{
		void *bytes = NULL;
		ZGMemorySize size = sizeof(int16_t);
		if (ZGReadBytes(self->processTask, memoryAddress, &bytes, &size))
		{
			retValue =  Py_BuildValue("i", *(int16_t *)bytes);
			ZGFreeBytes(self->processTask, bytes, size);
		}
	}
	
	return retValue;
}

static PyObject *VirtualMemory_readFloat(VirtualMemory *self, PyObject *args)
{
	PyObject *retValue = NULL;
	
	ZGMemoryAddress memoryAddress = 0x0;
	if (PyArg_ParseTuple(args, "K", &memoryAddress))
	{
		void *bytes = NULL;
		ZGMemorySize size = sizeof(float);
		if (ZGReadBytes(self->processTask, memoryAddress, &bytes, &size))
		{
			retValue =  Py_BuildValue("f", *(float *)bytes);
			ZGFreeBytes(self->processTask, bytes, size);
		}
	}
	
	return retValue;
}

static PyObject *VirtualMemory_writeFloat(VirtualMemory *self, PyObject *args)
{
	ZGMemoryAddress memoryAddress = 0x0;
	float value = 0;
	if (PyArg_ParseTuple(args, "Kf", &memoryAddress, &value))
	{
		ZGWriteBytesIgnoringProtection(self->processTask, memoryAddress, &value, sizeof(float));
	}
	return Py_BuildValue("");
}

@end
