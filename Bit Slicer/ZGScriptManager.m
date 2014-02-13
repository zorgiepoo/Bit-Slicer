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
#import "ZGAppController.h"
#import "ZGScriptManager.h"
#import "ZGVariable.h"
#import "ZGDocumentWindowController.h"
#import "ZGPyScript.h"
#import "ZGPyVirtualMemory.h"
#import "ZGPyDebugger.h"
#import "ZGBreakPoint.h"
#import "ZGProcess.h"
#import "ZGPyMainModule.h"
#import "ZGSearchProgress.h"
#import "ZGTableView.h"
#import "ZGUtilities.h"

#import "structmember.h"

#define SCRIPT_CACHES_PATH [[[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier]] stringByAppendingPathComponent:@"Scripts_Temp"]

#define SCRIPT_FILENAME_PREFIX @"Script"

@interface ZGScriptManager ()
{
	dispatch_once_t _cleanupDispatch;
}

@property (nonatomic) NSMutableDictionary *scriptsDictionary;
@property (nonatomic) VDKQueue *fileWatchingQueue;
@property (nonatomic, weak) ZGDocumentWindowController *windowController;
@property dispatch_source_t scriptTimer;
@property NSMutableArray *runningScripts;
@property (nonatomic) NSMutableArray *objectsPool;
@property (nonatomic) id scriptActivity;
@property (nonatomic) BOOL delayedAppTermination;

@end

@implementation ZGScriptManager

dispatch_queue_t gPythonQueue;

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
	NSString *userModulesDirectory = [[ZGAppController sharedController] createUserModulesDirectory];
	
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
	});
}

+ (void)initialize
{
	static dispatch_once_t onceToken = 0;
	dispatch_once(&onceToken, ^{
		srand((unsigned)time(NULL));
		
		if (![[NSFileManager defaultManager] fileExistsAtPath:SCRIPT_CACHES_PATH])
		{
			[[NSFileManager defaultManager] createDirectoryAtPath:SCRIPT_CACHES_PATH withIntermediateDirectories:YES attributes:nil error:nil];
		}
		
		NSMutableArray *filePathsToRemove = [NSMutableArray array];
		NSDirectoryEnumerator *directoryEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:SCRIPT_CACHES_PATH];
		for (NSString *filename in directoryEnumerator)
		{
			if ([filename hasPrefix:SCRIPT_FILENAME_PREFIX] && [[filename pathExtension] isEqualToString:@"py"])
			{
				NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[SCRIPT_CACHES_PATH stringByAppendingPathComponent:filename] error:nil];
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
			[[NSFileManager defaultManager] removeItemAtPath:filename error:nil];
		}
		
		gPythonQueue = dispatch_queue_create(NULL, DISPATCH_QUEUE_SERIAL);
		
		setenv("PYTHONDONTWRITEBYTECODE", "1", 1);
		
		[self initializePythonInterpreter];
	});
}

