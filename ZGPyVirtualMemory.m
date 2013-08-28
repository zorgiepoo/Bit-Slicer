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

#define declarePrototypeMethod(name) static PyObject *VirtualMemory_##name(VirtualMemory *self, PyObject *args);

declarePrototypeMethod(readInt8)
declarePrototypeMethod(readUInt8)
declarePrototypeMethod(readInt16)
declarePrototypeMethod(readUInt16)
declarePrototypeMethod(readInt32)
declarePrototypeMethod(readUInt32)
declarePrototypeMethod(readInt64)
declarePrototypeMethod(readUInt64)
declarePrototypeMethod(readFloat)
declarePrototypeMethod(readDouble)
declarePrototypeMethod(readBytes)

declarePrototypeMethod(writeInt8)
declarePrototypeMethod(writeUInt8)
declarePrototypeMethod(writeInt16)
declarePrototypeMethod(writeUInt16)
declarePrototypeMethod(writeInt32)
declarePrototypeMethod(writeUInt32)
declarePrototypeMethod(writeInt64)
declarePrototypeMethod(writeUInt64)
declarePrototypeMethod(writeFloat)
declarePrototypeMethod(writeDouble)
declarePrototypeMethod(writeBytes)

static PyObject *VirtualMemory_writeFloat(VirtualMemory *self, PyObject *args);

#define declareMethod(name) {#name"", (PyCFunction)VirtualMemory_##name, METH_VARARGS, NULL},

static PyMethodDef VirtualMemory_methods[] =
{
	declareMethod(readInt8)
	declareMethod(readUInt8)
	declareMethod(readInt16)
	declareMethod(readUInt16)
	declareMethod(readInt32)
	declareMethod(readUInt32)
	declareMethod(readInt64)
	declareMethod(readUInt64)
	declareMethod(readFloat)
	declareMethod(readDouble)
	declareMethod(readBytes)

	declareMethod(writeInt8)
	declareMethod(writeUInt8)
	declareMethod(writeInt16)
	declareMethod(writeUInt16)
	declareMethod(writeInt32)
	declareMethod(writeUInt32)
	declareMethod(writeInt64)
	declareMethod(writeUInt64)
	declareMethod(writeFloat)
	declareMethod(writeDouble)
	declareMethod(writeBytes)
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

#define VirtualMemory_read(type, typeFormat, functionName) \
static PyObject *VirtualMemory_##functionName(VirtualMemory *self, PyObject *args) \
{ \
	PyObject *retValue = NULL; \
	ZGMemoryAddress memoryAddress = 0x0; \
	if (PyArg_ParseTuple(args, "K", &memoryAddress)) \
	{ \
		void *bytes = NULL; \
		ZGMemorySize size = sizeof(type); \
		if (ZGReadBytes(self->processTask, memoryAddress, &bytes, &size)) \
		{ \
			retValue =  Py_BuildValue(typeFormat, *(type *)bytes); \
			ZGFreeBytes(self->processTask, bytes, size); \
		} \
	} \
	else \
	{ \
		return NULL; \
	} \
	return retValue; \
}

VirtualMemory_read(int8_t, "b", readInt8)
VirtualMemory_read(int8_t, "B", readUInt8)
VirtualMemory_read(int16_t, "h", readInt16)
VirtualMemory_read(uint16_t, "H", readUInt16)
VirtualMemory_read(int32_t, "i", readInt32)
VirtualMemory_read(uint32_t, "I", readUInt32)
VirtualMemory_read(int64_t, "L", readInt64)
VirtualMemory_read(uint64_t, "K", readUInt64)
VirtualMemory_read(float, "f", readFloat)
VirtualMemory_read(double, "d", readDouble)

static PyObject *VirtualMemory_readBytes(VirtualMemory *self, PyObject *args)
{
	PyObject *retValue = NULL;
	ZGMemoryAddress memoryAddress = 0x0;
	ZGMemorySize numberOfBytesToRead = 0;
	if (PyArg_ParseTuple(args, "KK", &memoryAddress, &numberOfBytesToRead))
	{
		void *bytes = NULL;
		if (ZGReadBytes(self->processTask, memoryAddress, &bytes, &numberOfBytesToRead))
		{
			retValue =  Py_BuildValue("s#", bytes, numberOfBytesToRead);
			ZGFreeBytes(self->processTask, bytes, numberOfBytesToRead);
		}
	}
	else
	{
		return NULL;
	}
	return retValue;
}

#define VirtualMemory_write(type, typeFormat, functionName) \
static PyObject *VirtualMemory_##functionName(VirtualMemory *self, PyObject *args) \
{ \
	ZGMemoryAddress memoryAddress = 0x0; \
	type value = 0; \
	if (PyArg_ParseTuple(args, "K"typeFormat, &memoryAddress, &value)) \
	{ \
		if (!ZGWriteBytesIgnoringProtection(self->processTask, memoryAddress, &value, sizeof(type))) \
		{ \
			return NULL; \
		} \
	} \
	else \
	{ \
		return NULL; \
	} \
	return Py_BuildValue("i", 1); \
}

VirtualMemory_write(int8_t, "b", writeInt8)
VirtualMemory_write(int8_t, "B", writeUInt8)
VirtualMemory_write(int16_t, "h", writeInt16)
VirtualMemory_write(uint16_t, "H", writeUInt16)
VirtualMemory_write(int32_t, "i", writeInt32)
VirtualMemory_write(uint32_t, "I", writeUInt32)
VirtualMemory_write(int64_t, "L", writeInt64)
VirtualMemory_write(uint64_t, "K", writeUInt64)
VirtualMemory_write(float, "f", writeFloat)
VirtualMemory_write(double, "d", writeDouble)

static PyObject *VirtualMemory_writeBytes(VirtualMemory *self, PyObject *args)
{
	ZGMemoryAddress memoryAddress = 0x0;
	Py_buffer buffer;
	if (PyArg_ParseTuple(args, "Ks*", &memoryAddress, &buffer))
	{
		if (!PyBuffer_IsContiguous(&buffer, 'C') || !ZGWriteBytesIgnoringProtection(self->processTask, memoryAddress, buffer.buf, buffer.len))
		{
			PyBuffer_Release(&buffer);
			return NULL;
		}
		PyBuffer_Release(&buffer);
	}
	else
	{
		return NULL;
	}
	return Py_BuildValue("");
}

@end
