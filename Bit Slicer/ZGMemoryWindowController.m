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
#import "ZGDebuggerController.h" // For seeing if we can pause/unpause a process
#import "ZGProcessList.h"
#import "ZGRunningProcess.h"
#import "ZGProcess.h"
#import "ZGVirtualMemory.h"
#import "ZGUtilities.h"

NSString *ZGLastChosenInternalProcessNameNotification = @"ZGLastChosenInternalProcessNameNotification";
NSString *ZGLastChosenInternalProcessNameKey = @"ZGLastChosenInternalProcessNameKey";

@interface ZGMemoryWindowController ()

@property (nonatomic) ZGProcessTaskManager *processTaskManager;
@property (nonatomic) ZGProcessList *processList;

@property (nonatomic, copy) NSString *lastChosenInternalProcessName;

@end

@implementation ZGMemoryWindowController

#pragma mark Birth

- (id)initWithProcessTaskManager:(ZGProcessTaskManager *)processTaskManager
{
	self = [super initWithWindowNibName:NSStringFromClass([self class])];
	
	if (self != nil)
	{
		self.processTaskManager = processTaskManager;
		
		self.undoManager = [[NSUndoManager alloc] init];
		self.navigationManager = [[NSUndoManager alloc] init];
		
		[[NSNotificationCenter defaultCenter]
		 addObserver:self
		 selector:@selector(lastChosenInternalProcessNameChanged:)
		 name:ZGLastChosenInternalProcessNameNotification
		 object:nil];
	}
	
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter]
	 removeObserver:self
	 name:ZGLastChosenInternalProcessNameNotification
	 object:nil];
}

- (void)lastChosenInternalProcessNameChanged:(NSNotification *)notification
{
	if (notification.object != self)
	{
		self.lastChosenInternalProcessName = [notification.userInfo objectForKey:ZGLastChosenInternalProcessNameKey];
	}
}

- (void)postLastChosenInternalProcessNameChange
{
	[[NSNotificationCenter defaultCenter]
	 postNotificationName:ZGLastChosenInternalProcessNameNotification
	 object:self
	 userInfo:@{ZGLastChosenInternalProcessNameKey : self.lastChosenInternalProcessName}];
}

