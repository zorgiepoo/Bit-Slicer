/*
 * Created by Mayur Pawashe on 2/5/10.
 *
 * Copyright (c) 2012 zgcoder
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

#import "ZGAppController.h"
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
#import "ZGLocalProcessTaskManager.h"
#import "ZGRemoteProcessTaskManager.h"
#import "ZGDocumentController.h"
#import "ZGHotKeyCenter.h"
#import "ZGAppUpdaterController.h"
#import "ZGAppTerminationState.h"
#import "ZGNavigationPost.h"
#import "ZGAppServer.h"
#import "ZGAppClient.h"

#define ZGLoggerIdentifier @"ZGLoggerIdentifier"
#define ZGMemoryViewerIdentifier @"ZGMemoryViewerIdentifier"
#define ZGDebuggerIdentifier @"ZGDebuggerIdentifier"

@implementation ZGAppController
{
	ZGAppUpdaterController *_appUpdaterController;
	ZGDocumentController *_documentController;
	ZGPreferencesController *_preferencesController;
	ZGMemoryViewerController *_memoryViewer;
	ZGDebuggerController *_debuggerController;
	ZGBreakPointController *_breakPointController;
	ZGLoggerWindowController *_loggerWindowController;
	ZGHotKeyCenter *_hotKeyCenter;
	id <ZGProcessTaskManager> _localProcessTaskManager;
	id <ZGProcessTaskManager> _remoteProcessTaskManager;
	ZGAppServer *_appServer;
	ZGAppClient *_appClient;
}

#pragma mark Birth & Death

- (id)init
{
	self = [super init];
	
	if (self != nil)
	{
		_appUpdaterController = [[ZGAppUpdaterController alloc] init];
		
		_localProcessTaskManager = [[ZGLocalProcessTaskManager alloc] init];

		_hotKeyCenter = [[ZGHotKeyCenter alloc] init];

		_loggerWindowController = [[ZGLoggerWindowController alloc] init];
		
		_breakPointController = [[ZGBreakPointController alloc] initWithProcessTaskManager:_localProcessTaskManager];
		
		_debuggerController = [[ZGDebuggerController alloc] initWithProcessTaskManager:_localProcessTaskManager breakPointController:_breakPointController hotKeyCenter:_hotKeyCenter loggerWindowController:_loggerWindowController];
		
		_memoryViewer = [[ZGMemoryViewerController alloc] initWithProcessTaskManager:_localProcessTaskManager];
		_memoryViewer.debuggerController = _debuggerController;
		
		_documentController = [[ZGDocumentController alloc] initWithProcessTaskManager:_localProcessTaskManager debuggerController:_debuggerController breakPointController:_breakPointController hotKeyCenter:_hotKeyCenter loggerWindowController:_loggerWindowController];
		
		[[NSNotificationCenter defaultCenter]
		 addObserver:self
		 selector:@selector(showWindowControllerNotification:)
		 name:ZGNavigationShowMemoryViewerNotification
		 object:nil];

		[[NSNotificationCenter defaultCenter]
		 addObserver:self
		 selector:@selector(showWindowControllerNotification:)
		 name:ZGNavigationShowDebuggerNotification
		 object:nil];

		[[NSNotificationCenter defaultCenter]
		 addObserver:self
		 selector:@selector(lastChosenInternalProcessNameChanged:)
		 name:ZGLastChosenInternalProcessNameNotification
		 object:nil];
		
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
		ZGDocumentWindowController *documentWindowController = document.windowControllers.firstObject;
		[documentWindowController.scriptManager cleanupWithAppTerminationState:appTerminationState];
		[documentWindowController cleanup];
	}
	
	return appTerminationState.isDead ? NSTerminateNow : NSTerminateLater;
}

#pragma mark Restoration

+ (void)restoreWindowWithIdentifier:(NSString *)identifier state:(NSCoder *)__unused state completionHandler:(void (^)(NSWindow *, NSError *))completionHandler
{
	ZGAppController *appController = (ZGAppController *)[[NSApplication sharedApplication] delegate];
	
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
		windowController.window.restorationClass = self.class;
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

- (IBAction)startServer:(id)__unused sender
{
	if (_appServer == nil)
	{
		_appServer = [[ZGAppServer alloc] initWithProcessTaskManager:_localProcessTaskManager];
	}
	
	[_appServer start];
}

- (IBAction)startClient:(id)__unused sender
{
	if (_appClient == nil)
	{
		_appClient = [[ZGAppClient alloc] initWithHost:@"127.0.0.1"];
	}
	
	[_appClient connect];
	
	if ([_appClient connected])
	{
		_remoteProcessTaskManager = [[ZGRemoteProcessTaskManager alloc] initWithAppClient:_appClient];
		_documentController.processTaskManager = _remoteProcessTaskManager;
	}
}

- (IBAction)checkForUpdates:(id)__unused sender
{
	[_appUpdaterController checkForUpdates];
}

#pragma mark Notifications

- (void)showWindowControllerNotification:(NSNotification *)notification
{
	ZGProcess *process = [notification.userInfo objectForKey:ZGNavigationProcessKey];
	ZGMemoryAddress address = [[notification.userInfo objectForKey:ZGNavigationMemoryAddressKey] unsignedLongLongValue];
	
	if ([notification.name isEqualToString:ZGNavigationShowDebuggerNotification])
	{
		[self showMemoryWindowController:_debuggerController withWindowIdentifier:ZGDebuggerIdentifier andCanReadMemory:NO];
		[_debuggerController jumpToMemoryAddress:address inProcess:process];
	}
	else if ([notification.name isEqualToString:ZGNavigationShowMemoryViewerNotification])
	{
		ZGMemoryAddress selectionLength = [[notification.userInfo objectForKey:ZGNavigationSelectionLengthKey] unsignedLongLongValue];
		
		[self showMemoryWindowController:_memoryViewer withWindowIdentifier:ZGMemoryViewerIdentifier andCanReadMemory:NO];
		[_memoryViewer jumpToMemoryAddress:address withSelectionLength:selectionLength inProcess:process];
	}
}

- (void)lastChosenInternalProcessNameChanged:(NSNotification *)notification
{
	NSString *lastChosenInternalProcessName = [notification.userInfo objectForKey:ZGLastChosenInternalProcessNameKey];

	_documentController.lastChosenInternalProcessName = lastChosenInternalProcessName;

	if (_debuggerController != notification.object)
	{
		_debuggerController.lastChosenInternalProcessName = lastChosenInternalProcessName;
	}

	if (_memoryViewer != notification.object)
	{
		_memoryViewer.lastChosenInternalProcessName = lastChosenInternalProcessName;
	}
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
				ZGDocumentWindowController *documentWindowController = [document.windowControllers firstObject];
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
	[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:WIKI_URL]];
}

#define ISSUES_TRACKER_URL @"https://github.com/zorgiepoo/Bit-Slicer/issues"
- (IBAction)reportABug:(id)__unused sender
{
	[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:ISSUES_TRACKER_URL]];
}

#define FORUMS_URL @"http://portingteam.com/forum/157-bit-slicer/"
- (IBAction)visitForums:(id)__unused sender
{
	[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:FORUMS_URL]];
}

#define FEEDBACK_EMAIL @"zorgiepoo@gmail.com"
- (IBAction)sendFeedback:(id)__unused sender
{
	[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:[@"mailto:" stringByAppendingString:FEEDBACK_EMAIL]]];
}

#define DONATION_URL @"https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=A3DTDV2F3VE5G&lc=US&item_name=Bit%20Slicer%20App&currency_code=USD&bn=PP%2dDonationsBF%3abtn_donate_SM%2egif%3aNonHosted"
- (IBAction)openDonationURL:(id)__unused sender
{
	[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:DONATION_URL]];
}

@end
