//
//  ZGPyUtilities.h
//  Bit Slicer
//
//  Created by Mayur Pawashe on 5/3/14.
//
//

#import "Python.h"

void ZGPyAddModuleToSys(const char *moduleName, PyObject *module);
void ZGPyAddIntegerConstant(PyObject *module, const char *name, long value);
