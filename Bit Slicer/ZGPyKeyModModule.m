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

#import "ZGPyKeyModModule.h"
#import "ZGPyModuleAdditions.h"
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

#define KEYMOD_MODULE_NAME "keymod"

static struct PyModuleDef keyModModuleDefinition =
{
	PyModuleDef_HEAD_INIT,
	KEYMOD_MODULE_NAME,
	"Key Mod Module",
	-1,
	NULL,
	NULL, NULL, NULL, NULL
};

static void addKeyMods(PyObject *keyModModule)
{
	ZGPyAddIntegerConstant(keyModModule, "NONE", 0x0);
	ZGPyAddIntegerConstant(keyModModule, "SHIFT", shiftKey);
	ZGPyAddIntegerConstant(keyModModule, "COMMAND", cmdKey);
	ZGPyAddIntegerConstant(keyModModule, "ALPHA_LOCK", alphaLock);
	ZGPyAddIntegerConstant(keyModModule, "OPTION", optionKey);
	ZGPyAddIntegerConstant(keyModModule, "CONTROL", controlKey);
	
	// shortcut recorder uses this modifier for carbon flags, so we may as well provide it too
	ZGPyAddIntegerConstant(keyModModule, "FUNCTION", NSFunctionKeyMask);
}

PyObject *loadKeyModPythonModule(void)
{
	PyObject *keyModModule = PyModule_Create(&keyModModuleDefinition);
	ZGPyAddModuleToSys(KEYMOD_MODULE_NAME, keyModModule);
	
	addKeyMods(keyModModule);
	
	return keyModModule;
}