- (NSUndoManager *)windowWillReturnUndoManager:(id)sender
{
	return self.undoManager;
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
		
		[self.processList removePriorityToProcessIdentifier:self.currentProcess.processID withObserver:self];
		[self.processList unrequestPollingWithObserver:self];
	}
	else
	{
		if (self.updateDisplayTimer == nil)
		{
			[self makeUpdateDisplayTimer];
		}
		
		[self.processList retrieveList];
		
		if (self.currentProcess.valid)
		{
			[self.processList addPriorityToProcessIdentifier:self.currentProcess.processID withObserver:self];
		}
		else
		{
			[self.processList requestPollingWithObserver:self];
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

- (void)updateWindow
{
	[self.processList retrieveList];
	
	if (self.updateDisplayTimer == nil)
	{
		[self makeUpdateDisplayTimer];
	}
	
	if (self.currentProcess != nil)
	{
		if (self.currentProcess.valid)
		{
			[self.processList addPriorityToProcessIdentifier:self.currentProcess.processID withObserver:self];
		}
		else
		{
			[self.processList requestPollingWithObserver:self];
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
			[self.processList removePriorityToProcessIdentifier:self.currentProcess.processID withObserver:self];
		}
		
		[self.processList unrequestPollingWithObserver:self];
	}
}

#pragma mark Process Handling

- (void)setupProcessListNotificationsAndPopUpButton
{
	self.processList = [[ZGProcessList alloc] initWithProcessTaskManager:self.processTaskManager];
	
	// Add processes to popup button
	self.desiredProcessInternalName = self.lastChosenInternalProcessName;
	[self updateRunningProcesses];
	
	[self.processList
	 addObserver:self
	 forKeyPath:@"runningProcesses"
	 options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew
	 context:NULL];
	
	// Still need to observe this for reliably fetching icon and localized name
	[[NSWorkspace sharedWorkspace]
	 addObserver:self
	 forKeyPath:@"runningApplications"
	 options:NSKeyValueObservingOptionNew
	 context:NULL];
	
	[[NSNotificationCenter defaultCenter]
	 addObserver:self
	 selector:@selector(runningApplicationsPopUpButtonWillPopUp:)
	 name:NSPopUpButtonWillPopUpNotification
	 object:self.runningApplicationsPopUpButton];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (object == self.processList)
	{
		for (ZGRunningProcess *runningProcess in [change objectForKey:NSKeyValueChangeOldKey])
		{
			if ([self.processTaskManager taskExistsForProcessIdentifier:runningProcess.processIdentifier])
			{
				[self.processTaskManager freeTaskForProcessIdentifier:runningProcess.processIdentifier];
			}
		}
		
		[self updateRunningProcesses];
		[self processListChanged:change];
	}
	else if (object == [NSWorkspace sharedWorkspace])
	{
		NSArray *newRunningProcesses = [change objectForKey:NSKeyValueChangeNewKey];
		
		// ZGProcessList may report processes to us faster than NSRunningApplication can ocasionally
		// So be sure to get updated localized name and icon
		for (NSRunningApplication *runningApplication in newRunningProcesses)
		{
			for (NSMenuItem *menuItem in self.runningApplicationsPopUpButton.itemArray)
			{
				ZGProcess *representedProcess = [menuItem representedObject];
				if (representedProcess.processID == runningApplication.processIdentifier)
				{
					representedProcess.name = runningApplication.localizedName;
					ZGUpdateProcessMenuItem(menuItem, runningApplication.localizedName, runningApplication.processIdentifier, runningApplication.icon);
					break;
				}
			}
		}
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
			[self.processList removePriorityToProcessIdentifier:_currentProcess.processID withObserver:self];
		}
		if (newProcess.valid)
		{
			[self.processList addPriorityToProcessIdentifier:newProcess.processID withObserver:self];
		}
		
		shouldUpdateDisplay = YES;
	}
	_currentProcess = newProcess;
	if (_currentProcess && ![_currentProcess hasGrantedAccess] && _currentProcess.valid)
	{
		if (!ZGGrantMemoryAccessToProcess(self.processTaskManager, _currentProcess))
		{
			shouldUpdateDisplay = YES;
			NSLog(@"%@ failed to grant access to PID %d", NSStringFromClass([self class]), _currentProcess.processID);
		}
	}
	
	if (shouldUpdateDisplay)
	{
		[self currentProcessChanged];
	}
	
	[self updateNavigationButtons];
}

- (void)updateRunningProcesses
{
	[self.runningApplicationsPopUpButton removeAllItems];
	
	NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"activationPolicy" ascending:YES];
	BOOL foundTargetProcess = NO;
	for (ZGRunningProcess *runningProcess in  [self.processList.runningProcesses sortedArrayUsingDescriptors:@[sortDescriptor]])
	{
		if (runningProcess.processIdentifier != NSRunningApplication.currentApplication.processIdentifier)
		{
			NSMenuItem *menuItem = [[NSMenuItem alloc] init];
			ZGUpdateProcessMenuItem(menuItem, runningProcess.name, runningProcess.processIdentifier, runningProcess.icon);
			
			ZGProcess *representedProcess =
				[[ZGProcess alloc]
				 initWithName:runningProcess.name
				 internalName:runningProcess.internalName
				 processID:runningProcess.processIdentifier
				 is64Bit:runningProcess.is64Bit];
			
			menuItem.representedObject = representedProcess;
			
			[self.runningApplicationsPopUpButton.menu addItem:menuItem];
			
			if ((self.currentProcess.processID == runningProcess.processIdentifier || !foundTargetProcess) && [self.desiredProcessInternalName isEqualToString:runningProcess.internalName])
			{
				[self.runningApplicationsPopUpButton selectItem:self.runningApplicationsPopUpButton.lastItem];
				foundTargetProcess = YES;
			}
		}
	}
	
	// Handle dead process
	if (self.desiredProcessInternalName != nil && ![self.desiredProcessInternalName isEqualToString:[self.runningApplicationsPopUpButton.selectedItem.representedObject internalName]])
	{
		NSMenuItem *menuItem = [[NSMenuItem alloc] init];
		ZGUpdateProcessMenuItem(menuItem, self.desiredProcessInternalName, -1, nil);
		
		menuItem.representedObject = [[ZGProcess alloc] initWithName:nil internalName:self.desiredProcessInternalName is64Bit:YES];
		[self.runningApplicationsPopUpButton.menu addItem:menuItem];
		[self.runningApplicationsPopUpButton selectItem:self.runningApplicationsPopUpButton.lastItem];
		
		[self.processList requestPollingWithObserver:self];
	}
	else
	{
		[self.processList unrequestPollingWithObserver:self];
	}
	
	self.currentProcess = self.runningApplicationsPopUpButton.selectedItem.representedObject;
}

- (void)runningApplicationsPopUpButtonWillPopUp:(NSNotification *)notification
{
	[self.processList retrieveList];
}

- (void)switchProcess
{
	self.desiredProcessInternalName = [self.runningApplicationsPopUpButton.selectedItem.representedObject internalName];
	
	if (self.desiredProcessInternalName != nil)
	{
		self.lastChosenInternalProcessName = self.desiredProcessInternalName;
		[self postLastChosenInternalProcessNameChange];
	}
	
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
		
		if ([self.debuggerController isProcessIdentifierHalted:self.currentProcess.processID])
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
