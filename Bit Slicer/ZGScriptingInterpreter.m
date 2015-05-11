/*
 * Created by Mayur Pawashe on 5/10/15.
 *
 * Copyright (c) 2015 zgcoder
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

#import "ZGScriptingInterpreter.h"
#import "ZGProcess.h"
#import "ZGRegistersState.h"
#import "ZGAppPathUtilities.h"
#import "ZGPyMainModule.h"
#import "ZGPyVirtualMemory.h"
#import "ZGPyDebugger.h"
#import "ZGPyKeyCodeModule.h"
#import "ZGPyKeyModModule.h"
#import "ZGPyVMProtModule.h"

#import "structmember.h"

@implementation ZGScriptingInterpreter
{
	PyObject *_cTypesObject;
	PyObject *_structObject;
}

+ (instancetype)sharedInterpreter
{
	static ZGScriptingInterpreter *scriptingInterpreter;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		scriptingInterpreter = [[[self class] alloc] init];
	});
	return scriptingInterpreter;
}

- (id)init
{
	self = [super init];
	if (self != nil)
	{
		NSFileManager *fileManager = [[NSFileManager alloc] init];
		
		if (![fileManager fileExistsAtPath:SCRIPT_CACHES_PATH])
		{
			[fileManager createDirectoryAtPath:SCRIPT_CACHES_PATH withIntermediateDirectories:YES attributes:nil error:nil];
		}
		
		NSMutableArray *filePathsToRemove = [NSMutableArray array];
		NSDirectoryEnumerator *directoryEnumerator = [fileManager enumeratorAtPath:SCRIPT_CACHES_PATH];
		for (NSString *filename in directoryEnumerator)
		{
			if ([filename hasPrefix:SCRIPT_FILENAME_PREFIX] && [[filename pathExtension] isEqualToString:@"py"])
			{
				NSDictionary *fileAttributes = [fileManager attributesOfItemAtPath:[SCRIPT_CACHES_PATH stringByAppendingPathComponent:filename] error:nil];
				if (fileAttributes != nil)
				{
					NSDate *lastModificationDate = [fileAttributes objectForKey:NSFileModificationDate];
					if ([[NSDate date] timeIntervalSinceDate:lastModificationDate] > 864000) // 10 days
					{
						[filePathsToRemove addObject:[SCRIPT_CACHES_PATH stringByAppendingPathComponent:filename]];
					}
				}
			}
			[directoryEnumerator skipDescendants];
		}
		
		for (NSString *filename in filePathsToRemove)
		{
			[fileManager removeItemAtPath:filename error:nil];
		}
		
		[self initializePythonInterpreter];
	}
	return self;
}

- (void)appendPath:(NSString *)path toSysPath:(PyObject *)sysPath
{
	if (path == nil) return;
	
	PyObject *newPath = PyUnicode_FromString([path UTF8String]);
	if (PyList_Append(sysPath, newPath) != 0)
	{
		NSLog(@"Error on appending %@", path);
	}
	Py_XDECREF(newPath);
}

- (void)initializePythonInterpreter
{
	_pythonQueue = dispatch_queue_create(NULL, DISPATCH_QUEUE_SERIAL);
	
	setenv("PYTHONDONTWRITEBYTECODE", "1", 1);
	
	NSString *userModulesDirectory = [ZGAppPathUtilities createUserModulesDirectory];
	
	NSString *pythonDirectory = [[NSBundle mainBundle] pathForResource:@"python3.3" ofType:nil];
	setenv("PYTHONHOME", [pythonDirectory UTF8String], 1);
	setenv("PYTHONPATH", [pythonDirectory UTF8String], 1);
	dispatch_async(_pythonQueue, ^{
		Py_Initialize();
		PyObject *path = PySys_GetObject("path");
		
		[self appendPath:[pythonDirectory stringByAppendingPathComponent:@"lib-dynload"] toSysPath:path];
		[self appendPath:SCRIPT_CACHES_PATH toSysPath:path];
		[self appendPath:userModulesDirectory toSysPath:path];
		
		PyObject *mainModule = loadMainPythonModule();
		if (mainModule != NULL)
		{
			[ZGPyVirtualMemory loadPythonClassInMainModule:mainModule];
			[ZGPyDebugger loadPythonClassInMainModule:mainModule];
		}
		else
		{
			NSLog(@"Error: Main Module could not be loaded");
			NSLog(@"Error Message: %@", [self fetchPythonErrorDescriptionWithoutDescriptiveTraceback]);
		}
		
		loadKeyCodePythonModule();
		loadKeyModPythonModule();
		loadVMProtPythonModule();
		
		self->_cTypesObject = PyImport_ImportModule("ctypes");
		self->_structObject = PyImport_ImportModule("struct");
	});
}

- (NSString *)fetchPythonErrorDescriptionFromObject:(PyObject *)pythonObject
{
	NSString *description = @"";
	if (pythonObject != NULL)
	{
		PyObject *pythonString = PyObject_Str(pythonObject);
		PyObject *unicodeString = PyUnicode_AsUTF8String(pythonString);
		const char *pythonCString = PyBytes_AsString(unicodeString);
		if (pythonCString != NULL)
		{
			description = @(pythonCString);
		}
		
		Py_XDECREF(unicodeString);
		Py_XDECREF(pythonString);
	}
	
	Py_XDECREF(pythonObject);
	
	return description;
}

- (NSString *)fetchPythonErrorDescriptionWithoutDescriptiveTraceback
{
	PyObject *type, *value, *traceback;
	PyErr_Fetch(&type, &value, &traceback);
	
	NSArray *errorDescriptionComponents = @[[self fetchPythonErrorDescriptionFromObject:type], [self fetchPythonErrorDescriptionFromObject:value], [self fetchPythonErrorDescriptionFromObject:traceback]];
	
	PyErr_Clear();
	
	return [errorDescriptionComponents componentsJoinedByString:@"\n"];
}

- (PyObject *)compiledExpressionFromExpression:(NSString *)expression error:(NSError * __autoreleasing *)error
{
	__block PyObject *compiledExpression = NULL;
	
	dispatch_sync(_pythonQueue, ^{
		compiledExpression = Py_CompileString([expression UTF8String], "EvaluateCondition", Py_eval_input);
		
		if (compiledExpression == NULL)
		{
			NSString *pythonErrorDescription = [self fetchPythonErrorDescriptionWithoutDescriptiveTraceback];
			if (error != NULL)
			{
				*error = [NSError errorWithDomain:@"CompileConditionFailure" code:2 userInfo:@{SCRIPT_PYTHON_ERROR : pythonErrorDescription}];
			}
		}
	});
	
	return compiledExpression;
}

static PyObject *convertRegisterEntriesToPyDict(ZGRegisterEntry *registerEntries, BOOL is64Bit)
{
	PyObject *dictionary = PyDict_New();
	
	for (ZGRegisterEntry *registerEntry = registerEntries; !ZG_REGISTER_ENTRY_IS_NULL(registerEntry); registerEntry++)
	{
		void *value = registerEntry->value;
		PyObject *registerObject = NULL;
		
		if (registerEntry->type == ZGRegisterGeneralPurpose)
		{
			registerObject = !is64Bit ? Py_BuildValue("I", *(uint32_t *)value) : Py_BuildValue("K", *(uint64_t *)value);
		}
		else
		{
			registerObject = Py_BuildValue("y#", value, registerEntry->size);
		}
		
		if (registerObject != NULL)
		{
			PyDict_SetItemString(dictionary, registerEntry->name, registerObject);
			Py_DecRef(registerObject);
		}
	}
	
	return dictionary;
}

- (PyObject *)registersfromRegistersState:(ZGRegistersState *)registersState
{
	ZGRegisterEntry registerEntries[ZG_MAX_REGISTER_ENTRIES];
	BOOL is64Bit = registersState.is64Bit;
	
	int numberOfGeneralPurposeEntries = [ZGRegisterEntries getRegisterEntries:registerEntries fromGeneralPurposeThreadState:registersState.generalPurposeThreadState is64Bit:is64Bit];
	
	if (registersState.hasVectorState)
	{
		[ZGRegisterEntries getRegisterEntries:registerEntries + numberOfGeneralPurposeEntries fromVectorThreadState:registersState.vectorState is64Bit:is64Bit hasAVXSupport:registersState.hasAVXSupport];
	}
	
	return convertRegisterEntriesToPyDict(registerEntries, is64Bit);
}

- (BOOL)evaluateCondition:(PyObject *)compiledExpression process:(ZGProcess *)process registerEntries:(ZGRegisterEntry *)registerEntries error:(NSError * __autoreleasing *)error
{
	__block BOOL result = NO;
	dispatch_sync(_pythonQueue, ^{
		PyObject *mainModule = PyImport_AddModule("__main__");
		
		ZGPyVirtualMemory *virtualMemoryInstance = [[ZGPyVirtualMemory alloc] initWithProcessNoCopy:process];
		CFRetain((__bridge CFTypeRef)(virtualMemoryInstance));
		
		PyObject_SetAttrString(mainModule, "vm", virtualMemoryInstance.object);
		
		PyObject *globalDictionary = PyModule_GetDict(mainModule);
		PyObject *localDictionary = convertRegisterEntriesToPyDict(registerEntries, process.is64Bit);
		
		PyDict_SetItemString(localDictionary, "ctypes", self->_cTypesObject);
		PyDict_SetItemString(localDictionary, "struct", self->_structObject);
		
		PyObject *evaluatedCode = PyEval_EvalCode(compiledExpression, globalDictionary, localDictionary);
		
		if (evaluatedCode == NULL)
		{
			NSString *pythonErrorDescription = [self fetchPythonErrorDescriptionWithoutDescriptiveTraceback];
			
			result = NO;
			if (error != NULL)
			{
				*error = [NSError errorWithDomain:@"EvaluateConditionFailure" code:2 userInfo:@{SCRIPT_EVALUATION_ERROR_REASON : @"expression could not be evaluated", SCRIPT_PYTHON_ERROR : pythonErrorDescription}];
			}
		}
		else
		{
			int temporaryResult = PyObject_IsTrue(evaluatedCode);
			if (temporaryResult == -1)
			{
				result = NO;
				if (error != NULL)
				{
					*error = [NSError errorWithDomain:@"EvaluateConditionFailure" code:3 userInfo:@{SCRIPT_EVALUATION_ERROR_REASON : @"expression did not evaluate to a boolean value"}];
				}
			}
			else
			{
				result = (BOOL)temporaryResult;
			}
		}
		
		Py_XDECREF(evaluatedCode);
		
		Py_XDECREF(localDictionary);
		
		CFRelease((__bridge CFTypeRef)(virtualMemoryInstance));
	});
	return result;
}

@end
