/*
 * Copyright (c) 2014 Mayur Pawashe
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

#import "ZGPyVMProtModule.h"
#import "ZGPyModuleAdditions.h"
#import "ZGVirtualMemory.h"

#define VMPROT_MODULE_NAME "vmprot"

static struct PyModuleDef vmProtModuleDefinition =
{
	PyModuleDef_HEAD_INIT,
	VMPROT_MODULE_NAME,
	"Virtual Memory Protection Module",
	-1,
	NULL,
	NULL, NULL, NULL, NULL
};

PyObject *loadVMProtPythonModule(void)
{
	PyObject *vmProtModule = PyModule_Create(&vmProtModuleDefinition);
	ZGPyAddModuleToSys(VMPROT_MODULE_NAME, vmProtModule);
	
	ZGPyAddIntegerConstant(vmProtModule, "NONE", VM_PROT_NONE);
	ZGPyAddIntegerConstant(vmProtModule, "READ", VM_PROT_READ);
	ZGPyAddIntegerConstant(vmProtModule, "WRITE", VM_PROT_WRITE);
	ZGPyAddIntegerConstant(vmProtModule, "EXECUTE", VM_PROT_EXECUTE);
	ZGPyAddIntegerConstant(vmProtModule, "ALL", VM_PROT_ALL);
	
	return vmProtModule;
}
