/*
 * Created by Mayur Pawashe on 7/21/12.
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

#import "ZGDocumentSearchController.h"
#import "ZGDocumentWindowController.h"
#import "ZGProcess.h"
#import "ZGDocumentTableController.h"
#import "ZGDocumentBreakPointController.h"
#import "ZGVariableController.h"
#import "ZGVirtualMemory.h"
#import "ZGVirtualMemoryHelpers.h"
#import "ZGRegion.h"
#import "ZGSearchData.h"
#import "ZGSearchProgress.h"
#import "ZGSearchResults.h"
#import "ZGCalculator.h"
#import "ZGUtilities.h"
#import "ZGComparisonFunctions.h"
#import "NSArrayAdditions.h"
#import "ZGDocumentData.h"
#import "ZGSearchFunctions.h"

@interface ZGDocumentSearchController ()

@property (assign) ZGDocumentWindowController *windowController;
@property (strong, nonatomic, readwrite) NSTimer *userInterfaceTimer;
@property (readwrite, strong, nonatomic) ZGSearchProgress *searchProgress;
@property (nonatomic) ZGSearchResults *temporarySearchResults;
@property (nonatomic) NSArray *tempSavedData;
@property (assign) BOOL isBusy;

@end

@implementation ZGDocumentSearchController

#pragma mark Birth & Death

- (id)initWithWindowController:(ZGDocumentWindowController *)windowController
{
	self = [super init];
	
	if (self)
	{
		self.windowController = windowController;
		self.documentData = windowController.documentData;
		self.searchData = windowController.searchData;
		self.searchProgress = [[ZGSearchProgress alloc] init];
	}
	
	return self;
}

- (void)cleanUp
{
	self.userInterfaceTimer = nil;
	
	// Force canceling
	self.searchProgress.shouldCancelSearch = YES;
	[self.windowController.documentBreakPointController stopWatchingBreakPoints];
	
	self.windowController = nil;
}

- (void)setUserInterfaceTimer:(NSTimer *)newTimer
{
	[_userInterfaceTimer invalidate];
	_userInterfaceTimer = newTimer;
}

- (void)createUserInterfaceTimer
{
	self.userInterfaceTimer =
		[NSTimer
		 scheduledTimerWithTimeInterval:USER_INTERFACE_UPDATE_TIME_INTERVAL
		 target:self
		 selector:@selector(updateSearchUserInterface:)
		 userInfo:nil
		 repeats:YES];
}

#pragma mark Confirm search input

- (NSString *)testSearchComponent:(NSString *)searchComponent
{
	return isValidNumber(searchComponent) ? nil : @"The function you are using requires the search value to be a valid expression."; 
}

- (NSString *)confirmSearchInput:(NSString *)expression
{
	ZGVariableType dataType = (ZGVariableType)self.documentData.selectedDatatypeTag;
	ZGFunctionType functionType = (ZGFunctionType)self.documentData.functionTypeTag;
	
	if (dataType != ZGUTF8String && dataType != ZGUTF16String && dataType != ZGByteArray)
	{
		// This doesn't matter if the search is comparing stored values or if it's a regular function type
		if ([self.windowController functionTypeAllowsSearchInput])
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
	ZGVariableType dataType = (ZGVariableType)self.documentData.selectedDatatypeTag;
	
	BOOL goingToNarrowDownSearches = NO;
	for (ZGVariable *variable in self.documentData.variables)
	{
		if (variable.enabled && variable.type == dataType)
		{
			goingToNarrowDownSearches = YES;
			break;
		}
	}
	
	return goingToNarrowDownSearches;
}

- (BOOL)canStartTask
{
	return !self.isBusy;
}

- (BOOL)canCancelTask
{
	return self.isBusy;
}

#pragma mark Preparing and resuming from tasks

- (void)prepareTask
{
	[self prepareTaskWithEscapeTitle:@"Cancel"];
}

- (void)prepareTaskWithEscapeTitle:(NSString *)escapeTitle
{
	self.isBusy = YES;
	
	[self.windowController updateClearButton];
	
	self.windowController.runningApplicationsPopUpButton.enabled = NO;
	self.windowController.dataTypesPopUpButton.enabled = NO;
	self.windowController.variableQualifierMatrix.enabled = NO;
	self.windowController.searchValueTextField.enabled = NO;
	self.windowController.flagsTextField.enabled = NO;
	self.windowController.functionPopUpButton.enabled = NO;
	self.windowController.searchButton.title = escapeTitle;
	self.windowController.searchButton.keyEquivalent = @"\e";
	self.windowController.scanUnwritableValuesCheckBox.enabled = NO;
	self.windowController.ignoreDataAlignmentCheckBox.enabled = NO;
	self.windowController.ignoreCaseCheckBox.enabled = NO;
	self.windowController.includeNullTerminatorCheckBox.enabled = NO;
	self.windowController.beginningAddressTextField.enabled = NO;
	self.windowController.endingAddressTextField.enabled = NO;
	self.windowController.beginningAddressLabel.textColor = NSColor.disabledControlTextColor;
	self.windowController.endingAddressLabel.textColor = NSColor.disabledControlTextColor;
}

- (void)resumeFromTaskAndMakeSearchFieldFirstResponder:(BOOL)shouldMakeSearchFieldFirstResponder
{
	self.isBusy = NO;
	
	[self.windowController updateClearButton];
	
	self.windowController.dataTypesPopUpButton.enabled = YES;
    
	if ([self.windowController functionTypeAllowsSearchInput])
	{
		self.windowController.searchValueTextField.enabled = YES;
	}
	self.windowController.searchButton.enabled = YES;
	self.windowController.searchButton.keyEquivalent = @"\r";
	
	[self.windowController updateFlagsAndSearchButtonTitle];
	
	self.windowController.variableQualifierMatrix.enabled = YES;
	self.windowController.functionPopUpButton.enabled = YES;
	
	self.windowController.scanUnwritableValuesCheckBox.enabled = YES;
	
	ZGVariableType dataType = (ZGVariableType)self.documentData.selectedDatatypeTag;
	
	if (dataType != ZGUTF8String && dataType != ZGInt8)
	{
		self.windowController.ignoreDataAlignmentCheckBox.enabled = YES;
	}
	
	if (dataType == ZGUTF8String || dataType == ZGUTF16String)
	{
		self.windowController.ignoreCaseCheckBox.enabled = YES;
		self.windowController.includeNullTerminatorCheckBox.enabled = YES;
	}
	
	self.windowController.beginningAddressTextField.enabled = YES;
	self.windowController.endingAddressTextField.enabled = YES;
	self.windowController.beginningAddressLabel.textColor = NSColor.controlTextColor;
	self.windowController.endingAddressLabel.textColor = NSColor.controlTextColor;
	
	self.windowController.runningApplicationsPopUpButton.enabled = YES;
	
	if (shouldMakeSearchFieldFirstResponder)
	{
		[self.windowController.window makeFirstResponder:self.windowController.searchValueTextField];
	}
	
	if (!self.windowController.currentProcess.valid)
	{
		[self.windowController removeRunningProcessFromPopupButton:nil];
	}
}

- (void)resumeFromTask
{
	[self resumeFromTaskAndMakeSearchFieldFirstResponder:YES];
}

#pragma mark Update UI

- (NSString *)numberOfVariablesFoundDescription
{
	NSNumberFormatter *numberOfVariablesFoundFormatter = [[NSNumberFormatter alloc] init];
	numberOfVariablesFoundFormatter.format = @"#,###";
	return [NSString stringWithFormat:@"Found %@ value%@...", [numberOfVariablesFoundFormatter stringFromNumber:@(self.searchProgress.numberOfVariablesFound)], self.searchProgress.numberOfVariablesFound != 1 ? @"s" : @""];
}

- (void)updateVariablesFound
{
	if (self.searchProgress.initiatedSearch)
	{
		self.windowController.searchingProgressIndicator.maxValue = (double)self.searchProgress.maxProgress;
		self.windowController.searchingProgressIndicator.doubleValue = (double)self.searchProgress.progress;
		self.windowController.generalStatusTextField.stringValue = [self numberOfVariablesFoundDescription];
	}
}

- (void)updateSearchUserInterface:(NSTimer *)timer
{
	if (!self.searchProgress.shouldCancelSearch)
	{
		[self updateVariablesFound];
	}
	else
	{
		self.windowController.generalStatusTextField.stringValue = @"Cancelling search...";
	}
}

- (void)updateMemoryStoreUserInterface:(NSTimer *)timer
{
	self.windowController.searchingProgressIndicator.doubleValue = self.searchProgress.progress;
}

#pragma mark Searching

- (void)fetchVariablesFromResults
{	
	if (self.documentData.variables.count < MAX_TABLE_VIEW_ITEMS && self.searchResults.addressCount > 0)
	{
		NSMutableArray *newVariables = [[NSMutableArray alloc] initWithArray:self.documentData.variables];
		
		NSUInteger numberOfVariables = MAX_TABLE_VIEW_ITEMS - self.documentData.variables.count;
		if (numberOfVariables > self.searchResults.addressCount)
		{
			numberOfVariables = self.searchResults.addressCount;
		}
		
		ZGVariableQualifier qualifier = (ZGVariableQualifier)self.documentData.qualifierTag;
		ZGMemorySize pointerSize = self.windowController.currentProcess.pointerSize;
		
		[self.searchResults enumerateWithCount:numberOfVariables usingBlock:^(ZGMemoryAddress variableAddress, BOOL *stop) {
			ZGVariable *newVariable =
				[[ZGVariable alloc]
				 initWithValue:NULL
				 size:self.searchResults.dataSize
				 address:variableAddress
				 type:(ZGVariableType)self.searchResults.tag
				 qualifier:qualifier
				 pointerSize:pointerSize];
			
			[newVariables addObject:newVariable];
		}];
		
		[self.searchResults removeNumberOfAddresses:numberOfVariables];
		
		self.documentData.variables = [NSArray arrayWithArray:newVariables];
		if (self.documentData.variables.count > 0)
		{
			[self.windowController.tableController updateVariableValuesInRange:NSMakeRange(0, self.documentData.variables.count)];
		}
	}
}

- (void)finalizeSearchWithNotSearchedVariables:(NSArray *)notSearchedVariables
{
	self.searchProgress.progress = 0;
	if (self.searchProgress.shouldCancelSearch)
	{
		self.windowController.searchingProgressIndicator.doubleValue = self.searchProgress.progress;
		self.windowController.generalStatusTextField.stringValue = @"Canceled search.";
	}
	else
	{
		[self updateVariablesFound];
		
		if (NSClassFromString(@"NSUserNotification"))
		{
			NSUserNotification *userNotification = [[NSUserNotification alloc] init];
			userNotification.title = @"Search Finished";
			userNotification.subtitle = self.windowController.currentProcess.name;
			userNotification.informativeText = [self numberOfVariablesFoundDescription];
			[[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:userNotification];
		}
		
		if (notSearchedVariables.count + self.temporarySearchResults.addressCount != self.documentData.variables.count)
		{
			self.windowController.undoManager.actionName = @"Search";
			[[self.windowController.undoManager prepareWithInvocationTarget:self.windowController] updateVariables:self.documentData.variables searchResults:self.searchResults];
			
			self.documentData.variables = [NSArray arrayWithArray:notSearchedVariables];
			self.searchResults = self.temporarySearchResults;
			[self fetchVariablesFromResults];
			[self.windowController.tableController.variablesTableView reloadData];
		}
	}
	
	self.temporarySearchResults = nil;
	
	BOOL shouldMakeSearchFieldFirstResponder = YES;
	
	// Make the table first responder if we come back from a search and only one variable was found. Hopefully the user found what he was looking for.
	if (!self.searchProgress.shouldCancelSearch && self.documentData.variables.count <= MAX_TABLE_VIEW_ITEMS)
	{
		NSArray *filteredVariables = [self.documentData.variables zgFilterUsingBlock:(zg_array_filter_t)^(ZGVariable *variable) {
			return !variable.enabled;
		}];
		
		if (filteredVariables.count == 1)
		{
			[self.windowController.window makeFirstResponder:self.windowController.tableController.variablesTableView];
			shouldMakeSearchFieldFirstResponder = NO;
		}
	}
	
	[self resumeFromTaskAndMakeSearchFieldFirstResponder:shouldMakeSearchFieldFirstResponder];
}

- (BOOL)retrieveSearchData
{
	ZGVariableType dataType = (ZGVariableType)self.documentData.selectedDatatypeTag;
	
	self.searchData.pointerSize = self.windowController.currentProcess.pointerSize;
	
	// Set default search arguments
	self.searchData.epsilon = DEFAULT_FLOATING_POINT_EPSILON;
	self.searchData.rangeValue = NULL;

	NSString *inputErrorMessage = nil;
	NSString *evaluatedSearchExpression = nil;
	
	evaluatedSearchExpression =
		(dataType == ZGUTF8String || dataType == ZGUTF16String || dataType == ZGByteArray)
		? self.documentData.searchValueString
		: [ZGCalculator evaluateExpression:self.documentData.searchValueString];
	
	inputErrorMessage = [self confirmSearchInput:evaluatedSearchExpression];
	
	if (inputErrorMessage)
	{
		NSRunAlertPanel(@"Invalid Search Input", inputErrorMessage, nil, nil, nil);
		return NO;
	}
	
	// get search value and data size
	ZGMemorySize tempDataSize = 0;
	self.searchData.searchValue = valueFromString(self.windowController.currentProcess.is64Bit, evaluatedSearchExpression, dataType, &tempDataSize);
	self.searchData.dataSize = tempDataSize;
	
	// We want to read the null terminator in this case... even though we normally don't store the terminator
	// internally for UTF-16 strings. Lame hack, I know.
	if (self.searchData.shouldIncludeNullTerminator)
	{
		if (dataType == ZGUTF16String)
		{
			self.searchData.dataSize += sizeof(unichar);
		}
		else if (dataType == ZGUTF8String)
		{
			self.searchData.dataSize += sizeof(char);
		}
	}
	
	ZGFunctionType functionType = (ZGFunctionType)self.documentData.functionTypeTag;
	
	if (![self.windowController functionTypeAllowsSearchInput])
	{
		self.searchData.searchValue = NULL;
	}
	
	self.searchData.dataAlignment =
		self.documentData.ignoreDataAlignment
		? sizeof(int8_t)
		: dataAlignment(self.windowController.currentProcess.is64Bit, dataType, self.searchData.dataSize);
	
	BOOL flagsFieldIsBlank = [[self.windowController.flagsTextField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] isEqualToString:@""];
	
	if (self.windowController.flagsTextField.isEnabled)
	{
		NSString *flagsExpression =
			(dataType == ZGUTF8String || dataType == ZGUTF16String || dataType == ZGByteArray)
			? self.windowController.flagsTextField.stringValue
			: [ZGCalculator evaluateExpression:self.windowController.flagsTextField.stringValue];
		
		inputErrorMessage = [self testSearchComponent:flagsExpression];
		
		if (inputErrorMessage && !flagsFieldIsBlank)
		{
			NSString *field =
				(functionType == ZGEquals || functionType == ZGNotEquals || functionType == ZGEqualsStored || functionType == ZGNotEqualsStored)
				? @"Epsilon"
				: ((functionType == ZGGreaterThan || functionType == ZGGreaterThanStored) ? @"Below" : @"Above");
			NSRunAlertPanel(@"Invalid Search Input", @"The value corresponding to %@ needs to be a valid expression or be left blank.", nil, nil, nil, field);
			return NO;
		}
		else /* if (!inputErrorMessage || flagsFieldIsBlank) */
		{
			if (functionType == ZGGreaterThan || functionType == ZGLessThan || functionType == ZGGreaterThanStored || functionType == ZGLessThanStored)
			{
				if (!flagsFieldIsBlank)
				{
					// Clearly a range type of search
					ZGMemorySize rangeDataSize;
					self.searchData.rangeValue = valueFromString(self.windowController.currentProcess.is64Bit, flagsExpression, dataType, &rangeDataSize);
				}
				else
				{
					self.searchData.rangeValue = NULL;
				}
				
				if (functionType == ZGGreaterThan || functionType == ZGGreaterThanStored)
				{
					self.documentData.lastBelowRangeValue = self.windowController.flagsTextField.stringValue;
				}
				else if (functionType == ZGLessThan || functionType == ZGLessThanStored)
				{
					self.documentData.lastAboveRangeValue = self.windowController.flagsTextField.stringValue;
				}
			}
			else
			{
				if (!flagsFieldIsBlank)
				{
					// Clearly an epsilon flag
					ZGMemorySize epsilonDataSize;
					void *epsilon = valueFromString(self.windowController.currentProcess.is64Bit, flagsExpression, ZGDouble, &epsilonDataSize);
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
				
				self.documentData.lastEpsilonValue = self.windowController.flagsTextField.stringValue;
			}
		}
	}
	
	// Deal with beginning and ending addresses, if there are any
	
	NSString *calculatedBeginAddress = [ZGCalculator evaluateExpression:self.documentData.beginningAddressStringValue];
	NSString *calculatedEndAddress = [ZGCalculator evaluateExpression:self.documentData.endingAddressStringValue];
	
	if (![self.documentData.beginningAddressStringValue isEqualToString:@""])
	{
		if ([self testSearchComponent:calculatedBeginAddress])
		{
			NSRunAlertPanel(@"Invalid Search Input", @"The expression in the beginning address field is not valid.", nil, nil, nil, nil);
			return NO;
		}
		
		self.searchData.beginAddress = memoryAddressFromExpression(calculatedBeginAddress);
	}
	else
	{
		self.searchData.beginAddress = 0x0;
	}
	
	if (![self.documentData.endingAddressStringValue isEqualToString:@""])
	{
		if ([self testSearchComponent:calculatedEndAddress])
		{
			NSRunAlertPanel(@"Invalid Search Input", @"The expression in the ending address field is not valid.", nil, nil, nil, nil);
			return NO;
		}
		
		self.searchData.endAddress = memoryAddressFromExpression(calculatedEndAddress);
	}
	else
	{
		self.searchData.endAddress = MAX_MEMORY_ADDRESS;
	}
	
	if (self.searchData.beginAddress >= self.searchData.endAddress)
	{
		NSRunAlertPanel(@"Invalid Search Input", @"The value in the beginning address field must be less than the value of the ending address field, or one or both of the fields can be omitted.", nil, nil, nil, nil);
		return NO;
	}
	
	if (dataType == ZGByteArray)
	{
		self.searchData.byteArrayFlags = allocateFlagsForByteArrayWildcards(evaluatedSearchExpression);
	}
	
	if (functionType == ZGEqualsStoredPlus || functionType == ZGNotEqualsStoredPlus)
	{
		self.searchData.compareOffset = self.searchData.searchValue;
	}
	
	return YES;
}

