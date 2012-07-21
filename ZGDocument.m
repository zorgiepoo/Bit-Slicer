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
 * Created by Mayur Pawashe on 10/25/09.
 * Copyright 2010 zgcoder. All rights reserved.
 */

#import "ZGDocument.h"
#import "ZGVariableController.h"
#import "ZGDocumentTableController.h"
#import "ZGMemoryDumpController.h"
#import "ZGMemoryProtectionController.h"
#import "ZGProcess.h"
#import "ZGVirtualMemory.h"
#import "ZGVariable.h"
#import "ZGAppController.h"
#import "ZGDocumentController.h"
#import "ZGMemoryViewer.h"
#import "ZGComparisonFunctions.h"
#import "NSStringAdditions.h"
#import "ZGCalculator.h"
#import "ZGTimer.h"
#import "ZGUtilities.h"

@interface ZGDocument (Private)

- (void)updateRunningApplicationProcesses;

- (void)setWatchVariablesArrayAndUpdateInterface:(NSArray *)newWatchVariablesArray;

- (void)updateFlags;

- (BOOL)isInNarrowSearchMode;

- (BOOL)doesFunctionTypeAllowSearchInput;
- (BOOL)isFunctionTypeStore;
- (BOOL)isFunctionTypeStore:(NSInteger)functionTypeTag;

- (void)selectDataTypeWithTag:(ZGVariableType)newTag recordUndo:(BOOL)recordUndo;

- (void)functionTypePopUpButtonRequest:(id)sender markChanges:(BOOL)shouldMarkChanges;

@end

#define VALUE_TABLE_COLUMN_INDEX 1

#define DEFAULT_FLOATING_POINT_EPSILON 0.1

#define ZGWatchVariablesArrayKey @"ZGWatchVariablesArrayKey"
#define ZGProcessNameKey @"ZGProcessNameKey"

#define ZGSelectedDataTypeTag @"ZGSelectedDataTypeTag"
#define ZGQualifierTagKey @"ZGQualifierKey"
#define ZGFunctionTypeTagKey @"ZGFunctionTypeTagKey"
#define ZGScanUnwritableValuesKey @"ZGScanUnwritableValuesKey"
#define ZGIgnoreDataAlignmentKey @"ZGIgnoreDataAlignmentKey"
#define ZGExactStringLengthKey @"ZGExactStringLengthKey"
#define ZGIgnoreStringCaseKey @"ZGIgnoreStringCaseKey"
#define ZGBeginningAddressKey @"ZGBeginningAddressKey"
#define ZGEndingAddressKey @"ZGEndingAddressKey"
#define ZGEpsilonKey @"ZGEpsilonKey"
#define ZGAboveValueKey @"ZGAboveValueKey"
#define ZGBelowValueKey @"ZGBelowValueKey"
#define ZGSearchStringValueKey @"ZGSearchStringValueKey"

#define WATCH_VARIABLES_UPDATE_TIME_INTERVAL 0.1
#define CHECK_PROCESSES_TIME_INTERVAL 0.5

#define ZG_EXPAND_OPTIONS @"ZG_EXPAND_OPTIONS"

@implementation ZGDocument

#pragma mark Accessors

@synthesize watchWindow;
@synthesize searchingProgressIndicator;
@synthesize generalStatusTextField;
@synthesize currentProcess;
@synthesize clearButton;
@synthesize watchVariablesArray;
@synthesize variableQualifierMatrix;
@synthesize tableController;
@synthesize variableController;

- (NSArray *)selectedVariables
{
	return ([[tableController watchVariablesTableView] selectedRow] == -1) ? nil : [watchVariablesArray objectsAtIndexes:[[tableController watchVariablesTableView] selectedRowIndexes]];
}

- (BOOL)canStartTask
{
	return [[searchButton title] isEqualToString:@"Search"];
}

- (BOOL)canCancelTask
{
	return [[searchButton title] isEqualToString:@"Cancel"];
}

#pragma mark Document stuff

+ (void)initialize
{
	[[NSUserDefaults standardUserDefaults]
	 registerDefaults:
		[NSDictionary
		 dictionaryWithObject:[NSNumber numberWithBool:NO]
		 forKey:ZG_EXPAND_OPTIONS]];
}

- (id)init
{
	self = [super init];
	if (self)
	{
		UCCreateCollator(NULL, 0, kUCCollateCaseInsensitiveMask, &collator);
		
		searchData = [[ZGSearchData alloc] init];
		searchData->savedData = nil;
		searchData->tempSavedData = nil;
		
		searchArguments.lastEpsilonValue = nil;
		searchArguments.lastAboveRangeValue = nil;
		searchArguments.lastBelowRangeValue = nil;
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	[watchVariablesTimer invalidate];
	[watchVariablesTimer release];
	watchVariablesTimer = nil;
	
	[updateSearchUserInterfaceTimer invalidate];
	[updateSearchUserInterfaceTimer release];
	updateSearchUserInterfaceTimer = nil;
	
	UCDisposeCollator(&collator);
	
	if (searchArguments.rangeValue)
	{
		free(searchArguments.rangeValue);
		searchArguments.rangeValue = NULL;
	}
	
	[searchArguments.lastEpsilonValue release];
	[searchArguments.lastAboveRangeValue release];
	[searchArguments.lastBelowRangeValue release];
	
	if (searchData && searchData->savedData)
	{
		ZGFreeData(searchData->savedData);
		[searchData->savedData release];
		searchData->savedData = nil;
	}
	
	[searchData release];
	searchData = nil;
	
	[watchVariablesArray release];
	watchVariablesArray = nil;
	
	[currentProcess release];
	currentProcess = nil;
	
	[desiredProcessName release];
	desiredProcessName = nil;
	
	[super dealloc];
}

- (NSString *)windowNibName
{
	return @"MyDocument";
}

+ (BOOL)autosavesInPlace
{
    return YES;
}

- (void)loadDocumentUserInterface
{
	if (!desiredProcessName)
	{
		desiredProcessName = [[[[ZGAppController sharedController] documentController] lastSelectedProcessName] copy];
	}
    
	// check if the document is being reverted
	if (watchWindow)
	{
		[generalStatusTextField setStringValue:@""];
	}
	
	[self updateRunningApplicationProcesses];
	
	currentSearchDataType = (ZGVariableType)[[dataTypesPopUpButton selectedItem] tag];

	if (documentState.loadedFromSave)
	{
		[self setWatchVariablesArrayAndUpdateInterface:documentState.watchVariablesArray];
		[documentState.watchVariablesArray release];
        
		[self
		 selectDataTypeWithTag:(ZGVariableType)documentState.selectedDatatypeTag
		 recordUndo:NO];
        
		[variableQualifierMatrix selectCellWithTag:documentState.qualifierTag];

		[scanUnwritableValuesCheckBox setState:documentState.scanUnwritableValues];
		[ignoreDataAlignmentCheckBox setState:documentState.ignoreDataAlignment];
		[includeNullTerminatorCheckBox setState:documentState.exactStringLength];
		[ignoreCaseCheckBox setState:documentState.ignoreStringCase];

		if (documentState.beginningAddress)
		{
			[beginningAddressTextField setStringValue:documentState.beginningAddress];
			[documentState.beginningAddress release];
		}
		
		if (documentState.endingAddress)
		{
			[endingAddressTextField setStringValue:documentState.endingAddress];
			[documentState.endingAddress release];
		}

		if (![self isFunctionTypeStore:documentState.functionTypeTag])
		{
			[functionPopUpButton selectItemWithTag:documentState.functionTypeTag];
			[self
			 functionTypePopUpButtonRequest:nil
			 markChanges:NO];
		}
        
		if (documentState.searchValue)
		{
			[searchValueTextField setStringValue:documentState.searchValue];
			[documentState.searchValue release];
		}
	}
	else
	{
		[self setWatchVariablesArrayAndUpdateInterface:[NSArray array]];
		searchArguments.lastEpsilonValue = [[NSString stringWithFormat:@"%.1f", DEFAULT_FLOATING_POINT_EPSILON] retain];
		[flagsLabel setTextColor:[NSColor disabledControlTextColor]];
	}
}

- (void)windowControllerDidLoadNib:(NSWindowController *) aController
{
	[super windowControllerDidLoadNib:aController];
	
	if (![[NSUserDefaults standardUserDefaults] boolForKey:ZG_EXPAND_OPTIONS])
	{
		[self optionsDisclosureButton:nil];
	}

	[watchWindow setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];

	if ([ZGAppController isRunningLaterThanLion])
	{
		[[NSNotificationCenter defaultCenter]
		 addObserver:self
		 selector:@selector(watchWindowDidExitFullScreen:)
		 name:NSWindowDidExitFullScreenNotification
		 object:watchWindow];
        
		[[NSNotificationCenter defaultCenter]
		 addObserver:self
		 selector:@selector(watchWindowWillExitFullScreen:)
		 name:NSWindowWillExitFullScreenNotification
		 object:watchWindow];
	}
	
	[[NSNotificationCenter defaultCenter]
	 addObserver:self
	 selector:@selector(anApplicationLaunched:)
	 name:ZGProcessLaunched
	 object:nil];
	
	[[NSNotificationCenter defaultCenter]
	 addObserver:self
	 selector:@selector(anApplicationTerminated:)
	 name:ZGProcessTerminated
	 object:nil];
	
	watchVariablesTimer =
		[[ZGTimer alloc]
		 initWithTimeInterval:WATCH_VARIABLES_UPDATE_TIME_INTERVAL
		 target:tableController
		 selector:@selector(updateWatchVariablesTable:)];
	
	[self loadDocumentUserInterface];
}

- (NSFileWrapper *)fileWrapperOfType:(NSString *)typeName error:(NSError **)outError
{
	NSMutableData *writeData = [[NSMutableData alloc] init];
	NSKeyedArchiver *keyedArchiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:writeData];
	
	NSArray *watchVariablesArrayToSave;
	
	if (!watchVariablesArray)
	{
		watchVariablesArrayToSave = [NSArray array];
	}
	else if ([watchVariablesArray count] > MAX_TABLE_VIEW_ITEMS)
	{
		watchVariablesArrayToSave = [watchVariablesArray subarrayWithRange:NSMakeRange(0, MAX_TABLE_VIEW_ITEMS)];
	}
	else
	{
		watchVariablesArrayToSave = watchVariablesArray;
	}
	
	[keyedArchiver
	 encodeObject:watchVariablesArrayToSave
	 forKey:ZGWatchVariablesArrayKey];
	
	[keyedArchiver
	 encodeObject:[currentProcess name]
	 forKey:ZGProcessNameKey];
    
	[keyedArchiver
	 encodeInt32:(int32_t)[[dataTypesPopUpButton selectedItem] tag]
	 forKey:ZGSelectedDataTypeTag];
    
	[keyedArchiver
	 encodeInt32:(int32_t)[[variableQualifierMatrix selectedCell] tag]
	 forKey:ZGQualifierTagKey];
    
	[keyedArchiver
	 encodeInt32:(int32_t)[[functionPopUpButton selectedItem] tag]
	 forKey:ZGFunctionTypeTagKey];
    
	[keyedArchiver
	 encodeBool:[scanUnwritableValuesCheckBox state]
	 forKey:ZGScanUnwritableValuesKey];
    
	[keyedArchiver
	 encodeBool:[ignoreDataAlignmentCheckBox state]
	 forKey:ZGIgnoreDataAlignmentKey];
    
	[keyedArchiver
	 encodeBool:[includeNullTerminatorCheckBox state]
	 forKey:ZGExactStringLengthKey];
    
	[keyedArchiver
	 encodeBool:[ignoreCaseCheckBox state]
	 forKey:ZGIgnoreStringCaseKey];
    
	[keyedArchiver
	 encodeObject:[beginningAddressTextField stringValue]
	 forKey:ZGBeginningAddressKey];
    
	[keyedArchiver
	 encodeObject:[endingAddressTextField stringValue]
	 forKey:ZGEndingAddressKey];
    
	[keyedArchiver
	 encodeObject:searchArguments.lastEpsilonValue
	 forKey:ZGEpsilonKey];
    
	[keyedArchiver
	 encodeObject:searchArguments.lastAboveRangeValue
	 forKey:ZGAboveValueKey];
    
	[keyedArchiver
	 encodeObject:searchArguments.lastBelowRangeValue
	 forKey:ZGBelowValueKey];
    
	[keyedArchiver
	 encodeObject:[searchValueTextField stringValue]
	 forKey:ZGSearchStringValueKey];
    
	[desiredProcessName release];
	desiredProcessName = [[currentProcess name] copy];
	
	[keyedArchiver finishEncoding];
	[keyedArchiver release];

	NSFileWrapper *fileWrapper = [[NSFileWrapper alloc] initRegularFileWithContents:writeData];
	[writeData release];
	
	return [fileWrapper autorelease];
}

