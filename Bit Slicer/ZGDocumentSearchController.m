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
#import "ZGStoredData.h"
#import "ZGCalculator.h"
#import "ZGUtilities.h"
#import "NSArrayAdditions.h"
#import "ZGDocumentData.h"
#import "APTokenSearchField.h"
#import "ZGSearchToken.h"
#import "ZGVariableController.h"
#import "ZGTableView.h"

@interface ZGDocumentSearchController ()

@property (nonatomic, assign) ZGDocumentWindowController *windowController;
@property (nonatomic) ZGSearchProgress *searchProgress;
@property (nonatomic) ZGSearchResults *temporarySearchResults;
@property (nonatomic) ZGStoredData *tempSavedData;
@property (atomic) BOOL isBusy;

@property (nonatomic) ZGVariableType dataType;
@property (nonatomic) ZGFunctionType functionType;
@property (nonatomic) BOOL allowsNarrowing;
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
	// Force canceling
	self.searchProgress.shouldCancelSearch = YES;
	
	self.windowController = nil;
}

#pragma mark Report information

- (BOOL)isVariableNarrowable:(ZGVariable *)variable withDataType:(ZGVariableType)dataType
{
	return (variable.enabled && variable.type == dataType && !variable.isFrozen);
}

- (BOOL)isInNarrowSearchMode
{
	ZGVariableType dataType = self.dataType;
	return [self.documentData.variables zgHasObjectMatchingCondition:^(ZGVariable *variable) {
		return [self isVariableNarrowable:variable withDataType:dataType];
	}];
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
	
	ZGDocumentWindowController *windowController = self.windowController;
	
	windowController.progressIndicator.doubleValue = 0;
	
	[windowController.progressIndicator setHidden:NO];
	
	windowController.storeValuesButton.enabled = NO;
	windowController.runningApplicationsPopUpButton.enabled = NO;
	windowController.dataTypesPopUpButton.enabled = NO;
	windowController.functionPopUpButton.enabled = NO;
}

- (void)resumeFromTaskAndMakeSearchFieldFirstResponder:(BOOL)shouldMakeSearchFieldFirstResponder
{
	self.isBusy = NO;
	
	ZGDocumentWindowController *windowController = self.windowController;
	
	[windowController.progressIndicator setHidden:YES];
	
	windowController.storeValuesButton.enabled = YES;
	
	windowController.dataTypesPopUpButton.enabled = YES;
	
	[windowController updateOptions];
	
	windowController.functionPopUpButton.enabled = YES;
	
	windowController.runningApplicationsPopUpButton.enabled = YES;
	
	if (shouldMakeSearchFieldFirstResponder)
	{
		[windowController.window makeFirstResponder:windowController.searchValueTextField];
		if (ZGIsFunctionTypeStore(self.functionType))
		{
			[windowController deselectSearchField];
		}
	}
}

- (void)resumeFromTask
{
	[self resumeFromTaskAndMakeSearchFieldFirstResponder:YES];
}

#pragma mark Update UI

- (void)updateMemoryStoreUserInterface:(NSTimer *)__unused timer
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
	ZGDocumentWindowController *windowController = self.windowController;
	windowController.progressIndicator.doubleValue = (double)searchProgress.progress;
	
	[windowController setStatusString:[self numberOfVariablesFoundDescriptionFromProgress:searchProgress]];
}

- (void)progress:(ZGSearchProgress *)searchProgress advancedWithResultSet:(NSData *)resultSet
{
	if (!self.searchProgress.shouldCancelSearch)
	{
		NSUInteger currentVariableCount = self.documentData.variables.count;
		
		if (currentVariableCount < MAX_NUMBER_OF_VARIABLES_TO_FETCH && resultSet.length > 0)
		{
			ZGSearchResults *searchResults = [[ZGSearchResults alloc] initWithResultSets:@[resultSet] dataSize:self.searchData.dataSize pointerSize:self.searchData.pointerSize];
			searchResults.dataType = self.dataType;
			searchResults.enabled = self.allowsNarrowing;
			[self fetchNumberOfVariables:MAX_NUMBER_OF_VARIABLES_TO_FETCH - currentVariableCount fromResults:searchResults];
			[self.windowController.tableController.variablesTableView reloadData];
		}
		
		[self updateProgressBarFromProgress:searchProgress];
	}
}

