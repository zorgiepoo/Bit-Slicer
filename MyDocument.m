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

#import "MyDocument.h"
#import "ZGProcess.h"
#import "ZGVirtualMemory.h"
#import "ZGVariable.h"
#import "ZGDocumentController.h"
#import "ZGComparisonFunctions.h"
#import "NSStringAdditions.h"
#import "ZGCalculator.h"
#import "ZGTimer.h"

// for chmod
#import <sys/types.h>
#import <sys/stat.h>

@interface MyDocument (Private)

- (void)updateRunningApplicationProcesses;

- (void)addVariables:(NSArray *)variables
		atRowIndexes:(NSIndexSet *)rowIndexes;

- (void)removeVariablesAtRowIndexes:(NSIndexSet *)rowIndexes;

- (void)lockTarget;
- (void)unlockTarget;

- (void)updateFlags;

- (BOOL)isInNarrowSearchMode;

@end

#define SIGNED_BUTTON_CELL_TAG				0
#define VALUE_TABLE_COLUMN_INDEX			1
#define NON_EXISTENT_PID_NUMBER				-1

#define DEFAULT_FLOATING_POINT_EPSILON		0.1

#define ZGWatchVariablesArrayKey			@"ZGWatchVariablesArrayKey"
#define ZGProcessNameKey					@"ZGProcessNameKey"

#define ZGVariableReorderType				@"ZGVariableReorderType"

#define MAX_TABLE_VIEW_ITEMS				((unsigned int)1000)

#define USER_INTERFACE_UPDATE_TIME_INTERVAL	0.33
#define WATCH_VARIABLES_UPDATE_TIME_INTERVAL 0.1
#define CHECK_CHILD_PROCESSES_TIME_INTERVAL	2.0

#define ZG_EXPAND_OPTIONS @"ZG_EXPAND_OPTIONS"

@implementation MyDocument

#pragma mark Document stuff

+ (void)initialize
{
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:NO]
																						forKey:ZG_EXPAND_OPTIONS]];
}