- (void)searchVariablesWithComparisonFunction:(comparison_function_t)compareFunction byNarrowing:(BOOL)isNarrowing usingCompletionBlock:(dispatch_block_t)completeSearchBlock
{
	ZGProcess *currentProcess = self.windowController.currentProcess;
	ZGSearchResults *firstSearchResults = nil;
	if (isNarrowing)
	{
		NSMutableData *firstResultSets = [NSMutableData data];
		for (ZGVariable *variable in self.documentData.variables)
		{
			if (variable.enabled)
			{
				if (self.searchData.pointerSize == sizeof(ZGMemoryAddress))
				{
					ZGMemoryAddress variableAddress = variable.address;
					[firstResultSets appendBytes:&variableAddress length:sizeof(variableAddress)];
				}
				else
				{
					ZG32BitMemoryAddress variableAddress = (ZG32BitMemoryAddress)variable.address;
					[firstResultSets appendBytes:&variableAddress length:sizeof(variableAddress)];
				}
			}
		}
		firstSearchResults = [[ZGSearchResults alloc] initWithResultSets:@[firstResultSets] dataSize:self.searchData.dataSize pointerSize:self.searchData.pointerSize];
	}
	
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		if (!isNarrowing)
		{
			self.temporarySearchResults = ZGSearchForData(currentProcess.processTask, self.searchData, self.searchProgress, compareFunction);
		}
		else
		{
			self.temporarySearchResults = ZGNarrowSearchForData(currentProcess.processTask, self.searchData, self.searchProgress, compareFunction, firstSearchResults, self.searchResults);
		}
		
		self.temporarySearchResults.tag = self.documentData.selectedDatatypeTag;
		
		dispatch_async(dispatch_get_main_queue(), completeSearchBlock);
	});
}

