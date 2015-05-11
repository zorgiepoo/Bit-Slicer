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
#import "ZGScriptingInterpreter.h"
#import "ZGLoggerWindowController.h"
#import "ZGVariable.h"
#import "ZGDocumentWindowController.h"
#import "ZGPyScript.h"
#import "ZGPyKeyCodeModule.h"
#import "ZGPyKeyModModule.h"
#import "ZGPyVirtualMemory.h"
#import "ZGPyDebugger.h"
#import "ZGBreakPoint.h"
#import "ZGRegistersState.h"
#import "ZGProcess.h"
#import "ZGPyMainModule.h"
#import "ZGPyVMProtModule.h"
#import "ZGSearchProgress.h"
#import "ZGTableView.h"
#import "ZGUtilities.h"
#import "ZGRegisterEntries.h"
#import "ZGAppTerminationState.h"
#import "ZGAppPathUtilities.h"
#import "ZGScriptPrompt.h"
#import "ZGScriptPromptWindowController.h"

#import "structmember.h"

#define ZGLocalizableScriptManagerString(string) NSLocalizedStringFromTable(string, @"[Code] Script Manager", nil)

NSString *ZGScriptDefaultApplicationEditorKey = @"ZGScriptDefaultApplicationEditorKey";

@interface ZGScriptManager ()

@property (nonatomic) ZGLoggerWindowController *loggerWindowController;
@property (nonatomic) ZGScriptingInterpreter *scriptingInterpreter;

@property (nonatomic) NSMutableDictionary *scriptsDictionary;
@property (nonatomic) VDKQueue *fileWatchingQueue;
@property (nonatomic, assign) ZGDocumentWindowController *windowController;
@property (atomic) dispatch_source_t scriptTimer;
@property (atomic) NSMutableArray *runningScripts;
@property (nonatomic) NSMutableArray *objectsPool;
@property (nonatomic) id scriptActivity;

@property (nonatomic) ZGScriptPromptWindowController *scriptPromptWindowController;

@property (nonatomic) ZGAppTerminationState *appTerminationState;
@property (nonatomic) BOOL delayedAppTermination;

@end

@implementation ZGScriptManager
{
	BOOL _cleanedUp;
	dispatch_queue_t _pythonQueue;
}

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		[[NSUserDefaults standardUserDefaults] registerDefaults:@{ZGScriptDefaultApplicationEditorKey : @""}];
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
		self.loggerWindowController = windowController.loggerWindowController;
		self.scriptingInterpreter = windowController.scriptingInterpreter;
		self.scriptPromptWindowController = [[ZGScriptPromptWindowController alloc] init];
		
		_pythonQueue = self.scriptingInterpreter.pythonQueue;
	}
	return self;
}

