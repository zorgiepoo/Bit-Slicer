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
#import "ZGUpdatePreferencesViewController.h"
#import "ZGHotKeyPreferencesViewController.h"
#import "ZGHotKeyCenter.h"
#import "ZGAppUpdaterController.h"
#import "ZGDebuggerController.h"

@interface ZGPreferencesController ()

@property (nonatomic) ZGHotKeyCenter *hotKeyCenter;
@property (nonatomic) ZGAppUpdaterController *appUpdaterController;
@property (nonatomic) ZGDebuggerController *debuggerController;

@property (nonatomic) ZGUpdatePreferencesViewController *updatePreferencesViewController;
@property (nonatomic, assign) IBOutlet NSView *updatePreferencesView;

@property (nonatomic) ZGHotKeyPreferencesViewController *hotKeyPreferencesViewController;
@property (nonatomic, assign) IBOutlet NSView *hotKeyPreferencesView;

@end

@implementation ZGPreferencesController

- (id)initWithHotKeyCenter:(ZGHotKeyCenter *)hotKeyCenter debuggerController:(ZGDebuggerController *)debuggerController appUpdaterController:(ZGAppUpdaterController *)appUpdaterController
{
	self = [super initWithWindowNibName:@"Preferences"];
	
	if (self != nil)
	{
		self.hotKeyCenter = hotKeyCenter;
		self.appUpdaterController = appUpdaterController;
		self.debuggerController = debuggerController;
	}
	
	return self;
}

- (void)windowDidLoad
{	
	self.updatePreferencesViewController = [[ZGUpdatePreferencesViewController alloc] initWithAppUpdaterController:self.appUpdaterController];
	[self.updatePreferencesView addSubview:self.updatePreferencesViewController.view];
	self.updatePreferencesViewController.view.frame = self.updatePreferencesView.bounds;
	
	self.hotKeyPreferencesViewController = [[ZGHotKeyPreferencesViewController alloc] initWithHotKeyCenter:self.hotKeyCenter debuggerController:self.debuggerController];
	[self.hotKeyPreferencesView addSubview:self.hotKeyPreferencesViewController.view];
	self.hotKeyPreferencesViewController.view.frame = self.hotKeyPreferencesView.bounds;
}

@end
