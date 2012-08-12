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
#import <SecurityFoundation/SFAuthorization.h>
#import <Security/AuthorizationTags.h>
#import "ZGPreferencesController.h"
#import "ZGMemoryViewer.h"
#import "ZGProcess.h"
#import "ZGCalculator.h"

@interface ZGAppController ()

@property (readwrite, strong, nonatomic) ZGPreferencesController *preferencesController;
@property (readwrite, strong, nonatomic) ZGMemoryViewer *memoryViewer;

@end

@implementation ZGAppController

#pragma mark Singleton & Accessors

+ (BOOL)isRunningLaterThanLion
{
	SInt32 majorVersion;
	SInt32 minorVersion;
	
	if (Gestalt(gestaltSystemVersionMajor, &majorVersion) != noErr)
	{
		return NO;
	}
	
	if (Gestalt(gestaltSystemVersionMinor, &minorVersion) != noErr)
	{
		return NO;
	}
	
	return (majorVersion == 10 && minorVersion >= 7) || majorVersion > 10;
}

static id sharedInstance;
+ (id)sharedController
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

#pragma mark Authenticating

// http://os-tres.net/blog/2010/02/17/mac-os-x-and-task-for-pid-mach-call/
int acquireTaskportRight(void)
{
	OSStatus stat;
	AuthorizationItem taskport_item[1];
	taskport_item[0].name = "system.privilege.taskport:";
	taskport_item[0].valueLength = 0;
	taskport_item[0].value = NULL;
	taskport_item[0].flags = 0;
	
	AuthorizationRights rights = {1, taskport_item}, *out_rights = NULL;
	AuthorizationRef author;
	
	AuthorizationFlags auth_flags = kAuthorizationFlagExtendRights | kAuthorizationFlagPreAuthorize | kAuthorizationFlagInteractionAllowed | ( 1 << 5);
	
	stat = AuthorizationCreate (NULL, kAuthorizationEmptyEnvironment,auth_flags,&author);
	if (stat != errAuthorizationSuccess)
	{
		NSLog(@"Failure on AuthorizationCreate");
		return 0;
	}
	
	stat = AuthorizationCopyRights ( author, &rights, kAuthorizationEmptyEnvironment, auth_flags,&out_rights);
	if (stat != errAuthorizationSuccess)
	{
		NSLog(@"Failure on AuthorizationCopyRights");
		return 1;
	}
	return 0;
}

#pragma mark Pausing and Unpausing processes

