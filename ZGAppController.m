/*
 * This file is part of Bit Slicer.
 *
 * Bit Slicer is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 
 * Bit Slicer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 
 * You should have received a copy of the GNU General Public License
 * along with Bit Slicer.  If not, see <http://www.gnu.org/licenses/>.
 * 
 * Created by Mayur Pawashe on 2/5/10.
 * Copyright 2010 zgcoder. All rights reserved.
 */

#import "ZGAppController.h"
#import "ZGDocumentController.h"
#import <SecurityFoundation/SFAuthorization.h>
#import <Security/AuthorizationTags.h>
#import "ZGPreferencesController.h"
#import "ZGMemoryViewer.h"
#import "ZGProcess.h"
#import "ZGCalculator.h"

@implementation ZGAppController

@synthesize applicationIsAuthenticated;

#pragma mark Singleton & Accessors

static ZGAppController *sharedInstance = nil;

+ (ZGAppController *)sharedController
{
	return sharedInstance;
}

- (id)init
{
	self = [super init];
	
	if (self)
	{
		sharedInstance = self;
	}
	
	return self;
}

- (ZGMemoryViewer *)memoryViewer
{
	return memoryViewer;
}

- (ZGDocumentController *)documentController
{
	return documentController;
}

#pragma mark Authenticating

void authMe(const char * FullPathToMe, NSURL *url)
{
	// get authorization as root
	
	OSStatus myStatus;
	
	// set up Authorization Item
	AuthorizationItem myItems[1];
	myItems[0].name = kAuthorizationRightExecute;
	myItems[0].valueLength = 0;
	myItems[0].value = NULL;
	myItems[0].flags = 0;
	
	// Set up Authorization Rights
	AuthorizationRights myRights;
	myRights.count = sizeof (myItems) / sizeof (myItems[0]);
	myRights.items = myItems;
	
	// set up Authorization Flags
	AuthorizationFlags myFlags;
	myFlags =
	kAuthorizationFlagDefaults |
	kAuthorizationFlagInteractionAllowed |
	kAuthorizationFlagExtendRights;
	
	// Create an Authorization Ref using Objects above. NOTE: Login bod comes up with this call.
	AuthorizationRef myAuthorizationRef;
	myStatus = AuthorizationCreate (&myRights, kAuthorizationEmptyEnvironment, myFlags, &myAuthorizationRef);
	
	if (myStatus == errAuthorizationSuccess)
	{
		// prepare communication path - used to signal that process is loaded
		FILE *myCommunicationsPipe = NULL;
		char myReadBuffer[] = " ";
		char *arguments[2] = {NULL, NULL};
		
		if (url)
		{
			arguments[0] = (char *)[[url relativePath] cStringUsingEncoding:NSUTF8StringEncoding];
		}
		
		// run this app in GOD mode by passing authorization ref and comm pipe (asynchoronous call to external application)
		myStatus = AuthorizationExecuteWithPrivileges(myAuthorizationRef,FullPathToMe,kAuthorizationFlagDefaults,arguments,&myCommunicationsPipe);
		
		// external app is running asynchronously - it will send to stdout when loaded
		if (myStatus == errAuthorizationSuccess)
		{
			read (fileno (myCommunicationsPipe), myReadBuffer, sizeof (myReadBuffer));
			fclose(myCommunicationsPipe);
		}
		
		// release authorization reference
		/* myStatus = */ AuthorizationFree (myAuthorizationRef, kAuthorizationFlagDestroyRights);
	}
}

BOOL checkExecutablePermissions(void)
{
	NSDictionary	*applicationAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[[NSBundle mainBundle] executablePath] error:NULL];
	
	// We expect 2755 as octal (1517 as decimal, -rwxr-sr-x as extended notation)
	return ([applicationAttributes filePosixPermissions] == 1517 && [[applicationAttributes fileGroupOwnerAccountName] isEqualToString: @"procmod"]);
}

BOOL amIWorthy(void)
{
	// running as root?
	AuthorizationRef myAuthRef;
	OSStatus stat = AuthorizationCopyPrivilegedReference(&myAuthRef,kAuthorizationFlagDefaults);
	
	return stat == errAuthorizationSuccess || checkExecutablePermissions();
}

- (void)authenticateWithURL:(NSURL *)url
{
	if (amIWorthy())
	{
#ifndef _DEBUG
		printf("Don't forget to flush! ;-) "); // signal back to close caller
#endif
		fflush(stdout);
		
		[NSApp activateIgnoringOtherApps:YES];
		applicationIsAuthenticated = YES;
	}
	else
	{
		authMe([[[NSBundle mainBundle] executablePath] UTF8String], url);
		[NSApp terminate:nil];
	}
}

#pragma mark Pausing and Unpausing processes

OSStatus pauseOrUnpauseHotKeyHandler(EventHandlerCallRef nextHandler,EventRef theEvent, void *userData)
{
	for (NSRunningApplication *runningApplication in [[NSWorkspace sharedWorkspace] runningApplications])
	{
		if ([runningApplication isActive] && [runningApplication processIdentifier] != getpid())
		{
			[ZGProcess pauseOrUnpauseProcess:[runningApplication processIdentifier]];
		}
	}
	
	return noErr;
}

