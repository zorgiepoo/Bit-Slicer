//
//  ZGDocumentSearchController.m
//  Bit Slicer
//
//  Created by Mayur Pawashe on 7/21/12.
//  Copyright (c) 2012 zgcoder. All rights reserved.
//

#import "ZGDocumentSearchController.h"
#import "ZGDocument.h"
#import "ZGProcess.h"
#import "ZGDocumentTableController.h"
#import "ZGVariableController.h"
#import "ZGVirtualMemory.h"
#import "ZGSearchData.h"
#import "ZGCalculator.h"
#import "ZGUtilities.h"
#import "ZGTimer.h"

@interface ZGDocumentSearchController ()

@property (retain, nonatomic, readwrite) ZGTimer *searchUserInterfaceTimer;
@property (assign) IBOutlet ZGDocument *document;

@end

@implementation ZGDocumentSearchController

#pragma mark Birth & Death

- (id)init
{
	self = [super init];
	
	if (self)
	{
		_searchData = [[ZGSearchData alloc] init];
	}
	
	return self;
}

- (void)dealloc
{
	self.userInterfaceTimer = nil;
	
	[_searchData release];
	[super dealloc];
}

- (void)setUserInterfaceTimer:(ZGTimer *)newTimer
{
	if (_searchUserInterfaceTimer)
	{
		[_searchUserInterfaceTimer invalidate];
		[_searchUserInterfaceTimer release];
	}
	
	_searchUserInterfaceTimer = [newTimer retain];
}

- (void)createUserInterfaceTimer
{
	self.userInterfaceTimer =
		[[[ZGTimer alloc]
		  initWithTimeInterval:USER_INTERFACE_UPDATE_TIME_INTERVAL
		  target:self
		  selector:@selector(updateSearchUserInterface:)] autorelease];
}

#pragma mark Confirm search input

- (NSString *)testSearchComponent:(NSString *)searchComponent
{
	return isValidNumber(searchComponent) ? nil : @"The function you are using requires the search value to be a valid expression."; 
}

