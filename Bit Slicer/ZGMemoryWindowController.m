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
#import "ZGMemoryDumpAllWindowController.h"
#import "ZGMemoryDumpRangeWindowController.h"
#import "ZGMemoryProtectionWindowController.h"
#import "ZGMachBinary.h"
#import "ZGMachBinaryInfo.h"
#import "ZGUtilities.h"

#define ZGLocalizedStringFromMemoryWindowTable(string) NSLocalizedStringFromTable((string), @"[Code] Memory Window", nil)

NSString *ZGLastChosenInternalProcessNameNotification = @"ZGLastChosenInternalProcessNameNotification";
NSString *ZGLastChosenInternalProcessNameKey = @"ZGLastChosenInternalProcessNameKey";

@interface ZGMemoryWindowController ()

@property (nonatomic) BOOL isWatchingActiveProcess;
@property (nonatomic) BOOL inactiveProcessSuspended;

@property (nonatomic) BOOL isOccluded;

@property (nonatomic) ZGMemoryDumpAllWindowController *memoryDumpAllWindowController;
@property (nonatomic) ZGMemoryDumpRangeWindowController *memoryDumpRangeWindowController;
@property (nonatomic) ZGMemoryProtectionWindowController *memoryProtectionWindowController;

@end

@implementation ZGMemoryWindowController

#pragma mark Birth

- (id)initWithProcessTaskManager:(ZGProcessTaskManager *)processTaskManager
{
	self = [super init];
	
	if (self != nil)
	{
		self.processTaskManager = processTaskManager;
	}
	
	return self;
}

- (NSUndoManager *)undoManager
{
	if (_undoManager == nil)
	{
		_undoManager = [[NSUndoManager alloc] init];
	}
	return _undoManager;
}

- (void)cleanup
{
	[self stopPausingProcessWhenInactive];
}

- (void)dealloc
{
	if ([self.window respondsToSelector:@selector(occlusionState)])
	{
		[[NSNotificationCenter defaultCenter]
		 removeObserver:self
		 name:NSWindowDidChangeOcclusionStateNotification
		 object:nil];
	}
	
	[[NSWorkspace sharedWorkspace]
	 removeObserver:self
	 forKeyPath:ZG_SELECTOR_STRING([NSWorkspace sharedWorkspace], runningApplications)];
	
	[self.processList removeObserver:self forKeyPath:ZG_SELECTOR_STRING(self.processList, runningProcesses)];
	
	[self cleanup];
}

- (void)postLastChosenInternalProcessNameChange
{
	[[NSNotificationCenter defaultCenter]
	 postNotificationName:ZGLastChosenInternalProcessNameNotification
	 object:self
	 userInfo:@{ZGLastChosenInternalProcessNameKey : self.lastChosenInternalProcessName}];
}

- (void)setAndPostLastChosenInternalProcessName
{
	if (self.currentProcess.valid)
	{
		self.lastChosenInternalProcessName = self.currentProcess.internalName;
		[self postLastChosenInternalProcessNameChange];
	}
}

- (NSUndoManager *)windowWillReturnUndoManager:(id)__unused sender
{
	return self.undoManager;
}

- (double)displayMemoryTimeInterval
{
	return 0.5;
}

- (BOOL)hasDefaultUpdateDisplayTimer
{
	return YES;
}

- (void)updateDisplayTimer:(NSTimer *)__unused timer
{
}

- (void)makeUpdateDisplayTimer
{
	if ([self hasDefaultUpdateDisplayTimer])
	{
		self.updateDisplayTimer =
		[NSTimer
		 scheduledTimerWithTimeInterval:[self displayMemoryTimeInterval]
		 target:self
		 selector:@selector(updateDisplayTimer:)
		 userInfo:nil
		 repeats:YES];
	}
}

- (void)destroyUpdateDisplayTimer
{
	[self.updateDisplayTimer invalidate];
	self.updateDisplayTimer = nil;
}

- (void)startProcessActivity
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

