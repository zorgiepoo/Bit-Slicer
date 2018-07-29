/*
 * Copyright (c) 2015 Mayur Pawashe
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
#import "OSCSingleThreadQueue.h"
#import "ZGNullability.h"

#import <pthread.h>
#import "Python/structmember.h"

@implementation ZGScriptingInterpreter
{
	OSCSingleThreadQueue * _Nullable _pythonQueue;
	PyObject * _Nullable _cTypesObject;
	PyObject * _Nullable _structObject;
	BOOL _initializedInterpreter;
}

+ (instancetype)createInterpreterOnce
{
	static ZGScriptingInterpreter *scriptingInterpreter;
	assert(scriptingInterpreter == nil);
	
	scriptingInterpreter = [(ZGScriptingInterpreter *)[[self class] alloc] init];
	return scriptingInterpreter;
}

+ (NSURL *)scriptCachesURL
{
	NSFileManager *fileManager = [[NSFileManager alloc] init];
	NSURL *cachesURL = [fileManager URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:NULL];
	if (cachesURL == nil)
	{
		return cachesURL;
	}
	
	NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
	if (bundleIdentifier == nil)
	{
		return nil;
	}
	
	return [[cachesURL URLByAppendingPathComponent:bundleIdentifier] URLByAppendingPathComponent:@"Scripts_Temp"];
}

- (id)init
{
	self = [super init];
	if (self != nil)
	{
		NSFileManager *fileManager = [[NSFileManager alloc] init];
		
		NSURL *scriptCachesURL = [[self class] scriptCachesURL];
		NSString *scriptCachesPath = ZGUnwrapNullableObject(scriptCachesURL.path);
		
		if (![fileManager fileExistsAtPath:scriptCachesPath])
		{
			NSError *createDirectoryError = nil;
			if (![fileManager createDirectoryAtURL:scriptCachesURL withIntermediateDirectories:YES attributes:nil error:&createDirectoryError])
			{
				NSLog(@"Failed to create scripting cache directory at %@ with error %@", scriptCachesURL, createDirectoryError);
				assert("Failed to crete script cache directory" == NULL);
			}
		}
		
		NSMutableArray<NSString *> *filePathsToRemove = [NSMutableArray array];
		NSDirectoryEnumerator *directoryEnumerator = [fileManager enumeratorAtPath:scriptCachesPath];
		for (NSString *filename in directoryEnumerator)
		{
			if ([filename hasPrefix:SCRIPT_FILENAME_PREFIX] && [[filename pathExtension] isEqualToString:@"py"])
			{
				NSDictionary<NSString *, id> *fileAttributes = [fileManager attributesOfItemAtPath:[scriptCachesPath stringByAppendingPathComponent:filename] error:nil];
				if (fileAttributes != nil)
				{
					NSDate *lastModificationDate = fileAttributes[NSFileModificationDate];
					if ([[NSDate date] timeIntervalSinceDate:lastModificationDate] > 864000) // 10 days
					{
						[filePathsToRemove addObject:[scriptCachesPath stringByAppendingPathComponent:filename]];
					}
				}
			}
			[directoryEnumerator skipDescendants];
		}
		
		for (NSString *filename in filePathsToRemove)
		{
			[fileManager removeItemAtPath:filename error:nil];
		}
	}
	return self;
}

// Python has stingy threading requirements and requires all python calls to be invoked from the same thread
// Otherwise we may run into memory corruption issues (as verified by ASan)

- (void)dispatchAsync:(dispatch_block_t)work
{
	[_pythonQueue dispatchAsync:work];
}

- (void)dispatchSync:(dispatch_block_t)work
{
	[_pythonQueue dispatchSync:work];
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

- (void)acquireInterpreter
{
	if (_initializedInterpreter) return;
	_initializedInterpreter = YES;
	
	_pythonQueue = [OSCSingleThreadQueue startWithPriority:DISPATCH_QUEUE_PRIORITY_DEFAULT label:"com.zgcoder.python-thread"];
	
	setenv("PYTHONDONTWRITEBYTECODE", "1", 1);
	
	NSString *userModulesDirectory = [ZGAppPathUtilities createUserModulesDirectory];
	
	NSString *privateFrameworksPath = [[NSBundle mainBundle] privateFrameworksPath];
	assert(privateFrameworksPath != nil);
	
	NSBundle *pythonBundle = [NSBundle bundleWithPath:[privateFrameworksPath stringByAppendingPathComponent:@"Python.framework"]];
	assert(pythonBundle != nil);
	
	NSString *pythonDirectory = [pythonBundle pathForResource:@"python3.7" ofType:nil];
	assert(pythonDirectory != nil);
	
	setenv("PYTHONHOME", [pythonDirectory UTF8String], 1);
	setenv("PYTHONPATH", [pythonDirectory UTF8String], 1);
	[self dispatchAsync:^{
		Py_Initialize();
		
		PyObject *path = PySys_GetObject("path");
		
		[self appendPath:[pythonDirectory stringByAppendingPathComponent:@"lib-dynload"] toSysPath:path];
		[self appendPath:[[[self class] scriptCachesURL] path] toSysPath:path];
		[self appendPath:userModulesDirectory toSysPath:path];
		
		PyObject *mainModule = loadMainPythonModule();
		if (mainModule != NULL)
		{
			self->_virtualMemoryException = [ZGPyVirtualMemory loadPythonClassInMainModule:mainModule];
			self->_debuggerException = [ZGPyDebugger loadPythonClassInMainModule:mainModule];
			
			assert(self->_virtualMemoryException != NULL);
			assert(self->_debuggerException != NULL);
		}
		else
		{
			NSLog(@"Error: Main Module could not be loaded");
			NSLog(@"Error Message: %@", [self fetchPythonErrorDescriptionWithoutDescriptiveTraceback]);
			assert(false);
		}
		
		loadKeyCodePythonModule();
		loadKeyModPythonModule();
		loadVMProtPythonModule();
		
		self->_cTypesObject = PyImport_ImportModule("ctypes");
		self->_structObject = PyImport_ImportModule("struct");
	}];
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
	
	NSArray<NSString *> *errorDescriptionComponents = @[[self fetchPythonErrorDescriptionFromObject:type], [self fetchPythonErrorDescriptionFromObject:value], [self fetchPythonErrorDescriptionFromObject:traceback]];
	
	PyErr_Clear();
	
	return [errorDescriptionComponents componentsJoinedByString:@"\n"];
}

- (PyObject *)compiledExpressionFromExpression:(NSString *)expression error:(NSError * __autoreleasing *)error
{
	[self acquireInterpreter];
	
	__block PyObject *compiledExpression = NULL;
	// If we don't declare a local __block NSError* for our synchronous dispatch, we may run into a bad memory access error
	__block NSError *compileError = nil;
	
	[self dispatchSync:^{
		compiledExpression = Py_CompileString([expression UTF8String], "EvaluateCondition", Py_eval_input);
		
		if (compiledExpression == NULL)
		{
			NSString *pythonErrorDescription = [self fetchPythonErrorDescriptionWithoutDescriptiveTraceback];
			compileError = [NSError errorWithDomain:@"CompileConditionFailure" code:2 userInfo:@{SCRIPT_PYTHON_ERROR : pythonErrorDescription}];
		}
	}];
	
	if (compileError != nil && error != NULL)
	{
		*error = compileError;
	}
	
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
	// If we don't declare a local __block NSError* for our synchronous dispatch, we may run into a bad memory access error
	__block NSError *evaluateError = nil;
	
	[self dispatchSync:^{
		PyObject *mainModule = PyImport_AddModule("__main__");
		
		ZGPyVirtualMemory *virtualMemoryInstance = [[ZGPyVirtualMemory alloc] initWithProcessNoCopy:process virtualMemoryException:(PyObject * _Nonnull)self->_virtualMemoryException];
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
			evaluateError = [NSError errorWithDomain:@"EvaluateConditionFailure" code:2 userInfo:@{SCRIPT_EVALUATION_ERROR_REASON : @"expression could not be evaluated", SCRIPT_PYTHON_ERROR : pythonErrorDescription}];
		}
		else
		{
			int temporaryResult = PyObject_IsTrue(evaluatedCode);
			if (temporaryResult == -1)
			{
				result = NO;
				evaluateError = [NSError errorWithDomain:@"EvaluateConditionFailure" code:3 userInfo:@{SCRIPT_EVALUATION_ERROR_REASON : @"expression did not evaluate to a boolean value"}];;
			}
			else
			{
				result = (BOOL)temporaryResult;
			}
		}
		
		Py_XDECREF(evaluatedCode);
		
		Py_XDECREF(localDictionary);
		
		CFRelease((__bridge CFTypeRef)(virtualMemoryInstance));
	}];
	
	if (evaluateError != nil && error != NULL)
	{
		*error = evaluateError;
	}
	return result;
}

@end