static EventHotKeyRef hotKeyRef;
static BOOL didRegisteredHotKey = NO;
+ (void)registerPauseAndUnpauseHotKey
{
	if (didRegisteredHotKey)
	{
		UnregisterEventHotKey(hotKeyRef);
	}
	
	NSNumber *hotKeyCodeNumber = [[NSUserDefaults standardUserDefaults] objectForKey:ZG_HOT_KEY];
	if (hotKeyCodeNumber && [hotKeyCodeNumber intValue] != INVALID_KEY_CODE)
	{
		EventTypeSpec eventType;
		eventType.eventClass = kEventClassKeyboard;
		eventType.eventKind = kEventHotKeyPressed;
		
		InstallApplicationEventHandler(&pauseOrUnpauseHotKeyHandler, 1, &eventType, NULL, NULL);
		
		EventHotKeyID hotKeyID;
		hotKeyID.signature = 'htk1';
		hotKeyID.id = 1;
		
		RegisterEventHotKey([hotKeyCodeNumber intValue], 0, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef);
		
		didRegisteredHotKey = YES;
	}
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	// Make sure that we unfreeze all processes that we may have frozen
	for (NSRunningApplication *runningApplication in [[NSWorkspace sharedWorkspace] runningApplications])
	{
		if ([[ZGProcess frozenProcesses] containsObject:[NSNumber numberWithInt:[runningApplication processIdentifier]]])
		{
			[ZGProcess pauseOrUnpauseProcess:[runningApplication processIdentifier]];
		}
	}
}

#pragma mark Controller behavior

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
	return amIWorthy();
}

#define CHECK_PROCESSES_TIME_INTERVAL 0.5
- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	if (!applicationIsAuthenticated)
	{
		[self authenticateWithURL:nil];
	}
	
	[ZGAppController registerPauseAndUnpauseHotKey];
	[ZGCalculator initializeCalculator];
	
	[NSTimer scheduledTimerWithTimeInterval:CHECK_PROCESSES_TIME_INTERVAL
									 target:self
								   selector:@selector(checkProcesses:)
								   userInfo:nil
									repeats:YES];
}

#pragma mark Actions

- (IBAction)openPreferences:(id)sender
{
	if (!preferencesController)
	{
		preferencesController = [[ZGPreferencesController alloc] init];
	}
	
	[preferencesController showWindow:nil];
}

- (IBAction)openMemoryViewer:(id)sender
{
	if (!memoryViewer)
	{
		memoryViewer = [[ZGMemoryViewer alloc] init];
	}
	
	[memoryViewer showWindow:nil];
}

- (IBAction)jumpToMemoryAddress:(id)sender
{
	[memoryViewer jumpToMemoryAddressRequest];
}

#define FAQ_URL @"http://forum.portingteam.com/viewtopic.php?f=245&t=6914"
- (IBAction)help:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:FAQ_URL]];
}

#pragma mark Menu Item Validation

- (BOOL)validateMenuItem:(NSMenuItem *)theMenuItem
{
	if ([theMenuItem action] == @selector(jumpToMemoryAddress:))
	{
		if (!memoryViewer || ![memoryViewer canJumpToAddress])
		{
			return NO;
		}
	}
	
	return YES;
}

#pragma mark Watching processes

- (void)checkProcesses:(NSTimer *)timer
{
	// So basically, NSWorkspace's methods for notifying us of processes terminating and launching,
	// don't notify us of processes that main applications spawn
	// So we check every few seconds if any new process spawns
	// In my experience, an example of this is with Chrome processes
	
	NSArray *newRunningApplications = [[NSWorkspace sharedWorkspace] runningApplications];
	BOOL anApplicationLaunchedOrTerminated = NO;
	
	for (NSRunningApplication *runningApplication in newRunningApplications)
	{
		// Check if a process spawned
		if (![runningApplications containsObject:runningApplication])
		{
			[[NSNotificationCenter defaultCenter] postNotificationName:ZGProcessLaunched
																object:self
															  userInfo:[NSDictionary dictionaryWithObject:runningApplication
																								   forKey:ZGRunningApplication]];
			anApplicationLaunchedOrTerminated = YES;
		}
	}
	
	for (NSRunningApplication *runningApplication in runningApplications)
	{
		// Check if a process terminated
		if (![newRunningApplications containsObject:runningApplication])
		{
			[[NSNotificationCenter defaultCenter] postNotificationName:ZGProcessTerminated
																object:self
															  userInfo:[NSDictionary dictionaryWithObject:runningApplication
																								   forKey:ZGRunningApplication]];
			anApplicationLaunchedOrTerminated = YES;
		}
	}
	
	if (anApplicationLaunchedOrTerminated)
	{
		[runningApplications release];
		runningApplications = [newRunningApplications retain];
	}
}

@end