- (void)cleanupWithAppTerminationState:(ZGAppTerminationState *)appTerminationState
{
	if (!_cleanedUp)
	{
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
		
		_cleanedUp = YES;
	}
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
		
		dispatch_sync(_pythonQueue, ^{
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

- (void)logPythonObject:(PyObject *)pythonObject
{
	NSString *errorDescription = [self.scriptingInterpreter fetchPythonErrorDescriptionFromObject:pythonObject];
	ZGLoggerWindowController *loggerWindowController = self.loggerWindowController;
	dispatch_async(dispatch_get_main_queue(), ^{
		[loggerWindowController writeLine:errorDescription];
	});
}

- (void)logPythonError
{
	PyObject *type, *value, *traceback;
	PyErr_Fetch(&type, &value, &traceback);
	
	dispatch_async(dispatch_get_main_queue(), ^{
		ZGProcess *process = self.windowController.currentProcess;
		NSString *errorMessage = [NSString stringWithFormat:@"An error occured trying to run the script on %@", process.name];
		[self.loggerWindowController writeLine:errorMessage];
		
		if ((![NSApp isActive] || ![self.loggerWindowController.window isVisible]))
		{
			ZGDeliverUserNotification(ZGLocalizableScriptManagerString(@"scriptFailedNotificationTitle"), nil, [NSString stringWithFormat:ZGLocalizableScriptManagerString(@"scriptFailedNotificationTextFormat"), process.name], nil);
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
	
	dispatch_async(_pythonQueue, ^{
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
		ZGPyDebugger *debuggerInstance = [[ZGPyDebugger alloc] initWithProcess:windowController.currentProcess scriptingInterpreter:self.scriptingInterpreter scriptManager:self breakPointController:self.windowController.breakPointController hotKeyCenter:self.windowController.hotKeyCenter loggerWindowController:windowController.loggerWindowController];
		
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
		
		if (self.scriptTimer == NULL && (self.scriptTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self->_pythonQueue)) != NULL)
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				if ([[NSProcessInfo processInfo] respondsToSelector:@selector(beginActivityWithOptions:reason:)])
				{
					self.scriptActivity = [[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiated reason:@"Script execute timer"];
				}
			});
			
			dispatch_source_set_timer(self.scriptTimer, DISPATCH_TIME_NOW, NSEC_PER_SEC * 3 / 100, NSEC_PER_SEC * 1 / 100);
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
			dispatch_async(_pythonQueue, ^{
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
		
		if ([self hasAttachedPrompt] && self.scriptPromptWindowController.delegate == script.debuggerInstance)
		{
			ZGScriptPrompt *scriptPrompt = self.scriptPromptWindowController.scriptPrompt;
			[self removeUserNotificationsForScriptPrompt:scriptPrompt];
			
			[self.scriptPromptWindowController terminateSession];
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
		
		dispatch_async(_pythonQueue, ^{
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
					
					dispatch_async(self->_pythonQueue, ^{
						scriptCleanup();
					});
				}
			}
		});
	}
}

- (void)handleFailureWithVariable:(ZGVariable *)variable methodCallResult:(PyObject *)methodCallResult forMethodName:(NSString *)methodName
{
	if (methodCallResult == NULL)
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			[self.loggerWindowController writeLine:[NSString stringWithFormat:@"Exception raised in %@", methodName]];
		});
		[self logPythonError];
		dispatch_async(dispatch_get_main_queue(), ^{
			[self stopScriptForVariable:variable];
		});
	}
}

- (BOOL)hasAttachedPrompt
{
	return self.scriptPromptWindowController.isAttached;
}

- (void)showScriptPrompt:(ZGScriptPrompt *)scriptPrompt delegate:(id <ZGScriptPromptDelegate>)delegate
{
	if (![self hasAttachedPrompt])
	{
		ZGDeliverUserNotificationWithReply(ZGLocalizableScriptManagerString(@"scriptPromptNotificationTitle"), self.windowController.currentProcess.name, scriptPrompt.message, scriptPrompt.answer, @{ZGScriptNotificationPromptHashKey : @(scriptPrompt.hash)});
		
		[self.scriptPromptWindowController attachToWindow:self.windowController.window withScriptPrompt:scriptPrompt delegate:delegate];
	}
}

- (void)handleScriptPromptHash:(NSNumber *)scriptPromptHash withUserNotificationReply:(NSString *)reply
{
	if ([scriptPromptHash isEqualToNumber:@(self.scriptPromptWindowController.scriptPrompt.hash)])
	{
		[self.scriptPromptWindowController terminateSessionWithAnswer:reply];
	}
}

- (void)removeUserNotifications:(NSArray *)userNotifications withScriptPrompt:(ZGScriptPrompt *)scriptPrompt
{
	for (NSUserNotification *userNotification in userNotifications)
	{
		NSNumber *scriptPromptHash = userNotification.userInfo[ZGScriptNotificationPromptHashKey];
		if (scriptPromptHash != nil && [scriptPromptHash isEqualToNumber:@(scriptPrompt.hash)])
		{
			[[NSUserNotificationCenter defaultUserNotificationCenter] removeScheduledNotification:userNotification];
		}
	}
}

- (void)removeUserNotificationsForScriptPrompt:(ZGScriptPrompt *)scriptPrompt
{
	NSUserNotificationCenter *userNotificationCenter = [NSUserNotificationCenter defaultUserNotificationCenter];
	[self removeUserNotifications:userNotificationCenter.scheduledNotifications withScriptPrompt:scriptPrompt];
	[self removeUserNotifications:userNotificationCenter.deliveredNotifications withScriptPrompt:scriptPrompt];
}

- (void)handleScriptPrompt:(ZGScriptPrompt *)scriptPrompt withAnswer:(NSString *)answer sender:(id)sender
{
	[self removeUserNotificationsForScriptPrompt:scriptPrompt];
	
	dispatch_async(dispatch_get_main_queue(), ^{
		[self.scriptsDictionary enumerateKeysAndObjectsUsingBlock:^(NSValue *variableValue, ZGPyScript *pyScript, __unused BOOL *stop) {
			dispatch_async(self->_pythonQueue, ^{
				if (Py_IsInitialized() && pyScript.debuggerInstance == sender)
				{
					PyObject *callback = scriptPrompt.userData;
					PyObject *result = (answer != nil) ? PyObject_CallFunction(callback, "s", [answer UTF8String]) : PyObject_CallFunction(callback, "O", Py_None);
					
					[self handleFailureWithVariable:[variableValue pointerValue] methodCallResult:result forMethodName:@"script prompt callback"];
					Py_XDECREF(callback);
					Py_XDECREF(result);
				}
			});
		}];
	});
}

- (void)handleDataAddress:(ZGMemoryAddress)dataAddress accessedFromInstructionAddress:(ZGMemoryAddress)instructionAddress registersState:(ZGRegistersState *)registersState callback:(PyObject *)callback sender:(id)sender
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[self.scriptsDictionary enumerateKeysAndObjectsUsingBlock:^(NSValue *variableValue, ZGPyScript *pyScript, __unused BOOL *stop) {
			dispatch_async(self->_pythonQueue, ^{
				if (Py_IsInitialized() && pyScript.debuggerInstance == sender)
				{
					PyObject *registers = [self.scriptingInterpreter registersfromRegistersState:registersState];
					PyObject *result = PyObject_CallFunction(callback, "KKO", dataAddress, instructionAddress, registers);
					[self handleFailureWithVariable:[variableValue pointerValue] methodCallResult:result forMethodName:@"data watchpoint callback"];
					Py_XDECREF(registers);
					Py_XDECREF(result);
				}
			});
		}];
	});
}

