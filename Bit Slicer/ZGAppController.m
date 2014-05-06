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
#import "ZGProcessTaskManager.h"
#import "ZGDocumentController.h"
#import "ZGHotKeyCenter.h"
#import "ZGAppUpdaterController.h"
#import "ZGAppTerminationState.h"
#import "ZGNavigationPost.h"

#define ZGLoggerIdentifier @"ZGLoggerIdentifier"
#define ZGMemoryViewerIdentifier @"ZGMemoryViewerIdentifier"
#define ZGDebuggerIdentifier @"ZGDebuggerIdentifier"

@interface ZGAppController ()

@property (nonatomic) ZGAppUpdaterController *appUpdaterController;
@property (nonatomic) ZGDocumentController *documentController;
@property (nonatomic) ZGPreferencesController *preferencesController;
@property (nonatomic) ZGMemoryViewerController *memoryViewer;
@property (nonatomic) ZGDebuggerController *debuggerController;
@property (nonatomic) ZGBreakPointController *breakPointController;
@property (nonatomic) ZGLoggerWindowController *loggerWindowController;
@property (nonatomic) ZGProcessTaskManager *processTaskManager;
@property (nonatomic) ZGHotKeyCenter *hotKeyCenter;

@end

@implementation ZGAppController

#pragma mark Birth & Death

- (id)init
{
	self = [super init];
	
	if (self != nil)
	{
		self.appUpdaterController = [[ZGAppUpdaterController alloc] init];
		
		self.processTaskManager = [[ZGProcessTaskManager alloc] init];

		self.hotKeyCenter = [[ZGHotKeyCenter alloc] init];

		self.loggerWindowController = [[ZGLoggerWindowController alloc] init];
		
		self.breakPointController = [ZGBreakPointController sharedController];
		
		self.debuggerController = [[ZGDebuggerController alloc] initWithProcessTaskManager:self.processTaskManager breakPointController:self.breakPointController hotKeyCenter:self.hotKeyCenter loggerWindowController:self.loggerWindowController];
		
		self.memoryViewer = [[ZGMemoryViewerController alloc] initWithProcessTaskManager:self.processTaskManager];
		self.memoryViewer.debuggerController = self.debuggerController;
		
		self.documentController = [[ZGDocumentController alloc] initWithProcessTaskManager:self.processTaskManager debuggerController:self.debuggerController breakPointController:self.breakPointController hotKeyCenter:self.hotKeyCenter loggerWindowController:self.loggerWindowController];
		
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
	}
	
	return self;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)__unused sender
{
	ZGAppTerminationState *appTerminationState = [[ZGAppTerminationState alloc] init];
	
	self.breakPointController.appTerminationState = appTerminationState;
	
	[self.debuggerController cleanup];
	
	for (ZGDocument *document in self.documentController.documents)
	{
		ZGScriptManager *scriptManager = [[document.windowControllers lastObject] scriptManager];
		[scriptManager cleanupWithAppTerminationState:appTerminationState];
	}
	
	return appTerminationState.isDead ? NSTerminateNow : NSTerminateLater;
}

#pragma mark Restoration

+ (void)restoreWindowWithIdentifier:(NSString *)identifier state:(NSCoder *)__unused state completionHandler:(void (^)(NSWindow *, NSError *))completionHandler
{
	ZGAppController *appController = [[NSApplication sharedApplication] delegate];
	
	NSWindowController *restoredWindowController = nil;
	
	if ([identifier isEqualToString:ZGMemoryViewerIdentifier])
	{
		restoredWindowController = appController.memoryViewer;
	}
	else if ([identifier isEqualToString:ZGDebuggerIdentifier])
	{
		restoredWindowController = appController.debuggerController;
	}
	else if ([identifier isEqualToString:ZGLoggerIdentifier])
	{
		restoredWindowController = appController.loggerWindowController;
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
	[self showMemoryWindowController:self.memoryViewer withWindowIdentifier:ZGMemoryViewerIdentifier andCanReadMemory:YES];
}

- (IBAction)openDebugger:(id)__unused sender
{
	[self showMemoryWindowController:self.debuggerController withWindowIdentifier:ZGDebuggerIdentifier andCanReadMemory:YES];
}

- (IBAction)openLogger:(id)__unused sender
{
	[self.loggerWindowController showWindow:nil];
	
	[self setRestorationForWindowController:self.loggerWindowController withWindowIdentifier:ZGLoggerIdentifier];
}

- (IBAction)openPreferences:(id)__unused sender
{
	if (self.preferencesController == nil)
	{
		self.preferencesController = [[ZGPreferencesController alloc] initWithHotKeyCenter:self.hotKeyCenter debuggerController:self.debuggerController appUpdaterController:self.appUpdaterController];
	}
	
	[self.preferencesController showWindow:nil];
}

- (IBAction)checkForUpdates:(id)__unused sender
{
	[self.appUpdaterController checkForUpdates];
}

#pragma mark Notifications

- (void)showWindowControllerNotification:(NSNotification *)notification
{
	ZGProcess *process = [notification.userInfo objectForKey:ZGNavigationProcessKey];
	ZGMemoryAddress address = [[notification.userInfo objectForKey:ZGNavigationMemoryAddressKey] unsignedLongLongValue];
	
	if ([notification.name isEqualToString:ZGNavigationShowDebuggerNotification])
	{
		[self showMemoryWindowController:self.debuggerController withWindowIdentifier:ZGDebuggerIdentifier andCanReadMemory:NO];
		[self.debuggerController jumpToMemoryAddress:address inProcess:process];
	}
	else if ([notification.name isEqualToString:ZGNavigationShowMemoryViewerNotification])
	{
		ZGMemoryAddress selectionLength = [[notification.userInfo objectForKey:ZGNavigationSelectionLengthKey] unsignedLongLongValue];
		
		[self showMemoryWindowController:self.memoryViewer withWindowIdentifier:ZGMemoryViewerIdentifier andCanReadMemory:NO];
		[self.memoryViewer jumpToMemoryAddress:address withSelectionLength:selectionLength inProcess:process];
	}
}

- (void)lastChosenInternalProcessNameChanged:(NSNotification *)notification
{
	NSString *lastChosenInternalProcessName = [notification.userInfo objectForKey:ZGLastChosenInternalProcessNameKey];

	self.documentController.lastChosenInternalProcessName = lastChosenInternalProcessName;

	if (self.debuggerController != notification.object)
	{
		self.debuggerController.lastChosenInternalProcessName = lastChosenInternalProcessName;
	}

	if (self.memoryViewer != notification.object)
	{
		self.memoryViewer.lastChosenInternalProcessName = lastChosenInternalProcessName;
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
