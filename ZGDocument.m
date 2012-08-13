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
#import "ZGDocumentSearchController.h"
#import "ZGDocumentTableController.h"
#import "ZGMemoryDumpController.h"
#import "ZGMemoryProtectionController.h"
#import "ZGProcess.h"
#import "ZGVirtualMemory.h"
#import "ZGVariable.h"
#import "ZGAppController.h"
#import "ZGMemoryViewer.h"
#import "ZGComparisonFunctions.h"
#import "NSStringAdditions.h"
#import "ZGCalculator.h"
#import "ZGVariable.h"
#import "ZGUtilities.h"
#import "ZGSearchData.h"
#import "ZGComparisonFunctions.h"

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

@interface ZGDocumentInfo : NSObject

@property (readwrite, nonatomic) BOOL loadedFromSave;
@property (readwrite, nonatomic) NSInteger selectedDatatypeTag;
@property (readwrite, nonatomic) NSInteger qualifierTag;
@property (readwrite, nonatomic) NSInteger functionTypeTag;
@property (readwrite, nonatomic) BOOL scanUnwritableValues;
@property (readwrite, nonatomic) BOOL ignoreDataAlignment;
@property (readwrite, nonatomic) BOOL exactStringLength;
@property (readwrite, nonatomic) BOOL ignoreStringCase;
@property (readwrite, copy, nonatomic) NSString *beginningAddress;
@property (readwrite, copy, nonatomic) NSString *endingAddress;
@property (readwrite, copy, nonatomic) NSString *searchValue;
@property (readwrite, strong, nonatomic) NSArray *watchVariablesArray;

@end

@implementation ZGDocumentInfo
@end

@interface ZGDocument ()

@property (readwrite) ZGVariableType currentSearchDataType;
@property (readwrite, strong) ZGDocumentInfo *documentState;

@property (strong) IBOutlet ZGMemoryDumpController *memoryDumpController;
@property (assign) IBOutlet ZGMemoryProtectionController *memoryProtectionController;

@property (assign) IBOutlet NSTextField *searchValueLabel;
@property (assign) IBOutlet NSTextField *flagsLabel;
@property (assign) IBOutlet NSButton *optionsDisclosureButton;
@property (assign) IBOutlet NSView *optionsView;

@end

#define ZG_EXPAND_OPTIONS @"ZG_EXPAND_OPTIONS"

@implementation ZGDocument

- (NSArray *)selectedVariables
{
	return (self.tableController.watchVariablesTableView.selectedRow == -1) ? nil : [self.watchVariablesArray objectsAtIndexes:self.tableController.watchVariablesTableView.selectedRowIndexes];
}

#pragma mark Document stuff

+ (void)initialize
{
	[NSUserDefaults.standardUserDefaults registerDefaults:@{ZG_EXPAND_OPTIONS : @(NO)}];
}

- (id)init
{
	self = [super init];
	if (self)
	{
		[NSWorkspace.sharedWorkspace
		 addObserver:self
		 forKeyPath:@"runningApplications"
		 options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew
		 context:NULL];
	}
	return self;
}

- (void)dealloc
{
	[NSNotificationCenter.defaultCenter removeObserver:self];
	
	[NSWorkspace.sharedWorkspace
	 removeObserver:self
	 forKeyPath:@"runningApplications"];
	
	[self.searchController cleanUp];
	[self.tableController cleanUp];
	[self.memoryDumpController cleanUp];
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
	if (!self.desiredProcessName)
	{
		self.desiredProcessName = [[ZGAppController sharedController] lastSelectedProcessName];
	}
    
	// check if the document is being reverted
	if (self.watchWindow)
	{
		self.generalStatusTextField.stringValue = @"";
	}
	
	[self addApplicationsToPopupButton];
	
	self.currentSearchDataType = (ZGVariableType)self.dataTypesPopUpButton.selectedItem.tag;
	
	if (self.documentState.loadedFromSave)
	{
		[self setWatchVariablesArrayAndUpdateInterface:self.documentState.watchVariablesArray];
		self.documentState.watchVariablesArray = nil;
        
		[self
		 selectDataTypeWithTag:(ZGVariableType)self.documentState.selectedDatatypeTag
		 recordUndo:NO];
        
		[self.variableQualifierMatrix selectCellWithTag:self.documentState.qualifierTag];
		
		self.scanUnwritableValuesCheckBox.state = self.documentState.scanUnwritableValues;
		self.ignoreDataAlignmentCheckBox.state = self.documentState.ignoreDataAlignment;
		self.includeNullTerminatorCheckBox.state = self.documentState.exactStringLength;
		self.ignoreCaseCheckBox.state = self.documentState.ignoreStringCase;
		
		if (self.documentState.beginningAddress)
		{
			self.beginningAddressTextField.stringValue = self.documentState.beginningAddress;
			self.documentState.beginningAddress = nil;
		}
		
		if (self.documentState.endingAddress)
		{
			self.endingAddressTextField.stringValue = self.documentState.endingAddress;
			self.documentState.endingAddress = nil;
		}

		if (![self isFunctionTypeStore:self.documentState.functionTypeTag])
		{
			[self.functionPopUpButton selectItemWithTag:self.documentState.functionTypeTag];
			[self
			 functionTypePopUpButtonRequest:nil
			 markChanges:NO];
		}
        
		if (self.documentState.searchValue)
		{
			self.searchValueTextField.stringValue = self.documentState.searchValue;
			self.documentState.searchValue = nil;
		}
		
		self.documentState = nil;
	}
	else
	{
		[self setWatchVariablesArrayAndUpdateInterface:[NSArray array]];
		self.flagsLabel.textColor = [NSColor disabledControlTextColor];
	}
}