- (void)stopProcessActivity
{
	[self destroyUpdateDisplayTimer];
	
	if (self.currentProcess.valid)
	{
		[self.processList removePriorityToProcessIdentifier:self.currentProcess.processID withObserver:self];
	}
	else
	{
		[self.processList unrequestPollingWithObserver:self];
	}
}

- (void)updateOcclusionActivity
{
	if ([self.window respondsToSelector:@selector(occlusionState)])
	{
		if (!self.isOccluded)
		{
			[self startProcessActivity];
		}
		else
		{
			[self stopProcessActivity];
		}
	}
}

- (void)windowDidChangeOcclusionState:(NSNotification *)__unused notification
{
	self.isOccluded = ([self.window occlusionState] & NSWindowOcclusionStateVisible) == 0;
	[self updateOcclusionActivity];
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
}

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

- (void)setupProcessListNotifications
{
	self.processList = [[ZGProcessList alloc] initWithProcessTaskManager:self.processTaskManager];
	
	[self.processList
	 addObserver:self
	 forKeyPath:ZG_SELECTOR_STRING(self.processList, runningProcesses)
	 options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew
	 context:NULL];
	
	// Still need to observe this for reliably fetching icon and localized name
	[[NSWorkspace sharedWorkspace]
	 addObserver:self
	 forKeyPath:ZG_SELECTOR_STRING([NSWorkspace sharedWorkspace], runningApplications)
	 options:NSKeyValueObservingOptionNew
	 context:NULL];
	
	[[NSNotificationCenter defaultCenter]
	 addObserver:self
	 selector:@selector(runningApplicationsPopUpButtonWillPopUp:)
	 name:NSPopUpButtonWillPopUpNotification
	 object:self.runningApplicationsPopUpButton];
}

+ (void)updateProcessMenuItem:(NSMenuItem *)menuItem name:(NSString *)name processIdentifier:(pid_t)processIdentifier icon:(NSImage *)icon
{
	BOOL isDead = (processIdentifier < 0);
	if (isDead)
	{
		NSFont *menuFont = [NSFont menuFontOfSize:12]; // don't think there's a real way to get font size if we were to set the non-attributed title
		
		NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:name];
		
		[attributedString addAttribute:NSStrikethroughStyleAttributeName value:@(NSUnderlineStyleSingle) range:NSMakeRange(0, attributedString.length)];
		
		[attributedString addAttribute:NSFontAttributeName value:menuFont range:NSMakeRange(0, attributedString.length)];
		menuItem.attributedTitle = attributedString;
	}
	else
	{
		menuItem.title = [NSString stringWithFormat:@"%@ (%d)", name, processIdentifier];
	}
	
	NSImage *smallIcon = isDead ? [[NSImage imageNamed:@"NSDefaultApplicationIcon"] copy] : [icon copy];
	smallIcon.size = NSMakeSize(16, 16);
	menuItem.image = smallIcon;
}

- (void)observeValueForKeyPath:(NSString *)__unused keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)__unused context
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
		NSArray *currentRunningProcesses = self.processList.runningProcesses;
		
		// ZGProcessList may report processes to us faster than NSRunningApplication can ocasionally
		// So be sure to get updated localized name and icon
		for (NSRunningApplication *runningApplication in newRunningProcesses)
		{
			assert([runningApplication isKindOfClass:[NSRunningApplication class]]);

			pid_t runningProcessIdentifier = runningApplication.processIdentifier;
			// when the running proccess identifier is -1, nothing useful is filled out in the NSRunningApplication instance
			if (runningProcessIdentifier != -1)
			{
				for (NSMenuItem *menuItem in self.runningApplicationsPopUpButton.itemArray)
				{
					ZGProcess *representedProcess = [menuItem representedObject];
					if (representedProcess.processID == runningApplication.processIdentifier)
					{
						NSString *processName = runningApplication.localizedName;
						ZGProcess *newProcess = [[ZGProcess alloc] initWithProcess:representedProcess name:runningApplication.localizedName];

						menuItem.representedObject = newProcess;

						[[self class] updateProcessMenuItem:menuItem name:processName processIdentifier:runningApplication.processIdentifier icon:runningApplication.icon];
						break;
					}
				}

				for (ZGRunningProcess *runningProcess in currentRunningProcesses)
				{
					if (runningProcess.processIdentifier == runningProcess.processIdentifier)
					{
						[runningProcess invalidateAppInfoCache];
					}
				}
			}
		}
	}
}

