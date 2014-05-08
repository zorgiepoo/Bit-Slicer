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

#import "ZGMemoryViewerController.h"
#import "ZGStatusBarRepresenter.h"
#import "ZGLineCountingRepresenter.h"
#import "ZGVerticalScrollerRepresenter.h"
#import "DataInspectorRepresenter.h"
#import "ZGProcess.h"
#import "ZGSearchProgress.h"
#import "ZGUtilities.h"
#import "ZGCalculator.h"
#import "ZGVirtualMemory.h"
#import "ZGVirtualMemoryHelpers.h"
#import "ZGRegion.h"
#import "ZGNavigationPost.h"
#import "ZGVariableController.h"
#import "NSArrayAdditions.h"

#define READ_MEMORY_INTERVAL 0.1
#define DEFAULT_MINIMUM_LINE_DIGIT_COUNT 12

#define ZGMemoryViewerAddressField @"ZGMemoryViewerAddressField"
#define ZGMemoryViewerAddress @"ZGMemoryViewerAddress"
#define ZGMemoryViewerProcessInternalName @"ZGMemoryViewerProcessName"
#define ZGMemoryViewerShowsDataInspector @"ZGMemoryViewerShowsDataInspector"

@interface ZGMemoryViewerController ()

@property (nonatomic) ZGStatusBarRepresenter *statusBarRepresenter;
@property (nonatomic) ZGLineCountingRepresenter *lineCountingRepresenter;
@property (nonatomic) DataInspectorRepresenter *dataInspectorRepresenter;
@property (atomic) BOOL showsDataInspector;

@property (strong, nonatomic) NSData *lastUpdatedData;
@property (nonatomic) HFRange lastUpdatedRange;
@property (nonatomic) int lastUpdateCount;

@property (nonatomic, assign) IBOutlet HFTextView *textView;

@end

@implementation ZGMemoryViewerController

#pragma mark Accessors

- (NSUndoManager *)undoManager
{
	return self.textView.controller.undoManager;
}

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

- (HFRange)preferredMemoryRequestRange
{
	HFRange selectedRange = [self selectedAddressRange];
	return selectedRange.length > 0 ? selectedRange : HFRangeMake(self.currentMemoryAddress, self.currentMemorySize);
}

#pragma mark Current Process Changed

- (void)currentProcessChangedWithOldProcess:(ZGProcess *)oldProcess newProcess:(ZGProcess *)__unused newProcess
{
	if (oldProcess != nil)
	{
		[self changeMemoryViewWithSelectionLength:0];
	}
}

#pragma mark Initialization

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		[[NSUserDefaults standardUserDefaults] registerDefaults:@{ZGMemoryViewerShowsDataInspector : @NO}];
	});
}

- (void)encodeRestorableStateWithCoder:(NSCoder *)coder
{
	[super encodeRestorableStateWithCoder:coder];

    [coder encodeObject:self.addressTextField.stringValue forKey:ZGMemoryViewerAddressField];
    [coder encodeObject:self.desiredProcessInternalName forKey:ZGMemoryViewerProcessInternalName];
}

- (void)restoreStateWithCoder:(NSCoder *)coder
{
	[super restoreStateWithCoder:coder];
	
	NSString *memoryViewerAddressField = [coder decodeObjectForKey:ZGMemoryViewerAddressField];
	if (memoryViewerAddressField != nil)
	{
		self.addressTextField.stringValue = memoryViewerAddressField;
	}
	
	self.desiredProcessInternalName = [coder decodeObjectForKey:ZGMemoryViewerProcessInternalName];
	
	[self updateRunningProcesses];
	[self setAndPostLastChosenInternalProcessName];
	[self changeMemoryViewWithSelectionLength:0];
}

- (void)windowDidLoad
{
	[super windowDidLoad];

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
	
	self.textView.controller.undoManager = [[NSUndoManager alloc] init];
	
	self.textView.delegate = self;
	
	[[self window] setFrameAutosaveName:NSStringFromClass([self class])];
	
	[self initiateDataInspector];
	
	if ([[NSUserDefaults standardUserDefaults] boolForKey:ZGMemoryViewerShowsDataInspector])
	{
		[self toggleDataInspector:nil];
	}

	[self setupProcessListNotifications];

	self.desiredProcessInternalName = self.lastChosenInternalProcessName;
	[self updateRunningProcesses];
}