- (void)windowControllerDidLoadNib:(NSWindowController *) aController
{
	[super windowControllerDidLoadNib:aController];
	
	if (![NSUserDefaults.standardUserDefaults boolForKey:ZG_EXPAND_OPTIONS])
	{
		[self optionsDisclosureButton:nil];
	}

	[self.watchWindow setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];

	if ([ZGAppController isRunningLaterThanLion])
	{
		[NSNotificationCenter.defaultCenter
		 addObserver:self
		 selector:@selector(watchWindowDidExitFullScreen:)
		 name:NSWindowDidExitFullScreenNotification
		 object:self.watchWindow];
        
		[NSNotificationCenter.defaultCenter
		 addObserver:self
		 selector:@selector(watchWindowWillExitFullScreen:)
		 name:NSWindowWillExitFullScreenNotification
		 object:self.watchWindow];
	}
	
	[self loadDocumentUserInterface];
}

- (NSFileWrapper *)fileWrapperOfType:(NSString *)typeName error:(NSError **)outError
{
	NSMutableData *writeData = [[NSMutableData alloc] init];
	NSKeyedArchiver *keyedArchiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:writeData];
	
	NSArray *watchVariablesArrayToSave;
	
	if (!self.watchVariablesArray)
	{
		watchVariablesArrayToSave = [NSArray array];
	}
	else if (self.watchVariablesArray.count > MAX_TABLE_VIEW_ITEMS)
	{
		watchVariablesArrayToSave = [self.watchVariablesArray subarrayWithRange:NSMakeRange(0, MAX_TABLE_VIEW_ITEMS)];
	}
	else
	{
		watchVariablesArrayToSave = self.watchVariablesArray;
	}
	
	[keyedArchiver
	 encodeObject:watchVariablesArrayToSave
	 forKey:ZGWatchVariablesArrayKey];
	
	[keyedArchiver
	 encodeObject:self.currentProcess.name
	 forKey:ZGProcessNameKey];
    
	[keyedArchiver
	 encodeInt32:(int32_t)self.dataTypesPopUpButton.selectedItem.tag
	 forKey:ZGSelectedDataTypeTag];
    
	[keyedArchiver
	 encodeInt32:(int32_t)[self.variableQualifierMatrix.selectedCell tag]
	 forKey:ZGQualifierTagKey];
    
	[keyedArchiver
	 encodeInt32:(int32_t)self.functionPopUpButton.selectedItem.tag
	 forKey:ZGFunctionTypeTagKey];
    
	[keyedArchiver
	 encodeBool:self.scanUnwritableValuesCheckBox.state
	 forKey:ZGScanUnwritableValuesKey];
    
	[keyedArchiver
	 encodeBool:self.ignoreDataAlignmentCheckBox.state
	 forKey:ZGIgnoreDataAlignmentKey];
    
	[keyedArchiver
	 encodeBool:self.includeNullTerminatorCheckBox.state
	 forKey:ZGExactStringLengthKey];
    
	[keyedArchiver
	 encodeBool:self.ignoreCaseCheckBox.state
	 forKey:ZGIgnoreStringCaseKey];
    
	[keyedArchiver
	 encodeObject:self.beginningAddressTextField.stringValue
	 forKey:ZGBeginningAddressKey];
    
	[keyedArchiver
	 encodeObject:self.endingAddressTextField.stringValue
	 forKey:ZGEndingAddressKey];
    
	[keyedArchiver
	 encodeObject:self.searchController.searchData.lastEpsilonValue
	 forKey:ZGEpsilonKey];
    
	[keyedArchiver
	 encodeObject:self.searchController.searchData.lastAboveRangeValue
	 forKey:ZGAboveValueKey];
    
	[keyedArchiver
	 encodeObject:self.searchController.searchData.lastBelowRangeValue
	 forKey:ZGBelowValueKey];
    
	[keyedArchiver
	 encodeObject:self.searchValueTextField.stringValue
	 forKey:ZGSearchStringValueKey];
    
	self.desiredProcessName = self.currentProcess.name;
	
	[keyedArchiver finishEncoding];
	
	return [[NSFileWrapper alloc] initRegularFileWithContents:writeData];
}

