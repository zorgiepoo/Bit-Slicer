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
#import "ZGSearchData.h"
#import "ZGComparisonFunctions.h"
#import "NSStringAdditions.h"
#import "ZGCalculator.h"
#import "ZGTimer.h"
#import "ZGUtilities.h"

@implementation ZGDocumentInfo

@synthesize loadedFromSave;
@synthesize selectedDatatypeTag;
@synthesize qualifierTag;
@synthesize functionTypeTag;
@synthesize scanUnwritableValues;
@synthesize ignoreDataAlignment;
@synthesize exactStringLength;
@synthesize ignoreStringCase;
@synthesize beginningAddress;
@synthesize endingAddress;
@synthesize searchValue;
@synthesize watchVariablesArray;

@end

@interface ZGDocument (Private)

- (void)setWatchVariablesArrayAndUpdateInterface:(NSArray *)newWatchVariablesArray;

- (void)updateFlags;

- (BOOL)isInNarrowSearchMode;

- (BOOL)doesFunctionTypeAllowSearchInput;
- (BOOL)isFunctionTypeStore;
- (BOOL)isFunctionTypeStore:(NSInteger)functionTypeTag;

- (void)selectDataTypeWithTag:(ZGVariableType)newTag recordUndo:(BOOL)recordUndo;

- (void)functionTypePopUpButtonRequest:(id)sender markChanges:(BOOL)shouldMarkChanges;

