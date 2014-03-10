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

#import "ZGHotKeyController.h"
#import "ZGAppUpdaterController.h"

#import <ShortcutRecorder/ShortcutRecorder.h>

@interface ZGPreferencesController ()

@property (nonatomic) ZGHotKeyController *hotKeyController;
@property (nonatomic) ZGAppUpdaterController *appUpdaterController;

@property (assign) IBOutlet SRRecorderControl *hotkeyRecorder;
@property (assign) IBOutlet NSButton *checkForUpdatesButton;
@property (assign) IBOutlet NSButton *checkForAlphaUpdatesButton;
@property (assign) IBOutlet NSButton *sendProfileInfoButton;

@end

@implementation ZGPreferencesController

- (id)initWithHotKeyController:(ZGHotKeyController *)hotKeyController appUpdaterController:(ZGAppUpdaterController *)appUpdaterController
{
	self = [super initWithWindowNibName:@"Preferences"];
	
	self.hotKeyController = hotKeyController;
	self.appUpdaterController = appUpdaterController;
	
	return self;
}

- (void)updateCheckingForUpdateButtons
{
	if (self.appUpdaterController.checksForUpdates)
	{
		self.checkForUpdatesButton.state = NSOnState;
		
		self.checkForAlphaUpdatesButton.enabled = YES;
		self.checkForAlphaUpdatesButton.state = self.appUpdaterController.checksForAlphaUpdates ? NSOnState : NSOffState;
		
		self.sendProfileInfoButton.enabled = YES;
		self.sendProfileInfoButton.state = self.appUpdaterController.sendsAnonymousInfo ? NSOnState : NSOffState;
	}
	else
	{
		self.checkForAlphaUpdatesButton.enabled = NO;
		self.sendProfileInfoButton.enabled = NO;
		
		self.checkForUpdatesButton.state = NSOffState;
		self.checkForAlphaUpdatesButton.state = NSOffState;
		self.sendProfileInfoButton.state = NSOffState;
	}
}

- (void)awakeFromNib
{
	[self updateCheckingForUpdateButtons];
}

- (IBAction)showWindow:(id)sender
{
	[super showWindow:nil];
	
	// These states could change, for example, when the user has to make Sparkle pick between checking for automatic updates or not checking for them
	[self.appUpdaterController reloadValuesFromDefaults];
	[self updateCheckingForUpdateButtons];
}

- (void)windowDidLoad
{
	[self.hotkeyRecorder setAllowsKeyOnly:YES escapeKeysRecord:NO];
	self.hotkeyRecorder.keyCombo = self.hotKeyController.pauseHotKeyCombo;
}

- (void)shortcutRecorder:(SRRecorderControl *)recorder keyComboDidChange:(KeyCombo)newKeyCombo
{
	self.hotKeyController.pauseHotKeyCombo = (KeyCombo){.code = newKeyCombo.code, .flags = SRCocoaToCarbonFlags(newKeyCombo.flags)};
}

- (IBAction)checkForUpdatesButton:(id)sender
{
	if (self.checkForUpdatesButton.state == NSOffState)
	{
		self.appUpdaterController.checksForAlphaUpdates = NO;
		self.appUpdaterController.checksForUpdates = NO;
	}
	else
	{
		self.appUpdaterController.checksForUpdates = YES;
		self.appUpdaterController.checksForAlphaUpdates = [ZGAppUpdaterController runningAlpha];
	}
	
	[self updateCheckingForUpdateButtons];
}

- (IBAction)checkForAlphaUpdatesButton:(id)sender
{
	self.appUpdaterController.checksForAlphaUpdates = (self.checkForAlphaUpdatesButton.state == NSOnState);
	[self updateCheckingForUpdateButtons];
}

- (IBAction)changeSendProfileInformation:(id)sender
{
	self.appUpdaterController.sendsAnonymousInfo = (self.sendProfileInfoButton.state == NSOnState);
	[self updateCheckingForUpdateButtons];
}

@end
