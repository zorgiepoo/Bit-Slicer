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

@implementation ZGDocumentSearchController

@synthesize searchData;

#pragma mark Birth & Death

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
	[self setUserInterfaceTimer:nil];
	
	[searchData release];
	[super dealloc];
}

- (void)setUserInterfaceTimer:(ZGTimer *)newTimer
{
	if (updateSearchUserInterfaceTimer)
	{
		[updateSearchUserInterfaceTimer invalidate];
		[updateSearchUserInterfaceTimer release];
	}
	
	updateSearchUserInterfaceTimer = [newTimer retain];
}

- (void)createUserInterfaceTimer
{
	[self
	 setUserInterfaceTimer:
	 [[[ZGTimer alloc]
	   initWithTimeInterval:USER_INTERFACE_UPDATE_TIME_INTERVAL
	   target:self
	   selector:@selector(updateSearchUserInterface:)] autorelease]];
}

#pragma mark Confirm search input

- (NSString *)testSearchComponent:(NSString *)searchComponent
{
	return isValidNumber(searchComponent) ? nil : @"The function you are using requires the search value to be a valid expression."; 
}

- (NSString *)confirmSearchInput:(NSString *)expression
{
	ZGVariableType dataType = (ZGVariableType)[[[document dataTypesPopUpButton] selectedItem] tag];
	ZGFunctionType functionType = (ZGFunctionType)[[[document functionPopUpButton] selectedItem] tag];
	
	if (dataType != ZGUTF8String && dataType != ZGUTF16String && dataType != ZGByteArray)
	{
		// This doesn't matter if the search is comparing stored values or if it's a regular function type
		if ([document doesFunctionTypeAllowSearchInput])
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

#pragma mark Report information

- (BOOL)isInNarrowSearchMode
{
	ZGVariableType dataType = (ZGVariableType)[[[document dataTypesPopUpButton] selectedItem] tag];
	
	BOOL goingToNarrowDownSearches = NO;
	for (ZGVariable *variable in [document watchVariablesArray])
	{
		if ([variable shouldBeSearched] && [variable type] == dataType)
		{
			goingToNarrowDownSearches = YES;
			break;
		}
	}
	
	return goingToNarrowDownSearches;
}

- (BOOL)canStartTask
{
	return [[[document searchButton] title] isEqualToString:@"Search"];
}

- (BOOL)canCancelTask
{
	return [[[document searchButton] title] isEqualToString:@"Cancel"];
}

#pragma mark Preparing and resuming from tasks

- (void)prepareTask
{
	[[document runningApplicationsPopUpButton] setEnabled:NO];
	[[document dataTypesPopUpButton] setEnabled:NO];
	[[document variableQualifierMatrix] setEnabled:NO];
	[[document searchValueTextField] setEnabled:NO];
	[[document flagsTextField] setEnabled:NO];
	[[document functionPopUpButton] setEnabled:NO];
	[[document clearButton] setEnabled:NO];
	[[document searchButton] setTitle:@"Cancel"];
	[[document searchButton] setKeyEquivalent:@"\e"];
	[[document scanUnwritableValuesCheckBox] setEnabled:NO];
	[[document ignoreDataAlignmentCheckBox] setEnabled:NO];
	[[document ignoreCaseCheckBox] setEnabled:NO];
	[[document includeNullTerminatorCheckBox] setEnabled:NO];
	[[document beginningAddressTextField] setEnabled:NO];
	[[document endingAddressTextField] setEnabled:NO];
	[[document beginningAddressLabel] setTextColor:[NSColor disabledControlTextColor]];
	[[document endingAddressLabel] setTextColor:[NSColor disabledControlTextColor]];
}

- (void)resumeFromTask
{
	[[document clearButton] setEnabled:YES];
	
	[[document dataTypesPopUpButton] setEnabled:YES];
    
	if ([document doesFunctionTypeAllowSearchInput])
	{
		[[document searchValueTextField] setEnabled:YES];
	}
	[[document searchButton] setEnabled:YES];
	[[document searchButton] setTitle:@"Search"];
	[[document searchButton] setKeyEquivalent:@"\r"];
	
	[document updateFlags];
	
	[[document variableQualifierMatrix] setEnabled:YES];
	[[document functionPopUpButton] setEnabled:YES];
	
	[[document scanUnwritableValuesCheckBox] setEnabled:YES];
	
	ZGVariableType dataType = (ZGVariableType)[[[document dataTypesPopUpButton] selectedItem] tag];
	
	if (dataType != ZGUTF8String && dataType != ZGInt8)
	{
		[[document ignoreDataAlignmentCheckBox] setEnabled:YES];
	}
	
	if (dataType == ZGUTF8String || dataType == ZGUTF16String)
	{
		[[document ignoreCaseCheckBox] setEnabled:YES];
		[[document includeNullTerminatorCheckBox] setEnabled:YES];
	}
	
	[[document beginningAddressTextField] setEnabled:YES];
	[[document endingAddressTextField] setEnabled:YES];
	[[document beginningAddressLabel] setTextColor:[NSColor controlTextColor]];
	[[document endingAddressLabel] setTextColor:[NSColor controlTextColor]];
	
	[[document runningApplicationsPopUpButton] setEnabled:YES];
	
	[[document watchWindow] makeFirstResponder:[document searchValueTextField]];
	
	if ([[document currentProcess] processID] == NON_EXISTENT_PID_NUMBER)
	{
		[document removeRunningApplicationFromPopupButton:nil];
	}
}

#pragma mark Update UI

- (void)updateNumberOfVariablesFoundDisplay
{
	NSNumberFormatter *numberOfVariablesFoundFormatter = [[NSNumberFormatter alloc] init];
	[numberOfVariablesFoundFormatter setFormat:@"#,###"];
	[[document generalStatusTextField] setStringValue:[NSString stringWithFormat:@"Found %@ value%@...", [numberOfVariablesFoundFormatter stringFromNumber:[NSNumber numberWithInt:[[document currentProcess] numberOfVariablesFound]]], [[document currentProcess] numberOfVariablesFound] != 1 ? @"s" : @""]];
	[numberOfVariablesFoundFormatter release];
}

- (void)updateSearchUserInterface:(NSTimer *)timer
{
	if ([[document windowForSheet] isVisible])
	{
		if (!ZGSearchIsCancelling([self searchData]))
		{
			[[document searchingProgressIndicator] setDoubleValue:(double)[[document currentProcess] searchProgress]];
			[self updateNumberOfVariablesFoundDisplay];
		}
		else
		{
			[[document generalStatusTextField] setStringValue:@"Cancelling search..."];
		}
	}
}

- (void)updateMemoryStoreUserInterface:(NSTimer *)timer
{
	if ([[document windowForSheet] isVisible])
	{
		[[document searchingProgressIndicator] setDoubleValue:[[document currentProcess] searchProgress]];
	}
}

#pragma mark Searching

- (void)clear
{
	[[document undoManager] removeAllActions];
	
	[[document runningApplicationsPopUpButton] setEnabled:YES];
	[[document dataTypesPopUpButton] setEnabled:YES];
	[[document variableQualifierMatrix] setEnabled:YES];
	
	if ([[document currentProcess] processID] != NON_EXISTENT_PID_NUMBER)
	{
		[[document searchButton] setEnabled:YES];
	}
	
	[document setWatchVariablesArray:[NSArray array]];
	[[[document tableController] watchVariablesTableView] reloadData];
	
	if ([document doesFunctionTypeAllowSearchInput])
	{
		[[document searchValueTextField] setEnabled:YES];
	}
	
	[[document clearButton] setEnabled:NO];
	
	if ([[document currentProcess] processID] != NON_EXISTENT_PID_NUMBER)
	{
		[[document generalStatusTextField] setStringValue:@"Cleared search."];
	}
	
	[document markDocumentChange];
}

- (void)searchCleanUp:(NSArray *)newVariablesArray
{
	if ([newVariablesArray count] != [[document watchVariablesArray] count])
	{
		[[document undoManager] setActionName:@"Search"];
		[[[document undoManager] prepareWithInvocationTarget:document] setWatchVariablesArrayAndUpdateInterface:[document watchVariablesArray]];
	}
	
	[[document currentProcess] setSearchProgress:0];
	if (ZGSearchDidCancelSearch([self searchData]))
	{
		[[document searchingProgressIndicator] setDoubleValue:[[document currentProcess] searchProgress]];
		[[document generalStatusTextField] setStringValue:@"Search canceled."];
	}
	else
	{
		ZGInitializeSearch([self searchData]);
		[self updateSearchUserInterface:nil];
		
		[document setWatchVariablesArray:[NSArray arrayWithArray:newVariablesArray]];
		
		[[[document tableController] watchVariablesTableView] reloadData];
	}
	
	[self resumeFromTask];
}

- (void)search
{
	ZGVariableType dataType = (ZGVariableType)[[[document dataTypesPopUpButton] selectedItem] tag];
	
	BOOL goingToNarrowDownSearches = [self isInNarrowSearchMode];
	
	if ([self canStartTask])
	{
		// Find all variables that are set to be searched, but shouldn't be
		// this is if the variable's data type does not match, or if the variable
		// is frozen
		for (ZGVariable *variable in [document watchVariablesArray])
		{
			if ([variable shouldBeSearched] && (variable->type != dataType || variable->isFrozen))
			{
				[variable setShouldBeSearched:NO];
			}
		}
		
		// Re-display in case we set variables to not be searched
		[[[document tableController] watchVariablesTableView] setNeedsDisplay:YES];
		
		// Basic search information
		ZGMemorySize dataSize = 0;
		void *searchValue = NULL;
		
		// Set default search arguments
		[[self searchData] setEpsilon:DEFAULT_FLOATING_POINT_EPSILON];
		[searchData setRangeValue:NULL];
		
		[[self searchData] setShouldIgnoreStringCase:[[document ignoreCaseCheckBox] state]];
		[[self searchData] setShouldIncludeNullTerminator:[[document includeNullTerminatorCheckBox] state]];
		[[self searchData] setShouldCompareStoredValues:[document isFunctionTypeStore]];
		
		NSString *evaluatedSearchExpression = nil;
		NSString *inputErrorMessage = nil;
		
		evaluatedSearchExpression =
			(dataType == ZGUTF8String || dataType == ZGUTF16String || dataType == ZGByteArray)
			? [[document searchValueTextField] stringValue]
			: [ZGCalculator evaluateExpression:[[document searchValueTextField] stringValue]];
		
		inputErrorMessage = [self confirmSearchInput:evaluatedSearchExpression];
		
		if (inputErrorMessage)
		{
			NSRunAlertPanel(@"Invalid Input", inputErrorMessage, nil, nil, nil);
			return;
		}
		
		// get search value and data size
		searchValue = valueFromString([document currentProcess], evaluatedSearchExpression, dataType, &dataSize);
		
		// We want to read the null terminator in this case... even though we normally don't store the terminator
		// internally for UTF-16 strings. Lame hack, I know.
		if ([searchData shouldIncludeNullTerminator] && dataType == ZGUTF16String)
		{
			dataSize += sizeof(unichar);
		}
		
		ZGFunctionType functionType = (ZGFunctionType)[[[document functionPopUpButton] selectedItem] tag];
		
		if (searchValue && ![document doesFunctionTypeAllowSearchInput])
		{
			free(searchValue);
			searchValue = NULL;
		}
		
		BOOL flagsFieldIsBlank = [[[[document flagsTextField] stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] isEqualToString:@""];
		
		if ([[document flagsTextField] isEnabled])
		{
			NSString *flagsExpression =
				(dataType == ZGUTF8String || dataType == ZGUTF16String || dataType == ZGByteArray)
				? [[document flagsTextField] stringValue]
				: [ZGCalculator evaluateExpression:[[document flagsTextField] stringValue]];
			
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
						[[self searchData] setRangeValue:valueFromString([document currentProcess], flagsExpression, dataType, &rangeDataSize)];
					}
					else
					{
						[[self searchData] setRangeValue:NULL];
					}
					
					if (functionType == ZGGreaterThan || functionType == ZGGreaterThanStored)
					{
						[[self searchData] setLastBelowRangeValue:[[document flagsTextField] stringValue]];
					}
					else if (functionType == ZGLessThan || functionType == ZGLessThanStored)
					{
						[[self searchData] setLastAboveRangeValue:[[document flagsTextField] stringValue]];
					}
				}
				else
				{
					if (!flagsFieldIsBlank)
					{
						// Clearly an epsilon flag
						ZGMemorySize epsilonDataSize;
						void *epsilon = valueFromString([document currentProcess], flagsExpression, ZGDouble, &epsilonDataSize);
						if (epsilon)
						{
							[[self searchData] setEpsilon:*((double *)epsilon)];
							free(epsilon);
						}
					}
					else
					{
						[[self searchData] setEpsilon:DEFAULT_FLOATING_POINT_EPSILON];
					}
					
					[[self searchData] setLastEpsilonValue:[[document flagsTextField] stringValue]];
				}
			}
		}
		
		// Deal with beginning and ending addresses, if there are any
		
		NSString *calculatedBeginAddress = [ZGCalculator evaluateExpression:[[document beginningAddressTextField] stringValue]];
		NSString *calculatedEndAddress = [ZGCalculator evaluateExpression:[[document endingAddressTextField] stringValue]];
		
		if (![[[document beginningAddressTextField] stringValue] isEqualToString:@""])
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
		
		if (![[[document endingAddressTextField] stringValue] isEqualToString:@""])
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
		
		for (ZGVariable *variable in [document watchVariablesArray])
		{
			if ([variable isFrozen] || [variable type] != [[[document dataTypesPopUpButton] selectedItem] tag])
			{
				[variable setShouldBeSearched:NO];
			}
			
			if (!variable->shouldBeSearched)
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
			[[self searchData] setByteArrayFlags:allocateFlagsForByteArrayWildcards(evaluatedSearchExpression)];
		}
		
		if (functionType == ZGEqualsStoredPlus || functionType == ZGNotEqualsStoredPlus)
		{
			[[self searchData] setCompareOffset:searchValue];
		}
		
		if (!goingToNarrowDownSearches)
		{
			int numberOfRegions = [[document currentProcess] numberOfRegions];
			
			[[document searchingProgressIndicator] setMaxValue:numberOfRegions];
			[[document currentProcess] setNumberOfVariablesFound:0];
			[[document currentProcess] setSearchProgress:0];
			
			[self createUserInterfaceTimer];
			
			ZGVariableQualifier qualifier =
				[[[document variableQualifierMatrix] cellWithTag:SIGNED_BUTTON_CELL_TAG] state] == NSOnState
				? ZGSigned
				: ZGUnsigned;
			ZGMemorySize pointerSize =
				[[document currentProcess] is64Bit]
				? sizeof(int64_t)
				: sizeof(int32_t);
			
			ZGProcess *currentProcess = [document currentProcess];
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
				
				[self setUserInterfaceTimer:nil];
				
				[self searchCleanUp:temporaryVariablesArray];
				[temporaryVariablesArray release];
			};
			dispatch_block_t searchForDataBlock = ^
			{
				ZGMemorySize dataAlignment =
					([[document ignoreDataAlignmentCheckBox] state] == NSOnState)
					? sizeof(int8_t)
					: ZGDataAlignment([[document currentProcess] is64Bit], dataType, dataSize);
				
				if ([searchData shouldCompareStoredValues])
				{
					ZGSearchForSavedData([currentProcess processTask], dataAlignment, dataSize, searchData, searchForDataCallback);
				}
				else
				{
					[[self searchData] setShouldScanUnwritableValues:([[document scanUnwritableValuesCheckBox] state] == NSOnState)];
					ZGSearchForData([currentProcess processTask], dataAlignment, dataSize, searchData, searchForDataCallback);
				}
				dispatch_async(dispatch_get_main_queue(), searchForDataCompleteBlock);
			};
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), searchForDataBlock);
		}
		else /* if (goingToNarrowDownSearches) */
		{
			ZGMemoryMap processTask = [[document currentProcess] processTask];
			
			[[document searchingProgressIndicator] setMaxValue:[[document watchVariablesArray] count]];
			[[document currentProcess] setSearchProgress:0];
			[[document currentProcess] setNumberOfVariablesFound:0];
			
			[self createUserInterfaceTimer];
			
			dispatch_block_t completeSearchBlock = ^
			{
				if (searchValue)
				{
					free(searchValue);
				}
				
				[self setUserInterfaceTimer:nil];
				
				[self searchCleanUp:temporaryVariablesArray];
				[temporaryVariablesArray release];
			};
			
			ZGProcess *currentProcess = [document currentProcess];
			dispatch_block_t searchBlock = ^
			{
				for (ZGVariable *variable in [document watchVariablesArray])
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
		if ([[document currentProcess] isDoingMemoryDump])
		{
			// Cancel memory dump
			[[document currentProcess] setIsDoingMemoryDump:NO];
			[[document generalStatusTextField] setStringValue:@"Canceling Memory Dump..."];
		}
		else if ([[document currentProcess] isStoringAllData])
		{
			// Cancel memory store
			[[document currentProcess] setIsStoringAllData:NO];
			[[document generalStatusTextField] setStringValue:@"Canceling Memory Store..."];
		}
		else
		{
			// Cancel the search
			[[document searchButton] setEnabled:NO];
			
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

#pragma mark Storing all values

- (void)storeAllValues
{
	if ([[document currentProcess] isStoringAllData])
	{
		return;
	}
	
	[self prepareTask];
	
	[[document searchingProgressIndicator] setMaxValue:[[document currentProcess] numberOfRegions]];
	
	[self createUserInterfaceTimer];
	
	[[document generalStatusTextField] setStringValue:@"Storing All Values..."];
	
	dispatch_block_t searchForDataCompleteBlock = ^
	{
		[self setUserInterfaceTimer:nil];
		
		if (![[document currentProcess] isStoringAllData])
		{
			[[document generalStatusTextField] setStringValue:@"Canceled Memory Store"];
		}
		else
		{
			[[document currentProcess] setIsStoringAllData:NO];
			
			[[self searchData] setSavedData:[[self searchData] tempSavedData]];
			[[self searchData] setTempSavedData:nil];
			
			[[document generalStatusTextField] setStringValue:@"Finished Memory Store"];
		}
		[[document searchingProgressIndicator] setDoubleValue:0];
		[self resumeFromTask];
	};
	
	dispatch_block_t searchForDataBlock = ^
	{
		[searchData setTempSavedData:ZGGetAllData([document currentProcess], [[document scanUnwritableValuesCheckBox] state])];
		
		dispatch_async(dispatch_get_main_queue(), searchForDataCompleteBlock);
	};
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), searchForDataBlock);
}

@end