- (void)search
{
	ZGVariableType dataType = (ZGVariableType)self.documentData.selectedDatatypeTag;
	ZGFunctionType functionType = (ZGFunctionType)self.documentData.functionTypeTag;
	
	if ([self retrieveSearchData])
	{
		NSMutableArray *notSearchedVariables = [[NSMutableArray alloc] init];
		
		// Add all variables whose value should not be searched for, first
		for (ZGVariable *variable in self.documentData.variables)
		{
			if (variable.isFrozen || variable.type != dataType || !variable.enabled)
			{
				[notSearchedVariables addObject:variable];
			}
		}
		
		[self prepareTask];
		[self.searchProgress clear];
		
		[self createUserInterfaceTimer];
		
		comparison_function_t compareFunction = getComparisonFunction(functionType, dataType, self.windowController.currentProcess.is64Bit, (ZGVariableQualifier)self.documentData.qualifierTag);
		
		[self searchVariablesWithComparisonFunction:compareFunction byNarrowing:self.isInNarrowSearchMode usingCompletionBlock:^ {
			self.searchData.searchValue = NULL;
			self.userInterfaceTimer = nil;
			
			[self finalizeSearchWithNotSearchedVariables:notSearchedVariables];
		}];
	}
}

- (void)searchOrCancel
{
	if (self.canStartTask)
	{
		if (self.documentData.functionTypeTag == ZGStoreAllValues)
		{
			[self storeAllValues];
		}
		else
		{
			[self search];
		}
	}
	else
	{
		[self cancelTask];
	}
}

