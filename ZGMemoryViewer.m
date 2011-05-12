/*
 * This file is part of Bit Slicer.
 *
 * Bit Slicer is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 
 * Bit Slicer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 
 * You should have received a copy of the GNU General Public License
 * along with Bit Slicer.  If not, see <http://www.gnu.org/licenses/>.
 * 
 * Created by Mayur Pawashe on 5/11/11
 * Copyright 2011 zgcoder. All rights reserved.
 */

#import "ZGMemoryViewer.h"
#import "ZGStatusBarRepresenter.h"
#import "ZGLineCountingRepresenter.h"
#import "ZGVerticalScrollerRepresenter.h"
#import "ZGProcess.h"
#import "ZGAppController.h"
#import "ZGDocumentController.h"
#import "ZGUtilities.h"
#import "ZGCalculator.h"
#import "ZGVirtualMemory.h"

#define READ_MEMORY_INTERVAL 0.1
#define DEFAULT_MINIMUM_LINE_DIGIT_COUNT 8

@interface ZGMemoryViewer (Private)

- (void)updateRunningApplicationProcesses:(NSString *)desiredProcessName;

@end

@implementation ZGMemoryViewer

#pragma mark Initialization

- (id)init
{
	self = [super initWithWindowNibName:@"MemoryViewer"];
	
	[self setWindowFrameAutosaveName:@"ZGMemoryViewer"];
	
	return self;
}

- (void)windowDidLoad
{
	// For handling windowWillClose:
	[[self window] setDelegate:self];
	
	[self updateRunningApplicationProcesses:[ZGDocumentController lastSelectedProcessName]];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(anApplicationLaunchedOrTerminated:)
												 name:ZGProcessLaunched
											   object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(anApplicationLaunchedOrTerminated:)
												 name:ZGProcessTerminated
											   object:nil];
	
	statusBarRepresenter = [[ZGStatusBarRepresenter alloc] init];
	[statusBarRepresenter setStatusMode:HFStatusModeHexadecimal];
	
	[[textView controller] addRepresenter:statusBarRepresenter];
	[[textView layoutRepresenter] addRepresenter:statusBarRepresenter];
	
	lineCountingRepresenter = [[ZGLineCountingRepresenter alloc] init];
	[lineCountingRepresenter setMinimumDigitCount:DEFAULT_MINIMUM_LINE_DIGIT_COUNT];
	[lineCountingRepresenter setLineNumberFormat:HFLineNumberFormatHexadecimal];
	
	ZGVerticalScrollerRepresenter *verticalScrollerRepresenter = [[ZGVerticalScrollerRepresenter alloc] init];
	
	[[textView controller] addRepresenter:verticalScrollerRepresenter];
	[[textView layoutRepresenter] addRepresenter:verticalScrollerRepresenter];
	
	[verticalScrollerRepresenter release];
	
	[[textView controller] addRepresenter:lineCountingRepresenter];
	[[textView layoutRepresenter] addRepresenter:lineCountingRepresenter];
}

- (IBAction)showWindow:(id)sender
{
	[super showWindow:sender];
	
	if (!checkMemoryTimer)
	{
		checkMemoryTimer = [[NSTimer scheduledTimerWithTimeInterval:READ_MEMORY_INTERVAL
															 target:self
														   selector:@selector(readMemory:)
														   userInfo:nil
															repeats:YES] retain];
	}
}

- (void)windowWillClose:(NSNotification *)notification
{
	[checkMemoryTimer invalidate];
	[checkMemoryTimer release];
	checkMemoryTimer = nil;
}

#pragma mark Updating running applications

- (void)anApplicationLaunchedOrTerminated:(NSNotification *)notification
{
	[self updateRunningApplicationProcesses:nil];
}

- (void)clearData
{
	currentMemoryAddress = 0;
	currentMemorySize = 0;
	[lineCountingRepresenter setBeginningMemoryAddress:0];
	[statusBarRepresenter setBeginningMemoryAddress:0];
	[textView setData:[NSData data]];
}