- (void)handleInstructionBreakPoint:(ZGBreakPoint *)breakPoint withRegistersState:(ZGRegistersState *)registersState callback:(PyObject *)callback sender:(id)sender
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[self.scriptsDictionary enumerateKeysAndObjectsUsingBlock:^(NSValue *variableValue, ZGPyScript *pyScript, __unused BOOL *stop) {
			dispatch_async(self->_pythonQueue, ^{
				if (Py_IsInitialized() && pyScript.debuggerInstance == sender)
				{
					PyObject *registers = [self.scriptingInterpreter registersfromRegistersState:registersState];
					PyObject *result = PyObject_CallFunction(callback, "KO", breakPoint.variable.address, registers);
					Py_XDECREF(registers);
					
					[self handleFailureWithVariable:[variableValue pointerValue] methodCallResult:result forMethodName:@"instruction breakpoint callback"];
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
		[self.scriptsDictionary enumerateKeysAndObjectsUsingBlock:^(NSValue *variableValue, ZGPyScript *pyScript, __unused BOOL *stop) {
			dispatch_async(self->_pythonQueue, ^{
				if (Py_IsInitialized() && pyScript.debuggerInstance == sender)
				{
					PyObject *result = PyObject_CallFunction(callback, "I", hotKeyID);
					[self handleFailureWithVariable:[variableValue pointerValue] methodCallResult:result forMethodName:@"hotkey trigger callback"];
					Py_XDECREF(result);
				}
			});
		}];
	});
}

@end