- (void)updateWindowAndReadMemory:(BOOL)shouldReadMemory
{
	[super updateWindow];
	
	if (shouldReadMemory)
	{
		[self changeMemoryViewWithSelectionLength:0];
	}
}

- (double)displayMemoryTimeInterval
{
	return READ_MEMORY_INTERVAL;
}

#pragma mark Menu Item Validation

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)userInterfaceItem
{
	NSMenuItem *menuItem = [(NSObject *)userInterfaceItem isKindOfClass:[NSMenuItem class]] ? (NSMenuItem *)userInterfaceItem : nil;
	
	if (userInterfaceItem.action == @selector(toggleDataInspector:))
	{
		[menuItem setState:self.showsDataInspector];
	}
	else if (userInterfaceItem.action == @selector(copyAddress:))
	{
		if (!self.currentProcess.valid)
		{
			return NO;
		}
		
		if ([self selectedAddressRange].location < self.currentMemoryAddress)
		{
			return NO;
		}
	}
	
	return [super validateUserInterfaceItem:userInterfaceItem];
}

#pragma mark Data Inspector

- (void)initiateDataInspector
{
	self.dataInspectorRepresenter = [[DataInspectorRepresenter alloc] init];
	
	[self.dataInspectorRepresenter resizeTableViewAfterChangingRowCount];
	[self relayoutAndResizeWindowPreservingFrame];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dataInspectorChangedRowCount:) name:DataInspectorDidChangeRowCount object:self.dataInspectorRepresenter];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dataInspectorDeletedAllRows:) name:DataInspectorDidDeleteAllRows object:self.dataInspectorRepresenter];
}

- (IBAction)toggleDataInspector:(id)__unused sender
{
	SEL action = self.showsDataInspector ? @selector(removeRepresenter:) : @selector(addRepresenter:);
	
	[@[self.textView.controller, self.textView.layoutRepresenter] makeObjectsPerformSelector:action withObject:self.dataInspectorRepresenter];
	
	self.showsDataInspector = !self.showsDataInspector;
	
	[[NSUserDefaults standardUserDefaults] setBool:self.showsDataInspector forKey:ZGMemoryViewerShowsDataInspector];
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
	const NSUInteger bytesMultiple = 4;
	NSUInteger remainder = self.textView.controller.bytesPerLine % bytesMultiple;
	NSUInteger bytesPerLineRoundedUp = (remainder == 0) ? (self.textView.controller.bytesPerLine) : (self.textView.controller.bytesPerLine + bytesMultiple - remainder);
	NSUInteger bytesPerLineRoundedDown = bytesPerLineRoundedUp - bytesMultiple;
	
	// Pick bytes per line that is closest to what we already have and is multiple of bytesMultiple
	NSUInteger bytesPerLine = (bytesPerLineRoundedUp - self.textView.controller.bytesPerLine) > (self.textView.controller.bytesPerLine - bytesPerLineRoundedDown) ? bytesPerLineRoundedDown : bytesPerLineRoundedUp;
	
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
	
	[[NSUserDefaults standardUserDefaults] setBool:self.showsDataInspector forKey:ZGMemoryViewerShowsDataInspector];
}

// Called when our data inspector changes its size (number of rows)
- (void)dataInspectorChangedRowCount:(NSNotification *)note
{
	DataInspectorRepresenter *inspector = [note object];
	CGFloat newHeight = (CGFloat)[[[note userInfo] objectForKey:@"height"] doubleValue];
	NSView *dataInspectorView = [inspector view];
	NSSize size = [dataInspectorView frame].size;
	size.height = newHeight;
	size.width = 1; // this is a hack that makes the data inspector's width actually resize..
	[dataInspectorView setFrameSize:size];
	
	[self.textView.layoutRepresenter performLayout];
}

- (void)windowDidResize:(NSNotification *)__unused notification
{
	[self relayoutAndResizeWindowPreservingBytesPerLine];
}

#pragma mark Updating running applications

- (void)clearData
{
	self.currentMemoryAddress = 0;
	self.currentMemorySize = 0;
	self.lineCountingRepresenter.beginningMemoryAddress = 0;
	self.statusBarRepresenter.beginningMemoryAddress = 0;
	self.textView.data = [NSData data];
}

#pragma mark Reading from Memory

