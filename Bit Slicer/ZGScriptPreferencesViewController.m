/*
 * Created by Mayur Pawashe on 4/28/14.
 *
 * Copyright (c) 2014 zgcoder
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

#import "ZGScriptPreferencesViewController.h"
#import "ZGScriptManager.h"
#import "ZGVariableController.h"
#import "ZGAppPathUtilities.h"

enum ZGScriptIndentationTag
{
	ZGScriptIndentationTabsTag,
	ZGScriptIndentationSpacesTag
};

@interface ZGScriptPreferencesViewController ()

@property (nonatomic, assign) IBOutlet NSPopUpButton *applicationEditorsPopUpButton;
@property (nonatomic, assign) IBOutlet NSPopUpButton *indentationPopUpButton;

@end

@implementation ZGScriptPreferencesViewController

#pragma mark Birth

- (id)init
{
	return [super initWithNibName:NSStringFromClass([self class]) bundle:nil];
}

- (void)loadView
{
	[super loadView];
	[self updateApplicationEditorsPopUpButton];
	[self updateIndentationPopUpButton];
}

#pragma mark Default Application Editor

#define EDITOR_ICON_SIZE NSMakeSize(16, 16)
- (void)updateApplicationEditorsPopUpButton
{
	[self.applicationEditorsPopUpButton removeAllItems];
	
	NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
	NSMenuItem *defaultEditorMenuItem = [[NSMenuItem alloc] initWithTitle:@"Default Python Editor" action:NULL keyEquivalent:@""];
	NSImage *extensionIcon = [workspace iconForFileType:@"py"];
	
	defaultEditorMenuItem.image = [extensionIcon copy];
	[defaultEditorMenuItem.image setSize:EDITOR_ICON_SIZE];
	[self.applicationEditorsPopUpButton.menu addItem:defaultEditorMenuItem];
	
	NSString *emptyPythonFile = [ZGAppPathUtilities createEmptyPythonFile];
	NSArray *editorURLs = CFBridgingRelease(LSCopyApplicationURLsForURL((__bridge CFURLRef)([NSURL fileURLWithPath:emptyPythonFile]), kLSRolesEditor));
	
	if (editorURLs.count == 0)
	{
		return;
	}
	
	[self.applicationEditorsPopUpButton.menu addItem:[NSMenuItem separatorItem]];
	
	NSMutableArray *addedEditorPaths = [NSMutableArray array];
	for (NSURL *editorURL in editorURLs)
	{
		NSString *editorPath = [editorURL relativePath];
		NSString *editorName = [[editorPath lastPathComponent] stringByDeletingPathExtension];
		if (![addedEditorPaths containsObject:editorName])
		{
			NSImage *icon = [workspace iconForFile:editorPath];
			
			NSMenuItem *editorMenuItem = [[NSMenuItem alloc] initWithTitle:editorName action:NULL keyEquivalent:@""];
			editorMenuItem.image = [icon copy];
			[editorMenuItem.image setSize:EDITOR_ICON_SIZE];
			
			[self.applicationEditorsPopUpButton.menu addItem:editorMenuItem];
			[addedEditorPaths addObject:editorName];
		}
	}
	
	NSString *defaultEditor = [[NSUserDefaults standardUserDefaults] objectForKey:ZGScriptDefaultApplicationEditorKey];
	if (defaultEditor.length > 0)
	{
		[self.applicationEditorsPopUpButton selectItemWithTitle:defaultEditor];
	}
}

- (IBAction)changeDefaultApplicationEditor:(id)__unused sender
{
	NSMenuItem *selectedItem = self.applicationEditorsPopUpButton.selectedItem;
	NSString *chosenEditor = (self.applicationEditorsPopUpButton.itemArray.firstObject == selectedItem) ? @"" : selectedItem.title;
	[[NSUserDefaults standardUserDefaults] setObject:chosenEditor forKey:ZGScriptDefaultApplicationEditorKey];
}

#pragma mark Default Script Indentation

- (void)updateIndentationPopUpButton
{
	[self.indentationPopUpButton removeAllItems];
	
	NSMenuItem *tabsMenuItem = [[NSMenuItem alloc] initWithTitle:@"Tabs" action:NULL keyEquivalent:@""];
	tabsMenuItem.tag = ZGScriptIndentationTabsTag;
	
	NSMenuItem *spacesMenuItem = [[NSMenuItem alloc] initWithTitle:@"Spaces" action:NULL keyEquivalent:@""];
	spacesMenuItem.tag = ZGScriptIndentationSpacesTag;
	
	[self.indentationPopUpButton.menu addItem:tabsMenuItem];
	[self.indentationPopUpButton.menu addItem:spacesMenuItem];
	
	BOOL usesTabs = [[NSUserDefaults standardUserDefaults] boolForKey:ZGScriptIndentationUsingTabsKey];
	[self.indentationPopUpButton selectItem:usesTabs ? tabsMenuItem : spacesMenuItem];
}

- (IBAction)changeDefaultScriptIndentation:(id)__unused sender
{
	BOOL usesTabs = ([self.indentationPopUpButton selectedTag]) == ZGScriptIndentationTabsTag;
	[[NSUserDefaults standardUserDefaults] setBool:usesTabs forKey:ZGScriptIndentationUsingTabsKey];
}

@end
