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
 *
 * ZGAppController
 * --------------
 * This class serves as the main application controller for Bit Slicer, coordinating
 * between various components and managing the application lifecycle. It handles:
 *
 * - Application initialization and termination
 * - Window management and restoration
 * - Menu actions and user interface coordination
 * - Process selection and memory viewing
 * - User notifications
 *
 * Application Component Relationships:
 * +------------------------+     +------------------------+     +------------------------+
 * |    ZGAppController     |     |  Document Controllers  |     |  Specialized Windows  |
 * |------------------------|     |------------------------|     |------------------------|
 * | - Initializes core     |     | - ZGDocumentController |     | - ZGMemoryViewer      |
 * |   components           | --> | - ZGDocumentWindow     | --> | - ZGDebugger          |
 * | - Manages app lifecycle|     |   Controller           |     | - ZGLogger            |
 * | - Coordinates between  |     | - Manages document     |     | - ZGPreferences       |
 * |   components           |     |   windows              |     | - ZGAbout             |
 * +------------------------+     +------------------------+     +------------------------+
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
#import "ZGAboutWindowController.h"
#import "ZGNullability.h"

#define ZGLoggerIdentifier @"ZGLoggerIdentifier"
#define ZGMemoryViewerIdentifier @"ZGMemoryViewerIdentifier"
#define ZGDebuggerIdentifier @"ZGDebuggerIdentifier"

#define ZGRemoveRootlessProcessesKey @"ZGRemoveRootlessProcessesKey"

@interface ZGAppController : NSObject <NSApplicationDelegate, NSUserNotificationCenterDelegate, NSWindowRestoration, ZGChosenProcessDelegate, ZGShowMemoryWindow, ZGMemorySelectionDelegate>

@end

@implementation ZGAppController
{
	ZGAppUpdaterController * _Nonnull _appUpdaterController;
	ZGDocumentController * _Nonnull _documentController;
	ZGPreferencesController * _Nullable _preferencesController;
	ZGMemoryViewerController * _Nonnull _memoryViewer;
	ZGDebuggerController * _Nonnull _debuggerController;
	ZGBreakPointController * _Nonnull _breakPointController;
	ZGLoggerWindowController * _Nonnull _loggerWindowController;
	ZGProcessTaskManager * _Nonnull _processTaskManager;
	ZGRootlessConfiguration * _Nullable _rootlessConfiguration;
	ZGHotKeyCenter * _Nonnull _hotKeyCenter;
	ZGScriptingInterpreter * _Nonnull _scriptingInterpreter;
	ZGAboutWindowController * _Nullable _aboutWindowController;

	NSString * _Nullable _lastChosenInternalProcessName;
	NSMutableDictionary<NSNumber *, NSValue *> * _Nullable _memorySelectionRanges;

	BOOL _creatingNewTab;
	IBOutlet NSMenu * _Nonnull _fileMenu;
	IBOutlet NSMenuItem * _Nonnull _newDocumentMenuItem;
	IBOutlet NSMenuItem * _Nonnull _showFontsMenuItem;

	IBOutlet NSMenuItem * _Nonnull _checkForUpdatesMenuItem;
}

#pragma mark Birth & Death

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		if (@available(macOS 10.11, *))
		{
			[[NSUserDefaults standardUserDefaults] registerDefaults:@{ZGRemoveRootlessProcessesKey: @YES}];
		}
	});
}

/**
 * Initializes the application controller and all core components
 *
 * This method creates and configures all the main controllers and components
 * needed by the application, establishing their relationships and dependencies.
 * The initialization sequence is important as some components depend on others.
 *
 * @return The initialized application controller
 */
