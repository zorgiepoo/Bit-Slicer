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
 * Created by Mayur Pawashe on 3/11/10.
 * Copyright 2010 zgcoder. All rights reserved.
 */

#import "ZGPreferencesController.h"
#import "ZGAppController.h"

@interface ZGPreferencesController ()

@property (assign) IBOutlet SRRecorderControl *hotkeyRecorder;
@property (assign) IBOutlet NSButton *checkForUpdatesButton;
@property (assign) IBOutlet NSButton *checkForAlphaUpdatesButton;

@end

@implementation ZGPreferencesController

+ (void)initialize
{
	[NSUserDefaults.standardUserDefaults
	 registerDefaults:
		@{
			ZG_HOT_KEY : @((NSInteger)INVALID_KEY_CODE),
			ZG_HOT_KEY_MODIFIER : @((NSInteger)0),
			ZG_CHECK_FOR_UPDATES : @(YES),
			ZG_CHECK_FOR_ALPHA_UPDATES : @(NO)
		}];
}

- (id)init
{
	self = [super initWithWindowNibName:@"Preferences"];
	
	[self setWindowFrameAutosaveName:@"ZGPreferencesWindow"];
	
	return self;
}

- (void)windowDidLoad
{
	if ([self.window respondsToSelector:@selector(setRestorable:)] && [self.window respondsToSelector:@selector(setRestorationClass:)])
	{
		self.window.restorable = YES;
		self.window.restorationClass = ZGAppController.class;
		self.window.identifier = ZGPreferencesIdentifier;
		[self invalidateRestorableState];
	}
	
	[self.hotkeyRecorder setAllowsKeyOnly:YES escapeKeysRecord:NO];
	
	NSInteger hotkeyCode = [NSUserDefaults.standardUserDefaults integerForKey:ZG_HOT_KEY];
	// INVALID_KEY_CODE used to be set at -999 (now it's at -1), so just take this into account
	if (hotkeyCode < INVALID_KEY_CODE)
	{
		hotkeyCode = INVALID_KEY_CODE;
		[NSUserDefaults.standardUserDefaults setInteger:INVALID_KEY_CODE forKey:ZG_HOT_KEY];
	}
	
	KeyCombo hotkeyCombo;
	hotkeyCombo.code = hotkeyCode;
	hotkeyCombo.flags = SRCarbonToCocoaFlags([[NSUserDefaults standardUserDefaults] integerForKey:ZG_HOT_KEY_MODIFIER]);
	
	self.hotkeyRecorder.keyCombo = hotkeyCombo;
	
	if ([NSUserDefaults.standardUserDefaults boolForKey:ZG_CHECK_FOR_UPDATES])
	{
		if ([NSUserDefaults.standardUserDefaults boolForKey:ZG_CHECK_FOR_ALPHA_UPDATES])
		{
			self.checkForAlphaUpdatesButton.state = NSOnState;
		}
	}
	else
	{
		self.checkForAlphaUpdatesButton.enabled = NO;
		self.checkForUpdatesButton.state = NSOffState;
	}
}

- (void)shortcutRecorder:(SRRecorderControl *)aRecorder keyComboDidChange:(KeyCombo)newKeyCombo
{
	[NSUserDefaults.standardUserDefaults
	 setInteger:[aRecorder keyCombo].code
	 forKey:ZG_HOT_KEY];
    
	[NSUserDefaults.standardUserDefaults
	 setInteger:SRCocoaToCarbonFlags([aRecorder keyCombo].flags)
	 forKey:ZG_HOT_KEY_MODIFIER];
	
	[ZGAppController registerPauseAndUnpauseHotKey];
}

- (IBAction)checkForUpdatesButton:(id)sender
{
	if (self.checkForUpdatesButton.state == NSOffState)
	{
		self.checkForAlphaUpdatesButton.enabled = NO;
		self.checkForAlphaUpdatesButton.state = NSOffState;
		[[NSUserDefaults standardUserDefaults]
		 setBool:NO
		 forKey:ZG_CHECK_FOR_ALPHA_UPDATES];
	}
	else
	{
		self.checkForAlphaUpdatesButton.enabled = YES;
	}
	
	[NSUserDefaults.standardUserDefaults
	 setBool:(self.checkForUpdatesButton.state == NSOnState)
	 forKey:ZG_CHECK_FOR_UPDATES];
}

- (IBAction)checkForAlphaUpdatesButton:(id)sender
{
	[NSUserDefaults.standardUserDefaults
	 setBool:self.checkForAlphaUpdatesButton.state == NSOnState
	 forKey:ZG_CHECK_FOR_ALPHA_UPDATES];
}

- (void)updateAlphaUpdatesUI
{
	self.checkForAlphaUpdatesButton.state = [NSUserDefaults.standardUserDefaults boolForKey:ZG_CHECK_FOR_ALPHA_UPDATES];
}

@end
