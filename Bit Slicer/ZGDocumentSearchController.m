/*
 * Copyright (c) 2012 Mayur Pawashe
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
#import "ZGRegion.h"
#import "ZGSearchData.h"
#import "ZGSearchProgress.h"
#import "ZGSearchResults.h"
#import "ZGStoredData.h"
#import "ZGCalculator.h"
#import "ZGDeliverUserNotifications.h"
#import "ZGRunAlertPanel.h"
#import "NSArrayAdditions.h"
#import "ZGDocumentData.h"
#import "ZGVariableController.h"
#import "ZGTableView.h"
#import "ZGDataValueExtracting.h"
#import "ZGVariableDataInfo.h"
#import "ZGMemoryAddressExpressionParsing.h"
#import "ZGNullability.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-umbrella"
#import <DDMathParser/DDMathStringToken.h>
#import <DDMathParser/DDMathStringTokenizer.h>
#import <DDMathParser/DDMathOperator.h>
#pragma clang diagnostic pop

@implementation ZGDocumentSearchController
{
	__weak ZGDocumentWindowController * _Nullable _windowController;
	ZGDocumentData * _Nonnull _documentData;
	ZGSearchProgress * _Nonnull _searchProgress;
	ZGSearchResults * _Nullable _temporarySearchResults;
	BOOL _isBusy;
	ZGVariableType _dataType;
	ZGFunctionType _functionType;
	BOOL _allowsNarrowing;
	NSString *_searchValueString;
	ZGSearchData * _Nonnull _searchData;
	ZGMachBinaryAnnotationInfo _machBinaryAnnotationInfo;
}

#pragma mark Class Utilities

+ (BOOL)hasStoredValueTokenFromExpression:(NSString *)expression isLinearlyExpressed:(BOOL *)isLinearlyExpressedReference
{
	BOOL result = NO;
	BOOL isLinearlyExpressed = NO;
	
	NSError *error = nil;
	DDMathStringTokenizer *tokenizer = [[DDMathStringTokenizer alloc] initWithString:expression operatorSet:[DDMathOperatorSet defaultOperatorSet] error:&error];
	if (error == nil)
	{
		NSUInteger tokenCount = 0;
		for (DDMathStringToken *token in tokenizer)
		{
			if (token.tokenType == DDTokenTypeVariable)
			{
				result = YES;
			}
			tokenCount++;
		}
		
		if (result && tokenCount > 1)
		{
			isLinearlyExpressed = YES;
		}
	}
	
	if (isLinearlyExpressedReference != NULL)
	{
		*isLinearlyExpressedReference = isLinearlyExpressed;
	}
	
	return result;
}

+ (BOOL)hasStoredValueTokenFromExpression:(NSString *)expression
{
	return [self hasStoredValueTokenFromExpression:expression isLinearlyExpressed:NULL];
}

#pragma mark Birth & Death

- (id)initWithWindowController:(ZGDocumentWindowController *)windowController
{
	self = [super init];
	
	if (self != nil)
	{
		_windowController = windowController;
		_documentData = windowController.documentData;
		_searchData = windowController.searchData;
		_searchProgress = [[ZGSearchProgress alloc] init];
	}
	
	return self;
}

- (void)cleanUp
{
	// Force canceling
	_searchProgress.shouldCancelSearch = YES;
	
	_windowController = nil;
}

#pragma mark Report information

- (BOOL)isVariableNarrowable:(ZGVariable *)variable withDataType:(ZGVariableType)dataType
{
	return (variable.enabled && variable.type == dataType && !variable.isFrozen);
}

- (BOOL)isInNarrowSearchMode
{
	ZGVariableType dataType = _dataType;
	return [_documentData.variables zgHasObjectMatchingCondition:^(ZGVariable *variable) {
		return [self isVariableNarrowable:variable withDataType:dataType];
	}];
}

- (BOOL)canStartTask
{
	return !_isBusy;
}

- (BOOL)canCancelTask
{
	return _isBusy;
}

#pragma mark Preparing and resuming from tasks

- (void)prepareTask
{
	_isBusy = YES;
	
	ZGDocumentWindowController *windowController = _windowController;
	
	windowController.progressIndicator.doubleValue = 0;
	
	[windowController.progressIndicator setHidden:NO];
	
	windowController.storeValuesButton.enabled = NO;
	windowController.runningApplicationsPopUpButton.enabled = NO;
	windowController.dataTypesPopUpButton.enabled = NO;
	windowController.functionPopUpButton.enabled = NO;
}

- (void)resumeFromTaskAndMakeSearchFieldFirstResponder:(BOOL)shouldMakeSearchFieldFirstResponder
{
	_isBusy = NO;
	
	ZGDocumentWindowController *windowController = _windowController;
	
	[windowController.progressIndicator setHidden:YES];
	
	windowController.storeValuesButton.enabled = YES;
	
	windowController.dataTypesPopUpButton.enabled = YES;
	
	[windowController updateOptions];
	
	windowController.functionPopUpButton.enabled = YES;
	
	windowController.runningApplicationsPopUpButton.enabled = YES;
	
	if (shouldMakeSearchFieldFirstResponder)
	{
		[windowController.window makeFirstResponder:windowController.searchValueTextField];
		if ([[self class] hasStoredValueTokenFromExpression:windowController.searchValueTextField.stringValue])
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
	_windowController.progressIndicator.doubleValue = _searchProgress.progress;
}

- (NSString *)numberOfVariablesFoundDescriptionFromProgress:(ZGSearchProgress *)searchProgress
{
	NSNumberFormatter *numberOfVariablesFoundFormatter = [[NSNumberFormatter alloc] init];
	[numberOfVariablesFoundFormatter setNumberStyle:NSNumberFormatterDecimalStyle];
	
	NSUInteger numberOfVariablesFound = searchProgress.numberOfVariablesFound;
	NSString *formattedNumber = [numberOfVariablesFoundFormatter stringFromNumber:@(numberOfVariablesFound)];
	
	return [[NSString stringWithFormat:ZGLocalizableSearchDocumentString(@"foundValuesLabelFormat"), numberOfVariablesFound] stringByReplacingOccurrencesOfString:@"_NUM_" withString:formattedNumber];
}

- (void)updateProgressBarFromProgress:(ZGSearchProgress *)searchProgress
{
	ZGDocumentWindowController *windowController = _windowController;
	windowController.progressIndicator.doubleValue = (double)searchProgress.progress;
	
	[windowController setStatusString:[self numberOfVariablesFoundDescriptionFromProgress:searchProgress]];
}

- (void)progress:(ZGSearchProgress *)searchProgress advancedWithResultSet:(NSData *)resultSet
{
	if (!_searchProgress.shouldCancelSearch)
	{
		NSUInteger currentVariableCount = _documentData.variables.count;
		
		if (currentVariableCount < MAX_NUMBER_OF_VARIABLES_TO_FETCH && resultSet.length > 0)
		{
			// These progress search results are thrown away,
			// so doesn't matter if accesses are unaligned or not
			ZGSearchResults *searchResults = [[ZGSearchResults alloc] initWithResultSets:@[resultSet] dataSize:_searchData.dataSize pointerSize:_searchData.pointerSize unalignedAccess:YES];
			searchResults.dataType = _dataType;
			searchResults.enabled = _allowsNarrowing;
			[self fetchNumberOfVariables:MAX_NUMBER_OF_VARIABLES_TO_FETCH - currentVariableCount fromResults:searchResults];
			[_windowController.variablesTableView reloadData];
		}
		
		[self updateProgressBarFromProgress:searchProgress];
	}
}

- (void)progressWillBegin:(ZGSearchProgress *)searchProgress
{
	_windowController.progressIndicator.maxValue = (double)searchProgress.maxProgress;
	[self updateProgressBarFromProgress:searchProgress];
	
	_searchProgress = searchProgress;
}

#pragma mark Searching

- (void)fetchNumberOfVariables:(NSUInteger)numberOfVariables fromResults:(ZGSearchResults *)searchResults
{
	if (searchResults.addressCount == 0) return;
	
	if (numberOfVariables > searchResults.addressCount)
	{
		numberOfVariables = searchResults.addressCount;
	}
	
	NSMutableArray<ZGVariable *> *allVariables = [[NSMutableArray alloc] initWithArray:_documentData.variables];
	NSMutableArray<ZGVariable *> *newVariables = [NSMutableArray array];
	
	ZGDocumentWindowController *windowController = _windowController;
	
	ZGVariableQualifier qualifier = (ZGVariableQualifier)_documentData.qualifierTag;
	CFByteOrder byteOrder = _documentData.byteOrderTag;
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
		 type:searchResults.dataType
		 qualifier:qualifier
		 pointerSize:pointerSize
		 description:[[NSAttributedString alloc] initWithString:@""]
		 enabled:enabled
		 byteOrder:byteOrder];
		
		[newVariables addObject:newVariable];
	}];
	
	[searchResults removeNumberOfAddresses:numberOfVariables];
	
	// Waiting for completion would lead to a bad user experience and there is no need to
	[ZGVariableController annotateVariables:newVariables annotationInfo:&_machBinaryAnnotationInfo process:currentProcess symbols:YES async:YES completionHandler:^{
		[windowController.variablesTableView reloadData];
	}];
	
	[allVariables addObjectsFromArray:newVariables];
	_documentData.variables = [NSArray arrayWithArray:allVariables];
	
	if (_documentData.variables.count > 0)
	{
		[windowController.tableController updateVariableValuesInRange:NSMakeRange(allVariables.count - newVariables.count, newVariables.count)];
	}
}

- (void)fetchNumberOfVariables:(NSUInteger)numberOfVariables
{
	[self fetchNumberOfVariables:numberOfVariables fromResults:_searchResults];
}

- (void)fetchVariablesFromResults
{
	if (_documentData.variables.count < MAX_NUMBER_OF_VARIABLES_TO_FETCH)
	{
		[self fetchNumberOfVariables:(MAX_NUMBER_OF_VARIABLES_TO_FETCH - _documentData.variables.count) fromResults:_searchResults];
	}
}

- (void)finalizeSearchWithOldVariables:(NSArray<ZGVariable *> *)oldVariables andNotSearchedVariables:(NSArray<ZGVariable *> *)notSearchedVariables
{
	ZGDocumentWindowController *windowController = _windowController;
	
	if (!_searchProgress.shouldCancelSearch)
	{
		ZGDeliverUserNotification(ZGLocalizableSearchDocumentString(@"searchFinishedNotificationTitle"), windowController.currentProcess.name, [self numberOfVariablesFoundDescriptionFromProgress:_searchProgress], nil);
		
		if (notSearchedVariables.count + _temporarySearchResults.addressCount != oldVariables.count)
		{
			windowController.undoManager.actionName = ZGLocalizableSearchDocumentString(@"undoSearchAction");
			[(ZGDocumentWindowController *)[windowController.undoManager prepareWithInvocationTarget:windowController] updateVariables:oldVariables searchResults:_searchResults];
			
			_searchResults = _temporarySearchResults;
			_documentData.variables = notSearchedVariables;
			[self fetchVariablesFromResults];
			[windowController.variablesTableView reloadData];
			[windowController markDocumentChange];
		}
	}
	else
	{
		_documentData.variables = oldVariables;
		[windowController.variablesTableView reloadData];
	}
	
	_machBinaryAnnotationInfo.machBinaries = nil;
	_machBinaryAnnotationInfo.machFilePathDictionary = nil;
	
	[windowController updateOcclusionActivity];
	
	_temporarySearchResults = nil;
	
	[windowController updateNumberOfValuesDisplayedStatus];
	
	if (_allowsNarrowing)
	{
		BOOL shouldMakeSearchFieldFirstResponder = YES;
		
		// Make the table first responder if we come back from a search and only one variable was found. Hopefully the user found what he was looking for.
		if (!_searchProgress.shouldCancelSearch && _documentData.variables.count <= MAX_NUMBER_OF_VARIABLES_TO_FETCH)
		{
			NSArray<ZGVariable *> *filteredVariables = [_documentData.variables zgFilterUsingBlock:(zg_array_filter_t)^(ZGVariable *variable) {
				return variable.enabled;
			}];
			
			if (filteredVariables.count == 1)
			{
				[windowController.window makeFirstResponder:windowController.variablesTableView];
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
	ZGDocumentWindowController *windowController = _windowController;
	
	if (!windowController.showsFlags) return YES;
	
	ZGProcess *currentProcess = windowController.currentProcess;
	NSString *flagsStringValue = windowController.flagsStringValue;
	
	BOOL flagsFieldIsBlank = [[flagsStringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] length] == 0;
	NSString *flagsExpression = !ZGIsNumericalDataType(dataType) ? flagsStringValue : [ZGCalculator evaluateExpression:flagsStringValue];
	
	if (!flagsFieldIsBlank && !ZGIsValidNumber(flagsExpression))
	{
		NSString *field = ZGLocalizableSearchDocumentString((ZGIsFunctionTypeEquals(functionType) || ZGIsFunctionTypeNotEquals(functionType)) ? @"searchRoundErrorLabel" : (ZGIsFunctionTypeGreaterThan(functionType) ? @"searchBelowLabel" : @"searchAboveLabel"));
		
		if (error != NULL)
		{
			*error = [NSError errorWithDomain:ZGRetrieveFlagsErrorDomain code:0 userInfo:@{ZGRetrieveFlagsErrorDescriptionKey : [NSString stringWithFormat:ZGLocalizableSearchDocumentString(@"invalidFlagsFieldErrorMessageFormat"), field]}];
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
				_searchData.rangeValue = ZGValueFromString(ZG_PROCESS_TYPE_IS_64_BIT(currentProcess.type), flagsExpression, dataType, &rangeDataSize);
				if (_searchData.rangeValue == NULL)
				{
					NSLog(@"Failed to parse range value from %@...", flagsExpression);
					return NO;
				}
			}
			else
			{
				_searchData.rangeValue = NULL;
			}
			
			if (ZGIsFunctionTypeGreaterThan(functionType))
			{
				_documentData.lastBelowRangeValue = flagsStringValue;
			}
			else if (ZGIsFunctionTypeLessThan(functionType))
			{
				_documentData.lastAboveRangeValue = flagsStringValue;
			}
		}
		else
		{
			if (!flagsFieldIsBlank)
			{
				// Clearly an epsilon flag
				ZGMemorySize epsilonDataSize;
				void *epsilon = ZGValueFromString(ZG_PROCESS_TYPE_IS_64_BIT(currentProcess.type), flagsExpression, ZGDouble, &epsilonDataSize);
				if (epsilon != NULL)
				{
					_searchData.epsilon = *((double *)epsilon);
					free(epsilon);
				}
			}
			else
			{
				_searchData.epsilon = DEFAULT_FLOATING_POINT_EPSILON;
			}
			
			_documentData.lastEpsilonValue = flagsStringValue;
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
			success = NO;
		}
		else
		{
			NSString *evaluatedExpression = [ZGCalculator evaluateExpression:stringValue];
			if (evaluatedExpression != nil)
			{
				*boundaryAddress = ZGMemoryAddressFromExpression(evaluatedExpression);
			}
			else
			{
				success = NO;
			}
		}
	}
	
	if (!success && error != NULL)
	{
		*error = [NSError errorWithDomain:ZGRetrieveFlagsErrorDomain code:0 userInfo:@{ZGRetrieveFlagsErrorDescriptionKey : [NSString stringWithFormat:ZGLocalizableSearchDocumentString(@"invalidFlagsFieldErrorMessageFormat"), label]}];
	}
	
	return success;
}

- (BOOL)retrieveSearchDataWithError:(NSError * __autoreleasing *)error
{
	ZGDocumentWindowController *windowController = _windowController;
	ZGVariableType dataType = _dataType;
	
	_searchData.pointerSize = windowController.currentProcess.pointerSize;
	
	// Set default search arguments
	_searchData.epsilon = DEFAULT_FLOATING_POINT_EPSILON;
	_searchData.rangeValue = NULL;
	
	ZGFunctionType functionType = _functionType;
	
	ZGProcessType processType = windowController.currentProcess.type;
	BOOL is64Bit = ZG_PROCESS_TYPE_IS_64_BIT(processType);
	
	_searchData.shouldCompareStoredValues = ZGIsFunctionTypeStore(functionType);
	
	if (!_searchData.shouldCompareStoredValues)
	{
		NSString *searchValueInput = _searchValueString;
		NSString *finalSearchExpression = ZGIsNumericalDataType(dataType) ? [ZGCalculator evaluateExpression:searchValueInput] : searchValueInput;
		
		if (ZGIsNumericalDataType(dataType) && !ZGIsFunctionTypeStore(_functionType) && !ZGIsValidNumber(finalSearchExpression))
		{
			if (error != NULL)
			{
				*error = [NSError errorWithDomain:ZGRetrieveFlagsErrorDomain code:0 userInfo:@{ZGRetrieveFlagsErrorDescriptionKey : ZGLocalizableSearchDocumentString(@"invalidNumericalSearchExpressionErrorMessage")}];
			}
			return NO;
		}
		
		ZGMemorySize dataSize = 0;
		void *searchValue = ZGValueFromString(is64Bit, finalSearchExpression, dataType, &dataSize);
		if (searchValue != NULL)
		{
			_searchData.searchValue = searchValue;
		}
		else
		{
			if (error != NULL)
			{
				*error = [NSError errorWithDomain:ZGRetrieveFlagsErrorDomain code:0 userInfo:@{ZGRetrieveFlagsErrorDescriptionKey : @""}];
			}
			NSLog(@"Failed to retrieve search value from %@", finalSearchExpression);
			return NO;
		}
		
		if (_searchData.shouldIncludeNullTerminator)
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
		
		_searchData.dataSize = dataSize;
		
		if (dataType == ZGByteArray)
		{
			// If this returns NULL, then there just were no wildcards
			_searchData.byteArrayFlags = ZGAllocateFlagsForByteArrayWildcards(finalSearchExpression);
		}
	}
	else
	{
		if (dataType == ZGString8 || dataType == ZGString16 || dataType == ZGByteArray)
		{
			if (error != NULL)
			{
				*error = [NSError errorWithDomain:ZGRetrieveFlagsErrorDomain code:0 userInfo:@{ZGRetrieveFlagsErrorDescriptionKey : ZGLocalizableSearchDocumentString(dataType == ZGByteArray ? @"storedValueSearchUnsupportedForByteArrays" : @"storedValueSearchUnsupportedForStrings")}];
			}
			return NO;
		}
		
		_searchData.searchValue = NULL;
		_searchData.dataSize = ZGDataSizeFromNumericalDataType(processType, dataType);
		
		if (ZGIsFunctionTypeLinear(functionType))
		{
			NSString *linearExpression = _searchValueString;
			NSString *additiveConstantString = nil;
			NSString *multiplicativeConstantString = nil;
			
			if (![ZGCalculator parseLinearExpression:linearExpression andGetAdditiveConstant:&additiveConstantString multiplicateConstant:&multiplicativeConstantString])
			{
				if (error != NULL)
				{
					*error = [NSError errorWithDomain:ZGRetrieveFlagsErrorDomain code:0 userInfo:@{ZGRetrieveFlagsErrorDescriptionKey : ZGLocalizableSearchDocumentString(@"linearExpressionParseFailureErrorMessage")}];
				}
				return NO;
			}
			
			_searchData.additiveConstant = ZGValueFromString(is64Bit, additiveConstantString, dataType, NULL);
			_searchData.multiplicativeConstant = ZGValueFromString(is64Bit, multiplicativeConstantString, dataType, NULL);
			
			if (_searchData.additiveConstant == NULL || _searchData.multiplicativeConstant == NULL)
			{
				if (error != NULL)
				{
					*error = [NSError errorWithDomain:ZGRetrieveFlagsErrorDomain code:0 userInfo:@{ZGRetrieveFlagsErrorDescriptionKey : ZGLocalizableSearchDocumentString(@"linearExpressionParseFailureErrorMessage")}];
				}
				return NO;
			}
		}
	}
	
	if (CFByteOrderGetCurrent() != _documentData.byteOrderTag && ZGSupportsEndianness(dataType))
	{
		_searchData.bytesSwapped = YES;
		if (ZGSupportsSwappingBeforeSearch(functionType, dataType))
		{
			void *searchValue = _searchData.searchValue;
			assert(searchValue != NULL);
			void *swappedValue = ZGSwappedValue(is64Bit, searchValue, dataType, _searchData.dataSize);
			if (swappedValue != NULL)
			{
				_searchData.swappedValue = swappedValue;
			}
			else
			{
				if (error != NULL)
				{
					*error = [NSError errorWithDomain:ZGRetrieveFlagsErrorDomain code:0 userInfo:@{ZGRetrieveFlagsErrorDescriptionKey : @""}];
				}
				NSLog(@"Failed allocating memory for swapped value..");
				return NO;
			}
		}
	}
	else
	{
		_searchData.bytesSwapped = NO;
		_searchData.swappedValue = NULL;
	}
	
	_searchData.dataAlignment =
		_documentData.ignoreDataAlignment
		? sizeof(int8_t)
		: ZGDataAlignment(processType, dataType, _searchData.dataSize);
	
	if (![self retrieveFlagsSearchDataWithDataType:dataType functionType:functionType error:error])
	{
		return NO;
	}
	
	ZGMemoryAddress beginningAddress = 0x0;
	
	BOOL retrievedBoundaryAddress =
	[self
	 getBoundaryAddress:&beginningAddress
	 fromStringValue:_documentData.beginningAddressStringValue
	 label:ZGLocalizableSearchDocumentString(@"beginningAddressLabel")
	 error:error];
	
	if (!retrievedBoundaryAddress) return NO;
	
	_searchData.beginAddress = beginningAddress;
	
	ZGMemoryAddress endingAddress = MAX_MEMORY_ADDRESS;
	
	retrievedBoundaryAddress =
	[self
	 getBoundaryAddress:&endingAddress
	 fromStringValue:_documentData.endingAddressStringValue
	 label:ZGLocalizableSearchDocumentString(@"endingAddressLabel")
	 error:error];
	
	if (!retrievedBoundaryAddress) return NO;
	
	_searchData.endAddress = endingAddress;
	
	if (_searchData.beginAddress >= _searchData.endAddress)
	{
		if (error != NULL)
		{
			*error = [NSError errorWithDomain:ZGRetrieveFlagsErrorDomain code:0 userInfo:@{ZGRetrieveFlagsErrorDescriptionKey : ZGLocalizableSearchDocumentString(@"endingAddressIsNotGreaterThanBeginningAddressErrorMessage")}];
		}
		return NO;
	}
	
	return YES;
}

- (void)searchVariables:(NSArray<ZGVariable *> *)variables byNarrowing:(BOOL)isNarrowing usingCompletionBlock:(dispatch_block_t)completeSearchBlock
{
	ZGDocumentWindowController *windowController = _windowController;
	ZGProcess *currentProcess = windowController.currentProcess;
	ZGVariableType dataType = _dataType;
	ZGSearchResults *firstSearchResults = nil;
	if (isNarrowing)
	{
		ZGMemorySize hostAlignment = ZGDataAlignment(ZG_PROCESS_TYPE_HOST, dataType, _searchData.dataSize);
		BOOL unalignedAddressAccess = NO;
		
		NSMutableData *firstResultSets = [NSMutableData data];
		for (ZGVariable *variable in variables)
		{
			ZGMemoryAddress variableAddress = variable.address;
			if (_searchData.pointerSize == sizeof(ZGMemoryAddress))
			{
				[firstResultSets appendBytes:&variableAddress length:sizeof(variableAddress)];
			}
			else
			{
				ZG32BitMemoryAddress halfVariableAddress = (ZG32BitMemoryAddress)variableAddress;
				[firstResultSets appendBytes:&halfVariableAddress length:sizeof(halfVariableAddress)];
			}
			
			if (!unalignedAddressAccess && variableAddress % hostAlignment != 0)
			{
				unalignedAddressAccess = YES;
			}
		}
		firstSearchResults = [[ZGSearchResults alloc] initWithResultSets:@[firstResultSets] dataSize:_searchData.dataSize pointerSize:_searchData.pointerSize unalignedAccess:unalignedAddressAccess];
	}
	
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		if (!isNarrowing)
		{
			self->_temporarySearchResults = ZGSearchForData(currentProcess.processTask, self->_searchData, self, dataType, (ZGVariableQualifier)self->_documentData.qualifierTag, self->_functionType);
		}
		else
		{
			self->_temporarySearchResults = ZGNarrowSearchForData(currentProcess.processTask, self->_searchData, self, dataType, self->_documentData.qualifierTag, self->_functionType, firstSearchResults, (self->_searchResults.dataType == dataType && currentProcess.pointerSize == self->_searchResults.pointerSize) ? self->_searchResults : nil);
		}
		
		self->_temporarySearchResults.dataType = dataType;
		self->_temporarySearchResults.enabled = self->_allowsNarrowing;
		
		dispatch_async(dispatch_get_main_queue(), completeSearchBlock);
	});
}

- (void)searchVariablesWithString:(NSString *)searchStringValue withDataType:(ZGVariableType)dataType functionType:(ZGFunctionType)functionType allowsNarrowing:(BOOL)allowsNarrowing
{
	_dataType = dataType;
	_functionType = functionType;
	_searchValueString = [searchStringValue copy];
	_allowsNarrowing = allowsNarrowing;
	
	NSError *error = nil;
	if (![self retrieveSearchDataWithError:&error])
	{
		ZGRunAlertPanelWithOKButton(ZGLocalizableSearchDocumentString(@"invalidSearchInputAlertTitle"), ZGUnwrapNullableObject(error.userInfo[ZGRetrieveFlagsErrorDescriptionKey]));
		return;
	}
	
	NSMutableArray<ZGVariable *> *notSearchedVariables = [[NSMutableArray alloc] init];
	NSMutableArray<ZGVariable *> *searchedVariables = [[NSMutableArray alloc] init];
	
	BOOL isNarrowingSearch = allowsNarrowing && [self isInNarrowSearchMode];
	
	// Add all variables whose value should not be searched for, first
	for (ZGVariable *variable in _documentData.variables)
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
	
	id searchDataActivity = [[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiated reason:@"Searching Data"];
	
	NSArray<ZGVariable *> *oldVariables = _documentData.variables;
	
	_documentData.variables = notSearchedVariables;
	[_windowController.variablesTableView reloadData];
	
	[self searchVariables:searchedVariables byNarrowing:isNarrowingSearch usingCompletionBlock:^ {
		if (self->_windowController != nil)
		{
			self->_searchData.searchValue = NULL;
			self->_searchData.swappedValue = NULL;
			
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
	ZGDocumentWindowController *windowController = _windowController;
	if (_searchProgress.progressType == ZGSearchProgressMemoryScanning)
	{
		[windowController setStatusString:ZGLocalizableSearchDocumentString(@"cancelingSearchStatusLabel")];
	}
	else if (_searchProgress.progressType == ZGSearchProgressMemoryStoring)
	{
		[windowController setStatusString:ZGLocalizableSearchDocumentString(@"cancelingStoringValuesStatusLabel")];
	}
	
	_searchProgress.shouldCancelSearch = YES;
}

#pragma mark Storing all values

- (void)storeAllValues
{
	[self prepareTask];
	
	ZGDocumentWindowController *windowController = _windowController;
	
	[windowController setStatusString:ZGLocalizableSearchDocumentString(@"storingValuesStatusLabel")];
	
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		__block ZGStoredData *tempSavedData = [ZGStoredData storedDataFromProcessTask:windowController.currentProcess.processTask];
		
		dispatch_async(dispatch_get_main_queue(), ^{
			if (!self->_searchProgress.shouldCancelSearch)
			{
				self->_searchData.savedData = tempSavedData;
				tempSavedData = nil;
				windowController.storeValuesButton.image = [NSImage imageNamed:@"container_filled"];
				
				if (![[self class] hasStoredValueTokenFromExpression:self->_documentData.searchValue])
				{
					[windowController insertStoredValueToken];
				}
			}
			
			[windowController updateNumberOfValuesDisplayedStatus];
			
			windowController.progressIndicator.doubleValue = 0;
			
			[self resumeFromTask];
		});
	});
}

@end
