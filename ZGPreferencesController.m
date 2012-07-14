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

@implementation ZGPreferencesController

+ (void)initialize
{
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:INVALID_KEY_CODE]
																						forKey:ZG_HOT_KEY]];
    
    [[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:0]
																						forKey:ZG_HOT_KEY_MODIFIER]];
	
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES]
																						forKey:ZG_CHECK_FOR_UPDATES]];
	
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:NO]
																						forKey:ZG_CHECK_FOR_ALPHA_UPDATES]];
}

- (id)init
{
	self = [super initWithWindowNibName:@"Preferences"];
	
	[self setWindowFrameAutosaveName:@"ZGPreferencesWindow"];
	
	return self;
}

- (void)windowDidLoad
{
    if ([[self window] respondsToSelector:@selector(setRestorable:)] && [[self window] respondsToSelector:@selector(setRestorationClass:)])
    {
        [[self window] setRestorable:YES];
        [[self window] setRestorationClass:[ZGAppController class]];
        [[self window] setIdentifier:ZGPreferencesIdentifier];
        [self invalidateRestorableState];
    }
    
    [hotkeyRecorder setAllowsKeyOnly:YES
                    escapeKeysRecord:NO];
    
    NSInteger hotkeyCode = [[NSUserDefaults standardUserDefaults] integerForKey:ZG_HOT_KEY];
    // INVALID_KEY_CODE used to be set at -999 (now it's at -1), so just take this into account
    if (hotkeyCode < INVALID_KEY_CODE)
    {
        hotkeyCode = INVALID_KEY_CODE;
        [[NSUserDefaults standardUserDefaults] setInteger:INVALID_KEY_CODE
                                                   forKey:ZG_HOT_KEY];
    }
    
    KeyCombo hotkeyCombo;
    hotkeyCombo.code = hotkeyCode;
    hotkeyCombo.flags = SRCarbonToCocoaFlags([[NSUserDefaults standardUserDefaults] integerForKey:ZG_HOT_KEY_MODIFIER]);
    
    [hotkeyRecorder setKeyCombo:hotkeyCombo];
	
	if ([[NSUserDefaults standardUserDefaults] boolForKey:ZG_CHECK_FOR_UPDATES])
	{
		if ([[NSUserDefaults standardUserDefaults] boolForKey:ZG_CHECK_FOR_ALPHA_UPDATES])
		{
			[checkForAlphaUpdatesButton setState:NSOnState];
		}
	}
	else
	{
		[checkForAlphaUpdatesButton setEnabled:NO];
		[checkForUpdatesButton setState:NSOffState];
	}
}

- (void)shortcutRecorder:(SRRecorderControl *)aRecorder keyComboDidChange:(KeyCombo)newKeyCombo
{
    [[NSUserDefaults standardUserDefaults] setInteger:[aRecorder keyCombo].code
											   forKey:ZG_HOT_KEY];
    
    [[NSUserDefaults standardUserDefaults] setInteger:SRCocoaToCarbonFlags([aRecorder keyCombo].flags)
											   forKey:ZG_HOT_KEY_MODIFIER];
    
    [ZGAppController registerPauseAndUnpauseHotKey];
}

- (IBAction)checkForUpdatesButton:(id)sender
{
	if ([checkForUpdatesButton state] == NSOffState)
	{
		[checkForAlphaUpdatesButton setEnabled:NO];
		[checkForAlphaUpdatesButton setState:NSOffState];
		[[NSUserDefaults standardUserDefaults] setBool:NO
												forKey:ZG_CHECK_FOR_ALPHA_UPDATES];
	}
	else
	{
		[checkForAlphaUpdatesButton setEnabled:YES];
	}
	
	[[NSUserDefaults standardUserDefaults] setBool:[checkForUpdatesButton state] == NSOnState
											forKey:ZG_CHECK_FOR_UPDATES];
}

- (IBAction)checkForAlphaUpdatesButton:(id)sender
{
	[[NSUserDefaults standardUserDefaults] setBool:[checkForAlphaUpdatesButton state] == NSOnState
											forKey:ZG_CHECK_FOR_ALPHA_UPDATES];
}

- (void)updateAlphaUpdatesUI
{
	[checkForAlphaUpdatesButton setState:[[NSUserDefaults standardUserDefaults] boolForKey:ZG_CHECK_FOR_ALPHA_UPDATES]];
}

@end
