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
#import "ZGVirtualMemory.h"
#import "ZGVirtualMemoryHelpers.h"
#import "ZGRegion.h"
#import "ZGSearchData.h"
#import "ZGSearchProgress.h"
#import "ZGSearchResults.h"
#import "ZGCalculator.h"
#import "ZGUtilities.h"
#import "NSArrayAdditions.h"
#import "ZGDocumentData.h"
#import "APTokenSearchField.h"
#import "ZGSearchToken.h"
#import "ZGVariableController.h"

@interface ZGDocumentSearchController ()

@property (assign) ZGDocumentWindowController *windowController;
@property (strong, nonatomic, readwrite) NSTimer *userInterfaceTimer;
@property (readwrite, strong, nonatomic) ZGSearchProgress *searchProgress;
@property (nonatomic) ZGSearchResults *temporarySearchResults;
@property (nonatomic) NSArray *tempSavedData;
@property (assign) BOOL isBusy;

@property (nonatomic) ZGVariableType dataType;
@property (nonatomic) ZGFunctionType functionType;
@property (nonatomic) NSArray *searchComponents;

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
	return ZGIsValidNumber(searchComponent) ? nil : @"The operator you are using requires the search value to be a valid expression.";
}

- (NSString *)confirmSearchInput:(NSString *)expression
{
	ZGVariableType dataType = self.dataType;
	
	if (ZGIsNumericalDataType(dataType))
	{
		if (![self.windowController isFunctionTypeStore:self.functionType])
		{
			NSString *inputError = [self testSearchComponent:expression];
			
			if (inputError)
			{
				return inputError;
			}
		}
	}
	
	if ((dataType == ZGString8 || dataType == ZGString16 || dataType == ZGByteArray) && [self.searchData shouldCompareStoredValues])
	{
		return [NSString stringWithFormat:@"Comparing Stored Values is not supported for %@.", dataType == ZGByteArray ? @"Byte Arrays" : @"Strings"];
	}
	
	return nil;
}

#pragma mark Report information

- (BOOL)isVariableNarrowable:(ZGVariable *)variable withDataType:(ZGVariableType)dataType
{
	return (variable.enabled && variable.type == dataType && !variable.isFrozen);
}

