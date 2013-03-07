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
#import "ZGDocument.h"
#import "ZGProcess.h"
#import "ZGDocumentTableController.h"
#import "ZGDocumentBreakPointController.h"
#import "ZGVariableController.h"
#import "ZGVirtualMemory.h"
#import "ZGSearchData.h"
#import "ZGSearchProgress.h"
#import "ZGCalculator.h"
#import "ZGUtilities.h"
#import "ZGComparisonFunctions.h"
#import "NSArrayAdditions.h"

@interface ZGDocumentSearchController ()

@property (assign) IBOutlet ZGDocument *document;
@property (strong, nonatomic, readwrite) NSTimer *userInterfaceTimer;
@property (readwrite, strong, nonatomic) ZGSearchData *searchData;
@property (assign) BOOL isBusy;

@end

@implementation ZGDocumentSearchController

#pragma mark Birth & Death

- (id)init
{
	self = [super init];
	
	if (self)
	{
		self.searchData = [[ZGSearchData alloc] init];
	}
	
	return self;
}

- (void)cleanUp
{
	self.userInterfaceTimer = nil;
	
	// Force canceling
	ZGCancelSearchImmediately(self.searchData);
	self.document.currentProcess.searchProgress.isDoingMemoryDump = NO;
	self.document.currentProcess.searchProgress.isStoringAllData = NO;
	[self.document.documentBreakPointController stopWatchingBreakPoints];
	
	self.searchData = nil;
	self.document = nil;
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
	
	[self.document updateClearButton];
	
	self.document.runningApplicationsPopUpButton.enabled = NO;
	self.document.dataTypesPopUpButton.enabled = NO;
	self.document.variableQualifierMatrix.enabled = NO;
	self.document.searchValueTextField.enabled = NO;
	self.document.flagsTextField.enabled = NO;
	self.document.functionPopUpButton.enabled = NO;
	self.document.searchButton.title = escapeTitle;
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

- (void)resumeFromTaskAndMakeSearchFieldFirstResponder:(BOOL)shouldMakeSearchFieldFirstResponder
{
	self.isBusy = NO;
	
	[self.document updateClearButton];
	
	self.document.dataTypesPopUpButton.enabled = YES;
    
	if ([self.document doesFunctionTypeAllowSearchInput])
	{
		self.document.searchValueTextField.enabled = YES;
	}
	self.document.searchButton.enabled = YES;
	self.document.searchButton.keyEquivalent = @"\r";
	
	[self.document updateFlagsAndSearchButtonTitle];
	
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
	
	if (shouldMakeSearchFieldFirstResponder)
	{
		[self.document.watchWindow makeFirstResponder:self.document.searchValueTextField];
	}
	
	if (!self.document.currentProcess.valid)
	{
		[self.document removeRunningProcessFromPopupButton:nil];
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
	return [NSString stringWithFormat:@"Found %@ value%@...", [numberOfVariablesFoundFormatter stringFromNumber:@(self.document.currentProcess.searchProgress.numberOfVariablesFound)], self.document.currentProcess.searchProgress.numberOfVariablesFound != 1 ? @"s" : @""];
}

- (void)updateSearchUserInterface:(NSTimer *)timer
{
	if (self.document.windowForSheet.isVisible)
	{
		if (!ZGSearchIsCancelling(self.searchData))
		{
			self.document.searchingProgressIndicator.doubleValue = (double)self.document.currentProcess.searchProgress.progress;
			self.document.generalStatusTextField.stringValue = [self numberOfVariablesFoundDescription];
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
		self.document.searchingProgressIndicator.doubleValue = self.document.currentProcess.searchProgress.progress;
	}
}

#pragma mark Searching

- (void)clear
{
	if (NSRunAlertPanel(@"Clear Search", @"Are you sure you want to clear your search? You will not be able to undo this action.", @"Clear", @"Cancel", nil) == NSAlertDefaultReturn)
	{
		// Remove undo actions in another task as it may be somewhat of an expensive operation
		NSUndoManager *oldUndoManager = self.document.undoManager;
		self.document.undoManager = [[NSUndoManager alloc] init];
		
		__block NSArray *oldVariables = self.document.watchVariablesArray;
		self.document.watchVariablesArray = [NSArray array];
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			[oldUndoManager removeAllActions];
			oldVariables = nil;
		});
		
		self.document.runningApplicationsPopUpButton.enabled = YES;
		self.document.dataTypesPopUpButton.enabled = YES;
		self.document.variableQualifierMatrix.enabled = YES;
		
		if (self.document.currentProcess.valid)
		{
			self.document.searchButton.enabled = YES;
		}
		
		[self.document.tableController.watchVariablesTableView reloadData];
		
		if ([self.document doesFunctionTypeAllowSearchInput])
		{
			self.document.searchValueTextField.enabled = YES;
		}
		
		self.document.clearButton.enabled = NO;
		
		if (self.document.currentProcess.valid)
		{
			self.document.generalStatusTextField.stringValue = @"Cleared search.";
		}
		
		[self.document markDocumentChange];
	}
}

- (void)searchCleanUp:(NSArray *)newVariablesArray
{
	if (newVariablesArray.count != self.document.watchVariablesArray.count)
	{
		self.document.undoManager.actionName = @"Search";
		[[self.document.undoManager prepareWithInvocationTarget:self.document] setWatchVariablesArrayAndUpdateInterface:self.document.watchVariablesArray];
	}
	
	self.document.currentProcess.searchProgress.progress = 0;
	if (ZGSearchDidCancel(self.searchData))
	{
		self.document.searchingProgressIndicator.doubleValue = self.document.currentProcess.searchProgress.progress;
		self.document.generalStatusTextField.stringValue = @"Canceled search.";
	}
	else
	{
		ZGInitializeSearch(self.searchData);
		[self updateSearchUserInterface:nil];
		
		if (NSClassFromString(@"NSUserNotification"))
		{
			NSUserNotification *userNotification = [[NSUserNotification alloc] init];
			userNotification.title = @"Search Finished";
			userNotification.subtitle = self.document.currentProcess.name;
			userNotification.informativeText = [self numberOfVariablesFoundDescription];
			[[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:userNotification];
		}
		
		self.document.watchVariablesArray = [NSArray arrayWithArray:newVariablesArray];
		
		[self.document.tableController.watchVariablesTableView reloadData];
	}
	
	[self resumeFromTask];
}

- (BOOL)retrieveSearchData
{
	ZGVariableType dataType = (ZGVariableType)self.document.dataTypesPopUpButton.selectedItem.tag;
	
	// Set default search arguments
	self.searchData.epsilon = DEFAULT_FLOATING_POINT_EPSILON;
	self.searchData.rangeValue = NULL;
	
	self.searchData.shouldIgnoreStringCase = self.document.ignoreCaseCheckBox.state;
	self.searchData.shouldIncludeNullTerminator = self.document.includeNullTerminatorCheckBox.state;
	self.searchData.shouldCompareStoredValues = self.document.isFunctionTypeStore;
	
	self.searchData.shouldScanUnwritableValues = (self.document.scanUnwritableValuesCheckBox.state == NSOnState);
	
	NSString *inputErrorMessage = nil;
	NSString *evaluatedSearchExpression = nil;
	
	evaluatedSearchExpression =
		(dataType == ZGUTF8String || dataType == ZGUTF16String || dataType == ZGByteArray)
		? self.document.searchValueTextField.stringValue
		: [ZGCalculator evaluateExpression:self.document.searchValueTextField.stringValue];
	
	inputErrorMessage = [self confirmSearchInput:evaluatedSearchExpression];
	
	if (inputErrorMessage)
	{
		NSRunAlertPanel(@"Invalid Search Input", inputErrorMessage, nil, nil, nil);
		return NO;
	}
	
	// get search value and data size
	ZGMemorySize tempDataSize = 0;
	self.searchData.searchValue = valueFromString(self.document.currentProcess, evaluatedSearchExpression, dataType, &tempDataSize);
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
	
	ZGFunctionType functionType = (ZGFunctionType)self.document.functionPopUpButton.selectedItem.tag;
	
	if (self.searchData.searchValue && ![self.document doesFunctionTypeAllowSearchInput])
	{
		free(self.searchData.searchValue);
		self.searchData.searchValue = NULL;
	}
	
	self.searchData.dataAlignment =
		(self.document.ignoreDataAlignmentCheckBox.state == NSOnState)
		? sizeof(int8_t)
		: ZGDataAlignment(self.document.currentProcess.is64Bit, dataType, self.searchData.dataSize);
	
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
	
	if (![self.document.beginningAddressTextField.stringValue isEqualToString:@""])
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
	
	if (![self.document.endingAddressTextField.stringValue isEqualToString:@""])
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

- (void)search
{
	ZGVariableType dataType = (ZGVariableType)self.document.dataTypesPopUpButton.selectedItem.tag;
	ZGFunctionType functionType = (ZGFunctionType)self.document.functionPopUpButton.selectedItem.tag;
	
	BOOL goingToNarrowDownSearches = self.isInNarrowSearchMode;
	
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
	
	if (![self retrieveSearchData])
	{
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
	
	comparison_function_t compareFunction = getComparisonFunction(functionType, dataType, self.document.currentProcess.is64Bit);
	
	ZGMemorySize dataSize = self.searchData.dataSize;
	void *searchValue = self.searchData.searchValue;
	
	ZGVariableQualifier qualifier = [[self.document.variableQualifierMatrix cellWithTag:SIGNED_BUTTON_CELL_TAG] state] == NSOnState ? ZGSigned : ZGUnsigned;
	ZGMemorySize pointerSize = self.document.currentProcess.pointerSize;
	
	dispatch_block_t completeSearchBlock = ^
	{
		if (self.searchData.searchValue)
		{
			free(self.searchData.searchValue);
		}
		
		self.userInterfaceTimer = nil;
		
		[self searchCleanUp:temporaryVariablesArray];
	};
	
	if (!goingToNarrowDownSearches)
	{
		NSUInteger numberOfRegions = self.document.currentProcess.numberOfRegions;
		
		self.document.searchingProgressIndicator.maxValue = numberOfRegions;
		self.document.currentProcess.searchProgress.numberOfVariablesFound = 0;
		self.document.currentProcess.searchProgress.progress = 0;
		
		[self createUserInterfaceTimer];
		
		ZGProcess *currentProcess = self.document.currentProcess;
		search_for_data_t searchForDataCallback = ^(ZGSearchData * __unsafe_unretained searchData, void *variableData, void *compareData, ZGMemoryAddress address, NSMutableArray * __unsafe_unretained results)
		{
			if (compareFunction(searchData, variableData, (compareData != NULL) ? compareData : searchValue, dataSize))
			{
				ZGVariable *newVariable =
					[[ZGVariable alloc]
					 initWithValue:variableData
					 size:dataSize
					 address:address
					 type:dataType
					 qualifier:qualifier
					 pointerSize:pointerSize];
				
				[results addObject:newVariable];
			}
		};
		
		search_for_data_update_progress_t searchForDataUpdateInterfaceCallback = ^(NSUInteger newResultsCount)
		{
			currentProcess.searchProgress.numberOfVariablesFound += newResultsCount;
			currentProcess.searchProgress.progress++;
		};
		
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			if (self.searchData.shouldCompareStoredValues)
			{
				[temporaryVariablesArray addObjectsFromArray:ZGSearchForSavedData(currentProcess.processTask, self.searchData, searchForDataCallback, searchForDataUpdateInterfaceCallback)];
			}
			else
			{
				[temporaryVariablesArray addObjectsFromArray:ZGSearchForData(currentProcess.processTask, self.searchData, searchForDataCallback, searchForDataUpdateInterfaceCallback)];
			}
			
			dispatch_async(dispatch_get_main_queue(), completeSearchBlock);
		});
	}
	else /* if (goingToNarrowDownSearches) */
	{
		ZGMemoryMap processTask = self.document.currentProcess.processTask;
		
		self.document.searchingProgressIndicator.maxValue = self.document.watchVariablesArray.count;
		self.document.currentProcess.searchProgress.progress = 0;
		self.document.currentProcess.searchProgress.numberOfVariablesFound = 0;
		
		[self createUserInterfaceTimer];
		
		ZGProcess *currentProcess = self.document.currentProcess;
		ZGMemoryAddress beginningAddress = self.searchData.beginAddress;
		ZGMemoryAddress endingAddress = self.searchData.endAddress;
		
		__block ZGSearchData *searchData = self.searchData;
		ZGInitializeSearch(self.searchData);
		
		// Get all relevant regions
		NSArray *regions = [ZGRegionsForProcessTask(processTask) zgFilterUsingBlock:(zg_array_filter_t)^(ZGRegion *region) {
			return !(region.address < endingAddress && region.address + region.size > beginningAddress && region.protection & VM_PROT_READ && (self.searchData.shouldScanUnwritableValues || (region.protection & VM_PROT_WRITE)));
		}];
		
		// Store all regions memory locally
		for (ZGRegion *region in regions)
		{
			void *bytes = NULL;
			ZGMemorySize outputSize = region.size;
			if (ZGReadBytes(currentProcess.processTask	, region.address, &bytes, &outputSize))
			{
				region.bytes = bytes;
				region.size = outputSize;
			}
		}
		
		// Filter out any regions we could not read
		regions = [regions zgFilterUsingBlock:(zg_array_filter_t)^(ZGRegion *region) {
			return !(region.bytes);
		}];
		
		// Start using multiple tasks for narrowing down our search
		// batchSize indicates the number of elements that each task will handle at most
		// Not sure what the best number to put in for this, but it appears to work well
		NSUInteger batchSize = 5000;
		NSUInteger totalCount = self.document.watchVariablesArray.count;
		NSUInteger numberOfBatches = (NSUInteger)ceil(totalCount / (batchSize * 1.0));
		
		NSMutableArray *batches = [[NSMutableArray alloc] init];
		for (NSUInteger batchIndex = 0; batchIndex < numberOfBatches; batchIndex++)
		{
			[batches addObject:[[NSMutableArray alloc] init]];
		}
		
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			dispatch_apply(numberOfBatches, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t batchIndex) {
				NSArray *variables = [self.document.watchVariablesArray subarrayWithRange:NSMakeRange(batchIndex*batchSize, MIN(batchSize, totalCount - batchIndex*batchSize))];
				NSMutableArray *batch = [batches objectAtIndex:batchIndex];
				ZGRegion *lastUsedRegion = nil;
				ZGRegion *lastUsedSavedRegion = nil;
				
				#define ADD_VARIABLE_SNIPPET \
				void *compareValue = searchData.shouldCompareStoredValues ? ZGSavedValue(variableAddress, searchData, &lastUsedSavedRegion, dataSize) : searchValue; \
				if (compareValue && compareFunction(searchData, lastUsedRegion.bytes + (variableAddress - lastUsedRegion.address), compareValue, dataSize)) \
				{ \
					[batch addObject:variable]; \
				}
				
				for (ZGVariable *variable in variables)
				{
					ZGMemoryAddress variableAddress = variable.address;
					
					if (variable.shouldBeSearched && variable.size > 0 && dataSize > 0 && beginningAddress <= variableAddress && endingAddress >= variableAddress + dataSize)
					{
						// Check if the variable is in the last region we scanned
						if (lastUsedRegion && variableAddress >= lastUsedRegion.address && variableAddress + dataSize <= lastUsedRegion.address + lastUsedRegion.size)
						{
							ADD_VARIABLE_SNIPPET
						}
						else
						{
							// Find which region the variable is in. Binary search time! Super fast!
							NSUInteger maxRegionIndex = regions.count - 1;
							NSUInteger minRegionIndex = 0;
							while (maxRegionIndex >= minRegionIndex)
							{
								NSUInteger middleRegionIndex = (minRegionIndex + maxRegionIndex) / 2;
								ZGRegion *region = [regions objectAtIndex:middleRegionIndex];
								ZGMemoryAddress regionAddress = region.address;
								
								if (variableAddress + dataSize <= regionAddress)
								{
									if (middleRegionIndex == 0) break;
									maxRegionIndex = middleRegionIndex - 1;
								}
								else if (variableAddress >= regionAddress + region.size)
								{
									minRegionIndex = middleRegionIndex + 1;
								}
								else
								{
									// Found the region, see if we should add the variable
									lastUsedRegion = region;
									if (variableAddress >= regionAddress && variableAddress + dataSize <= regionAddress + region.size)
									{
										ADD_VARIABLE_SNIPPET
									}
									
									break;
								}
							}
						}
					}
					
					if (ZGSearchDidCancel(searchData))
					{
						break;
					}
				}
				
				dispatch_async(dispatch_get_main_queue(), ^{
					currentProcess.searchProgress.progress += variables.count;
					currentProcess.searchProgress.numberOfVariablesFound += batch.count;
				});
			});
			
			for (ZGRegion *region in regions)
			{
				if (region.bytes)
				{
					ZGFreeBytes(processTask, region.bytes, region.size);
				}
			}
			
			for (NSMutableArray *batch in batches)
			{
				[temporaryVariablesArray addObjectsFromArray:batch];
			}
			
			dispatch_async(dispatch_get_main_queue(), completeSearchBlock);
		});
	}
}