@end

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
@synthesize documentState;
@synthesize desiredProcessName;
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
		searchData = [[ZGSearchData alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	[[NSWorkspace sharedWorkspace]
	 removeObserver:self
	 forKeyPath:@"runningApplications"];
	
	[watchVariablesTimer invalidate];
	[watchVariablesTimer release];
	watchVariablesTimer = nil;
	
	[updateSearchUserInterfaceTimer invalidate];
	[updateSearchUserInterfaceTimer release];
	updateSearchUserInterfaceTimer = nil;
	
	[searchData release];
	searchData = nil;
	
	[self setWatchVariablesArray:nil];
	[self setCurrentProcess:nil];
	[self setDesiredProcessName:nil];
	
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
	if (![self desiredProcessName])
	{
		[self setDesiredProcessName:[[[ZGAppController sharedController] documentController] lastSelectedProcessName]];
	}
    
	// check if the document is being reverted
	if (watchWindow)
	{
		[generalStatusTextField setStringValue:@""];
	}
	
	// Add running applications to popup button
	for (NSRunningApplication *runningApplication in [[NSWorkspace sharedWorkspace] runningApplications])
	{
		[self addRunningApplicationToPopupButton:runningApplication];
	}
	
	[[NSWorkspace sharedWorkspace]
	 addObserver:self
	 forKeyPath:@"runningApplications"
	 options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew
	 context:NULL];
	
	currentSearchDataType = (ZGVariableType)[[dataTypesPopUpButton selectedItem] tag];

	if ([[self documentState] loadedFromSave])
	{
		[self setWatchVariablesArrayAndUpdateInterface:[[self documentState] watchVariablesArray]];
		[documentState setWatchVariablesArray:nil];
        
		[self
		 selectDataTypeWithTag:(ZGVariableType)[[self documentState] selectedDatatypeTag]
		 recordUndo:NO];
        
		[variableQualifierMatrix selectCellWithTag:[[self documentState] qualifierTag]];

		[scanUnwritableValuesCheckBox setState:[[self documentState] scanUnwritableValues]];
		[ignoreDataAlignmentCheckBox setState:[[self documentState] ignoreDataAlignment]];
		[includeNullTerminatorCheckBox setState:[[self documentState] exactStringLength]];
		[ignoreCaseCheckBox setState:[[self documentState] ignoreStringCase]];
		
		if ([[self documentState] beginningAddress])
		{
			[beginningAddressTextField setStringValue:[[self documentState] beginningAddress]];
			[[self documentState] setBeginningAddress:nil];
		}
		
		if ([[self documentState] endingAddress])
		{
			[endingAddressTextField setStringValue:[[self documentState] endingAddress]];
			[[self documentState] setEndingAddress:nil];
		}

		if (![self isFunctionTypeStore:[[self documentState] functionTypeTag]])
		{
			[functionPopUpButton selectItemWithTag:[[self documentState] functionTypeTag]];
			[self
			 functionTypePopUpButtonRequest:nil
			 markChanges:NO];
		}
        
		if ([[self documentState] searchValue])
		{
			[searchValueTextField setStringValue:[[self documentState] searchValue]];
			[[self documentState] setSearchValue:nil];
		}
		
		[self setDocumentState:nil];
	}
	else
	{
		[self setWatchVariablesArrayAndUpdateInterface:[NSArray array]];
		[searchData setLastEpsilonValue:[NSString stringWithFormat:@"%.1f", DEFAULT_FLOATING_POINT_EPSILON]];
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
	 encodeObject:[searchData lastEpsilonValue]
	 forKey:ZGEpsilonKey];
    
	[keyedArchiver
	 encodeObject:[searchData lastAboveRangeValue]
	 forKey:ZGAboveValueKey];
    
	[keyedArchiver
	 encodeObject:[searchData lastBelowRangeValue]
	 forKey:ZGBelowValueKey];
    
	[keyedArchiver
	 encodeObject:[searchValueTextField stringValue]
	 forKey:ZGSearchStringValueKey];
    
	[self setDesiredProcessName:[currentProcess name]];
	
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
	
	[self setDocumentState:[[[ZGDocumentInfo alloc] init] autorelease]];
	
	[[self documentState] setWatchVariablesArray:[keyedUnarchiver decodeObjectForKey:ZGWatchVariablesArrayKey]];
	[self setDesiredProcessName:[keyedUnarchiver decodeObjectForKey:ZGProcessNameKey]];
	
	[[self documentState] setLoadedFromSave:YES];
	[[self documentState] setSelectedDatatypeTag:(NSInteger)[keyedUnarchiver decodeInt32ForKey:ZGSelectedDataTypeTag]];
	[[self documentState] setQualifierTag:(NSInteger)[keyedUnarchiver decodeInt32ForKey:ZGQualifierTagKey]];
	[[self documentState] setFunctionTypeTag:(NSInteger)[keyedUnarchiver decodeInt32ForKey:ZGFunctionTypeTagKey]];
	[[self documentState] setScanUnwritableValues:[keyedUnarchiver decodeBoolForKey:ZGScanUnwritableValuesKey]];
	[[self documentState] setIgnoreDataAlignment:[keyedUnarchiver decodeBoolForKey:ZGIgnoreDataAlignmentKey]];
	[[self documentState] setExactStringLength:[keyedUnarchiver decodeBoolForKey:ZGExactStringLengthKey]];
	[[self documentState] setIgnoreStringCase:[keyedUnarchiver decodeBoolForKey:ZGIgnoreStringCaseKey]];
	[[self documentState] setBeginningAddress:[keyedUnarchiver decodeObjectForKey:ZGBeginningAddressKey]];
	[[self documentState] setEndingAddress:[keyedUnarchiver decodeObjectForKey:ZGEndingAddressKey]];
	
	[[self documentState] setSearchValue:[keyedUnarchiver decodeObjectForKey:ZGSearchStringValueKey]];
	
	[searchData setLastEpsilonValue:[keyedUnarchiver decodeObjectForKey:ZGEpsilonKey]];
	[searchData setLastAboveRangeValue:[keyedUnarchiver decodeObjectForKey:ZGAboveValueKey]];
	[searchData setLastBelowRangeValue:[keyedUnarchiver decodeObjectForKey:ZGBelowValueKey]];
	
	[keyedUnarchiver release];
	
	BOOL success = [[self documentState] watchVariablesArray] != nil && [self desiredProcessName] != nil;
	
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
	
	[self setCurrentProcess:[[runningApplicationsPopUpButton selectedItem] representedObject]];
	
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
	
	if (sender && ![[self desiredProcessName] isEqualToString:[currentProcess name]])
	{
		[self setDesiredProcessName:[currentProcess name]];
		[self markDocumentChange];
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
	
	// Trash all other menu items if they're dead
	NSMutableArray *itemsToRemove = [[NSMutableArray alloc] init];
	for (NSMenuItem *menuItem in [runningApplicationsPopUpButton itemArray])
	{
		if (menuItem != [runningApplicationsPopUpButton selectedItem] &&
			([[menuItem representedObject] processID] == NON_EXISTENT_PID_NUMBER ||
			 ![[[NSWorkspace sharedWorkspace] runningApplications] containsObject:[NSRunningApplication runningApplicationWithProcessIdentifier:[[menuItem representedObject] processID]]]))
		{
			[itemsToRemove addObject:menuItem];
		}
	}
	
	for (id item in itemsToRemove)
	{
		[runningApplicationsPopUpButton removeItemAtIndex:[runningApplicationsPopUpButton indexOfItem:item]];
	}
	
	[itemsToRemove release];
	
	// If we're switching to a process, search button should be enabled
	[searchButton setEnabled:YES];
}

- (void)removeRunningApplicationFromPopupButton:(NSRunningApplication *)oldRunningApplication
{
	// Great, a process terminated, but we don't know which one
	if ([oldRunningApplication processIdentifier] == -1)
	{
		NSLog(@"Yes, process ID was -1");
		NSMutableArray *menuItemsToRemove = [[NSMutableArray alloc] init];
		for (NSMenuItem *menuItem in [runningApplicationsPopUpButton itemArray])
		{
			NSRunningApplication *runningApplication = [NSRunningApplication runningApplicationWithProcessIdentifier:[[menuItem representedObject] processID]];
			if ([runningApplication processIdentifier] == -1 || ![[[NSWorkspace sharedWorkspace] runningApplications] containsObject:runningApplication])
			{
				if ([[menuItem representedObject] processID] == [currentProcess processID])
				{
					oldRunningApplication = nil;
				}
				else
				{
					[menuItemsToRemove addObject:menuItem];
				}
			}
		}
		
		for (id menuItem in menuItemsToRemove)
		{
			[runningApplicationsPopUpButton removeItemAtIndex:[runningApplicationsPopUpButton indexOfItem:menuItem]];
		}
		
		[menuItemsToRemove release];
	}
	
	// Just to be sure
	if ([oldRunningApplication processIdentifier] != [[NSRunningApplication currentApplication] processIdentifier])
	{
		// oldRunningApplication == nil, means current process terminated (was in middle of a search)
		if ([currentProcess processID] == [oldRunningApplication processIdentifier] || !oldRunningApplication)
		{
			// Don't remove the item, just indicate it's terminated
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
		else if ([oldRunningApplication processIdentifier] != -1)
		{
			// Find the menu item, and remove it
			NSMenuItem *itemToRemove = nil;
			for (NSMenuItem *item in [runningApplicationsPopUpButton itemArray])
			{
				if ([[item representedObject] processID] == [oldRunningApplication processIdentifier])
				{
					itemToRemove = item;
					break;
				}
			}
			
			if (itemToRemove)
			{
				[runningApplicationsPopUpButton removeItemAtIndex:[runningApplicationsPopUpButton indexOfItem:itemToRemove]];
			}
		}
	}
}

- (void)addRunningApplicationToPopupButton:(NSRunningApplication *)newRunningApplication
{
	// Don't add ourselves
	if ([newRunningApplication processIdentifier] != [[NSRunningApplication currentApplication] processIdentifier])
	{
		// Check if a dead application can be 'revived'
		for (NSMenuItem *menuItem in [runningApplicationsPopUpButton itemArray])
		{
			ZGProcess *process = [menuItem representedObject];
			if (process == currentProcess &&
				[currentProcess processID] == NON_EXISTENT_PID_NUMBER &&
				[[currentProcess name] isEqualToString:[newRunningApplication localizedName]])
			{
				[currentProcess setProcessID:[newRunningApplication processIdentifier]];
				[menuItem setTitle:[NSString stringWithFormat:@"%@ (%d)", [currentProcess name], [currentProcess processID]]];
				[self runningApplicationsPopUpButtonRequest:nil];
				[searchButton setEnabled:YES];
				return;
			}
		}
		
		// Otherwise add the new application
		NSMenuItem *menuItem = [[NSMenuItem alloc] init];
		[menuItem setTitle:[NSString stringWithFormat:@"%@ (%d)", [newRunningApplication localizedName], [newRunningApplication processIdentifier]]];
		NSImage *iconImage = [newRunningApplication icon];
		[iconImage setSize:NSMakeSize(16, 16)];
		[menuItem setImage:iconImage];
		
		ZGProcess *representedProcess =
		[[ZGProcess alloc]
		 initWithName:[newRunningApplication localizedName]
		 processID:[newRunningApplication processIdentifier]
		 set64Bit:([newRunningApplication executableArchitecture] == NSBundleExecutableArchitectureX86_64)];
		
		[menuItem setRepresentedObject:representedProcess];
		[representedProcess release];
		
		[[runningApplicationsPopUpButton menu] addItem:menuItem];
		
		// If we found desired process name, select it
		if (![[currentProcess name] isEqualToString:[self desiredProcessName]] &&
			[[self desiredProcessName] isEqualToString:[newRunningApplication localizedName]])
		{
			[runningApplicationsPopUpButton selectItem:menuItem];
			[self runningApplicationsPopUpButtonRequest:nil];
		}
		
		[menuItem release];
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (object == [NSWorkspace sharedWorkspace])
	{
		NSArray *newRunningApplications = [change objectForKey:NSKeyValueChangeNewKey];
		NSArray *oldRunningApplications = [change objectForKey:NSKeyValueChangeOldKey];
		
		if (newRunningApplications)
		{
			for (NSRunningApplication *runningApplication in newRunningApplications)
			{
				[self addRunningApplicationToPopupButton:runningApplication];
			}
		}
		
		if (oldRunningApplications)
		{
			for (NSRunningApplication *runningApplication in oldRunningApplications)
			{
				[self removeRunningApplicationFromPopupButton:runningApplication];
			}
		}
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
	
	[runningApplicationsPopUpButton setEnabled:YES];
	
	[watchWindow makeFirstResponder:searchValueTextField];
	
	if ([currentProcess processID] == NON_EXISTENT_PID_NUMBER)
	{
		[self removeRunningApplicationFromPopupButton:nil];
	}
}

- (void)updateClearButton
{
	[clearButton setEnabled:[[self watchVariablesArray] count] > 0];
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
		
		if ([searchData lastBelowRangeValue])
		{
			[flagsTextField setStringValue:[searchData lastBelowRangeValue]];
		}
		else
		{
			[flagsTextField setStringValue:@""];
		}
	}
	else if (functionType == ZGLessThan || functionType == ZGLessThanStored)
	{
		[flagsLabel setStringValue:@"Above:"];
		
		if ([searchData lastAboveRangeValue])
		{
			[flagsTextField setStringValue:[searchData lastAboveRangeValue]];
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
			if ([searchData lastEpsilonValue])
			{
				[flagsTextField setStringValue:[searchData lastEpsilonValue]];
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
	
	[self updateClearButton];
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
		// This doesn't matter if the search is comparing stored values or if it's a regular function type
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
	
	if ((dataType == ZGUTF8String || dataType == ZGUTF16String || dataType == ZGByteArray) && [searchData shouldCompareStoredValues])
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
	
	if ([currentProcess processID] != NON_EXISTENT_PID_NUMBER)
	{
		[searchButton setEnabled:YES];
	}
	
	[self setWatchVariablesArray:[NSArray array]];
	[[tableController watchVariablesTableView] reloadData];
	
	if ([self doesFunctionTypeAllowSearchInput])
	{
		[searchValueTextField setEnabled:YES];
	}
	
	[clearButton setEnabled:NO];
	
	if ([currentProcess processID] != NON_EXISTENT_PID_NUMBER)
	{
		[generalStatusTextField setStringValue:@"Cleared search."];
	}
	
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
		[searchData setEpsilon:DEFAULT_FLOATING_POINT_EPSILON];
		[searchData setRangeValue:NULL];
		
		[searchData setShouldIgnoreStringCase:[ignoreCaseCheckBox state]];
		[searchData setShouldIncludeNullTerminator:[includeNullTerminatorCheckBox state]];
		[searchData setShouldCompareStoredValues:[self isFunctionTypeStore]];
		
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
		searchValue = valueFromString(currentProcess, evaluatedSearchExpression, dataType, &dataSize);
		
		// We want to read the null terminator in this case... even though we normally don't store the terminator
		// internally for UTF-16 strings. Lame hack, I know.
		if ([searchData shouldIncludeNullTerminator] && dataType == ZGUTF16String)
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
						[searchData setRangeValue:valueFromString(currentProcess, flagsExpression, dataType, &rangeDataSize)];
					}
					else
					{
						[searchData setRangeValue:NULL];
					}
					
					if (functionType == ZGGreaterThan || functionType == ZGGreaterThanStored)
					{
						[searchData setLastBelowRangeValue:[flagsTextField stringValue]];
					}
					else if (functionType == ZGLessThan || functionType == ZGLessThanStored)
					{
						[searchData setLastAboveRangeValue:[flagsTextField stringValue]];
					}
				}
				else
				{
					if (!flagsFieldIsBlank)
					{
						// Clearly an epsilon flag
						ZGMemorySize epsilonDataSize;
						void *epsilon = valueFromString(currentProcess, flagsExpression, ZGDouble, &epsilonDataSize);
						if (epsilon)
						{
							[searchData setEpsilon:*((double *)epsilon)];
							free(epsilon);
						}
					}
					else
					{
						[searchData setEpsilon:DEFAULT_FLOATING_POINT_EPSILON];
					}
					
					[searchData setLastEpsilonValue:[flagsTextField stringValue]];
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
			
			[searchData setBeginAddress:memoryAddressFromExpression(calculatedBeginAddress)];
		}
		else
		{
			[searchData setBeginAddress:0x0];
		}
		
		if (![[endingAddressTextField stringValue] isEqualToString:@""])
		{
			if ([self testSearchComponent:calculatedEndAddress])
			{
				NSRunAlertPanel(@"Invalid Input", @"The expression in the ending address field is not valid.", nil, nil, nil, nil);
				return;
			}
			
			[searchData setEndAddress:memoryAddressFromExpression(calculatedEndAddress)];
		}
		else
		{
			[searchData setEndAddress:MAX_MEMORY_ADDRESS];
		}
		
		if ([searchData beginAddress] >= [searchData endAddress])
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
		
		static BOOL (*compareFunctions[10])(ZGSearchData *, const void *, const void *, ZGVariableType, ZGMemorySize) =
		{
			equalFunction, notEqualFunction, greaterThanFunction, lessThanFunction, equalFunction, notEqualFunction, greaterThanFunction, lessThanFunction, equalPlusFunction, notEqualPlusFunction
		};
		
		BOOL (*compareFunction)(ZGSearchData *, const void *, const void *, ZGVariableType, ZGMemorySize) = compareFunctions[functionType];
        
		if (dataType == ZGByteArray)
		{
			[searchData setByteArrayFlags:allocateFlagsForByteArrayWildcards(evaluatedSearchExpression)];
		}
		
		if (functionType == ZGEqualsStoredPlus || functionType == ZGNotEqualsStoredPlus)
		{
			[searchData setCompareOffset:searchValue];
		}
		
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
			
			search_for_data_t searchForDataCallback = ^(void *variableData, void *compareData, ZGMemoryAddress address, ZGMemorySize currentRegionNumber)
			{
				if (compareFunction(searchData, variableData, (compareData != NULL) ? compareData : searchValue, dataType, dataSize))
				{
					ZGVariable *newVariable =
						[[ZGVariable alloc]
						 initWithValue:variableData
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
				
				if ([searchData shouldCompareStoredValues])
				{
					ZGSearchForSavedData([currentProcess processTask], dataAlignment, dataSize, searchData, searchForDataCallback);
				}
				else
				{
					[searchData setShouldScanUnwritableValues:([scanUnwritableValuesCheckBox state] == NSOnState)];
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
							(searchData->beginAddress <= variable->address) &&
							(searchData->endAddress >= variable->address + dataSize))
						{
							ZGMemorySize outputSize = dataSize;
							void *variableValue = NULL;
							if (ZGReadBytes(processTask, variable->address, &variableValue, &outputSize))
							{
								void *compareValue = searchData->shouldCompareStoredValues ? ZGSavedValue(variable->address, searchData, dataSize) : searchValue;
								
								if (compareValue && compareFunction(searchData, variableValue, compareValue, dataType, dataSize))
								{
									[temporaryVariablesArray addObject:variable];
									currentProcess->numberOfVariablesFound++;
								}
								
								ZGFreeBytes(processTask, variableValue, outputSize);
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
			
			[searchData setSavedData:[searchData tempSavedData]];
			[searchData setTempSavedData:nil];
			
			[generalStatusTextField setStringValue:@"Finished Memory Store"];
		}
		[searchingProgressIndicator setDoubleValue:0.0];
		[self resumeDocument];
	};
	
	dispatch_block_t searchForDataBlock = ^
	{
		[searchData setTempSavedData:ZGGetAllData(currentProcess, [scanUnwritableValuesCheckBox state])];
		
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
		if ([self isFunctionTypeStore:[theMenuItem tag]] && !([searchData savedData]))
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
