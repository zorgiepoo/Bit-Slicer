/*
 * Created by Mayur Pawashe on 3/20/14.
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

#import "ZGMemoryNavigationWindowController.h"
#import "ZGProcess.h"

@implementation ZGMemoryNavigationWindowController

- (id)initWithProcessTaskManager:(ZGProcessTaskManager *)processTaskManager
{
	self = [super initWithProcessTaskManager:processTaskManager];
	
	if (self != nil)
	{
		self.navigationManager = [[NSUndoManager alloc] init];
	}
	
	return self;
}

- (void)updateWindow
{
	[super updateWindow];
	[self updateNavigationButtons];
}

- (void)setCurrentProcess:(ZGProcess *)newProcess
{
	[super setCurrentProcess:newProcess];
	
	[self.navigationManager removeAllActions];
	[self updateNavigationButtons];
}

- (void)switchProcess
{
	[super switchProcess];
	
	[self.navigationManager removeAllActions];
	[self updateNavigationButtons];
}

- (IBAction)goBack:(id)__unused sender
{
	[self.navigationManager undo];
	[self updateNavigationButtons];
}

- (IBAction)goForward:(id)__unused sender
{
	[self.navigationManager redo];
	[self updateNavigationButtons];
}

- (IBAction)navigate:(id)sender
{
	switch ([sender selectedSegment])
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
		[self.navigationSegmentedControl setEnabled:self.navigationManager.canUndo forSegment:ZGNavigationBack];
		[self.navigationSegmentedControl setEnabled:self.navigationManager.canRedo forSegment:ZGNavigationForward];
	}
	else
	{
		[self.navigationSegmentedControl setEnabled:NO forSegment:ZGNavigationBack];
		[self.navigationSegmentedControl setEnabled:NO forSegment:ZGNavigationForward];
	}
}

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)userInterfaceItem
{
	if (userInterfaceItem.action == @selector(goBack:) || userInterfaceItem.action == @selector(goForward:))
	{
		NSMenuItem *menuItem = (NSMenuItem *)userInterfaceItem;
		if (userInterfaceItem.action == @selector(goBack:))
		{
			menuItem.title = @"Back";
		}
		else
		{
			menuItem.title = @"Forward";
		}
		
		if (![self canEnableNavigationButtons])
		{
			return NO;
		}
		
		if ((userInterfaceItem.action == @selector(goBack:) && !self.navigationManager.canUndo) || (userInterfaceItem.action == @selector(goForward:) && !self.navigationManager.canRedo))
		{
			return NO;
		}
	}
	
	return [super validateUserInterfaceItem:userInterfaceItem];
}

@end
