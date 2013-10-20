/*
 * Created by Mayur Pawashe on 3/8/13.
 *
 * Copyright (c) 2013 zgcoder
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

#import "ZGMemoryWindowController.h"
#import "ZGAppController.h"
#import "ZGDebuggerController.h" // For seeing if we can pause/unpause a process
#import "ZGProcessList.h"
#import "ZGRunningProcess.h"
#import "ZGProcess.h"
#import "ZGVirtualMemory.h"

@implementation ZGMemoryWindowController

#pragma mark Birth

- (id)init
{
	self = [super initWithWindowNibName:NSStringFromClass([self class])];
	
	if (self)
	{
		self.undoManager = [[NSUndoManager alloc] init];
		self.navigationManager = [[NSUndoManager alloc] init];
	}
	
	return self;
}

- (NSUndoManager *)windowWillReturnUndoManager:(id)sender
{
	return self.undoManager;
}

- (void)markChanges
{
	if ([self respondsToSelector:@selector(invalidateRestorableState)])
	{
		[self invalidateRestorableState];
	}
}

- (void)setWindowAttributesWithIdentifier:(NSString *)windowIdentifier
{
	self.window.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
	
	if ([self.window respondsToSelector:@selector(setRestorable:)] && [self.window respondsToSelector:@selector(setRestorationClass:)])
	{
		self.window.restorable = YES;
		self.window.restorationClass = [ZGAppController class];
		self.window.identifier = windowIdentifier;
		[self markChanges];
	}
}

- (IBAction)showWindow:(id)sender
{
	[super showWindow:sender];
	
	[self windowDidShow:sender];
}

- (void)windowDidAppearForFirstTime:(id)sender
{
}

- (double)displayMemoryTimeInterval
{
	return 0.5;
}

- (void)makeUpdateDisplayTimer
{
	self.updateDisplayTimer =
	[NSTimer
	 scheduledTimerWithTimeInterval:[self displayMemoryTimeInterval]
	 target:self
	 selector:@selector(updateDisplayTimer:)
	 userInfo:nil
	 repeats:YES];
}

- (void)destroyUpdateDisplayTimer
{
	[self.updateDisplayTimer invalidate];
	self.updateDisplayTimer = nil;
}

- (void)windowDidChangeOcclusionState:(NSNotification *)notification
{
	if (([self.window occlusionState] & NSWindowOcclusionStateVisible) == 0)
	{
		[self destroyUpdateDisplayTimer];
		
		[[ZGProcessList sharedProcessList] removePriorityToProcessIdentifier:self.currentProcess.processID withObserver:self];
		[[ZGProcessList sharedProcessList] unrequestPollingWithObserver:self];
	}
	else
	{
		if (self.updateDisplayTimer == nil)
		{
			[self makeUpdateDisplayTimer];
		}
		
		if (self.currentProcess.valid)
		{
			[[ZGProcessList sharedProcessList] addPriorityToProcessIdentifier:self.currentProcess.processID withObserver:self];
		}
		else
		{
			[[ZGProcessList sharedProcessList] requestPollingWithObserver:self];
		}
	}
}

- (void)windowDidLoad
{
	if ([self.window respondsToSelector:@selector(occlusionState)])
	{
		[[NSNotificationCenter defaultCenter]
		 addObserver:self
		 selector:@selector(windowDidChangeOcclusionState:)
		 name:NSWindowDidChangeOcclusionStateNotification
		 object:self.window];
	}
}

// This is intended to be called when the window shows up - either from showWindow: or from window restoration
- (void)windowDidShow:(id)sender
{
	if (self.updateDisplayTimer == nil)
	{
		[self makeUpdateDisplayTimer];
	}
	
	if (!self.windowDidAppear)
	{
		[self windowDidAppearForFirstTime:sender];
		self.windowDidAppear = YES;
	}
	
	if (self.currentProcess)
	{
		if (self.currentProcess.valid)
		{
			[[ZGProcessList sharedProcessList] addPriorityToProcessIdentifier:self.currentProcess.processID withObserver:self];
		}
		else
		{
			[[ZGProcessList sharedProcessList] requestPollingWithObserver:self];
		}
	}
	
	[self updateNavigationButtons];
}

#pragma mark Death

- (void)windowWillClose:(NSNotification *)notification
{
	if ([notification object] == self.window)
	{
		[self destroyUpdateDisplayTimer];
		
		if (self.currentProcess.valid)
		{
			[[ZGProcessList sharedProcessList] removePriorityToProcessIdentifier:self.currentProcess.processID withObserver:self];
		}
		
		[[ZGProcessList sharedProcessList] unrequestPollingWithObserver:self];
	}
}

#pragma mark Process Handling

- (void)setupProcessListNotificationsAndPopUpButton
{
	// Add processes to popup button
	self.desiredProcessName = [[ZGAppController sharedController] lastSelectedProcessName];
	[self updateRunningProcesses];
	
	[[ZGProcessList sharedProcessList]
	 addObserver:self
	 forKeyPath:@"runningProcesses"
	 options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew
	 context:NULL];
	
	[[NSNotificationCenter defaultCenter]
	 addObserver:self
	 selector:@selector(runningApplicationsPopUpButtonWillPopUp:)
	 name:NSPopUpButtonWillPopUpNotification
	 object:self.runningApplicationsPopUpButton];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (object == [ZGProcessList sharedProcessList])
	{
		[self updateRunningProcesses];
		[self processListChanged:change];
	}
}

- (void)processListChanged:(NSDictionary *)change
{
}

- (void)currentProcessChanged
{
}

- (void)setCurrentProcess:(ZGProcess *)newProcess
{
	BOOL shouldUpdateDisplay = NO;
	
	if (_currentProcess.processID != newProcess.processID)
	{
		[self.undoManager removeAllActions];
		
		if (_currentProcess)
		{
			[[ZGProcessList sharedProcessList] removePriorityToProcessIdentifier:_currentProcess.processID withObserver:self];
		}
		if (newProcess.valid)
		{
			[[ZGProcessList sharedProcessList] addPriorityToProcessIdentifier:newProcess.processID withObserver:self];
		}
		
		shouldUpdateDisplay = YES;
	}
	_currentProcess = newProcess;
	if (_currentProcess && ![_currentProcess hasGrantedAccess] && _currentProcess.valid)
	{
		if (![_currentProcess grantUsAccess])
		{
			shouldUpdateDisplay = YES;
			NSLog(@"%@ failed to grant access to PID %d", NSStringFromClass([self class]), _currentProcess.processID);
		}
	}
	
	if (shouldUpdateDisplay && self.windowDidAppear)
	{
		[self currentProcessChanged];
	}
	
	[self updateNavigationButtons];
}

- (void)updateRunningProcesses
{
	[self.runningApplicationsPopUpButton removeAllItems];
	
	NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"activationPolicy" ascending:YES];
	for (ZGRunningProcess *runningProcess in  [[[ZGProcessList sharedProcessList] runningProcesses] sortedArrayUsingDescriptors:@[sortDescriptor]])
	{
		if (runningProcess.processIdentifier != NSRunningApplication.currentApplication.processIdentifier)
		{
			NSMenuItem *menuItem = [[NSMenuItem alloc] init];
			menuItem.title = [NSString stringWithFormat:@"%@ (%d)", runningProcess.name, runningProcess.processIdentifier];
			NSImage *iconImage = [runningProcess.icon copy];
			iconImage.size = NSMakeSize(16, 16);
			menuItem.image = iconImage;
			ZGProcess *representedProcess =
				[[ZGProcess alloc]
				 initWithName:runningProcess.name
				 processID:runningProcess.processIdentifier
				 set64Bit:runningProcess.is64Bit];
			
			menuItem.representedObject = representedProcess;
			
			[self.runningApplicationsPopUpButton.menu addItem:menuItem];
			
			if (self.currentProcess.processID == runningProcess.processIdentifier || [self.desiredProcessName isEqualToString:runningProcess.name])
			{
				[self.runningApplicationsPopUpButton selectItem:self.runningApplicationsPopUpButton.lastItem];
			}
		}
	}
	
	// Handle dead process
	if (self.desiredProcessName && ![self.desiredProcessName isEqualToString:[self.runningApplicationsPopUpButton.selectedItem.representedObject name]])
	{
		NSMenuItem *menuItem = [[NSMenuItem alloc] init];
		menuItem.title = [NSString stringWithFormat:@"%@ (none)", self.desiredProcessName];
		NSImage *iconImage = [[NSImage imageNamed:@"NSDefaultApplicationIcon"] copy];
		iconImage.size = NSMakeSize(16, 16);
		menuItem.image = iconImage;
		menuItem.representedObject = [[ZGProcess alloc] initWithName:self.desiredProcessName set64Bit:YES];
		[self.runningApplicationsPopUpButton.menu addItem:menuItem];
		[self.runningApplicationsPopUpButton selectItem:self.runningApplicationsPopUpButton.lastItem];
		
		[[ZGProcessList sharedProcessList] requestPollingWithObserver:self];
	}
	else
	{
		[[ZGProcessList sharedProcessList] unrequestPollingWithObserver:self];
	}
	
	self.currentProcess = self.runningApplicationsPopUpButton.selectedItem.representedObject;
}

- (void)runningApplicationsPopUpButtonWillPopUp:(NSNotification *)notification
{
	[[ZGProcessList sharedProcessList] retrieveList];
}

- (void)switchProcess
{
	self.desiredProcessName = [self.runningApplicationsPopUpButton.selectedItem.representedObject name];
	[[ZGAppController sharedController] setLastSelectedProcessName:self.desiredProcessName];
	self.currentProcess = self.runningApplicationsPopUpButton.selectedItem.representedObject;
	[self.navigationManager removeAllActions];
	[self updateNavigationButtons];
}

#pragma mark Navigation

- (IBAction)goBack:(id)sender
{
	[self.navigationManager undo];
	[self updateNavigationButtons];
}

- (IBAction)goForward:(id)sender
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

#pragma mark Pausing

- (IBAction)pauseOrUnpauseProcess:(id)sender
{
	[ZGProcess pauseOrUnpauseProcessTask:self.currentProcess.processTask];
}

#pragma mark Menu Item Validation

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)userInterfaceItem
{
	NSMenuItem *menuItem = [[(NSObject *)userInterfaceItem class] isKindOfClass:[NSMenuItem class]] ? (NSMenuItem *)userInterfaceItem : nil;
	
	if (userInterfaceItem.action == @selector(pauseOrUnpauseProcess:))
	{
		if (!self.currentProcess.valid)
		{
			return NO;
		}
		
		integer_t suspendCount;
		if (!ZGSuspendCount(self.currentProcess.processTask, &suspendCount))
		{
			return NO;
		}
		else
		{
			[menuItem setTitle:[NSString stringWithFormat:@"%@ Target", suspendCount > 0 ? @"Unpause" : @"Pause"]];
		}
		
		if ([[[ZGAppController sharedController] debuggerController] isProcessIdentifierHalted:self.currentProcess.processID])
		{
			return NO;
		}
	}
	else if (userInterfaceItem.action == @selector(goBack:) || userInterfaceItem.action == @selector(goForward:))
	{
		if (![self canEnableNavigationButtons])
		{
			return NO;
		}
		
		if ((userInterfaceItem.action == @selector(goBack:) && !self.navigationManager.canUndo) || (userInterfaceItem.action == @selector(goForward:) && !self.navigationManager.canRedo))
		{
			return NO;
		}
	}
	
	return YES;
}

@end
