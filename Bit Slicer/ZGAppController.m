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
#import "ZGHotKeyController.h"
#import "ZGAppUpdaterController.h"
#import "ZGAppTerminationState.h"

@interface ZGAppController ()

@property (nonatomic) ZGAppUpdaterController *appUpdaterController;
@property (nonatomic) ZGDocumentController *documentController;
@property (nonatomic) ZGPreferencesController *preferencesController;
@property (nonatomic) ZGMemoryViewerController *memoryViewer;
@property (nonatomic) ZGDebuggerController *debuggerController;
@property (nonatomic) ZGBreakPointController *breakPointController;
@property (nonatomic) ZGLoggerWindowController *loggerWindowController;
@property (nonatomic) ZGProcessTaskManager *processTaskManager;
@property (nonatomic) ZGHotKeyController *hotKeyController;

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
		
		self.loggerWindowController = [[ZGLoggerWindowController alloc] init];
		
		self.breakPointController = [ZGBreakPointController sharedController];
		
		self.memoryViewer = [[ZGMemoryViewerController alloc] initWithProcessTaskManager:self.processTaskManager];
		
		self.debuggerController = [[ZGDebuggerController alloc] initWithProcessTaskManager:self.processTaskManager breakPointController:self.breakPointController memoryViewer:self.memoryViewer loggerWindowController:self.loggerWindowController];
		
		self.memoryViewer.debuggerController = self.debuggerController;
		
		self.hotKeyController = [[ZGHotKeyController alloc] initWithProcessTaskManager:self.processTaskManager debuggerController:self.debuggerController];
		
		self.documentController = [[ZGDocumentController alloc] initWithProcessTaskManager:self.processTaskManager debuggerController:self.debuggerController breakPointController:self.breakPointController memoryViewer:self.memoryViewer loggerWindowController:self.loggerWindowController];
	}
	
	return self;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
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

+ (void)restoreWindowWithIdentifier:(NSString *)identifier state:(NSCoder *)state completionHandler:(void (^)(NSWindow *, NSError *))completionHandler
{
	ZGAppController *appController = [NSApp delegate];
	
	if ([identifier isEqualToString:ZGMemoryViewerIdentifier])
	{
		completionHandler(appController.memoryViewer.window, nil);
	}
	else if ([identifier isEqualToString:ZGDebuggerIdentifier])
	{
		completionHandler(appController.debuggerController.window, nil);
	}
	else if ([identifier isEqualToString:ZGLoggerIdentifier])
	{
		completionHandler(appController.loggerWindowController.window, nil);
	}
}

#pragma mark Menu Actions

- (IBAction)openPreferences:(id)sender
{
	if (self.preferencesController == nil)
	{
		self.preferencesController = [[ZGPreferencesController alloc] initWithHotKeyController:self.hotKeyController appUpdaterController:self.appUpdaterController];
	}
	
	[self.preferencesController showWindow:nil];
}

- (IBAction)openMemoryViewer:(id)sender
{
	[self.memoryViewer showWindow:nil];
}

- (IBAction)openDebugger:(id)sender
{
	[self.debuggerController showWindow:nil];
}

- (IBAction)openLogger:(id)sender
{
	[self.loggerWindowController showWindow:nil];
}

- (IBAction)checkForUpdates:(id)sender
{
	[self.appUpdaterController checkForUpdates];
}

#pragma mark Help

#define WIKI_URL @"https://bitbucket.org/zorgiepoo/bit-slicer/wiki"
- (IBAction)help:(id)sender
{	
	[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:WIKI_URL]];
}

#define ISSUES_TRACKER_URL @"https://bitbucket.org/zorgiepoo/bit-slicer/issues"
- (IBAction)reportABug:(id)sender
{
	[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:ISSUES_TRACKER_URL]];
}

#define FORUMS_URL @"http://portingteam.com/forum/157-bit-slicer/"
- (IBAction)visitForums:(id)sender
{
	[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:FORUMS_URL]];
}

#define FEEDBACK_EMAIL @"zorgiepoo@gmail.com"
- (IBAction)sendFeedback:(id)sender
{
	[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:[@"mailto:" stringByAppendingString:FEEDBACK_EMAIL]]];
}

#define DONATION_URL @"https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=A3DTDV2F3VE5G&lc=US&item_name=Bit%20Slicer%20App&currency_code=USD&bn=PP%2dDonationsBF%3abtn_donate_SM%2egif%3aNonHosted"
- (IBAction)openDonationURL:(id)sender
{
	[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:DONATION_URL]];
}

@end
