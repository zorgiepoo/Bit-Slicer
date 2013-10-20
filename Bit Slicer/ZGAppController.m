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
#import "ZGProcess.h"
#import "ZGProcessList.h"
#import "ZGRunningProcess.h"
#import "ZGVirtualMemory.h"
#import "ZGVirtualMemoryHelpers.h"

@interface ZGAppController ()

@property (nonatomic) ZGPreferencesController *preferencesController;
@property (nonatomic) ZGMemoryViewerController *memoryViewer;
@property (nonatomic) ZGDebuggerController *debuggerController;
@property (nonatomic) ZGBreakPointController *breakPointController;
@property (nonatomic) ZGLoggerWindowController *loggerController;

@end

@implementation ZGAppController

#pragma mark Singleton & Accessors

+ (BOOL)isRunningOnAtLeastMajorVersion:(SInt32)majorVersion minorVersion:(SInt32)minorVersion
{
	SInt32 actualMajorVersion;
	SInt32 actualMinorVersion;
	
	if (Gestalt(gestaltSystemVersionMajor, &actualMajorVersion) != noErr)
	{
		return NO;
	}
	
	if (Gestalt(gestaltSystemVersionMinor, &actualMinorVersion) != noErr)
	{
		return NO;
	}
	
	return actualMajorVersion > majorVersion || (actualMajorVersion == majorVersion && actualMinorVersion >= minorVersion);
}

+ (BOOL)isRunningOnLionOrLater
{
	return [self isRunningOnAtLeastMajorVersion:10 minorVersion:7];
}

+ (id)sharedController
{
	return [NSApp delegate];
}

- (ZGBreakPointController *)breakPointController
{
	if (!_breakPointController)
	{
		self.breakPointController = [[ZGBreakPointController alloc] init];
	}
	
	return _breakPointController;
}

+ (void)initialize
{
	static dispatch_once_t onceToken = 0;
	dispatch_once(&onceToken, ^{
		// ensure user defaults are initialized
		[ZGPreferencesController class];
	});
}

- (id)init
{
	self = [super init];
	
	if (self)
	{
		[[ZGProcessList sharedProcessList]
		 addObserver:self
		 forKeyPath:@"runningProcesses"
		 options:NSKeyValueObservingOptionOld
		 context:NULL];
	}
	
	return self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (object == [ZGProcessList sharedProcessList])
	{
		NSArray *oldRunningProcesses = [change objectForKey:NSKeyValueChangeOldKey];
		
		if (oldRunningProcesses)
		{
			for (ZGRunningProcess *runningProcess in oldRunningProcesses)
			{
				ZGMemoryMap task;
				if (ZGTaskExistsForProcess(runningProcess.processIdentifier, &task))
				{
					ZGFreeTask(task);
				}
			}
		}
	}
}

#pragma mark Pausing and Unpausing processes

OSStatus pauseOrUnpauseHotKeyHandler(EventHandlerCallRef nextHandler,EventRef theEvent, void *userData)
{
	for (NSRunningApplication *runningApplication in NSWorkspace.sharedWorkspace.runningApplications)
	{
		if (runningApplication.isActive && runningApplication.processIdentifier != getpid() && ![[[ZGAppController sharedController] debuggerController] isProcessIdentifierHalted:runningApplication.processIdentifier])
		{
			ZGMemoryMap processTask = 0;
			if (ZGGetTaskForProcess(runningApplication.processIdentifier, &processTask))
			{
				[ZGProcess pauseOrUnpauseProcessTask:processTask];
			}
			else
			{
				NSLog(@"Failed to pause/unpause process with pid %d", runningApplication.processIdentifier);
			}
		}
	}
	
	return noErr;
}