- (BOOL)readFromFileWrapper:(NSFileWrapper *)fileWrapper ofType:(NSString *)typeName error:(NSError **)outError
{
	NSData *readData = [fileWrapper regularFileContents];
	NSKeyedUnarchiver *keyedUnarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:readData];
	
	documentState.watchVariablesArray = [[keyedUnarchiver decodeObjectForKey:ZGWatchVariablesArrayKey] retain];
	desiredProcessName = [[keyedUnarchiver decodeObjectForKey:ZGProcessNameKey] retain];
	
	documentState.loadedFromSave = YES;
	documentState.selectedDatatypeTag = (NSInteger)[keyedUnarchiver decodeInt32ForKey:ZGSelectedDataTypeTag];
	documentState.qualifierTag = (NSInteger)[keyedUnarchiver decodeInt32ForKey:ZGQualifierTagKey];
	documentState.functionTypeTag = (NSInteger)[keyedUnarchiver decodeInt32ForKey:ZGFunctionTypeTagKey];
	documentState.scanUnwritableValues = [keyedUnarchiver decodeBoolForKey:ZGScanUnwritableValuesKey];
	documentState.ignoreDataAlignment = [keyedUnarchiver decodeBoolForKey:ZGIgnoreDataAlignmentKey];
	documentState.exactStringLength = [keyedUnarchiver decodeBoolForKey:ZGExactStringLengthKey];
	documentState.ignoreStringCase = [keyedUnarchiver decodeBoolForKey:ZGIgnoreStringCaseKey];
	documentState.beginningAddress = [[keyedUnarchiver decodeObjectForKey:ZGBeginningAddressKey] copy];
	documentState.endingAddress = [[keyedUnarchiver decodeObjectForKey:ZGEndingAddressKey] copy];
	
	documentState.searchValue = [[keyedUnarchiver decodeObjectForKey:ZGSearchStringValueKey] copy];

	searchArguments.lastEpsilonValue = [[keyedUnarchiver decodeObjectForKey:ZGEpsilonKey] copy];
	searchArguments.lastAboveRangeValue = [[keyedUnarchiver decodeObjectForKey:ZGAboveValueKey] copy];
	searchArguments.lastBelowRangeValue = [[keyedUnarchiver decodeObjectForKey:ZGBelowValueKey] copy];

	[keyedUnarchiver release];
	
	BOOL success = documentState.watchVariablesArray != nil && desiredProcessName != nil;
	
	if (success && watchWindow)
	{
		[self loadDocumentUserInterface];
	}
	
	return success;
}

#pragma mark Watching other applications

- (IBAction)runningApplicationsPopUpButtonRequest:(id)sender
{
	BOOL pointerSizeChanged = YES;
	
	if ([[runningApplicationsPopUpButton selectedItem] representedObject] != currentProcess)
	{
		if ([[runningApplicationsPopUpButton selectedItem] representedObject] && currentProcess
			&& ((ZGProcess *)[[runningApplicationsPopUpButton selectedItem] representedObject])->is64Bit != currentProcess->is64Bit)
		{
			pointerSizeChanged = YES;
		}
		// this is about as far as we go when it comes to undo/redos...
		[[self undoManager] removeAllActions];
	}
	
	[currentProcess release];
	currentProcess = [[[runningApplicationsPopUpButton selectedItem] representedObject] retain];
	
	if (pointerSizeChanged)
	{
		// Update the pointer variable sizes
		for (ZGVariable *variable in watchVariablesArray)
		{
			if (variable->type == ZGPointer)
			{
				[variable setPointerSize:currentProcess->is64Bit ? sizeof(int64_t) : sizeof(int32_t)];
			}
		}
		
		[[tableController watchVariablesTableView] reloadData];
	}
	
	// keep track of the process the user targeted
	[[[ZGAppController sharedController] documentController] setLastSelectedProcessName:[currentProcess name]];
	
	if (sender)
	{
		// change the desired process
		[desiredProcessName release];
		desiredProcessName = [[currentProcess name] copy];
	}
	
	if (currentProcess)
	{
		if (![currentProcess grantUsAccess])
		{
			NSAttributedString *errorMessage =
				[[NSAttributedString alloc]
				 initWithString:@"Process Load Error!"
				 attributes:[NSDictionary dictionaryWithObject:[NSColor redColor] forKey:NSForegroundColorAttributeName]];
			
			[generalStatusTextField setAttributedStringValue:errorMessage];
			
			[errorMessage release];
		}
		else
		{
			// clear the status
			[generalStatusTextField setStringValue:@""];
		}
	}
}