- (void)updateRunningApplicationProcesses:(NSString *)desiredProcessName
{
	[runningApplicationsPopUpButton removeAllItems];
	
	NSMenuItem *firstRegularApplicationMenuItem = nil;
	
	BOOL foundTargettedProcess = NO;
	for (NSRunningApplication *runningApplication in [[NSWorkspace sharedWorkspace] runningApplications])
	{
		if ([runningApplication processIdentifier] != [[NSRunningApplication currentApplication] processIdentifier])
		{
			NSMenuItem *menuItem = [[NSMenuItem alloc] init];
			[menuItem setTitle:[NSString stringWithFormat:@"%@ (%d)", [runningApplication localizedName], [runningApplication processIdentifier]]];
			NSImage *iconImage = [runningApplication icon];
			[iconImage setSize:NSMakeSize(16, 16)];
			[menuItem setImage:iconImage];
			ZGProcess *representedProcess = [[ZGProcess alloc] initWithName:[runningApplication localizedName]
																  processID:[runningApplication processIdentifier]
																   set64Bit:([runningApplication executableArchitecture] == NSBundleExecutableArchitectureX86_64)];
			[menuItem setRepresentedObject:representedProcess];
			[representedProcess release];
			
			[[runningApplicationsPopUpButton menu] addItem:menuItem];
			
			if (!firstRegularApplicationMenuItem && [runningApplication activationPolicy] == NSApplicationActivationPolicyRegular)
			{
				firstRegularApplicationMenuItem = [menuItem retain];
			}
			
			if (currentProcessIdentifier == [runningApplication processIdentifier] || [desiredProcessName isEqualToString:[runningApplication localizedName]])
			{
				[runningApplicationsPopUpButton selectItem:[runningApplicationsPopUpButton lastItem]];
				foundTargettedProcess = YES;
			}
			
			[menuItem release];
		}
	}
	
	if (!foundTargettedProcess)
	{
		if (firstRegularApplicationMenuItem)
		{
			[runningApplicationsPopUpButton selectItem:firstRegularApplicationMenuItem];
		}
		else if ([runningApplicationsPopUpButton indexOfSelectedItem] >= 0)
		{
			[runningApplicationsPopUpButton selectItemAtIndex:0];
		}
		
		[self clearData];
	}
	
	if (firstRegularApplicationMenuItem)
	{
		[firstRegularApplicationMenuItem release];
	}
	
	currentProcessIdentifier = [[[runningApplicationsPopUpButton selectedItem] representedObject] processID];
}

- (IBAction)runningApplicationsPopUpButton:(id)sender
{
	if ([[[runningApplicationsPopUpButton selectedItem] representedObject] processID] != currentProcessIdentifier)
	{
		currentProcessIdentifier = [[[runningApplicationsPopUpButton selectedItem] representedObject] processID];
		[self clearData];
	}
}

#pragma mark Reading from Memory

// Triggered when address or size text field's actions are sent
- (IBAction)changeMemoryView:(id)sender
{
	if ([[addressTextField stringValue] isEqualToString:@""] || [[sizeTextField stringValue] isEqualToString:@""])
	{
		// don't even bother yet checking
		return;
	}
	
	NSString *calculatedMemoryAddress = [ZGCalculator evaluateExpression:[addressTextField stringValue]];
	NSString *calculatedMemorySize = [ZGCalculator evaluateExpression:[sizeTextField stringValue]];
	
	BOOL success = NO;
	
	if (isValidNumber(calculatedMemoryAddress) && isValidNumber(calculatedMemorySize))
	{
		ZGMemoryAddress memoryAddress = memoryAddressFromExpression(calculatedMemoryAddress);
		ZGMemorySize memorySize = memoryAddressFromExpression(calculatedMemorySize);
		
		// Make sure this is an actual new change
		if (memoryAddress == currentMemoryAddress && memorySize == currentMemorySize)
		{
			return;
		}
		
		if (memorySize > 0)
		{
			void *bytes = malloc((size_t)memorySize);
			if (bytes)
			{
				if (ZGReadBytesCarefully(currentProcessIdentifier, memoryAddress, bytes, &memorySize) && memorySize > 0)
				{
					// Replace all the contents of the textview
					[textView setData:[NSData dataWithBytes:bytes length:(NSUInteger)memorySize]];
					currentMemoryAddress = memoryAddress;
					currentMemorySize = memorySize;
					
					[statusBarRepresenter setBeginningMemoryAddress:currentMemoryAddress];
					// Select the first byte of data
					[[statusBarRepresenter controller] setSelectedContentsRanges:[NSArray arrayWithObject:[HFRangeWrapper withRange:HFRangeMake(0, 0)]]];
					// To make sure status bar doesn't always show 0x0 as the offset, we need to force it to update
					[statusBarRepresenter updateString];
					
					[lineCountingRepresenter setMinimumDigitCount:HFCountDigitsBase16(memoryAddress + memorySize)];
					[lineCountingRepresenter setBeginningMemoryAddress:currentMemoryAddress];
					// This will force the line numbers to update
					[[lineCountingRepresenter view] setNeedsDisplay:YES];
					// This will force the line representer's layout to re-draw, which is necessary from calling setMinimumDigitCount:
					[[textView layoutRepresenter] performLayout];
					
					success = YES;
				}
				
				free(bytes);
			}
		}
	}
	
	if (!success)
	{
		NSRunAlertPanel(@"An error occurred", @"An unknown error occurred. Perhaps the address & size fields were not entered correctly, or that memory could not be read from the specified range.", nil, nil, nil);
	}
}

