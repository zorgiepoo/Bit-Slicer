/*
 * Copyright (c) 2012 Mayur Pawashe
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

#import <Cocoa/Cocoa.h>

#import "ZGChosenProcessDelegate.h"
#import "ZGMemorySelectionDelegate.h"
#import "ZGShowMemoryWindow.h"
#import "ZGPreferencesController.h"
#import "ZGMemoryViewerController.h"
#import "ZGDebuggerController.h"
#import "ZGBreakPointController.h"
#import "ZGLoggerWindowController.h"
#import "ZGDocument.h"
#import "ZGDocumentWindowController.h"
#import "ZGScriptManager.h"
#import "ZGScriptPrompt.h"
#import "ZGScriptPromptWindowController.h"
#import "ZGProcessTaskManager.h"
#import "ZGRootlessConfiguration.h"
#import "ZGDocumentController.h"
#import "ZGHotKeyCenter.h"
#import "ZGAppUpdaterController.h"
#import "ZGAppTerminationState.h"
#import "ZGScriptingInterpreter.h"
#import "ZGProcess.h"
#import "ZGOperatingSystemCompatibility.h"
#import "ZGAboutWindowController.h"
#import "ZGNullability.h"

#define ZGLoggerIdentifier @"ZGLoggerIdentifier"
#define ZGMemoryViewerIdentifier @"ZGMemoryViewerIdentifier"
#define ZGDebuggerIdentifier @"ZGDebuggerIdentifier"

#define ZGRemoveRootlessProcessesKey @"ZGRemoveRootlessProcessesKey"

@interface ZGAppController : NSObject <NSApplicationDelegate, NSUserNotificationCenterDelegate, ZGChosenProcessDelegate, ZGShowMemoryWindow, ZGMemorySelectionDelegate>

@end

@implementation ZGAppController
{
	ZGAppUpdaterController *_appUpdaterController;
	ZGDocumentController *_documentController;
	ZGPreferencesController *_preferencesController;
	ZGMemoryViewerController *_memoryViewer;
	ZGDebuggerController *_debuggerController;
	ZGBreakPointController *_breakPointController;
	ZGLoggerWindowController *_loggerWindowController;
	ZGProcessTaskManager *_processTaskManager;
	ZGRootlessConfiguration *_rootlessConfiguration;
	ZGHotKeyCenter *_hotKeyCenter;
	ZGScriptingInterpreter *_scriptingInterpreter;
	ZGAboutWindowController *_aboutWindowController;
	
	
	NSString *_lastChosenInternalProcessName;
	NSMutableDictionary *_memorySelectionRanges;
}

#pragma mark Birth & Death

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		if (ZGIsOnElCapitanOrLater())
		{
			[[NSUserDefaults standardUserDefaults] registerDefaults:@{ZGRemoveRootlessProcessesKey: @YES}];
		}
	});
}

- (id)init
{
	self = [super init];
	
	if (self != nil)
	{
		_appUpdaterController = [[ZGAppUpdaterController alloc] init];
		
		_processTaskManager = [[ZGProcessTaskManager alloc] init];
		
		if (ZGIsOnElCapitanOrLater() && [[NSUserDefaults standardUserDefaults] boolForKey:ZGRemoveRootlessProcessesKey])
		{
			_rootlessConfiguration = [[ZGRootlessConfiguration alloc] init];
		}

		_hotKeyCenter = [[ZGHotKeyCenter alloc] init];

		_loggerWindowController = [[ZGLoggerWindowController alloc] init];
		
		_scriptingInterpreter = [ZGScriptingInterpreter createInterpreterOnce];
		
		_breakPointController = [ZGBreakPointController createBreakPointControllerOnceWithScriptingInterpreter:_scriptingInterpreter];
		
		_debuggerController =
		[[ZGDebuggerController alloc]
		 initWithProcessTaskManager:_processTaskManager
		 rootlessConfiguration:_rootlessConfiguration
		 breakPointController:_breakPointController
		 scriptingInterpreter:_scriptingInterpreter
		 hotKeyCenter:_hotKeyCenter
		 loggerWindowController:_loggerWindowController
		 delegate:self];
		
		_memoryViewer =
		[[ZGMemoryViewerController alloc]
		 initWithProcessTaskManager:_processTaskManager
		 rootlessConfiguration:_rootlessConfiguration
		 haltedBreakPoints:_debuggerController.haltedBreakPoints
		 delegate:self];
		
		__weak ZGAppController *weakSelf = self;
		_documentController = [[ZGDocumentController alloc] initWithMakeDocumentWindowController:^ZGDocumentWindowController *{
			ZGAppController *selfReference = weakSelf;
			assert(selfReference != nil);
			
			return
			[[ZGDocumentWindowController alloc]
			 initWithProcessTaskManager:selfReference->_processTaskManager
			 rootlessConfiguration:selfReference->_rootlessConfiguration
			 debuggerController:selfReference->_debuggerController
			 breakPointController:selfReference->_breakPointController
			 scriptingInterpreter:selfReference->_scriptingInterpreter
			 hotKeyCenter:selfReference->_hotKeyCenter
			 loggerWindowController:selfReference->_loggerWindowController
			 lastChosenInternalProcessName:selfReference->_lastChosenInternalProcessName
			 delegate:selfReference];
		}];
		
		[[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];
	}
	
	return self;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)__unused sender
{
	ZGAppTerminationState *appTerminationState = [[ZGAppTerminationState alloc] init];
	
	_breakPointController.appTerminationState = appTerminationState;
	
	[_debuggerController cleanup];
	[_memoryViewer cleanup];
	
	for (ZGDocument *document in _documentController.documents)
	{
		ZGDocumentWindowController *documentWindowController = (ZGDocumentWindowController *)document.windowControllers[0];
		[documentWindowController cleanupWithAppTerminationState:appTerminationState];
	}
	
	return appTerminationState.isDead ? NSTerminateNow : NSTerminateLater;
}

#pragma mark Restoration

+ (void)restoreWindowWithIdentifier:(NSString *)identifier state:(NSCoder *)__unused state completionHandler:(void (^)(NSWindow *, NSError *))completionHandler
{
	ZGAppController *appController = (ZGAppController *)[(NSApplication *)[NSApplication sharedApplication] delegate];
	
	assert([appController isKindOfClass:[ZGAppController class]]);
	
	NSWindowController *restoredWindowController = nil;
	
	if ([identifier isEqualToString:ZGMemoryViewerIdentifier])
	{
		restoredWindowController = appController->_memoryViewer;
	}
	else if ([identifier isEqualToString:ZGDebuggerIdentifier])
	{
		restoredWindowController = appController->_debuggerController;
	}
	else if ([identifier isEqualToString:ZGLoggerIdentifier])
	{
		restoredWindowController = appController->_loggerWindowController;
	}
	
	if (restoredWindowController != nil)
	{
		[appController setRestorationForWindowController:restoredWindowController	withWindowIdentifier:identifier];
		
		completionHandler(restoredWindowController.window, nil);
	}
	else
	{
		NSLog(@"Error: Restored window controller is nil from identifier %@", identifier);
	}
}

- (BOOL)setRestorationForWindowController:(NSWindowController *)windowController withWindowIdentifier:(NSString *)windowIdentifier
{
	BOOL firstTimeLoading = (windowController.window.restorationClass == nil);
	
	if (firstTimeLoading)
	{
		windowController.window.restorationClass = [self class];
		windowController.window.identifier = windowIdentifier;
	}
	
	return firstTimeLoading;
}

#pragma mark Menu Actions

- (void)showMemoryWindowController:(id)memoryWindowController withWindowIdentifier:(NSString *)windowIdentifier andCanReadMemory:(BOOL)canReadMemory
{
	[memoryWindowController showWindow:nil];
	
	BOOL firstTimeLoading = [self setRestorationForWindowController:memoryWindowController withWindowIdentifier:windowIdentifier];
	
	[memoryWindowController updateWindowAndReadMemory:canReadMemory && firstTimeLoading];
}

- (IBAction)openMemoryViewer:(id)__unused sender
{
	[self showMemoryWindowController:_memoryViewer withWindowIdentifier:ZGMemoryViewerIdentifier andCanReadMemory:YES];
}

- (IBAction)openDebugger:(id)__unused sender
{
	[self showMemoryWindowController:_debuggerController withWindowIdentifier:ZGDebuggerIdentifier andCanReadMemory:YES];
}

- (IBAction)openLogger:(id)__unused sender
{
	[_loggerWindowController showWindow:nil];
	
	[self setRestorationForWindowController:_loggerWindowController withWindowIdentifier:ZGLoggerIdentifier];
}

- (IBAction)openPreferences:(id)__unused sender
{
	if (_preferencesController == nil)
	{
		_preferencesController = [[ZGPreferencesController alloc] initWithHotKeyCenter:_hotKeyCenter debuggerController:_debuggerController appUpdaterController:_appUpdaterController];
	}
	
	[_preferencesController showWindow:nil];
}

- (IBAction)checkForUpdates:(id)__unused sender
{
	[_appUpdaterController checkForUpdates];
}

- (IBAction)openAboutWindow:(id)__unused sender
{
	if (_aboutWindowController == nil)
	{
		_aboutWindowController = [[ZGAboutWindowController alloc] init];
	}
	[_aboutWindowController showWindow:nil];
}

#pragma mark Delegate Methods

- (void)showDebuggerWindowWithProcess:(ZGProcess *)process address:(ZGMemoryAddress)address
{
	[self showMemoryWindowController:_debuggerController withWindowIdentifier:ZGDebuggerIdentifier andCanReadMemory:NO];
	[_debuggerController jumpToMemoryAddress:address inProcess:process];
}

- (void)showMemoryViewerWindowWithProcess:(ZGProcess *)process address:(ZGMemoryAddress)address selectionLength:(ZGMemorySize)selectionLength
{
	[self showMemoryWindowController:_memoryViewer withWindowIdentifier:ZGMemoryViewerIdentifier andCanReadMemory:NO];
	[_memoryViewer jumpToMemoryAddress:address withSelectionLength:selectionLength inProcess:process];
}

- (void)memoryWindowController:(ZGMemoryWindowController *)memoryWindowController didChangeProcessInternalName:(NSString *)newChosenInternalProcessName
{
	_lastChosenInternalProcessName = [newChosenInternalProcessName copy];
	
	if (_debuggerController != memoryWindowController)
	{
		_debuggerController.lastChosenInternalProcessName = newChosenInternalProcessName;
	}
	
	if (_memoryViewer != memoryWindowController)
	{
		_memoryViewer.lastChosenInternalProcessName = newChosenInternalProcessName;
	}
}

- (void)memorySelectionDidChange:(NSRange)newMemorySelectionRange process:(ZGProcess *)process
{
	if (_memorySelectionRanges == nil)
	{
		_memorySelectionRanges = [[NSMutableDictionary alloc] init];
	}
	_memorySelectionRanges[@(process.processID)] = [NSValue valueWithRange:newMemorySelectionRange];
}

- (NSRange)lastMemorySelectionForProcess:(ZGProcess *)process
{
	if (_memorySelectionRanges == nil || _memorySelectionRanges[@(process.processID)] == nil)
	{
		return NSMakeRange(0, 0);
	}
	
	return [(NSValue *)(_memorySelectionRanges[@(process.processID)]) rangeValue];
}

#pragma mark User Notifications

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)__unused center shouldPresentNotification:(NSUserNotification *)notification
{
	return [notification.userInfo[ZGScriptNotificationTypeKey] boolValue] || ![NSApp isActive];
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)__unused center didActivateNotification:(NSUserNotification *)notification
{
	if (notification.activationType == NSUserNotificationActivationTypeReplied)
	{
		NSNumber *scriptPromptHash = notification.userInfo[ZGScriptNotificationPromptHashKey];
		if (scriptPromptHash != nil)
		{
			for (ZGDocument *document in _documentController.documents)
			{
				ZGDocumentWindowController *documentWindowController = (ZGDocumentWindowController *)document.windowControllers[0];
				ZGScriptManager *scriptManager = documentWindowController.scriptManager;
				[scriptManager handleScriptPromptHash:scriptPromptHash withUserNotificationReply:notification.response.string];
			}
		}
	}
}

#pragma mark Links

#define WIKI_URL @"https://github.com/zorgiepoo/Bit-Slicer/wiki"
- (IBAction)help:(id)__unused sender
{	
	[[NSWorkspace sharedWorkspace] openURL:ZGUnwrapNullableObject([NSURL URLWithString:WIKI_URL])];
}

#define ISSUES_TRACKER_URL @"https://github.com/zorgiepoo/Bit-Slicer/issues"
- (IBAction)reportABug:(id)__unused sender
{
	[[NSWorkspace sharedWorkspace] openURL:ZGUnwrapNullableObject([NSURL URLWithString:ISSUES_TRACKER_URL])];
}

#define FORUMS_URL @"http://portingteam.com/forum/157-bit-slicer/"
- (IBAction)visitForums:(id)__unused sender
{
	[[NSWorkspace sharedWorkspace] openURL:ZGUnwrapNullableObject([NSURL URLWithString:FORUMS_URL])];
}

#define FEEDBACK_EMAIL @"zorgiepoo@gmail.com"
- (IBAction)sendFeedback:(id)__unused sender
{
	[[NSWorkspace sharedWorkspace] openURL:ZGUnwrapNullableObject([NSURL URLWithString:[@"mailto:" stringByAppendingString:FEEDBACK_EMAIL]])];
}

#define DONATION_URL @"https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=A3DTDV2F3VE5G&lc=US&item_name=Bit%20Slicer%20App&currency_code=USD&bn=PP%2dDonationsBF%3abtn_donate_SM%2egif%3aNonHosted"
- (IBAction)openDonationURL:(id)__unused sender
{
	[[NSWorkspace sharedWorkspace] openURL:ZGUnwrapNullableObject([NSURL URLWithString:DONATION_URL])];
}

@end
