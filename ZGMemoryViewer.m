/*
 * Created by Mayur Pawashe on 5/11/11.
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

#import "ZGMemoryViewer.h"
#import "ZGStatusBarRepresenter.h"
#import "ZGLineCountingRepresenter.h"
#import "ZGVerticalScrollerRepresenter.h"
#import "DataInspectorRepresenter.h"
#import "ZGProcess.h"
#import "ZGAppController.h"
#import "ZGUtilities.h"
#import "ZGCalculator.h"
#import "ZGVirtualMemory.h"
#import "ZGProcessList.h"
#import "ZGRunningProcess.h"
#import "ZGMemoryProtectionController.h"
#import "ZGMemoryDumpController.h"
#import "ZGDisassemblerController.h"

#define READ_MEMORY_INTERVAL 0.1
#define DEFAULT_MINIMUM_LINE_DIGIT_COUNT 12

#define ZGMemoryViewerAddressField @"ZGMemoryViewerAddressField"
#define ZGMemoryViewerSizeField @"ZGMemoryViewerSizeField"
#define ZGMemoryViewerAddress @"ZGMemoryViewerAddress"
#define ZGMemoryViewerSize @"ZGMemoryViewerSize"
#define ZGMemoryViewerProcessName @"ZGMemoryViewerProcessName"
#define ZGMemoryViewerShowsDataInspector @"ZGMemoryViewerShowsDataInspector"

#define DEFAULT_SELECTION_LENGTH 4

@interface ZGMemoryViewer ()

@property (readwrite, strong) NSTimer *checkMemoryTimer;

@property (readwrite, strong) ZGStatusBarRepresenter *statusBarRepresenter;
@property (readwrite, strong) ZGLineCountingRepresenter *lineCountingRepresenter;
@property (readwrite, strong) DataInspectorRepresenter *dataInspectorRepresenter;
@property (readwrite) BOOL showsDataInspector;

@property (readwrite) ZGMemoryAddress currentMemoryAddress;
@property (readwrite) ZGMemorySize currentMemorySize;

@property (assign) IBOutlet NSPopUpButton *runningApplicationsPopUpButton;
@property (assign) IBOutlet NSTextField *addressTextField;
@property (assign) IBOutlet HFTextView *textView;

@property (copy, nonatomic) NSString *desiredProcessName;
@property (readwrite, nonatomic) BOOL windowDidAppear;

@property (nonatomic, strong) NSUndoManager *undoManager;

@property (assign, nonatomic) IBOutlet ZGMemoryProtectionController *memoryProtectionController;
@property (assign, nonatomic) IBOutlet ZGMemoryDumpController *memoryDumpController;

@end

@implementation ZGMemoryViewer

#pragma mark Accessors

- (HFRange)selectedAddressRange
{
	HFRange selectedRange = {.location = 0, .length = 0};
	if (self.currentMemorySize > 0)
	{
		selectedRange = [[self.textView.controller.selectedContentsRanges objectAtIndex:0] HFRange];
		selectedRange.location += self.currentMemoryAddress;
	}
	return selectedRange;
}

#pragma mark Setters

- (void)setCurrentProcess:(ZGProcess *)newProcess
{
	BOOL shouldUpdateMemoryView = NO;
	
	if (_currentProcess.processID != newProcess.processID)
	{
		[self.undoManager removeAllActions];
		
		if (_currentProcess)
		{
			[[ZGProcessList sharedProcessList] removePriorityToProcessIdentifier:_currentProcess.processID];
		}
		[[ZGProcessList sharedProcessList] addPriorityToProcessIdentifier:newProcess.processID];
		
		shouldUpdateMemoryView = YES;
	}
	_currentProcess = newProcess;
	if (_currentProcess && ![_currentProcess hasGrantedAccess] && _currentProcess.valid)
	{
		if (![_currentProcess grantUsAccess])
		{
			shouldUpdateMemoryView = YES;
			NSLog(@"Memory viewer failed to grant access to PID %d", _currentProcess.processID);
		}
	}
	
	if (shouldUpdateMemoryView && self.windowDidAppear)
	{
		[self changeMemoryView:nil];
	}
}

#pragma mark Initialization

- (id)init
{
	self = [super initWithWindowNibName:@"MemoryViewer"];
	
	self.selectionLength = DEFAULT_SELECTION_LENGTH;
	self.undoManager = [[NSUndoManager alloc] init];
	
	return self;
}

- (NSUndoManager *)windowWillReturnUndoManager:(id)sender
{
	return self.undoManager;
}

- (void)encodeRestorableStateWithCoder:(NSCoder *)coder
{
    [super encodeRestorableStateWithCoder:coder];
    
    [coder
		 encodeObject:self.addressTextField.stringValue
		 forKey:ZGMemoryViewerAddressField];
    
    [coder
		 encodeInt64:(int64_t)self.currentMemoryAddress
		 forKey:ZGMemoryViewerAddress];
    
    [coder
		 encodeObject:self.desiredProcessName
		 forKey:ZGMemoryViewerProcessName];
	
	[coder encodeBool:self.showsDataInspector forKey:ZGMemoryViewerShowsDataInspector];
}

- (void)restoreStateWithCoder:(NSCoder *)coder
{
	[super restoreStateWithCoder:coder];
	
	NSString *memoryViewerAddressField = [coder decodeObjectForKey:ZGMemoryViewerAddressField];
	if (memoryViewerAddressField)
	{
		self.addressTextField.stringValue = memoryViewerAddressField;
	}
	
	self.currentMemoryAddress = [coder decodeInt64ForKey:ZGMemoryViewerAddress];
	
	self.desiredProcessName = [coder decodeObjectForKey:ZGMemoryViewerProcessName];
	[self updateRunningProcesses];
	
	if ([coder decodeBoolForKey:ZGMemoryViewerShowsDataInspector])
	{
		[self toggleDataInspector:nil];
	}
	
	[self windowDidShow:nil];
}

- (void)markChanges
{
	if ([self respondsToSelector:@selector(invalidateRestorableState)])
	{
		[self invalidateRestorableState];
	}
}

- (void)windowDidLoad
{
	self.window.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
	
	if ([self.window respondsToSelector:@selector(setRestorable:)] && [self.window respondsToSelector:@selector(setRestorationClass:)])
	{
		self.window.restorable = YES;
		self.window.restorationClass = ZGAppController.class;
		self.window.identifier = ZGMemoryViewerIdentifier;
		[self markChanges];
	}
	
	self.textView.controller.editable = NO;
	
	// So, I've no idea what HFTextView does by default, remove any type of representer that it might have and that we want to add
	NSMutableArray *representersToRemove = [[NSMutableArray alloc] init];
	
	for (HFRepresenter *representer in self.textView.layoutRepresenter.representers)
	{
		if ([representer isKindOfClass:HFStatusBarRepresenter.class] || [representer isKindOfClass:HFLineCountingRepresenter.class] || [representer isKindOfClass:HFVerticalScrollerRepresenter.class] || [representer isKindOfClass:[DataInspectorRepresenter class]])
		{
			[representersToRemove addObject:representer];
		}
	}
	
	for (HFRepresenter *representer in representersToRemove)
	{
		[self.textView.layoutRepresenter removeRepresenter:representer];
	}
	
	// Add custom status bar
	self.statusBarRepresenter = [[ZGStatusBarRepresenter alloc] init];
	self.statusBarRepresenter.statusMode = HFStatusModeHexadecimal;
	
	[self.textView.controller addRepresenter:self.statusBarRepresenter];
	[[self.textView layoutRepresenter] addRepresenter:self.statusBarRepresenter];
	
	// Add custom line counter
	self.lineCountingRepresenter = [[ZGLineCountingRepresenter alloc] init];
	self.lineCountingRepresenter.minimumDigitCount = DEFAULT_MINIMUM_LINE_DIGIT_COUNT;
	self.lineCountingRepresenter.lineNumberFormat = HFLineNumberFormatHexadecimal;
	
	[self.textView.controller addRepresenter:self.lineCountingRepresenter];
	[self.textView.layoutRepresenter addRepresenter:self.lineCountingRepresenter];
	
	// Add custom scroller
	ZGVerticalScrollerRepresenter *verticalScrollerRepresenter = [[ZGVerticalScrollerRepresenter alloc] init];
	
	[self.textView.controller addRepresenter:verticalScrollerRepresenter];
	[self.textView.layoutRepresenter addRepresenter:verticalScrollerRepresenter];
	
	[self initiateDataInspector];
	
	// It's important to set frame autosave name after we initiate the data inspector, otherwise the data inspector's frame will not be correct for some reason
	[[self window] setFrameAutosaveName: @"ZGMemoryViewer"];
	
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

- (void)windowDidShow:(id)sender
{
	if (!self.checkMemoryTimer)
	{
		self.checkMemoryTimer =
		[NSTimer
		 scheduledTimerWithTimeInterval:READ_MEMORY_INTERVAL
		 target:self
		 selector:@selector(readMemory:)
		 userInfo:nil
		 repeats:YES];
	}
	
	if (!self.windowDidAppear)
	{
		[self changeMemoryView:nil];
		[self relayoutAndResizeWindowPreservingBytesPerLine];
		self.windowDidAppear = YES;
	}
	
	if (self.currentProcess)
	{
		if (self.currentProcess.valid)
		{
			[[ZGProcessList sharedProcessList] addPriorityToProcessIdentifier:self.currentProcess.processID];
		}
		else
		{
			[[ZGProcessList sharedProcessList] requestPollingWithObserver:self];
		}
	}
}

- (IBAction)showWindow:(id)sender
{
	[super showWindow:sender];
	
	[self windowDidShow:nil];
}

- (void)windowWillClose:(NSNotification *)notification
{
	[self.checkMemoryTimer invalidate];
	self.checkMemoryTimer = nil;
	
	if (self.currentProcess.valid)
	{
		[[ZGProcessList sharedProcessList] removePriorityToProcessIdentifier:self.currentProcess.processID];
	}
	
	[[ZGProcessList sharedProcessList] unrequestPollingWithObserver:self];
}

#pragma mark Data Inspector

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	if (menuItem.action == @selector(toggleDataInspector:))
	{
		[menuItem setState:self.showsDataInspector];
	}
	else if (menuItem.action == @selector(changeMemoryProtection:))
	{
		if (!self.currentProcess.valid || !self.window.isVisible)
		{
			return NO;
		}
	}
	else if (menuItem.action == @selector(dumpMemoryInRange:) || menuItem.action == @selector(dumpAllMemory:))
	{
		if (!self.currentProcess.valid || self.currentProcess.isDoingMemoryDump)
		{
			return NO;
		}
	}
	else if (menuItem.action == @selector(pauseOrUnpauseProcess:))
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
			menuItem.title = [NSString stringWithFormat:@"%@ Target", suspendCount > 0 ? @"Unpause" : @"Pause"];
		}
		
		if ([[[ZGAppController sharedController] disassemblerController] isProcessIdentifierHalted:self.currentProcess.processID])
		{
			return NO;
		}
	}
	
	return YES;
}

- (void)initiateDataInspector
{
	self.dataInspectorRepresenter = [[DataInspectorRepresenter alloc] init];
	
	// Add representers for data inspector, then remove them here. We do this otherwise if we try to add the representers some later point, they may not autoresize correctly.
	
	[@[self.textView.controller, self.textView.layoutRepresenter] makeObjectsPerformSelector:@selector(addRepresenter:) withObject:self.dataInspectorRepresenter];
	
	[self.dataInspectorRepresenter resizeTableViewAfterChangingRowCount];
	[self relayoutAndResizeWindowPreservingFrame];
	
	[@[self.textView.controller, self.textView.layoutRepresenter] makeObjectsPerformSelector:@selector(removeRepresenter:) withObject:self.dataInspectorRepresenter];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dataInspectorChangedRowCount:) name:DataInspectorDidChangeRowCount object:self.dataInspectorRepresenter];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dataInspectorDeletedAllRows:) name:DataInspectorDidDeleteAllRows object:self.dataInspectorRepresenter];
}

- (IBAction)toggleDataInspector:(id)sender
{
	SEL action = self.showsDataInspector ? @selector(removeRepresenter:) : @selector(addRepresenter:);
	
	[@[self.textView.controller, self.textView.layoutRepresenter] makeObjectsPerformSelector:action withObject:self.dataInspectorRepresenter];
	
	self.showsDataInspector = !self.showsDataInspector;
}

- (NSSize)minimumWindowFrameSizeForProposedSize:(NSSize)frameSize
{
    NSView *layoutView = [self.textView.layoutRepresenter view];
    NSSize proposedSizeInLayoutCoordinates = [layoutView convertSize:frameSize fromView:nil];
    CGFloat resultingWidthInLayoutCoordinates = [self.textView.layoutRepresenter minimumViewWidthForLayoutInProposedWidth:proposedSizeInLayoutCoordinates.width];
    NSSize resultSize = [layoutView convertSize:NSMakeSize(resultingWidthInLayoutCoordinates, proposedSizeInLayoutCoordinates.height) toView:nil];
    return resultSize;
}

- (void)relayoutAndResizeWindowPreservingBytesPerLine
{
	NSUInteger bytesPerLine = ceil(self.textView.controller.bytesPerLine / 4.0) * 4;
    NSWindow *window = [self window];
    NSRect windowFrame = [window frame];
    NSView *layoutView = [self.textView.layoutRepresenter view];
    CGFloat minViewWidth = [self.textView.layoutRepresenter minimumViewWidthForBytesPerLine:bytesPerLine];
    CGFloat minWindowWidth = [layoutView convertSize:NSMakeSize(minViewWidth, 1) toView:nil].width;
    windowFrame.size.width = minWindowWidth;
    [window setFrame:windowFrame display:YES];
}

// Relayout the window without increasing its window frame size
- (void)relayoutAndResizeWindowPreservingFrame
{
	NSWindow *window = [self window];
	NSRect windowFrame = [window frame];
	windowFrame.size = [self minimumWindowFrameSizeForProposedSize:windowFrame.size];
	[window setFrame:windowFrame display:YES];
}

- (void)dataInspectorDeletedAllRows:(NSNotification *)note
{
	DataInspectorRepresenter *inspector = [note object];
	[self.textView.controller removeRepresenter:inspector];
	[[self.textView layoutRepresenter] removeRepresenter:inspector];
	[self relayoutAndResizeWindowPreservingFrame];
	self.showsDataInspector = NO;
}

// Called when our data inspector changes its size (number of rows)
- (void)dataInspectorChangedRowCount:(NSNotification *)note
{
	DataInspectorRepresenter *inspector = [note object];
	CGFloat newHeight = (CGFloat)[[[note userInfo] objectForKey:@"height"] doubleValue];
	NSView *dataInspectorView = [inspector view];
	NSSize size = [dataInspectorView frame].size;
	size.height = newHeight;
	[dataInspectorView setFrameSize:size];
	
	[self.textView.layoutRepresenter performLayout];
}

- (void)windowDidResize:(NSNotification *)notification
{
	[self relayoutAndResizeWindowPreservingBytesPerLine];
}

#pragma mark Updating running applications

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (object == [ZGProcessList sharedProcessList])
	{
		[self updateRunningProcesses];
	}
}

- (void)clearData
{
	self.currentMemoryAddress = 0;
	self.currentMemorySize = 0;
	self.lineCountingRepresenter.beginningMemoryAddress = 0;
	self.statusBarRepresenter.beginningMemoryAddress = 0;
	self.textView.data = [NSData data];
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

- (IBAction)runningApplicationsPopUpButton:(id)sender
{
	if ([self.runningApplicationsPopUpButton.selectedItem.representedObject processID] != self.currentProcess.processID)
	{
		self.desiredProcessName = [self.runningApplicationsPopUpButton.selectedItem.representedObject name];
		[[ZGAppController sharedController] setLastSelectedProcessName:self.desiredProcessName];
		self.currentProcess = self.runningApplicationsPopUpButton.selectedItem.representedObject;
	}
}

#pragma mark Reading from Memory

- (IBAction)changeMemoryView:(id)sender
{
	BOOL success = NO;
	
	if (!self.currentProcess.valid || ![self.currentProcess hasGrantedAccess])
	{
		goto END_MEMORY_VIEW_CHANGE;
	}
	
	// create scope block to allow for goto
	{
		NSString *calculatedMemoryAddressExpression = [ZGCalculator evaluateExpression:self.addressTextField.stringValue];
		
		ZGMemoryAddress calculatedMemoryAddress = 0;
		
		if (isValidNumber(calculatedMemoryAddressExpression))
		{
			calculatedMemoryAddress = memoryAddressFromExpression(calculatedMemoryAddressExpression);
		}
		
		NSArray *memoryRegions = ZGRegionsForProcessTask(self.currentProcess.processTask);
		if (memoryRegions.count == 0)
		{
			goto END_MEMORY_VIEW_CHANGE;
		}
		
		ZGRegion *chosenRegion = nil;
		if (calculatedMemoryAddress != 0)
		{
			for (ZGRegion *region in memoryRegions)
			{
				if ((region.protection & VM_PROT_READ) && calculatedMemoryAddress >= region.address && calculatedMemoryAddress < region.address + region.size)
				{
					chosenRegion = region;
					break;
				}
			}
		}
		
		BOOL shouldMakeSelection = YES;
		
		if (!chosenRegion)
		{
			for (ZGRegion *region in memoryRegions)
			{
				if (region.protection & VM_PROT_READ)
				{
					chosenRegion = region;
					break;
				}
			}
			
			if (!chosenRegion)
			{
				goto END_MEMORY_VIEW_CHANGE;
			}
			
			calculatedMemoryAddress = 0;
			shouldMakeSelection = NO;
		}
		
		self.currentMemoryAddress = chosenRegion.address;
		self.currentMemorySize = chosenRegion.size;
		
#define MEMORY_VIEW_THRESHOLD 26843545
		// Bound the upper and lower half by a threshold so that we will never view too much data that we won't be able to handle, in the rarer cases
		if (calculatedMemoryAddress > 0)
		{
			if (calculatedMemoryAddress >= MEMORY_VIEW_THRESHOLD && calculatedMemoryAddress - MEMORY_VIEW_THRESHOLD > self.currentMemoryAddress)
			{
				ZGMemoryAddress newMemoryAddress = calculatedMemoryAddress - MEMORY_VIEW_THRESHOLD;
				self.currentMemorySize -= newMemoryAddress - self.currentMemoryAddress;
				self.currentMemoryAddress = newMemoryAddress;
			}
			
			if (calculatedMemoryAddress + MEMORY_VIEW_THRESHOLD < self.currentMemoryAddress + self.currentMemorySize)
			{
				self.currentMemorySize -= self.currentMemoryAddress + self.currentMemorySize - (calculatedMemoryAddress + MEMORY_VIEW_THRESHOLD);
			}
		}
		else
		{
			if (self.currentMemorySize > MEMORY_VIEW_THRESHOLD * 2)
			{
				self.currentMemorySize = MEMORY_VIEW_THRESHOLD * 2;
			}
		}
		
		ZGMemoryAddress memoryAddress = self.currentMemoryAddress;
		ZGMemorySize memorySize = self.currentMemorySize;
		
		void *bytes = NULL;
		
		if (ZGReadBytes(self.currentProcess.processTask, memoryAddress, &bytes, &memorySize) && memorySize > 0)
		{
			// Replace all the contents of the self.textView
			self.textView.data = [NSData dataWithBytes:bytes length:(NSUInteger)memorySize];
			self.currentMemoryAddress = memoryAddress;
			self.currentMemorySize = memorySize;
			
			self.statusBarRepresenter.beginningMemoryAddress = self.currentMemoryAddress;
			// Select the first byte of data
			self.statusBarRepresenter.controller.selectedContentsRanges = @[[HFRangeWrapper withRange:HFRangeMake(0, 0)]];
			// To make sure status bar doesn't always show 0x0 as the offset, we need to force it to update
			[self.statusBarRepresenter updateString];
			
			self.lineCountingRepresenter.minimumDigitCount = HFCountDigitsBase10(memoryAddress + memorySize);
			self.lineCountingRepresenter.beginningMemoryAddress = self.currentMemoryAddress;
			// This will force the line numbers to update
			[self.lineCountingRepresenter.view setNeedsDisplay:YES];
			// This will force the line representer's layout to re-draw, which is necessary from calling setMinimumDigitCount:
			[self.textView.layoutRepresenter performLayout];
			
			success = YES;
			
			ZGFreeBytes(self.currentProcess.processTask, bytes, memorySize);
			
			if (!calculatedMemoryAddress)
			{
				self.addressTextField.stringValue = [NSString stringWithFormat:@"0x%llX", memoryAddress];
				calculatedMemoryAddress = memoryAddress;
			}
			
			// Make the hex view the first responder, so that the highlighted bytes will be blue and in the clear
			for (id representer in self.textView.controller.representers)
			{
				if ([representer isKindOfClass:[HFHexTextRepresenter class]])
				{
					[self.window makeFirstResponder:[representer view]];
					break;
				}
			}
			
			[self jumpToMemoryAddress:calculatedMemoryAddress shouldMakeSelection:shouldMakeSelection];
		}
	}
	
END_MEMORY_VIEW_CHANGE:
	
	[self markChanges];
	
	if (!success)
	{
		[self clearData];
	}
}

- (void)readMemory:(NSTimer *)timer
{
	if (self.currentMemorySize > 0)
	{
		HFFPRange displayedLineRange = self.textView.controller.displayedLineRange;
		
		ZGMemoryAddress readAddress = (ZGMemoryAddress)(displayedLineRange.location * self.textView.controller.bytesPerLine) + self.currentMemoryAddress;
		
		if (readAddress >= self.currentMemoryAddress && readAddress < self.currentMemoryAddress + self.currentMemorySize)
		{
			// Try to read two extra lines, to make sure we at least get the upper and lower fractional parts.
			ZGMemorySize readSize = (ZGMemorySize)((displayedLineRange.length + 2) * self.textView.controller.bytesPerLine);
			// If we go over in size, resize it to the end
			if (readAddress + readSize > self.currentMemoryAddress + self.currentMemorySize)
			{
				readSize = (self.currentMemoryAddress + self.currentMemorySize) - readAddress;
			}
			
			void *bytes = NULL;
			if (ZGReadBytes(self.currentProcess.processTask, readAddress, &bytes, &readSize) && readSize > 0)
			{
				HFFullMemoryByteSlice *byteSlice = [[HFFullMemoryByteSlice alloc] initWithData:[NSData dataWithBytes:bytes length:(NSUInteger)readSize]];
				HFByteArray *newByteArray = self.textView.controller.byteArray;
				
				[newByteArray insertByteSlice:byteSlice inRange:HFRangeMake((ZGMemoryAddress)(displayedLineRange.location * self.textView.controller.bytesPerLine), readSize)];
				[self.textView.controller setByteArray:newByteArray];
				
				ZGFreeBytes(self.currentProcess.processTask, bytes, readSize);
			}
		}
	}
}

// memoryAddress is assumed to be within bounds of current memory region being viewed
- (void)jumpToMemoryAddress:(ZGMemoryAddress)memoryAddress shouldMakeSelection:(BOOL)shouldMakeSelection
{
	long double offset = (long double)(memoryAddress - self.currentMemoryAddress);
	
	long double offsetLine = offset / [self.textView.controller bytesPerLine];
	
	HFFPRange displayedLineRange = self.textView.controller.displayedLineRange;
	
	// the line we want to jump to should be in the middle of the view
	[self.textView.controller scrollByLines:offsetLine - displayedLineRange.location - displayedLineRange.length / 2.0];
	
	if (shouldMakeSelection)
	{
		// Select a few bytes from the offset
		self.textView.controller.selectedContentsRanges = @[[HFRangeWrapper withRange:HFRangeMake(offset, MIN(self.selectionLength, self.currentMemoryAddress + self.currentMemorySize - memoryAddress))]];
		
		// Restore default selection length
		self.selectionLength = DEFAULT_SELECTION_LENGTH;
		
		[self.textView.controller pulseSelection];
	}
}

- (void)jumpToMemoryAddress:(ZGMemoryAddress)memoryAddress inProcess:(ZGProcess *)requestedProcess
{
	NSMenuItem *targetMenuItem = nil;
	for (NSMenuItem *menuItem in self.runningApplicationsPopUpButton.menu.itemArray)
	{
		ZGProcess *process = menuItem.representedObject;
		if (process.processID == requestedProcess.processID)
		{
			targetMenuItem = menuItem;
			break;
		}
	}
	
	if (targetMenuItem)
	{
		[self.runningApplicationsPopUpButton selectItem:targetMenuItem];
		[self runningApplicationsPopUpButton:nil];
		[self.addressTextField setStringValue:[NSString stringWithFormat:@"0x%llX", memoryAddress]];
		[self changeMemoryView:nil];
	}
}

#pragma mark Memory Protection

- (IBAction)changeMemoryProtection:(id)sender
{
	[self.memoryProtectionController changeMemoryProtectionRequest];
}

#pragma mark Dumping Memory

- (IBAction)dumpMemoryInRange:(id)sender
{
	[self.memoryDumpController memoryDumpRangeRequest];
}

- (IBAction)dumpAllMemory:(id)sender
{
	[self.memoryDumpController memoryDumpAllRequest];
}

#pragma mark Pausing

- (IBAction)pauseOrUnpauseProcess:(id)sender
{
	[ZGProcess pauseOrUnpauseProcessTask:self.currentProcess.processTask];
}

@end
