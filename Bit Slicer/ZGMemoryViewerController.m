/*
 * Copyright (c) 2012 Mayur Pawashe
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
#import "ZGTextViewLayoutController.h"
#import "ZGStatusBarRepresenter.h"
#import "ZGLineCountingRepresenter.h"
#import "ZGVerticalScrollerRepresenter.h"
#import "DataInspectorRepresenter.h"
#import "ZGProcess.h"
#import "ZGSearchProgress.h"
#import "ZGMemoryAddressExpressionParsing.h"
#import "ZGCalculator.h"
#import "ZGVirtualMemory.h"
#import "ZGRegion.h"
#import "ZGVariableController.h"
#import "NSArrayAdditions.h"
#import "ZGNullability.h"

#define READ_MEMORY_INTERVAL 0.1
#define DEFAULT_MINIMUM_LINE_DIGIT_COUNT 12

#define ZGMemoryViewerAddressField @"ZGMemoryViewerAddressField"
#define ZGMemoryViewerProcessInternalName @"ZGMemoryViewerProcessName"
#define ZGMemoryViewerShowsDataInspector @"ZGMemoryViewerShowsDataInspector"

#define ZGLocalizedStringFromMemoryViewerTable(string) NSLocalizedStringFromTable((string), @"[Code] Memory Viewer", nil)

@implementation ZGMemoryViewerController
{
	NSMutableArray<ZGBreakPoint *> * _Nonnull _haltedBreakPoints;
	
	ZGTextViewLayoutController * _Nullable _textViewLayoutController;
	
	ZGStatusBarRepresenter * _Nullable _statusBarRepresenter;
	ZGLineCountingRepresenter * _Nullable _lineCountingRepresenter;
	DataInspectorRepresenter * _Nullable _dataInspectorRepresenter;
	
	BOOL _showsDataInspector;
	
	NSData * _Nullable _lastUpdatedData;
	HFRange _lastUpdatedRange;
	NSInteger _lastUpdateCount;
	
	IBOutlet HFTextView *_textView;
}

#pragma mark Accessors

- (NSUndoManager *)undoManager
{
	return ZGUnwrapNullableObject(_textView.controller.undoManager);
}

- (HFRange)selectedAddressRange
{
	HFRange selectedRange = {.location = 0, .length = 0};
	if (_currentMemorySize > 0)
	{
		selectedRange = [(HFRangeWrapper *)_textView.controller.selectedContentsRanges[0] HFRange];
		selectedRange.location += _currentMemoryAddress;
	}
	return selectedRange;
}

- (HFRange)preferredMemoryRequestRange
{
	HFRange selectedRange = [self selectedAddressRange];
	return selectedRange.length > 0 ? selectedRange : HFRangeMake(_currentMemoryAddress, _currentMemorySize);
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

- (id)initWithProcessTaskManager:(ZGProcessTaskManager *)processTaskManager rootlessConfiguration:(nullable ZGRootlessConfiguration *)rootlessConfiguration haltedBreakPoints:(NSMutableArray<ZGBreakPoint *> *)haltedBreakPoints delegate:(id <ZGChosenProcessDelegate, ZGShowMemoryWindow, ZGMemorySelectionDelegate>)delegate
{
	self = [super initWithProcessTaskManager:processTaskManager rootlessConfiguration:rootlessConfiguration delegate:delegate];
	if (self != nil)
	{
		_haltedBreakPoints = haltedBreakPoints;
	}
	return self;
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
	
	NSString *memoryViewerAddressField = [coder decodeObjectOfClass:[NSString class] forKey:ZGMemoryViewerAddressField];
	if (memoryViewerAddressField != nil)
	{
		self.addressTextField.stringValue = memoryViewerAddressField;
	}
	
	self.desiredProcessInternalName = [coder decodeObjectOfClass:[NSString class] forKey:ZGMemoryViewerProcessInternalName];
	
	[self updateRunningProcesses];
	[self setAndPostLastChosenInternalProcessName];
	[self changeMemoryViewWithSelectionLength:0];
}

- (NSString *)windowNibName
{
	return @"Memory Viewer Window";
}

- (void)windowDidLoad
{
	[super windowDidLoad];
	
	_textViewLayoutController = [[ZGTextViewLayoutController alloc] init];

	// So, I've no idea what HFTextView does by default, remove any type of representer that it might have and that we want to add
	NSMutableArray<HFRepresenter *> *representersToRemove = [[NSMutableArray alloc] init];
	
	for (HFRepresenter *representer in _textView.layoutRepresenter.representers)
	{
		if ([representer isKindOfClass:HFStatusBarRepresenter.class] || [representer isKindOfClass:HFLineCountingRepresenter.class] || [representer isKindOfClass:HFVerticalScrollerRepresenter.class] || [representer isKindOfClass:[DataInspectorRepresenter class]])
		{
			[representersToRemove addObject:representer];
		}
	}
	
	for (HFRepresenter *representer in representersToRemove)
	{
		[_textView.layoutRepresenter removeRepresenter:representer];
	}
	
	// Add custom status bar
	_statusBarRepresenter = [[ZGStatusBarRepresenter alloc] init];
	_statusBarRepresenter.statusMode = HFStatusModeHexadecimal;
	
	[_textView.controller addRepresenter:ZGUnwrapNullableObject(_statusBarRepresenter)];
	[[_textView layoutRepresenter] addRepresenter:ZGUnwrapNullableObject(_statusBarRepresenter)];
	
	// Add custom line counter
	_lineCountingRepresenter = [[ZGLineCountingRepresenter alloc] init];
	_lineCountingRepresenter.minimumDigitCount = DEFAULT_MINIMUM_LINE_DIGIT_COUNT;
	_lineCountingRepresenter.lineNumberFormat = HFLineNumberFormatHexadecimal;
	
	[_textView.controller addRepresenter:ZGUnwrapNullableObject(_lineCountingRepresenter)];
	[_textView.layoutRepresenter addRepresenter:ZGUnwrapNullableObject(_lineCountingRepresenter)];
	
	// Add custom scroller
	ZGVerticalScrollerRepresenter *verticalScrollerRepresenter = [[ZGVerticalScrollerRepresenter alloc] init];
	
	[_textView.controller addRepresenter:verticalScrollerRepresenter];
	[_textView.layoutRepresenter addRepresenter:verticalScrollerRepresenter];
	
	_textView.controller.undoManager = [[NSUndoManager alloc] init];
	
	_textView.delegate = self;
	
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

- (BOOL)isProcessIdentifierHalted:(pid_t)processIdentifier
{
	return [super isProcessIdentifier:processIdentifier inHaltedBreakPoints:_haltedBreakPoints];
}

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)userInterfaceItem
{
	NSMenuItem *menuItem = [(NSObject *)userInterfaceItem isKindOfClass:[NSMenuItem class]] ? (NSMenuItem *)userInterfaceItem : nil;
	
	if (userInterfaceItem.action == @selector(toggleDataInspector:))
	{
		[menuItem setState:_showsDataInspector];
	}
	else if (userInterfaceItem.action == @selector(copyAddress:) || userInterfaceItem.action == @selector(showDebugger:))
	{
		if (!self.currentProcess.valid)
		{
			return NO;
		}
		
		if ([self selectedAddressRange].location < _currentMemoryAddress)
		{
			return NO;
		}
	}
	
	return [super validateUserInterfaceItem:userInterfaceItem];
}

#pragma mark Data Inspector

- (void)initiateDataInspector
{
	_dataInspectorRepresenter = [[DataInspectorRepresenter alloc] init];
	
	[_dataInspectorRepresenter resizeTableViewAfterChangingRowCount];
	[_textViewLayoutController relayoutAndResizeWindow:ZGUnwrapNullableObject(self.window) preservingFrameWithTextView:_textView];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dataInspectorChangedRowCount:) name:DataInspectorDidChangeRowCount object:_dataInspectorRepresenter];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dataInspectorDeletedAllRows:) name:DataInspectorDidDeleteAllRows object:_dataInspectorRepresenter];
}

- (IBAction)toggleDataInspector:(id)__unused sender
{
	DataInspectorRepresenter *dataInspectorRepresenter = ZGUnwrapNullableObject(_dataInspectorRepresenter);
	
	if (_showsDataInspector)
	{
		[_textView.layoutRepresenter removeRepresenter:dataInspectorRepresenter];
		[_textView.controller removeRepresenter:dataInspectorRepresenter];
	}
	else
	{
		[_textView.controller addRepresenter:dataInspectorRepresenter];
		[_textView.layoutRepresenter addRepresenter:dataInspectorRepresenter];
	}
	
	_showsDataInspector = !_showsDataInspector;
	
	[[NSUserDefaults standardUserDefaults] setBool:_showsDataInspector forKey:ZGMemoryViewerShowsDataInspector];
}

- (void)dataInspectorDeletedAllRows:(NSNotification *)notification
{
	[_textViewLayoutController dataInspectorDeletedAllRows:ZGUnwrapNullableObject(notification.object) window:ZGUnwrapNullableObject(self.window) textView:_textView];
	
	_showsDataInspector = NO;
	[[NSUserDefaults standardUserDefaults] setBool:_showsDataInspector forKey:ZGMemoryViewerShowsDataInspector];
}

- (void)dataInspectorChangedRowCount:(NSNotification *)note
{
	[_textViewLayoutController dataInspectorChangedRowCount:ZGUnwrapNullableObject(note.object) withHeight:ZGUnwrapNullableObject(note.userInfo[@"height"]) textView:_textView];
}

- (void)windowDidResize:(NSNotification *)__unused notification
{
	[_textViewLayoutController relayoutAndResizeWindow:ZGUnwrapNullableObject(self.window) preservingBytesPerLineWithTextView:_textView];
}

#pragma mark Updating running applications

- (void)clearData
{
	_currentMemoryAddress = 0;
	_currentMemorySize = 0;
	_lineCountingRepresenter.beginningMemoryAddress = 0;
	_statusBarRepresenter.beginningMemoryAddress = 0;
	_textView.data = [NSData data];
}

#pragma mark Reading from Memory

- (void)updateMemoryViewerAtAddress:(ZGMemoryAddress)desiredMemoryAddress withSelectionLength:(ZGMemorySize)selectionLength andChangeFirstResponder:(BOOL)shouldChangeFirstResponder
{
	_lastUpdateCount++;
	
	_lastUpdatedData = nil;
	
	void (^cleanupOnSuccess)(BOOL) = ^(BOOL success) {
		[self invalidateRestorableState];
		
		if (!success)
		{
			[self clearData];
		}
		
		// Revert back to overwrite mode
		self->_textView.controller.editable = YES;
		//[self->_textView.controller setInOverwriteMode:YES];
		self->_textView.controller.editMode = HFOverwriteMode;
		
		[self->_textView.controller.undoManager removeAllActions];
		
		self->_lastUpdateCount--;
	};
	
	// When filling or clearing the memory viewer, make sure we aren't in overwrite mode
	// If we are, filling the memory viewer will take too long, or clearing it will fail
	_textView.controller.editable = NO;
	//[_textView.controller setInOverwriteMode:NO];
	self->_textView.controller.editMode = HFReadOnlyMode;
	
	if (!self.currentProcess.valid || ![self.currentProcess hasGrantedAccess])
	{
		cleanupOnSuccess(NO);
		return;
	}
	
	NSArray<ZGRegion *> *memoryRegions = [ZGRegion regionsFromProcessTask:self.currentProcess.processTask];
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
	
	ZGMemoryAddress oldMemoryAddress = _currentMemoryAddress;
	
	_currentMemoryAddress = chosenRegion.address;
	_currentMemorySize = chosenRegion.size;
	
	const NSUInteger MEMORY_VIEW_THRESHOLD = 26843545;
	// Bound the upper and lower half by a threshold so that we will never view too much data that we won't be able to handle, in the rarer cases
	if (desiredMemoryAddress > 0)
	{
		if (desiredMemoryAddress >= MEMORY_VIEW_THRESHOLD && desiredMemoryAddress - MEMORY_VIEW_THRESHOLD > _currentMemoryAddress)
		{
			ZGMemoryAddress newMemoryAddress = desiredMemoryAddress - MEMORY_VIEW_THRESHOLD;
			_currentMemorySize -= newMemoryAddress - _currentMemoryAddress;
			_currentMemoryAddress = newMemoryAddress;
		}
		
		if (desiredMemoryAddress + MEMORY_VIEW_THRESHOLD < _currentMemoryAddress + _currentMemorySize)
		{
			_currentMemorySize -= _currentMemoryAddress + _currentMemorySize - (desiredMemoryAddress + MEMORY_VIEW_THRESHOLD);
		}
	}
	else
	{
		if (_currentMemorySize > MEMORY_VIEW_THRESHOLD * 2)
		{
			_currentMemorySize = MEMORY_VIEW_THRESHOLD * 2;
		}
	}
	
	ZGMemoryAddress memoryAddress = _currentMemoryAddress;
	ZGMemorySize memorySize = _currentMemorySize;
	
	void *bytes = NULL;
	
	if (ZGReadBytes(self.currentProcess.processTask, memoryAddress, &bytes, &memorySize))
	{
		if (_textView.data && ![_textView.data isEqualToData:[NSData data]])
		{
			HFFPRange displayedLineRange = _textView.controller.displayedLineRange;
			HFRange selectionRange = [(HFRangeWrapper *)_textView.controller.selectedContentsRanges[0] HFRange];
			
			ZGMemoryAddress navigationAddress;
			ZGMemorySize navigationLength;
			
			if (selectionRange.length > 0 && selectionRange.location >= displayedLineRange.location * _textView.controller.bytesPerLine && selectionRange.location + selectionRange.length <= (displayedLineRange.location + displayedLineRange.length) * _textView.controller.bytesPerLine)
			{
				// Selection is completely within the user's sight
				navigationAddress = oldMemoryAddress + selectionRange.location;
				navigationLength = selectionRange.length;
			}
			else
			{
				// Selection not completely within user's sight, use middle of viewer as the point to navigate
				navigationAddress = oldMemoryAddress + (ZGMemorySize)((displayedLineRange.location + displayedLineRange.length / 2) * _textView.controller.bytesPerLine);
				navigationLength = 0;
			}
			
			[(ZGMemoryViewerController *)[self.navigationManager prepareWithInvocationTarget:self] updateMemoryViewerAtAddress:navigationAddress withSelectionLength:navigationLength andChangeFirstResponder:shouldChangeFirstResponder];
		}
		
		// Replace all the contents of the self.textView
		_textView.data = [NSData dataWithBytes:bytes length:(NSUInteger)memorySize];
		_currentMemoryAddress = memoryAddress;
		_currentMemorySize = memorySize;
		
		_statusBarRepresenter.beginningMemoryAddress = _currentMemoryAddress;
		// Select the first byte of data
		_statusBarRepresenter.controller.selectedContentsRanges = @[[HFRangeWrapper withRange:HFRangeMake(0, 0)]];
		// To make sure status bar doesn't always show 0x0 as the offset, we need to force it to update
		[_statusBarRepresenter updateString];
		
		_lineCountingRepresenter.minimumDigitCount = HFCountDigitsBase10(memoryAddress + memorySize);
		_lineCountingRepresenter.beginningMemoryAddress = _currentMemoryAddress;
		// This will force the line numbers to update
		[(NSView *)_lineCountingRepresenter.view setNeedsDisplay:YES];
		// This will force the line representer's layout to re-draw, which is necessary from calling setMinimumDigitCount:
		[_textView.layoutRepresenter performLayout];
		
		ZGFreeBytes(bytes, memorySize);
		
		if (desiredMemoryAddress == 0)
		{
			desiredMemoryAddress = memoryAddress;
			self.addressTextField.stringValue = [NSString stringWithFormat:@"0x%llX", desiredMemoryAddress];
		}
		
		if (shouldChangeFirstResponder)
		{
			// Make the hex view the first responder, so that the highlighted bytes will be blue and in the clear
			for (HFRepresenter *representer in _textView.controller.representers)
			{
				if ([representer isKindOfClass:[HFHexTextRepresenter class]])
				{
					[self.window makeFirstResponder:[representer view]];
					break;
				}
			}
		}
		
		[_textViewLayoutController relayoutAndResizeWindow:ZGUnwrapNullableObject(self.window) preservingBytesPerLineWithTextView:_textView];
		
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
	BOOL foundSymbol = NO;
	NSError *error = nil;
	NSString *calculatedMemoryAddressExpression = [ZGCalculator evaluateAndSymbolicateExpression:self.addressTextField.stringValue process:self.currentProcess currentAddress:[self selectedAddressRange].location didSymbolicate:&foundSymbol error:&error];
	if (error != nil)
	{
		NSLog(@"Error calculating memory address expression in memory viewer: %@", error);
	}

	ZGMemoryAddress calculatedMemoryAddress = 0;
	if (ZGIsValidNumber(calculatedMemoryAddressExpression))
	{
		calculatedMemoryAddress = ZGMemoryAddressFromExpression(calculatedMemoryAddressExpression);
	}
	
	[self updateMemoryViewerAtAddress:calculatedMemoryAddress withSelectionLength:selectionLength andChangeFirstResponder:!foundSymbol];
}

- (void)revertUpdateCount
{
	_lastUpdateCount++;
}

- (void)writeNewData:(NSData *)newData oldData:(NSData *)oldData address:(ZGMemoryAddress)address size:(ZGMemorySize)size
{
	if (ZGWriteBytesIgnoringProtection(self.currentProcess.processTask, address, newData.bytes, size))
	{
		[_textView.controller.undoManager setActionName:ZGLocalizedStringFromMemoryViewerTable(@"undoMemoryWrite")];
		[(ZGMemoryViewerController *)[_textView.controller.undoManager prepareWithInvocationTarget:self] writeNewData:oldData oldData:newData address:address size:size];
	}
}

- (void)hexTextView:(HFTextView *)__unused representer didChangeProperties:(HFControllerPropertyBits)properties
{
	if (properties & HFControllerContentValue && _currentMemorySize > 0 && _lastUpdateCount <= 0 && _lastUpdatedData != nil)
	{
		ZGMemorySize length = _lastUpdatedRange.length;
		const unsigned char *oldBytes = _lastUpdatedData.bytes;
		unsigned char *newBytes = malloc(length);
		[_textView.controller.byteArray copyBytes:newBytes range:_lastUpdatedRange];
		
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
			 address:beginDifferenceIndex + _lastUpdatedRange.location + _currentMemoryAddress
			 size:endDifferenceIndex - beginDifferenceIndex];
		}
		
		free(newBytes);
		
		// Give user a moment to be able to make changes before we can re-enable live-updating
		_lastUpdateCount--;
		[self performSelector:@selector(revertUpdateCount) withObject:nil afterDelay:1.5];
	}
	else if (properties & HFControllerSelectedRanges && _currentMemorySize > 0)
	{
		HFRange selectedAddressRange = [self selectedAddressRange];
		
		id <ZGMemorySelectionDelegate> delegate = self.delegate;
		[delegate memorySelectionDidChange:NSMakeRange(selectedAddressRange.location, selectedAddressRange.length) process:self.currentProcess];
	}
}

- (void)updateDisplayTimer:(NSTimer *)__unused timer
{
	if (_currentMemorySize > 0)
	{
		HFFPRange displayedLineRange = _textView.controller.displayedLineRange;
		
		ZGMemoryAddress readAddress = (ZGMemoryAddress)(displayedLineRange.location * _textView.controller.bytesPerLine) + _currentMemoryAddress;
		
		if (readAddress >= _currentMemoryAddress && readAddress < _currentMemoryAddress + _currentMemorySize)
		{
			// Try to read two extra lines, to make sure we at least get the upper and lower fractional parts.
			ZGMemorySize readSize = (ZGMemorySize)((displayedLineRange.length + 2) * _textView.controller.bytesPerLine);
			// If we go over in size, resize it to the end
			if (readAddress + readSize > _currentMemoryAddress + _currentMemorySize)
			{
				readSize = (_currentMemoryAddress + _currentMemorySize) - readAddress;
			}
			
			void *bytes = NULL;
			if (ZGReadBytes(self.currentProcess.processTask, readAddress, &bytes, &readSize) && readSize > 0)
			{
				NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)readSize];
				HFFullMemoryByteSlice *byteSlice = [[HFFullMemoryByteSlice alloc] initWithData:data];
				HFByteArray *newByteArray = _textView.controller.byteArray;
				
				unsigned long long overwriteLocation = (ZGMemoryAddress)(displayedLineRange.location * _textView.controller.bytesPerLine);
				HFRange replaceRange = HFRangeMake(overwriteLocation, readSize);
				
				[newByteArray insertByteSlice:byteSlice inRange:replaceRange];
				
				_lastUpdatedData = data;
				_lastUpdatedRange = replaceRange;
				
				_lastUpdateCount++;
				// Check if we're allowed to live-update
				if (_lastUpdateCount > 0)
				{
					[_textView.controller setByteArray:newByteArray];
				}
				_lastUpdateCount--;
				
				ZGFreeBytes(bytes, readSize);
			}
		}
	}
}

// memoryAddress is assumed to be within bounds of current memory region being viewed
- (void)jumpToMemoryAddress:(ZGMemoryAddress)memoryAddress withSelectionLength:(ZGMemorySize)selectionLength
{
	unsigned long long offset = (memoryAddress - _currentMemoryAddress);
	
	unsigned long long offsetLine = offset / [_textView.controller bytesPerLine];
	
	HFFPRange displayedLineRange = _textView.controller.displayedLineRange;
	
	// the line we want to jump to should be in the middle of the view
	[_textView.controller scrollByLines:offsetLine - displayedLineRange.location - displayedLineRange.length / 2.0L];
	
	if (selectionLength > 0)
	{
		// Select a few bytes from the offset
		_textView.controller.selectedContentsRanges = @[[HFRangeWrapper withRange:HFRangeMake(offset, MIN(selectionLength, _currentMemoryAddress + _currentMemorySize - memoryAddress))]];
		
		[_textView.controller pulseSelection];
	}
}

- (void)jumpToMemoryAddress:(ZGMemoryAddress)memoryAddress withSelectionLength:(ZGMemorySize)selectionLength inProcess:(ZGProcess *)requestedProcess
{
	NSMenuItem *targetMenuItem = nil;
	for (NSMenuItem *menuItem in self.runningApplicationsPopUpButton.menu.itemArray)
	{
		ZGProcess *process = menuItem.representedObject;
		if ([process isEqual:requestedProcess])
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
		[self updateMemoryViewerAtAddress:memoryAddress withSelectionLength:selectionLength andChangeFirstResponder:YES];
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

#pragma mark Showing Debugger

- (IBAction)showDebugger:(id)__unused sender
{
	HFRange selectedAddressRange = [self selectedAddressRange];
	id <ZGShowMemoryWindow> delegate = self.delegate;
	[delegate showDebuggerWindowWithProcess:self.currentProcess address:selectedAddressRange.location];
}

@end
