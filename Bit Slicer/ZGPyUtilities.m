//
//  ZGPyUtilities.m
//  Bit Slicer
//
//  Created by Mayur Pawashe on 5/3/14.
//
//

#import "ZGPyUtilities.h"
#import "ZGUtilities.h"

void ZGPyAddModuleToSys(const char *moduleName, PyObject *module)
{
	// PyModule_Create won't add the module to sys.modules like Py_InitModule would in 2.x
	// We have to do that manually
	PyObject *modules = PySys_GetObject("modules");
	if (PyDict_SetItem(modules, PyUnicode_FromString(moduleName), module) != 0)
	{
		NSLog(@"Failed to add %s module to sys.modules!", moduleName);
	}
}

void ZGPyAddIntegerConstant(PyObject *module, const char *name, long value)
{
	if (PyModule_AddIntConstant(module, name, value) == -1)
	{
		ZG_LOG(@"Failed to add %s with value %ld to module %s", name, value, PyModule_GetName(module));
	}
}