- (NSString *)confirmSearchInput:(NSString *)expression
{
	ZGVariableType dataType = (ZGVariableType)self.document.dataTypesPopUpButton.selectedItem.tag;
	ZGFunctionType functionType = (ZGFunctionType)self.document.functionPopUpButton.selectedItem.tag;
	
	if (dataType != ZGUTF8String && dataType != ZGUTF16String && dataType != ZGByteArray)
	{
		// This doesn't matter if the search is comparing stored values or if it's a regular function type
		if ([self.document doesFunctionTypeAllowSearchInput])
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
	
	if ((dataType == ZGUTF8String || dataType == ZGUTF16String || dataType == ZGByteArray) && [self.searchData shouldCompareStoredValues])
	{
		return [NSString stringWithFormat:@"Comparing Stored Values is not supported for %@.", dataType == ZGByteArray ? @"Byte Arrays" : @"Strings"];
	}
	
	return nil;
}

#pragma mark Report information

- (BOOL)isInNarrowSearchMode
{
	ZGVariableType dataType = (ZGVariableType)self.document.dataTypesPopUpButton.selectedItem.tag;
	
	BOOL goingToNarrowDownSearches = NO;
	for (ZGVariable *variable in self.document.watchVariablesArray)
	{
		if (variable.shouldBeSearched && variable.type == dataType)
		{
			goingToNarrowDownSearches = YES;
			break;
		}
	}
	
	return goingToNarrowDownSearches;
}

- (BOOL)canStartTask
{
	return [self.document.searchButton.title isEqualToString:@"Search"];
}

- (BOOL)canCancelTask
{
	return [self.document.searchButton.title isEqualToString:@"Cancel"];
}

#pragma mark Preparing and resuming from tasks

- (void)prepareTask
{
	self.document.runningApplicationsPopUpButton.enabled = NO;
	self.document.dataTypesPopUpButton.enabled = NO;
	self.document.variableQualifierMatrix.enabled = NO;
	self.document.searchValueTextField.enabled = NO;
	self.document.flagsTextField.enabled = NO;
	self.document.functionPopUpButton.enabled = NO;
	self.document.clearButton.enabled = NO;
	self.document.searchButton.title = @"Cancel";
	self.document.searchButton.keyEquivalent = @"\e";
	self.document.scanUnwritableValuesCheckBox.enabled = NO;
	self.document.ignoreDataAlignmentCheckBox.enabled = NO;
	self.document.ignoreCaseCheckBox.enabled = NO;
	self.document.includeNullTerminatorCheckBox.enabled = NO;
	self.document.beginningAddressTextField.enabled = NO;
	self.document.endingAddressTextField.enabled = NO;
	self.document.beginningAddressLabel.textColor = NSColor.disabledControlTextColor;
	self.document.endingAddressLabel.textColor = NSColor.disabledControlTextColor;
}

- (void)resumeFromTask
{
	self.document.clearButton.enabled = YES;
	
	self.document.dataTypesPopUpButton.enabled = YES;
    
	if ([self.document doesFunctionTypeAllowSearchInput])
	{
		self.document.searchValueTextField.enabled = YES;
	}
	self.document.searchButton.enabled = YES;
	self.document.searchButton.title = @"Search";
	self.document.searchButton.keyEquivalent = @"\r";
	
	[self.document updateFlags];
	
	self.document.variableQualifierMatrix.enabled = YES;
	self.document.functionPopUpButton.enabled = YES;
	
	self.document.scanUnwritableValuesCheckBox.enabled = YES;
	
	ZGVariableType dataType = (ZGVariableType)self.document.dataTypesPopUpButton.selectedItem.tag;
	
	if (dataType != ZGUTF8String && dataType != ZGInt8)
	{
		self.document.ignoreDataAlignmentCheckBox.enabled = YES;
	}
	
	if (dataType == ZGUTF8String || dataType == ZGUTF16String)
	{
		self.document.ignoreCaseCheckBox.enabled = YES;
		self.document.includeNullTerminatorCheckBox.enabled = YES;
	}
	
	self.document.beginningAddressTextField.enabled = YES;
	self.document.endingAddressTextField.enabled = YES;
	self.document.beginningAddressLabel.textColor = NSColor.controlTextColor;
	self.document.endingAddressLabel.textColor = NSColor.controlTextColor;
	
	self.document.runningApplicationsPopUpButton.enabled = YES;
	
	[self.document.watchWindow makeFirstResponder:self.document.searchValueTextField];
	
	if (self.document.currentProcess.processID == NON_EXISTENT_PID_NUMBER)
	{
		[self.document removeRunningApplicationFromPopupButton:nil];
	}
}

#pragma mark Update UI

- (void)updateNumberOfVariablesFoundDisplay
{
	NSNumberFormatter *numberOfVariablesFoundFormatter = [[NSNumberFormatter alloc] init];
	numberOfVariablesFoundFormatter.format = @"#,###";
	self.document.generalStatusTextField.stringValue = [NSString stringWithFormat:@"Found %@ value%@...", [numberOfVariablesFoundFormatter stringFromNumber:@(self.document.currentProcess.numberOfVariablesFound)], self.document.currentProcess.numberOfVariablesFound != 1 ? @"s" : @""];
	[numberOfVariablesFoundFormatter release];
}

- (void)updateSearchUserInterface:(NSTimer *)timer
{
	if (self.document.windowForSheet.isVisible)
	{
		if (!ZGSearchIsCancelling(self.searchData))
		{
			self.document.searchingProgressIndicator.doubleValue = (double)self.document.currentProcess.searchProgress;
			[self updateNumberOfVariablesFoundDisplay];
		}
		else
		{
			self.document.generalStatusTextField.stringValue = @"Cancelling search...";
		}
	}
}

- (void)updateMemoryStoreUserInterface:(NSTimer *)timer
{
	if (self.document.windowForSheet.isVisible)
	{
		self.document.searchingProgressIndicator.doubleValue = self.document.currentProcess.searchProgress;
	}
}

#pragma mark Searching

- (void)clear
{
	[self.document.undoManager removeAllActions];
	
	self.document.runningApplicationsPopUpButton.enabled = YES;
	self.document.dataTypesPopUpButton.enabled = YES;
	self.document.variableQualifierMatrix.enabled = YES;
	
	if (self.document.currentProcess.processID != NON_EXISTENT_PID_NUMBER)
	{
		self.document.searchButton.enabled = YES;
	}
	
	self.document.watchVariablesArray = [NSArray array];
	[self.document.tableController.watchVariablesTableView reloadData];
	
	if ([self.document doesFunctionTypeAllowSearchInput])
	{
		self.document.searchValueTextField.enabled = YES;
	}
	
	self.document.clearButton.enabled = NO;
	
	if (self.document.currentProcess.processID != NON_EXISTENT_PID_NUMBER)
	{
		self.document.generalStatusTextField.stringValue = @"Cleared search.";
	}
	
	[self.document markDocumentChange];
}

- (void)searchCleanUp:(NSArray *)newVariablesArray
{
	if (newVariablesArray.count != self.document.watchVariablesArray.count)
	{
		self.document.undoManager.actionName = @"Search";
		[[self.document.undoManager prepareWithInvocationTarget:self.document] setWatchVariablesArrayAndUpdateInterface:self.document.watchVariablesArray];
	}
	
	self.document.currentProcess.searchProgress = 0;
	if (ZGSearchDidCancelSearch(self.searchData))
	{
		self.document.searchingProgressIndicator.doubleValue = self.document.currentProcess.searchProgress;
		self.document.generalStatusTextField.stringValue = @"Search canceled.";
	}
	else
	{
		ZGInitializeSearch(self.searchData);
		[self updateSearchUserInterface:nil];
		
		self.document.watchVariablesArray = [NSArray arrayWithArray:newVariablesArray];
		
		[self.document.tableController.watchVariablesTableView reloadData];
	}
	
	[self resumeFromTask];
}

- (void)search
{
	ZGVariableType dataType = (ZGVariableType)self.document.dataTypesPopUpButton.selectedItem.tag;
	
	BOOL goingToNarrowDownSearches = self.isInNarrowSearchMode;
	
	if ([self canStartTask])
	{
		// Find all variables that are set to be searched, but shouldn't be
		// this is if the variable's data type does not match, or if the variable
		// is frozen
		for (ZGVariable *variable in self.document.watchVariablesArray)
		{
			if (variable.shouldBeSearched && (variable.type != dataType || variable.isFrozen))
			{
				variable.shouldBeSearched = NO;
			}
		}
		
		// Re-display in case we set variables to not be searched
		self.document.tableController.watchVariablesTableView.needsDisplay = YES;
		
		// Basic search information
		ZGMemorySize dataSize = 0;
		void *searchValue = NULL;
		
		// Set default search arguments
		self.searchData.epsilon = DEFAULT_FLOATING_POINT_EPSILON;
		self.searchData.rangeValue = NULL;
		
		self.searchData.shouldIgnoreStringCase = self.document.ignoreCaseCheckBox.state;
		self.searchData.shouldIncludeNullTerminator = self.document.includeNullTerminatorCheckBox.state;
		self.searchData.shouldCompareStoredValues = self.document.isFunctionTypeStore;
		
		NSString *evaluatedSearchExpression = nil;
		NSString *inputErrorMessage = nil;
		
		evaluatedSearchExpression =
			(dataType == ZGUTF8String || dataType == ZGUTF16String || dataType == ZGByteArray)
			? self.document.searchValueTextField.stringValue
			: [ZGCalculator evaluateExpression:self.document.searchValueTextField.stringValue];
		
		inputErrorMessage = [self confirmSearchInput:evaluatedSearchExpression];
		
		if (inputErrorMessage)
		{
			NSRunAlertPanel(@"Invalid Input", inputErrorMessage, nil, nil, nil);
			return;
		}
		
		// get search value and data size
		searchValue = valueFromString(self.document.currentProcess, evaluatedSearchExpression, dataType, &dataSize);
		
		// We want to read the null terminator in this case... even though we normally don't store the terminator
		// internally for UTF-16 strings. Lame hack, I know.
		if (self.searchData.shouldIncludeNullTerminator && dataType == ZGUTF16String)
		{
			dataSize += sizeof(unichar);
		}
		
		ZGFunctionType functionType = (ZGFunctionType)self.document.functionPopUpButton.selectedItem.tag;
		
		if (searchValue && ![self.document doesFunctionTypeAllowSearchInput])
		{
			free(searchValue);
			searchValue = NULL;
		}
		
		BOOL flagsFieldIsBlank = [[self.document.flagsTextField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] isEqualToString:@""];
		
		if (self.document.flagsTextField.isEnabled)
		{
			NSString *flagsExpression =
				(dataType == ZGUTF8String || dataType == ZGUTF16String || dataType == ZGByteArray)
				? self.document.flagsTextField.stringValue
				: [ZGCalculator evaluateExpression:self.document.flagsTextField.stringValue];
			
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
						self.searchData.rangeValue = valueFromString(self.document.currentProcess, flagsExpression, dataType, &rangeDataSize);
					}
					else
					{
						self.searchData.rangeValue = NULL;
					}
					
					if (functionType == ZGGreaterThan || functionType == ZGGreaterThanStored)
					{
						self.searchData.lastBelowRangeValue = self.document.flagsTextField.stringValue;
					}
					else if (functionType == ZGLessThan || functionType == ZGLessThanStored)
					{
						self.searchData.lastAboveRangeValue = self.document.flagsTextField.stringValue;
					}
				}
				else
				{
					if (!flagsFieldIsBlank)
					{
						// Clearly an epsilon flag
						ZGMemorySize epsilonDataSize;
						void *epsilon = valueFromString(self.document.currentProcess, flagsExpression, ZGDouble, &epsilonDataSize);
						if (epsilon)
						{
							self.searchData.epsilon = *((double *)epsilon);
							free(epsilon);
						}
					}
					else
					{
						self.searchData.epsilon = DEFAULT_FLOATING_POINT_EPSILON;
					}
					
					self.searchData.lastEpsilonValue = self.document.flagsTextField.stringValue;
				}
			}
		}
		
		// Deal with beginning and ending addresses, if there are any
		
		NSString *calculatedBeginAddress = [ZGCalculator evaluateExpression:self.document.beginningAddressTextField.stringValue];
		NSString *calculatedEndAddress = [ZGCalculator evaluateExpression:self.document.endingAddressTextField.stringValue];
		
		if (![[self.document.beginningAddressTextField stringValue] isEqualToString:@""])
		{
			if ([self testSearchComponent:calculatedBeginAddress])
			{
				NSRunAlertPanel(@"Invalid Input", @"The expression in the beginning address field is not valid.", nil, nil, nil, nil);
				return;
			}
			
			self.searchData.beginAddress = memoryAddressFromExpression(calculatedBeginAddress);
		}
		else
		{
			self.searchData.beginAddress = 0x0;
		}
		
		if (![self.document.endingAddressTextField.stringValue isEqualToString:@""])
		{
			if ([self testSearchComponent:calculatedEndAddress])
			{
				NSRunAlertPanel(@"Invalid Input", @"The expression in the ending address field is not valid.", nil, nil, nil, nil);
				return;
			}
			
			self.searchData.endAddress = memoryAddressFromExpression(calculatedEndAddress);
		}
		else
		{
			self.searchData.endAddress = MAX_MEMORY_ADDRESS;
		}
		
		if (self.searchData.beginAddress >= self.searchData.endAddress)
		{
			NSRunAlertPanel(@"Invalid Input", @"The value in the beginning address field must be less than the value of the ending address field, or one or both of the fields can be omitted.", nil, nil, nil, nil);
			return;
		}
		
		NSMutableArray *temporaryVariablesArray = [[NSMutableArray alloc] init];
		
		// Add all variables whose value should not be searched for, first
		
		for (ZGVariable *variable in self.document.watchVariablesArray)
		{
			if (variable.isFrozen || variable.type != self.document.dataTypesPopUpButton.selectedItem.tag)
			{
				variable.shouldBeSearched = NO;
			}
			
			if (!variable.shouldBeSearched)
			{
				[temporaryVariablesArray addObject:variable];
			}
		}
		
		[self prepareTask];
		
		static BOOL (*compareFunctions[10])(ZGSearchData *, const void *, const void *, ZGVariableType, ZGMemorySize) =
		{
			equalFunction, notEqualFunction, greaterThanFunction, lessThanFunction, equalFunction, notEqualFunction, greaterThanFunction, lessThanFunction, equalPlusFunction, notEqualPlusFunction
		};
		
		BOOL (*compareFunction)(ZGSearchData *, const void *, const void *, ZGVariableType, ZGMemorySize) = compareFunctions[functionType];
        
		if (dataType == ZGByteArray)
		{
			[self.searchData setByteArrayFlags:allocateFlagsForByteArrayWildcards(evaluatedSearchExpression)];
		}
		
		if (functionType == ZGEqualsStoredPlus || functionType == ZGNotEqualsStoredPlus)
		{
			[self.searchData setCompareOffset:searchValue];
		}
		
		if (!goingToNarrowDownSearches)
		{
			int numberOfRegions = [self.document.currentProcess numberOfRegions];
			
			self.document.searchingProgressIndicator.maxValue = numberOfRegions;
			self.document.currentProcess.numberOfVariablesFound = 0;
			self.document.currentProcess.searchProgress = 0;
			
			[self createUserInterfaceTimer];
			
			ZGVariableQualifier qualifier =
				[[self.document.variableQualifierMatrix cellWithTag:SIGNED_BUTTON_CELL_TAG] state] == NSOnState
				? ZGSigned
				: ZGUnsigned;
			ZGMemorySize pointerSize =
				self.document.currentProcess.is64Bit
				? sizeof(int64_t)
				: sizeof(int32_t);
			
			ZGProcess *currentProcess = self.document.currentProcess;
			search_for_data_t searchForDataCallback = ^(void *variableData, void *compareData, ZGMemoryAddress address, ZGMemorySize currentRegionNumber)
			{
				if (compareFunction(self.searchData, variableData, (compareData != NULL) ? compareData : searchValue, dataType, dataSize))
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
					
					currentProcess.numberOfVariablesFound++;
				}
				
				currentProcess.searchProgress = currentRegionNumber;
			};
			
			dispatch_block_t searchForDataCompleteBlock = ^
			{
				if (searchValue)
				{
					free(searchValue);
				}
				
				self.userInterfaceTimer = nil;
				
				[self searchCleanUp:temporaryVariablesArray];
				[temporaryVariablesArray release];
			};
			dispatch_block_t searchForDataBlock = ^
			{
				ZGMemorySize dataAlignment =
					(self.document.ignoreDataAlignmentCheckBox.state == NSOnState)
					? sizeof(int8_t)
					: ZGDataAlignment(self.document.currentProcess.is64Bit, dataType, dataSize);
				
				if (self.searchData.shouldCompareStoredValues)
				{
					ZGSearchForSavedData(currentProcess.processTask, dataAlignment, dataSize, self.searchData, searchForDataCallback);
				}
				else
				{
					self.searchData.shouldScanUnwritableValues = (self.document.scanUnwritableValuesCheckBox.state == NSOnState);
					ZGSearchForData(currentProcess.processTask, dataAlignment, dataSize, self.searchData, searchForDataCallback);
				}
				dispatch_async(dispatch_get_main_queue(), searchForDataCompleteBlock);
			};
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), searchForDataBlock);
		}
		else /* if (goingToNarrowDownSearches) */
		{
			ZGMemoryMap processTask = self.document.currentProcess.processTask;
			
			self.document.searchingProgressIndicator.maxValue = self.document.watchVariablesArray.count;
			self.document.currentProcess.searchProgress = 0;
			self.document.currentProcess.numberOfVariablesFound = 0;
			
			[self createUserInterfaceTimer];
			
			dispatch_block_t completeSearchBlock = ^
			{
				if (searchValue)
				{
					free(searchValue);
				}
				
				self.userInterfaceTimer = nil;
				
				[self searchCleanUp:temporaryVariablesArray];
				[temporaryVariablesArray release];
			};
			
			ZGProcess *currentProcess = self.document.currentProcess;
			dispatch_block_t searchBlock = ^
			{
				for (ZGVariable *variable in self.self.document.watchVariablesArray)
				{
					if (variable.shouldBeSearched)
					{
						if (variable.size > 0 && dataSize > 0 &&
							(self.searchData.beginAddress <= variable.address) &&
							(self.searchData.endAddress >= variable.address + dataSize))
						{
							ZGMemorySize outputSize = dataSize;
							void *variableValue = NULL;
							if (ZGReadBytes(processTask, variable.address, &variableValue, &outputSize))
							{
								void *compareValue = self.searchData.shouldCompareStoredValues ? ZGSavedValue(variable.address, self.searchData, dataSize) : searchValue;
								
								if (compareValue && compareFunction(self.searchData, variableValue, compareValue, dataType, dataSize))
								{
									[temporaryVariablesArray addObject:variable];
									currentProcess.numberOfVariablesFound++;
								}
								
								ZGFreeBytes(processTask, variableValue, outputSize);
							}
						}
					}
					
					if (ZGSearchDidCancelSearch(self.searchData))
					{
						break;
					}
					
					currentProcess.searchProgress++;
				}
				
				dispatch_async(dispatch_get_main_queue(), completeSearchBlock);
			};
			ZGInitializeSearch(self.searchData);
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), searchBlock);
		}
	}
	else
	{
		if (self.document.currentProcess.isDoingMemoryDump)
		{
			// Cancel memory dump
			self.document.currentProcess.isDoingMemoryDump = NO;
			self.document.generalStatusTextField.stringValue = @"Canceling Memory Dump...";
		}
		else if (self.document.currentProcess.isStoringAllData)
		{
			// Cancel memory store
			self.document.currentProcess.isStoringAllData = NO;
			self.document.generalStatusTextField.stringValue = @"Canceling Memory Store...";
		}
		else
		{
			// Cancel the search
			self.document.searchButton.enabled = NO;
			
			if (goingToNarrowDownSearches)
			{
				ZGCancelSearchImmediately(self.searchData);
			}
			else
			{
				ZGCancelSearch(self.searchData);
			}
		}
	}
}

