/*
 * Created by Mayur Pawashe on 8/25/13.
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

#import "ZGLoggerWindowController.h"
#import "ZGScriptManager.h"
#import "ZGVariable.h"
#import "ZGDocumentWindowController.h"
#import "ZGPyScript.h"
#import "ZGPyKeyCodeModule.h"
#import "ZGPyKeyModModule.h"
#import "ZGPyVirtualMemory.h"
#import "ZGPyDebugger.h"
#import "ZGBreakPoint.h"
#import "ZGProcess.h"
#import "ZGPyMainModule.h"
#import "ZGPyVMProtModule.h"
#import "ZGSearchProgress.h"
#import "ZGTableView.h"
#import "ZGUtilities.h"
#import "ZGRegisterEntries.h"
#import "ZGAppTerminationState.h"
#import "ZGAppPathUtilities.h"

#import "structmember.h"

#define SCRIPT_CACHES_PATH [[[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier]] stringByAppendingPathComponent:@"Scripts_Temp"]

#define SCRIPT_FILENAME_PREFIX @"Script"

NSString *ZGScriptDefaultApplicationEditorKey = @"ZGScriptDefaultApplicationEditorKey";

@interface ZGScriptManager ()
{
	dispatch_once_t _cleanupDispatch;
}

@property (nonatomic) ZGLoggerWindowController *loggerWindowController;

@property (nonatomic) NSMutableDictionary *scriptsDictionary;
@property (nonatomic) VDKQueue *fileWatchingQueue;
@property (nonatomic, assign) ZGDocumentWindowController *windowController;
@property (atomic) dispatch_source_t scriptTimer;
@property (atomic) NSMutableArray *runningScripts;
@property (nonatomic) NSMutableArray *objectsPool;
@property (nonatomic) id scriptActivity;

@property (nonatomic) ZGAppTerminationState *appTerminationState;
@property (nonatomic) BOOL delayedAppTermination;

@end

@implementation ZGScriptManager

dispatch_queue_t gPythonQueue;
static PyObject *gCtypesObject;
static PyObject *gStructObject;

+ (void)appendPath:(NSString *)path toSysPath:(PyObject *)sysPath
{
	if (path == nil) return;
	
	PyObject *newPath = PyUnicode_FromString([path UTF8String]);
	if (PyList_Append(sysPath, newPath) != 0)
	{
		NSLog(@"Error on appending %@", path);
	}
	Py_XDECREF(newPath);
}

+ (void)initializePythonInterpreter
{
	NSString *userModulesDirectory = [ZGAppPathUtilities createUserModulesDirectory];
	
	NSString *pythonDirectory = [[NSBundle mainBundle] pathForResource:@"python3.3" ofType:nil];
	setenv("PYTHONHOME", [pythonDirectory UTF8String], 1);
	setenv("PYTHONPATH", [pythonDirectory UTF8String], 1);
	dispatch_async(gPythonQueue, ^{
		Py_Initialize();
		PyObject *path = PySys_GetObject("path");
		
		[self appendPath:[pythonDirectory stringByAppendingPathComponent:@"lib-dynload"] toSysPath:path];
		[self appendPath:SCRIPT_CACHES_PATH toSysPath:path];
		[self appendPath:userModulesDirectory toSysPath:path];
		
		PyObject *mainModule = loadMainPythonModule();
		[ZGPyVirtualMemory loadPythonClassInMainModule:mainModule];
		[ZGPyDebugger loadPythonClassInMainModule:mainModule];
		
		loadKeyCodePythonModule();
		loadKeyModPythonModule();
		loadVMProtPythonModule();
		
		gCtypesObject = PyImport_ImportModule("ctypes");
		gStructObject = PyImport_ImportModule("struct");
	});
}

+ (void)initialize
{
	static dispatch_once_t onceToken = 0;
	dispatch_once(&onceToken, ^{
		[[NSUserDefaults standardUserDefaults] registerDefaults:@{ZGScriptDefaultApplicationEditorKey : @""}];
		
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
		
		gPythonQueue = dispatch_queue_create(NULL, DISPATCH_QUEUE_SERIAL);
		
		setenv("PYTHONDONTWRITEBYTECODE", "1", 1);
		
		[self initializePythonInterpreter];
	});
}

+ (PyObject *)compiledExpressionFromExpression:(NSString *)expression error:(NSError * __autoreleasing *)error
{
	__block PyObject *compiledExpression = NULL;
	
	dispatch_sync(gPythonQueue, ^{
		compiledExpression = Py_CompileString([expression UTF8String], "EvaluateCondition", Py_eval_input);
		
		if (compiledExpression == NULL)
		{
			NSString *pythonErrorDescription = [self fetchPythonErrorDescriptionWithoutDescriptiveTraceback];
			if (error != NULL)
			{
				*error = [NSError errorWithDomain:@"CompileConditionFailure" code:2 userInfo:@{SCRIPT_COMPILATION_ERROR_REASON : [NSString stringWithFormat:@"An error occured trying to parse expression %@", expression], SCRIPT_PYTHON_ERROR : pythonErrorDescription}];
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

+ (BOOL)evaluateCondition:(PyObject *)compiledExpression process:(ZGProcess *)process registerEntries:(ZGRegisterEntry *)registerEntries error:(NSError * __autoreleasing *)error
{
	__block BOOL result = NO;
	dispatch_sync(gPythonQueue, ^{
		PyObject *mainModule = PyImport_AddModule("__main__");
		
		ZGPyVirtualMemory *virtualMemoryInstance = [[ZGPyVirtualMemory alloc] initWithProcessNoCopy:process];
		CFRetain((__bridge CFTypeRef)(virtualMemoryInstance));
		
		PyObject_SetAttrString(mainModule, "vm", virtualMemoryInstance.object);
		
		PyObject *globalDictionary = PyModule_GetDict(mainModule);
		PyObject *localDictionary = convertRegisterEntriesToPyDict(registerEntries, process.is64Bit);
		
		PyDict_SetItemString(localDictionary, "ctypes", gCtypesObject);
		PyDict_SetItemString(localDictionary, "struct", gStructObject);
		
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

- (id)initWithWindowController:(ZGDocumentWindowController *)windowController
{
	self = [super init];
	if (self != nil)
	{
		self.scriptsDictionary = [[NSMutableDictionary alloc] init];
		self.fileWatchingQueue = [[VDKQueue alloc] init];
		self.fileWatchingQueue.delegate = self;
		self.windowController = windowController;
		self.loggerWindowController = windowController.loggerWindowController;
	}
	return self;
}

- (void)cleanupWithAppTerminationState:(ZGAppTerminationState *)appTerminationState
{
	dispatch_once(&_cleanupDispatch, ^{
		self.appTerminationState = appTerminationState;
		
		[self.scriptsDictionary enumerateKeysAndObjectsUsingBlock:^(NSValue *variableValue, ZGPyScript *pyScript, BOOL * __unused stop) {
			if ([self.runningScripts containsObject:pyScript])
			{
				if (self.appTerminationState != nil)
				{
					[self.appTerminationState increaseLifeCount];
					self.delayedAppTermination = YES;
				}
				[self stopScriptForVariable:[variableValue pointerValue]];
			}
		}];
		
		[self.fileWatchingQueue removeAllPaths];
	});
}

- (void)cleanup
{
	[self cleanupWithAppTerminationState:nil];
}

- (void)VDKQueue:(VDKQueue *)__unused queue receivedNotification:(NSString *)__unused noteName forPath:(NSString *)fullPath
{
	NSFileManager *fileManager = [[NSFileManager alloc] init];
	__block BOOL assignedNewScript = NO;
	[self.scriptsDictionary enumerateKeysAndObjectsUsingBlock:^(NSValue *variableValue, ZGPyScript *script, BOOL *stop) {
		if ([script.path isEqualToString:fullPath])
		{
			if ([fileManager fileExistsAtPath:script.path])
			{
				NSString *newScriptValue = [[NSString alloc] initWithContentsOfFile:script.path encoding:NSUTF8StringEncoding error:nil];
				if (newScriptValue != nil)
				{
					ZGVariable *variable = [variableValue pointerValue];
					if (![variable.scriptValue isEqualToString:newScriptValue])
					{
						variable.scriptValue = newScriptValue;
						assignedNewScript = YES;
					}
				}
			}
			*stop = YES;
		}
	}];
	
	if (assignedNewScript)
	{
		ZGDocumentWindowController *windowController = self.windowController;
		[windowController.variablesTableView reloadData];
		[windowController markDocumentChange];
	}
	
	// Handle atomic saves
	[self.fileWatchingQueue removePath:fullPath];
	[self.fileWatchingQueue addPath:fullPath];
}

- (void)loadCachedScriptsFromVariables:(NSArray *)variables
{
	NSFileManager *fileManager = [[NSFileManager alloc] init];
	BOOL needsToMarkChange = NO;
	for (ZGVariable *variable in variables)
	{
		if (variable.type == ZGScript)
		{
			if (variable.cachedScriptPath != nil && [fileManager fileExistsAtPath:variable.cachedScriptPath])
			{
				NSString *cachedScriptString = [[NSString alloc] initWithContentsOfFile:variable.cachedScriptPath encoding:NSUTF8StringEncoding error:nil];
				if (cachedScriptString != nil && variable.scriptValue != nil && ![variable.scriptValue isEqualToString:cachedScriptString] && cachedScriptString.length > 0)
				{
					variable.scriptValue = cachedScriptString;
					needsToMarkChange = YES;
				}
				
				// Make sure we're watching the script for changes
				[self scriptForVariable:variable];
			}
		}
	}
	
	if (needsToMarkChange)
	{
		[self.windowController markDocumentChange];
	}
}

- (ZGPyScript *)scriptForVariable:(ZGVariable *)variable
{
	NSFileManager *fileManager = [[NSFileManager alloc] init];
	
	ZGPyScript *script = [self.scriptsDictionary objectForKey:[NSValue valueWithNonretainedObject:variable]];
	if (script != nil && ![fileManager fileExistsAtPath:script.path])
	{
		[self.scriptsDictionary removeObjectForKey:[NSValue valueWithNonretainedObject:variable]];
		[self.fileWatchingQueue removePath:script.path];
		script = nil;
	}
	
	if (script == nil)
	{
		NSString *scriptPath = nil;
		
		if (variable.cachedScriptPath != nil && [fileManager fileExistsAtPath:variable.cachedScriptPath])
		{
			scriptPath = variable.cachedScriptPath;
		}
		else
		{
			uint32_t randomInteger = arc4random();
			
			NSMutableString *randomFilename = [NSMutableString stringWithFormat:@"%@ %X", SCRIPT_FILENAME_PREFIX, randomInteger];
			while ([fileManager fileExistsAtPath:[[SCRIPT_CACHES_PATH stringByAppendingPathComponent:randomFilename] stringByAppendingString:@".py"]])
			{
				[randomFilename appendString:@"1"];
			}
			
			[randomFilename appendString:@".py"];
			
			scriptPath = [SCRIPT_CACHES_PATH stringByAppendingPathComponent:randomFilename];
		}
		
		if (variable.cachedScriptPath == nil || ![variable.cachedScriptPath isEqualToString:scriptPath])
		{
			variable.cachedScriptPath = scriptPath;
			[self.windowController markDocumentChange];
		}
		
		NSData *scriptData = [variable.scriptValue dataUsingEncoding:NSUTF8StringEncoding];
		
		script = [[ZGPyScript alloc] initWithPath:scriptPath];
		
		// We have to import the module the first time succesfully so we can reload it later; to ensure this, we use an empty file
		[[NSData data] writeToFile:scriptPath atomically:YES];
		
		dispatch_sync(gPythonQueue, ^{
			script.module = PyImport_ImportModule([script.moduleName UTF8String]);
		});
		
		[scriptData writeToFile:scriptPath atomically:YES];
		
		[self.fileWatchingQueue addPath:scriptPath];
		
		[self.scriptsDictionary setObject:script forKey:[NSValue valueWithNonretainedObject:variable]];
	}
	
	return script;
}

- (void)openScriptForVariable:(ZGVariable *)variable
{
	ZGPyScript *script = [self scriptForVariable:variable];
	NSString *editorApplication = [[NSUserDefaults standardUserDefaults] objectForKey:ZGScriptDefaultApplicationEditorKey];
	if (editorApplication.length == 0)
	{
		[[NSWorkspace sharedWorkspace] openFile:script.path];
	}
	else
	{
		if (![[NSWorkspace sharedWorkspace] openFile:script.path withApplication:editorApplication])
		{
			[[NSWorkspace sharedWorkspace] openFile:script.path];
		}
	}
}

+ (NSString *)fetchPythonErrorDescriptionFromObject:(PyObject *)pythonObject
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

+ (NSString *)fetchPythonErrorDescriptionWithoutDescriptiveTraceback
{
	PyObject *type, *value, *traceback;
	PyErr_Fetch(&type, &value, &traceback);
	
	NSArray *errorDescriptionComponents = @[[self fetchPythonErrorDescriptionFromObject:type], [self fetchPythonErrorDescriptionFromObject:value], [self fetchPythonErrorDescriptionFromObject:traceback]];
	
	PyErr_Clear();
	
	return [errorDescriptionComponents componentsJoinedByString:@"\n"];
}

+ (void)logPythonObject:(PyObject *)pythonObject withLoggerWindowController:(ZGLoggerWindowController *)loggerWindowController
{
	NSString *errorDescription = [[self class] fetchPythonErrorDescriptionFromObject:pythonObject];
	dispatch_async(dispatch_get_main_queue(), ^{
		[loggerWindowController writeLine:errorDescription];
	});
}

- (void)logPythonObject:(PyObject *)pythonObject
{
	[[self class] logPythonObject:pythonObject withLoggerWindowController:self.loggerWindowController];
}

- (void)logPythonError
{
	PyObject *type, *value, *traceback;
	PyErr_Fetch(&type, &value, &traceback);
	
	dispatch_async(dispatch_get_main_queue(), ^{
		NSString *errorMessage = [NSString stringWithFormat:@"An error occured trying to run the script on %@", self.windowController.currentProcess.name];
		[self.loggerWindowController writeLine:errorMessage];
		
		if ((![NSApp isActive] || ![self.loggerWindowController.window isVisible]))
		{
			ZGDeliverUserNotification(@"Script Failed", nil, errorMessage);
		}
	});
	
	[self logPythonObject:type];
	[self logPythonObject:value];
	
	// Log detailed traceback info including the line where the exception was thrown
	if (traceback != NULL)
	{
		NSString *logPath = [ZGAppPathUtilities lastErrorLogPath];
		if (logPath != NULL && [logPath UTF8String] != NULL)
		{
			FILE *logFile = fopen([logPath UTF8String], "w");
			if (logFile != NULL)
			{
				PyObject *file = PyFile_FromFd(fileno(logFile), NULL, "w", -1, NULL, NULL, NULL, NO);
				if (file != NULL)
				{
					PyTraceBack_Print(traceback, file);
					Py_DecRef(file);
				}
				
				fclose(logFile);
				
				NSString *latestLog = [[NSString alloc] initWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:NULL];
				if (latestLog != nil)
				{
					dispatch_async(dispatch_get_main_queue(), ^{
						[self.loggerWindowController writeLine:latestLog];
					});
				}
			}
		}
	}
	
	PyErr_Clear();
}

- (BOOL)executeScript:(ZGPyScript *)script
{	
	PyObject *retValue = NULL;
	
	if (Py_IsInitialized())
	{
		retValue = PyObject_CallFunction(script.executeFunction, "d", script.deltaTime);
	}
	
	if (retValue == NULL)
	{
		if (Py_IsInitialized())
		{
			[self logPythonError];
		}
		
		script.scriptObject = NULL;
		
		[self.scriptsDictionary enumerateKeysAndObjectsUsingBlock:^(NSValue *variableValue, ZGPyScript *pyScript, BOOL *stop) {
			if (pyScript == script)
			{
				dispatch_async(dispatch_get_main_queue(), ^{
					[self stopScriptForVariable:[variableValue pointerValue]];
				});
				*stop = YES;
			}
		}];
	}
	
	if (Py_IsInitialized())
	{
		Py_XDECREF(retValue);
	}
	
	return retValue != NULL;
}

- (void)watchProcessDied:(NSNotification *)__unused notification
{
	[self.scriptsDictionary enumerateKeysAndObjectsUsingBlock:^(NSValue *variableValue, ZGPyScript *pyScript, BOOL *__unused stop) {
		if ([self.runningScripts containsObject:pyScript])
		{
			[self stopScriptForVariable:[variableValue pointerValue]];
		}
	}];
}

- (void)disableVariable:(ZGVariable *)variable
{
	if (variable.enabled)
	{
		variable.enabled = NO;
		ZGDocumentWindowController *windowController = self.windowController;
		[windowController.variablesTableView reloadData];
		[windowController markDocumentChange];
	}
}

- (void)setUpStackDepthLimit
{
	PyObject *sys = PyImport_ImportModule("sys");
	if (sys != NULL)
	{
		PyObject *setRecursionLimitFunction = PySys_GetObject("setrecursionlimit");
		if (setRecursionLimitFunction != NULL)
		{
			PyObject *successValue = PyObject_CallFunction(setRecursionLimitFunction, "K", 500);
			if (successValue == NULL)
			{
				[self logPythonError];
			}
			Py_XDECREF(successValue);
		}

		Py_DecRef(sys);
	}
}

- (void)runScriptForVariable:(ZGVariable *)variable
{
	ZGPyScript *script = [self scriptForVariable:variable];
	
	ZGDocumentWindowController *windowController = self.windowController;
	
	if (!windowController.currentProcess.valid)
	{
		[self disableVariable:variable];
		return;
	}
	
	dispatch_async(gPythonQueue, ^{
		script.module = PyImport_ImportModule([script.moduleName UTF8String]);
		script.module = PyImport_ReloadModule(script.module);
		
		PyTypeObject *scriptClassType = NULL;
		if (script.module != NULL)
		{
			scriptClassType = (PyTypeObject *)PyObject_GetAttrString(script.module, "Script");
		}
		
		if (scriptClassType == NULL)
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				[self disableVariable:variable];
			});
			[self logPythonError];
			
			return;
		}
		
		script.scriptObject = scriptClassType->tp_alloc(scriptClassType, 0);
		
		Py_XDECREF(scriptClassType);
		
		ZGPyVirtualMemory *virtualMemoryInstance = [[ZGPyVirtualMemory alloc] initWithProcess:windowController.currentProcess];
		ZGPyDebugger *debuggerInstance = [[ZGPyDebugger alloc] initWithProcess:windowController.currentProcess scriptManager:self breakPointController:self.windowController.breakPointController hotKeyCenter:self.windowController.hotKeyCenter loggerWindowController:windowController.loggerWindowController];
		
		script.virtualMemoryInstance = virtualMemoryInstance;
		script.debuggerInstance = debuggerInstance;
		
		if (virtualMemoryInstance == nil || debuggerInstance == nil)
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				[self disableVariable:variable];
				NSLog(@"Error: Couldn't create VM or Debug instance");
			});
			
			return;
		}
		
		if (self.runningScripts == nil)
		{
			self.runningScripts = [[NSMutableArray alloc] init];
		}
		
		[self.runningScripts addObject:script];
		
		dispatch_async(dispatch_get_main_queue(), ^{
			[[NSNotificationCenter defaultCenter]
			 addObserver:self
			 selector:@selector(watchProcessDied:)
			 name:ZGTargetProcessDiedNotification
			 object:self.windowController.currentProcess];
		});
		
		PyObject_SetAttrString(script.module, "vm", virtualMemoryInstance.object);
		PyObject_SetAttrString(script.module, "debug", debuggerInstance.object);
		
		id scriptInitActivity = nil;
		if ([[NSProcessInfo processInfo] respondsToSelector:@selector(beginActivityWithOptions:reason:)])
		{
			scriptInitActivity = [[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiated reason:@"Script initializer"];
		}
		
		[self setUpStackDepthLimit];
		
		PyObject *initMethodResult = PyObject_CallMethod(script.scriptObject, "__init__", NULL);
		
		if (scriptInitActivity != nil)
		{
			[[NSProcessInfo processInfo] endActivity:scriptInitActivity];
		}
		
		BOOL stillInitialized = (BOOL)Py_IsInitialized();
		if (initMethodResult == NULL || !stillInitialized)
		{
			if (stillInitialized)
			{
				[self logPythonError];
			}
			
			script.scriptObject = NULL;
			
			dispatch_async(dispatch_get_main_queue(), ^{
				[self stopScriptForVariable:variable];
			});
			
			Py_XDECREF(initMethodResult);
			return;
		}
		
		script.lastTime = [NSDate timeIntervalSinceReferenceDate];
		script.deltaTime = 0;
		
		const char *executeFunctionName = "execute";
		if (!PyObject_HasAttrString(script.scriptObject, executeFunctionName))
		{
			Py_XDECREF(initMethodResult);
			return;
		}
		
		script.executeFunction = PyObject_GetAttrString(script.scriptObject, executeFunctionName);
		
		if (self.scriptTimer == NULL && (self.scriptTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gPythonQueue)) != NULL)
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				if ([[NSProcessInfo processInfo] respondsToSelector:@selector(beginActivityWithOptions:reason:)])
				{
					self.scriptActivity = [[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiated reason:@"Script execute timer"];
				}
			});
			
			dispatch_source_set_timer(self.scriptTimer, dispatch_walltime(NULL, 0), (uint64_t)(0.03 * NSEC_PER_SEC), (uint64_t)(0.01 * NSEC_PER_SEC));
			dispatch_source_set_event_handler(self.scriptTimer, ^{
				for (ZGPyScript *runningScript in self.runningScripts)
				{
					NSTimeInterval currentTime = [NSDate timeIntervalSinceReferenceDate];
					runningScript.deltaTime = currentTime - runningScript.lastTime;
					runningScript.lastTime = currentTime;
					[self executeScript:runningScript];
				}
			});
			dispatch_resume(self.scriptTimer);
		}
		
		if (self.scriptTimer == NULL)
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				[self stopScriptForVariable:variable];
			});
		}
		
		Py_XDECREF(initMethodResult);
	});
}

- (void)removeScriptForVariable:(ZGVariable *)variable
{
	ZGPyScript *script = [self.scriptsDictionary objectForKey:[NSValue valueWithNonretainedObject:variable]];
	if (script != nil)
	{
		[self.fileWatchingQueue removePath:script.path];
		[self.scriptsDictionary removeObjectForKey:[NSValue valueWithNonretainedObject:variable]];
	}
}

- (void)stopScriptForVariable:(ZGVariable *)variable
{
	[self disableVariable:variable];
	
	ZGPyScript *script = [self scriptForVariable:variable];
	
	if ([self.runningScripts containsObject:script])
	{
		[self.runningScripts removeObject:script];
		if (self.runningScripts.count == 0)
		{
			dispatch_async(gPythonQueue, ^{
				if (self.scriptTimer != NULL)
				{
					dispatch_source_cancel(self.scriptTimer);
					self.scriptTimer = NULL;
					dispatch_async(dispatch_get_main_queue(), ^{
						if (self.scriptActivity != nil)
						{
							[[NSProcessInfo processInfo] endActivity:self.scriptActivity];
							self.scriptActivity = nil;
						}
						
						[self.windowController updateOcclusionActivity];
					});
				}
			});
			
			[[NSNotificationCenter defaultCenter] removeObserver:self];
		}
		
		BOOL delayedAppTermination = self.delayedAppTermination;
		
		NSUInteger scriptFinishedCount = script.finishedCount;
		
		void (^scriptCleanup)(void) = ^{
			script.deltaTime = 0;
			script.virtualMemoryInstance = nil;
			[script.debuggerInstance cleanup];
			script.debuggerInstance = nil;
			script.scriptObject = NULL;
			script.executeFunction = NULL;
			script.finishedCount++;
		};
		
		[script.virtualMemoryInstance.searchProgress setShouldCancelSearch:YES];
		
		dispatch_async(gPythonQueue, ^{
			if (script.finishedCount == scriptFinishedCount)
			{
				if (!delayedAppTermination)
				{
					const char *finishFunctionName = "finish";
					if (Py_IsInitialized() && self.windowController.currentProcess.valid && script.scriptObject != NULL && PyObject_HasAttrString(script.scriptObject, finishFunctionName))
					{
						PyObject *retValue = PyObject_CallMethod(script.scriptObject, (char *)finishFunctionName, NULL);
						if (Py_IsInitialized())
						{
							if (retValue == NULL)
							{
								[self logPythonError];
							}
							Py_XDECREF(retValue);
						}
					}
				}
				
				scriptCleanup();
				
				if (delayedAppTermination)
				{
					dispatch_async(dispatch_get_main_queue(), ^{
						[self.appTerminationState decreaseLifeCount];
					});
				}
			}
		});
		
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
			if (scriptFinishedCount == script.finishedCount)
			{
				if (delayedAppTermination)
				{
					[self.appTerminationState decreaseLifeCount];
				}
				else
				{
					// Give up - this should be okay to call from another thread
					PyErr_SetInterrupt();
					
					dispatch_async(gPythonQueue, ^{
						scriptCleanup();
					});
				}
			}
		});
	}
}

- (void)handleCallbackFailureWithVariable:(ZGVariable *)variable methodCallResult:(PyObject *)methodCallResult forMethodName:(const char *)methodName shouldStop:(BOOL *)stop
{
	if (methodCallResult == NULL)
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			[self.loggerWindowController writeLine:[NSString stringWithFormat:@"Exception raised in %s callback", methodName]];
		});
		[self logPythonError];
		dispatch_async(dispatch_get_main_queue(), ^{
			[self stopScriptForVariable:variable];
		});
		*stop = YES;
	}
}

- (PyObject *)registersfromBreakPoint:(ZGBreakPoint *)breakPoint
{
	ZGRegisterEntry registerEntries[ZG_MAX_REGISTER_ENTRIES];
	BOOL is64Bit = breakPoint.process.is64Bit;
	
	int numberOfGeneralPurposeEntries = [ZGRegisterEntries getRegisterEntries:registerEntries fromGeneralPurposeThreadState:breakPoint.generalPurposeThreadState is64Bit:is64Bit];
	
	if (breakPoint.hasVectorState)
	{
		[ZGRegisterEntries getRegisterEntries:registerEntries + numberOfGeneralPurposeEntries fromVectorThreadState:breakPoint.vectorState is64Bit:is64Bit hasAVXSupport:breakPoint.hasAVXSupport];
	}
	
	return convertRegisterEntriesToPyDict(registerEntries, is64Bit);
}

- (void)handleDataBreakPoint:(ZGBreakPoint *)breakPoint instructionAddress:(ZGMemoryAddress)instructionAddress callback:(PyObject *)callback sender:(id)sender
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[self.scriptsDictionary enumerateKeysAndObjectsUsingBlock:^(NSValue *variableValue, ZGPyScript *pyScript, BOOL *stop) {
			dispatch_async(gPythonQueue, ^{
				if (Py_IsInitialized() && pyScript.debuggerInstance == sender)
				{
					PyObject *registers = [self registersfromBreakPoint:breakPoint];
					PyObject *result = PyObject_CallFunction(callback, "KKO", breakPoint.variable.address, instructionAddress, registers);
					[self handleCallbackFailureWithVariable:[variableValue pointerValue] methodCallResult:result forMethodName:"data watchpoint" shouldStop:stop];
					Py_XDECREF(registers);
					Py_XDECREF(result);
				}
			});
		}];
	});
}

- (void)handleInstructionBreakPoint:(ZGBreakPoint *)breakPoint callback:(PyObject *)callback sender:(id)sender
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[self.scriptsDictionary enumerateKeysAndObjectsUsingBlock:^(NSValue *variableValue, ZGPyScript *pyScript, BOOL *stop) {
			dispatch_async(gPythonQueue, ^{
				if (Py_IsInitialized() && pyScript.debuggerInstance == sender)
				{
					PyObject *registers = [self registersfromBreakPoint:breakPoint];
					PyObject *result = PyObject_CallFunction(callback, "KO", breakPoint.variable.address, registers);
					Py_XDECREF(registers);
					
					[self handleCallbackFailureWithVariable:[variableValue pointerValue] methodCallResult:result forMethodName:"instruction breakpoint" shouldStop:stop];
					Py_XDECREF(result);
					
					if (breakPoint.hidden && breakPoint.callback != NULL)
					{
						Py_DecRef(breakPoint.callback);
						breakPoint.callback = NULL;
					}
				}
			});
		}];
	});
}

- (void)handleHotKeyTriggerWithInternalID:(UInt32)hotKeyID callback:(PyObject *)callback sender:(id)sender
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[self.scriptsDictionary enumerateKeysAndObjectsUsingBlock:^(NSValue *variableValue, ZGPyScript *pyScript, BOOL *stop) {
			dispatch_async(gPythonQueue, ^{
				if (Py_IsInitialized() && pyScript.debuggerInstance == sender)
				{
					PyObject *result = PyObject_CallFunction(callback, "I", hotKeyID);
					[self handleCallbackFailureWithVariable:[variableValue pointerValue] methodCallResult:result forMethodName:"hotkey trigger" shouldStop:stop];
					Py_XDECREF(result);
				}
			});
		}];
	});
}

@end