- (void)cancelTask
{
	if (self.searchProgress.progressType == ZGSearchProgressMemoryStoring)
	{
		// Cancel memory store
		self.windowController.generalStatusTextField.stringValue = @"Canceling Memory Store...";
	}
	else if (self.searchProgress.progressType == ZGSearchProgressMemoryWatching)
	{
		// Cancel break point watching
		[self.windowController.documentBreakPointController cancelTask];
	}
	else
	{
		// Cancel the search
		self.windowController.searchButton.enabled = NO;
	}
	
	self.searchProgress.shouldCancelSearch = YES;
}

#pragma mark Storing all values

- (void)storeAllValues
{
	[self prepareTask];
	
	self.windowController.generalStatusTextField.stringValue = @"Storing All Values...";
	[self.searchProgress clear];
	
	[self createUserInterfaceTimer];
	
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		self.tempSavedData = ZGGetAllData(self.windowController.currentProcess.processTask, self.searchData, self.searchProgress);
		
		dispatch_async(dispatch_get_main_queue(), ^{
			self.userInterfaceTimer = nil;
			
			if (self.searchProgress.shouldCancelSearch)
			{
				self.windowController.generalStatusTextField.stringValue = @"Canceled Memory Store";
			}
			else
			{
				self.searchData.savedData = self.tempSavedData;
				self.tempSavedData = nil;
				
				self.windowController.generalStatusTextField.stringValue = @"Finished Memory Store";
			}
			
			self.windowController.searchingProgressIndicator.doubleValue = 0;
			
			[self resumeFromTask];
		});
	});
}

@end
