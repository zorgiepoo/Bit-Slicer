/*
 * Created by Mayur Pawashe on 3/11/10.
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