- (id)init
{
	self = [super init];

	if (self != nil)
	{
		_appUpdaterController = [[ZGAppUpdaterController alloc] init];

		_processTaskManager = [[ZGProcessTaskManager alloc] init];

		if (@available(macOS 10.11, *))
		{
			if ([[NSUserDefaults standardUserDefaults] boolForKey:ZGRemoveRootlessProcessesKey])
			{
				_rootlessConfiguration = [[ZGRootlessConfiguration alloc] init];
			}
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

			BOOL creatingNewTab = selfReference->_creatingNewTab;
			selfReference->_creatingNewTab = NO;

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
			 preferringNewTab:creatingNewTab
			 delegate:selfReference];
		}];

		[[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];
	}

	return self;
}

/**
 * Handles application termination requests
 *
 * This method is called when the user attempts to quit the application. It:
 * 1. Creates a termination state object to track cleanup progress
 * 2. Notifies the breakpoint controller about termination
 * 3. Cleans up the debugger and memory viewer
 * 4. Cleans up all document windows
 * 5. Returns whether the app can terminate immediately or should wait
 *
 * @param sender The application requesting termination
 * @return NSTerminateNow if all cleanup is complete, NSTerminateLater if cleanup is still in progress
 */
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

#pragma mark Tabs

- (void)applicationDidFinishLaunching:(NSNotification *)__unused notification
{
	// Add New Tab menu item only if we are on 10.12 or later
	if (@available(macOS 10.12, *))
	{
		// New Tab should use cmd t so make show font use cmd shift t
		[_showFontsMenuItem setKeyEquivalent:@"T"];

		NSMenuItem *newTabMenuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"New Tab", nil) action:@selector(createNewTabbedWindow:) keyEquivalent:@"t"];

		[newTabMenuItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
		[newTabMenuItem setTarget:self];

		NSInteger insertionIndex = [_fileMenu indexOfItem:_newDocumentMenuItem] + 1;
		[_fileMenu insertItem:newTabMenuItem atIndex:insertionIndex];
	}

	[_appUpdaterController configureCheckForUpdatesMenuItem:_checkForUpdatesMenuItem];
}

- (IBAction)createNewTabbedWindow:(id)sender
{
	_creatingNewTab = YES;
	[_documentController newDocument:sender];
}

#pragma mark Restoration

/**
 * Restores a window when the application is relaunched
 *
 * This class method is called by the system during application launch to restore
 * windows that were open when the application was last quit. It maps window identifiers
 * to the appropriate window controllers and restores their state.
 *
 * Window Restoration Process:
 * +------------------------+     +------------------------+     +------------------------+
 * | Identify Window Type   |     | Get Window Controller  |     | Complete Restoration  |
 * |------------------------|     |------------------------|     |------------------------|
 * | - Check identifier     |     | - Memory Viewer        |     | - Set restoration     |
 * |   against known types  | --> | - Debugger             | --> |   properties          |
 * | - Map to controller    |     | - Logger               |     | - Call completion     |
 * |   type                 |     |                        |     |   handler             |
 * +------------------------+     +------------------------+     +------------------------+
 *
 * @param identifier The window's unique identifier
 * @param state The encoded state information (unused)
 * @param completionHandler Block to call with the restored window or error
 */
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
		completionHandler(nil, nil);
	}
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)application
{
	return YES;
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

/**
 * Shows a memory-related window controller and configures it for restoration
 *
 * This method is a helper for displaying memory-related windows (like the memory viewer
 * or debugger). It shows the window, sets up window restoration, and updates the window
 * content if needed.
 *
 * @param memoryWindowController The window controller to show
 * @param windowIdentifier A unique identifier for window restoration
 * @param canReadMemory Whether the window should read memory when first shown
 */
- (void)showMemoryWindowController:(ZGMemoryNavigationWindowController *)memoryWindowController withWindowIdentifier:(NSString *)windowIdentifier andCanReadMemory:(BOOL)canReadMemory
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

	return _memorySelectionRanges[@(process.processID)].rangeValue;
}

#pragma mark User Notifications

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)__unused center shouldPresentNotification:(NSUserNotification *)notification
{
	return [(NSNumber *)notification.userInfo[ZGScriptNotificationTypeKey] boolValue] || ![NSApp isActive];
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

@end