- (void)updateRunningApplicationProcesses
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
			
			ZGProcess *representedProcess =
				[[ZGProcess alloc]
				 initWithName:[runningApplication localizedName]
				 processID:[runningApplication processIdentifier]
				 set64Bit:([runningApplication executableArchitecture] == NSBundleExecutableArchitectureX86_64)];
			[menuItem setRepresentedObject:representedProcess];
			[representedProcess release];
			
			[[runningApplicationsPopUpButton menu] addItem:menuItem];
			
			if (!firstRegularApplicationMenuItem && [runningApplication activationPolicy] == NSApplicationActivationPolicyRegular)
			{
				firstRegularApplicationMenuItem = [menuItem retain];
			}
			
			if (![[currentProcess name] isEqualToString:desiredProcessName] && [desiredProcessName isEqualToString:[runningApplication localizedName]])
			{
				[runningApplicationsPopUpButton selectItem:[runningApplicationsPopUpButton lastItem]];
				foundTargettedProcess = YES;
				[currentProcess setProcessID:[runningApplication processIdentifier]];
				[currentProcess setName:[runningApplication localizedName]];
				[self runningApplicationsPopUpButtonRequest:nil];
			}
			else if ([currentProcess processID] == [runningApplication processIdentifier])
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
			[self runningApplicationsPopUpButtonRequest:nil];
		}
		else if ([runningApplicationsPopUpButton indexOfSelectedItem] >= 0)
		{
			[runningApplicationsPopUpButton selectItemAtIndex:0];
			[self runningApplicationsPopUpButtonRequest:nil];
		}
	}
	
	if (firstRegularApplicationMenuItem)
	{
		[firstRegularApplicationMenuItem release];
	}
}

- (void)anApplicationLaunched:(NSNotification *)notification
{
	NSRunningApplication *runningApplication = [[notification userInfo] objectForKey:ZGRunningApplication];
	if ([currentProcess processID] == NON_EXISTENT_PID_NUMBER && [[runningApplication localizedName] isEqualToString:[currentProcess name]])
	{
		[currentProcess setProcessID:[runningApplication processIdentifier]];
		[[runningApplicationsPopUpButton selectedItem] setTitle:[NSString stringWithFormat:@"%@ (%d)", [currentProcess name], [currentProcess processID]]];
		
		// need to grant access
		[self runningApplicationsPopUpButtonRequest:nil];
		
		[searchButton setEnabled:YES];
	}
	else if ([currentProcess processID] != NON_EXISTENT_PID_NUMBER)
	{
		[self updateRunningApplicationProcesses];
	}
}

- (void)anApplicationTerminated:(NSNotification *)notification
{
	NSRunningApplication *runningApplication = [[notification userInfo] objectForKey:ZGRunningApplication];
	[ZGProcess removeFrozenProcess:[runningApplication processIdentifier]];
	
	if (([clearButton isEnabled] || [self canCancelTask]) && [[runningApplication localizedName] isEqualToString:[currentProcess name]])
	{
		NSAttributedString *status =
			[[NSAttributedString alloc]
			 initWithString:@"Process terminated."
			 attributes:
				[NSDictionary
				 dictionaryWithObject:[NSColor redColor]
				 forKey:NSForegroundColorAttributeName]];
		
		[generalStatusTextField setAttributedStringValue:status];
		
		[status release];
		
		[searchButton setEnabled:NO];
		[currentProcess setProcessID:NON_EXISTENT_PID_NUMBER];
		[[runningApplicationsPopUpButton selectedItem] setTitle:[NSString stringWithFormat:@"%@ (none)", [currentProcess name]]];
	}
	else if ([currentProcess processID] != NON_EXISTENT_PID_NUMBER)
	{
		[self updateRunningApplicationProcesses];
	}
}

#pragma mark Updating user interface

- (void)markDocumentChange
{
    [self updateChangeCount:NSChangeDone];
}

- (void)updateNumberOfVariablesFoundDisplay
{
	NSNumberFormatter *numberOfVariablesFoundFormatter = [[NSNumberFormatter alloc] init];
	[numberOfVariablesFoundFormatter setFormat:@"#,###"];
	[generalStatusTextField setStringValue:[NSString stringWithFormat:@"Found %@ value%@...", [numberOfVariablesFoundFormatter stringFromNumber:[NSNumber numberWithInt:currentProcess->numberOfVariablesFound]], currentProcess->numberOfVariablesFound != 1 ? @"s" : @""]];
	[numberOfVariablesFoundFormatter release];
}

- (void)prepareDocumentTask
{
	[runningApplicationsPopUpButton setEnabled:NO];
	[dataTypesPopUpButton setEnabled:NO];
	[variableQualifierMatrix setEnabled:NO];
	[searchValueTextField setEnabled:NO];
	[flagsTextField setEnabled:NO];
	[functionPopUpButton setEnabled:NO];
	[clearButton setEnabled:NO];
	[searchButton setTitle:@"Cancel"];
	[searchButton setKeyEquivalent:@"\e"];
	[scanUnwritableValuesCheckBox setEnabled:NO];
	[ignoreDataAlignmentCheckBox setEnabled:NO];
	[ignoreCaseCheckBox setEnabled:NO];
	[includeNullTerminatorCheckBox setEnabled:NO];
	[beginningAddressTextField setEnabled:NO];
	[endingAddressTextField setEnabled:NO];
	[beginningAddressLabel setTextColor:[NSColor disabledControlTextColor]];
	[endingAddressLabel setTextColor:[NSColor disabledControlTextColor]];
}

- (void)resumeDocument
{
	[clearButton setEnabled:YES];
	
	[dataTypesPopUpButton setEnabled:YES];
    
	if ([self doesFunctionTypeAllowSearchInput])
	{
		[searchValueTextField setEnabled:YES];
	}
	[searchButton setEnabled:YES];
	[searchButton setTitle:@"Search"];
	[searchButton setKeyEquivalent:@"\r"];
	
	[self updateFlags];
	
	[variableQualifierMatrix setEnabled:YES];
	[functionPopUpButton setEnabled:YES];
	
	[scanUnwritableValuesCheckBox setEnabled:YES];
	
	ZGVariableType dataType = (ZGVariableType)[[dataTypesPopUpButton selectedItem] tag];
	
	if (dataType != ZGUTF8String && dataType != ZGInt8)
	{
		[ignoreDataAlignmentCheckBox setEnabled:YES];
	}
	
	if (dataType == ZGUTF8String || dataType == ZGUTF16String)
	{
		[ignoreCaseCheckBox setEnabled:YES];
		[includeNullTerminatorCheckBox setEnabled:YES];
	}
	
	[beginningAddressTextField setEnabled:YES];
	[endingAddressTextField setEnabled:YES];
	[beginningAddressLabel setTextColor:[NSColor controlTextColor]];
	[endingAddressLabel setTextColor:[NSColor controlTextColor]];
	
	[watchWindow makeFirstResponder:searchValueTextField];
}

- (void)updateMemoryStoreUserInterface:(NSTimer *)timer
{
	if ([[self windowForSheet] isVisible])
	{
		[searchingProgressIndicator setDoubleValue:(double)currentProcess->searchProgress];
	}
}

- (void)updateSearchUserInterface:(NSTimer *)timer
{
	if ([[self windowForSheet] isVisible])
	{
		if (!ZGSearchIsCancelling(searchData))
		{
			[searchingProgressIndicator setDoubleValue:(double)currentProcess->searchProgress];
			[self updateNumberOfVariablesFoundDisplay];
		}
		else
		{
			[generalStatusTextField setStringValue:@"Cancelling search..."];
		}
	}
}

- (IBAction)qualifierMatrixButtonRequest:(id)sender
{
	ZGVariableQualifier newQualifier = (ZGVariableQualifier)[[variableQualifierMatrix selectedCell] tag];
	
	for (ZGVariable *variable in watchVariablesArray)
	{
		switch (variable->type)
		{
			case ZGInt8:
			case ZGInt16:
			case ZGInt32:
			case ZGInt64:
				variable->qualifier = newQualifier;
				[variable updateStringValue];
				break;
			default:
				break;
		}
	}
	
	[[tableController watchVariablesTableView] reloadData];
	
	[self markDocumentChange];
}

- (void)updateFlagsRangeTextField
{
	ZGFunctionType functionType = (ZGFunctionType)[[functionPopUpButton selectedItem] tag];
	
	if (functionType == ZGGreaterThan || functionType == ZGGreaterThanStored)
	{
		[flagsLabel setStringValue:@"Below:"];
		
		if (searchArguments.lastBelowRangeValue)
		{
			[flagsTextField setStringValue:searchArguments.lastBelowRangeValue];
		}
		else
		{
			[flagsTextField setStringValue:@""];
		}
	}
	else if (functionType == ZGLessThan || functionType == ZGLessThanStored)
	{
		[flagsLabel setStringValue:@"Above:"];
		
		if (searchArguments.lastAboveRangeValue)
		{
			[flagsTextField setStringValue:searchArguments.lastAboveRangeValue];
		}
		else
		{
			[flagsTextField setStringValue:@""];
		}
	}	
}