- (void)readMemory:(NSTimer *)timer
{
	if (currentMemorySize > 0)
	{
		HFFPRange displayedLineRange = [[textView controller] displayedLineRange];
		
		unsigned long long displayedLocation = (unsigned long long)(displayedLineRange.location * [[textView controller] bytesPerLine]);
		unsigned long long displayedEndLocation = (unsigned long long)([[textView controller] bytesPerLine] * (displayedLineRange.location + displayedLineRange.length));
		
		unsigned long long minimumLocation = [[textView controller] minimumSelectionLocation];
		unsigned long long maximumLocation = [[textView controller] maximumSelectionLocation];
		
		// If the current selection is not visible, then make it visible
		// If we replace the bytes and the current selection is not visible, it will scroll to the current selection
		// So we need to change the current selection accordingly
		if ((minimumLocation < displayedLocation || minimumLocation >= displayedEndLocation) || (maximumLocation < displayedLocation || maximumLocation >= displayedEndLocation))
		{
			[[textView controller] setSelectedContentsRanges:[NSArray arrayWithObject:[HFRangeWrapper withRange:HFRangeMake(ceill(displayedLineRange.location) * [[textView controller] bytesPerLine], 0)]]];
			displayedLineRange = [[textView controller] displayedLineRange];
		}
		
		ZGMemoryAddress readAddress = (ZGMemoryAddress)(displayedLineRange.location * [[textView controller] bytesPerLine]) + currentMemoryAddress;
		
		if (readAddress >= currentMemoryAddress && readAddress < currentMemoryAddress + currentMemorySize)
		{
			// Try to read two extra lines, to make sure we at least get the upper and lower fractional parts.
			ZGMemorySize readSize = (ZGMemorySize)((displayedLineRange.length + 2) * [[textView controller] bytesPerLine]);
			// If we go over in size, resize it to the end
			if (readAddress + readSize > currentMemoryAddress + currentMemorySize)
			{
				readSize = (currentMemoryAddress + currentMemorySize) - readAddress;
			}
			
			void *bytes = malloc((size_t)readSize);
			if (bytes)
			{
				if (ZGReadBytesCarefully(currentProcessIdentifier, readAddress, bytes, &readSize) && readSize > 0)
				{
					HFFullMemoryByteSlice *byteSlice = [[HFFullMemoryByteSlice alloc] initWithData:[NSData dataWithBytes:bytes length:(NSUInteger)readSize]];
					HFByteArray *newByteArray = [[textView controller] byteArray];
					
					[newByteArray insertByteSlice:byteSlice inRange:HFRangeMake((ZGMemoryAddress)(displayedLineRange.location * [[textView controller] bytesPerLine]), readSize)];
					[[textView controller] replaceByteArray:newByteArray];
					
					[byteSlice release];
				}
				free(bytes);
			}
		}
	}
}

@end