- (void)progressWillBegin:(ZGSearchProgress *)searchProgress
{
	self.windowController.progressIndicator.maxValue = (double)searchProgress.maxProgress;
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
	
	ZGDocumentWindowController *windowController = self.windowController;
	
	ZGVariableQualifier qualifier = (ZGVariableQualifier)self.documentData.qualifierTag;
	CFByteOrder byteOrder = self.documentData.byteOrderTag;
	ZGProcess *currentProcess = windowController.currentProcess;
	ZGMemorySize pointerSize = currentProcess.pointerSize;
	
	ZGMemorySize dataSize = searchResults.dataSize;
	BOOL enabled = searchResults.enabled;
	[searchResults enumerateWithCount:numberOfVariables usingBlock:^(ZGMemoryAddress variableAddress, BOOL * __unused stop) {
		ZGVariable *newVariable =
		[[ZGVariable alloc]
		 initWithValue:NULL
		 size:dataSize
		 address:variableAddress
		 type:(ZGVariableType)searchResults.dataType
		 qualifier:qualifier
		 pointerSize:pointerSize
		 description:[[NSAttributedString alloc] initWithString:@""]
		 enabled:enabled
		 byteOrder:byteOrder];
		
		[newVariables addObject:newVariable];
	}];
	
	[searchResults removeNumberOfAddresses:numberOfVariables];
	
	[ZGVariableController annotateVariables:newVariables process:currentProcess];
	
	[allVariables addObjectsFromArray:newVariables];
	self.documentData.variables = [NSArray arrayWithArray:allVariables];
	
	if (self.documentData.variables.count > 0)
	{
		[windowController.tableController updateVariableValuesInRange:NSMakeRange(allVariables.count - newVariables.count, newVariables.count)];
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
	ZGDocumentWindowController *windowController = self.windowController;
	
	if (!self.searchProgress.shouldCancelSearch)
	{
		ZGDeliverUserNotification(@"Search Finished", windowController.currentProcess.name, [self numberOfVariablesFoundDescriptionFromProgress:self.searchProgress]);
		
		if (notSearchedVariables.count + self.temporarySearchResults.addressCount != oldVariables.count)
		{
			windowController.undoManager.actionName = @"Search";
			[[windowController.undoManager prepareWithInvocationTarget:windowController] updateVariables:oldVariables searchResults:self.searchResults];
			
			self.searchResults = self.temporarySearchResults;
			self.documentData.variables = notSearchedVariables;
			[self fetchVariablesFromResults];
			[windowController.tableController.variablesTableView reloadData];
			[windowController markDocumentChange];
		}
	}
	else
	{
		self.documentData.variables = oldVariables;
		[windowController.tableController.variablesTableView reloadData];
	}
	
	[windowController updateOcclusionActivity];
	
	self.temporarySearchResults = nil;
	
	[windowController updateNumberOfValuesDisplayedStatus];
	
	if (self.allowsNarrowing)
	{
		BOOL shouldMakeSearchFieldFirstResponder = YES;
		
		// Make the table first responder if we come back from a search and only one variable was found. Hopefully the user found what he was looking for.
		if (!self.searchProgress.shouldCancelSearch && self.documentData.variables.count <= MAX_NUMBER_OF_VARIABLES_TO_FETCH)
		{
			NSArray *filteredVariables = [self.documentData.variables zgFilterUsingBlock:(zg_array_filter_t)^(ZGVariable *variable) {
				return variable.enabled;
			}];
			
			if (filteredVariables.count == 1)
			{
				[windowController.window makeFirstResponder:windowController.tableController.variablesTableView];
				shouldMakeSearchFieldFirstResponder = NO;
			}
		}
		
		[self resumeFromTaskAndMakeSearchFieldFirstResponder:shouldMakeSearchFieldFirstResponder];
	}
	else
	{
		[self resumeFromTaskAndMakeSearchFieldFirstResponder:NO];
	}
}

#define ZGRetrieveFlagsErrorDomain @"ZGRetrieveFlagsErrorDomain"
#define ZGRetrieveFlagsErrorDescriptionKey @"ZGRetrieveFlagsErrorDescriptionKey"

- (BOOL)retrieveFlagsSearchDataWithDataType:(ZGVariableType)dataType functionType:(ZGFunctionType)functionType error:(NSError * __autoreleasing *)error
{
	ZGDocumentWindowController *windowController = self.windowController;
	
	if (!windowController.showsFlags) return YES;
	
	ZGProcess *currentProcess = windowController.currentProcess;
	NSString *flagsStringValue = windowController.flagsStringValue;
	
	BOOL flagsFieldIsBlank = [[flagsStringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] length] == 0;
	NSString *flagsExpression = !ZGIsNumericalDataType(dataType) ? flagsStringValue : [ZGCalculator evaluateExpression:flagsStringValue];
	
	if (!flagsFieldIsBlank && !ZGIsValidNumber(flagsExpression))
	{
		NSString *field = (ZGIsFunctionTypeEquals(functionType) || ZGIsFunctionTypeNotEquals(functionType)) ? @"Round Error" : (ZGIsFunctionTypeGreaterThan(functionType) ? @"Below" : @"Above");
		
		if (error != NULL)
		{
			*error = [NSError errorWithDomain:ZGRetrieveFlagsErrorDomain code:0 userInfo:@{ZGRetrieveFlagsErrorDescriptionKey : [NSString stringWithFormat:@"The value corresponding to %@ needs to be a valid expression or be empty.", field]}];
		}
		
		return NO;
	}
	else
	{
		if (ZGIsFunctionTypeGreaterThan(functionType) ||  ZGIsFunctionTypeLessThan(functionType))
		{
			if (!flagsFieldIsBlank)
			{
				// Clearly a range type of search
				ZGMemorySize rangeDataSize;
				self.searchData.rangeValue = ZGValueFromString(currentProcess.is64Bit, flagsExpression, dataType, &rangeDataSize);
			}
			else
			{
				self.searchData.rangeValue = NULL;
			}
			
			if (ZGIsFunctionTypeGreaterThan(functionType))
			{
				self.documentData.lastBelowRangeValue = flagsStringValue;
			}
			else if (ZGIsFunctionTypeLessThan(functionType))
			{
				self.documentData.lastAboveRangeValue = flagsStringValue;
			}
		}
		else
		{
			if (!flagsFieldIsBlank)
			{
				// Clearly an epsilon flag
				ZGMemorySize epsilonDataSize;
				void *epsilon = ZGValueFromString(currentProcess.is64Bit, flagsExpression, ZGDouble, &epsilonDataSize);
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
			
			self.documentData.lastEpsilonValue = flagsStringValue;
		}
	}
	
	return YES;
}

- (BOOL)getBoundaryAddress:(ZGMemoryAddress *)boundaryAddress fromStringValue:(NSString *)stringValue label:(NSString *)label error:(NSError * __autoreleasing *)error
{
	assert(boundaryAddress != NULL);
	
	BOOL success = YES;
	
	if ([stringValue length] != 0)
	{
		if (!ZGIsValidNumber(stringValue))
		{
			if (error != NULL)
			{
				*error = [NSError errorWithDomain:ZGRetrieveFlagsErrorDomain code:0 userInfo:@{ZGRetrieveFlagsErrorDescriptionKey : [NSString stringWithFormat:@"The expression in the %@ address field is not valid.", label]}];
			}
			
			success = NO;
		}
		else
		{
			*boundaryAddress = ZGMemoryAddressFromExpression([ZGCalculator evaluateExpression:stringValue]);
		}
	}
	
	return success;
}

- (BOOL)retrieveSearchDataWithError:(NSError * __autoreleasing *)error
{
	ZGDocumentWindowController *windowController = self.windowController;
	ZGVariableType dataType = self.dataType;
	
	self.searchData.pointerSize = windowController.currentProcess.pointerSize;
	
	// Set default search arguments
	self.searchData.epsilon = DEFAULT_FLOATING_POINT_EPSILON;
	self.searchData.rangeValue = NULL;
	
	ZGFunctionType functionType = self.functionType;
	
	BOOL is64Bit = windowController.currentProcess.is64Bit;
	
	self.searchData.shouldCompareStoredValues = ZGIsFunctionTypeStore(functionType);
	
	if (!self.searchData.shouldCompareStoredValues)
	{
		NSString *searchValueInput = [self.searchComponents objectAtIndex:0];
		NSString *finalSearchExpression = ZGIsNumericalDataType(dataType) ? [ZGCalculator evaluateExpression:searchValueInput] : searchValueInput;
		
		if (ZGIsNumericalDataType(dataType) && !ZGIsFunctionTypeStore(self.functionType) && !ZGIsValidNumber(finalSearchExpression))
		{
			if (error != NULL)
			{
				*error = [NSError errorWithDomain:ZGRetrieveFlagsErrorDomain code:0 userInfo:@{ZGRetrieveFlagsErrorDescriptionKey : @"The operator you are using requires the search value to be a valid expression."}];
			}
			return NO;
		}
		
		ZGMemorySize dataSize = 0;
		self.searchData.searchValue = ZGValueFromString(is64Bit, finalSearchExpression, dataType, &dataSize);
		
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
		if (dataType == ZGString8 || dataType == ZGString16 || dataType == ZGByteArray)
		{
			if (error != NULL)
			{
				*error = [NSError errorWithDomain:ZGRetrieveFlagsErrorDomain code:0 userInfo:@{ZGRetrieveFlagsErrorDescriptionKey : [NSString stringWithFormat:@"Comparing Stored Values is not supported for %@.", dataType == ZGByteArray ? @"Byte Arrays" : @"Strings"]}];
			}
			return NO;
		}
		
		self.searchData.searchValue = NULL;
		self.searchData.dataSize = ZGDataSizeFromNumericalDataType(is64Bit, dataType);
		
		if (ZGIsFunctionTypeLinear(functionType))
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
				if (error != NULL)
				{
					*error = [NSError errorWithDomain:ZGRetrieveFlagsErrorDomain code:0 userInfo:@{ZGRetrieveFlagsErrorDescriptionKey : @"The search expression could not be properly parsed. Try a simpler expression."}];
				}
				return NO;
			}
			
			self.searchData.additiveConstant = ZGValueFromString(windowController.currentProcess.is64Bit, additiveConstantString, dataType, NULL);
			self.searchData.multiplicativeConstant = [multiplicativeConstantString doubleValue];
			
			if (self.searchData.additiveConstant == NULL)
			{
				if (error != NULL)
				{
					*error = [NSError errorWithDomain:ZGRetrieveFlagsErrorDomain code:0 userInfo:@{ZGRetrieveFlagsErrorDescriptionKey : @"The search expression could not be properly parsed. Try a simpler expression."}];
				}
				return NO;
			}
		}
	}
	
	if (CFByteOrderGetCurrent() != self.documentData.byteOrderTag)
	{
		self.searchData.bytesSwapped = YES;
		if (ZGSupportsSwappingBeforeSearch(functionType, dataType))
		{
			self.searchData.swappedValue = ZGSwappedValue(is64Bit, self.searchData.searchValue, dataType, self.searchData.dataSize);
		}
	}
	else
	{
		self.searchData.bytesSwapped = NO;
		self.searchData.swappedValue = NULL;
	}
	
	self.searchData.dataAlignment =
		self.documentData.ignoreDataAlignment
		? sizeof(int8_t)
		: ZGDataAlignment(windowController.currentProcess.is64Bit, dataType, self.searchData.dataSize);
	
	if (![self retrieveFlagsSearchDataWithDataType:dataType functionType:functionType error:error])
	{
		return NO;
	}
	
	ZGMemoryAddress beginningAddress = 0x0;
	
	BOOL retrievedBoundaryAddress =
	[self
	 getBoundaryAddress:&beginningAddress
	 fromStringValue:self.documentData.beginningAddressStringValue
	 label:@"beginning"
	 error:error];
	
	if (!retrievedBoundaryAddress) return NO;
	
	self.searchData.beginAddress = beginningAddress;
	
	ZGMemoryAddress endingAddress = MAX_MEMORY_ADDRESS;
	
	retrievedBoundaryAddress =
	[self
	 getBoundaryAddress:&endingAddress
	 fromStringValue:self.documentData.endingAddressStringValue
	 label:@"ending"
	 error:error];
	
	if (!retrievedBoundaryAddress) return NO;
	
	self.searchData.endAddress = endingAddress;
	
	if (self.searchData.beginAddress >= self.searchData.endAddress)
	{
		if (error != NULL)
		{
			*error = [NSError errorWithDomain:ZGRetrieveFlagsErrorDomain code:0 userInfo:@{ZGRetrieveFlagsErrorDescriptionKey : @"The value in the beginning address field must be less than the value of the ending address field, or one or both of the fields can be omitted."}];
		}
		return NO;
	}
	
	return YES;
}