OSStatus pauseOrUnpauseHotKeyHandler(EventHandlerCallRef nextHandler,EventRef theEvent, void *userData)
{
	for (NSRunningApplication *runningApplication in NSWorkspace.sharedWorkspace.runningApplications)
	{
		if (runningApplication.isActive && runningApplication.processIdentifier != getpid())
		{
			[ZGProcess pauseOrUnpauseProcess:runningApplication.processIdentifier];
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

- (void)applicationWillTerminate:(NSNotification *)notification
{
	// Make sure that we unfreeze all processes that we may have frozen
	for (NSRunningApplication *runningApplication in NSWorkspace.sharedWorkspace.runningApplications)
	{
		if ([ZGProcess.frozenProcesses containsObject:@(runningApplication.processIdentifier)])
		{
			[ZGProcess pauseOrUnpauseProcess:runningApplication.processIdentifier];
		}
	}
}

#pragma mark Controller behavior

- (void)checkForUpdates
{
	if ([NSUserDefaults.standardUserDefaults boolForKey:ZG_CHECK_FOR_UPDATES])
	{
		__block NSDictionary *latestVersionDictionary = nil;
		
		dispatch_block_t compareVersionsBlock = ^
		{
			if (latestVersionDictionary)
			{
				NSString *currentShortVersion = [NSBundle.mainBundle.infoDictionary objectForKey:@"CFBundleShortVersionString"];
				NSString *currentBuildString = [NSBundle.mainBundle.infoDictionary objectForKey:@"CFBundleVersion"];
				double currentVersion = currentBuildString.doubleValue;
				double latestStableVersion = [[latestVersionDictionary objectForKey:@"Build-Stable"] doubleValue];
				double latestAlphaVersion = [[latestVersionDictionary objectForKey:@"Build-Alpha"] doubleValue];
				
				BOOL checkForAlphas = [[NSUserDefaults standardUserDefaults] boolForKey:ZG_CHECK_FOR_ALPHA_UPDATES];
				if (!checkForAlphas && (floor(currentVersion) != currentVersion))
				{
					// we are in an alpha version, so we should check for alpha updates since we're already checking for regular updates
					[[NSUserDefaults standardUserDefaults] setBool:YES forKey:ZG_CHECK_FOR_ALPHA_UPDATES];
					[self.preferencesController updateAlphaUpdatesUI];
					checkForAlphas = YES;
				}
				
				NSString *latestShortVersion = nil;
				NSString *latestVersionURL = nil;
				
				if (checkForAlphas && (latestAlphaVersion > latestStableVersion) && (latestAlphaVersion > currentVersion))
				{
					latestShortVersion = [latestVersionDictionary objectForKey:@"Version-Alpha"];
					latestVersionURL = [latestVersionDictionary objectForKey:@"URL-Alpha"];
				}
				else if (latestStableVersion > currentVersion)
				{
					latestShortVersion = [latestVersionDictionary objectForKey:@"Version-Stable"];
					latestVersionURL = [latestVersionDictionary objectForKey:@"URL-Stable"];
				}
				
				if (latestShortVersion && latestVersionURL)
				{
					switch (NSRunAlertPanel(@"A new version is available", @"You currently have version %@. Do you want to update to %@?", @"Yes", @"No", @"Don't ask me again", currentShortVersion, latestShortVersion))
					{
						case NSAlertDefaultReturn: // yes, I want update
							[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:latestVersionURL]];
							break;
						case NSAlertOtherReturn: // don't ask again
							[NSUserDefaults.standardUserDefaults
							 setBool:NO
							 forKey:ZG_CHECK_FOR_UPDATES];
							
							[NSUserDefaults.standardUserDefaults
							 setBool:NO
							 forKey:ZG_CHECK_FOR_ALPHA_UPDATES];
							break;
					}
				}
			}
			else
			{
				NSLog(@"Cannot find latest version of Bit Slicer");
			}
		};
		
		dispatch_block_t queryLatestVersionBlock = ^
		{
			latestVersionDictionary = [NSDictionary dictionaryWithContentsOfURL:[NSURL URLWithString:BIT_SLICER_VERSION_FILE]];
			dispatch_async(dispatch_get_main_queue(), compareVersionsBlock);
		};
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), queryLatestVersionBlock);
	}
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	if (acquireTaskportRight() != 0)
	{
		NSLog(@"Failed to acquire taskport rights");
		
		NSRunAlertPanel(@"Insufficient privileges", @"Bit Slicer failed to acquire privileges needed to access another process' memory space.", nil, nil, nil);
		
		[NSApp terminate:nil];
	}
    
	// Initialize preference defaults
	[self openPreferences:nil showWindow:NO];
    
	[self.class registerPauseAndUnpauseHotKey];
	[ZGCalculator initializeCalculator];
	
	[self checkForUpdates];
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
	else if ([identifier isEqualToString:ZGPreferencesIdentifier])
	{
		[[self sharedController]
		 openPreferences:nil
		 showWindow:NO];
		
		completionHandler([[[self sharedController] preferencesController] window], nil);
	}
}

- (void)openPreferences:(id)sender showWindow:(BOOL)shouldShowWindow
{
	if (!self.preferencesController)
	{
		self.preferencesController = [[ZGPreferencesController alloc] init];
	}
	
	if (shouldShowWindow)
	{
		[self.preferencesController showWindow:nil];
	}
}

- (IBAction)openPreferences:(id)sender
{
	[self openPreferences:sender showWindow:YES];
}

- (void)openMemoryViewer:(id)sender showWindow:(BOOL)shouldShowWindow
{
	if (!self.memoryViewer)
	{
		self.memoryViewer = [[ZGMemoryViewer alloc] init];
	}
	
	if (shouldShowWindow)
	{
		[self.memoryViewer showWindow:nil];
	}
}

- (IBAction)openMemoryViewer:(id)sender
{
	[self openMemoryViewer:sender showWindow:YES];
}

- (IBAction)jumpToMemoryAddress:(id)sender
{
	[self.memoryViewer jumpToMemoryAddressRequest];
}

#define FAQ_URL @"http://portingteam.com/index.php/topic/4454-faq-information/"
- (IBAction)help:(id)sender
{	
	[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:FAQ_URL]];
}

#pragma mark Menu Item Validation

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	if (menuItem.action == @selector(jumpToMemoryAddress:))
	{
		if (!self.memoryViewer || !self.memoryViewer.canJumpToAddress)
		{
			return NO;
		}
	}
	
	return YES;
}

@end