- (BOOL)isInNarrowSearchMode
{
	ZGVariableType dataType = self.dataType;
	
	BOOL goingToNarrowDownSearches = NO;
	for (ZGVariable *variable in self.documentData.variables)
	{
		if ([self isVariableNarrowable:variable withDataType:dataType])
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
	self.isBusy = YES;
	
	self.windowController.progressIndicator.doubleValue = 0;
	
	[self.windowController.progressIndicator setHidden:NO];
	
	self.windowController.storeValuesButton.enabled = NO;
	self.windowController.runningApplicationsPopUpButton.enabled = NO;
	self.windowController.dataTypesPopUpButton.enabled = NO;
	self.windowController.functionPopUpButton.enabled = NO;
}

- (void)resumeFromTaskAndMakeSearchFieldFirstResponder:(BOOL)shouldMakeSearchFieldFirstResponder
{
	self.isBusy = NO;
	
	[self.windowController.progressIndicator setHidden:YES];
	
	self.windowController.storeValuesButton.enabled = YES;
	
	self.windowController.dataTypesPopUpButton.enabled = YES;
	
	[self.windowController updateOptions];
	
	self.windowController.functionPopUpButton.enabled = YES;
	
	self.windowController.runningApplicationsPopUpButton.enabled = YES;
	
	if (shouldMakeSearchFieldFirstResponder)
	{
		[self.windowController.window makeFirstResponder:self.windowController.searchValueTextField];
		if ([self.windowController isFunctionTypeStore:self.functionType])
		{
			[self.windowController deselectSearchField];
		}
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

- (void)updateMemoryStoreUserInterface:(NSTimer *)timer
{
	self.windowController.progressIndicator.doubleValue = self.searchProgress.progress;
}

- (NSString *)numberOfVariablesFoundDescriptionFromProgress:(ZGSearchProgress *)searchProgress
{
	NSNumberFormatter *numberOfVariablesFoundFormatter = [[NSNumberFormatter alloc] init];
	numberOfVariablesFoundFormatter.format = @"#,###";
	return [NSString stringWithFormat:@"Found %@ value%@...", [numberOfVariablesFoundFormatter stringFromNumber:@(searchProgress.numberOfVariablesFound)], searchProgress.numberOfVariablesFound != 1 ? @"s" : @""];
}

- (void)updateProgressBarFromProgress:(ZGSearchProgress *)searchProgress
{
	self.windowController.progressIndicator.maxValue = (double)searchProgress.maxProgress;
	self.windowController.progressIndicator.doubleValue = (double)searchProgress.progress;
	
	[self.windowController setStatus:[self numberOfVariablesFoundDescriptionFromProgress:searchProgress]];
}

- (void)progress:(ZGSearchProgress *)searchProgress advancedWithResultSet:(NSData *)resultSet
{
	if (!self.searchProgress.shouldCancelSearch)
	{
		NSUInteger currentVariableCount = self.documentData.variables.count;
		
		if (currentVariableCount < MAX_NUMBER_OF_VARIABLES_TO_FETCH && resultSet.length > 0)
		{
			ZGSearchResults *searchResults = [[ZGSearchResults alloc] initWithResultSets:@[resultSet] dataSize:self.searchData.dataSize pointerSize:self.searchData.pointerSize];
			searchResults.tag = self.dataType;
			[self fetchNumberOfVariables:MAX_NUMBER_OF_VARIABLES_TO_FETCH - currentVariableCount fromResults:searchResults];
			[self.windowController.tableController.variablesTableView reloadData];
		}
		
		[self updateProgressBarFromProgress:searchProgress];
	}
}

- (void)progressWillBegin:(ZGSearchProgress *)searchProgress
{
	[self updateProgressBarFromProgress:searchProgress];
	
	self.searchProgress = searchProgress;
}

#pragma mark Searching

- (void)fetchNumberOfVariables:(NSUInteger)numberOfVariables fromResults:(ZGSearchResults *)searchResults
{
	if (searchResults.addressCount == 0) return;
	
	if (numberOfVariables > searchResults.addressCount)
	{
		numberOfVariables = searchResults.addressCount;
	}
	
	NSMutableArray *allVariables = [[NSMutableArray alloc] initWithArray:self.documentData.variables];
	NSMutableArray *newVariables = [NSMutableArray array];
	
	ZGVariableQualifier qualifier = (ZGVariableQualifier)self.documentData.qualifierTag;
	ZGProcess *currentProcess = self.windowController.currentProcess;
	ZGMemorySize pointerSize = currentProcess.pointerSize;
	
	ZGMemorySize dataSize = searchResults.dataSize;
	[searchResults enumerateWithCount:numberOfVariables usingBlock:^(ZGMemoryAddress variableAddress, BOOL *stop) {
		ZGVariable *newVariable =
		[[ZGVariable alloc]
		 initWithValue:NULL
		 size:dataSize
		 address:variableAddress
		 type:(ZGVariableType)searchResults.tag
		 qualifier:qualifier
		 pointerSize:pointerSize];
		
		[newVariables addObject:newVariable];
	}];
	
	[searchResults removeNumberOfAddresses:numberOfVariables];
	
	[self.windowController.variableController annotateVariables:newVariables];
	
	[allVariables addObjectsFromArray:newVariables];
	self.documentData.variables = [NSArray arrayWithArray:allVariables];
	
	if (self.documentData.variables.count > 0)
	{
		[self.windowController.tableController updateVariableValuesInRange:NSMakeRange(allVariables.count - newVariables.count, newVariables.count)];
	}
}

- (void)fetchNumberOfVariables:(NSUInteger)numberOfVariables
{
	[self fetchNumberOfVariables:numberOfVariables fromResults:self.searchResults];
}

- (void)fetchVariablesFromResults
{
	if (self.documentData.variables.count < MAX_NUMBER_OF_VARIABLES_TO_FETCH)
	{
		[self fetchNumberOfVariables:(MAX_NUMBER_OF_VARIABLES_TO_FETCH - self.documentData.variables.count) fromResults:self.searchResults];
	}
}

- (void)finalizeSearchWithOldVariables:(NSArray *)oldVariables andNotSearchedVariables:(NSArray *)notSearchedVariables
{
	if (!self.searchProgress.shouldCancelSearch)
	{
		if (NSClassFromString(@"NSUserNotification"))
		{
			NSUserNotification *userNotification = [[NSUserNotification alloc] init];
			userNotification.title = @"Search Finished";
			userNotification.subtitle = self.windowController.currentProcess.name;
			userNotification.informativeText = [self numberOfVariablesFoundDescriptionFromProgress:self.searchProgress];
			[[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:userNotification];
		}
		
		if (notSearchedVariables.count + self.temporarySearchResults.addressCount != oldVariables.count)
		{
			self.windowController.undoManager.actionName = @"Search";
			[[self.windowController.undoManager prepareWithInvocationTarget:self.windowController] updateVariables:oldVariables searchResults:self.searchResults];
			
			self.searchResults = self.temporarySearchResults;
			self.documentData.variables = notSearchedVariables;
			[self fetchVariablesFromResults];
			[self.windowController.tableController.variablesTableView reloadData];
		}
	}
	else
	{
		self.documentData.variables = oldVariables;
		[self.windowController.tableController.variablesTableView reloadData];
	}
	
	[self.windowController updateObservingProcessOcclusionState];
	
	self.temporarySearchResults = nil;
	
	[self.windowController setStatus:nil];
	
	BOOL shouldMakeSearchFieldFirstResponder = YES;
	
	// Make the table first responder if we come back from a search and only one variable was found. Hopefully the user found what he was looking for.
	if (!self.searchProgress.shouldCancelSearch && self.documentData.variables.count <= MAX_NUMBER_OF_VARIABLES_TO_FETCH)
	{
		NSArray *filteredVariables = [self.documentData.variables zgFilterUsingBlock:(zg_array_filter_t)^(ZGVariable *variable) {
			return variable.enabled;
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
	ZGVariableType dataType = self.dataType;
	
	self.searchData.pointerSize = self.windowController.currentProcess.pointerSize;
	
	// Set default search arguments
	self.searchData.epsilon = DEFAULT_FLOATING_POINT_EPSILON;
	self.searchData.rangeValue = NULL;

	NSString *inputErrorMessage = nil;
	
	ZGFunctionType functionType = self.functionType;
	
	self.searchData.shouldCompareStoredValues = [self.windowController isFunctionTypeStore:functionType];
	
	if (!self.searchData.shouldCompareStoredValues)
	{
		NSString *searchValueInput = [self.searchComponents objectAtIndex:0];
		NSString *finalSearchExpression = ZGIsNumericalDataType(dataType) ? [ZGCalculator evaluateExpression:searchValueInput] : searchValueInput;
		
		inputErrorMessage = [self confirmSearchInput:finalSearchExpression];
		
		if (inputErrorMessage != nil)
		{
			NSRunAlertPanel(@"Invalid Search Input", inputErrorMessage, nil, nil, nil);
			return NO;
		}
		
		ZGMemorySize dataSize = 0;
		self.searchData.searchValue = ZGValueFromString(self.windowController.currentProcess.is64Bit, finalSearchExpression, dataType, &dataSize);
		
		if (self.searchData.shouldIncludeNullTerminator)
		{
			if (dataType == ZGString16)
			{
				dataSize += sizeof(int16_t);
			}
			else if (dataType == ZGString8)
			{
				dataSize += sizeof(int8_t);
			}
		}
		
		self.searchData.dataSize = dataSize;
		
		if (dataType == ZGByteArray)
		{
			self.searchData.byteArrayFlags = ZGAllocateFlagsForByteArrayWildcards(finalSearchExpression);
		}
	}
	else
	{
		self.searchData.searchValue = NULL;
		self.searchData.dataSize = ZGDataSizeFromNumericalDataType(self.windowController.currentProcess.is64Bit, dataType);
		
		if (functionType == ZGEqualsStoredLinear || functionType == ZGNotEqualsStoredLinear)
		{
			NSMutableArray *stringComponents = [NSMutableArray array];
			for (id object in self.searchComponents)
			{
				if ([object isKindOfClass:[ZGSearchToken class]])
				{
					[stringComponents addObject:@"$StoredValue"];
				}
				else if ([object isKindOfClass:[NSString class]])
				{
					[stringComponents addObject:object];
				}
			}
			NSString *linearExpression = [stringComponents componentsJoinedByString:@""];
			NSString *additiveConstantString = nil;
			NSString *multiplicativeConstantString = nil;
			
			if (![ZGCalculator parseLinearExpression:linearExpression andGetAdditiveConstant:&additiveConstantString multiplicateConstant:&multiplicativeConstantString])
			{
				NSLog(@"Error: Failed to parse linear expression %@", linearExpression);
				NSRunAlertPanel(@"Invalid Search Input", @"The search expression could not be properly parsed. Try a simpler expression.", nil, nil, nil);
				return NO;
			}
			
			self.searchData.additiveConstant = ZGValueFromString(self.windowController.currentProcess.is64Bit, additiveConstantString, dataType, NULL);
			self.searchData.multiplicativeConstant = [multiplicativeConstantString doubleValue];
			
			if (self.searchData.additiveConstant == NULL)
			{
				NSLog(@"Error: transformed additive is NULL");
				NSRunAlertPanel(@"Invalid Search Input", @"The additive part of the search expression could not be properly parsed. Try a simpler expression", nil, nil, nil);
				return NO;
			}
		}
	}
	
	self.searchData.dataAlignment =
		self.documentData.ignoreDataAlignment
		? sizeof(int8_t)
		: ZGDataAlignment(self.windowController.currentProcess.is64Bit, dataType, self.searchData.dataSize);
	
	BOOL flagsFieldIsBlank = [[self.windowController.flagsTextField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] isEqualToString:@""];
	
	if (self.windowController.flagsTextField.isEnabled)
	{
		NSString *flagsExpression =
			!ZGIsNumericalDataType(dataType)
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
					self.searchData.rangeValue = ZGValueFromString(self.windowController.currentProcess.is64Bit, flagsExpression, dataType, &rangeDataSize);
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
					void *epsilon = ZGValueFromString(self.windowController.currentProcess.is64Bit, flagsExpression, ZGDouble, &epsilonDataSize);
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
		
		self.searchData.beginAddress = ZGMemoryAddressFromExpression(calculatedBeginAddress);
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
		
		self.searchData.endAddress = ZGMemoryAddressFromExpression(calculatedEndAddress);
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
	
	return YES;
}

- (void)searchVariablesByNarrowing:(BOOL)isNarrowing withVariables:(NSArray *)narrowVariables usingCompletionBlock:(dispatch_block_t)completeSearchBlock
{
	ZGProcess *currentProcess = self.windowController.currentProcess;
	ZGVariableType dataType = self.dataType;
	ZGSearchResults *firstSearchResults = nil;
	if (isNarrowing)
	{
		NSMutableData *firstResultSets = [NSMutableData data];
		for (ZGVariable *variable in narrowVariables)
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
		firstSearchResults = [[ZGSearchResults alloc] initWithResultSets:@[firstResultSets] dataSize:self.searchData.dataSize pointerSize:self.searchData.pointerSize];
	}
	
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		if (!isNarrowing)
		{
			self.temporarySearchResults = ZGSearchForData(currentProcess.processTask, self.searchData, self, dataType, self.documentData.qualifierTag, self.functionType);
		}
		else
		{
			self.temporarySearchResults = ZGNarrowSearchForData(currentProcess.processTask, self.searchData, self, dataType, self.documentData.qualifierTag, self.functionType, firstSearchResults, (self.searchResults.tag == dataType && currentProcess.pointerSize == self.searchResults.pointerSize) ? self.searchResults : nil);
		}
		
		self.temporarySearchResults.tag = dataType;
		
		dispatch_async(dispatch_get_main_queue(), completeSearchBlock);
	});
}

- (void)searchComponents:(NSArray *)searchComponents withDataType:(ZGVariableType)dataType functionType:(ZGFunctionType)functionType allowsNarrowing:(BOOL)allowsNarrowing
{
	self.dataType = dataType;
	self.functionType = functionType;
	self.searchComponents = searchComponents;
	
	if ([self retrieveSearchData])
	{
		NSMutableArray *notSearchedVariables = [[NSMutableArray alloc] init];
		NSMutableArray *searchedVariables = [[NSMutableArray alloc] init];
		
		BOOL isNarrowingSearch = allowsNarrowing && [self isInNarrowSearchMode];
		
		// Add all variables whose value should not be searched for, first
		for (ZGVariable *variable in self.documentData.variables)
		{
			if (!isNarrowingSearch || ![self isVariableNarrowable:variable withDataType:dataType])
			{
				[notSearchedVariables addObject:variable];
			}
			else
			{
				[searchedVariables addObject:variable];
			}
		}
		
		[self prepareTask];
		
		id searchDataActivity = nil;
		if ([[NSProcessInfo processInfo] respondsToSelector:@selector(beginActivityWithOptions:reason:)])
		{
			searchDataActivity = [[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiated reason:@"Searching Data"];
		}
		
		NSArray *oldVariables = self.documentData.variables;
		
		self.documentData.variables = notSearchedVariables;
		[self.windowController.tableController.variablesTableView reloadData];
		
		[self searchVariablesByNarrowing:isNarrowingSearch withVariables:searchedVariables usingCompletionBlock:^ {
			self.searchData.searchValue = NULL;
			
			if (searchDataActivity != nil)
			{
				[[NSProcessInfo processInfo] endActivity:searchDataActivity];
			}
			
			[self finalizeSearchWithOldVariables:oldVariables andNotSearchedVariables:notSearchedVariables];
		}];
	}
}

- (void)cancelTask
{
	if (self.searchProgress.progressType == ZGSearchProgressMemoryScanning)
	{
		[self.windowController setStatus:@"Cancelling search..."];
	}
	else if (self.searchProgress.progressType == ZGSearchProgressMemoryStoring)
	{
		[self.windowController setStatus:@"Canceling Memory Store..."];
	}
	
	self.searchProgress.shouldCancelSearch = YES;
}

#pragma mark Storing all values

- (void)storeAllValues
{
	[self prepareTask];
	
	[self.windowController setStatus:@"Storing All Values..."];
	[self.searchProgress clear];
	
	[self createUserInterfaceTimer];
	
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		self.tempSavedData = ZGGetAllData(self.windowController.currentProcess.processTask, self.searchData, self.searchProgress);
		
		dispatch_async(dispatch_get_main_queue(), ^{
			self.userInterfaceTimer = nil;
			
			if (!self.searchProgress.shouldCancelSearch)
			{
				if (self.searchData.savedData == nil)
				{
					[self.windowController createSearchMenu];
				}
				
				self.searchData.savedData = self.tempSavedData;
				self.tempSavedData = nil;
				self.windowController.storeValuesButton.image = [NSImage imageNamed:@"container_filled"];
				
				if (self.documentData.searchValue.count == 0)
				{
					[self.windowController insertStoredValueToken:nil];
				}
			}
			
			[self.windowController setStatus:nil];
			
			self.windowController.progressIndicator.doubleValue = 0;
			
			[self resumeFromTask];
		});
	});
}

@end
