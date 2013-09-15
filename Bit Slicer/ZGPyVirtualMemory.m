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
#import "ZGVirtualMemoryHelpers.h"
#import "ZGUtilities.h"
#import "ZGSearchData.h"
#import "ZGSearchFunctions.h"
#import "ZGSearchResults.h"
#import "ZGSearchProgress.h"
#import <Python/structmember.h>

typedef struct
{
	PyObject_HEAD
	uint32_t processTask;
	int32_t processIdentifier;
	char is64Bit;
	__unsafe_unretained NSMutableArray *objectsPool;
	__unsafe_unretained NSMutableDictionary *allocationSizeTable;
} VirtualMemory;

static PyMemberDef VirtualMemory_members[] =
{
	{"pid", T_INT, offsetof(VirtualMemory, processIdentifier), 0, "process identifier"},
	{"is64Bit", T_BOOL, offsetof(VirtualMemory, is64Bit), 0, "is process 64-bit"},
	{NULL, 0, 0, 0, NULL}
};

#define declareVMPrototypeMethod(name) static PyObject *VirtualMemory_##name(VirtualMemory *self, PyObject *args);

declareVMPrototypeMethod(readInt8)
declareVMPrototypeMethod(readUInt8)
declareVMPrototypeMethod(readInt16)
declareVMPrototypeMethod(readUInt16)
declareVMPrototypeMethod(readInt32)
declareVMPrototypeMethod(readUInt32)
declareVMPrototypeMethod(readInt64)
declareVMPrototypeMethod(readUInt64)
declareVMPrototypeMethod(readFloat)
declareVMPrototypeMethod(readDouble)
declareVMPrototypeMethod(readString8)
declareVMPrototypeMethod(readString16)
declareVMPrototypeMethod(readBytes)

declareVMPrototypeMethod(writeInt8)
declareVMPrototypeMethod(writeUInt8)
declareVMPrototypeMethod(writeInt16)
declareVMPrototypeMethod(writeUInt16)
declareVMPrototypeMethod(writeInt32)
declareVMPrototypeMethod(writeUInt32)
declareVMPrototypeMethod(writeInt64)
declareVMPrototypeMethod(writeUInt64)
declareVMPrototypeMethod(writeFloat)
declareVMPrototypeMethod(writeDouble)
declareVMPrototypeMethod(writeString8)
declareVMPrototypeMethod(writeString16)
declareVMPrototypeMethod(writeBytes)

declareVMPrototypeMethod(pause)
declareVMPrototypeMethod(unpause)

declareVMPrototypeMethod(scanBytes)
declareVMPrototypeMethod(scanByteString)

declareVMPrototypeMethod(allocate)
declareVMPrototypeMethod(deallocate)

#define declareVMMethod2(name, argsType) {#name"", (PyCFunction)VirtualMemory_##name, argsType, NULL},
#define declareVMMethod(name) declareVMMethod2(name, METH_VARARGS)

static PyMethodDef VirtualMemory_methods[] =
{
	declareVMMethod(readInt8)
	declareVMMethod(readUInt8)
	declareVMMethod(readInt16)
	declareVMMethod(readUInt16)
	declareVMMethod(readInt32)
	declareVMMethod(readUInt32)
	declareVMMethod(readInt64)
	declareVMMethod(readUInt64)
	declareVMMethod(readFloat)
	declareVMMethod(readDouble)
	declareVMMethod(readString8)
	declareVMMethod(readString16)
	declareVMMethod(readBytes)

	declareVMMethod(writeInt8)
	declareVMMethod(writeUInt8)
	declareVMMethod(writeInt16)
	declareVMMethod(writeUInt16)
	declareVMMethod(writeInt32)
	declareVMMethod(writeUInt32)
	declareVMMethod(writeInt64)
	declareVMMethod(writeUInt64)
	declareVMMethod(writeFloat)
	declareVMMethod(writeDouble)
	declareVMMethod(writeString8)
	declareVMMethod(writeString16)
	declareVMMethod(writeBytes)
	
	declareVMMethod2(pause, METH_NOARGS)
	declareVMMethod2(unpause, METH_NOARGS)
	
	declareVMMethod(allocate)
	declareVMMethod(deallocate)
	
	declareVMMethod(scanBytes)
	declareVMMethod(scanByteString)
	{NULL, NULL, 0, NULL}
};