- (BOOL)readFromFileWrapper:(NSFileWrapper *)fileWrapper ofType:(NSString *)typeName error:(NSError **)outError
{
	NSData *readData = [fileWrapper regularFileContents];
	NSKeyedUnarchiver *keyedUnarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:readData];
	
	[self setDocumentState:[[ZGDocumentInfo alloc] init]];
	
	self.documentState.watchVariablesArray = [keyedUnarchiver decodeObjectForKey:ZGWatchVariablesArrayKey];
	self.desiredProcessName = [keyedUnarchiver decodeObjectForKey:ZGProcessNameKey];
	
	self.documentState.loadedFromSave = YES;
	self.documentState.selectedDatatypeTag = (NSInteger)[keyedUnarchiver decodeInt32ForKey:ZGSelectedDataTypeTag];
	self.documentState.qualifierTag = (NSInteger)[keyedUnarchiver decodeInt32ForKey:ZGQualifierTagKey];
	self.documentState.functionTypeTag = (NSInteger)[keyedUnarchiver decodeInt32ForKey:ZGFunctionTypeTagKey];
	self.documentState.scanUnwritableValues = [keyedUnarchiver decodeBoolForKey:ZGScanUnwritableValuesKey];
	self.documentState.ignoreDataAlignment = [keyedUnarchiver decodeBoolForKey:ZGIgnoreDataAlignmentKey];
	self.documentState.exactStringLength = [keyedUnarchiver decodeBoolForKey:ZGExactStringLengthKey];
	self.documentState.ignoreStringCase = [keyedUnarchiver decodeBoolForKey:ZGIgnoreStringCaseKey];
	self.documentState.beginningAddress = [keyedUnarchiver decodeObjectForKey:ZGBeginningAddressKey];
	self.documentState.endingAddress = [keyedUnarchiver decodeObjectForKey:ZGEndingAddressKey];
	
	self.documentState.searchValue = [keyedUnarchiver decodeObjectForKey:ZGSearchStringValueKey];
	
	self.searchController.searchData.lastEpsilonValue = [keyedUnarchiver decodeObjectForKey:ZGEpsilonKey];
	self.searchController.searchData.lastAboveRangeValue = [keyedUnarchiver decodeObjectForKey:ZGAboveValueKey];
	self.searchController.searchData.lastBelowRangeValue = [keyedUnarchiver decodeObjectForKey:ZGBelowValueKey];
	
	BOOL success = self.documentState.watchVariablesArray != nil && self.desiredProcessName != nil;
	
	if (success && self.watchWindow)
	{
		[self loadDocumentUserInterface];
	}
	
	return success;
}

#pragma mark Watching other applications

- (IBAction)runningApplicationsPopUpButtonRequest:(id)sender
{
	BOOL pointerSizeChanged = YES;
	
	if (self.runningApplicationsPopUpButton.selectedItem.representedObject != self.currentProcess)
	{
		if (self.runningApplicationsPopUpButton.selectedItem.representedObject && self.currentProcess && [self.runningApplicationsPopUpButton.selectedItem.representedObject is64Bit] != self.currentProcess.is64Bit)
		{
			pointerSizeChanged = YES;
		}
		
		// this is about as far as we go when it comes to undo/redos...
		[self.undoManager removeAllActions];
	}
	
	self.currentProcess = self.runningApplicationsPopUpButton.selectedItem.representedObject;
	
	if (pointerSizeChanged)
	{
		// Update the pointer variable sizes
		for (ZGVariable *variable in self.watchVariablesArray)
		{
			if (variable.type == ZGPointer)
			{
				variable.pointerSize = self.currentProcess.pointerSize;
			}
		}
		
		[self.tableController.watchVariablesTableView reloadData];
	}
	
	// keep track of the process the user targeted
	[[ZGAppController sharedController] setLastSelectedProcessName:self.currentProcess.name];
	
	if (sender && ![self.desiredProcessName isEqualToString:self.currentProcess.name])
	{
		self.desiredProcessName = self.currentProcess.name;
		[self markDocumentChange];
	}
	
	if (self.currentProcess && self.currentProcess.processID != NON_EXISTENT_PID_NUMBER)
	{
		if (![self.currentProcess grantUsAccess])
		{
			NSAttributedString *errorMessage =
				[[NSAttributedString alloc]
				 initWithString:[NSString stringWithFormat:@"Failed accessing %@", self.currentProcess.name]
				 attributes:@{NSForegroundColorAttributeName : NSColor.redColor}];
			
			self.generalStatusTextField.attributedStringValue = errorMessage;
		}
		else
		{
			// clear the status
			[self.generalStatusTextField setStringValue:@""];
		}
	}
	
	// Trash all other menu items if they're dead
	NSMutableArray *itemsToRemove = [[NSMutableArray alloc] init];
	for (NSMenuItem *menuItem in self.runningApplicationsPopUpButton.itemArray)
	{
		if (menuItem != self.runningApplicationsPopUpButton.selectedItem &&
			([menuItem.representedObject processID] == NON_EXISTENT_PID_NUMBER ||
			 ![NSWorkspace.sharedWorkspace.runningApplications containsObject:[NSRunningApplication runningApplicationWithProcessIdentifier:[menuItem.representedObject processID]]]))
		{
			[itemsToRemove addObject:menuItem];
		}
	}
	
	for (id item in itemsToRemove)
	{
		[self.runningApplicationsPopUpButton removeItemAtIndex:[self.runningApplicationsPopUpButton indexOfItem:item]];
	}
	
	// If we're switching to a process, search button should be enabled if it's alive
	if (self.currentProcess.processID != NON_EXISTENT_PID_NUMBER)
	{
		self.searchButton.enabled =YES;
	}
}

