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
#import <Python/Python.h>
#import "ZGPyVirtualMemory.h"
#import "ZGPyDebugger.h"
#import "ZGProcess.h"
#import "ZGPyMainModule.h"
#import "ZGSearchProgress.h"

#import <Python/structmember.h>

#define SCRIPT_CACHES_PATH [[[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier]] stringByAppendingPathComponent:@"Scripts_Temp"]

@interface ZGScriptManager ()

@property (nonatomic) NSMutableDictionary *scriptsDictionary;
@property (nonatomic) VDKQueue *fileWatchingQueue;
@property (nonatomic, assign) ZGDocumentWindowController *windowController;
@property dispatch_source_t scriptTimer;
@property NSMutableArray *runningScripts;
@property (nonatomic) NSMutableArray *objectsPool;

@end

@implementation ZGScriptManager

static dispatch_queue_t gPythonQueue;

+ (void)initializePythonInterpreter
{
	dispatch_async(gPythonQueue, ^{
		Py_Initialize();
		PyObject *sys = PyImport_ImportModule("sys");
		PyObject *path = PyObject_GetAttrString(sys, "path");
		PyList_Append(path, PyString_FromString((char *)[SCRIPT_CACHES_PATH UTF8String]));
		
		Py_XDECREF(sys);
		Py_XDECREF(path);
		
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
		
		if ([[NSFileManager defaultManager] fileExistsAtPath:SCRIPT_CACHES_PATH])
		{
			[[NSFileManager defaultManager] removeItemAtPath:SCRIPT_CACHES_PATH error:nil];
		}
		
		[[NSFileManager defaultManager] createDirectoryAtPath:SCRIPT_CACHES_PATH withIntermediateDirectories:YES attributes:nil error:nil];
		
		gPythonQueue = dispatch_queue_create(NULL, DISPATCH_QUEUE_SERIAL);
		
		setenv("PYTHONDONTWRITEBYTECODE", "1", 1);
		
		[self initializePythonInterpreter];
	});
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
		self.objectsPool = [[NSMutableArray alloc] init];
	}
	return self;
}

- (void)cleanup
{
	[self.scriptsDictionary enumerateKeysAndObjectsUsingBlock:^(NSValue *variableValue, ZGPyScript *pyScript, BOOL *stop) {
		if ([self.runningScripts containsObject:pyScript])
		{
			[self stopScriptForVariable:[variableValue pointerValue]];
		}
	}];
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
		unsigned int randomInteger = rand() % INT32_MAX;
		unsigned int randomInteger2 = rand() % INT32_MAX;
		
		NSMutableString *randomFilename = [NSMutableString stringWithFormat:@"%u%u", randomInteger, randomInteger2];
		while ([[NSFileManager defaultManager] fileExistsAtPath:[[SCRIPT_CACHES_PATH stringByAppendingPathComponent:randomFilename] stringByAppendingString:@".py"]])
		{
			[randomFilename appendString:@"1"];
		}
		
		[randomFilename appendString:@".py"];
		
		NSMutableData *scriptData = [NSMutableData data];
		
		[scriptData appendData:[variable.scriptValue dataUsingEncoding:NSUTF8StringEncoding]];
		
		NSString *scriptPath = [SCRIPT_CACHES_PATH stringByAppendingPathComponent:randomFilename];
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

- (void)logPythonObject:(PyObject *)pythonObject
{
	if (pythonObject != NULL)
	{
		PyObject *pythonString = PyObject_Str(pythonObject);
		const char *pythonCString = PyString_AsString(pythonString);
		if (pythonCString != NULL)
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				[[[ZGAppController sharedController] loggerController] writeLine:@(pythonCString)];
			});
		}
		
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
		
		if (![NSApp isActive] && NSClassFromString(@"NSUserNotification") != nil)
		{
			NSUserNotification *userNotification = [[NSUserNotification alloc] init];
			userNotification.title = @"Script Failed";
			userNotification.informativeText = errorMessage;
			[[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:userNotification];
		}
	});
	
	[self logPythonObject:type];
	[self logPythonObject:value];
	[self logPythonObject:traceback];
}