static PyTypeObject VirtualMemoryType =
{
	PyObject_HEAD_INIT(NULL)
	0, // ob_size
	"bitslicer.VirtualMemory", // tp_name
	sizeof(VirtualMemory), // tp_basicsize
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
	"VirtualMemory objects", // tp_doc
	0, // tp_traverse
	0, // tp_clear
	0, // tp_richcompare
	0, // tp_weaklistoffset
	0, // tp_iter
	0, // tp_iternext
	VirtualMemory_methods, // tp_methods
	VirtualMemory_members, // tp_members
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

@implementation ZGPyVirtualMemory

+ (void)loadPythonClassInMainModule:(PyObject *)module
{	
	VirtualMemoryType.tp_new = PyType_GenericNew;
	if (PyType_Ready(&VirtualMemoryType) >= 0)
	{
		Py_INCREF(&VirtualMemoryType);
		
		PyModule_AddObject(module, "VirtualMemory", (PyObject *)&VirtualMemoryType);
	}
	else
	{
		NSLog(@"Error: VirtualMemoryType was not ready!");
	}
}

- (id)initWithProcessTask:(ZGMemoryMap)processTask is64Bit:(BOOL)is64Bit objectsPool:(NSMutableArray *)objectsPool
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
		VirtualMemory *vmObject = (VirtualMemory *)self.vmObject;
		vmObject->processTask = processTask;
		vmObject->processIdentifier = 0;
		if (!ZGPIDForTaskPort(processTask, &(vmObject->processIdentifier)))
		{
			NSLog(@"Script Error: Failed to access PID for process task");
			return nil;
		}
		vmObject->is64Bit = is64Bit;
		NSMutableDictionary *allocationSizeTable = [[NSMutableDictionary alloc] init];
		vmObject->allocationSizeTable = allocationSizeTable;
		@synchronized(objectsPool)
		{
			[objectsPool addObject:allocationSizeTable];
		}
		vmObject->objectsPool = objectsPool;
	}
	return self;
}