- (void)searchOrCancel
{
	if (self.canStartTask)
	{
		if ([self.document.functionPopUpButton selectedTag] == ZGStoreAllValues)
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
	if (self.document.currentProcess.searchProgress.isDoingMemoryDump)
	{
		// Cancel memory dump
		self.document.currentProcess.searchProgress.isDoingMemoryDump = NO;
		self.document.generalStatusTextField.stringValue = @"Canceling Memory Dump...";
	}
	else if (self.document.currentProcess.searchProgress.isStoringAllData)
	{
		// Cancel memory store
		self.document.currentProcess.searchProgress.isStoringAllData = NO;
		self.document.generalStatusTextField.stringValue = @"Canceling Memory Store...";
	}
	else if (self.document.currentProcess.searchProgress.isWatchingBreakPoint)
	{
		// Cancel break point watching
		[self.document.documentBreakPointController cancelTask];
	}
	else
	{
		// Cancel the search
		self.document.searchButton.enabled = NO;
		
		if (self.isInNarrowSearchMode)
		{
			ZGCancelSearchImmediately(self.searchData);
		}
		else
		{
			ZGCancelSearch(self.searchData);
		}
	}
}

#pragma mark Storing all values

- (void)storeAllValues
{
	if (self.document.currentProcess.searchProgress.isStoringAllData)
	{
		return;
	}
	
	[self prepareTask];
	
	self.document.searchingProgressIndicator.maxValue = self.document.currentProcess.numberOfRegions;
	
	[self createUserInterfaceTimer];
	
	self.document.generalStatusTextField.stringValue = @"Storing All Values...";
	
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		self.searchData.tempSavedData = ZGGetAllData(self.document.currentProcess, self.document.scanUnwritableValuesCheckBox.state);
		
		dispatch_async(dispatch_get_main_queue(), ^{
			self.userInterfaceTimer = nil;
			
			if (!self.document.currentProcess.searchProgress.isStoringAllData)
			{
				self.document.generalStatusTextField.stringValue = @"Canceled Memory Store";
			}
			else
			{
				self.document.currentProcess.searchProgress.isStoringAllData = NO;
				
				self.searchData.savedData = self.searchData.tempSavedData;
				self.searchData.tempSavedData = nil;
				
				self.document.generalStatusTextField.stringValue = @"Finished Memory Store";
			}
			self.document.searchingProgressIndicator.doubleValue = 0;
			[self resumeFromTask];
		});
	});
}

@end