- (void)updateFlags
{
	ZGVariableType dataType = (ZGVariableType)[[dataTypesPopUpButton selectedItem] tag];
	ZGFunctionType functionType = (ZGFunctionType)[[functionPopUpButton selectedItem] tag];
	
	if (dataType == ZGUTF8String || dataType == ZGUTF16String)
	{
		[flagsTextField setEnabled:NO];
		[flagsTextField setStringValue:@""];
		[flagsLabel setStringValue:@"Flags:"];
		[flagsLabel setTextColor:[NSColor disabledControlTextColor]];
	}
	else if (dataType == ZGFloat || dataType == ZGDouble)
	{
		[flagsTextField setEnabled:YES];
		[flagsLabel setTextColor:[NSColor controlTextColor]];
		
		if (functionType == ZGEquals || functionType == ZGNotEquals || functionType == ZGEqualsStored || functionType == ZGNotEqualsStored || functionType == ZGEqualsStoredPlus || functionType == ZGNotEqualsStoredPlus)
		{
			// epsilon
			[flagsLabel setStringValue:@"Epsilon:"];
			if (searchArguments.lastEpsilonValue)
			{
				[flagsTextField setStringValue:searchArguments.lastEpsilonValue];
			}
			else
			{
				[flagsTextField setStringValue:@""];
			}
		}
		else
		{
			// range
			[self updateFlagsRangeTextField];
		}
	}
	else /* if data type is an integer type */
	{
		if (functionType == ZGEquals || functionType == ZGNotEquals || functionType == ZGEqualsStored || functionType == ZGNotEqualsStored || functionType == ZGEqualsStoredPlus || functionType == ZGNotEqualsStoredPlus)
		{
			[flagsTextField setEnabled:NO];
			[flagsTextField setStringValue:@""];
			[flagsLabel setStringValue:@"Flags:"];
			[flagsLabel setTextColor:[NSColor disabledControlTextColor]];
		}
		else
		{
			// range
			[self updateFlagsRangeTextField];
			
			[flagsTextField setEnabled:YES];
			[flagsLabel setTextColor:[NSColor controlTextColor]];
		}
	}
}

static NSSize *expandedWindowMinSize = nil;
- (IBAction)optionsDisclosureButton:(id)sender
{
    NSRect windowFrame = [watchWindow frame];
	
	// The first time this method is called, the disclosure triangle is expanded
	// Record the minimize size of the window before we expand the content
	// This will make it easy to keep track of the minimum window size when expanded,
	// and will make it easy to calculate the minimum window size when contracted.
	if (!expandedWindowMinSize)
	{
		expandedWindowMinSize = malloc(sizeof(NSSize));
		if (!expandedWindowMinSize)
		{
			NSLog(@"optionsDisclosureButton: Not enough memory");
			return;
		}
		
		*expandedWindowMinSize = [watchWindow minSize];
	}
	
	// This occurs when sender is nil (when we call it in code), or when
	// it's called by another action (eg: the "Options" label button)
	if (sender != optionsDisclosureButton)
	{
		[optionsDisclosureButton setState:[optionsDisclosureButton state] == NSOnState ? NSOffState : NSOnState];
	}
	
	switch ([optionsDisclosureButton state])
	{
		case NSOnState:
			// Check if we need to resize based on the relative position between the functionPopUpButton and the optionsView
			// If so, this means that the functionPopUpButton's y origin > optionsView y origin
			if ([optionsView frame].origin.y < [functionPopUpButton frame].origin.y + [functionPopUpButton frame].size.height + 6)
			{
				// Resize the window to its the minimum size when the disclosure triangle is expanded
				windowFrame.size.height += ([functionPopUpButton frame].origin.y + [functionPopUpButton frame].size.height + 6) - [optionsView frame].origin.y;
				windowFrame.origin.y -= ([functionPopUpButton frame].origin.y + [functionPopUpButton frame].size.height + 6) - [optionsView frame].origin.y;
				
				[watchWindow
				 setFrame:windowFrame
				 display:YES
				 animate:YES];
			}
			
			[optionsView setHidden:NO];
			
			[watchWindow setMinSize:*expandedWindowMinSize];
			break;
		case NSOffState:
			[optionsView setHidden:YES];
			
			// Only resize when the window is at the minimum size
			if (windowFrame.size.height == [watchWindow minSize].height)
			{
				windowFrame.size.height -= [optionsView frame].size.height + 6;
				windowFrame.origin.y += [optionsView frame].size.height + 6;
				
				[watchWindow
				 setFrame:windowFrame
				 display:YES
				 animate:YES];
			}
			
			NSSize minSize = *expandedWindowMinSize;
			minSize.height -= [optionsView frame].size.height + 6;
			[watchWindow setMinSize:minSize];
			break;
		default:
			break;
	}
	
	[[NSUserDefaults standardUserDefaults]
	 setBool:[optionsDisclosureButton state]
	 forKey:ZG_EXPAND_OPTIONS];
}

- (void)watchWindowWillExitFullScreen:(NSNotificationCenter *)notification
{
	[optionsView setHidden:YES];
}

- (void)watchWindowDidExitFullScreen:(NSNotification *)notification
{
	if (expandedWindowMinSize && [watchWindow minSize].height == expandedWindowMinSize->height)
	{
		if ([watchWindow frame].size.height < expandedWindowMinSize->height)
		{
			[optionsDisclosureButton setState:NSOffState];
			[self optionsDisclosureButton:nil];
		}
		else
		{
			[optionsView setHidden:NO];
		}
	}
}

- (void)selectDataTypeWithTag:(ZGVariableType)newTag recordUndo:(BOOL)recordUndo
{
	if (currentSearchDataType != newTag)
	{
		[dataTypesPopUpButton selectItemWithTag:newTag];

		[functionPopUpButton setEnabled:YES];
		[variableQualifierMatrix setEnabled:YES];

		if (newTag == ZGUTF8String || newTag == ZGUTF16String)
		{
			[ignoreCaseCheckBox setEnabled:YES];
			[includeNullTerminatorCheckBox setEnabled:YES];
		}
		else
		{
			[ignoreCaseCheckBox setEnabled:NO];
			[ignoreCaseCheckBox setState:NSOffState];

			[includeNullTerminatorCheckBox setEnabled:NO];
			[includeNullTerminatorCheckBox setState:NSOffState];
		}

		[ignoreDataAlignmentCheckBox setEnabled:(newTag != ZGUTF8String && newTag != ZGInt8)];

		[self updateFlags];

		if (recordUndo)
		{
			[[self undoManager] setActionName:@"Data Type Change"];
			[[[self undoManager] prepareWithInvocationTarget:self]
			 selectDataTypeWithTag:currentSearchDataType
			 recordUndo:YES];
		}
		
		currentSearchDataType = newTag;
	}
}

- (IBAction)dataTypePopUpButtonRequest:(id)sender
{
	[self
	 selectDataTypeWithTag:(ZGVariableType)[[sender selectedItem] tag]
	 recordUndo:YES];
}

- (BOOL)doesFunctionTypeAllowSearchInput
{
	BOOL allows;
	switch ([[functionPopUpButton selectedItem] tag])
	{
		case ZGEquals:
		case ZGNotEquals:
		case ZGGreaterThan:
		case ZGLessThan:
		case ZGEqualsStoredPlus:
		case ZGNotEqualsStoredPlus:
			allows = YES;
			break;
		default:
			allows = NO;
			break;
	}

	return allows;
}

- (BOOL)isFunctionTypeStore:(NSInteger)functionTypeTag
{
	BOOL isFunctionTypeStore;
	
	switch (functionTypeTag)
	{
		case ZGEqualsStored:
		case ZGNotEqualsStored:
		case ZGGreaterThanStored:
		case ZGLessThanStored:
		case ZGEqualsStoredPlus:
		case ZGNotEqualsStoredPlus:
			isFunctionTypeStore = YES;
			break;
		default:
			isFunctionTypeStore = NO;
	}

	return isFunctionTypeStore;
}

- (BOOL)isFunctionTypeStore
{
	return [self isFunctionTypeStore:[[functionPopUpButton selectedItem] tag]];
}

- (void)functionTypePopUpButtonRequest:(id)sender markChanges:(BOOL)shouldMarkChanges
{
	[self updateFlags];
	
	if (![self doesFunctionTypeAllowSearchInput])
	{
		[searchValueTextField setEnabled:NO];
		[searchValueLabel setTextColor:[NSColor disabledControlTextColor]];
	}
	else
	{
		[searchValueTextField setEnabled:YES];
		[searchValueLabel setTextColor:[NSColor controlTextColor]];
		[watchWindow makeFirstResponder:searchValueTextField];
	}

	if (shouldMarkChanges)
	{
		[self markDocumentChange];
	}
}

- (IBAction)functionTypePopUpButtonRequest:(id)sender
{
	[self
	 functionTypePopUpButtonRequest:sender
	 markChanges:YES];
}

#pragma mark Useful Methods