#pragma mark Storing all values

- (void)storeAllValues
{
	if (self.document.currentProcess.isStoringAllData)
	{
		return;
	}
	
	[self prepareTask];
	
	self.document.searchingProgressIndicator.maxValue = self.document.currentProcess.numberOfRegions;
	
	[self createUserInterfaceTimer];
	
	self.document.generalStatusTextField.stringValue = @"Storing All Values...";
	
	dispatch_block_t searchForDataCompleteBlock = ^
	{self.
		self.userInterfaceTimer = nil;
		
		if (!self.document.currentProcess.isStoringAllData)
		{
			self.document.generalStatusTextField.stringValue = @"Canceled Memory Store";
		}
		else
		{
			self.document.currentProcess.isStoringAllData = NO;
			
			self.searchData.savedData = self.searchData.tempSavedData;
			self.searchData.tempSavedData = nil;
			
			self.document.generalStatusTextField.stringValue = @"Finished Memory Store";
		}
		self.document.searchingProgressIndicator.doubleValue = 0;
		[self resumeFromTask];
	};
	
	dispatch_block_t searchForDataBlock = ^
	{
		self.searchData.tempSavedData = ZGGetAllData(self.document.currentProcess, self.document.scanUnwritableValuesCheckBox.state);
		
		dispatch_async(dispatch_get_main_queue(), searchForDataCompleteBlock);
	};
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), searchForDataBlock);
}

@end