- (BOOL)executeScript:(ZGPyScript *)script
{	
	PyObject *retValue = NULL;
	
	if (Py_IsInitialized())
	{
		retValue = PyObject_CallMethod(script.scriptObject, "execute", "d", script.timeElapsed);
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
		[self stopScriptForVariable:[variableValue pointerValue]];
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

- (void)runScriptForVariable:(ZGVariable *)variable
{
	ZGPyScript *script = [self scriptForVariable:variable];
	
	if (!self.windowController.currentProcess.valid)
	{
		[self disableVariable:variable];
	}
	else
	{
		dispatch_async(gPythonQueue, ^{
			script.module = PyImport_ImportModule([script.moduleName UTF8String]);
			script.module = PyImport_ReloadModule(script.module);
			
			if (script.module == NULL)
			{
				dispatch_async(dispatch_get_main_queue(), ^{
					[self disableVariable:variable];
				});
				[self logPythonError];
			}
			else
			{
				PyTypeObject *scriptClassType = (PyTypeObject *)PyObject_GetAttrString(script.module, "Script");
				script.scriptObject = scriptClassType->tp_alloc(scriptClassType, 0);
				
				Py_XDECREF(scriptClassType);
				
				script.virtualMemoryInstance = [[ZGPyVirtualMemory alloc] initWithProcessTask:self.windowController.currentProcess.processTask is64Bit:self.windowController.currentProcess.is64Bit objectsPool:self.objectsPool];
				
				script.debuggerInstance = [[ZGPyDebugger alloc] initWithProcessTask:self.windowController.currentProcess.processTask is64Bit:self.windowController.currentProcess.is64Bit scriptManager:self];
				
				if (script.virtualMemoryInstance == nil || script.debuggerInstance == nil)
				{
					dispatch_async(dispatch_get_main_queue(), ^{
						[self disableVariable:variable];
						NSLog(@"Error: Couldn't create VM or Debug instance");
					});
				}
				else
				{
					PyObject_SetAttrString(script.module, "vm", script.virtualMemoryInstance.vmObject);
					PyObject_SetAttrString(script.module, "debug", script.debuggerInstance.object);
					
					PyObject *initMethodResult = PyObject_CallMethod(script.scriptObject, "__init__", NULL);
					BOOL stillInitialized = Py_IsInitialized();
					if (initMethodResult == NULL || !stillInitialized)
					{
						if (stillInitialized)
						{
							[self logPythonError];
						}
						
						script.scriptObject = NULL;
						
						dispatch_async(dispatch_get_main_queue(), ^{
							[self disableVariable:variable];
						});
					}
					else
					{
						script.lastTime = [NSDate timeIntervalSinceReferenceDate];
						script.timeElapsed = 0;
						
						self.scriptTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gPythonQueue);
						
						if (self.scriptTimer == NULL)
						{
							dispatch_async(dispatch_get_main_queue(), ^{
								[self disableVariable:variable];
							});
						}
						else
						{
							if (self.runningScripts == nil)
							{
								self.runningScripts = [[NSMutableArray alloc] init];
							}
							
							[self.runningScripts addObject:script];
							
							dispatch_source_set_timer(self.scriptTimer, dispatch_walltime(NULL, 0), 0.03 * NSEC_PER_SEC, 0.01 * NSEC_PER_SEC);
							dispatch_source_set_event_handler(self.scriptTimer, ^{
								for (ZGPyScript *script in self.runningScripts)
								{
									NSTimeInterval currentTime = [NSDate timeIntervalSinceReferenceDate];
									script.timeElapsed += currentTime - script.lastTime;
									script.lastTime = currentTime;
									[self executeScript:script];
								}
							});
							dispatch_resume(self.scriptTimer);
							
							dispatch_async(dispatch_get_main_queue(), ^{
								[[NSNotificationCenter defaultCenter]
								 addObserver:self
								 selector:@selector(watchProcessDied:)
								 name:ZGTargetProcessDiedNotification
								 object:self.windowController.currentProcess];
							});
						}
					}
					
					Py_XDECREF(initMethodResult);
				}
			}
		});
	}
}

- (void)removeScriptForVariable:(ZGVariable *)variable
{
	[self.scriptsDictionary removeObjectForKey:[NSValue valueWithNonretainedObject:variable]];
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
				}
			});
			
			[[NSNotificationCenter defaultCenter] removeObserver:self];
		}
	}
	
	NSUInteger scriptFinishedCount = script.finishedCount;
	
	dispatch_async(gPythonQueue, ^{
		if (script.finishedCount == scriptFinishedCount)
		{
			if (Py_IsInitialized() && script.timeElapsed > 0 && self.windowController.currentProcess.valid && script.scriptObject != NULL)
			{
				PyObject *retValue = PyObject_CallMethod(script.scriptObject, "finish", NULL);
				if (Py_IsInitialized())
				{
					if (retValue == NULL)
					{
						[self logPythonError];
					}
					Py_XDECREF(retValue);
				}
			}
			
			script.timeElapsed = 0;
			script.virtualMemoryInstance = nil;
			script.debuggerInstance = nil;
			script.scriptObject = NULL;
			script.finishedCount++;
		}
	});
	
	@synchronized(self.objectsPool)
	{
		for (id object in self.objectsPool)
		{
			if ([object isKindOfClass:[ZGSearchProgress class]])
			{
				[object setShouldCancelSearch:YES];
			}
		}
	}
	
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_current_queue(), ^{
		if (scriptFinishedCount == script.finishedCount)
		{
			// Give up
			Py_Finalize();
			dispatch_async(gPythonQueue, ^{
				@synchronized(self.objectsPool)
				{
					[self.objectsPool removeAllObjects];
				}
				[[self class] initializePythonInterpreter];
			});
		}
	});
}

- (void)handleBreakPointDataAddress:(ZGMemoryAddress)dataAddress instructionAddress:(ZGMemoryAddress)instructionAddress sender:(id)sender
{
	[self.scriptsDictionary enumerateKeysAndObjectsUsingBlock:^(NSValue *variableValue, ZGPyScript *pyScript, BOOL *stop) {
		dispatch_async(gPythonQueue, ^{
			if (Py_IsInitialized() && pyScript.debuggerInstance == sender)
			{
				PyObject *result = PyObject_CallMethod(pyScript.scriptObject, "dataAccessed", "KK", dataAddress, instructionAddress);
				if (result == NULL)
				{
					[self stopScriptForVariable:[variableValue pointerValue]];
					*stop = YES;
				}
				Py_XDECREF(result);
			}
		});
	}];
}

@end
