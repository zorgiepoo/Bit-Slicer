/*
 * Copyright (c) 2013 Mayur Pawashe
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
#import "ZGProcessTaskManager.h"
#import "ZGRootlessConfiguration.h"
#import "ZGBreakPoint.h" // For seeing if we can pause/unpause a process
#import "NSArrayAdditions.h"
#import "ZGProcessList.h"
#import "ZGRunningProcess.h"
#import "ZGProcess.h"
#import "ZGVirtualMemory.h"
#import "ZGMemoryDumpAllWindowController.h"
#import "ZGMemoryDumpRangeWindowController.h"
#import "ZGMemoryProtectionWindowController.h"
#import "ZGMachBinary.h"
#import "ZGMachBinaryInfo.h"
#import "ZGStaticSelectorChecker.h"
#import "ZGDebugLogging.h"
#import "ZGNullability.h"

#define ZGLocalizedStringFromMemoryWindowTable(string) NSLocalizedStringFromTable((string), @"[Code] Memory Window", nil)

@implementation ZGMemoryWindowController
{
	BOOL _isWatchingActiveProcess;
	BOOL _inactiveProcessSuspended;
	
	ZGMemoryDumpAllWindowController * _Nullable _memoryDumpAllWindowController;
	ZGMemoryDumpRangeWindowController * _Nullable _memoryDumpRangeWindowController;
	ZGMemoryProtectionWindowController * _Nullable _memoryProtectionWindowController;
	
	NSUndoManager * _Nullable _undoManager;
	NSTimer * _Nullable _updateDisplayTimer;
}

#pragma mark Birth

- (id)initWithProcessTaskManager:(ZGProcessTaskManager *)processTaskManager rootlessConfiguration:(ZGRootlessConfiguration *)rootlessConfiguration delegate:(id <ZGChosenProcessDelegate, ZGMemorySelectionDelegate, ZGShowMemoryWindow>)delegate
{
	self = [super init];
	
	if (self != nil)
	{
		_processTaskManager = processTaskManager;
		_rootlessConfiguration = rootlessConfiguration;
		_delegate = delegate;
	}
	
	return self;
}

- (NSUndoManager *)undoManager
{
	if (_undoManager == nil)
	{
		_undoManager = [[NSUndoManager alloc] init];
	}
	return (NSUndoManager * _Nonnull)_undoManager;
}

- (void)cleanup
{
	[self stopPausingProcessWhenInactive];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter]
	 removeObserver:self
	 name:NSWindowDidChangeOcclusionStateNotification
	 object:nil];
	
	[[NSWorkspace sharedWorkspace]
	 removeObserver:self
	 forKeyPath:ZG_SELECTOR_STRING([NSWorkspace sharedWorkspace], runningApplications)];
	
	[_processList removeObserver:self forKeyPath:ZG_SELECTOR_STRING(_processList, runningProcesses)];
	
	[self cleanup];
}

- (void)postLastChosenInternalProcessNameChange
{
	id <ZGChosenProcessDelegate> delegate = _delegate;
	[delegate memoryWindowController:self didChangeProcessInternalName:ZGUnwrapNullableObject(_lastChosenInternalProcessName)];
}

- (void)setAndPostLastChosenInternalProcessName
{
	if (_currentProcess.valid)
	{
		_lastChosenInternalProcessName = _currentProcess.internalName;
		[self postLastChosenInternalProcessNameChange];
	}
}

- (NSUndoManager *)windowWillReturnUndoManager:(id)__unused sender
{
	return [self undoManager];
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
		_updateDisplayTimer =
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
	[_updateDisplayTimer invalidate];
	_updateDisplayTimer = nil;
}

- (void)startProcessActivity
{
	if (_updateDisplayTimer == nil)
	{
		[self makeUpdateDisplayTimer];
	}
	
	[_processList retrieveList];
	
	if (_currentProcess.valid)
	{
		[_processList addPriorityToProcessIdentifier:_currentProcess.processID withObserver:self];
	}
	else
	{
		[_processList requestPollingWithObserver:self];
	}
}

- (void)stopProcessActivity
{
	[self destroyUpdateDisplayTimer];
	
	if (_currentProcess.valid)
	{
		[_processList removePriorityToProcessIdentifier:_currentProcess.processID withObserver:self];
	}
	else
	{
		[_processList unrequestPollingWithObserver:self];
	}
}

- (void)updateOcclusionActivity
{
	if (!_isOccluded)
	{
		[self startProcessActivity];
	}
	else
	{
		[self stopProcessActivity];
	}
}

- (void)windowDidChangeOcclusionState:(NSNotification *)__unused notification
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
	_isOccluded = ([self.window occlusionState] & NSWindowOcclusionStateVisible) == 0;
#pragma clang diagnostic pop
	[self updateOcclusionActivity];
}

- (void)windowDidLoad
{
	[[NSNotificationCenter defaultCenter]
	 addObserver:self
	 selector:@selector(windowDidChangeOcclusionState:)
	 name:NSWindowDidChangeOcclusionStateNotification
	 object:self.window];
}

- (void)updateWindow
{
	[_processList retrieveList];
	
	if (_updateDisplayTimer == nil)
	{
		[self makeUpdateDisplayTimer];
	}
	
	if (_currentProcess != nil)
	{
		if (_currentProcess.valid)
		{
			[_processList addPriorityToProcessIdentifier:_currentProcess.processID withObserver:self];
		}
		else
		{
			[_processList requestPollingWithObserver:self];
		}
	}
}

- (void)windowWillClose:(NSNotification *)notification
{
	if ([notification object] == self.window)
	{
		[self destroyUpdateDisplayTimer];
		
		if (_currentProcess.valid)
		{
			[_processList removePriorityToProcessIdentifier:_currentProcess.processID withObserver:self];
		}
		
		[_processList unrequestPollingWithObserver:self];
	}
}

#pragma mark Process Handling

- (void)setupProcessListNotifications
{
	_processList = [[ZGProcessList alloc] initWithProcessTaskManager:_processTaskManager];
	
	[_processList
	 addObserver:self
	 forKeyPath:ZG_SELECTOR_STRING(_processList, runningProcesses)
	 options:(NSKeyValueObservingOptions)(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
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
	 object:_runningApplicationsPopUpButton];
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

- (void)observeValueForKeyPath:(NSString *)__unused keyPath ofObject:(id)object change:(NSDictionary<NSString *, id> *)change context:(void *)__unused context
{
	if (object == _processList)
	{
		for (ZGRunningProcess *runningProcess in change[NSKeyValueChangeOldKey])
		{
			if ([_processTaskManager taskExistsForProcessIdentifier:runningProcess.processIdentifier])
			{
				[_processTaskManager freeTaskForProcessIdentifier:runningProcess.processIdentifier];
			}
		}
		
		[self updateRunningProcesses];
		[self processListChanged:change];
	}
	else if (object == [NSWorkspace sharedWorkspace])
	{
		NSArray<NSRunningApplication *> *newRunningProcesses = change[NSKeyValueChangeNewKey];
		NSArray<ZGRunningProcess *> *currentRunningProcesses = _processList.runningProcesses;
		
		// ZGProcessList may report processes to us faster than NSRunningApplication can ocasionally
		// So be sure to get updated localized name and icon
		for (NSRunningApplication *runningApplication in newRunningProcesses)
		{
			assert([runningApplication isKindOfClass:[NSRunningApplication class]]);

			pid_t runningProcessIdentifier = runningApplication.processIdentifier;
			// when the running proccess identifier is -1, nothing useful is filled out in the NSRunningApplication instance
			if (runningProcessIdentifier != -1)
			{
				for (NSMenuItem *menuItem in _runningApplicationsPopUpButton.itemArray)
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

- (void)processListChanged:(NSDictionary<NSString *, id> *)__unused change
{
}

- (void)currentProcessChangedWithOldProcess:(nullable ZGProcess *)__unused oldProcess newProcess:(ZGProcess *)__unused newProcess
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
		[[self undoManager] removeAllActions];
		
		if (_currentProcess)
		{
			[_processList removePriorityToProcessIdentifier:_currentProcess.processID withObserver:self];
		}
		if (newProcess.valid)
		{
			[_processList addPriorityToProcessIdentifier:newProcess.processID withObserver:self];
		}
		
		[self stopPausingProcessWhenInactive];
		
		shouldUpdateDisplay = YES;
	}
	
	ZGProcess *oldProcess = _currentProcess;
	_currentProcess = newProcess;
	
	if (_currentProcess != nil && ![_currentProcess hasGrantedAccess] && _currentProcess.valid)
	{
		BOOL grantedAccess = NO;
		_currentProcess = ZGGrantMemoryAccessToProcess(_processTaskManager, _currentProcess, &grantedAccess);
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
	NSMutableDictionary<NSNumber *, ZGProcess *> *oldProcessesDictionary = [[NSMutableDictionary alloc] init];
	for (NSMenuItem *oldMenuItem in _runningApplicationsPopUpButton.itemArray)
	{
		ZGProcess *oldProcess = oldMenuItem.representedObject;
		[oldProcessesDictionary setObject:oldProcess forKey:@(oldProcess.processID)];
	}
	
	[_runningApplicationsPopUpButton removeAllItems];
	
	pid_t ourProcessIdentifier = NSRunningApplication.currentApplication.processIdentifier;
	
	BOOL foundTargetProcess = NO;
	for (ZGRunningProcess *runningProcess in  [_processList.runningProcesses sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:ZG_SELECTOR_STRING(runningProcess, isGame) ascending:NO], [NSSortDescriptor sortDescriptorWithKey:ZG_SELECTOR_STRING(runningProcess, activationPolicy) ascending:YES], [NSSortDescriptor sortDescriptorWithKey:ZG_SELECTOR_STRING(runningProcess, isThirdParty) ascending:NO], [NSSortDescriptor sortDescriptorWithKey:ZG_SELECTOR_STRING(runningProcess, hasHelpers) ascending:YES], [NSSortDescriptor sortDescriptorWithKey:ZG_SELECTOR_STRING(runningProcess, isWebContent) ascending:NO], [NSSortDescriptor sortDescriptorWithKey:ZG_SELECTOR_STRING(runningProcess, name) ascending:YES]]])
	{
		if (runningProcess.processIdentifier == ourProcessIdentifier)
		{
			continue;
		}
		
		if (_rootlessConfiguration != nil)
		{
			NSURL *fileURL = runningProcess.fileURL;
			if (fileURL != nil && [_rootlessConfiguration isFileURLAffected:fileURL])
			{
				continue;
			}
		}
		
		if (runningProcess.name == nil)
		{
			continue;
		}
		
		NSMenuItem *menuItem = [[NSMenuItem alloc] init];
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
		
		[_runningApplicationsPopUpButton.menu addItem:menuItem];
		
		if (_currentProcess.isDummy)
		{
			[_runningApplicationsPopUpButton selectItem:_runningApplicationsPopUpButton.lastItem];
			foundTargetProcess = YES;
		}
		else if ((_currentProcess.processID == runningProcess.processIdentifier || !foundTargetProcess) && [_desiredProcessInternalName isEqualToString:runningProcess.internalName])
		{
			[_runningApplicationsPopUpButton selectItem:_runningApplicationsPopUpButton.lastItem];
			foundTargetProcess = YES;
		}
	}
	
	// Handle dead process
	ZGProcess *selectedProcess = _runningApplicationsPopUpButton.selectedItem.representedObject;
	if (selectedProcess == nil || (_desiredProcessInternalName != nil && ![_desiredProcessInternalName isEqualToString:selectedProcess.internalName]))
	{
		NSMenuItem *menuItem = [[NSMenuItem alloc] init];
		NSString *nameToUse = (_desiredProcessInternalName != nil) ? _desiredProcessInternalName : ZGLocalizedStringFromMemoryWindowTable(@"noTargetAvailable");
		[[self class] updateProcessMenuItem:menuItem name:nameToUse processIdentifier:-1 icon:nil];
		
		ZGProcess *deadProcess = [[ZGProcess alloc] initWithName:nil internalName:nameToUse is64Bit:YES];
		if (_desiredProcessInternalName == nil)
		{
			// we want to change the target whenever one comes online regardless of what it is
			deadProcess.isDummy = YES;
		}
		
		menuItem.representedObject = deadProcess;

		[_runningApplicationsPopUpButton.menu insertItem:menuItem atIndex:0];
		[_runningApplicationsPopUpButton selectItem:menuItem];

		[_processList requestPollingWithObserver:self];
		
		[self stopPausingProcessWhenInactive];
	}
	else
	{
		[_processList unrequestPollingWithObserver:self];
	}

	[self setCurrentProcess:ZGUnwrapNullableObject(_runningApplicationsPopUpButton.selectedItem.representedObject)];
	if (!_currentProcess.isDummy)
	{
		[self setDesiredProcessInternalName:_currentProcess.internalName];
	}
}

- (void)runningApplicationsPopUpButtonWillPopUp:(NSNotification *)__unused notification
{
	[_processList retrieveList];
}

- (IBAction)runningApplicationsPopUpButton:(id)__unused sender
{
	ZGProcess *process = _runningApplicationsPopUpButton.selectedItem.representedObject;
	if (process.processID != _currentProcess.processID)
	{
		[self switchProcess];
	}
}

- (void)switchProcess
{
	[self setDesiredProcessInternalName:[(ZGProcess *)_runningApplicationsPopUpButton.selectedItem.representedObject internalName]];
	
	if (_desiredProcessInternalName != nil)
	{
		_lastChosenInternalProcessName = _desiredProcessInternalName;
		[self postLastChosenInternalProcessNameChange];
	}
	
	[self setCurrentProcess:ZGUnwrapNullableObject(_runningApplicationsPopUpButton.selectedItem.representedObject)];
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
	[[self class] pauseOrUnpauseProcessTask:_currentProcess.processTask];
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
		BOOL validProcess = _currentProcess.valid;
		ZGMemoryMap processTask = _currentProcess.processTask;
		
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
	[self setIsWatchingActiveProcess:NO];
	[self setInactiveProcessSuspended:NO];
}

- (IBAction)pauseProcessWhenInactive:(id)__unused sender
{
	NSRunningApplication *runningApplication = [NSRunningApplication runningApplicationWithProcessIdentifier:_currentProcess.processID];
	
	if (!_isWatchingActiveProcess)
	{
		if (runningApplication != nil && !runningApplication.isActive)
		{
			[self setInactiveProcessSuspended:YES];
		}
	}
	else
	{
		[self setInactiveProcessSuspended:NO];
	}
	
	[self setIsWatchingActiveProcess:!_isWatchingActiveProcess];
}

- (void)activeApplicationChanged:(NSNotification *)notification
{
	NSRunningApplication *runningApplication = [notification.userInfo objectForKey:NSWorkspaceApplicationKey];
	
	if (runningApplication != nil && runningApplication.processIdentifier == _currentProcess.processID)
	{
		[self setInactiveProcessSuspended:NO];
	}
	else
	{
		[self setInactiveProcessSuspended:YES];
	}
}

- (BOOL)isProcessIdentifier:(pid_t)processIdentifier inHaltedBreakPoints:(NSArray<ZGBreakPoint *> *)haltedBreakPoints
{
	return [haltedBreakPoints zgHasObjectMatchingCondition:^BOOL (ZGBreakPoint *breakPoint) { return (breakPoint.process.processID == processIdentifier); }];
}

- (BOOL)isProcessIdentifierHalted:(pid_t)__unused processIdentifier
{
	return NO;
}

#pragma mark Menu Item Validation

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)userInterfaceItem
{
	NSMenuItem *menuItem = [(id <NSObject>)userInterfaceItem isKindOfClass:[NSMenuItem class]] ? (NSMenuItem *)userInterfaceItem : nil;
	
	if (userInterfaceItem.action == @selector(pauseOrUnpauseProcess:))
	{
		menuItem.title = ZGLocalizedStringFromMemoryWindowTable(@"pauseTargetProcess"); // the default
		
		if (!_currentProcess.valid)
		{
			return NO;
		}
		
		integer_t suspendCount;
		if (!ZGSuspendCount(_currentProcess.processTask, &suspendCount))
		{
			return NO;
		}
		else
		{
			NSString *localizableKey = suspendCount > 0 ? @"unpauseTargetProcess" : @"pauseTargetProcess";
			menuItem.title = ZGLocalizedStringFromMemoryWindowTable(localizableKey);
		}
		
		if ([self isProcessIdentifierHalted:_currentProcess.processID])
		{
			return NO;
		}
	}
	else if (userInterfaceItem.action == @selector(pauseProcessWhenInactive:))
	{
		menuItem.state = _isWatchingActiveProcess ? NSOnState : NSOffState;;
		
		if (!_currentProcess.valid)
		{
			return NO;
		}
		
		NSRunningApplication *runningApplication = [NSRunningApplication runningApplicationWithProcessIdentifier:_currentProcess.processID];
		if (runningApplication == nil)
		{
			return NO;
		}
	}
	else if (userInterfaceItem.action == @selector(dumpAllMemory:) || userInterfaceItem.action == @selector(dumpMemoryInRange:))
	{
		if (!_currentProcess.valid || _memoryDumpAllWindowController.isBusy)
		{
			return NO;
		}
	}
	else if (userInterfaceItem.action == @selector(changeMemoryProtection:))
	{
		if (!_currentProcess.valid)
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
	ZGMachBinaryInfo *mainBinaryInfo = [_currentProcess.mainMachBinary machBinaryInfoInProcess:_currentProcess];
	NSRange totalSegmentRange = mainBinaryInfo.totalSegmentRange;
	return HFRangeMake(totalSegmentRange.location, totalSegmentRange.length);
}

#pragma mark Dumping Memory

- (IBAction)dumpAllMemory:(id)__unused sender
{
	if (_memoryDumpAllWindowController == nil)
	{
		_memoryDumpAllWindowController = [[ZGMemoryDumpAllWindowController alloc] init];
	}
	
	[_memoryDumpAllWindowController attachToWindow:ZGUnwrapNullableObject(self.window) withProcess:_currentProcess];
}

- (IBAction)dumpMemoryInRange:(id)__unused sender
{
	if (_memoryDumpRangeWindowController == nil)
	{
		_memoryDumpRangeWindowController = [[ZGMemoryDumpRangeWindowController alloc] init];
	}
	
	[_memoryDumpRangeWindowController
	 attachToWindow:ZGUnwrapNullableObject(self.window)
	 withProcess:_currentProcess
	 requestedAddressRange:[self preferredMemoryRequestRange]];
}

#pragma mark Memory Protection Change

- (IBAction)changeMemoryProtection:(id)__unused sender
{
	if (_memoryProtectionWindowController == nil)
	{
		_memoryProtectionWindowController = [[ZGMemoryProtectionWindowController alloc] init];
	}
	
	[_memoryProtectionWindowController
	 attachToWindow:ZGUnwrapNullableObject(self.window)
	 withProcess:_currentProcess
	 requestedAddressRange:[self preferredMemoryRequestRange]
	 undoManager:[self undoManager]];
}

@end
