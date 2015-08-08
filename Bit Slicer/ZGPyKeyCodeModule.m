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

#import "ZGPyKeyCodeModule.h"
#import <Carbon/Carbon.h>
#import "ZGPyModuleAdditions.h"

#define KEYCODE_MODULE_NAME "keycode"

static struct PyModuleDef keyCodeModuleDefinition =
{
	PyModuleDef_HEAD_INIT,
	KEYCODE_MODULE_NAME,
	"Key Code Module",
	-1,
	NULL,
	NULL, NULL, NULL, NULL
};

static void addKeyCodes(PyObject *keyCodeModule)
{
	ZGPyAddIntegerConstant(keyCodeModule, "A", kVK_ANSI_A);
	ZGPyAddIntegerConstant(keyCodeModule, "S", kVK_ANSI_S);
	ZGPyAddIntegerConstant(keyCodeModule, "D", kVK_ANSI_D);
	ZGPyAddIntegerConstant(keyCodeModule, "F", kVK_ANSI_F);
	ZGPyAddIntegerConstant(keyCodeModule, "H", kVK_ANSI_H);
	ZGPyAddIntegerConstant(keyCodeModule, "G", kVK_ANSI_G);
	ZGPyAddIntegerConstant(keyCodeModule, "Z", kVK_ANSI_Z);
	ZGPyAddIntegerConstant(keyCodeModule, "X", kVK_ANSI_X);
	ZGPyAddIntegerConstant(keyCodeModule, "C", kVK_ANSI_C);
	ZGPyAddIntegerConstant(keyCodeModule, "V", kVK_ANSI_V);
	ZGPyAddIntegerConstant(keyCodeModule, "B", kVK_ANSI_B);
	ZGPyAddIntegerConstant(keyCodeModule, "Q", kVK_ANSI_Q);
	ZGPyAddIntegerConstant(keyCodeModule, "W", kVK_ANSI_W);
	ZGPyAddIntegerConstant(keyCodeModule, "E", kVK_ANSI_E);
	ZGPyAddIntegerConstant(keyCodeModule, "R", kVK_ANSI_R);
	ZGPyAddIntegerConstant(keyCodeModule, "Y", kVK_ANSI_Y);
	ZGPyAddIntegerConstant(keyCodeModule, "T", kVK_ANSI_T);
	ZGPyAddIntegerConstant(keyCodeModule, "NUM1", kVK_ANSI_1);
	ZGPyAddIntegerConstant(keyCodeModule, "NUM2", kVK_ANSI_2);
	ZGPyAddIntegerConstant(keyCodeModule, "NUM3", kVK_ANSI_3);
	ZGPyAddIntegerConstant(keyCodeModule, "NUM4", kVK_ANSI_4);
	ZGPyAddIntegerConstant(keyCodeModule, "NUM6", kVK_ANSI_6);
	ZGPyAddIntegerConstant(keyCodeModule, "NUM5", kVK_ANSI_5);
	ZGPyAddIntegerConstant(keyCodeModule, "EQUAL", kVK_ANSI_Equal);
	ZGPyAddIntegerConstant(keyCodeModule, "NUM9", kVK_ANSI_9);
	ZGPyAddIntegerConstant(keyCodeModule, "NUM7", kVK_ANSI_7);
	ZGPyAddIntegerConstant(keyCodeModule, "MINUS", kVK_ANSI_Minus);
	ZGPyAddIntegerConstant(keyCodeModule, "NUM8", kVK_ANSI_8);
	ZGPyAddIntegerConstant(keyCodeModule, "NUM0", kVK_ANSI_0);
	ZGPyAddIntegerConstant(keyCodeModule, "RIGHT_BRACKET", kVK_ANSI_RightBracket);
	ZGPyAddIntegerConstant(keyCodeModule, "O", kVK_ANSI_O);
	ZGPyAddIntegerConstant(keyCodeModule, "U", kVK_ANSI_U);
	ZGPyAddIntegerConstant(keyCodeModule, "LEFT_BRACKET", kVK_ANSI_LeftBracket);
	ZGPyAddIntegerConstant(keyCodeModule, "I", kVK_ANSI_I);
	ZGPyAddIntegerConstant(keyCodeModule, "P", kVK_ANSI_P);
	ZGPyAddIntegerConstant(keyCodeModule, "L", kVK_ANSI_L);
	ZGPyAddIntegerConstant(keyCodeModule, "J", kVK_ANSI_J);
	ZGPyAddIntegerConstant(keyCodeModule, "QUOTE", kVK_ANSI_Quote);
	ZGPyAddIntegerConstant(keyCodeModule, "K", kVK_ANSI_K);
	ZGPyAddIntegerConstant(keyCodeModule, "SEMICOLON", kVK_ANSI_Semicolon);
	ZGPyAddIntegerConstant(keyCodeModule, "BACKSLASH", kVK_ANSI_Backslash);
	ZGPyAddIntegerConstant(keyCodeModule, "COMMA", kVK_ANSI_Comma);
	ZGPyAddIntegerConstant(keyCodeModule, "SLASH", kVK_ANSI_Slash);
	ZGPyAddIntegerConstant(keyCodeModule, "N", kVK_ANSI_N);
	ZGPyAddIntegerConstant(keyCodeModule, "M", kVK_ANSI_M);
	ZGPyAddIntegerConstant(keyCodeModule, "PERIOD", kVK_ANSI_Period);
	ZGPyAddIntegerConstant(keyCodeModule, "GRAVE", kVK_ANSI_Grave);
	ZGPyAddIntegerConstant(keyCodeModule, "KEYPAD_DECIMAL", kVK_ANSI_KeypadDecimal);
	ZGPyAddIntegerConstant(keyCodeModule, "KEYPAD_MULTIPLY", kVK_ANSI_KeypadMultiply);
	ZGPyAddIntegerConstant(keyCodeModule, "KEYPAD_PLUS", kVK_ANSI_KeypadPlus);
	ZGPyAddIntegerConstant(keyCodeModule, "KEYPAD_CLEAR", kVK_ANSI_KeypadClear);
	ZGPyAddIntegerConstant(keyCodeModule, "KEYPAD_DIVIDE", kVK_ANSI_KeypadDivide);
	ZGPyAddIntegerConstant(keyCodeModule, "KETPAD_ENTER", kVK_ANSI_KeypadEnter);
	ZGPyAddIntegerConstant(keyCodeModule, "KEYPAD_MINUS", kVK_ANSI_KeypadMinus);
	ZGPyAddIntegerConstant(keyCodeModule, "KEYPAD_EQUALS", kVK_ANSI_KeypadEquals);
	ZGPyAddIntegerConstant(keyCodeModule, "KEYPAD0", kVK_ANSI_Keypad0);
	ZGPyAddIntegerConstant(keyCodeModule, "KEYPAD1", kVK_ANSI_Keypad1);
	ZGPyAddIntegerConstant(keyCodeModule, "KEYPAD2", kVK_ANSI_Keypad2);
	ZGPyAddIntegerConstant(keyCodeModule, "KEYPAD3", kVK_ANSI_Keypad3);
	ZGPyAddIntegerConstant(keyCodeModule, "KEYPAD4", kVK_ANSI_Keypad4);
	ZGPyAddIntegerConstant(keyCodeModule, "KEYPAD5", kVK_ANSI_Keypad5);
	ZGPyAddIntegerConstant(keyCodeModule, "KEYPAD6", kVK_ANSI_Keypad6);
	ZGPyAddIntegerConstant(keyCodeModule, "KEYPAD7", kVK_ANSI_Keypad7);
	ZGPyAddIntegerConstant(keyCodeModule, "KEYPAD8", kVK_ANSI_Keypad8);
	ZGPyAddIntegerConstant(keyCodeModule, "KEYPAD9", kVK_ANSI_Keypad9);
	
	ZGPyAddIntegerConstant(keyCodeModule, "RETURN", kVK_Return);
	ZGPyAddIntegerConstant(keyCodeModule, "TAB", kVK_Tab);
	ZGPyAddIntegerConstant(keyCodeModule, "SPACE", kVK_Space);
	ZGPyAddIntegerConstant(keyCodeModule, "DELETE", kVK_Delete);
	ZGPyAddIntegerConstant(keyCodeModule, "ESCAPE", kVK_Escape);
	ZGPyAddIntegerConstant(keyCodeModule, "COMMAND", kVK_Command);
	ZGPyAddIntegerConstant(keyCodeModule, "SHIFT", kVK_Shift);
	ZGPyAddIntegerConstant(keyCodeModule, "CAPS_LOCK", kVK_CapsLock);
	ZGPyAddIntegerConstant(keyCodeModule, "OPTION", kVK_Option);
	ZGPyAddIntegerConstant(keyCodeModule, "CONTROL", kVK_Control);
	ZGPyAddIntegerConstant(keyCodeModule, "RIGHT_SHIFT", kVK_RightShift);
	ZGPyAddIntegerConstant(keyCodeModule, "RIGHT_OPTION", kVK_RightOption);
	ZGPyAddIntegerConstant(keyCodeModule, "RIGHT_CONTROL", kVK_RightControl);
	ZGPyAddIntegerConstant(keyCodeModule, "FUNCTION", kVK_Function);
	ZGPyAddIntegerConstant(keyCodeModule, "F17", kVK_F17);
	ZGPyAddIntegerConstant(keyCodeModule, "VOLUME_UP", kVK_VolumeUp);
	ZGPyAddIntegerConstant(keyCodeModule, "VOLUME_DOWN", kVK_VolumeDown);
	ZGPyAddIntegerConstant(keyCodeModule, "MUTE", kVK_Mute);
	ZGPyAddIntegerConstant(keyCodeModule, "F18", kVK_F18);
	ZGPyAddIntegerConstant(keyCodeModule, "F19", kVK_F19);
	ZGPyAddIntegerConstant(keyCodeModule, "F20", kVK_F20);
	ZGPyAddIntegerConstant(keyCodeModule, "F5", kVK_F5);
	ZGPyAddIntegerConstant(keyCodeModule, "F6", kVK_F6);
	ZGPyAddIntegerConstant(keyCodeModule, "F7", kVK_F7);
	ZGPyAddIntegerConstant(keyCodeModule, "F3", kVK_F3);
	ZGPyAddIntegerConstant(keyCodeModule, "F8", kVK_F8);
	ZGPyAddIntegerConstant(keyCodeModule, "F9", kVK_F9);
	ZGPyAddIntegerConstant(keyCodeModule, "F11", kVK_F11);
	ZGPyAddIntegerConstant(keyCodeModule, "F13", kVK_F13);
	ZGPyAddIntegerConstant(keyCodeModule, "F16", kVK_F16);
	ZGPyAddIntegerConstant(keyCodeModule, "F14", kVK_F14);
	ZGPyAddIntegerConstant(keyCodeModule, "F10", kVK_F10);
	ZGPyAddIntegerConstant(keyCodeModule, "F12", kVK_F12);
	ZGPyAddIntegerConstant(keyCodeModule, "F15", kVK_F15);
	ZGPyAddIntegerConstant(keyCodeModule, "HELP", kVK_Help);
	ZGPyAddIntegerConstant(keyCodeModule, "HOME", kVK_Home);
	ZGPyAddIntegerConstant(keyCodeModule, "PAGE_UP", kVK_PageUp);
	ZGPyAddIntegerConstant(keyCodeModule, "FORWARD_DELETE", kVK_ForwardDelete);
	ZGPyAddIntegerConstant(keyCodeModule, "F4", kVK_F4);
	ZGPyAddIntegerConstant(keyCodeModule, "END", kVK_End);
	ZGPyAddIntegerConstant(keyCodeModule, "F2", kVK_F2);
	ZGPyAddIntegerConstant(keyCodeModule, "PAGE_DOWN", kVK_PageDown);
	ZGPyAddIntegerConstant(keyCodeModule, "F1", kVK_F1);
	ZGPyAddIntegerConstant(keyCodeModule, "LEFT_ARROW", kVK_LeftArrow);
	ZGPyAddIntegerConstant(keyCodeModule, "RIGHT_ARROW", kVK_RightArrow);
	ZGPyAddIntegerConstant(keyCodeModule, "DOWN_ARROW", kVK_DownArrow);
	ZGPyAddIntegerConstant(keyCodeModule, "UP_ARROW", kVK_UpArrow);
}

PyObject *loadKeyCodePythonModule(void)
{
	PyObject *keyCodeModule = PyModule_Create(&keyCodeModuleDefinition);
	ZGPyAddModuleToSys(KEYCODE_MODULE_NAME, keyCodeModule);
	
	addKeyCodes(keyCodeModule);
	
	return keyCodeModule;
}