- (void)searchVariables:(NSArray *)variables byNarrowing:(BOOL)isNarrowing usingCompletionBlock:(dispatch_block_t)completeSearchBlock
{
	ZGProcess *currentProcess = self.windowController.currentProcess;
	ZGVariableType dataType = self.dataType;
	ZGSearchResults *firstSearchResults = nil;
	if (isNarrowing)
	{
		NSMutableData *firstResultSets = [NSMutableData data];
		for (ZGVariable *variable in variables)
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
			self.temporarySearchResults = ZGSearchForData(currentProcess.processTask, self.searchData, self, dataType, (ZGVariableQualifier)self.documentData.qualifierTag, self.functionType);
		}
		else
		{
			self.temporarySearchResults = ZGNarrowSearchForData(currentProcess.processTask, self.searchData, self, dataType, (ZGVariableQualifier)self.documentData.qualifierTag, self.functionType, firstSearchResults, (self.searchResults.dataType == dataType && currentProcess.pointerSize == self.searchResults.pointerSize) ? self.searchResults : nil);
		}
		
		self.temporarySearchResults.dataType = dataType;
		self.temporarySearchResults.enabled = self.allowsNarrowing;
		
		dispatch_async(dispatch_get_main_queue(), completeSearchBlock);
	});
}

- (void)searchComponents:(NSArray *)searchComponents withDataType:(ZGVariableType)dataType functionType:(ZGFunctionType)functionType allowsNarrowing:(BOOL)allowsNarrowing
{
	self.dataType = dataType;
	self.functionType = functionType;
	self.searchComponents = searchComponents;
	self.allowsNarrowing = allowsNarrowing;
	
	NSError *error = nil;
	if (![self retrieveSearchDataWithError:&error])
	{
		NSRunAlertPanel(@"Invalid Search Input", @"%@", nil, nil, nil, [error.userInfo objectForKey:ZGRetrieveFlagsErrorDescriptionKey]);
		return;
	}
	
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
	
	[self searchVariables:searchedVariables byNarrowing:isNarrowingSearch usingCompletionBlock:^ {
		if (self.windowController != nil)
		{
			self.searchData.searchValue = NULL;
			self.searchData.swappedValue = NULL;
			
			if (searchDataActivity != nil)
			{
				[[NSProcessInfo processInfo] endActivity:searchDataActivity];
			}
			
			[self finalizeSearchWithOldVariables:oldVariables andNotSearchedVariables:notSearchedVariables];
		}
	}];
}