- (void *)valueFromString:(NSString *)stringValue dataType:(ZGVariableType)dataType dataSize:(ZGMemorySize *)dataSize
{
	void *value = NULL;
	BOOL searchValueIsAHexRepresentation = [stringValue isHexRepresentation];
	
	if (dataType == ZGInt8)
	{
		int8_t variableValue = 0;
		
		if (searchValueIsAHexRepresentation)
		{
			unsigned int theValue = 0;
			[[NSScanner scannerWithString:stringValue] scanHexInt:&theValue];
			variableValue = theValue;
		}
		else
		{
			variableValue = [stringValue intValue];
		}
		
		*dataSize = 1;
		value = malloc((size_t)*dataSize);
		memcpy(value, &variableValue, (size_t)*dataSize);
	}
	else if (dataType == ZGInt16)
	{
		int16_t variableValue = 0;
		
		if (searchValueIsAHexRepresentation)
		{
			unsigned int theValue = 0;
			[[NSScanner scannerWithString:stringValue] scanHexInt:&theValue];
			variableValue = theValue;
		}
		else
		{
			variableValue = [stringValue intValue];
		}
		
		*dataSize = 2;
		value = malloc((size_t)*dataSize);
		memcpy(value, &variableValue, (size_t)*dataSize);
	}
	else if (dataType == ZGInt32 || (dataType == ZGPointer && !currentProcess->is64Bit))
	{
		int32_t variableValue = 0;
		
		if (searchValueIsAHexRepresentation)
		{
			unsigned int theValue = 0;
			[[NSScanner scannerWithString:stringValue] scanHexInt:&theValue];
			variableValue = theValue;
		}
		else
		{
			variableValue = [stringValue unsignedIntValue];
		}
		
		*dataSize = 4;
		value = malloc((size_t)*dataSize);
		memcpy(value, &variableValue, (size_t)*dataSize);
	}
	else if (dataType == ZGFloat)
	{
		float variableValue = 0.0;
		
		if (searchValueIsAHexRepresentation)
		{
			[[NSScanner scannerWithString:stringValue] scanHexFloat:&variableValue];
		}
		else
		{
			variableValue = [stringValue floatValue];
		}
		
		*dataSize = 4;
		value = malloc((size_t)*dataSize);
		memcpy(value, &variableValue, (size_t)*dataSize);
	}
	else if (dataType == ZGInt64 || (dataType == ZGPointer && currentProcess->is64Bit))
	{
		int64_t variableValue = 0;
		
		if (searchValueIsAHexRepresentation)
		{
			unsigned long long theValue = 0;
			[[NSScanner scannerWithString:stringValue] scanHexLongLong:&theValue];
			variableValue = theValue;
		}
		else
		{
			variableValue = [stringValue unsignedLongLongValue];
		}
		
		*dataSize = 8;
		value = malloc((size_t)*dataSize);
		memcpy(value, &variableValue, (size_t)*dataSize);
	}
	else if (dataType == ZGDouble)
	{
		double variableValue = 0.0;
		
		if (searchValueIsAHexRepresentation)
		{
			[[NSScanner scannerWithString:stringValue] scanHexDouble:&variableValue];
		}
		else
		{
			variableValue = [stringValue doubleValue];
		}
		
		*dataSize = 8;
		value = malloc((size_t)*dataSize);
		memcpy(value, &variableValue, (size_t)*dataSize);
	}
	else if (dataType == ZGUTF8String)
	{
		const char *variableValue = [stringValue cStringUsingEncoding:NSUTF8StringEncoding];
		*dataSize = strlen(variableValue) + 1;
		value = malloc((size_t)*dataSize);
		strncpy(value, variableValue, (size_t)*dataSize);
	}
	else if (dataType == ZGUTF16String)
	{
		*dataSize = [stringValue length] * sizeof(unichar);
		value = malloc((size_t)*dataSize);
		[stringValue getCharacters:value
							 range:NSMakeRange(0, [stringValue length])];
	}
	
	else if (dataType == ZGByteArray)
	{
		NSArray *bytesArray = [stringValue componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

		*dataSize = [bytesArray count];
		value = malloc((size_t)*dataSize);
		
		unsigned char *valuePtr = value;
		
		for (NSString *byteString in bytesArray)
		{
			unsigned int theValue = 0;
			if (([byteString rangeOfString:@"?"].location == NSNotFound && [byteString rangeOfString:@"*"].location == NSNotFound) || [byteString length] != 2)
			{
				[[NSScanner scannerWithString:byteString] scanHexInt:&theValue];
				*valuePtr = (unsigned char)theValue;
			}
			else
			{
				*valuePtr = 0;
				if ([byteString length] == 2)
				{
					[[NSScanner scannerWithString:[byteString substringToIndex:1]] scanHexInt:&theValue];
					*valuePtr = (((unsigned char)theValue) << 4) & 0xF0;
					theValue = 0;
					[[NSScanner scannerWithString:[byteString substringFromIndex:1]] scanHexInt:&theValue];
					*valuePtr |= ((unsigned char)theValue) & 0x0F;
				}
			}
			
			valuePtr++;
		}
	}
	
	return value;
}

- (unsigned char *)allocateFlagsForByteArrayWildcards:(NSString *)searchValue
{
	NSArray *bytesArray = [searchValue componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

	unsigned char *data = calloc(1, [bytesArray count] * sizeof(unsigned char));

	if (data)
	{
		__block BOOL didUseWildcard = NO;
		[bytesArray enumerateObjectsUsingBlock:^(NSString *byteString, NSUInteger byteIndex, BOOL *stop)
		{
			if ([byteString length] == 2)
			{
				if ([[byteString substringToIndex:1] isEqualToString:@"?"] || [[byteString substringToIndex:1] isEqualToString:@"*"])
				{
					data[byteIndex] |= 0xF0;
					didUseWildcard = YES;
				}
				
				if ([[byteString substringFromIndex:1] isEqualToString:@"?"] || [[byteString substringFromIndex:1] isEqualToString:@"*"])
				{
					data[byteIndex] |= 0x0F;
					didUseWildcard = YES;
				}
			}
		}];
		
		if (!didUseWildcard)
		{
			free(data);
			data = NULL;
		}
	}
    
	return data;
}

- (void)setWatchVariablesArrayAndUpdateInterface:(NSArray *)newWatchVariablesArray
{
	if ([[self undoManager] isUndoing] || [[self undoManager] isRedoing])
	{
		// Clear the status
		[generalStatusTextField setStringValue:@""];
		
		[[[self undoManager] prepareWithInvocationTarget:self] setWatchVariablesArrayAndUpdateInterface:watchVariablesArray];
	}
	
	[self setWatchVariablesArray:newWatchVariablesArray];
	[[tableController watchVariablesTableView] reloadData];
	
	// Make sure the search value field is enabled if we aren't doing a store comparison
	if ([self doesFunctionTypeAllowSearchInput])
	{
		[searchValueTextField setEnabled:YES];
		[searchValueLabel setTextColor:[NSColor controlTextColor]]; 
	}
}

#pragma mark Locking  & Unlocking

- (void)unlockTarget
{
	[clearButton setEnabled:NO];
	[runningApplicationsPopUpButton setEnabled:YES];
	[variableQualifierMatrix setEnabled:YES];
	
	// we enable the search button in case its disabled, as what would happen if the targetted application terminates when in a multiple search situation
	[searchButton setEnabled:YES];
	
	BOOL unlockingFromDeadProcess = ([currentProcess processID] == NON_EXISTENT_PID_NUMBER);
	
	[self updateRunningApplicationProcesses];
	
	if (!unlockingFromDeadProcess)
	{
		[generalStatusTextField setStringValue:[NSString stringWithFormat:@"Unlocked %@", [currentProcess name]]];
		
		if ([[self undoManager] isUndoing])
		{
			[[self undoManager] setActionName:@"Lock Target"];
		}
		else if ([[self undoManager] isRedoing])
		{
			[[self undoManager] setActionName:@"Unlock Target"];
		}
		[[[self undoManager] prepareWithInvocationTarget:self] lockTarget];
	}
	else
	{
		[[self undoManager] removeAllActions];
	}
}

- (void)lockTarget
{
	[clearButton setEnabled:YES];
	[runningApplicationsPopUpButton setEnabled:NO];
	
	[generalStatusTextField setStringValue:[NSString stringWithFormat:@"Locked %@", [currentProcess name]]];
	
	if (desiredProcessName && ![desiredProcessName isEqualToString:[currentProcess name]])
	{
		[desiredProcessName release];
		desiredProcessName = [[currentProcess name] copy];
	}
	
	if ([[self undoManager] isUndoing])
	{
		[[self undoManager] setActionName:@"Unlock Target"];
	}
	else if ([[self undoManager] isRedoing])
	{
		[[self undoManager] setActionName:@"Lock Target"];
	}
	
	[[[self undoManager] prepareWithInvocationTarget:self] unlockTarget];
}

- (IBAction)lockTarget:(id)sender
{
	if (![clearButton isEnabled])
	{
		[[self undoManager] setActionName:@"Lock Target"];
		[self lockTarget];
	}
	else
	{
		[[self undoManager] setActionName:@"Unlock Target"];
		[self unlockTarget];
	}
}

#pragma mark Confirm Input Methods

- (BOOL)isInNarrowSearchMode
{
	ZGVariableType dataType = (ZGVariableType)[[dataTypesPopUpButton selectedItem] tag];
	
	BOOL goingToNarrowDownSearches = NO;
	for (ZGVariable *variable in watchVariablesArray)
	{
		if ([variable shouldBeSearched] && variable->type == dataType)
		{
			goingToNarrowDownSearches = YES;
			break;
		}
	}
	
	return goingToNarrowDownSearches;
}

- (NSString *)testSearchComponent:(NSString *)searchComponent
{
	return isValidNumber(searchComponent) ? nil : @"The function you are using requires the search value to be a valid expression."; 
}

- (NSString *)confirmSearchInput:(NSString *)expression
{
	ZGVariableType dataType = (ZGVariableType)[[dataTypesPopUpButton selectedItem] tag];
	ZGFunctionType functionType = (ZGFunctionType)[[functionPopUpButton selectedItem] tag];
	
	if (dataType != ZGUTF8String && dataType != ZGUTF16String && dataType != ZGByteArray)
	{
		// This doesn't matter if the search is implicit or if it's a regular function type
		if ([self doesFunctionTypeAllowSearchInput])
		{
			NSString *inputError = [self testSearchComponent:expression];
			
			if (inputError)
			{
				return inputError;
			}
		}
	}
	else if (functionType != ZGEquals && functionType != ZGNotEquals && functionType != ZGEqualsStored && functionType != ZGNotEqualsStored && functionType != ZGEqualsStoredPlus && functionType != ZGNotEqualsStoredPlus)
	{
		return [NSString stringWithFormat:@"The function you are using does not support %@.", dataType == ZGByteArray ? @"Byte Arrays" : @"Strings"];
	}
	
	if ((dataType == ZGUTF8String || dataType == ZGUTF16String || dataType == ZGByteArray) && searchArguments.isImplicit)
	{
		return [NSString stringWithFormat:@"Comparing Stored Values is not supported for %@.", dataType == ZGByteArray ? @"Byte Arrays" : @"Strings"];
	}
	
	return nil;
}

#pragma mark Searching

- (IBAction)clearSearchValues:(id)sender
{
	[[self undoManager] removeAllActions];
	
	[runningApplicationsPopUpButton setEnabled:YES];
	[dataTypesPopUpButton setEnabled:YES];
	[variableQualifierMatrix setEnabled:YES];
	
	// we enable the search button in case its disabled, as what would happen if the targetted application terminates when in a multiple search situation
	[searchButton setEnabled:YES];
	
	[self setWatchVariablesArray:[NSArray array]];
	[[tableController watchVariablesTableView] reloadData];
	
	if ([self doesFunctionTypeAllowSearchInput])
	{
		[searchValueTextField setEnabled:YES];
	}
	
	[clearButton setEnabled:NO];
	
	[self updateRunningApplicationProcesses];
	
	[generalStatusTextField setStringValue:@"Cleared search."];
	
	[self markDocumentChange];
}

- (void)searchCleanUp:(NSArray *)newVariablesArray
{
	if ([newVariablesArray count] != [watchVariablesArray count])
	{
		[[self undoManager] setActionName:@"Search"];
		[[[self undoManager] prepareWithInvocationTarget:self] setWatchVariablesArrayAndUpdateInterface:watchVariablesArray];
	}
	
	currentProcess->searchProgress = 0;
	if (ZGSearchDidCancelSearch(searchData))
	{
		[searchingProgressIndicator setDoubleValue:(double)currentProcess->searchProgress];
		[generalStatusTextField setStringValue:@"Search canceled."];
	}
	else
	{
		ZGInitializeSearch(searchData);
		[self updateSearchUserInterface:nil];
		
		[watchVariablesArray release];
		watchVariablesArray = [[NSArray arrayWithArray:newVariablesArray] retain];
		[[tableController watchVariablesTableView] reloadData];
	}
	
	[self resumeDocument];
}

- (IBAction)searchValue:(id)sender
{
	ZGVariableType dataType = (ZGVariableType)[[dataTypesPopUpButton selectedItem] tag];
	
	BOOL goingToNarrowDownSearches = [self isInNarrowSearchMode];
	
	if ([self canStartTask])
	{
		// Find all variables that are set to be searched, but shouldn't be
		// this is if the variable's data type does not match, or if the variable
		// is frozen
		for (ZGVariable *variable in watchVariablesArray)
		{
			if ([variable shouldBeSearched] && (variable->type != dataType || variable->isFrozen))
			{
				[variable setShouldBeSearched:NO];
			}
		}
		
		// Re-display in case we set variables to not be searched
		[[tableController watchVariablesTableView] setNeedsDisplay:YES];
		
		// Basic search information
		ZGMemorySize dataSize = 0;
		void *searchValue = NULL;
		
		// Set default search arguments
		searchArguments.epsilon = DEFAULT_FLOATING_POINT_EPSILON;
		if (searchArguments.rangeValue)
		{
			free(searchArguments.rangeValue);
		}
		searchArguments.rangeValue = NULL;
		
		searchArguments.sensitive = ![ignoreCaseCheckBox state];
		searchArguments.disregardNullTerminator = ![includeNullTerminatorCheckBox state];
		searchArguments.isImplicit = [self isFunctionTypeStore];
		
		NSString *evaluatedSearchExpression = nil;
		NSString *inputErrorMessage = nil;
		
		evaluatedSearchExpression =
			(dataType == ZGUTF8String || dataType == ZGUTF16String || dataType == ZGByteArray)
			? [searchValueTextField stringValue]
			: [ZGCalculator evaluateExpression:[searchValueTextField stringValue]];
		
		inputErrorMessage = [self confirmSearchInput:evaluatedSearchExpression];
		
		if (inputErrorMessage)
		{
			NSRunAlertPanel(@"Invalid Input", inputErrorMessage, nil, nil, nil);
			return;
		}
		
		// get search value and data size
		searchValue =
			[self
			 valueFromString:evaluatedSearchExpression
			 dataType:dataType
			 dataSize:&dataSize];
		
		// We want to read the null terminator in this case... even though we normally don't store the terminator
		// internally for UTF-16 strings. Lame hack, I know.
		if (!searchArguments.disregardNullTerminator && dataType == ZGUTF16String)
		{
			dataSize += sizeof(unichar);
		}
		
		ZGFunctionType functionType = (ZGFunctionType)[[functionPopUpButton selectedItem] tag];
		
		if (searchValue && ![self doesFunctionTypeAllowSearchInput])
		{
			free(searchValue);
			searchValue = NULL;
		}
		
		BOOL flagsFieldIsBlank = [[[flagsTextField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] isEqualToString:@""];
		
		if ([flagsTextField isEnabled])
		{
			NSString *flagsExpression =
				(dataType == ZGUTF8String || dataType == ZGUTF16String || dataType == ZGByteArray)
				? [flagsTextField stringValue]
				: [ZGCalculator evaluateExpression:[flagsTextField stringValue]];
			
			inputErrorMessage = [self testSearchComponent:flagsExpression];
			
			if (inputErrorMessage && !flagsFieldIsBlank)
			{
				NSString *field =
					(functionType == ZGEquals || functionType == ZGNotEquals || functionType == ZGEqualsStored || functionType == ZGNotEqualsStored)
					? @"Epsilon"
					: ((functionType == ZGGreaterThan || functionType == ZGGreaterThanStored) ? @"Below" : @"Above");
				NSRunAlertPanel(@"Invalid Input", @"The value corresponding to %@ needs to be a valid expression or be left blank.", nil, nil, nil, field);
				return;
			}
			else /* if (!inputErrorMessage || flagsFieldIsBlank) */
			{
				if (functionType == ZGGreaterThan || functionType == ZGLessThan || functionType == ZGGreaterThanStored || functionType == ZGLessThanStored)
				{
					if (!flagsFieldIsBlank)
					{
						// Clearly a range type of search
						ZGMemorySize rangeDataSize;
						searchArguments.rangeValue =
							[self
							 valueFromString:flagsExpression
							 dataType:dataType
							 dataSize:&rangeDataSize];
					}
					else
					{
						searchArguments.rangeValue = NULL;
					}
					
					if (functionType == ZGGreaterThan || functionType == ZGGreaterThanStored)
					{
						[searchArguments.lastBelowRangeValue release];
						searchArguments.lastBelowRangeValue = [[flagsTextField stringValue] copy];
					}
					else if (functionType == ZGLessThan || functionType == ZGLessThanStored)
					{
						[searchArguments.lastAboveRangeValue release];
						searchArguments.lastAboveRangeValue = [[flagsTextField stringValue] copy];
					}
				}
				else
				{
					if (!flagsFieldIsBlank)
					{
						// Clearly an epsilon flag
						ZGMemorySize epsilonDataSize;
						void *epsilon =
							[self
							 valueFromString:flagsExpression
							 dataType:ZGDouble
							 dataSize:&epsilonDataSize];
						if (epsilon)
						{
							searchArguments.epsilon = *((double *)epsilon);
							free(epsilon);
						}
					}
					else
					{
						searchArguments.epsilon = DEFAULT_FLOATING_POINT_EPSILON;
					}
					
					[searchArguments.lastEpsilonValue release];
					searchArguments.lastEpsilonValue = [[flagsTextField stringValue] copy];
				}
			}
		}
		
		// Deal with beginning and ending addresses, if there are any
		
		NSString *calculatedBeginAddress = [ZGCalculator evaluateExpression:[beginningAddressTextField stringValue]];
		NSString *calculatedEndAddress = [ZGCalculator evaluateExpression:[endingAddressTextField stringValue]];
		
		if (![[beginningAddressTextField stringValue] isEqualToString:@""])
		{
			if ([self testSearchComponent:calculatedBeginAddress])
			{
				NSRunAlertPanel(@"Invalid Input", @"The expression in the beginning address field is not valid.", nil, nil, nil, nil);
				return;
			}
			
			searchArguments.beginAddress = memoryAddressFromExpression(calculatedBeginAddress);
			searchArguments.beginAddressExists = YES;
		}
		else
		{
			searchArguments.beginAddressExists = NO;
		}
		
		if (![[endingAddressTextField stringValue] isEqualToString:@""])
		{
			if ([self testSearchComponent:calculatedEndAddress])
			{
				NSRunAlertPanel(@"Invalid Input", @"The expression in the ending address field is not valid.", nil, nil, nil, nil);
				return;
			}
			
			searchArguments.endAddress = memoryAddressFromExpression(calculatedEndAddress);
			searchArguments.endAddressExists = YES;
		}
		else
		{
			searchArguments.endAddressExists = NO;
		}
		
		if (searchArguments.beginAddressExists && searchArguments.endAddressExists && searchArguments.beginAddress >= searchArguments.endAddress)
		{
			NSRunAlertPanel(@"Invalid Input", @"The value in the beginning address field must be less than the value of the ending address field, or one or both of the fields can be omitted.", nil, nil, nil, nil);
			return;
		}
		
		NSMutableArray *temporaryVariablesArray = [[NSMutableArray alloc] init];
		
		// Add all variables whose value should not be searched for, first
		
		for (ZGVariable *variable in watchVariablesArray)
		{
			if (variable->isFrozen || variable->type != [[dataTypesPopUpButton selectedItem] tag])
			{
				[variable setShouldBeSearched:NO];
			}
			
			if (!variable->shouldBeSearched)
			{
				[temporaryVariablesArray addObject:variable];
			}
		}
		
		[self prepareDocumentTask];
		
		static BOOL (*compareFunctions[10])(ZGSearchArguments *, const void *, const void *, ZGVariableType, ZGMemorySize, void *) =
		{
			equalFunction, notEqualFunction, greaterThanFunction, lessThanFunction, equalFunction, notEqualFunction, greaterThanFunction, lessThanFunction, equalPlusFunction, notEqualPlusFunction
		};
		
		BOOL (*compareFunction)(ZGSearchArguments *, const void *, const void *, ZGVariableType, ZGMemorySize, void *) = compareFunctions[functionType];
        
		void *extraData =
			dataType == ZGByteArray
			? [self allocateFlagsForByteArrayWildcards:evaluatedSearchExpression]
			: ((functionType == ZGEqualsStoredPlus || functionType == ZGNotEqualsStoredPlus) ? searchValue : &collator);
		
		if (!goingToNarrowDownSearches)
		{
			int numberOfRegions = [currentProcess numberOfRegions];
			
			[searchingProgressIndicator setMaxValue:numberOfRegions];
			currentProcess->numberOfVariablesFound = 0;
			currentProcess->searchProgress = 0;
			
			updateSearchUserInterfaceTimer =
				[[ZGTimer alloc]
				 initWithTimeInterval:USER_INTERFACE_UPDATE_TIME_INTERVAL
				 target:self
				 selector:@selector(updateSearchUserInterface:)];
			
			ZGVariableQualifier qualifier =
				[[variableQualifierMatrix cellWithTag:SIGNED_BUTTON_CELL_TAG] state] == NSOnState
				? ZGSigned
				: ZGUnsigned;
			ZGMemorySize pointerSize =
				currentProcess->is64Bit
				? sizeof(int64_t)
				: sizeof(int32_t);
			
			search_for_data_t searchForDataCallback = ^(void *data, void *data2, ZGMemoryAddress address, ZGMemorySize currentRegionNumber)
			{
				if ((!searchArguments.beginAddressExists || searchArguments.beginAddress <= address) &&
					(!searchArguments.endAddressExists || searchArguments.endAddress >= address + dataSize) &&
					compareFunction(&searchArguments, data, (data2 != NULL) ? data2 : searchValue, dataType, dataSize, extraData))
				{
					ZGVariable *newVariable =
						[[ZGVariable alloc]
						 initWithValue:data
						 size:dataSize
						 address:address
						 type:dataType
						 qualifier:qualifier
						 pointerSize:pointerSize];
					
					[temporaryVariablesArray addObject:newVariable];
					[newVariable release];
					 
					currentProcess->numberOfVariablesFound++;
				}
				
				currentProcess->searchProgress = currentRegionNumber;
			};
			
			dispatch_block_t searchForDataCompleteBlock = ^
			{
				if (searchValue)
				{
					free(searchValue);
				}
                
				if (extraData && dataType == ZGByteArray)
				{
					free(extraData);
				}
				
				[updateSearchUserInterfaceTimer invalidate];
				[updateSearchUserInterfaceTimer release];
				updateSearchUserInterfaceTimer = nil;
				
				[self searchCleanUp:temporaryVariablesArray];
				[temporaryVariablesArray release];
			};
			dispatch_block_t searchForDataBlock = ^
			{
				ZGMemorySize dataAlignment =
					([ignoreDataAlignmentCheckBox state] == NSOnState)
					? sizeof(int8_t)
					: ZGDataAlignment(currentProcess->is64Bit, dataType, dataSize);
				
				if (searchArguments.isImplicit)
				{
					ZGSearchForSavedData([currentProcess processTask], dataAlignment, dataSize, searchData, searchForDataCallback);
				}
				else
				{
					searchData->scanReadOnly = ([scanUnwritableValuesCheckBox state] == NSOnState);
					ZGSearchForData([currentProcess processTask], dataAlignment, dataSize, searchData, searchForDataCallback);
				}
				dispatch_async(dispatch_get_main_queue(), searchForDataCompleteBlock);
			};
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), searchForDataBlock);
		}
		else /* if (goingToNarrowDownSearches) */
		{
			ZGMemoryMap processTask = [currentProcess processTask];
			
			[searchingProgressIndicator setMaxValue:[watchVariablesArray count]];
			currentProcess->searchProgress = 0;
			currentProcess->numberOfVariablesFound = 0;
			
			updateSearchUserInterfaceTimer =
				[[ZGTimer alloc]
				 initWithTimeInterval:USER_INTERFACE_UPDATE_TIME_INTERVAL
				 target:self
				 selector:@selector(updateSearchUserInterface:)];
			
			dispatch_block_t completeSearchBlock = ^
			{
				if (searchValue)
				{
					free(searchValue);
				}
				
				if (extraData && dataType == ZGByteArray)
				{
					free(extraData);
				}
				[updateSearchUserInterfaceTimer invalidate];
				[updateSearchUserInterfaceTimer release];
				updateSearchUserInterfaceTimer = nil;
				
				[self searchCleanUp:temporaryVariablesArray];
				[temporaryVariablesArray release];
			};
			dispatch_block_t searchBlock = ^
			{
				for (ZGVariable *variable in watchVariablesArray)
				{
					if (variable->shouldBeSearched)
					{
						if (variable->size > 0 && dataSize > 0 &&
							(!searchArguments.beginAddressExists || searchArguments.beginAddress <= variable->address) &&
							(!searchArguments.endAddressExists || searchArguments.endAddress >= variable->address + dataSize))
						{
							ZGMemorySize outputSize = dataSize;
							void *value = NULL;
							if (ZGReadBytes(processTask, variable->address, &value, &outputSize))
							{
								void *value2 = searchArguments.isImplicit ? ZGSavedValue(variable->address, searchData, dataSize) : searchValue;
								
								if (value2 && compareFunction(&searchArguments, value, value2, dataType, dataSize, extraData))
								{
									[temporaryVariablesArray addObject:variable];
									currentProcess->numberOfVariablesFound++;
								}
								
								ZGFreeBytes(processTask, value, outputSize);
							}
						}
					}
					
					if (ZGSearchDidCancelSearch(searchData))
					{
						break;
					}
					
					currentProcess->searchProgress++;
				}
				
				dispatch_async(dispatch_get_main_queue(), completeSearchBlock);
			};
			ZGInitializeSearch(searchData);
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), searchBlock);
		}
	}
	else
	{
		if (currentProcess->isDoingMemoryDump)
		{
			// Cancel memory dump
			currentProcess->isDoingMemoryDump = NO;
			[generalStatusTextField setStringValue:@"Canceling Memory Dump..."];
		}
		else if (currentProcess->isStoringAllData)
		{
			// Cancel memory store
			currentProcess->isStoringAllData = NO;
			[generalStatusTextField setStringValue:@"Canceling Memory Store..."];
		}
		else
		{
			// Cancel the search
			[searchButton setEnabled:NO];
			
			if (goingToNarrowDownSearches)
			{
				ZGCancelSearchImmediately(searchData);
			}
			else
			{
				ZGCancelSearch(searchData);
			}
		}
	}
}

