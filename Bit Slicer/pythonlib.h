//
//  pythonlib.h
//  Bit Slicer
//
//  Created by Mayur Pawashe on 8/2/20.
//

#ifndef pythonlib_h
#define pythonlib_h

#include <stdlib.h>

#define PyModuleDef_HEAD_INIT "python"

#define PyObject_HEAD

typedef struct
{
	char *name;
	int _type;
	size_t offset;
	int data;
	char *description;
} PyMemberDef;

#define T_INT 0
#define T_BOOL 1

//static PyObject *VirtualMemory_readBytes(VirtualMemory *self, PyObject *args)

typedef struct
{
	int unused;
} PyObject;

typedef PyObject* (*PyCFunction)(PyObject *obj1, PyObject *obj2);

struct PyModuleDef
{
	char *data1;
	char *data2;
	char *data3;
	int data5;
	void *data6;
	void *data7;
	void *data8;
	void *data9;
	void *data10;
};

typedef ssize_t Py_ssize_t;

#define METH_VARARGS 2
#define METH_NOARGS 3

typedef struct
{
	char *name;
	PyCFunction func;
	int data;
	void *ptr;
} PyMethodDef;

#define Py_TPFLAGS_DEFAULT 4

typedef struct _PyTypeObject
{
	char *name; // tp_name
	size_t size; // tp_basicsize
	int data1; // tp_itemsize
	int data2; // tp_dealloc
	int data3; // tp_print
	int data4; // tp_getattr
	int data5; // tp_setattr
	int data6; // tp_compare
	int data7; // tp_repr
	int data8; // tp_as_number
	int data9; // tp_as_sequence
	int data10; // tp_as_mapping
	int data11; // tp_hash
	int data12; // tp_call
	int data13; // tp_str
	int data14; // tp_getattro
	int data15; // tp_setattro
	int data16; // tp_as_buffer
	int data17; // tp_flags
	char *method; // tp_doc
	int data18; // tp_traverse
	int data19; // tp_clear
	int data20; // tp_richcompare
	int data21; // tp_weaklistoffset
	int data22; // tp_iter
	int data23; // tp_iternext
	PyMethodDef *methods; // tp_methods
	PyMemberDef *members; // tp_members
	int data24; // tp_getset
	int data25; // tp_base
	int data26; // tp_dict
	int data27; // tp_descr_get
	int data28; // tp_descr_set
	int data29; // tp_dictoffset
	int data30; // tp_init
	void* (*tp_alloc)(struct _PyTypeObject *typeObj, int arg); // tp_alloc
	int tp_new; // tp_new
	int data33; int data34; int data35;int data36; int data37; int data38; int data39; int data40; int data41; int data42; // the rest
} PyTypeObject;

typedef struct
{
	char *buf;
	unsigned long len;
} Py_buffer;

#define PY_LONG_LONG long long

#define PyExc_BufferError NULL

#define PyType_GenericNew 0

#define PyVarObject_HEAD_INIT(data, data2)

PyObject *PyImport_AddModule(const char *module);
PyObject *PyImport_Import(PyObject *object);
PyObject *PyImport_ReloadModule(PyObject *object);

int PyArg_ParseTuple(PyObject *obj, const char *format, ...);

PyObject *PySys_GetObject(const char *name);
PyObject* PyUnicode_FromString(const char *u);

int PyDict_SetItem(PyObject *mp, PyObject *key, PyObject *item);

int PyModule_AddIntConstant(PyObject *obj, const char *name, long data);

const char * PyModule_GetName(PyObject *obj);

PyObject *PyModule_Create(void *def);

int Py_IsInitialized(void);

void Py_XDECREF(void *object);

int PyList_Append(PyObject *sysPath, PyObject *newPath);

void Py_Initialize(void);

PyObject *PyImport_ImportModule(const char *name);

PyObject *PyObject_Str(PyObject *pythonObject);
PyObject *PyUnicode_AsUTF8String(PyObject *pythonString);
char *PyBytes_AsString(PyObject *obj);

void PyErr_Fetch(PyObject **a, PyObject **b, PyObject **c);
void PyErr_Clear(void);

#define Py_eval_input 32

#define PyExc_ValueError NULL

#define Py_RETURN_FALSE NULL
#define Py_RETURN_TRUE NULL

#define Py_None NULL

#define PyBUF_SIMPLE 0

PyObject *Py_CompileString(const char *str, char *str2, int input);

PyObject *PyDict_New(void);

PyObject *Py_BuildValue(const char *format, ...);

void PyObject_SetAttrString(PyObject *obj, char *name, PyObject *obj2);

int PyObject_IsTrue(PyObject *obj);

PyObject *PyModule_GetDict(PyObject *obj);

void PyDict_SetItemString(PyObject *dict, char *name, PyObject *obj2);

PyObject *PyEval_EvalCode(PyObject * obj1, PyObject *obj2, PyObject *obj3);

void Py_DecRef(PyObject *obj);

int PyType_Ready(PyTypeObject *typeObject);

void Py_INCREF(void *object);

int PyModule_AddObject(PyObject *module, const char *name, PyObject *obj);

PyObject *PyErr_NewException(const char *name, void *unused, void *unused2);

void PyErr_SetString(PyObject *object, const char *string);

int PyBuffer_IsContiguous(Py_buffer *buffer, char format);

void PyBuffer_Release(Py_buffer *buffer);

PyObject *PyUnicode_Decode(void *bytes, Py_ssize_t numberBytes, char *encoding, void *unused);

PyObject *PyList_New(Py_ssize_t size);

void PyList_SET_ITEM(PyObject *list, Py_ssize_t index, PyObject *value);

int PyCallable_Check(PyObject *callback);

void Py_XINCREF(PyObject *object);

PyObject *PyBool_FromLong(long value);

PyObject *PyFile_FromFd(int fileno, void *data, const char *format, int data2, void *data3, void *data4, void *data5, int flag);

void PyTraceBack_Print(PyObject *traceback, PyObject *file);

PyObject *PyObject_CallFunction(PyObject *callback, const char *format, ...);

PyObject *PyObject_GetAttrString(PyObject *obj, const char *name);

PyObject *PyObject_CallMethod(PyObject *obj, const char *name, void *unused);

int PyObject_HasAttrString(PyObject *obj, const char *name);

void PyErr_SetInterrupt(void);

int PyByteArray_Check(PyObject *obj);
int PyBytes_Check(PyObject *obj);
int PyLong_Check(PyObject *obj);
int PyFloat_Check(PyObject *obj);

float PyFloat_AsDouble(PyObject *obj);

void *PyByteArray_AsString(PyObject *obj);

Py_ssize_t PyByteArray_Size(PyObject *obj);

int PyDict_Next(PyObject *dict, Py_ssize_t *position, PyObject **key, PyObject **value);

PyObject *PyUnicode_AsASCIIString(PyObject *obj);

int PyObject_GetBuffer(PyObject *value, Py_buffer *buffer, int flag);

unsigned long long PyLong_AsUnsignedLongLongMask(PyObject *obj);

#endif /* pythonlib_h */
