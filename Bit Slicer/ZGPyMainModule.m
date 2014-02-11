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

#define MAIN_MODULE_NAME "bitslicer"

static PyObject *BitSlicer_reload(PyObject *self, PyObject *args);

static PyMethodDef mainModuleMethods[] =
{
	{"reload", (PyCFunction)BitSlicer_reload, METH_VARARGS, NULL}
};

static struct PyModuleDef mainModuleDefinition =
{
	PyModuleDef_HEAD_INIT,
	MAIN_MODULE_NAME,
	"Main Bit Slicer Module",
	-1,
	mainModuleMethods,
	NULL, NULL, NULL, NULL
};

PyObject *loadMainPythonModule(PyObject *sysModule)
{
	PyObject *mainModule = PyModule_Create(&mainModuleDefinition);
	
	// PyModule_Create won't add the module to sys.modules like Py_InitModule would in 2.x
	// We have to do that manually
	PyObject *modules = PyObject_GetAttrString(sysModule, "modules");
	if (PyDict_SetItem(modules, PyUnicode_FromString(MAIN_MODULE_NAME), mainModule) != 0)
	{
		NSLog(@"Failed to add "MAIN_MODULE_NAME" module to sys.modules!");
	}
	Py_XDECREF(modules);
	
	return mainModule;
}

// The API provided in 3.3 for reloading modules is deprecated, so rather than waiting for 3.4, we should provide our own
static PyObject *BitSlicer_reload(PyObject *self, PyObject *args)
{
	PyObject *moduleName = NULL;
	if (!PyArg_ParseTuple(args, "O:reload", &moduleName))
	{
		return NULL;
	}
	
	PyObject *module = PyImport_Import(moduleName);
	if (module == NULL)
	{
		return NULL;
	}
	
	PyObject *reloadedModule = PyImport_ReloadModule(module);
	if (reloadedModule == NULL)
	{
		return NULL;
	}
	
	return reloadedModule;
}