#pragma mark Getting stored values

- (IBAction)getInitialValues:(id)sender
{
	if (currentProcess->isStoringAllData)
	{
		return;
	}
	
	[self prepareDocumentTask];
	
	[searchingProgressIndicator setMaxValue:[currentProcess numberOfRegions]];
	
	updateSearchUserInterfaceTimer =
		[[ZGTimer alloc]
		 initWithTimeInterval:USER_INTERFACE_UPDATE_TIME_INTERVAL
		 target:self
		 selector:@selector(updateMemoryStoreUserInterface:)];
	
	
	[generalStatusTextField setStringValue:@"Storing All Values..."];
	
	dispatch_block_t searchForDataCompleteBlock = ^
	{
		[updateSearchUserInterfaceTimer invalidate];
		[updateSearchUserInterfaceTimer release];
		updateSearchUserInterfaceTimer = nil;
		
		if (!currentProcess->isStoringAllData)
		{
			[generalStatusTextField setStringValue:@"Canceled Memory Store"];
		}
		else
		{
			currentProcess->isStoringAllData = NO;
			
			if (searchData->savedData)
			{
				ZGFreeData(searchData->savedData);
				[searchData->savedData release];
			}
			
			searchData->savedData = searchData->tempSavedData;
			searchData->tempSavedData = nil;
			
			[generalStatusTextField setStringValue:@"Finished Memory Store"];
		}
		[searchingProgressIndicator setDoubleValue:0.0];
		[self resumeDocument];
	};
	
	dispatch_block_t searchForDataBlock = ^
	{
		searchData->tempSavedData = ZGGetAllData(currentProcess, [scanUnwritableValuesCheckBox state]);
		if (searchData->tempSavedData)
		{
			[searchData->tempSavedData retain];
		}
		
		dispatch_async(dispatch_get_main_queue(), searchForDataCompleteBlock);
	};
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), searchForDataBlock);
}