- (void)updateMemoryViewerAtAddress:(ZGMemoryAddress)desiredMemoryAddress withSelectionLength:(ZGMemorySize)selectionLength
{
	self.lastUpdateCount++;
	
	self.lastUpdatedData = nil;
	
	void (^cleanupOnSuccess)(BOOL) = ^(BOOL success) {
		[self invalidateRestorableState];
		
		if (!success)
		{
			[self clearData];
		}
		
		// Revert back to overwrite mode
		self.textView.controller.editable = YES;
		[self.textView.controller setInOverwriteMode:YES];
		
		[self.textView.controller.undoManager removeAllActions];
		
		self.lastUpdateCount--;
	};
	
	// When filling or clearing the memory viewer, make sure we aren't in overwrite mode
	// If we are, filling the memory viewer will take too long, or clearing it will fail
	self.textView.controller.editable = NO;
	[self.textView.controller setInOverwriteMode:NO];
	
	if (!self.currentProcess.valid || ![self.currentProcess hasGrantedAccess])
	{
		cleanupOnSuccess(NO);
		return;
	}
	
	NSArray *memoryRegions = [ZGRegion regionsFromProcessTask:self.currentProcess.processTask];
	if (memoryRegions.count == 0)
	{
		cleanupOnSuccess(NO);
		return;
	}
	
	ZGRegion *chosenRegion = nil;
	if (desiredMemoryAddress != 0)
	{
		chosenRegion = [memoryRegions zgFirstObjectThatMatchesCondition:^(ZGRegion *region) {
			return (BOOL)((region.protection & VM_PROT_READ) != 0 && (desiredMemoryAddress >= region.address && desiredMemoryAddress < region.address + region.size));
		}];
		
		if (chosenRegion != nil)
		{
			chosenRegion = [[ZGRegion submapRegionsFromProcessTask:self.currentProcess.processTask region:chosenRegion] zgFirstObjectThatMatchesCondition:^(ZGRegion *region) {
				return (BOOL)((region.protection & VM_PROT_READ) != 0 && (desiredMemoryAddress >= region.address && desiredMemoryAddress < region.address + region.size));
			}];
		}
	}
	
	if (chosenRegion == nil)
	{
		for (ZGRegion *region in memoryRegions)
		{
			if (region.protection & VM_PROT_READ)
			{
				chosenRegion = region;
				break;
			}
		}
		
		if (chosenRegion == nil)
		{
			cleanupOnSuccess(NO);
			return;
		}
		
		desiredMemoryAddress = 0;
		selectionLength = 0;
	}
	
	ZGMemoryAddress oldMemoryAddress = self.currentMemoryAddress;
	
	self.currentMemoryAddress = chosenRegion.address;
	self.currentMemorySize = chosenRegion.size;
	
	const NSUInteger MEMORY_VIEW_THRESHOLD = 26843545;
	// Bound the upper and lower half by a threshold so that we will never view too much data that we won't be able to handle, in the rarer cases
	if (desiredMemoryAddress > 0)
	{
		if (desiredMemoryAddress >= MEMORY_VIEW_THRESHOLD && desiredMemoryAddress - MEMORY_VIEW_THRESHOLD > self.currentMemoryAddress)
		{
			ZGMemoryAddress newMemoryAddress = desiredMemoryAddress - MEMORY_VIEW_THRESHOLD;
			self.currentMemorySize -= newMemoryAddress - self.currentMemoryAddress;
			self.currentMemoryAddress = newMemoryAddress;
		}
		
		if (desiredMemoryAddress + MEMORY_VIEW_THRESHOLD < self.currentMemoryAddress + self.currentMemorySize)
		{
			self.currentMemorySize -= self.currentMemoryAddress + self.currentMemorySize - (desiredMemoryAddress + MEMORY_VIEW_THRESHOLD);
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
	
	if (ZGReadBytes(self.currentProcess.processTask, memoryAddress, &bytes, &memorySize))
	{
		if (self.textView.data && ![self.textView.data isEqualToData:[NSData data]])
		{
			HFFPRange displayedLineRange = self.textView.controller.displayedLineRange;
			HFRange selectionRange = [[self.textView.controller.selectedContentsRanges objectAtIndex:0] HFRange];
			
			ZGMemoryAddress navigationAddress;
			ZGMemorySize navigationLength;
			
			if (selectionRange.length > 0 && selectionRange.location >= displayedLineRange.location * self.textView.controller.bytesPerLine && selectionRange.location + selectionRange.length <= (displayedLineRange.location + displayedLineRange.length) * self.textView.controller.bytesPerLine)
			{
				// Selection is completely within the user's sight
				navigationAddress = oldMemoryAddress + selectionRange.location;
				navigationLength = selectionRange.length;
			}
			else
			{
				// Selection not completely within user's sight, use middle of viewer as the point to navigate
				navigationAddress = oldMemoryAddress + (ZGMemorySize)((displayedLineRange.location + displayedLineRange.length / 2) * self.textView.controller.bytesPerLine);
				navigationLength = 0;
			}
			
			[[self.navigationManager prepareWithInvocationTarget:self] updateMemoryViewerAtAddress:navigationAddress withSelectionLength:navigationLength];
		}
		
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
		
		ZGFreeBytes(bytes, memorySize);
		
		if (desiredMemoryAddress == 0)
		{
			desiredMemoryAddress = memoryAddress;
			self.addressTextField.stringValue = [NSString stringWithFormat:@"0x%llX", desiredMemoryAddress];
		}
		
		// Make the hex view the first responder, so that the highlighted bytes will be blue and in the clear
		for (HFRepresenter *representer in self.textView.controller.representers)
		{
			if ([representer isKindOfClass:[HFHexTextRepresenter class]])
			{
				[self.window makeFirstResponder:[representer view]];
				break;
			}
		}
		
		[self relayoutAndResizeWindowPreservingBytesPerLine];
		
		[self jumpToMemoryAddress:desiredMemoryAddress withSelectionLength:selectionLength];
		
		[self updateNavigationButtons];
	}
	
	cleanupOnSuccess(YES);
}

- (IBAction)changeMemoryView:(id)__unused sender
{
	[self changeMemoryViewWithSelectionLength:DEFAULT_MEMORY_VIEWER_SELECTION_LENGTH];
}

- (void)changeMemoryViewWithSelectionLength:(ZGMemorySize)selectionLength
{
	NSError *error = nil;
	NSString *calculatedMemoryAddressExpression = [ZGCalculator evaluateAndSymbolicateExpression:self.addressTextField.stringValue process:self.currentProcess currentAddress:[self selectedAddressRange].location error:&error];
	if (error != nil)
	{
		NSLog(@"Error calculating memory address expression in memory viewer: %@", error);
	}

	ZGMemoryAddress calculatedMemoryAddress = 0;
	if (ZGIsValidNumber(calculatedMemoryAddressExpression))
	{
		calculatedMemoryAddress = ZGMemoryAddressFromExpression(calculatedMemoryAddressExpression);
	}
	
	[self updateMemoryViewerAtAddress:calculatedMemoryAddress withSelectionLength:selectionLength];
}

- (void)revertUpdateCount
{
	self.lastUpdateCount++;
}

- (void)writeNewData:(NSData *)newData oldData:(NSData *)oldData address:(ZGMemoryAddress)address size:(ZGMemorySize)size
{
	if (ZGWriteBytesIgnoringProtection(self.currentProcess.processTask, address, newData.bytes, size))
	{
		[self.textView.controller.undoManager setActionName:@"Write Change"];
		[[self.textView.controller.undoManager prepareWithInvocationTarget:self] writeNewData:oldData oldData:newData address:address size:size];
	}
}

- (void)hexTextView:(HFTextView *)__unused representer didChangeProperties:(HFControllerPropertyBits)properties
{
	if (properties & HFControllerContentValue && self.currentMemorySize > 0 && self.lastUpdateCount <= 0 && self.lastUpdatedData != nil)
	{
		ZGMemorySize length = self.lastUpdatedRange.length;
		const unsigned char *oldBytes = self.lastUpdatedData.bytes;
		unsigned char *newBytes = malloc(length);
		[self.textView.controller.byteArray copyBytes:newBytes range:self.lastUpdatedRange];
		
		BOOL foundDifference = NO;
		ZGMemorySize beginDifferenceIndex = 0;
		ZGMemorySize endDifferenceIndex = 0;
		
		// Find the smallest difference to overwrite
		for (ZGMemorySize byteIndex = 0; byteIndex < length; byteIndex++)
		{
			if (oldBytes[byteIndex] != newBytes[byteIndex])
			{
				if (!foundDifference)
				{
					beginDifferenceIndex = byteIndex;
				}
				endDifferenceIndex = byteIndex + 1;
				
				foundDifference = YES;
			}
		}
		
		if (foundDifference)
		{
			[self
			 writeNewData:[NSData dataWithBytes:&newBytes[beginDifferenceIndex] length:endDifferenceIndex - beginDifferenceIndex]
			 oldData:[NSData dataWithBytes:&oldBytes[beginDifferenceIndex] length:endDifferenceIndex - beginDifferenceIndex]
			 address:beginDifferenceIndex + self.lastUpdatedRange.location + self.currentMemoryAddress
			 size:endDifferenceIndex - beginDifferenceIndex];
		}
		
		free(newBytes);
		
		// Give user a moment to be able to make changes before we can re-enable live-updating
		self.lastUpdateCount--;
		[self performSelector:@selector(revertUpdateCount) withObject:nil afterDelay:1.5];
	}
	else if (properties & HFControllerSelectedRanges && self.currentMemorySize > 0)
	{
		HFRange selectedAddressRange = [self selectedAddressRange];
		[ZGNavigationPost postMemorySelectionChangeWithProcess:self.currentProcess selectionRange:NSMakeRange(selectedAddressRange.location, selectedAddressRange.length)];
	}
}

- (void)updateDisplayTimer:(NSTimer *)__unused timer
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
				NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)readSize];
				HFFullMemoryByteSlice *byteSlice = [[HFFullMemoryByteSlice alloc] initWithData:data];
				HFByteArray *newByteArray = self.textView.controller.byteArray;
				
				unsigned long long overwriteLocation = (ZGMemoryAddress)(displayedLineRange.location * self.textView.controller.bytesPerLine);
				HFRange replaceRange = HFRangeMake(overwriteLocation, readSize);
				
				[newByteArray insertByteSlice:byteSlice inRange:replaceRange];
				
				self.lastUpdatedData = data;
				self.lastUpdatedRange = replaceRange;
				
				self.lastUpdateCount++;
				// Check if we're allowed to live-update
				if (self.lastUpdateCount > 0)
				{
					[self.textView.controller setByteArray:newByteArray];
				}
				self.lastUpdateCount--;
				
				ZGFreeBytes(bytes, readSize);
			}
		}
	}
}