- (void)addApplicationsToPopupButton
{
	// Add running applications to popup button
	for (NSRunningApplication *runningApplication in NSWorkspace.sharedWorkspace.runningApplications)
	{
		[self addRunningApplicationToPopupButton:runningApplication];
	}
	
	if (self.desiredProcessName && ![self.currentProcess.name isEqualToString:self.desiredProcessName])
	{
		ZGProcess *deadProcess =
		[[ZGProcess alloc]
		 initWithName:[self desiredProcessName]
		 processID:NON_EXISTENT_PID_NUMBER
		 set64Bit:YES];
		
		NSMenuItem *menuItem = [[NSMenuItem alloc] init];
		menuItem.title = [NSString stringWithFormat:@"%@ (none)", deadProcess.name];
		menuItem.representedObject = deadProcess;
		
		[self.runningApplicationsPopUpButton.menu addItem:menuItem];
		
		[self.runningApplicationsPopUpButton selectItem:menuItem];
		
		[self runningApplicationsPopUpButtonRequest:nil];
		[self removeRunningApplicationFromPopupButton:nil];
	}
}

- (void)removeRunningApplicationFromPopupButton:(NSRunningApplication *)oldRunningApplication
{
	// Great, a process terminated, but we don't know which one
	if (oldRunningApplication.processIdentifier == -1)
	{
		NSMutableArray *menuItemsToRemove = [[NSMutableArray alloc] init];
		for (NSMenuItem *menuItem in self.runningApplicationsPopUpButton.itemArray)
		{
			NSRunningApplication *runningApplication = [NSRunningApplication runningApplicationWithProcessIdentifier:[menuItem.representedObject processID]];
			if (runningApplication.processIdentifier == -1 || ![NSWorkspace.sharedWorkspace.runningApplications containsObject:runningApplication])
			{
				if ([menuItem.representedObject processID] == self.currentProcess.processID)
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
			[self.runningApplicationsPopUpButton removeItemAtIndex:[self.runningApplicationsPopUpButton indexOfItem:menuItem]];
		}
	}
	
	// Just to be sure
	if (oldRunningApplication.processIdentifier != NSRunningApplication.currentApplication.processIdentifier)
	{
		// oldRunningApplication == nil, means remove 'current process'
		if (self.currentProcess.processID == oldRunningApplication.processIdentifier || !oldRunningApplication)
		{
			// Don't remove the item, just indicate it's terminated
			NSAttributedString *status =
				[[NSAttributedString alloc]
				 initWithString:[NSString stringWithFormat:@"%@ is not running.", self.currentProcess.name]
				 attributes:@{NSForegroundColorAttributeName : NSColor.redColor}];
			
			self.generalStatusTextField.attributedStringValue = status;
			
			self.searchButton.enabled = NO;
			self.currentProcess.processID = NON_EXISTENT_PID_NUMBER;
			self.runningApplicationsPopUpButton.selectedItem.title = [NSString stringWithFormat:@"%@ (none)", self.currentProcess.name];
			
			// Set the icon to the standard one
			NSImage *regularAppIcon = [[NSImage imageNamed:@"NSDefaultApplicationIcon"] copy];
			if (regularAppIcon)
			{
				regularAppIcon.size = NSMakeSize(16, 16);
				self.runningApplicationsPopUpButton.selectedItem.image = regularAppIcon;
			}
		}
		else if (oldRunningApplication.processIdentifier != -1)
		{
			// Find the menu item, and remove it
			NSMenuItem *itemToRemove = nil;
			for (NSMenuItem *item in self.runningApplicationsPopUpButton.itemArray)
			{
				if ([item.representedObject processID] == oldRunningApplication.processIdentifier)
				{
					itemToRemove = item;
					break;
				}
			}
			
			if (itemToRemove)
			{
				[self.runningApplicationsPopUpButton removeItemAtIndex:[self.runningApplicationsPopUpButton indexOfItem:itemToRemove]];
			}
		}
	}
}

- (void)addRunningApplicationToPopupButton:(NSRunningApplication *)newRunningApplication
{
	// Don't add ourselves
	if (newRunningApplication.processIdentifier != NSRunningApplication.currentApplication.processIdentifier)
	{
		// Check if a dead application can be 'revived'
		for (NSMenuItem *menuItem in self.runningApplicationsPopUpButton.itemArray)
		{
			ZGProcess *process = menuItem.representedObject;
			if (process == self.currentProcess &&
				self.currentProcess.processID == NON_EXISTENT_PID_NUMBER &&
				[self.currentProcess.name isEqualToString:newRunningApplication.localizedName])
			{
				self.currentProcess.processID = newRunningApplication.processIdentifier;
				self.currentProcess.is64Bit = (newRunningApplication.executableArchitecture == NSBundleExecutableArchitectureX86_64);
				menuItem.title = [NSString stringWithFormat:@"%@ (%d)", self.currentProcess.name, self.currentProcess.processID];
				
				NSImage *iconImage = [[newRunningApplication icon] copy];
				iconImage.size = NSMakeSize(16, 16);
				menuItem.image = iconImage;
				
				[self runningApplicationsPopUpButtonRequest:nil];
				self.searchButton.enabled = YES;
				return;
			}
		}
		
		// Otherwise add the new application
		NSMenuItem *menuItem = [[NSMenuItem alloc] init];
		menuItem.title = [NSString stringWithFormat:@"%@ (%d)", newRunningApplication.localizedName, newRunningApplication.processIdentifier];
		
		NSImage *iconImage = [[newRunningApplication icon] copy];
		iconImage.size = NSMakeSize(16, 16);
		menuItem.image = iconImage;
		
		ZGProcess *representedProcess =
			[[ZGProcess alloc]
			 initWithName:newRunningApplication.localizedName
			 processID:newRunningApplication.processIdentifier
			 set64Bit:(newRunningApplication.executableArchitecture == NSBundleExecutableArchitectureX86_64)];
		
		menuItem.representedObject = representedProcess;
		
		[self.runningApplicationsPopUpButton.menu addItem:menuItem];
		
		// If we found desired process name, select it
		if (![self.currentProcess.name isEqualToString:self.desiredProcessName] &&
			[self.desiredProcessName isEqualToString:newRunningApplication.localizedName])
		{
			[self.runningApplicationsPopUpButton selectItem:menuItem];
			[self runningApplicationsPopUpButtonRequest:nil];
		}
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (object == NSWorkspace.sharedWorkspace && self.runningApplicationsPopUpButton.itemArray.count > 0)
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

- (void)updateClearButton
{
	self.clearButton.enabled = (self.watchVariablesArray.count > 0);
}

- (IBAction)qualifierMatrixButtonRequest:(id)sender
{
	ZGVariableQualifier newQualifier = (ZGVariableQualifier)[self.variableQualifierMatrix.selectedCell tag];
	
	for (ZGVariable *variable in self.watchVariablesArray)
	{
		switch (variable.type)
		{
			case ZGInt8:
			case ZGInt16:
			case ZGInt32:
			case ZGInt64:
				variable.qualifier = newQualifier;
				[variable updateStringValue];
				break;
			default:
				break;
		}
	}
	
	[self.tableController.watchVariablesTableView reloadData];
	
	[self markDocumentChange];
}

- (void)updateFlagsRangeTextField
{
	ZGFunctionType functionType = (ZGFunctionType)self.functionPopUpButton.selectedItem.tag;
	
	if (functionType == ZGGreaterThan || functionType == ZGGreaterThanStored)
	{
		self.flagsLabel.stringValue = @"Below:";
		
		if (self.searchController.searchData.lastBelowRangeValue)
		{
			self.flagsTextField.stringValue = self.searchController.searchData.lastBelowRangeValue;
		}
		else
		{
			self.flagsTextField.stringValue = @"";
		}
	}
	else if (functionType == ZGLessThan || functionType == ZGLessThanStored)
	{
		self.flagsLabel.stringValue = @"Above:";
		
		if (self.searchController.searchData.lastAboveRangeValue)
		{
			self.flagsTextField.stringValue = self.searchController.searchData.lastAboveRangeValue;
		}
		else
		{
			self.flagsTextField.stringValue = @"";
		}
	}	
}

- (void)updateFlags
{
	ZGVariableType dataType = (ZGVariableType)self.dataTypesPopUpButton.selectedItem.tag;
	ZGFunctionType functionType = (ZGFunctionType)self.functionPopUpButton.selectedItem.tag;
	
	if (dataType == ZGUTF8String || dataType == ZGUTF16String)
	{
		self.flagsTextField.enabled = NO;
		self.flagsTextField.stringValue = @"";
		self.flagsLabel.stringValue = @"Flags:";
		self.flagsLabel.textColor = NSColor.disabledControlTextColor;
	}
	else if (dataType == ZGFloat || dataType == ZGDouble)
	{
		self.flagsTextField.enabled = YES;
		self.flagsLabel.textColor = NSColor.controlTextColor;
		
		if (functionType == ZGEquals || functionType == ZGNotEquals || functionType == ZGEqualsStored || functionType == ZGNotEqualsStored || functionType == ZGEqualsStoredPlus || functionType == ZGNotEqualsStoredPlus)
		{
			// epsilon
			self.flagsLabel.stringValue = @"Epsilon:";
			if (self.searchController.searchData.lastEpsilonValue)
			{
				self.flagsTextField.stringValue = self.searchController.searchData.lastEpsilonValue;
			}
			else
			{
				self.flagsTextField.stringValue = @"";
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
			self.flagsTextField.enabled = NO;
			self.flagsTextField.stringValue = @"";
			self.flagsLabel.stringValue = @"Flags:";
			self.flagsLabel.textColor = NSColor.disabledControlTextColor;
		}
		else
		{
			// range
			[self updateFlagsRangeTextField];
			
			self.flagsTextField.enabled = YES;
			self.flagsLabel.textColor = NSColor.controlTextColor;
		}
	}
}

static NSSize *expandedWindowMinSize = nil;
- (IBAction)optionsDisclosureButton:(id)sender
{
    NSRect windowFrame = self.watchWindow.frame;
	
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
		
		*expandedWindowMinSize = self.watchWindow.minSize;
	}
	
	// This occurs when sender is nil (when we call it in code), or when
	// it's called by another action (eg: the "Options" label button)
	if (sender != self.optionsDisclosureButton)
	{
		self.optionsDisclosureButton.state = (self.optionsDisclosureButton.state == NSOnState ? NSOffState : NSOnState);
	}
	
	switch (self.optionsDisclosureButton.state)
	{
		case NSOnState:
			// Check if we need to resize based on the relative position between the functionPopUpButton and the optionsView
			// If so, this means that the functionPopUpButton's y origin > optionsView y origin
			if (self.optionsView.frame.origin.y < self.functionPopUpButton.frame.origin.y + self.functionPopUpButton.frame.size.height + 6)
			{
				// Resize the window to its the minimum size when the disclosure triangle is expanded
				windowFrame.size.height += (self.functionPopUpButton.frame.origin.y + self.functionPopUpButton.frame.size.height + 6) - self.optionsView.frame.origin.y;
				windowFrame.origin.y -= (self.functionPopUpButton.frame.origin.y + self.functionPopUpButton.frame.size.height + 6) - self.optionsView.frame.origin.y;
				
				[self.watchWindow
				 setFrame:windowFrame
				 display:YES
				 animate:YES];
			}
			
			self.optionsView.hidden = NO;
			
			self.watchWindow.minSize = *expandedWindowMinSize;
			break;
		case NSOffState:
			self.optionsView.hidden = YES;
			
			// Only resize when the window is at the minimum size
			if (windowFrame.size.height == [self.watchWindow minSize].height)
			{
				windowFrame.size.height -= self.optionsView.frame.size.height + 6;
				windowFrame.origin.y += self.optionsView.frame.size.height + 6;
				
				[self.watchWindow
				 setFrame:windowFrame
				 display:YES
				 animate:YES];
			}
			
			NSSize minSize = *expandedWindowMinSize;
			minSize.height -= self.optionsView.frame.size.height + 6;
			self.watchWindow.minSize = minSize;
			break;
		default:
			break;
	}
	
	[NSUserDefaults.standardUserDefaults
	 setBool:self.optionsDisclosureButton.state
	 forKey:ZG_EXPAND_OPTIONS];
}

- (void)watchWindowWillExitFullScreen:(NSNotificationCenter *)notification
{
	self.optionsView.hidden = YES;
}

- (void)watchWindowDidExitFullScreen:(NSNotification *)notification
{
	if (expandedWindowMinSize && self.watchWindow.minSize.height == expandedWindowMinSize->height)
	{
		if (self.watchWindow.frame.size.height < expandedWindowMinSize->height)
		{
			self.optionsDisclosureButton.state = NSOffState;
			[self optionsDisclosureButton:nil];
		}
		else
		{
			self.optionsView.hidden = NO;
		}
	}
}

- (void)selectDataTypeWithTag:(ZGVariableType)newTag recordUndo:(BOOL)recordUndo
{
	if (self.currentSearchDataType != newTag)
	{
		[self.dataTypesPopUpButton selectItemWithTag:newTag];
		
		self.functionPopUpButton.enabled = YES;
		self.variableQualifierMatrix.enabled = YES;

		if (newTag == ZGUTF8String || newTag == ZGUTF16String)
		{
			self.ignoreCaseCheckBox.enabled = YES;
			self.includeNullTerminatorCheckBox.enabled = YES;
		}
		else
		{
			self.ignoreCaseCheckBox.enabled = NO;
			self.ignoreCaseCheckBox.state = NSOffState;
			
			self.includeNullTerminatorCheckBox.enabled = NO;
			self.includeNullTerminatorCheckBox.state = NSOffState;
		}
		
		self.ignoreDataAlignmentCheckBox.enabled = (newTag != ZGUTF8String && newTag != ZGInt8);

		[self updateFlags];

		if (recordUndo)
		{
			[self.undoManager setActionName:@"Data Type Change"];
			[[self.undoManager prepareWithInvocationTarget:self]
			 selectDataTypeWithTag:self.currentSearchDataType
			 recordUndo:YES];
		}
		
		self.currentSearchDataType = newTag;
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
	switch (self.functionPopUpButton.selectedItem.tag)
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
	return [self isFunctionTypeStore:self.functionPopUpButton.selectedItem.tag];
}

- (void)functionTypePopUpButtonRequest:(id)sender markChanges:(BOOL)shouldMarkChanges
{
	[self updateFlags];
	
	if (![self doesFunctionTypeAllowSearchInput])
	{
		self.searchValueTextField.enabled = NO;
		self.searchValueLabel.textColor = NSColor.disabledControlTextColor;
	}
	else
	{
		self.searchValueTextField.enabled = YES;
		self.searchValueLabel.textColor = NSColor.controlTextColor;
		[self.watchWindow makeFirstResponder:self.searchValueTextField];
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
	if (self.undoManager.isUndoing || self.undoManager.isRedoing)
	{
		// Clear the status
		self.generalStatusTextField.stringValue = @"";
		
		[[self.undoManager prepareWithInvocationTarget:self] setWatchVariablesArrayAndUpdateInterface:self.watchVariablesArray];
	}
	
	self.watchVariablesArray = newWatchVariablesArray;
	[self.tableController.watchVariablesTableView reloadData];
	
	// Make sure the search value field is enabled if we aren't doing a store comparison
	if ([self doesFunctionTypeAllowSearchInput])
	{
		self.searchValueTextField.enabled = YES;
		self.searchValueLabel.textColor = [NSColor controlTextColor];
	}
	
	[self updateClearButton];
}

#pragma mark Menu item validation

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	if (menuItem.action == @selector(clearSearchValues:))
	{
		if (!self.clearButton.isEnabled)
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(removeSelectedSearchValues:))
	{
		if (self.tableController.watchVariablesTableView.selectedRow < 0 || self.watchWindow.firstResponder != self.tableController.watchVariablesTableView)
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(freezeVariables:))
	{
		if (self.watchVariablesArray.count > 0)
		{
			// All the variables selected need to either be all unfrozen or all frozen
			BOOL isFrozen = [[self.watchVariablesArray objectAtIndex:self.tableController.watchVariablesTableView.selectedRow] isFrozen];
			BOOL isInconsistent = NO;
			
			NSUInteger currentIndex = self.tableController.watchVariablesTableView.selectedRowIndexes.firstIndex;
			while (currentIndex != NSNotFound)
			{
				ZGVariable *variable = [self.watchVariablesArray objectAtIndex:currentIndex];
				// we should also check if the variable has an existing value at all
				if (variable && (variable.isFrozen != isFrozen || !variable.value))
				{
					isInconsistent = YES;
					break;
				}
				currentIndex = [self.tableController.watchVariablesTableView.selectedRowIndexes indexGreaterThanIndex:currentIndex];
			}
			
			NSString *title = isFrozen ? @"Unfreeze Variable" : @"Freeze Variable";
			
			if ([[self.tableController.watchVariablesTableView selectedRowIndexes] count] > 1)
			{
				title = [title stringByAppendingString:@"s"];
			}
			
			menuItem.title = title;
			
			if (isInconsistent || !self.clearButton.isEnabled)
			{
				return NO;
			}
		}
		else
		{
			menuItem.title = @"Freeze Variables";
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(addVariable:))
	{
		if (![self.searchController canStartTask])
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(undo:))
	{
		if ([self.searchController canCancelTask])
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(copy:))
	{
		if (self.tableController.watchVariablesTableView.selectedRowIndexes.count == 0)
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(paste:))
	{
		if ([self.searchController canCancelTask] || ![NSPasteboard.generalPasteboard dataForType:ZGVariablePboardType])
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(pauseOrUnpauseProcess:))
	{
		if (!self.currentProcess || self.currentProcess.processID == NON_EXISTENT_PID_NUMBER)
		{
			return NO;
		}
		
		menuItem.title = [ZGProcess.frozenProcesses containsObject:@(self.currentProcess.processID)] ? @"Unpause Target" : @"Pause Target";
	}
	
	else if (menuItem.action == @selector(editVariablesValue:))
	{
		menuItem.title = self.tableController.watchVariablesTableView.selectedRowIndexes.count != 1 ? @"Edit Variable Values…" : @"Edit Variable Value…";
		
		if ([self.searchController canCancelTask] || self.tableController.watchVariablesTableView.selectedRow == -1 || self.currentProcess.processID == NON_EXISTENT_PID_NUMBER)
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(editVariablesAddress:))
	{
		if ([self.searchController canCancelTask] || self.tableController.watchVariablesTableView.selectedRow == -1 || self.currentProcess.processID == NON_EXISTENT_PID_NUMBER)
		{
			return NO;
		}
	}
    
    else if (menuItem.action == @selector(editVariablesSize:))
    {
		menuItem.title = self.tableController.watchVariablesTableView.selectedRowIndexes.count != 1 ? @"Edit Variable Sizes…" : @"Edit Variable Size…";
		
		if ([self.searchController canCancelTask] || self.tableController.watchVariablesTableView.selectedRow == -1 || self.currentProcess.processID == NON_EXISTENT_PID_NUMBER)
		{
			return NO;
		}
		
		// All selected variables must be Byte Array's
		NSArray *selectedVariables = [self.watchVariablesArray objectsAtIndexes:self.tableController.watchVariablesTableView.selectedRowIndexes];
		for (ZGVariable *variable in selectedVariables)
		{
			if (variable.type != ZGByteArray)
			{
				return NO;
			}
		}
	}
	
	else if (menuItem.action == @selector(memoryDumpRangeRequest:) || menuItem.action == @selector(memoryDumpAllRequest:) || menuItem.action == @selector(storeAllValues:) || menuItem.action == @selector(changeMemoryProtection:))
	{
		if ([self.searchController canCancelTask] || self.currentProcess.processID == NON_EXISTENT_PID_NUMBER)
		{
			return NO;
		}
	}
	else if (menuItem.action == @selector(functionTypePopUpButtonRequest:))
	{
		if ([self isFunctionTypeStore:menuItem.tag] && !self.searchController.searchData.savedData)
		{
			return NO;
		}
	}
	
	return [super validateMenuItem:menuItem];
}

#pragma mark Search Handling

- (IBAction)clearSearchValues:(id)sender
{
	[self.searchController clear];
}

- (IBAction)searchValue:(id)sender
{
	[self.searchController search];
}

- (IBAction)storeAllValues:(id)sender
{
	[self.searchController storeAllValues];
}

#pragma mark Variables Handling

- (IBAction)freezeVariables:(id)sender
{
	[self.variableController freezeVariables];
}

- (IBAction)copy:(id)sender
{
	[self.variableController copyVariables];
}

- (IBAction)paste:(id)sender
{
	[self.variableController pasteVariables];
}

- (IBAction)removeSelectedSearchValues:(id)sender
{
	[self.variableController removeSelectedSearchValues];
}

- (IBAction)addVariable:(id)sender
{
	[self.variableController addVariable:sender];
}

- (IBAction)editVariablesValue:(id)sender
{
	[self.variableController editVariablesValueRequest];
}

- (IBAction)editVariablesAddress:(id)sender
{
	[self.variableController editVariablesAddressRequest];
}

- (IBAction)editVariablesSize:(id)sender
{
	[self.variableController editVariablesSizeRequest];
}

#pragma mark Memory Dump Handling

- (IBAction)memoryDumpRangeRequest:(id)sender
{
	[self.memoryDumpController memoryDumpRangeRequest];
}

- (IBAction)memoryDumpAllRequest:(id)sender
{
	[self.memoryDumpController memoryDumpAllRequest];
}

#pragma mark Memory Protection Handling

- (IBAction)changeMemoryProtection:(id)sender
{
	[self.memoryProtectionController changeMemoryProtectionRequest];
}

#pragma mark Pausing and Unpausing Processes

- (IBAction)pauseOrUnpauseProcess:(id)sender
{
	[ZGProcess pauseOrUnpauseProcess:self.currentProcess.processID];
}

@end