- (void)processListChanged:(NSDictionary *)__unused change
{
}

- (void)currentProcessChangedWithOldProcess:(ZGProcess *)__unused oldProcess newProcess:(ZGProcess *)__unused newProcess
{
}

static ZGProcess *ZGGrantMemoryAccessToProcess(ZGProcessTaskManager *processTaskManager, ZGProcess *process, BOOL *grantedAccess)
{
	ZGMemoryMap processTask;
	BOOL success = [processTaskManager getTask:&processTask forProcessIdentifier:process.processID];
	
	if (grantedAccess != NULL)
	{
		*grantedAccess = success;
	}
	
	return [[ZGProcess alloc] initWithProcess:process processTask:processTask];
}

- (void)setCurrentProcess:(ZGProcess *)newProcess
{
	BOOL shouldUpdateDisplay = NO;
	
	if (_currentProcess == nil || ![_currentProcess isEqual:newProcess])
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
		
		[self stopPausingProcessWhenInactive];
		
		shouldUpdateDisplay = YES;
	}
	
	ZGProcess *oldProcess = _currentProcess;
	_currentProcess = newProcess;
	
	if (_currentProcess != nil && ![_currentProcess hasGrantedAccess] && _currentProcess.valid)
	{
		BOOL grantedAccess = NO;
		_currentProcess = ZGGrantMemoryAccessToProcess(self.processTaskManager, _currentProcess, &grantedAccess);
		if (!grantedAccess)
		{
			shouldUpdateDisplay = YES;
			ZG_LOG(@"%@ failed to grant access to PID %d", NSStringFromClass([self class]), _currentProcess.processID);
		}
	}
	
	if (shouldUpdateDisplay)
	{
		[self currentProcessChangedWithOldProcess:oldProcess newProcess:newProcess];
	}
}

- (void)updateRunningProcesses
{
	NSMutableDictionary *oldProcessesDictionary = [[NSMutableDictionary alloc] init];
	for (NSMenuItem *oldMenuItem in self.runningApplicationsPopUpButton.itemArray)
	{
		ZGProcess *oldProcess = oldMenuItem.representedObject;
		[oldProcessesDictionary setObject:oldProcess forKey:@(oldProcess.processID)];
	}
	
	[self.runningApplicationsPopUpButton removeAllItems];
	
	pid_t ourProcessIdentifier = NSRunningApplication.currentApplication.processIdentifier;
	
	BOOL foundTargetProcess = NO;
	for (ZGRunningProcess *runningProcess in  [self.processList.runningProcesses sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"activationPolicy" ascending:YES], [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]])
	{
		if (runningProcess.processIdentifier != ourProcessIdentifier)
		{
			NSMenuItem *menuItem = [[NSMenuItem alloc] init];
			assert(runningProcess.name != nil);
			[[self class] updateProcessMenuItem:menuItem name:runningProcess.name processIdentifier:runningProcess.processIdentifier icon:runningProcess.icon];
			
			ZGProcess *oldProcess = [oldProcessesDictionary objectForKey:@(runningProcess.processIdentifier)];
			if (oldProcess != nil)
			{
				menuItem.representedObject = oldProcess;
			}
			else
			{
				ZGProcess *representedProcess =
				[[ZGProcess alloc]
				 initWithName:runningProcess.name
				 internalName:runningProcess.internalName
				 processID:runningProcess.processIdentifier
				 is64Bit:runningProcess.is64Bit];
				
				menuItem.representedObject = representedProcess;
			}
			
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
		[[self class] updateProcessMenuItem:menuItem name:self.desiredProcessInternalName processIdentifier:-1 icon:nil];
		
		menuItem.representedObject = [[ZGProcess alloc] initWithName:nil internalName:self.desiredProcessInternalName is64Bit:YES];

		[self.runningApplicationsPopUpButton.menu insertItem:menuItem atIndex:0];
		[self.runningApplicationsPopUpButton selectItem:menuItem];

		[self.processList requestPollingWithObserver:self];
		
		[self stopPausingProcessWhenInactive];
	}
	else
	{
		[self.processList unrequestPollingWithObserver:self];
	}

	self.currentProcess = self.runningApplicationsPopUpButton.selectedItem.representedObject;
	self.desiredProcessInternalName = self.currentProcess.internalName;
}

