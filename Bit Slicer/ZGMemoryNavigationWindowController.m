/*
 * Copyright (c) 2014 Mayur Pawashe
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

#import "ZGMemoryNavigationWindowController.h"
#import "ZGProcess.h"

#define ZGLocalizedStringFromMemoryNavigationTable(string) NSLocalizedStringFromTable((string), @"[Code] Memory Navigation", nil)

@implementation ZGMemoryNavigationWindowController

- (id)initWithProcessTaskManager:(ZGProcessTaskManager *)processTaskManager rootlessConfiguration:(ZGRootlessConfiguration *)rootlessConfiguration delegate:(id <ZGChosenProcessDelegate, ZGMemorySelectionDelegate, ZGShowMemoryWindow>)delegate
{
	self = [super initWithProcessTaskManager:processTaskManager rootlessConfiguration:rootlessConfiguration delegate:delegate];
	
	if (self != nil)
	{
		_navigationManager = [[NSUndoManager alloc] init];
	}
	
	return self;
}

- (void)updateWindow
{
	[super updateWindow];
	[self updateNavigationButtons];
}

- (void)updateWindowAndReadMemory:(BOOL)__unused shouldReadMemory
{
}

- (void)setCurrentProcess:(ZGProcess *)newProcess
{
	[super setCurrentProcess:newProcess];
	
	[_navigationManager removeAllActions];
	[self updateNavigationButtons];
}

- (void)switchProcess
{
	[super switchProcess];
	
	[_navigationManager removeAllActions];
	[self updateNavigationButtons];
}

- (IBAction)goBack:(id)__unused sender
{
	[_navigationManager undo];
	[self updateNavigationButtons];
}

- (IBAction)goForward:(id)__unused sender
{
	[_navigationManager redo];
	[self updateNavigationButtons];
}

- (IBAction)navigate:(id)sender
{
	switch ([(NSSegmentedControl *)sender selectedSegment])
	{
		case ZGNavigationBack:
			[self goBack:nil];
			break;
		case ZGNavigationForward:
			[self goForward:nil];
			break;
	}
}

- (BOOL)canEnableNavigationButtons
{
	return self.currentProcess.valid;
}

- (void)updateNavigationButtons
{
	if ([self canEnableNavigationButtons])
	{
		[_navigationSegmentedControl setEnabled:_navigationManager.canUndo forSegment:ZGNavigationBack];
		[_navigationSegmentedControl setEnabled:_navigationManager.canRedo forSegment:ZGNavigationForward];
	}
	else
	{
		[_navigationSegmentedControl setEnabled:NO forSegment:ZGNavigationBack];
		[_navigationSegmentedControl setEnabled:NO forSegment:ZGNavigationForward];
	}
}

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)userInterfaceItem
{
	if (userInterfaceItem.action == @selector(goBack:) || userInterfaceItem.action == @selector(goForward:))
	{
		NSMenuItem *menuItem = (NSMenuItem *)userInterfaceItem;
		if (userInterfaceItem.action == @selector(goBack:))
		{
			menuItem.title = ZGLocalizedStringFromMemoryNavigationTable(@"back");
		}
		else
		{
			menuItem.title = ZGLocalizedStringFromMemoryNavigationTable(@"forward");
		}
		
		if (![self canEnableNavigationButtons])
		{
			return NO;
		}
		
		if ((userInterfaceItem.action == @selector(goBack:) && !_navigationManager.canUndo) || (userInterfaceItem.action == @selector(goForward:) && !_navigationManager.canRedo))
		{
			return NO;
		}
	}
	
	return [super validateUserInterfaceItem:userInterfaceItem];
}

@end