- (void)cancelTask
{
	ZGDocumentWindowController *windowController = self.windowController;
	if (self.searchProgress.progressType == ZGSearchProgressMemoryScanning)
	{
		[windowController setStatusString:@"Cancelling search..."];
	}
	else if (self.searchProgress.progressType == ZGSearchProgressMemoryStoring)
	{
		[windowController setStatusString:@"Canceling Memory Store..."];
	}
	
	self.searchProgress.shouldCancelSearch = YES;
}

#pragma mark Storing all values

- (void)storeAllValues
{
	[self prepareTask];
	
	ZGDocumentWindowController *windowController = self.windowController;
	
	[windowController setStatusString:@"Storing All Values..."];
	
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		self.tempSavedData = [ZGStoredData storedDataFromProcessTask:windowController.currentProcess.processTask];
		
		dispatch_async(dispatch_get_main_queue(), ^{
			if (!self.searchProgress.shouldCancelSearch)
			{
				if (self.searchData.savedData == nil)
				{
					[windowController createSearchMenu];
				}
				
				self.searchData.savedData = self.tempSavedData;
				self.tempSavedData = nil;
				windowController.storeValuesButton.image = [NSImage imageNamed:@"container_filled"];
				
				if (![self.documentData.searchValue zgHasObjectMatchingCondition:^(id object) { return [object isKindOfClass:[ZGSearchToken class]]; }])
				{
					[windowController insertStoredValueToken:nil];
				}
			}
			
			[windowController updateNumberOfValuesDisplayedStatus];
			
			windowController.progressIndicator.doubleValue = 0;
			
			[self resumeFromTask];
		});
	});
}

@end