- (void)runningApplicationsPopUpButtonWillPopUp:(NSNotification *)__unused notification
{
	[self.processList retrieveList];
}

- (IBAction)runningApplicationsPopUpButton:(id)__unused sender
{
	if ([self.runningApplicationsPopUpButton.selectedItem.representedObject processID] != self.currentProcess.processID)
	{
		[self switchProcess];
	}
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
	[self updateRunningProcesses];
}

#pragma mark Pausing

+ (void)pauseOrUnpauseProcessTask:(ZGMemoryMap)processTask
{
	integer_t suspendCount;
	if (ZGSuspendCount(processTask, &suspendCount))
	{
		if (suspendCount > 0)
		{
			ZGResumeTask(processTask);
		}
		else
		{
			ZGSuspendTask(processTask);
		}
	}
}

- (IBAction)pauseOrUnpauseProcess:(id)__unused sender
{
	[[self class] pauseOrUnpauseProcessTask:self.currentProcess.processTask];
}

- (void)setIsWatchingActiveProcess:(BOOL)isWatchingActiveProcess
{
	if (_isWatchingActiveProcess != isWatchingActiveProcess)
	{
		if (isWatchingActiveProcess)
		{
			[[[NSWorkspace sharedWorkspace] notificationCenter]
			 addObserver:self
			 selector:@selector(activeApplicationChanged:)
			 name:NSWorkspaceDidActivateApplicationNotification
			 object:nil];
		}
		else
		{
			[[[NSWorkspace sharedWorkspace] notificationCenter]
			 removeObserver:self
			 name:NSWorkspaceDidActivateApplicationNotification
			 object:nil];
		}
		
		_isWatchingActiveProcess = isWatchingActiveProcess;
	}
}

- (void)setInactiveProcessSuspended:(BOOL)inactiveProcessSuspended
{
	if (_inactiveProcessSuspended != inactiveProcessSuspended)
	{
		BOOL validProcess = self.currentProcess.valid;
		ZGMemoryMap processTask = self.currentProcess.processTask;
		
		if (validProcess)
		{
			if (inactiveProcessSuspended)
			{
				if (validProcess && ZGSuspendTask(processTask))
				{
					_inactiveProcessSuspended = YES;
				}
			}
			else
			{
				if (validProcess && ZGResumeTask(processTask))
				{
					_inactiveProcessSuspended = NO;
				}
			}
		}
		else
		{
			_inactiveProcessSuspended = NO;
		}
	}
}

- (void)stopPausingProcessWhenInactive
{
	self.isWatchingActiveProcess = NO;
	self.inactiveProcessSuspended = NO;
}

- (IBAction)pauseProcessWhenInactive:(id)__unused sender
{
	NSRunningApplication *runningApplication = [NSRunningApplication runningApplicationWithProcessIdentifier:self.currentProcess.processID];
	
	if (!self.isWatchingActiveProcess)
	{
		if (runningApplication != nil && !runningApplication.isActive)
		{
			self.inactiveProcessSuspended = YES;
		}
	}
	else
	{
		self.inactiveProcessSuspended = NO;
	}
	
	self.isWatchingActiveProcess = !self.isWatchingActiveProcess;
}