static EventHotKeyRef hotKeyRef;
static BOOL didRegisteredHotKey;
+ (void)registerPauseAndUnpauseHotKey
{
	if (didRegisteredHotKey)
	{
		UnregisterEventHotKey(hotKeyRef);
	}
	
	NSNumber *hotKeyCodeNumber = [NSUserDefaults.standardUserDefaults objectForKey:ZG_HOT_KEY];
	NSNumber *hotKeyModifier = [NSUserDefaults.standardUserDefaults objectForKey:ZG_HOT_KEY_MODIFIER];
    
	if (hotKeyCodeNumber && hotKeyCodeNumber.integerValue > INVALID_KEY_CODE)
	{
		EventTypeSpec eventType;
		eventType.eventClass = kEventClassKeyboard;
		eventType.eventKind = kEventHotKeyPressed;
		
		InstallApplicationEventHandler(&pauseOrUnpauseHotKeyHandler, 1, &eventType, NULL, NULL);
		
		EventHotKeyID hotKeyID;
		hotKeyID.signature = 'htk1';
		hotKeyID.id = 1;
		
		RegisterEventHotKey(hotKeyCodeNumber.intValue, hotKeyModifier.intValue, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef);
		
		didRegisteredHotKey = YES;
	}
}

#pragma mark Controller behavior

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	// Initialize preference defaults
	[self openPreferences:nil showWindow:NO];
    
	[self.class registerPauseAndUnpauseHotKey];
}

#pragma mark Actions

+ (void)restoreWindowWithIdentifier:(NSString *)identifier state:(NSCoder *)state completionHandler:(void (^)(NSWindow *, NSError *))completionHandler
{
	if ([identifier isEqualToString:ZGMemoryViewerIdentifier])
	{
		[self.sharedController
		 openMemoryViewer:nil
		 showWindow:NO];
        
		completionHandler([[[self sharedController] memoryViewer] window], nil);
	}
	else if ([identifier isEqualToString:ZGDebuggerIdentifier])
	{
		[self.sharedController
		 openDebugger:nil
		 showWindow:NO];
		
		completionHandler([[[self sharedController] debuggerController] window], nil);
	}
}

- (ZGPreferencesController *)preferencesController
{
	if (!_preferencesController)
	{
		_preferencesController = [[ZGPreferencesController alloc] init];
	}
	return _preferencesController;
}

- (void)openPreferences:(id)sender showWindow:(BOOL)shouldShowWindow
{
	// Testing for preferencesController will ensure it'll be allocated
	if (self.preferencesController && shouldShowWindow)
	{
		[self.preferencesController showWindow:nil];
	}
}

- (IBAction)openPreferences:(id)sender
{
	[self openPreferences:sender showWindow:YES];
}

- (ZGMemoryViewerController *)memoryViewer
{
	if (!_memoryViewer)
	{
		_memoryViewer = [[ZGMemoryViewerController alloc] init];
	}
	return _memoryViewer;
}

- (void)openMemoryViewer:(id)sender showWindow:(BOOL)shouldShowWindow
{
	// Testing for memoryViewer will ensure it'll be allocated
	if (self.memoryViewer && shouldShowWindow)
	{
		[self.memoryViewer showWindow:nil];
	}
}

- (IBAction)openMemoryViewer:(id)sender
{
	[self openMemoryViewer:sender showWindow:YES];
}

- (void)openDebugger:(id)sender showWindow:(BOOL)shouldShowWindow
{
	// Testing for debuggerController will ensure it'll be allocated
	if (self.debuggerController && shouldShowWindow)
	{
		[self.debuggerController showWindow:nil];
	}
}

- (ZGDebuggerController *)debuggerController
{
	if (!_debuggerController)
	{
		_debuggerController = [[ZGDebuggerController alloc] init];
	}
	return _debuggerController;
}

- (IBAction)openDebugger:(id)sender
{
	[self openDebugger:sender showWindow:YES];
}

- (ZGLoggerWindowController *)loggerController
{
	if (!_loggerController)
	{
		self.loggerController = [[ZGLoggerWindowController alloc] init];
	}
	
	return _loggerController;
}

- (IBAction)openLogger:(id)sender
{
	[self.loggerController showWindow:self];
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

- (IBAction)openDonationURL:(id)sender
{
	[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=A3DTDV2F3VE5G&lc=US&item_name=Bit%20Slicer%20App&currency_code=USD&bn=PP%2dDonationsBF%3abtn_donate_SM%2egif%3aNonHosted"]];
}

@end