#pragma mark Menu item validation

- (BOOL)validateMenuItem:(NSMenuItem *)theMenuItem
{
	if ([theMenuItem action] == @selector(clearSearchValues:))
	{
		if (![clearButton isEnabled])
		{
			return NO;
		}
	}
	
	else if ([theMenuItem action] == @selector(removeSelectedSearchValues:))
	{
		if ([[tableController watchVariablesTableView] selectedRow] < 0 || [watchWindow firstResponder] != [tableController watchVariablesTableView])
		{
			return NO;
		}
	}
	
	else if ([theMenuItem action] == @selector(freezeVariables:))
	{
		if ([watchVariablesArray count] > 0)
		{
			// All the variables selected need to either be all unfrozen or all frozen
			BOOL isFrozen = ((ZGVariable *)[watchVariablesArray objectAtIndex:[[tableController watchVariablesTableView] selectedRow]])->isFrozen;
			BOOL isInconsistent = NO;
			
			NSUInteger currentIndex = [[[tableController watchVariablesTableView] selectedRowIndexes] firstIndex];
			while (currentIndex != NSNotFound)
			{
				ZGVariable *variable = [watchVariablesArray objectAtIndex:currentIndex];
				// we should also check if the variable has an existing value at all
				if (variable && (variable->isFrozen != isFrozen || !variable->value))
				{
					isInconsistent = YES;
					break;
				}
				currentIndex = [[[tableController watchVariablesTableView] selectedRowIndexes] indexGreaterThanIndex:currentIndex];
			}
			
			NSString *title;
			
			if (isFrozen)
			{
				title = @"Unfreeze Variable";
			}
			else
			{
				title = @"Freeze Variable";
			}
			
			if ([[[tableController watchVariablesTableView] selectedRowIndexes] count] > 1)
			{
				title = [title stringByAppendingString:@"s"];
			}
			
			[theMenuItem setTitle:title];
			
			if (isInconsistent || ![clearButton isEnabled])
			{
				return NO;
			}
		}
		else
		{
			[theMenuItem setTitle:@"Freeze Variables"];
			return NO;
		}
	}
	
	else if ([theMenuItem action] == @selector(addVariable:))
	{
		if (![self canStartTask])
		{
			return NO;
		}
	}
	
	else if ([theMenuItem action] == @selector(lockTarget:))
	{
		if (![self canStartTask])
		{
			[theMenuItem setTitle:@"Unlock Target"];
			return NO;
		}
		else
		{
			if ([clearButton isEnabled])
			{
				[theMenuItem setTitle:@"Unlock Target"];
			}
			else
			{
				[theMenuItem setTitle:@"Lock Target"];
			}
		}
	}
	
	else if ([theMenuItem action] == @selector(undo:))
	{
		if ([self canCancelTask])
		{
			return NO;
		}
	}
	
	else if ([theMenuItem action] == @selector(copy:))
	{
		if ([[[tableController watchVariablesTableView] selectedRowIndexes] count] == 0)
		{
			return NO;
		}
	}
	
	else if ([theMenuItem action] == @selector(paste:))
	{
		if ([self canCancelTask] || ![[NSPasteboard generalPasteboard] dataForType:ZGVariablePboardType])
		{
			return NO;
		}
	}
	
	else if ([theMenuItem action] == @selector(pauseOrUnpauseProcess:))
	{
		if (!currentProcess || [currentProcess processID] == NON_EXISTENT_PID_NUMBER)
		{
			return NO;
		}
		
		if ([[ZGProcess frozenProcesses] containsObject:[NSNumber numberWithInt:[currentProcess processID]]])
		{
			[theMenuItem setTitle:@"Unpause Target"];
		}
		else
		{
			[theMenuItem setTitle:@"Pause Target"];
		}
	}
	
	else if ([theMenuItem action] == @selector(editVariablesValue:))
	{
		if ([[[tableController watchVariablesTableView] selectedRowIndexes] count] != 1)
		{
			[theMenuItem setTitle:@"Edit Variable Values…"];
		}
		else
		{
			[theMenuItem setTitle:@"Edit Variable Value…"];
		}
		
		if ([self canCancelTask] || [[tableController watchVariablesTableView] selectedRow] == -1 || [currentProcess processID] == NON_EXISTENT_PID_NUMBER)
		{
			return NO;
		}
	}
	
	else if ([theMenuItem action] == @selector(editVariablesAddress:))
	{
		if ([self canCancelTask] || [[tableController watchVariablesTableView] selectedRow] == -1 || [currentProcess processID] == NON_EXISTENT_PID_NUMBER)
		{
			return NO;
		}
	}
    
    else if ([theMenuItem action] == @selector(editVariablesSize:))
    {
		if ([[[tableController watchVariablesTableView] selectedRowIndexes] count] != 1)
		{
			[theMenuItem setTitle:@"Edit Variable Sizes…"];
		}
		else
		{
			[theMenuItem setTitle:@"Edit Variable Size…"];
		}
		
		if ([self canCancelTask] || [[tableController watchVariablesTableView] selectedRow] == -1 || [currentProcess processID] == NON_EXISTENT_PID_NUMBER)
		{
			return NO;
		}
		
		// All selected variables must be Byte Array's
		NSArray *selectedVariables = [watchVariablesArray objectsAtIndexes:[[tableController watchVariablesTableView] selectedRowIndexes]];
		for (ZGVariable *variable in selectedVariables)
		{
			if (variable->type != ZGByteArray)
			{
				return NO;
			}
		}
	}
	
	else if ([theMenuItem action] == @selector(memoryDumpRangeRequest:) || [theMenuItem action] == @selector(memoryDumpAllRequest:) || [theMenuItem action] == @selector(getInitialValues:) || [theMenuItem action] == @selector(changeMemoryProtection:))
	{
		if ([self canCancelTask] || [currentProcess processID] == NON_EXISTENT_PID_NUMBER)
		{
			return NO;
		}
	}
	else if ([theMenuItem action] == @selector(functionTypePopUpButtonRequest:))
	{
		if ([self isFunctionTypeStore:[theMenuItem tag]] && !(searchData->savedData))
		{
			return NO;
		}
	}
	
	return [super validateMenuItem:theMenuItem];
}