// memoryAddress is assumed to be within bounds of current memory region being viewed
- (void)jumpToMemoryAddress:(ZGMemoryAddress)memoryAddress withSelectionLength:(ZGMemorySize)selectionLength
{
	unsigned long long offset = (memoryAddress - self.currentMemoryAddress);
	
	unsigned long long offsetLine = offset / [self.textView.controller bytesPerLine];
	
	HFFPRange displayedLineRange = self.textView.controller.displayedLineRange;
	
	// the line we want to jump to should be in the middle of the view
	[self.textView.controller scrollByLines:offsetLine - displayedLineRange.location - displayedLineRange.length / 2.0];
	
	if (selectionLength > 0)
	{
		// Select a few bytes from the offset
		self.textView.controller.selectedContentsRanges = @[[HFRangeWrapper withRange:HFRangeMake(offset, MIN(selectionLength, self.currentMemoryAddress + self.currentMemorySize - memoryAddress))]];
		
		[self.textView.controller pulseSelection];
	}
}

- (void)jumpToMemoryAddress:(ZGMemoryAddress)memoryAddress withSelectionLength:(ZGMemorySize)selectionLength inProcess:(ZGProcess *)requestedProcess
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
	
	if (targetMenuItem != nil)
	{
		[self.runningApplicationsPopUpButton selectItem:targetMenuItem];
		[self runningApplicationsPopUpButton:nil];
		[self.addressTextField setStringValue:[NSString stringWithFormat:@"0x%llX", memoryAddress]];
		[self updateMemoryViewerAtAddress:memoryAddress withSelectionLength:selectionLength];
	}
}

#pragma mark Copying

- (IBAction)copyAddress:(id)__unused sender
{
	HFRange selectedAddressRange = [self selectedAddressRange];
	ZGVariable *variable = [[ZGVariable alloc] initWithValue:NULL size:selectedAddressRange.length address:selectedAddressRange.location type:ZGByteArray qualifier:ZGUnsigned pointerSize:self.currentProcess.pointerSize];

	[ZGVariableController annotateVariables:@[variable] process:self.currentProcess];
	
	[[NSPasteboard generalPasteboard] declareTypes:@[NSStringPboardType] owner:self];
	[[NSPasteboard generalPasteboard] setString:variable.addressFormula forType:NSStringPboardType];
}

@end
