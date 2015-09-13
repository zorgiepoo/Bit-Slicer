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
 */

#import "ZGPreferencesController.h"
#import "ZGUpdatePreferencesViewController.h"
#import "ZGHotKeyPreferencesViewController.h"
#import "ZGHotKeyCenter.h"
#import "ZGScriptPreferencesViewController.h"
#import "ZGAppUpdaterController.h"
#import "ZGDebuggerController.h"

#define ZGSoftwareUpdatePreferenceIdentifier @"ZGSoftwareUpdateIdentifier"
#define ZGDebuggerHotKeysPreferenceIdentifier @"ZGDebuggerHotKeysIdentifier"
#define ZGScriptPreferenceIdentifier @"ZGScriptPreferenceIdentifier"

#define ZGSoftwareUpdateIconPath @"/System/Library/CoreServices/Software Update.app/Contents/Resources/SoftwareUpdate.icns"

#define ZGPreferencesLocalizationTable @"[Code] Preferences"

@implementation ZGPreferencesController
{
	ZGHotKeyCenter * _Nonnull _hotKeyCenter;
	ZGAppUpdaterController * _Nonnull _appUpdaterController;
	ZGDebuggerController * _Nonnull _debuggerController;
	
	NSViewController * _Nullable _preferencesViewController;
}

- (id)initWithHotKeyCenter:(ZGHotKeyCenter *)hotKeyCenter debuggerController:(ZGDebuggerController *)debuggerController appUpdaterController:(ZGAppUpdaterController *)appUpdaterController
{
	self = [super initWithWindowNibName:@"Preferences Window"];
	
	if (self != nil)
	{
		_hotKeyCenter = hotKeyCenter;
		_appUpdaterController = appUpdaterController;
		_debuggerController = debuggerController;
	}
	
	return self;
}

- (void)windowDidLoad
{
	[self.window.toolbar setSelectedItemIdentifier:ZGSoftwareUpdatePreferenceIdentifier];
	
	for (NSToolbarItem *toolbarItem in self.window.toolbar.items)
	{
		if ([toolbarItem.itemIdentifier isEqualToString:ZGSoftwareUpdatePreferenceIdentifier])
		{
			if ([[NSFileManager defaultManager] fileExistsAtPath:ZGSoftwareUpdateIconPath])
			{
				toolbarItem.image = [[NSImage alloc] initWithContentsOfFile:ZGSoftwareUpdateIconPath];
			}
		}
	}
	
	[self setUpdatePreferencesView];
}

- (void)setPreferencesViewController:(NSViewController *)viewController andWindowTitle:(NSString *)windowTitle
{
	if ([_preferencesViewController class] != [viewController class])
	{
		_preferencesViewController = viewController;
		self.window.contentView = viewController.view;
		[self.window setTitle:windowTitle];
	}
}

- (void)setUpdatePreferencesView
{
	[self
	 setPreferencesViewController:[[ZGUpdatePreferencesViewController alloc] initWithAppUpdaterController:_appUpdaterController]
	 andWindowTitle:NSLocalizedStringFromTable(@"softwareUpdateWindowTitle", ZGPreferencesLocalizationTable, nil)];
}

- (void)setHotKeyPreferencesView
{
	[self
	 setPreferencesViewController:[[ZGHotKeyPreferencesViewController alloc] initWithHotKeyCenter:_hotKeyCenter debuggerController:_debuggerController]
	 andWindowTitle:NSLocalizedStringFromTable(@"shortcutsWindowTitle", ZGPreferencesLocalizationTable, nil)];
}

- (void)setScriptPreferencesView
{
	[self
	 setPreferencesViewController:[[ZGScriptPreferencesViewController alloc] init]
	 andWindowTitle:NSLocalizedStringFromTable(@"scriptsWindowTitle", ZGPreferencesLocalizationTable, nil)];
}

- (IBAction)changePreferencesView:(NSToolbarItem *)toolbarItem
{
	if ([toolbarItem.itemIdentifier isEqualToString:ZGSoftwareUpdatePreferenceIdentifier])
	{
		[self setUpdatePreferencesView];
	}
	else if ([toolbarItem.itemIdentifier isEqualToString:ZGDebuggerHotKeysPreferenceIdentifier])
	{
		[self setHotKeyPreferencesView];
	}
	else if ([toolbarItem.itemIdentifier isEqualToString:ZGScriptPreferenceIdentifier])
	{
		[self setScriptPreferencesView];
	}
}

@end