- (void)setVmObject:(PyObject *)vmObject
{
	if (Py_IsInitialized())
	{
		Py_XDECREF(_vmObject);
	}
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
	if (PyArg_ParseTuple(args, "K:"#functionName, &memoryAddress)) \
	{ \
		void *bytes = NULL; \
		ZGMemorySize size = sizeof(type); \
		if (ZGReadBytes(self->processTask, memoryAddress, &bytes, &size)) \
		{ \
			retValue =  Py_BuildValue(typeFormat, *(type *)bytes); \
			ZGFreeBytes(self->processTask, bytes, size); \
		} \
	} \
	return retValue; \
}

VirtualMemory_read(int8_t, "b", readInt8)
VirtualMemory_read(uint8_t, "B", readUInt8)
VirtualMemory_read(int16_t, "h", readInt16)
VirtualMemory_read(uint16_t, "H", readUInt16)
VirtualMemory_read(int32_t, "i", readInt32)
VirtualMemory_read(uint32_t, "I", readUInt32)
VirtualMemory_read(int64_t, "L", readInt64)
VirtualMemory_read(uint64_t, "K", readUInt64)
VirtualMemory_read(float, "f", readFloat)
VirtualMemory_read(double, "d", readDouble)

static void readBytes(PyObject **retValue, VirtualMemory *self, ZGMemoryAddress memoryAddress, ZGMemorySize *numberOfBytes)
{
	void *bytes = NULL;
	if (ZGReadBytes(self->processTask, memoryAddress, &bytes, numberOfBytes))
	{
		*retValue = Py_BuildValue("s#", bytes, *numberOfBytes);
		ZGFreeBytes(self->processTask, bytes, *numberOfBytes);
	}
}

static PyObject *VirtualMemory_readBytes(VirtualMemory *self, PyObject *args)
{
	PyObject *retValue = NULL;
	ZGMemoryAddress memoryAddress = 0x0;
	ZGMemorySize numberOfBytes = 0;
	if (PyArg_ParseTuple(args, "KK:readBytes", &memoryAddress, &numberOfBytes))
	{
		readBytes(&retValue, self, memoryAddress, &numberOfBytes);
	}
	return retValue;
}

static PyObject *VirtualMemory_readString(VirtualMemory *self, PyObject *args, ZGVariableType variableType, const char *functionName)
{
	PyObject *retValue = NULL;
	ZGMemoryAddress memoryAddress = 0x0;
	if (PyArg_ParseTuple(args, [[NSString stringWithFormat:@"K:%s", functionName] UTF8String], &memoryAddress))
	{
		ZGMemorySize numberOfBytes = ZGGetStringSize(self->processTask, memoryAddress, variableType, 0, 0);
		if (numberOfBytes == 0)
		{
			retValue = PyString_FromString("");
		}
		else
		{
			readBytes(&retValue, self, memoryAddress, &numberOfBytes);
		}
	}
	return retValue;
}

static PyObject *VirtualMemory_readString8(VirtualMemory *self, PyObject *args)
{
	return VirtualMemory_readString(self, args, ZGString8, "readString8");
}

static PyObject *VirtualMemory_readString16(VirtualMemory *self, PyObject *args)
{
	return VirtualMemory_readString(self, args, ZGString16, "readString16");
}

#define VirtualMemory_write(type, typeFormat, functionName) \
static PyObject *VirtualMemory_##functionName(VirtualMemory *self, PyObject *args) \
{ \
	ZGMemoryAddress memoryAddress = 0x0; \
	type value = 0; \
	if (PyArg_ParseTuple(args, "K"typeFormat":"#functionName, &memoryAddress, &value)) \
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
VirtualMemory_write(uint8_t, "B", writeUInt8)
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
	if (PyArg_ParseTuple(args, "Ks*:writeBytes", &memoryAddress, &buffer))
	{
		if (!PyBuffer_IsContiguous(&buffer, 'C'))
		{
			PyBuffer_Release(&buffer);
			return NULL;
		}
		
		if (buffer.len > 0 && !ZGWriteBytesIgnoringProtection(self->processTask, memoryAddress, buffer.buf, buffer.len))
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

static PyObject *writeString(VirtualMemory *self, PyObject *args, void *nullBuffer, size_t nullSize, const char *functionName)
{
	ZGMemoryAddress memoryAddress = 0x0;
	Py_buffer buffer;
	if (PyArg_ParseTuple(args, [[NSString stringWithFormat:@"Ks*:%s", functionName] UTF8String], &memoryAddress, &buffer))
	{
		if (!PyBuffer_IsContiguous(&buffer, 'C'))
		{
			PyBuffer_Release(&buffer);
			return NULL;
		}
		
		if (buffer.len > 0)
		{
			if (!ZGWriteBytesIgnoringProtection(self->processTask, memoryAddress, buffer.buf, buffer.len) || !ZGWriteBytesIgnoringProtection(self->processTask, memoryAddress+buffer.len, nullBuffer, nullSize))
			{
				PyBuffer_Release(&buffer);
				return NULL;
			}
		}
		
		PyBuffer_Release(&buffer);
	}
	else
	{
		return NULL;
	}
	return Py_BuildValue("");
}

static PyObject *VirtualMemory_writeString8(VirtualMemory *self, PyObject *args)
{
	int8_t nullByte = 0;
	return writeString(self, args, &nullByte, sizeof(nullByte), "writeString8");
}

static PyObject *VirtualMemory_writeString16(VirtualMemory *self, PyObject *args)
{
	int16_t nullByte = 0;
	return writeString(self, args, &nullByte, sizeof(nullByte), "writeString16");
}

static PyObject *VirtualMemory_pause(VirtualMemory *self, PyObject *args)
{
	if (!ZGSuspendTask(self->processTask))
	{
		return NULL;
	}
	return Py_BuildValue("");
}

static PyObject *VirtualMemory_unpause(VirtualMemory *self, PyObject *args)
{
	if (!ZGResumeTask(self->processTask))
	{
		return NULL;
	}
	return Py_BuildValue("");
}

#define MAX_VALUES_SCANNED 1000

static PyObject *scanSearchData(VirtualMemory *self, ZGSearchData *searchData)
{
	PyObject *retValue = NULL;
	if (searchData.dataSize > 0)
	{
		ZGSearchProgress *searchProgress = [[ZGSearchProgress alloc] init];
		
		@synchronized(self->objectsPool)
		{
			[self->objectsPool addObject:searchProgress];
		}
		
		ZGSearchResults *results = ZGSearchForData(self->processTask, searchData, searchProgress, ZGByteArray, 0, ZGEquals);
		
		@synchronized(self->objectsPool)
		{
			[self->objectsPool removeObject:searchProgress];
		}
		
		Py_ssize_t numberOfEntries = MIN(MAX_VALUES_SCANNED, (Py_ssize_t)results.addressCount);
		PyObject *pythonResults = PyList_New(numberOfEntries);
		__block Py_ssize_t addressIndex = 0;
		[results enumerateWithCount:numberOfEntries usingBlock:^(ZGMemoryAddress address, BOOL *stop) {
			PyList_SET_ITEM(pythonResults, addressIndex, Py_BuildValue("K", address));
			addressIndex++;
		}];
		retValue = pythonResults;
	}
	return retValue;
}

static PyObject *VirtualMemory_scanByteString(VirtualMemory *self, PyObject *args)
{
	PyObject *retValue = NULL;
	char *byteArrayString = NULL;
	
	if (PyArg_ParseTuple(args, "s:scanByteString", &byteArrayString))
	{
		ZGMemorySize dataSize = 0;
		void *searchValue = ZGValueFromString(self->is64Bit, @(byteArrayString), ZGByteArray, &dataSize);
		
		ZGSearchData *searchData =
		[[ZGSearchData alloc]
		 initWithSearchValue:searchValue
		 dataSize:dataSize
		 dataAlignment:ZGDataAlignment(self->is64Bit, ZGByteArray, dataSize)
		 pointerSize:self->is64Bit ? sizeof(int64_t) : sizeof(int32_t)];
		
		searchData.byteArrayFlags = ZGAllocateFlagsForByteArrayWildcards(@(byteArrayString));
		searchData.shouldUseBoyerMoore = ZGCanUseBoyerMoore(ZGByteArray, ZGEquals, searchData);
		
		retValue = scanSearchData(self, searchData);
	}
	
	return retValue;
}

static PyObject *VirtualMemory_scanBytes(VirtualMemory *self, PyObject *args)
{
	PyObject *retValue = NULL;
	Py_buffer buffer;
	if (PyArg_ParseTuple(args, "s*:scanBytes", &buffer))
	{
		if (!PyBuffer_IsContiguous(&buffer, 'C') || buffer.len <= 0)
		{
			PyBuffer_Release(&buffer);
			return NULL;
		}
		
		void *data = malloc(buffer.len);
		memcpy(data, buffer.buf, buffer.len);
		
		ZGSearchData *searchData =
		[[ZGSearchData alloc]
		 initWithSearchValue:data
		 dataSize:buffer.len
		 dataAlignment:ZGDataAlignment(self->is64Bit, ZGByteArray, buffer.len)
		 pointerSize:self->is64Bit ? sizeof(int64_t) : sizeof(int32_t)];
		searchData.shouldUseBoyerMoore = YES;
		
		retValue = scanSearchData(self, searchData);
		
		PyBuffer_Release(&buffer);
	}
	return retValue;
}

static PyObject *VirtualMemory_allocate(VirtualMemory *self, PyObject *args)
{
	PyObject *retValue = NULL;
	ZGMemorySize numberOfBytes = NSPageSize(); // sane default
	ZGPageSize(self->processTask, &numberOfBytes);
	if (PyArg_ParseTuple(args, "|K:allocate", &numberOfBytes))
	{
		ZGMemoryAddress memoryAddress = 0;
		if (ZGAllocateMemory(self->processTask, &memoryAddress, numberOfBytes))
		{
			[self->allocationSizeTable setObject:@(numberOfBytes) forKey:[NSNumber numberWithUnsignedLongLong:memoryAddress]];
			retValue = Py_BuildValue("K", memoryAddress);
		}
	}
	return retValue;
}

static PyObject *VirtualMemory_deallocate(VirtualMemory *self, PyObject *args)
{
	PyObject *retValue = NULL;
	ZGMemoryAddress memoryAddress = 0;
	if (PyArg_ParseTuple(args, "K:deallocate", &memoryAddress))
	{
		NSNumber *bytesNumber = [self->allocationSizeTable objectForKey:[NSNumber numberWithUnsignedLongLong:memoryAddress]];
		if (bytesNumber != nil)
		{
			ZGMemorySize numberOfBytes = [bytesNumber unsignedLongLongValue];
			if (ZGDeallocateMemory(self->processTask, memoryAddress, numberOfBytes))
			{
				retValue = Py_BuildValue("");
				[self->allocationSizeTable removeObjectForKey:[NSNumber numberWithUnsignedLongLong:memoryAddress]];
			}
		}
	}
	return retValue;
}

@end