- (id)init
{
    self = [super init];
    if (self)
	{
		[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
															   selector:@selector(anotherApplicationLaunched:)
																   name:NSWorkspaceWillLaunchApplicationNotification
																 object:nil];
		[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
															   selector:@selector(anotherApplicationTerminated:)
																   name:NSWorkspaceDidTerminateApplicationNotification
																 object:nil];
		
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
	[[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
	
	[checkChildProcessesTimer invalidate];
	[checkChildProcessesTimer release];
	checkChildProcessesTimer = nil;
	
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
	
	[runningApplications release];
	runningApplications = nil;
	
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

- (void)windowControllerDidLoadNib:(NSWindowController *) aController
{
    [super windowControllerDidLoadNib:aController];
	
	[watchVariablesTableView setDelegate:self];
	
	if (![[NSUserDefaults standardUserDefaults] boolForKey:ZG_EXPAND_OPTIONS])
	{
		[self optionsDisclosureButton:nil];
	}
	
	if (!desiredProcessName)
	{
		desiredProcessName = [[ZGDocumentController lastSelectedProcessName] copy];
	}
	
	[self updateRunningApplicationProcesses];
	
	checkChildProcessesTimer = [[ZGTimer alloc] initWithTimeInterval:CHECK_CHILD_PROCESSES_TIME_INTERVAL
															  target:self
															selector:@selector(checkChildProcesses:)];
	
	currentSearchDataType = [[dataTypesPopUpButton selectedItem] tag];
	
	watchVariablesTimer = [[ZGTimer alloc] initWithTimeInterval:WATCH_VARIABLES_UPDATE_TIME_INTERVAL
														 target:self
													   selector:@selector(updateWatchVariablesTable:)];
	
	searchArguments.lastEpsilonValue = [[NSString stringWithFormat:@"%.1f", DEFAULT_FLOATING_POINT_EPSILON] retain];
	[flagsLabel setTextColor:[NSColor disabledControlTextColor]];
	
	[watchVariablesTableView registerForDraggedTypes:[NSArray arrayWithObject:ZGVariableReorderType]];
}

- (BOOL)writeToURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{
	BOOL result = [super writeToURL:absoluteURL ofType:typeName error:outError];
	
	if (result)
	{
		// Change the permissions on the document file to something more sane
		if (chmod([[absoluteURL path] UTF8String], 0777) == -1)
		{
			NSLog(@"chmod failed: %s", strerror(errno));
		}
	}

	return result;
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
{	
	if (outError != NULL)
	{
		*outError = [NSError errorWithDomain:NSOSStatusErrorDomain
										code:unimpErr
									userInfo:nil];
	}
	
	NSMutableData *mutableData = [[NSMutableData alloc] init];
	NSKeyedArchiver *keyedArchiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:mutableData];
	
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
	
	[keyedArchiver encodeObject:watchVariablesArrayToSave
						 forKey:ZGWatchVariablesArrayKey];
	
	[keyedArchiver encodeObject:[currentProcess name]
						 forKey:ZGProcessNameKey];
	
	[desiredProcessName release];
	desiredProcessName = [[currentProcess name] copy];
	
	[keyedArchiver finishEncoding];
	[keyedArchiver release];
	
	return [mutableData autorelease];
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError
{
    if ( outError != NULL )
	{
		*outError = [NSError errorWithDomain:NSOSStatusErrorDomain
										code:unimpErr
									userInfo:NULL];
	}
	
	NSKeyedUnarchiver *keyedUnarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
	
	watchVariablesArray = [[keyedUnarchiver decodeObjectForKey:ZGWatchVariablesArrayKey] retain];
	desiredProcessName = [[keyedUnarchiver decodeObjectForKey:ZGProcessNameKey] retain];
	
	[keyedUnarchiver release];
	
    return watchVariablesArray != nil && desiredProcessName != nil;
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
		
		[watchVariablesTableView reloadData];
	}
	
	// keep track of the process the user targeted
	[ZGDocumentController setLastSelectedProcessName:[currentProcess name]];
	
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
			NSAttributedString *errorMessage = [[NSAttributedString alloc] initWithString:@"Process Load Error!"
																			   attributes:[NSDictionary dictionaryWithObject:[NSColor redColor]
																													  forKey:NSForegroundColorAttributeName]];
			
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
			[menuItem setTitle:[NSString stringWithFormat:@"%@ (%i)", [runningApplication localizedName], [runningApplication processIdentifier]]];
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

- (void)anApplicationLaunched:(NSRunningApplication *)runningApplication
{
	if ([currentProcess processID] == NON_EXISTENT_PID_NUMBER && [[runningApplication localizedName] isEqualToString:[currentProcess name]])
	{
		[currentProcess	setProcessID:[runningApplication processIdentifier]];
		[[runningApplicationsPopUpButton selectedItem] setTitle:[NSString stringWithFormat:@"%@ (%i)", [currentProcess name], [currentProcess processID]]];
		
		// need to grant access
		[self runningApplicationsPopUpButtonRequest:nil];
		
		[searchButton setEnabled:YES];
	}
	else if ([currentProcess processID] != NON_EXISTENT_PID_NUMBER)
	{
		[self updateRunningApplicationProcesses];
	}
}

- (void)anotherApplicationLaunched:(NSNotification *)notification
{
	[self anApplicationLaunched:[[notification userInfo] objectForKey:@"NSWorkspaceApplicationKey"]];
}

- (void)anApplicationTerminated:(NSRunningApplication *)runningApplication
{
	[ZGProcess removeFrozenProcess:[runningApplication processIdentifier]];
	
	if (([clearButton isEnabled] || [[searchButton title] isEqualToString:@"Cancel"]) && [[runningApplication localizedName] isEqualToString:[currentProcess name]])
	{
		NSAttributedString *status = [[NSAttributedString alloc] initWithString:@"Process terminated."
																	 attributes:[NSDictionary dictionaryWithObject:[NSColor redColor]
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

- (void)anotherApplicationTerminated:(NSNotification *)notification
{
	[self anApplicationTerminated:[[notification userInfo] objectForKey:@"NSWorkspaceApplicationKey"]];
}

- (void)checkChildProcesses:(NSTimer *)timer
{
	if (![[self windowForSheet] isVisible])
	{
		return;
	}
	
	// So basically, NSWorkspace's methods for notifying us of processes terminating and launching,
	// don't notify us of processes that main applications spawn
	// So we check every few seconds if any new child-spawned application spawns
	// In my experience, an example of this is with Chrome processes
	
	NSArray *newRunningApplications = [[NSWorkspace sharedWorkspace] runningApplications];
	
	if ([runningApplications count] > 0)
	{
		for (NSRunningApplication *runningApplication in newRunningApplications)
		{
			// Check if a process spawned
			if ([runningApplication activationPolicy] != NSApplicationActivationPolicyRegular && ![runningApplications containsObject:runningApplication])
			{
				[self anApplicationLaunched:runningApplication];
			}
		}
	}
	
	for (NSRunningApplication *runningApplication in runningApplications)
	{
		// Check if a process terminated
		if ([runningApplication activationPolicy] != NSApplicationActivationPolicyRegular && ![newRunningApplications containsObject:runningApplication])
		{
			[self anApplicationTerminated:runningApplication];
		}
	}
	
	[runningApplications release];
	runningApplications = [newRunningApplications retain];
}

#pragma mark Updating user interface

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
	[compareInitialValuesCheckBox setEnabled:NO];
	[scanReadOnlyValuesCheckBox setEnabled:NO];
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
	
	if (searchData->savedData)
	{
		[compareInitialValuesCheckBox setEnabled:YES];
	}
	
	if ([compareInitialValuesCheckBox state] == NSOffState)
	{
		[searchValueTextField setEnabled:YES];
	}
	[searchButton setEnabled:YES];
	[searchButton setTitle:@"Search"];
	[searchButton setKeyEquivalent:@"\r"];
	
	[self updateFlags];
	
	[variableQualifierMatrix setEnabled:YES];
	[functionPopUpButton setEnabled:YES];
	
	[scanReadOnlyValuesCheckBox setEnabled:YES];
	
	ZGVariableType dataType = [[dataTypesPopUpButton selectedItem] tag];
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

- (void)updateMemoryDumpOrStoreUserInterface:(NSTimer *)timer
{
	if ([[self windowForSheet] isVisible])
	{
		if ([[searchButton title] isEqualToString:@"Search"])
		{
			[self prepareDocumentTask];
		}
		
		[searchingProgressIndicator setDoubleValue:currentProcess->searchProgress];
	}
}

- (void)updateSearchUserInterface:(NSTimer *)timer
{
	if ([[self windowForSheet] isVisible])
	{
		if (!ZGSearchIsCancelling(searchData))
		{
			[searchingProgressIndicator setDoubleValue:currentProcess->searchProgress];
			[self updateNumberOfVariablesFoundDisplay];
		}
		else
		{
			[generalStatusTextField setStringValue:@"Cancelling search..."];
		}
	}
}

- (void)updateWatchVariablesTable:(NSTimer *)timer
{
	if (![[self windowForSheet] isVisible])
	{
		return;
	}
	
	// First, update all the variable's addresses that are pointers
	// We don't want to update this when the user is editing something in the table
	if ([currentProcess processID] != NON_EXISTENT_PID_NUMBER && [watchVariablesTableView editedRow] == -1)
	{
		[watchVariablesArray enumerateObjectsUsingBlock:^(id object, NSUInteger index, BOOL *stop)
		 {
			 ZGVariable *variable = object;
			 if (variable->isPointer)
			 {
				 NSString *newAddress = [ZGCalculator evaluateAddress:[NSMutableString stringWithString:[variable addressFormula]]
															  process:currentProcess];
				 
				 if (variable->address != [newAddress unsignedLongLongValue])
				 {
					 [variable setAddressStringValue:newAddress];
					 [watchVariablesTableView reloadData];
				 }
			 }
		 }];
	}
	
	// Then check that the process is locked and that the process is alive
	if ([clearButton isEnabled] && [currentProcess processID] != NON_EXISTENT_PID_NUMBER)
	{
		// Freeze all variables that need be frozen!
		[watchVariablesArray enumerateObjectsUsingBlock:^(id object, NSUInteger index, BOOL *stop)
		 {
			 ZGVariable *variable = object;
			 if (variable->isFrozen && variable->freezeValue)
			 {
				 if (variable->size)
				 {
					 ZGWriteBytes([currentProcess processID], variable->address, variable->freezeValue, variable->size);
				 }
				 
				 if (variable->type == ZGUTF16String)
				 {
					 unichar terminatorValue = 0;
					 ZGWriteBytes([currentProcess processID], variable->address + variable->size, &terminatorValue, sizeof(unichar));
				 }
			 }
		 }];
	}
	
	// if any variables are changing, that means that we'll have to reload the table, and that'd be very bad
	// if the user is in the process of editing a variable's value, so don't do it then
	if ([currentProcess processID] != NON_EXISTENT_PID_NUMBER && [watchVariablesTableView editedRow] == -1)
	{
		// Read all the variables and update them in the table view if needed
		NSRange visibleRowsRange = [watchVariablesTableView rowsInRect:[watchVariablesTableView visibleRect]];
		
		[[watchVariablesArray subarrayWithRange:visibleRowsRange] enumerateObjectsUsingBlock:^(id object, NSUInteger index, BOOL *stop)
		 {
			 ZGVariable *variable = object;
			 
			 if (variable->type == ZGUTF8String || variable->type == ZGUTF16String)
			 {
				 variable->size = ZGGetStringSize([currentProcess processID], variable->address, variable->type);
			 }
			 
			 if (variable->size)
			 {
				 void *value = malloc((size_t)variable->size);
				 
				 if (ZGReadBytes([currentProcess processID], variable->address, value, variable->size))
				 {
					 NSString *oldStringValue = [variable stringValue];
					 [variable setVariableValue:value];
					 if (![[variable stringValue] isEqualToString:oldStringValue])
					 {
						 [watchVariablesTableView reloadData];
					 }
				 }
				 else if (variable->value)
				 {
					 [variable setVariableValue:NULL];
					 [watchVariablesTableView reloadData];
				 }
				 
				 free(value);
			 }
			 else if (variable->lastUpdatedSize)
			 {
				 [variable setVariableValue:NULL];
				 [watchVariablesTableView reloadData];
			 }
			 
			 variable->lastUpdatedSize = variable->size;
		 }];
	}
}

- (IBAction)qualifierMatrixButtonRequest:(id)sender
{
	ZGVariableQualifier newQualifier = [[variableQualifierMatrix selectedCell] tag];
	
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
	
	[watchVariablesTableView reloadData];
}

- (IBAction)compareInitialValuesCheckBoxRequest:(id)sender
{
	if ([compareInitialValuesCheckBox state] == NSOffState)
	{
		[searchValueTextField setEnabled:YES];
		[searchValueLabel setTextColor:[NSColor controlTextColor]];
		[watchWindow makeFirstResponder:searchValueTextField];
	}
	else
	{
		[searchValueTextField setEnabled:NO];
		[searchValueLabel setTextColor:[NSColor disabledControlTextColor]];
	}
}

- (void)updateFlagsRangeTextField
{
	ZGFunctionType functionType = [[functionPopUpButton selectedItem] tag];
	
	if (functionType == ZGGreaterThan)
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
	else if (functionType == ZGLessThan)
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
	ZGVariableType dataType = [[dataTypesPopUpButton selectedItem] tag];
	ZGFunctionType functionType = [[functionPopUpButton selectedItem] tag];
	
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
		
		if (functionType == ZGEquals || functionType == ZGNotEquals)
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
		if (functionType == ZGEquals || functionType == ZGNotEquals)
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
				
				[watchWindow setFrame:windowFrame
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
				
				[watchWindow setFrame:windowFrame
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
	
	[[NSUserDefaults standardUserDefaults] setBool:[optionsDisclosureButton state]
											forKey:ZG_EXPAND_OPTIONS];
}

- (void)selectDataTypeWithTag:(ZGVariableType)newTag
{
	if ([[self undoManager] isUndoing] || [[self undoManager] isRedoing])
	{
		[dataTypesPopUpButton selectItemWithTag:newTag];
	}
	
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
	
	[self updateFlags];

	[[self undoManager] setActionName:@"Data Type Change"];
	[[[self undoManager] prepareWithInvocationTarget:self] selectDataTypeWithTag:currentSearchDataType];
	
	currentSearchDataType = newTag;
}

- (IBAction)dataTypePopUpButtonRequest:(id)sender
{
	if ([[sender selectedItem] tag] != currentSearchDataType)
	{
		[self selectDataTypeWithTag:[[sender selectedItem] tag]];
	}
}

- (IBAction)functionTypePopUpButtonRequest:(id)sender
{
	[self updateFlags];
}

#pragma mark Adding & Removing Variables

- (void)removeVariablesAtRowIndexes:(NSIndexSet *)rowIndexes
{
	NSMutableArray *temporaryArray = [[NSMutableArray alloc] initWithCapacity:[watchVariablesArray count]];
	
	if ([[self undoManager] isUndoing])
	{
		[[self undoManager] setActionName:[NSString stringWithFormat:@"Add Variable%@", [rowIndexes count] > 1 ? @"s" : @""]];
	}
	else
	{
		[[self undoManager] setActionName:[NSString stringWithFormat:@"Delete Variable%@", [rowIndexes count] > 1 ? @"s" : @""]];
	}
	[[[self undoManager] prepareWithInvocationTarget:self] addVariables:[watchVariablesArray objectsAtIndexes:rowIndexes]
														   atRowIndexes:rowIndexes];
	
	[temporaryArray addObjectsFromArray:watchVariablesArray];
	[temporaryArray removeObjectsAtIndexes:rowIndexes];
	
	[watchVariablesArray release];
	watchVariablesArray = [[NSArray arrayWithArray:temporaryArray] retain];
	[temporaryArray release];
	[watchVariablesTableView reloadData];
}

- (void)addVariables:(NSArray *)variables
		atRowIndexes:(NSIndexSet *)rowIndexes
{
	NSMutableArray *temporaryArray = [[NSMutableArray alloc] initWithArray:watchVariablesArray];
	[temporaryArray insertObjects:variables
						atIndexes:rowIndexes];
	
	[watchVariablesArray release];
	watchVariablesArray = [[NSArray arrayWithArray:temporaryArray] retain];
	[temporaryArray release];
	[watchVariablesTableView reloadData];
	
	if ([[self undoManager] isUndoing])
	{
		[[self undoManager] setActionName:[NSString stringWithFormat:@"Delete Variable%@", [rowIndexes count] > 1 ? @"s" : @""]];
	}
	else
	{
		[[self undoManager] setActionName:[NSString stringWithFormat:@"Add Variable%@", [rowIndexes count] > 1 ? @"s" : @""]];
	}
	[[[self undoManager] prepareWithInvocationTarget:self] removeVariablesAtRowIndexes:rowIndexes];
	
	[generalStatusTextField setStringValue:@""];
}

- (IBAction)removeSelectedSearchValues:(id)sender
{
	[self removeVariablesAtRowIndexes:[watchVariablesTableView selectedRowIndexes]];
	[generalStatusTextField setStringValue:@""];
}

- (IBAction)addVariable:(id)sender
{
	ZGVariableQualifier qualifier = [[variableQualifierMatrix cellWithTag:SIGNED_BUTTON_CELL_TAG] state] == NSOnState ? ZGSigned : ZGUnsigned;
	
	ZGVariable *variable = [[ZGVariable alloc] initWithValue:NULL
														size:0
													 address:0
														type:[sender tag]
												   qualifier:qualifier
												 pointerSize:currentProcess->is64Bit ? sizeof(int64_t) : sizeof(int32_t)];
	
	[variable setShouldBeSearched:NO];
	
	[self addVariables:[NSArray arrayWithObject:variable]
		  atRowIndexes:[NSIndexSet indexSetWithIndex:0]];
	
	[variable release];
	
	// have the user edit the variable's address
	[watchVariablesTableView editColumn:[watchVariablesTableView columnWithIdentifier:@"address"]
									row:0
							  withEvent:nil
								 select:YES];
}

#pragma mark Freezing variables

- (void)freezeOrUnfreezeVariablesAtRoxIndexes:(NSIndexSet *)rowIndexes
{
	[rowIndexes enumerateIndexesUsingBlock:^(NSUInteger rowIndex, BOOL *stop)
	 {
		 ZGVariable *variable = [watchVariablesArray objectAtIndex:rowIndex];
		 variable->isFrozen = !(variable->isFrozen);
		 
		 if (variable->isFrozen)
		 {
			 [variable setFreezeValue:variable->value];
		 }
	 }];
	
	[watchVariablesTableView reloadData];
	
	// check whether we want to use "Undo Freeze" or "Redo Freeze" or "Undo Unfreeze" or "Redo Unfreeze"
	if (((ZGVariable *)[watchVariablesArray objectAtIndex:[rowIndexes firstIndex]])->isFrozen)
	{
		if ([[self undoManager] isUndoing])
		{
			[[self undoManager] setActionName:@"Unfreeze"];
		}
		else
		{
			[[self undoManager] setActionName:@"Freeze"];
		}
	}
	else
	{
		if ([[self undoManager] isUndoing])
		{
			[[self undoManager] setActionName:@"Freeze"];
		}
		else
		{
			[[self undoManager] setActionName:@"Unfreeze"];
		}
	}

	[[[self undoManager] prepareWithInvocationTarget:self] freezeOrUnfreezeVariablesAtRoxIndexes:rowIndexes];
}

- (IBAction)freezeVariables:(id)sender
{
	[self freezeOrUnfreezeVariablesAtRoxIndexes:[watchVariablesTableView selectedRowIndexes]];
}

#pragma mark Useful Methods

- (void *)valueFromString:(NSString *)stringValue
				 dataType:(ZGVariableType)dataType
				 dataSize:(mach_vm_size_t *)dataSize
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
	
	return value;
}

- (unsigned long long)memoryAddressFromExpression:(NSString *)expression
{
	unsigned long long address;
	if ([expression isHexRepresentation])
	{
		[[NSScanner scannerWithString:expression] scanHexLongLong:&address];
	}
	else
	{
		address = [expression unsignedLongLongValue];
	}
	
	return address;
}

- (void)setWatchVariablesArray:(NSArray *)newWatchVariablesArray
{
	if ([[self undoManager] isUndoing] || [[self undoManager] isRedoing])
	{
		// Clear the status
		[generalStatusTextField setStringValue:@""];
		
		[[[self undoManager] prepareWithInvocationTarget:self] setWatchVariablesArray:watchVariablesArray];
	}
	
	[watchVariablesArray release];
	watchVariablesArray = [newWatchVariablesArray retain];
	[watchVariablesTableView reloadData];
	
	// Make sure the search value field is enabled if the compare initial values
	// check box is not
	if ([compareInitialValuesCheckBox state] == NSOffState)
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
	ZGVariableType dataType = [[dataTypesPopUpButton selectedItem] tag];
	
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
	// Make sure it's not in hex
	if ([searchComponent isHexRepresentation])
	{
	}
	else
	{
		// Make sure it's a valid number
		NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
		NSNumber *number = [numberFormatter numberFromString:searchComponent];
		if (!number)
		{
			[numberFormatter release];
			return @"The function you are using requires the search value to be a valid expression.";
		}
		
		[numberFormatter release];
	}
	
	return nil;
}

- (NSString *)confirmSearchInput:(NSString *)expression
{
	ZGVariableType dataType = [[dataTypesPopUpButton selectedItem] tag];
	ZGFunctionType functionType = [[functionPopUpButton selectedItem] tag];
	
	if (dataType != ZGUTF8String && dataType != ZGUTF16String)
	{
		// This doesn't matter if the search is implicit
		if (!searchArguments.isImplicit)
		{
			NSString *inputError = [self testSearchComponent:expression];
			
			if (inputError)
			{
				return inputError;
			}
		}
	}
	else if (functionType != ZGEquals && functionType != ZGNotEquals)
	{
		return @"The function you are using does not support Strings.";
	}
	
	if ((dataType == ZGUTF8String || dataType == ZGUTF16String) && searchArguments.isImplicit)
	{
		return @"Comparing initial values is not supported for Strings.";
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
	
	[watchVariablesArray release];
	watchVariablesArray = [[NSArray array] retain];
	[watchVariablesTableView reloadData];
	
	if ([compareInitialValuesCheckBox state] == NSOffState)
	{
		[searchValueTextField setEnabled:YES];
	}
	
	[clearButton setEnabled:NO];
	
	[self updateRunningApplicationProcesses];
	
	[generalStatusTextField setStringValue:@"Cleared search."];
}

- (void)searchCleanUp:(NSArray *)newVariablesArray
{
	if ([newVariablesArray count] != [watchVariablesArray count])
	{
		// time to set the undo action!
		[[self undoManager] setActionName:@"Search"];
		[[[self undoManager] prepareWithInvocationTarget:self] setWatchVariablesArray:watchVariablesArray];
	}
	
	currentProcess->searchProgress = 0;
	if (ZGSearchDidCancelSearch(searchData))
	{
		[searchingProgressIndicator setDoubleValue:currentProcess->searchProgress];
		[generalStatusTextField setStringValue:@"Search canceled."];
	}
	else
	{
		ZGInitializeSearch(searchData);
		[self updateSearchUserInterface:nil];
		
		[watchVariablesArray release];
		watchVariablesArray = [[NSArray arrayWithArray:newVariablesArray] retain];
		[watchVariablesTableView reloadData];
	}
	
	[self resumeDocument];
}

- (IBAction)searchValue:(id)sender
{	
	ZGVariableType dataType = [[dataTypesPopUpButton selectedItem] tag];
	
	BOOL goingToNarrowDownSearches = [self isInNarrowSearchMode];
	
	if ([[searchButton title] isEqualToString:@"Search"])
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
		[watchVariablesTableView setNeedsDisplay:YES];
		
		// Basic search information
		mach_vm_size_t dataSize = 0;
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
		searchArguments.isImplicit = [compareInitialValuesCheckBox state];
		
		NSString *evaluatedSearchExpression = nil;
		NSString *inputErrorMessage = nil;
		
		evaluatedSearchExpression = (dataType == ZGUTF8String || dataType == ZGUTF16String)
									? [searchValueTextField stringValue]
									: [ZGCalculator evaluateExpression:[searchValueTextField stringValue]];
		inputErrorMessage = [self confirmSearchInput:evaluatedSearchExpression];
		
		if (inputErrorMessage)
		{
			NSRunAlertPanel(@"Invalid Input", inputErrorMessage, nil, nil, nil);
			return;
		}
		
		// get search value and data size
		searchValue = [self valueFromString:evaluatedSearchExpression
								   dataType:dataType
								   dataSize:&dataSize];
		
		// We want to read the null terminator in this case... even though we normally don't store the terminator
		// internally for UTF-16 strings. Lame hack, I know.
		if (!searchArguments.disregardNullTerminator && dataType == ZGUTF16String)
		{
			dataSize += sizeof(unichar);
		}
		
		if (searchArguments.isImplicit)
		{
			searchValue = NULL;
		}
		
		ZGFunctionType functionType = [[functionPopUpButton selectedItem] tag];
		BOOL flagsFieldIsBlank = [[[flagsTextField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] isEqualToString:@""];
		
		if ([flagsTextField isEnabled])
		{
			NSString *flagsExpression = (dataType == ZGUTF8String || dataType == ZGUTF16String) ? [flagsTextField stringValue] : [ZGCalculator evaluateExpression:[flagsTextField stringValue]];
			inputErrorMessage = [self testSearchComponent:flagsExpression];
			
			if (inputErrorMessage && !flagsFieldIsBlank)
			{
				NSString *field = (functionType == ZGEquals || functionType == ZGNotEquals) ? @"Epsilon" : (functionType == ZGGreaterThan ? @"Below" : @"Above");
				NSRunAlertPanel(@"Invalid Input", @"The value corresponding to %@ needs to be a valid expression or be left blank.", nil, nil, nil, field);
				return;
			}
			else /* if (!inputErrorMessage || flagsFieldIsBlank) */
			{
				if (functionType == ZGGreaterThan || functionType == ZGLessThan)
				{
					if (!flagsFieldIsBlank)
					{
						// Clearly a range type of search
						mach_vm_size_t rangeDataSize;
						searchArguments.rangeValue = [self valueFromString:flagsExpression
																  dataType:dataType
																  dataSize:&rangeDataSize];
					}
					else
					{
						searchArguments.rangeValue = NULL;
					}
					
					if (functionType == ZGGreaterThan)
					{
						[searchArguments.lastBelowRangeValue release];
						searchArguments.lastBelowRangeValue = [[flagsTextField stringValue] copy];
					}
					else if (functionType == ZGLessThan)
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
						mach_vm_size_t epsilonDataSize;
						void *epsilon = [self valueFromString:flagsExpression
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
		
		if (![calculatedBeginAddress isEqualToString:@""])
		{
			searchArguments.beginAddress = [self memoryAddressFromExpression:calculatedBeginAddress];
			searchArguments.beginAddressExists = YES;
		}
		else
		{
			searchArguments.beginAddressExists = NO;
		}
		
		if (![calculatedEndAddress isEqualToString:@""])
		{
			searchArguments.endAddress = [self memoryAddressFromExpression:calculatedEndAddress];
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
		
		static BOOL (*compareFunctions[4])(ZGSearchArguments *, const void *, const void *, ZGVariableType, mach_vm_size_t, void *) =
		{
			equalFunction, notEqualFunction, greaterThanFunction, lessThanFunction,
		};
		
		BOOL (*compareFunction)(ZGSearchArguments *, const void *, const void *, ZGVariableType, mach_vm_size_t, void *) = compareFunctions[functionType];
		
		if (!goingToNarrowDownSearches)
		{
			int numberOfRegions = [currentProcess numberOfRegions];
			
			[searchingProgressIndicator setMaxValue:numberOfRegions];
			currentProcess->numberOfVariablesFound = 0;
			currentProcess->searchProgress = 0;
			
			updateSearchUserInterfaceTimer = [[ZGTimer alloc] initWithTimeInterval:USER_INTERFACE_UPDATE_TIME_INTERVAL
																			target:self
																		  selector:@selector(updateSearchUserInterface:)];
			
			ZGVariableQualifier qualifier = [[variableQualifierMatrix cellWithTag:SIGNED_BUTTON_CELL_TAG] state] == NSOnState ? ZGSigned : ZGUnsigned;
			unsigned long long pointerSize = currentProcess->is64Bit ? sizeof(int64_t) : sizeof(int32_t);
			
			search_for_data_t searchForDataCallback = ^(void *data, void *data2, mach_vm_address_t address, int currentRegionNumber)
			{
				if ((!searchArguments.beginAddressExists || searchArguments.beginAddress <= address) &&
					(!searchArguments.endAddressExists || searchArguments.endAddress >= address + dataSize) &&
					compareFunction(&searchArguments, data, (data2 != NULL) ? data2 : searchValue, dataType, dataSize, &collator))
				{
					ZGVariable *newVariable = [[ZGVariable alloc] initWithValue:data
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
				if (searchArguments.isImplicit)
				{
					ZGSearchForSavedData([currentProcess processID], currentProcess->is64Bit, dataSize, searchData, searchForDataCallback);
				}
				else
				{
					searchData->scanReadOnly = ([scanReadOnlyValuesCheckBox state] == NSOnState);
					ZGSearchForData([currentProcess processID], currentProcess->is64Bit, dataType, dataSize, searchData, searchForDataCallback);
				}
				dispatch_async(dispatch_get_main_queue(), searchForDataCompleteBlock);
			};
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), searchForDataBlock);
		}
		else /* if (goingToNarrowDownSearches) */
		{
			int processID = [currentProcess processID];
			
			[searchingProgressIndicator setMaxValue:[watchVariablesArray count]];
			currentProcess->searchProgress = 0;
			currentProcess->numberOfVariablesFound = 0;
			
			updateSearchUserInterfaceTimer = [[NSTimer scheduledTimerWithTimeInterval:USER_INTERFACE_UPDATE_TIME_INTERVAL
																			   target:self
																			 selector:@selector(updateSearchUserInterface:)
																			 userInfo:nil
																			  repeats:YES] retain];
			
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
							(!searchArguments.beginAddressExists || searchArguments.beginAddress <= variable->address) &&
							(!searchArguments.endAddressExists || searchArguments.endAddress >= variable->address + dataSize))
						{
							void *value = malloc((size_t)dataSize);
							if (ZGReadBytes(processID, variable->address, value, dataSize))
							{
								void *value2 = searchArguments.isImplicit ? ZGSavedValue(variable->address, searchData, dataSize) : searchValue;
								
								if (value2 && compareFunction(&searchArguments, value, value2, dataType, dataSize, &collator))
								{
									[temporaryVariablesArray addObject:variable];
									currentProcess->numberOfVariablesFound++;
								}
							}
							
							free(value);
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

#pragma mark Getting initial values

- (IBAction)getInitialValues:(id)sender
{
	if (currentProcess->isStoringAllData)
	{
		return;
	}
	
	[searchingProgressIndicator setMaxValue:[currentProcess numberOfRegions]];
	
	updateSearchUserInterfaceTimer = [[NSTimer scheduledTimerWithTimeInterval:USER_INTERFACE_UPDATE_TIME_INTERVAL
																	   target:self
																	 selector:@selector(updateMemoryDumpOrStoreUserInterface:)
																	 userInfo:nil
																	  repeats:YES] retain];
	//not doing this here, there's a bug with setKeyEquivalent, instead i'm going to do this in the timer
	//[self prepareDocumentTask];
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
			else
			{
				[compareInitialValuesCheckBox setEnabled:YES];
			}
			
			searchData->savedData = searchData->tempSavedData;
			searchData->tempSavedData = nil;
			
			[generalStatusTextField setStringValue:@"Finished Memory Store"];
		}
		[searchingProgressIndicator setDoubleValue:0];
		[self resumeDocument];
	};
	
	dispatch_block_t searchForDataBlock = ^
	{
		searchData->tempSavedData = ZGGetAllData(currentProcess, [scanReadOnlyValuesCheckBox state]);
		if (searchData->tempSavedData)
		{
			[searchData->tempSavedData retain];
		}
		
		dispatch_async(dispatch_get_main_queue(), searchForDataCompleteBlock);
	};
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), searchForDataBlock);
}

#pragma mark Table View Drag & Drop

- (NSDragOperation)tableView:(NSTableView *)tableView 
				validateDrop:(id <NSDraggingInfo>)draggingInfo 
				 proposedRow:(int)row 
	   proposedDropOperation:(NSTableViewDropOperation)operation
{
	if ([[[draggingInfo draggingPasteboard] types] containsObject:ZGVariableReorderType] && operation != NSTableViewDropOn)
	{
		return NSDragOperationMove;
	}
	
	return NSDragOperationNone;
}

- (void)reorderVariables:(NSArray *)newVariables
{
	[[self undoManager] setActionName:@"Move"];
	[[[self undoManager] prepareWithInvocationTarget:self] reorderVariables:watchVariablesArray];
	
	[watchVariablesArray release];
	watchVariablesArray = [[NSArray arrayWithArray:newVariables] retain];
	[watchVariablesTableView reloadData];
}

- (BOOL)tableView:(NSTableView *)tableView
	   acceptDrop:(id <NSDraggingInfo>)draggingInfo 
			  row:(int)newRow
	dropOperation:(NSTableViewDropOperation)operation
{	
	NSMutableArray *variables = [NSMutableArray arrayWithArray:watchVariablesArray];
	NSArray *rows = [[draggingInfo draggingPasteboard] propertyListForType:ZGVariableReorderType];
	
	// Fill in the current rows with null objects
	for (NSNumber *row in rows)
	{
		[variables replaceObjectAtIndex:[row integerValue]
							 withObject:[NSNull null]];
	}
	
	// Insert the objects to the new position
	for (NSNumber *row in rows)
	{
		[variables insertObject:[watchVariablesArray objectAtIndex:[row integerValue]]
						atIndex:newRow];
		
		newRow++;
	}
	
	// Remove all the old objects
	[variables removeObject:[NSNull null]];
	
	// Set the new variables
	[self reorderVariables:variables];
	
	return YES;
}

- (BOOL)tableView:(NSTableView *)view
		writeRows:(NSArray *)rows 
	 toPasteboard:(NSPasteboard *)pasteboard
{
	[pasteboard declareTypes:[NSArray arrayWithObject:ZGVariableReorderType] owner:self];
	
	[pasteboard setPropertyList:rows
						forType:ZGVariableReorderType];
	
	return YES;
}

#pragma mark Table View Data Source Methods

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	if (aTableView == watchVariablesTableView)
	{
		if ([[aTableColumn identifier] isEqualToString:@"name"])
		{
			return [[watchVariablesArray objectAtIndex:rowIndex] name];
		}
		else if ([[aTableColumn identifier] isEqualToString:@"address"])
		{
			return [[watchVariablesArray objectAtIndex:rowIndex] addressStringValue];
		}
		else if ([[aTableColumn identifier] isEqualToString:@"value"])
		{
			return [[watchVariablesArray objectAtIndex:rowIndex] stringValue];
		}
		else if ([[aTableColumn identifier] isEqualToString:@"shouldBeSearched"])
		{
			return [NSNumber numberWithBool:[[watchVariablesArray objectAtIndex:rowIndex] shouldBeSearched]];
		}
		else if ([[aTableColumn identifier] isEqualToString:@"type"])
		{
			return [NSNumber numberWithInt:((ZGVariable *)[watchVariablesArray objectAtIndex:rowIndex])->type];
		}
	}
	
	return nil;
}

- (void)changeVariable:(ZGVariable *)variable
			   newName:(NSString *)newName
{
	[[self undoManager] setActionName:@"Name Change"];
	[[[self undoManager] prepareWithInvocationTarget:self] changeVariable:variable
																  newName:[variable name]];
	
	[variable setName:newName];
	
	if ([[self undoManager] isUndoing] || [[self undoManager] isRedoing])
	{
		[watchVariablesTableView reloadData];
	}
}

- (void)changeVariable:(ZGVariable *)variable
			newAddress:(NSString *)newAddress
{
	[[self undoManager] setActionName:@"Address Change"];
	[[[self undoManager] prepareWithInvocationTarget:self] changeVariable:variable
															   newAddress:[variable addressStringValue]];
	[variable setAddressStringValue:[ZGCalculator evaluateExpression:newAddress]];
	
	if ([[self undoManager] isUndoing] || [[self undoManager] isRedoing])
	{
		[watchVariablesTableView reloadData];
	}
}

- (void)changeVariable:(ZGVariable *)variable
			   newType:(ZGVariableType)type
{
	[[self undoManager] setActionName:@"Type Change"];
	[[[self undoManager] prepareWithInvocationTarget:self] changeVariable:variable
																  newType:variable->type];
	
	[variable setType:type pointerSize:currentProcess->is64Bit ? sizeof(int64_t) : sizeof(int32_t)];
	
	if ([[self undoManager] isUndoing] || [[self undoManager] isRedoing])
	{
		[watchVariablesTableView reloadData];
	}
}

- (void)changeVariable:(ZGVariable *)variable
			  newValue:(NSString *)stringObject
	  shouldRecordUndo:(BOOL)recordUndoFlag
{
	void *newValue = NULL;
	
	int8_t int8Value = 0;
	int16_t int16Value = 0;
	int32_t int32Value = 0;
	int64_t int64Value = 0;
	float floatValue = 0.0;
	double doubleValue = 0.0;
	
	if (variable->type != ZGUTF8String && variable->type != ZGUTF16String)
	{
		stringObject = [ZGCalculator evaluateExpression:stringObject];
	}
	
	BOOL stringIsAHexRepresentation = [stringObject isHexRepresentation];
	
	switch (variable->type)
	{
		case ZGInt8:
			if (stringIsAHexRepresentation)
			{
				[[NSScanner scannerWithString:stringObject] scanHexInt:(unsigned int *)&int32Value];
				int8Value = int32Value;
			}
			else
			{
				int8Value = [stringObject intValue];
			}
			
			newValue = &int8Value;
			break;
		case ZGInt16:
			if (stringIsAHexRepresentation)
			{
				[[NSScanner scannerWithString:stringObject] scanHexInt:(unsigned int *)&int32Value];
				int16Value = int32Value;
			}
			else
			{
				int16Value = [stringObject intValue];
			}
			
			newValue = &int16Value;
			break;
		case ZGPointer:
			if (currentProcess->is64Bit)
			{
				if (variable->size == sizeof(int32_t))
				{
					goto INT32_BIT_CHANGE_VARIABLE;
				}
				else if (variable->size == sizeof(int64_t))
				{
					goto INT64_BIT_CHANGE_VARIABLE;
				}
			}
			
			break;
		case ZGInt32:
		INT32_BIT_CHANGE_VARIABLE:
			if (stringIsAHexRepresentation)
			{
				[[NSScanner scannerWithString:stringObject] scanHexInt:(unsigned int *)&int32Value];
			}
			else
			{
				int32Value = [stringObject intValue];
			}
			
			newValue = &int32Value;
			break;
		case ZGFloat:
			if (stringIsAHexRepresentation)
			{
				[[NSScanner scannerWithString:stringObject] scanHexFloat:&floatValue];
			}
			else
			{
				floatValue = [stringObject floatValue];
			}
			
			newValue = &floatValue;
			break;
		case ZGInt64:
		INT64_BIT_CHANGE_VARIABLE:
			if (stringIsAHexRepresentation)
			{
				[[NSScanner scannerWithString:stringObject] scanHexLongLong:(unsigned long long *)&int64Value];
			}
			else
			{
				[[NSScanner scannerWithString:stringObject] scanLongLong:&int64Value];
			}
			
			newValue = &int64Value;
			break;
		case ZGDouble:
			if (stringIsAHexRepresentation)
			{
				[[NSScanner scannerWithString:stringObject] scanHexDouble:&doubleValue];
			}
			else
			{
				doubleValue = [stringObject doubleValue];
			}
			
			newValue = &doubleValue;
			break;
		case ZGUTF8String:
			newValue = (void *)[stringObject cStringUsingEncoding:NSUTF8StringEncoding];
			variable->size = strlen(newValue) + 1;
			break;
		case ZGUTF16String:
			variable->size = [stringObject length] * sizeof(unichar);
			
			if (variable->size)
			{
				newValue = malloc((size_t)variable->size);
				[stringObject getCharacters:newValue
									  range:NSMakeRange(0, [stringObject length])];
			}
			else
			{
				// String "" can be of 0 length
				newValue = malloc(sizeof(unichar));
				unichar nullTerminator = 0;
				memcpy(newValue, &nullTerminator, sizeof(unichar));
			}
			
			break;
	}
	
	if (newValue)
	{
		if (variable->isFrozen)
		{
			[variable setFreezeValue:newValue];
			
			if (recordUndoFlag)
			{
				[[self undoManager] setActionName:@"Freeze Value Change"];
				[[[self undoManager] prepareWithInvocationTarget:self] changeVariable:variable
																			 newValue:[variable stringValue]
																	 shouldRecordUndo:YES];
				
				if ([[self undoManager] isUndoing] || [[self undoManager] isRedoing])
				{
					[watchVariablesTableView reloadData];
				}
			}
		}
		else
		{
			BOOL successfulWrite = YES;
			
			if (variable->size)
			{
				if (!ZGWriteBytes([currentProcess processID], variable->address, newValue, variable->size))
				{
					successfulWrite = NO;
				}
			}
			
			if (variable->type == ZGUTF16String)
			{
				// Don't forget to write the null terminator
				unichar nullTerminator = 0;
				if (!ZGWriteBytes([currentProcess processID], variable->address + variable->size, &nullTerminator, sizeof(unichar)))
				{
					successfulWrite = NO;
				}
			}
			
			if (successfulWrite && recordUndoFlag)
			{
				[[self undoManager] setActionName:@"Value Change"];
				[[[self undoManager] prepareWithInvocationTarget:self] changeVariable:variable
																			 newValue:[variable stringValue]
																	 shouldRecordUndo:YES];
				
				if ([[self undoManager] isUndoing] || [[self undoManager] isRedoing])
				{
					[watchVariablesTableView reloadData];
				}
			}
		}
		
		if (variable->type == ZGUTF16String)
		{
			free(newValue);
		}
	}
}

- (void)changeVariableShouldBeSearched:(BOOL)shouldBeSearched
							rowIndexes:(NSIndexSet *)rowIndexes
{
	NSUInteger currentIndex = [rowIndexes firstIndex];
	while (currentIndex != NSNotFound)
	{
		[[watchVariablesArray objectAtIndex:currentIndex] setShouldBeSearched:shouldBeSearched];
		currentIndex = [rowIndexes indexGreaterThanIndex:currentIndex];
	}
	
	if (![[self undoManager] isUndoing] && ![[self undoManager] isRedoing] && [rowIndexes count] > 1)
	{
		shouldIgnoreTableViewSelectionChange = YES;
	}
	
	// the table view always needs to be reloaded because of being able to select multiple indexes
	[watchVariablesTableView reloadData];
	
	[[self undoManager] setActionName:[NSString stringWithFormat:@"Search Variable%@ Change", ([rowIndexes count] > 1) ? @"s" : @""]];
	[[[self undoManager] prepareWithInvocationTarget:self] changeVariableShouldBeSearched:!shouldBeSearched
																			   rowIndexes:rowIndexes];
}

- (void)tableView:(NSTableView *)aTableView setObjectValue:(id)anObject forTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	if (aTableView == watchVariablesTableView)
	{
		if ([[aTableColumn identifier] isEqualToString:@"name"])
		{
			[self changeVariable:[watchVariablesArray objectAtIndex:rowIndex]
						 newName:anObject];
		}
		else if ([[aTableColumn identifier] isEqualToString:@"address"])
		{
			[self changeVariable:[watchVariablesArray objectAtIndex:rowIndex]
					  newAddress:anObject];
		}
		else if ([[aTableColumn identifier] isEqualToString:@"value"])
		{
			[self changeVariable:[watchVariablesArray objectAtIndex:rowIndex]
						newValue:anObject
				shouldRecordUndo:YES];
		}
		else if ([[aTableColumn identifier] isEqualToString:@"shouldBeSearched"])
		{
			[self changeVariableShouldBeSearched:[anObject boolValue]
									  rowIndexes:[watchVariablesTableView selectedRowIndexes]];
		}
		else if (([[aTableColumn identifier] isEqualToString:@"type"]))
		{
			[self changeVariable:[watchVariablesArray objectAtIndex:rowIndex]
						 newType:[anObject integerValue]];
		}
	}
}

- (int)numberOfRowsInTableView:(NSTableView *)aTableView
{
	// This conversion to unsigned int is kind of awkward to me, but seems like the only way to get rid of an
	// implicit conversion warning
	return MIN(MAX_TABLE_VIEW_ITEMS, (unsigned int)[watchVariablesArray count]);
}

#pragma mark Table View Delegate Methods

- (BOOL)selectionShouldChangeInTableView:(NSTableView *)aTableView
{
	if (shouldIgnoreTableViewSelectionChange)
	{
		shouldIgnoreTableViewSelectionChange = NO;
		return NO;
	}
	
	return YES;
}

- (BOOL)tableView:(NSTableView *)aTableView shouldEditTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	if ([[aTableColumn identifier] isEqualToString:@"value"])
	{
		if (![[searchButton title] isEqualToString:@"Search"] || [currentProcess processID] == NON_EXISTENT_PID_NUMBER)
		{
			NSBeep();
			return NO;
		}
		else if (![clearButton isEnabled])
		{
			[self lockTarget];
		}
	}
	else if ([[aTableColumn identifier] isEqualToString:@"address"])
	{
		ZGVariable *variable = [watchVariablesArray objectAtIndex:rowIndex];
		if (variable && variable->isPointer)
		{
			[self editVariablesAddress:nil];
			return NO;
		}
	}
	
	return YES;
}

- (void)tableView:(NSTableView *)aTableView
  willDisplayCell:(id)aCell
   forTableColumn:(NSTableColumn *)aTableColumn
			  row:(NSInteger)rowIndex
{
	if ([[aTableColumn identifier] isEqualToString:@"address"])
	{
		if (((ZGVariable *)[watchVariablesArray objectAtIndex:rowIndex])->isFrozen)
		{
			[aCell setTextColor:[NSColor redColor]];
		}
		else
		{
			[aCell setTextColor:[NSColor textColor]];
		}
	}
}

- (NSString *)tableView:(NSTableView *)aTableView
		 toolTipForCell:(NSCell *)aCell
				   rect:(NSRectPointer)rect
			tableColumn:(NSTableColumn *)aTableColumn
					row:(NSInteger)row
		  mouseLocation:(NSPoint)mouseLocation
{
	NSString *displayString = nil;
	
	NSNumberFormatter *numberOfVariablesFormatter = [[NSNumberFormatter alloc] init];
	[numberOfVariablesFormatter setFormat:@"#,###"];
	
	if ([watchVariablesArray count] <= MAX_TABLE_VIEW_ITEMS)
	{
		displayString = [NSString stringWithFormat:@"Displaying %@ value", [numberOfVariablesFormatter stringFromNumber:[NSNumber numberWithUnsignedInteger:[watchVariablesArray count]]]];
	}
	else
	{
		displayString = [NSString stringWithFormat:@"Displaying %@ of %@ value", [numberOfVariablesFormatter stringFromNumber:[NSNumber numberWithUnsignedInt:MAX_TABLE_VIEW_ITEMS]],[numberOfVariablesFormatter stringFromNumber:[NSNumber numberWithUnsignedInteger:[watchVariablesArray count]]]];
	}
	
	[numberOfVariablesFormatter release];
	
	if (displayString && [watchVariablesArray count] != 1)
	{
		displayString = [displayString stringByAppendingString:@"s"];
	}
	
	return displayString;
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
		if ([watchVariablesTableView selectedRow] < 0 || [watchWindow firstResponder] != watchVariablesTableView)
		{
			return NO;
		}
	}
	
	else if ([theMenuItem action] == @selector(freezeVariables:))
	{
		if ([watchVariablesArray count] > 0)
		{
			// All the variables selected need to either be all unfrozen or all frozen
			BOOL isFrozen = ((ZGVariable *)[watchVariablesArray objectAtIndex:[watchVariablesTableView selectedRow]])->isFrozen;
			BOOL isInconsistent = NO;
			
			NSUInteger currentIndex = [[watchVariablesTableView selectedRowIndexes] firstIndex];
			while (currentIndex != NSNotFound)
			{
				ZGVariable *variable = [watchVariablesArray objectAtIndex:currentIndex];
				// we should also check if the variable has an existing value at all
				if (variable && (variable->isFrozen != isFrozen || !variable->value))
				{
					isInconsistent = YES;
					break;
				}
				currentIndex = [[watchVariablesTableView selectedRowIndexes] indexGreaterThanIndex:currentIndex];
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
			
			if ([[watchVariablesTableView selectedRowIndexes] count] > 1)
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
		if (![[searchButton title] isEqualToString:@"Search"])
		{
			return NO;
		}
	}
	
	else if ([theMenuItem action] == @selector(lockTarget:))
	{
		if (![[searchButton title] isEqualToString:@"Search"])
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
		if ([[searchButton title] isEqualToString:@"Cancel"])
		{
			return NO;
		}
	}
	
	else if ([theMenuItem action] == @selector(copy:))
	{
		if ([[watchVariablesTableView selectedRowIndexes] count] == 0)
		{
			return NO;
		}
	}
	
	else if ([theMenuItem action] == @selector(paste:))
	{
		if ([[searchButton title] isEqualToString:@"Cancel"] || ![[NSPasteboard generalPasteboard] dataForType:ZGVariablePboardType])
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
		if ([[watchVariablesTableView selectedRowIndexes] count] != 1)
		{
			[theMenuItem setTitle:@"Edit Variable Values…"];
		}
		else
		{
			[theMenuItem setTitle:@"Edit Variable Value…"];
		}
		
		if ([[searchButton title] isEqualToString:@"Cancel"] || [watchVariablesTableView selectedRow] == -1 || [currentProcess processID] == NON_EXISTENT_PID_NUMBER)
		{
			return NO;
		}
	}
	
	else if ([theMenuItem action] == @selector(editVariablesAddress:))
	{
		if ([[searchButton title] isEqualToString:@"Cancel"] || [watchVariablesTableView selectedRow] == -1 || [currentProcess processID] == NON_EXISTENT_PID_NUMBER)
		{
			return NO;
		}
	}
	
	else if ([theMenuItem action] == @selector(memoryDumpRequest:) || [theMenuItem action] == @selector(memoryDumpAllRequest:) || [theMenuItem action] == @selector(getInitialValues:))
	{
		if ([[searchButton title] isEqualToString:@"Cancel"] || [currentProcess processID] == NON_EXISTENT_PID_NUMBER)
		{
			return NO;
		}
	}
	
	return YES;
}

#pragma mark Global Actions

- (IBAction)copy:(id)sender
{
	[[NSPasteboard generalPasteboard] declareTypes:[NSArray arrayWithObjects:NSStringPboardType, ZGVariablePboardType, nil]
											 owner:self];
	
	NSMutableString *stringToWrite = [[NSMutableString alloc] init];
	NSArray *variablesArray = [watchVariablesArray objectsAtIndexes:[watchVariablesTableView selectedRowIndexes]];
	
	for (ZGVariable *variable in variablesArray)
	{
		[stringToWrite appendFormat:@"%@ %@ %@\n", [variable name], [variable addressStringValue], [variable stringValue]];
	}
	
	// Remove the last '\n' character
	[stringToWrite deleteCharactersInRange:NSMakeRange([stringToWrite length] - 1, 1)];
	
	[[NSPasteboard generalPasteboard] setString:stringToWrite
										forType:NSStringPboardType];
	
	[stringToWrite release];
	
	[[NSPasteboard generalPasteboard] setData:[NSKeyedArchiver archivedDataWithRootObject:variablesArray]
									  forType:ZGVariablePboardType];
}

- (IBAction)paste:(id)sender
{
	NSData *pasteboardData = [[NSPasteboard generalPasteboard] dataForType:ZGVariablePboardType];
	if (pasteboardData)
	{
		NSArray *variablesToInsertArray = [NSKeyedUnarchiver unarchiveObjectWithData:pasteboardData];
		NSInteger currentIndex = [watchVariablesTableView selectedRow];
		if (currentIndex == -1)
		{
			currentIndex = 0;
		}
		else
		{
			currentIndex++;
		}
		
		NSIndexSet *indexesToInsert = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(currentIndex, [variablesToInsertArray count])];
		
		[self addVariables:variablesToInsertArray
			  atRowIndexes:indexesToInsert];
	}
}

#pragma mark Edit Variables Values

- (IBAction)editVariablesValueCancelButton:(id)sender
{
	[NSApp endSheet:editVariablesValueWindow];
	[editVariablesValueWindow close];
}

- (void)editVariables:(NSArray *)variables
			newValues:(NSArray *)newValues
{
	NSMutableArray *oldValues = [[NSMutableArray alloc] init];
	
	[variables enumerateObjectsUsingBlock:^(id object, NSUInteger index, BOOL *stop)
	 {
		 ZGVariable *variable = object;
		 
		 [oldValues addObject:[variable stringValue]];
		 
		 [self changeVariable:variable
					 newValue:[newValues objectAtIndex:index]
			 shouldRecordUndo:NO];
	 }];
	
	[watchVariablesTableView reloadData];
	
	[[self undoManager] setActionName:@"Edit Variables"];
	[[[self undoManager] prepareWithInvocationTarget:self] editVariables:variables
															   newValues:oldValues];
	[oldValues release];
}

- (IBAction)editVariablesValueOkayButton:(id)sender
{
	[NSApp endSheet:editVariablesValueWindow];
	[editVariablesValueWindow close];
	
	NSArray *variables = [watchVariablesArray objectsAtIndexes:[watchVariablesTableView selectedRowIndexes]];
	NSMutableArray *valuesArray = [[NSMutableArray alloc] init];
	
	[variables enumerateObjectsUsingBlock:^(id variable, NSUInteger index, BOOL *stop)
	 {
		 [valuesArray addObject:[editVariablesValueTextField stringValue]];
	 }];
	
	[self editVariables:variables
			  newValues:valuesArray];
	
	[valuesArray release];
}

- (IBAction)editVariablesValue:(id)sender
{
	[editVariablesValueTextField setStringValue:[[watchVariablesArray objectAtIndex:[watchVariablesTableView selectedRow]] stringValue]];
	
	[NSApp beginSheet:editVariablesValueWindow
	   modalForWindow:watchWindow
		modalDelegate:self
	   didEndSelector:nil
		  contextInfo:NULL];
}

#pragma mark Edit Variables Address

- (IBAction)editVariablesAddressCancelButton:(id)sender
{
	[NSApp endSheet:editVariablesAddressWindow];
	[editVariablesAddressWindow close];
}

- (void)editVariable:(ZGVariable *)variable
	  addressFormula:(NSString *)newAddressFormula
{
	[[self undoManager] setActionName:@"Address Change"];
	[[[self undoManager] prepareWithInvocationTarget:self] editVariable:variable
														 addressFormula:[variable addressFormula]];
	
	[variable setAddressFormula:newAddressFormula];
	if ([newAddressFormula rangeOfString:@"["].location != NSNotFound && [newAddressFormula rangeOfString:@"]"].location != NSNotFound)
	{
		variable->isPointer = YES;
	}
	else
	{
		variable->isPointer = NO;
		[variable setAddressStringValue:[ZGCalculator evaluateExpression:newAddressFormula]];
		[watchVariablesTableView reloadData];
	}
}

- (IBAction)editVariablesAddressOkayButton:(id)sender
{
	[NSApp endSheet:editVariablesAddressWindow];
	[editVariablesAddressWindow close];
	
	[self editVariable:[watchVariablesArray objectAtIndex:[watchVariablesTableView selectedRow]]
		addressFormula:[editVariablesAddressTextField stringValue]];
}

- (IBAction)editVariablesAddress:(id)sender
{
	ZGVariable *variable = [watchVariablesArray objectAtIndex:[watchVariablesTableView selectedRow]];
	[editVariablesAddressTextField setStringValue:[variable addressFormula]];
	
	[NSApp beginSheet:editVariablesAddressWindow
	   modalForWindow:watchWindow
		modalDelegate:self
	   didEndSelector:nil
		  contextInfo:NULL];
}

#pragma mark Memory Dumps

- (IBAction)memoryDumpOkayButton:(id)sender
{
	NSString *fromAddressExpression = [ZGCalculator evaluateExpression:[memoryDumpFromAddressTextField stringValue]];
	unsigned long long fromAddress = [self memoryAddressFromExpression:fromAddressExpression];
	
	NSString *toAddressExpression = [ZGCalculator evaluateExpression:[memoryDumpToAddressTextField stringValue]];
	unsigned long long toAddress = [self memoryAddressFromExpression:toAddressExpression];
	
	if (toAddress > fromAddress && ![fromAddressExpression isEqualToString:@""] && ![toAddressExpression isEqualToString:@""])
	{
		[NSApp endSheet:memoryDumpWindow];
		[memoryDumpWindow close];
		
		NSSavePanel *savePanel = [NSSavePanel savePanel];
		[savePanel beginSheetModalForWindow:watchWindow
						  completionHandler:^(NSInteger result)
		 {
			 if (result == NSFileHandlingPanelOKButton)
			 {
				 BOOL success = YES;
				 
				 @try
				 {
					 
					 mach_vm_size_t size = toAddress - fromAddress;
					 void *bytes = malloc((size_t)size);
					 
					 if (bytes)
					 {
						 ZGReadBytesCarefully([currentProcess processID], fromAddress, bytes, &size);
						 
						 NSData *data = [NSData dataWithBytes:bytes
													   length:(NSUInteger)size];
						 
						 success = [data writeToFile:[savePanel filename]
										  atomically:NO];
						 
						 free(bytes); 
					 }
					 else
					 {
						 NSLog(@"Failed to allocate region");
						 success = NO;
					 }
				 }
				 @catch (NSException *exception)
				 {
					 NSLog(@"Failed to write data");
					 success = NO;
				 }
				 @finally
				 {
					 if (!success)
					 {
						 NSRunAlertPanel(@"The Memory Dump failed",
										 @"An error resulted in writing the memory dump.",
										 @"OK", nil, nil);
					 }
				 }
			 }
		 }];
	}
	else
	{
		NSRunAlertPanel(@"Invalid range",
						@"Please make sure you typed in the addresses correctly.",
						@"OK", nil, nil);
	}
}

- (IBAction)memoryDumpCancelButton:(id)sender
{
	[NSApp endSheet:memoryDumpWindow];
	[memoryDumpWindow close];
}

- (IBAction)memoryDumpRequest:(id)sender
{
	// guess what the user may want if nothing is in the text fields
	if ([[memoryDumpFromAddressTextField stringValue] isEqualToString:@""] && [[memoryDumpToAddressTextField stringValue] isEqualToString:@""] && [watchVariablesTableView selectedRow] != -1)
	{
		ZGVariable *firstVariable = [watchVariablesArray objectAtIndex:[[watchVariablesTableView selectedRowIndexes] firstIndex]];
		ZGVariable *lastVariable = [watchVariablesArray objectAtIndex:[[watchVariablesTableView selectedRowIndexes] lastIndex]];
		
		[memoryDumpFromAddressTextField setStringValue:[firstVariable addressStringValue]];
		
		if (firstVariable != lastVariable)
		{
			[memoryDumpToAddressTextField setStringValue:[lastVariable addressStringValue]];
		}
	}
	
	[NSApp beginSheet:memoryDumpWindow
	   modalForWindow:watchWindow
		modalDelegate:self
	   didEndSelector:nil
		  contextInfo:NULL];
}

- (IBAction)memoryDumpAllRequest:(id)sender
{
	NSSavePanel *savePanel = [NSSavePanel savePanel];
	[savePanel setMessage:@"Choose a folder name to save the memory dump files. This may take a while."];
	
	[savePanel beginSheetModalForWindow:watchWindow
					  completionHandler:^(NSInteger result)
	 {
		 if (result == NSFileHandlingPanelOKButton)
		 {
			 if ([[NSFileManager defaultManager] fileExistsAtPath:[savePanel filename]])
			 {
				 [[NSFileManager defaultManager] removeItemAtPath:[savePanel filename]
															error:NULL];
			 }
			 
			 // Since Bit Slicer is running as root, we'll need to pass attributes dictionary so that
			 // the folder is owned by the user
			 [[NSFileManager defaultManager] createDirectoryAtPath:[savePanel filename]
									   withIntermediateDirectories:NO
														attributes:[NSDictionary dictionaryWithObjectsAndKeys:NSUserName(), NSFileGroupOwnerAccountName, NSUserName(), NSFileOwnerAccountName, nil]
															 error:NULL];
			 
			 [searchingProgressIndicator setMaxValue:[currentProcess numberOfRegions]];
			 
			 updateSearchUserInterfaceTimer = [[NSTimer scheduledTimerWithTimeInterval:USER_INTERFACE_UPDATE_TIME_INTERVAL
																				target:self
																			  selector:@selector(updateMemoryDumpOrStoreUserInterface:)
																			  userInfo:nil
																			   repeats:YES] retain];
			 
			 //not doing this here, there's a bug with setKeyEquivalent, instead i'm going to do this in the timer
			 //[self prepareDocumentTask];
			 [generalStatusTextField setStringValue:@"Writing Memory Dump..."];
			 
			 dispatch_block_t searchForDataCompleteBlock = ^
			 {
				 [updateSearchUserInterfaceTimer invalidate];
				 [updateSearchUserInterfaceTimer release];
				 updateSearchUserInterfaceTimer = nil;
				 
				 if (!currentProcess->isDoingMemoryDump)
				 {
					 [generalStatusTextField setStringValue:@"Canceled Memory Dump"];
				 }
				 else
				 {
					 currentProcess->isDoingMemoryDump = NO;
					 [generalStatusTextField setStringValue:@"Finished Memory Dump"];
				 }
				 [searchingProgressIndicator setDoubleValue:0];
				 [self resumeDocument];
			 };
			 
			 dispatch_block_t searchForDataBlock = ^
			 {
				 if (!ZGSaveAllDataToDirectory([savePanel filename], currentProcess))
				 {
					 NSRunAlertPanel(@"The Memory Dump failed",
									 @"An error resulted in writing the memory dump.",
									 @"OK", nil, nil);
				 }
				  
				 dispatch_async(dispatch_get_main_queue(), searchForDataCompleteBlock);
			 };
			 dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), searchForDataBlock);
		 }
	 }];
}

#pragma mark Pausing and Unpausing Processes

- (IBAction)pauseOrUnpauseProcess:(id)sender
{
	[ZGProcess pauseOrUnpauseProcess:[currentProcess processID]];
}

@end
