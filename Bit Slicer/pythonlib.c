//
//  pythonlib.c
//  Bit Slicer
//
//  Created by Mayur Pawashe on 8/2/20.
//

#include "pythonlib.h"

PyObject *PyImport_AddModule(const char * __unused module)
{
	return NULL;
}

PyObject *PyImport_Import(PyObject * __unused object)
{
	return NULL;
}

PyObject *PyImport_ReloadModule(PyObject * __unused object)
{
	return NULL;
}

int PyArg_ParseTuple(PyObject * __unused obj, const char * __unused format, ...)
{
	return 0;
}

PyObject *PySys_GetObject(const char * __unused name)
{
	return NULL;
}

PyObject* PyUnicode_FromString(const char * __unused u)
{
	return NULL;
}

int PyDict_SetItem(PyObject * __unused mp, PyObject * __unused key, PyObject * __unused item)
{
	return 0;
}

int PyModule_AddIntConstant(PyObject * __unused obj, const char * __unused name, long __unused data)
{
	return 0;
}

const char * PyModule_GetName(PyObject * __unused obj)
{
	return "";
}

PyObject *PyModule_Create(void * __unused def)
{
	return NULL;
}

int Py_IsInitialized(void)
{
	return 1;
}

void Py_XDECREF(void * __unused object)
{
}

int PyList_Append(PyObject *__unused sysPath, PyObject * __unused newPath)
{
	return 0;
}

void Py_Initialize(void)
{
}

PyObject *PyImport_ImportModule(const char * __unused name)
{
	return NULL;
}

PyObject *PyObject_Str(PyObject * __unused pythonObject)
{
	return NULL;
}

PyObject *PyUnicode_AsUTF8String(PyObject * __unused pythonString)
{
	return NULL;
}

char *PyBytes_AsString(PyObject * __unused obj)
{
	return "";
}

void PyErr_Fetch(PyObject ** __unused a, PyObject ** __unused b, PyObject ** __unused c)
{
}

void PyErr_Clear(void)
{
}

PyObject *Py_CompileString(const char * __unused str, char * __unused str2, int __unused input)
{
	return NULL;
}

PyObject *PyDict_New(void)
{
	return NULL;
}

PyObject *Py_BuildValue(const char * __unused format, ...)
{
	return NULL;
}

void PyObject_SetAttrString(PyObject * __unused obj, char * __unused name, PyObject * __unused obj2)
{
}

int PyObject_IsTrue(PyObject * __unused obj)
{
	return 0;
}

PyObject *PyModule_GetDict(PyObject *__unused obj)
{
	return NULL;
}

void PyDict_SetItemString(PyObject * __unused dict, char *__unused name, PyObject *__unused obj2)
{
}

PyObject *PyEval_EvalCode(PyObject * __unused obj1, PyObject *__unused obj2, PyObject *__unused obj3)
{
	return NULL;
}

void Py_DecRef(PyObject *__unused obj)
{
}

int PyType_Ready(PyTypeObject * __unused typeObject)
{
	return 0;
}

void Py_INCREF(void * __unused object)
{
	
}

int PyModule_AddObject(PyObject * __unused module, const char *__unused name, PyObject * __unused obj)
{
	return 0;
}

PyObject *PyErr_NewException(const char * __unused name, void * __unused unused, void * __unused unused2)
{
	return NULL;
}

void PyErr_SetString(PyObject *__unused object, const char *__unused string)
{
	
}

int PyBuffer_IsContiguous(Py_buffer * __unused buffer, char __unused format)
{
	return 0;
}

void PyBuffer_Release(Py_buffer *__unused buffer)
{
	
}

PyObject *PyUnicode_Decode(void *__unused bytes, Py_ssize_t __unused numberBytes, char *__unused encoding, void *__unused unused)
{
	return NULL;
}

PyObject *PyList_New(Py_ssize_t __unused size)
{
	return NULL;
}

void PyList_SET_ITEM(PyObject *__unused list, Py_ssize_t __unused index, PyObject *__unused value)
{
	
}

int PyCallable_Check(PyObject *__unused callback)
{
	return 0;
}

void Py_XINCREF(PyObject *__unused object)
{
	
}

PyObject *PyBool_FromLong(long __unused value)
{
	return NULL;
}

PyObject *PyFile_FromFd(int __unused fileno, void *__unused data, const char *__unused format, int __unused data2, void *__unused data3, void *__unused data4, void *__unused data5, int __unused flag)
{
	return NULL;
}

void PyTraceBack_Print(PyObject *__unused traceback, PyObject *__unused file)
{
	
}

PyObject *PyObject_CallFunction(PyObject *__unused callback, const char *__unused format, ...)
{
	return NULL;
}

PyObject *PyObject_GetAttrString(PyObject *__unused obj, const char *__unused name)
{
	return NULL;
}

PyObject *PyObject_CallMethod(PyObject *__unused obj, const char *__unused name, void * __unused unused)
{
	return NULL;
}

int PyObject_HasAttrString(PyObject *__unused obj, const char *__unused name)
{
	return 0;
}

void PyErr_SetInterrupt(void)
{
	
}

int PyByteArray_Check(PyObject *__unused obj)
{
	return 0;
}

int PyBytes_Check(PyObject *__unused obj)
{
	return 0;
}

int PyLong_Check(PyObject *__unused obj)
{
	return 0;
}

int PyFloat_Check(PyObject *__unused obj)
{
	return 0;
}

float PyFloat_AsDouble(PyObject *__unused obj)
{
	return 0.0f;
}

void *PyByteArray_AsString(PyObject *__unused obj)
{
	return NULL;
}

Py_ssize_t PyByteArray_Size(PyObject *__unused obj)
{
	return 0;
}

int PyDict_Next(PyObject *__unused dict, Py_ssize_t __unused *position, PyObject **__unused key, PyObject **__unused value)
{
	return 0;
}

PyObject *PyUnicode_AsASCIIString(PyObject *__unused obj)
{
	return NULL;
}

int PyObject_GetBuffer(PyObject *__unused value, Py_buffer *__unused buffer, int __unused flag)
{
	return 0;
}

unsigned long long PyLong_AsUnsignedLongLongMask(PyObject *__unused obj)
{
	return 0;
}