- (void)activeApplicationChanged:(NSNotification *)notification
{
	NSRunningApplication *runningApplication = [notification.userInfo objectForKey:NSWorkspaceApplicationKey];
	
	if (runningApplication != nil && runningApplication.processIdentifier == self.currentProcess.processID)
	{
		self.inactiveProcessSuspended = NO;
	}
	else
	{
		self.inactiveProcessSuspended = YES;
	}
}

#pragma mark Menu Item Validation

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)userInterfaceItem
{
	NSMenuItem *menuItem = [(id <NSObject>)userInterfaceItem isKindOfClass:[NSMenuItem class]] ? (NSMenuItem *)userInterfaceItem : nil;
	
	if (userInterfaceItem.action == @selector(pauseOrUnpauseProcess:))
	{
		menuItem.title = ZGLocalizedStringFromMemoryWindowTable(@"pauseTargetProcess"); // the default
		
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
			NSString *localizableKey = suspendCount > 0 ? @"unpauseTargetProcess" : @"pauseTargetProcess";
			menuItem.title = ZGLocalizedStringFromMemoryWindowTable(localizableKey);
		}
		
		if ([self.debuggerController isProcessIdentifierHalted:self.currentProcess.processID])
		{
			return NO;
		}
	}
	else if (userInterfaceItem.action == @selector(pauseProcessWhenInactive:))
	{
		menuItem.state = self.isWatchingActiveProcess;
		
		if (!self.currentProcess.valid)
		{
			return NO;
		}
		
		NSRunningApplication *runningApplication = [NSRunningApplication runningApplicationWithProcessIdentifier:self.currentProcess.processID];
		if (runningApplication == nil)
		{
			return NO;
		}
	}
	else if (userInterfaceItem.action == @selector(dumpAllMemory:) || userInterfaceItem.action == @selector(dumpMemoryInRange:))
	{
		if (!self.currentProcess.valid || self.memoryDumpAllWindowController.isBusy)
		{
			return NO;
		}
	}
	else if (userInterfaceItem.action == @selector(changeMemoryProtection:))
	{
		if (!self.currentProcess.valid)
		{
			return NO;
		}
	}
	
	return YES;
}

#pragma mark Preferred Memory Address Range

// Default implementation
- (HFRange)preferredMemoryRequestRange
{
	ZGMachBinaryInfo *mainBinaryInfo = [self.currentProcess.mainMachBinary machBinaryInfoInProcess:self.currentProcess];
	NSRange totalSegmentRange = mainBinaryInfo.totalSegmentRange;
	return HFRangeMake(totalSegmentRange.location, totalSegmentRange.length);
}

#pragma mark Dumping Memory

- (IBAction)dumpAllMemory:(id)__unused sender
{
	if (self.memoryDumpAllWindowController == nil)
	{
		self.memoryDumpAllWindowController = [[ZGMemoryDumpAllWindowController alloc] init];
	}
	
	[self.memoryDumpAllWindowController attachToWindow:self.window withProcess:self.currentProcess];
}

- (IBAction)dumpMemoryInRange:(id)__unused sender
{
	if (self.memoryDumpRangeWindowController == nil)
	{
		self.memoryDumpRangeWindowController = [[ZGMemoryDumpRangeWindowController alloc] init];
	}
	
	[self.memoryDumpRangeWindowController
	 attachToWindow:self.window
	 withProcess:self.currentProcess
	 requestedAddressRange:[self preferredMemoryRequestRange]];
}

#pragma mark Memory Protection Change

- (IBAction)changeMemoryProtection:(id)__unused sender
{
	if (self.memoryProtectionWindowController == nil)
	{
		self.memoryProtectionWindowController = [[ZGMemoryProtectionWindowController alloc] init];
	}
	
	[self.memoryProtectionWindowController
	 attachToWindow:self.window
	 withProcess:self.currentProcess
	 requestedAddressRange:[self preferredMemoryRequestRange]
	 undoManager:self.undoManager];
}

@end