+ (PyObject *)compiledExpressionFromExpression:(NSString *)expression
{
	__block PyObject *compiledExpression = NULL;
	
	dispatch_sync(gPythonQueue, ^{
		compiledExpression = Py_CompileString([expression UTF8String], "EvaluateCondition", Py_eval_input);
		
		if (compiledExpression == NULL)
		{
			PyObject *type, *value, *traceback;
			PyErr_Fetch(&type, &value, &traceback);
			
			[self logPythonObject:type];
			[self logPythonObject:value];
			[self logPythonObject:traceback];
			
			PyErr_Clear();
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
		}
	}
	
	return dictionary;
}

+ (BOOL)evaluateCondition:(PyObject *)compiledExpression process:(ZGProcess *)process registerEntries:(ZGRegisterEntry *)registerEntries error:(NSError * __autoreleasing *)error
{
	__block BOOL result = NO;
	dispatch_sync(gPythonQueue, ^{
		PyObject *mainModule = PyImport_AddModule("__main__");
		
		ZGPyVirtualMemory *virtualMemoryInstance = [[ZGPyVirtualMemory alloc] initWithProcess:process];
		CFRetain((__bridge CFTypeRef)(virtualMemoryInstance));
		
		PyObject_SetAttrString(mainModule, "vm", virtualMemoryInstance.object);
		
		PyObject *globalDictionary = PyModule_GetDict(mainModule);
		PyObject *localDictionary = convertRegisterEntriesToPyDict(registerEntries, process.is64Bit);
		
		PyObject *evaluatedCode = PyEval_EvalCode(compiledExpression, globalDictionary, localDictionary);
		
		if (evaluatedCode == NULL)
		{
			result = NO;
			if (error != NULL)
			{
				*error = [NSError errorWithDomain:@"EvaluateConditionFailure" code:2 userInfo:@{SCRIPT_EVALUATION_ERROR_REASON : @"expression could not be evaluated"}];
			}
			
			PyObject *type, *value, *traceback;
			PyErr_Fetch(&type, &value, &traceback);
			
			[self logPythonObject:type];
			[self logPythonObject:value];
			[self logPythonObject:traceback];
			
			PyErr_Clear();
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
				result = temporaryResult;
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
	}
	return self;
}

- (void)cleanup
{
	dispatch_once(&_cleanupDispatch, ^{
		[self.scriptsDictionary enumerateKeysAndObjectsUsingBlock:^(NSValue *variableValue, ZGPyScript *pyScript, BOOL *stop) {
			if ([self.runningScripts containsObject:pyScript])
			{
				if ([[ZGAppController sharedController] isTerminating])
				{
					[[ZGAppController sharedController] increaseLivingCount];
					self.delayedAppTermination = YES;
				}
				[self stopScriptForVariable:[variableValue pointerValue]];
			}
		}];
		
		[self.fileWatchingQueue removeAllPaths];
	});
}

- (void)VDKQueue:(VDKQueue *)queue receivedNotification:(NSString *)noteName forPath:(NSString *)fullPath
{
	__block BOOL assignedNewScript = NO;
	[self.scriptsDictionary enumerateKeysAndObjectsUsingBlock:^(NSValue *variableValue, ZGPyScript *script, BOOL *stop) {
		if ([script.path isEqualToString:fullPath])
		{
			if ([[NSFileManager defaultManager] fileExistsAtPath:script.path])
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
		[self.windowController.variablesTableView reloadData];
		[self.windowController markDocumentChange];
	}
	
	// Handle atomic saves
	[self.fileWatchingQueue removePath:fullPath];
	[self.fileWatchingQueue addPath:fullPath];
}

- (void)loadCachedScriptsFromVariables:(NSArray *)variables
{
	BOOL needsToMarkChange = NO;
	for (ZGVariable *variable in variables)
	{
		if (variable.type == ZGScript)
		{
			if (variable.cachedScriptPath != nil && [[NSFileManager defaultManager] fileExistsAtPath:variable.cachedScriptPath])
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
	ZGPyScript *script = [self.scriptsDictionary objectForKey:[NSValue valueWithNonretainedObject:variable]];
	if (script != nil && ![[NSFileManager defaultManager] fileExistsAtPath:script.path])
	{
		[self.scriptsDictionary removeObjectForKey:[NSValue valueWithNonretainedObject:variable]];
		[self.fileWatchingQueue removePath:script.path];
		script = nil;
	}
	
	if (script == nil)
	{
		NSString *scriptPath = nil;
		
		if (variable.cachedScriptPath != nil && [[NSFileManager defaultManager] fileExistsAtPath:variable.cachedScriptPath])
		{
			scriptPath = variable.cachedScriptPath;
		}
		else
		{
			unsigned int randomInteger = rand() % INT32_MAX;
			
			NSMutableString *randomFilename = [NSMutableString stringWithFormat:@"%@ %X", SCRIPT_FILENAME_PREFIX, randomInteger];
			while ([[NSFileManager defaultManager] fileExistsAtPath:[[SCRIPT_CACHES_PATH stringByAppendingPathComponent:randomFilename] stringByAppendingString:@".py"]])
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
	NSArray *items = CFBridgingRelease(LSCopyApplicationURLsForURL((__bridge CFURLRef)([NSURL fileURLWithPath:script.path]), kLSRolesEditor));
	if (items.count == 0)
	{
		[[NSWorkspace sharedWorkspace] openFile:script.path withApplication:@"TextEdit"];
	}
	else
	{
		[[NSWorkspace sharedWorkspace] openFile:script.path];
	}
}

+ (void)logPythonObject:(PyObject *)pythonObject
{
	if (pythonObject != NULL)
	{
		PyObject *pythonString = PyObject_Str(pythonObject);
		PyObject *unicodeString = PyUnicode_AsUTF8String(pythonString);
		const char *pythonCString = PyBytes_AsString(unicodeString);
		if (pythonCString != NULL)
		{
			NSString *line = @(pythonCString);
			dispatch_async(dispatch_get_main_queue(), ^{
				[[[ZGAppController sharedController] loggerController] writeLine:line];
			});
		}
		
		Py_XDECREF(unicodeString);
		Py_XDECREF(pythonString);
	}
	
	Py_XDECREF(pythonObject);
}

- (void)logPythonError
{
	PyObject *type, *value, *traceback;
	PyErr_Fetch(&type, &value, &traceback);
	
	dispatch_async(dispatch_get_main_queue(), ^{
		NSString *errorMessage = [NSString stringWithFormat:@"An error occured trying to run the script on %@", self.windowController.currentProcess.name];
		ZGLoggerWindowController *loggerController = [[ZGAppController sharedController] loggerController];
		[loggerController writeLine:errorMessage];
		
		if ((![NSApp isActive] || ![loggerController.window isVisible]))
		{
			ZGDeliverUserNotification(@"Script Failed", nil, errorMessage);
		}
	});
	
	[[self class] logPythonObject:type];
	[[self class] logPythonObject:value];
	
	// Log detailed traceback info including the line where the exception was thrown
	if (traceback != NULL)
	{
		NSString *logPath = [[ZGAppController sharedController] lastErrorLogPath];
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
						[[[ZGAppController sharedController] loggerController] writeLine:latestLog];
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

- (void)watchProcessDied:(NSNotification *)notification
{
	[self.scriptsDictionary enumerateKeysAndObjectsUsingBlock:^(NSValue *variableValue, ZGPyScript *pyScript, BOOL *stop) {
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
		[self.windowController.variablesTableView reloadData];
		[self.windowController markDocumentChange];
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
	
	if (!self.windowController.currentProcess.valid)
	{
		[self disableVariable:variable];
		return;
	}
	
	dispatch_async(gPythonQueue, ^{
		script.module = PyImport_ImportModule([script.moduleName UTF8String]);
		script.module = PyImport_ReloadModule(script.module);
		
		if (script.module == NULL)
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				[self disableVariable:variable];
			});
			[self logPythonError];
			
			return;
		}
		
		PyTypeObject *scriptClassType = (PyTypeObject *)PyObject_GetAttrString(script.module, "Script");
		script.scriptObject = scriptClassType->tp_alloc(scriptClassType, 0);
		
		Py_XDECREF(scriptClassType);
		
		ZGPyVirtualMemory *virtualMemoryInstance = [[ZGPyVirtualMemory alloc] initWithProcess:self.windowController.currentProcess];
		ZGPyDebugger *debuggerInstance = [[ZGPyDebugger alloc] initWithProcess:self.windowController.currentProcess scriptManager:self];
		
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
		
		BOOL stillInitialized = Py_IsInitialized();
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
			
			dispatch_source_set_timer(self.scriptTimer, dispatch_walltime(NULL, 0), 0.03 * NSEC_PER_SEC, 0.01 * NSEC_PER_SEC);
			dispatch_source_set_event_handler(self.scriptTimer, ^{
				for (ZGPyScript *script in self.runningScripts)
				{
					NSTimeInterval currentTime = [NSDate timeIntervalSinceReferenceDate];
					script.deltaTime = currentTime - script.lastTime;
					script.lastTime = currentTime;
					[self executeScript:script];
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
					dispatch_release(self.scriptTimer);
					self.scriptTimer = NULL;
					dispatch_async(dispatch_get_main_queue(), ^{
						if (self.scriptActivity != nil)
						{
							[[NSProcessInfo processInfo] endActivity:self.scriptActivity];
							self.scriptActivity = nil;
						}
						
						[self.windowController updateObservingProcessOcclusionState];
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
						[[ZGAppController sharedController] decreaseLivingCount];
					});
				}
			}
		});
		
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
			if (scriptFinishedCount == script.finishedCount)
			{
				if (delayedAppTermination)
				{
					[[ZGAppController sharedController] decreaseLivingCount];
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

- (void)handleBreakPointFailureWithVariable:(ZGVariable *)variable methodCallResult:(PyObject *)methodCallResult forMethodName:(const char *)methodName shouldStop:(BOOL *)stop
{
	if (methodCallResult == NULL)
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			[[[ZGAppController sharedController] loggerController] writeLine:[NSString stringWithFormat:@"Exception raised in %s callback", methodName]];
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
	
	int numberOfGeneralPurposeEntries = [ZGRegistersController getRegisterEntries:registerEntries fromGeneralPurposeThreadState:breakPoint.generalPurposeThreadState is64Bit:is64Bit];
	
	if (breakPoint.hasVectorState)
	{
		[ZGRegistersController getRegisterEntries:registerEntries + numberOfGeneralPurposeEntries fromVectorThreadState:breakPoint.vectorState is64Bit:is64Bit hasAVXSupport:breakPoint.hasAVXSupport];
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
					[self handleBreakPointFailureWithVariable:[variableValue pointerValue] methodCallResult:result forMethodName:"data watchpoint" shouldStop:stop];
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
					
					[self handleBreakPointFailureWithVariable:[variableValue pointerValue] methodCallResult:result forMethodName:"instruction breakpoint" shouldStop:stop];
					Py_XDECREF(result);
				}
			});
		}];
	});
}

@end
