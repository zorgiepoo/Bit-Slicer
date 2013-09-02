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

#import "ZGScriptManager.h"
#import "ZGVariable.h"
#import "ZGDocumentWindowController.h"
#import "ZGPyScript.h"
#import <Python/Python.h>
#import "ZGPyVirtualMemory.h"
#import "ZGProcess.h"

#define SCRIPT_CACHES_PATH [[[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier]] stringByAppendingPathComponent:@"Scripts_Temp"]

@interface ZGScriptManager ()

@property (nonatomic) NSMutableDictionary *scriptsDictionary;
@property (nonatomic) VDKQueue *fileWatchingQueue;
@property (nonatomic, assign) ZGDocumentWindowController *windowController;
@property dispatch_source_t scriptTimer;
@property NSMutableArray *runningScripts;

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
		
		[ZGPyVirtualMemory loadModule];
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
	}
	return self;
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
		
		if (variable.scriptValue != nil)
		{
			[scriptData appendData:[variable.scriptValue dataUsingEncoding:NSUTF8StringEncoding]];
		}
		else
		{
			NSString *scriptTemplateLines =
				@"#Written by <author>\n\n"
				@"def execute(timeElapsed): pass\n\n"
				@"def finish(): pass\n";
			[scriptData appendData:[scriptTemplateLines dataUsingEncoding:NSUTF8StringEncoding]];
		}
		
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
	[[NSWorkspace sharedWorkspace] openFile:script.path];
}

- (BOOL)executeScript:(ZGPyScript *)script
{	
	PyObject *retValue = NULL;
	
	if (Py_IsInitialized())
	{
		retValue = PyObject_CallFunction(script.executeFunction, "d", script.timeElapsed);
	}
	
	if (retValue == NULL)
	{
		if (Py_IsInitialized())
		{
			PyErr_Print();
		}
		
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
				PyErr_Print();
			}
			else
			{
				script.executeFunction = PyObject_GetAttrString(script.module, "execute");
				if (script.executeFunction != NULL && PyCallable_Check(script.executeFunction))
				{
					script.virtualMemoryInstance = [[ZGPyVirtualMemory alloc] initWithProcessTask:self.windowController.currentProcess.processTask];
					if (script.virtualMemoryInstance != nil)
					{
						PyObject_SetAttrString(script.module, "vm", script.virtualMemoryInstance.vmObject);
						
						script.timeElapsed = 0;
						script.lastTime = 0;
						
						if (self.scriptTimer == NULL)
						{
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
										if (script.lastTime == 0 && script.timeElapsed == 0)
										{
											[self executeScript:script];
											script.lastTime = [NSDate timeIntervalSinceReferenceDate];
										}
										else
										{
											NSTimeInterval currentTime = [NSDate timeIntervalSinceReferenceDate];
											script.timeElapsed += currentTime - script.lastTime;
											script.lastTime = currentTime;
											[self executeScript:script];
										}
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
					}
					else
					{
						dispatch_async(dispatch_get_main_queue(), ^{
							[self disableVariable:variable];
							NSLog(@"Error: Couldn't create ZGPyVirtualMemory instance");
						});
					}
				}
				else
				{
					dispatch_async(dispatch_get_main_queue(), ^{
						[self disableVariable:variable];
						NSLog(@"Error: Couldn't pick up execute() function");
					});
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
			script.executeFunction = NULL;
			
			if (Py_IsInitialized() && script.timeElapsed > 0 && self.windowController.currentProcess.valid)
			{
				PyObject *finishFunction = PyObject_GetAttrString(script.module, "finish");
				if (finishFunction != NULL && PyCallable_Check(finishFunction))
				{
					PyObject *retValue = PyObject_CallFunction(finishFunction, NULL);
					if (retValue == NULL)
					{
						PyErr_Print();
					}
					Py_XDECREF(retValue);
				}
				Py_XDECREF(finishFunction);
			}
			
			script.timeElapsed = 0;
			script.virtualMemoryInstance = nil;
			script.finishedCount++;
		}
	});
	
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_current_queue(), ^{
		if (scriptFinishedCount == script.finishedCount)
		{
			// Give up
			Py_Finalize();
			dispatch_async(gPythonQueue, ^{
				[[self class] initializePythonInterpreter];
			});
		}
	});
}

@end