#pragma mark Variables Handling

- (IBAction)freezeVariables:(id)sender
{
	[variableController freezeVariables];
}

- (IBAction)copy:(id)sender
{
	[variableController copyVariables];
}

- (IBAction)paste:(id)sender
{
	[variableController pasteVariables];
}

- (IBAction)removeSelectedSearchValues:(id)sender
{
	[variableController removeSelectedSearchValues];
}

- (IBAction)addVariable:(id)sender
{
	[variableController addVariable:sender];
}

- (IBAction)editVariablesValue:(id)sender
{
	[variableController editVariablesValueRequest];
}

- (IBAction)editVariablesAddress:(id)sender
{
	[variableController editVariablesAddressRequest];
}

- (IBAction)editVariablesSize:(id)sender
{
	[variableController editVariablesSizeRequest];
}

#pragma mark Memory Dump Handling

- (IBAction)memoryDumpRangeRequest:(id)sender
{
	[memoryDumpController memoryDumpRangeRequest];
}

- (IBAction)memoryDumpAllRequest:(id)sender
{
	[memoryDumpController memoryDumpAllRequest];
}

#pragma mark Memory Protection Handling

- (IBAction)changeMemoryProtection:(id)sender
{
	[memoryProtectionController changeMemoryProtectionRequest];
}

#pragma mark Pausing and Unpausing Processes

- (IBAction)pauseOrUnpauseProcess:(id)sender
{
	[ZGProcess pauseOrUnpauseProcess:[currentProcess processID]];
}

@end
