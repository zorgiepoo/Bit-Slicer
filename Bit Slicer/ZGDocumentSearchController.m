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
	NSString *_searchValueString;
	ZGSearchData * _Nonnull _searchData;
	ZGMachBinaryAnnotationInfo _machBinaryAnnotationInfo;
	dispatch_queue_t _machBinaryAnnotationInfoQueue;
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
		
		_machBinaryAnnotationInfoQueue = dispatch_queue_create("com.zgcoder.search-mach-binary-info", DISPATCH_QUEUE_SERIAL);
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

- (BOOL)isVariableNarrowable:(ZGVariable *)variable dataType:(ZGVariableType)dataType pointerAddressSearch:(BOOL)pointerAddressSearch
{
	// If we are doing a pointer address search, the variable must have a dynamic pointer address
	// If we are doing a regular value search, variable could be a normal address or dynamic pointer address
	return (variable.enabled && variable.type == dataType && !variable.isFrozen) && (!pointerAddressSearch || variable.usesDynamicPointerAddress) && !variable.usesDynamicSymbolAddress;
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

- (void)progress:(ZGSearchProgress *)searchProgress advancedWithResultSet:(NSData *)resultSet resultType:(ZGSearchResultType)resultType dataType:(ZGVariableType)dataType stride:(ZGMemorySize)stride
{
	ZGDocumentWindowController *windowController = _windowController;
	if (!_searchProgress.shouldCancelSearch && windowController != nil)
	{
		NSUInteger currentVariableCount = _documentData.variables.count;
		
		NSTableView *variablesTableView = windowController.variablesTableView;
		
		// Limit the number of intermediate search results to show to be relatively small
		// (a little bit larger than what can be displayed on screen without scrolling)
		// This is so we don't spend to much time annotating/relativizing variables before the search is finished
		NSUInteger maxNumberOfVariablesToFetch = MIN((NSUInteger)(variablesTableView.visibleRect.size.height / variablesTableView.rowHeight * 1.5), MAX_NUMBER_OF_VARIABLES_TO_FETCH);
		if (currentVariableCount < maxNumberOfVariablesToFetch && resultSet.length > 0)
		{
			// These progress search results are thrown away,
			// so doesn't matter if accesses are unaligned or not
			ZGSearchResults *searchResults = [[ZGSearchResults alloc] initWithResultSets:@[resultSet] resultType:resultType dataType:dataType stride:stride unalignedAccess:YES];
			
			[self fetchNumberOfVariables:maxNumberOfVariablesToFetch - currentVariableCount finishingSearch:NO fromResults:searchResults];
			[variablesTableView reloadData];
		}
		
		[self updateProgressBarFromProgress:searchProgress];
	}
}

// Note: this can be called multiple times if maxProgress is unknown the first time
- (void)progressWillBegin:(ZGSearchProgress *)searchProgress
{
	_windowController.progressIndicator.maxValue = (double)searchProgress.maxProgress;
	[self updateProgressBarFromProgress:searchProgress];
	
	_searchProgress = searchProgress;
}

#pragma mark Searching

- (void)fetchNumberOfVariables:(NSUInteger)numberOfVariables finishingSearch:(BOOL)finishingSearch fromResults:(ZGSearchResults *)searchResults
{
	if (searchResults.count == 0) return;
	
	if (numberOfVariables > searchResults.count)
	{
		numberOfVariables = searchResults.count;
	}
	
	NSMutableArray<ZGVariable *> *allVariables = [[NSMutableArray alloc] initWithArray:_documentData.variables];
	NSMutableArray<ZGVariable *> *newVariables = [NSMutableArray array];
	
	ZGDocumentWindowController *windowController = _windowController;
	
	ZGVariableQualifier qualifier = (ZGVariableQualifier)_documentData.qualifierTag;
	CFByteOrder byteOrder = _documentData.byteOrderTag;
	ZGProcess *currentProcess = windowController.currentProcess;
	ZGMemorySize pointerSize = currentProcess.pointerSize;
	
	ZGMemorySize dataSize = _searchData.dataSize;
	ZGSearchResultType resultType = searchResults.resultType;
	
	ZGMemorySize searchResultsCount = searchResults.count;
	
	[searchResults enumerateWithCount:numberOfVariables removeResults:YES usingBlock:^(const void *data, BOOL * __unused stop) {
		BOOL enabled = (!finishingSearch || searchResultsCount > 1);
		
		switch (resultType)
		{
			case ZGSearchResultTypeDirect:
			{
				ZGMemoryAddress variableAddress;
				switch (pointerSize)
				{
					case sizeof(ZGMemoryAddress):
						variableAddress = *((const ZGMemoryAddress *)data);
						break;
					case sizeof(ZG32BitMemoryAddress):
						variableAddress = *((const ZG32BitMemoryAddress *)data);
						break;
					default:
						abort();
				}
				
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
				
				break;
			}
			case ZGSearchResultTypeIndirect:
			{
				//	Struct {
				//		uintptr_t baseAddress;
				//		uint16_t numLevels;
				//		uint16_t offsets[MAX_NUM_LEVELS];
				//		uint8_t padding[N];
				//	}
				
				ZGMemoryAddress baseAddress;
				switch (pointerSize)
				{
					case sizeof(ZGMemoryAddress):
						baseAddress = *((const ZGMemoryAddress *)data);
						break;
					case sizeof(ZG32BitMemoryAddress):
						baseAddress = *((const ZG32BitMemoryAddress *)data);
						break;
					default:
						abort();
				}
				
				uint16_t numberOfLevels = *(const uint16_t *)((const void *)((const uint8_t *)data) + pointerSize);
				const uint16_t *offsets = (const uint16_t *)((const void *)((const uint8_t *)data + pointerSize + sizeof(numberOfLevels)));
				
				NSString *addressFormula = [NSString stringWithFormat:@"0x%llX", baseAddress];
				for (uint16_t level = 0; level < numberOfLevels; level++)
				{
					uint16_t offsetIndex = numberOfLevels - level - 1;
					uint16_t offset = offsets[offsetIndex];
					
					addressFormula =
						offset != 0x0 ?
						[NSString stringWithFormat:@"[%@] + 0x%X", addressFormula, offset] :
						[NSString stringWithFormat:@"[%@]", addressFormula];
				}
				
				ZGVariable *newVariable =
				[[ZGVariable alloc]
				 initWithValue:NULL
				 size:dataSize
				 address:baseAddress
				 type:searchResults.dataType
				 qualifier:qualifier
				 pointerSize:pointerSize
				 description:[[NSAttributedString alloc] initWithString:@""]
				 enabled:enabled
				 byteOrder:byteOrder];
				
				// Set the address formula to use a dynamic address but do not set usesDynamicAddress to YES yet
				// When we relativize variables we may mark them as dynamic addresses, or when annotations are
				// finished below.
				newVariable.addressFormula = addressFormula;
				
				[newVariables addObject:newVariable];
				
				break;
			}
		}
	}];
	
	dispatch_async(_machBinaryAnnotationInfoQueue, ^{
		__block ZGMachBinaryAnnotationInfo annotationInfo;
		if (self->_machBinaryAnnotationInfo.machBinaries == nil)
		{
			self->_machBinaryAnnotationInfo = [ZGVariableController machBinaryAnnotationInfoForProcess:currentProcess];
		}
		
		// Copy annotation info
		annotationInfo = self->_machBinaryAnnotationInfo;
		
		dispatch_async(dispatch_get_main_queue(), ^{
			// Waiting for completion would lead to a bad user experience and there is no need to
			[ZGVariableController annotateVariables:newVariables annotationInfo:annotationInfo process:currentProcess symbols:YES async:YES completionHandler:^{
				if (resultType == ZGSearchResultTypeIndirect)
				{
					// Make sure all our new indirect variables are dynamic if they haven't been marked dynamic
					// when annotating/relativizing them.
					for (ZGVariable *variable in newVariables)
					{
						variable.usesDynamicAddress = YES;
					}
				}
				
				[windowController.variablesTableView reloadData];
			}];
		});
	});
	
	[allVariables addObjectsFromArray:newVariables];
	_documentData.variables = [NSArray arrayWithArray:allVariables];
	
	if (_documentData.variables.count > 0)
	{
		[windowController.tableController updateVariableValuesInRange:NSMakeRange(allVariables.count - newVariables.count, newVariables.count)];
	}
}

- (void)fetchNumberOfVariables:(NSUInteger)numberOfVariables
{
	[self fetchNumberOfVariables:numberOfVariables finishingSearch:NO fromResults:_searchResults];
}

- (void)_fetchVariablesFromResultsAndFinishedSearch:(BOOL)finishedSearch
{
	if (_documentData.variables.count < MAX_NUMBER_OF_VARIABLES_TO_FETCH)
	{
		[self fetchNumberOfVariables:(MAX_NUMBER_OF_VARIABLES_TO_FETCH - _documentData.variables.count) finishingSearch:finishedSearch fromResults:_searchResults];
	}
}

- (void)fetchVariablesFromResults
{
	[self _fetchVariablesFromResultsAndFinishedSearch:NO];
}

- (void)fetchVariablesFromResultsAndFinishedSearch
{
	[self _fetchVariablesFromResultsAndFinishedSearch:YES];
}

- (void)finalizeSearchWithOldVariables:(NSArray<ZGVariable *> *)oldVariables andNotSearchedVariables:(NSArray<ZGVariable *> *)notSearchedVariables
{
	ZGDocumentWindowController *windowController = _windowController;
	
	if (!_searchProgress.shouldCancelSearch)
	{
		ZGDeliverUserNotification(ZGLocalizableSearchDocumentString(@"searchFinishedNotificationTitle"), windowController.currentProcess.name, [self numberOfVariablesFoundDescriptionFromProgress:_searchProgress], nil);
		
		if (notSearchedVariables.count + _temporarySearchResults.count != oldVariables.count + _searchResults.count)
		{
			windowController.undoManager.actionName = ZGLocalizableSearchDocumentString(@"undoSearchAction");
			[(ZGDocumentWindowController *)[windowController.undoManager prepareWithInvocationTarget:windowController] updateVariables:oldVariables searchResults:_searchResults];
			
			_searchResults = _temporarySearchResults;
			_documentData.variables = notSearchedVariables;
			[self fetchVariablesFromResultsAndFinishedSearch];
			[windowController.variablesTableView reloadData];
			[windowController markDocumentChange];
		}
		else
		{
			// New search didn't return any new results, so let's show old variables again
			_documentData.variables = oldVariables;
			[windowController.variablesTableView reloadData];
		}
	}
	else
	{
		_documentData.variables = oldVariables;
		[windowController.variablesTableView reloadData];
	}
	
	dispatch_async(_machBinaryAnnotationInfoQueue, ^{
		self->_machBinaryAnnotationInfo.machBinaries = nil;
		self->_machBinaryAnnotationInfo.machFilePathDictionary = nil;
	});
	
	[windowController updateOcclusionActivity];
	
	_temporarySearchResults = nil;
	
	[windowController updateNumberOfValuesDisplayedStatus];
	
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
				_searchData.rangeValue = ZGValueFromString(currentProcess.type, flagsExpression, dataType, &rangeDataSize);
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
				void *epsilon = ZGValueFromString(currentProcess.type, flagsExpression, ZGDouble, &epsilonDataSize);
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

- (BOOL)retrieveSearchDataWithDataType:(ZGVariableType)directDataType addressSearch:(BOOL)addressSearch error:(NSError * __autoreleasing *)error
{
	ZGVariableType dataType = addressSearch ? ZGPointer : directDataType;
	
	ZGDocumentWindowController *windowController = _windowController;
	
	_searchData.pointerSize = windowController.currentProcess.pointerSize;
	
	// Set default search arguments
	_searchData.epsilon = DEFAULT_FLOATING_POINT_EPSILON;
	_searchData.rangeValue = NULL;
	
	ZGFunctionType functionType = _functionType;
	
	ZGProcessType processType = windowController.currentProcess.type;
	
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
		void *searchValue = ZGValueFromString(processType, finalSearchExpression, dataType, &dataSize);
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
			
			_searchData.additiveConstant = ZGValueFromString(processType, additiveConstantString, dataType, NULL);
			_searchData.multiplicativeConstant = ZGValueFromString(processType, multiplicativeConstantString, dataType, NULL);
			
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
	
	if (!addressSearch && CFByteOrderGetCurrent() != _documentData.byteOrderTag && ZGSupportsEndianness(dataType))
	{
		_searchData.bytesSwapped = YES;
		if (ZGSupportsSwappingBeforeSearch(functionType, dataType))
		{
			void *searchValue = _searchData.searchValue;
			assert(searchValue != NULL);
			void *swappedValue = ZGSwappedValue(processType, searchValue, dataType, _searchData.dataSize);
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
	
	if (!addressSearch && ![self retrieveFlagsSearchDataWithDataType:dataType functionType:functionType error:error])
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
	
	if (_documentData.searchAddressOffsetComparison == ZGSearchAddressOffsetComparisonSame)
	{
		_searchData.indirectOffsetMaxComparison = NO;
		_searchData.indirectOffset = (uint16_t)_documentData.searchAddressSameOffset;
	}
	else
	{
		_searchData.indirectOffsetMaxComparison = YES;
		_searchData.indirectOffset = (uint16_t)_documentData.searchAddressMaxOffset;
	}
	
	_searchData.indirectMaxLevels = (uint16_t)_documentData.searchAddressMaxLevels;
	_searchData.indirectStopAtStaticAddresses = YES;
	_searchData.filterHeapAndStackData = addressSearch;
	
	return YES;
}

- (void)searchVariablesWithString:(NSString *)searchStringValue dataType:(ZGVariableType)dataType pointerAddressSearch:(BOOL)pointerAddressSearch functionType:(ZGFunctionType)functionType storeValuesAfterSearch:(BOOL)storeValuesAfterSearch
{
	_dataType = dataType;
	_functionType = functionType;
	_searchValueString = [searchStringValue copy];
	
	NSError *error = nil;
	if (![self retrieveSearchDataWithDataType:dataType addressSearch:pointerAddressSearch error:&error])
	{
		ZGRunAlertPanelWithOKButton(ZGLocalizableSearchDocumentString(@"invalidSearchInputAlertTitle"), ZGUnwrapNullableObject(error.userInfo[ZGRetrieveFlagsErrorDescriptionKey]));
		return;
	}
	
	NSMutableArray<ZGVariable *> *notSearchedVariables = [[NSMutableArray alloc] init];
	NSMutableArray<ZGVariable *> *searchedVariables = [[NSMutableArray alloc] init];
	
	BOOL isNarrowingSearch = [_documentData.variables zgHasObjectMatchingCondition:^(ZGVariable *variable) {
		return [self isVariableNarrowable:variable dataType:dataType pointerAddressSearch:pointerAddressSearch];
	}];
	
	ZGDocumentWindowController *windowController = _windowController;
	
	NSArray<ZGVariable *> *variables = _documentData.variables;
	
	// Compute indirectMaxLevelsForCurrentSearchResults (if relevant)
	uint16_t indirectMaxLevelsForCurrentSearchResults;
	
	if (!isNarrowingSearch)
	{
		// Regular initial value search with indirect variable searching is not possible
		// For initial address search, indirectMaxLevelsForCurrentSearchResults is not used
		indirectMaxLevelsForCurrentSearchResults = 0;
	}
	else /* if (isNarrowingSearch) */
	{
		// Figure out if we are narrowing regular variables or indirect variables
		// Figure out what max indirect level to use too if we're narrowing indirect variables
		// Note we may be narrowing indirect variables for a value search or an address search
		
		uint16_t computedIndirectMaxLevels = 0;
		uint16_t numberOfIndirectNarrowingVariables = 0;
		uint16_t numberOfDirectNarrowingVariables = 0;
		
		for (ZGVariable *variable in variables)
		{
			if ([self isVariableNarrowable:variable dataType:dataType pointerAddressSearch:pointerAddressSearch])
			{
				uint16_t numberOfDynamicPointersInAddress = (uint16_t)(variable.numberOfDynamicPointersInAddress);
				if (numberOfDynamicPointersInAddress > computedIndirectMaxLevels)
				{
					computedIndirectMaxLevels = numberOfDynamicPointersInAddress;
				}
				
				if (numberOfDynamicPointersInAddress > 0)
				{
					numberOfIndirectNarrowingVariables++;
				}
				else
				{
					numberOfDirectNarrowingVariables++;
				}
			}
		}
		
		// Rely on current indirect search results if available
		if (_searchResults.count > 0)
		{
			if (_searchResults.resultType == ZGSearchResultTypeIndirect)
			{
				indirectMaxLevelsForCurrentSearchResults = (computedIndirectMaxLevels >= _searchResults.indirectMaxLevels) ? computedIndirectMaxLevels : _searchResults.indirectMaxLevels;
			}
			else
			{
				indirectMaxLevelsForCurrentSearchResults = 0;
			}
		}
		else
		{
			indirectMaxLevelsForCurrentSearchResults = (numberOfIndirectNarrowingVariables > numberOfDirectNarrowingVariables) ? computedIndirectMaxLevels : 0;
		}
	}
	
	// Prefer requested max levels for initial and narrowing pointer address search for the next search,
	// as long as it's >= indirectMaxLevelsForCurrentSearchResults
	uint16_t indirectMaxLevelsForNextSearchResults;
	if (pointerAddressSearch)
	{
		indirectMaxLevelsForNextSearchResults = (indirectMaxLevelsForCurrentSearchResults >= _searchData.indirectMaxLevels) ? indirectMaxLevelsForCurrentSearchResults : _searchData.indirectMaxLevels;
	}
	else
	{
		indirectMaxLevelsForNextSearchResults = 0;
	}
	
	// Split not searched variables and searched variables
		
	for (ZGVariable *variable in variables)
	{
		if (!isNarrowingSearch)
		{
			// Nothing to narrow
			[notSearchedVariables addObject:variable];
		}
		else if ([self isVariableNarrowable:variable dataType:dataType pointerAddressSearch:pointerAddressSearch])
		{
			if (pointerAddressSearch)
			{
				// Variable must have dynamic pointer address
				[searchedVariables addObject:variable];
			}
			else if (indirectMaxLevelsForCurrentSearchResults > 0)
			{
				// Only narrow search variable if it has dynamic pointer address
				if (variable.usesDynamicPointerAddress)
				{
					[searchedVariables addObject:variable];
				}
				else
				{
					[notSearchedVariables addObject:variable];
				}
			}
			else
			{
				// Regular value narrow search, only narrow search variable if it does not have dynamic pointer address
				if (!variable.usesDynamicPointerAddress)
				{
					[searchedVariables addObject:variable];
				}
				else
				{
					[notSearchedVariables addObject:variable];
				}
			}
		}
		else
		{
			// Narrowing search, but variable is not narrowable
			[notSearchedVariables addObject:variable];
		}
	}
	
	[self prepareTask];
	
	id searchDataActivity = [[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiated reason:@"Searching Data"];
	
	NSArray<ZGVariable *> *oldVariables = _documentData.variables;
	
	_documentData.variables = notSearchedVariables;
	[windowController.variablesTableView reloadData];
	
	// Build first search results for narrow search
	ZGProcess *currentProcess = windowController.currentProcess;
	ZGSearchResults *firstSearchResults = nil;
	if (isNarrowingSearch)
	{
		ZGMemorySize hostAlignment = ZGDataAlignment(ZG_PROCESS_TYPE_HOST, dataType, _searchData.dataSize);
		BOOL unalignedAddressAccess = NO;
		
		ZGMemorySize currentIndirectStride = (indirectMaxLevelsForCurrentSearchResults == 0) ? 0 : [ZGSearchResults indirectStrideWithMaxNumberOfLevels:indirectMaxLevelsForCurrentSearchResults pointerSize:currentProcess.pointerSize];
		
		NSMutableArray<NSString *> *indirectFailedImages;
		void *indirectBuffer;
		if (currentIndirectStride > 0)
		{
			indirectBuffer = calloc(1, currentIndirectStride);
			assert(indirectBuffer != NULL);
			indirectFailedImages = [NSMutableArray array];
		}
		else
		{
			indirectBuffer = NULL;
			indirectFailedImages = nil;
		}
		
		ZGMemorySize pointerSize = _searchData.pointerSize;
		
		NSMutableData *firstResultSets = [NSMutableData data];
		for (ZGVariable *variable in searchedVariables)
		{
			ZGMemoryAddress variableAddress = variable.address;
			
			if (indirectMaxLevelsForCurrentSearchResults == 0)
			{
				if (pointerSize == sizeof(ZGMemoryAddress))
				{
					[firstResultSets appendBytes:&variableAddress length:sizeof(variableAddress)];
				}
				else
				{
					ZG32BitMemoryAddress halfVariableAddress = (ZG32BitMemoryAddress)variableAddress;
					[firstResultSets appendBytes:&halfVariableAddress length:sizeof(halfVariableAddress)];
				}
			}
			else
			{
				if ([ZGCalculator extractIndirectAddressesAndOffsetsFromIntoBuffer:indirectBuffer expression:variable.addressFormula process:currentProcess failedImages:indirectFailedImages maxLevels:indirectMaxLevelsForCurrentSearchResults stride:currentIndirectStride])
				{
					[firstResultSets appendBytes:indirectBuffer length:currentIndirectStride];
				}
				else
				{
					NSLog(@"Error: failed to parse indirect variable expression: %@", variable.addressFormula);
				}
			}
			
			if (!unalignedAddressAccess && variableAddress % hostAlignment != 0)
			{
				unalignedAddressAccess = YES;
			}
		}
		
		if (indirectMaxLevelsForCurrentSearchResults == 0)
		{
			// Regular narrow search involving no indirect variables
			firstSearchResults = [[ZGSearchResults alloc] initWithResultSets:@[firstResultSets] resultType:ZGSearchResultTypeDirect dataType:dataType stride:_searchData.pointerSize unalignedAccess:unalignedAddressAccess];
		}
		else
		{
			// Narrow search involving indirect variables
			
			// Check if previous search results should be combined with new search results from the table
			ZGSearchResults *newSearchResults = [[ZGSearchResults alloc] initWithResultSets:@[firstResultSets] resultType:ZGSearchResultTypeIndirect dataType:dataType stride:currentIndirectStride unalignedAccess:unalignedAddressAccess];
			newSearchResults.indirectMaxLevels = indirectMaxLevelsForCurrentSearchResults;
			
			if (_searchResults.count > 0 && _searchResults.dataType == dataType && _searchResults.resultType == ZGSearchResultTypeIndirect)
			{
				// This will also make the strides of the search results match if necessary
				// This should be rare and should only happen if the user manually adds indirect variables
				// to the table whose level exceeds the current search result's max level
				firstSearchResults = [newSearchResults indirectSearchResultsByAppendingIndirectSearchResults:(ZGSearchResults * _Nonnull)_searchResults];
			}
			else
			{
				firstSearchResults = newSearchResults;
			}
		}
	}
	
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		if (pointerAddressSearch)
		{
			// Pointer address searches for initial and narrow searches
			
			NSArray<ZGMachBinary *> *machBinaries = [ZGMachBinary machBinariesInProcess:currentProcess];
			
			NSArray<NSValue *> *totalStaticSegmentRanges = [machBinaries zgMapUsingBlock:^id _Nonnull(ZGMachBinary *__unsafe_unretained  _Nonnull machBinary) {
				ZGMachBinaryInfo *machBinaryInfo = [machBinary machBinaryInfoInProcess:currentProcess];
				
				return [NSValue valueWithRange:machBinaryInfo.totalSegmentRange];
			}];
			
			self->_searchData.totalStaticSegmentRanges = totalStaticSegmentRanges;
			
			self->_temporarySearchResults = ZGSearchForIndirectPointer(currentProcess.processTask, self->_searchData, self, indirectMaxLevelsForNextSearchResults, self->_dataType, firstSearchResults);
		}
		else if (!isNarrowingSearch)
		{
			// Regular initial value search
			self->_temporarySearchResults = ZGSearchForData(currentProcess.processTask, self->_searchData, self, dataType, (ZGVariableQualifier)self->_documentData.qualifierTag, self->_functionType);
		}
		else if (indirectMaxLevelsForCurrentSearchResults > 0)
		{
			// Narrow value search involving indirect variables
			self->_temporarySearchResults = ZGNarrowIndirectSearchForData(currentProcess.processTask, self->_searchData, self, dataType, self->_documentData.qualifierTag, self->_functionType, firstSearchResults);
		}
		else
		{
			// Regular Narrow value search
			self->_temporarySearchResults = ZGNarrowSearchForData(currentProcess.processTask, self->_searchData, self, dataType, self->_documentData.qualifierTag, self->_functionType, firstSearchResults, (self->_searchResults.dataType == dataType && currentProcess.pointerSize == self->_searchResults.stride) ? self->_searchResults : nil);
		}
		
		dispatch_async(dispatch_get_main_queue(), ^{
			if (self->_windowController != nil)
			{
				self->_searchData.searchValue = NULL;
				self->_searchData.swappedValue = NULL;
				
				if (searchDataActivity != nil)
				{
					[[NSProcessInfo processInfo] endActivity:searchDataActivity];
				}
				
				[self finalizeSearchWithOldVariables:oldVariables andNotSearchedVariables:notSearchedVariables];
				
				if (storeValuesAfterSearch && self->_searchData.savedData != nil)
				{
					[self storeAllValuesAndAfterSearches:YES];
				}
			}
		});
	});
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

- (BOOL)hasSavedValues
{
	return _searchData.savedData != nil;
}

- (void)updateStoreValuesButtonImageWithStoringValuesAfterSearches:(BOOL)storingValuesAfterSearches
{
	ZGDocumentWindowController *windowController = _windowController;
	
	if (_searchData.savedData == nil)
	{
		windowController.storeValuesButton.image = [NSImage imageNamed:@"container"];
	}
	else if (storingValuesAfterSearches)
	{
		windowController.storeValuesButton.image = [NSImage imageNamed:@"container_filled_record"];
	}
	else
	{
		windowController.storeValuesButton.image = [NSImage imageNamed:@"container_filled"];
	}
}

- (void)storeAllValuesAndAfterSearches:(BOOL)storeValuesAfterSearches
{
	[self prepareTask];
	
	ZGDocumentWindowController *windowController = _windowController;
	
	[windowController setStatusString:ZGLocalizableSearchDocumentString(@"storingValuesStatusLabel")];
	
	ZGMemoryAddress beginAddress = _searchData.beginAddress;
	ZGMemoryAddress endAddress = _searchData.endAddress;
	ZGProtectionMode protectionMode = _searchData.protectionMode;
	BOOL includeSharedMemory = _searchData.includeSharedMemory;
	
	ZGMemoryMap processTask = windowController.currentProcess.processTask;
	
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		__block ZGStoredData *tempSavedData = [ZGStoredData storedDataFromProcessTask:processTask beginAddress:beginAddress endAddress:endAddress protectionMode:protectionMode includeSharedMemory:includeSharedMemory];
		
		dispatch_async(dispatch_get_main_queue(), ^{
			if (!self->_searchProgress.shouldCancelSearch)
			{
				self->_searchData.savedData = tempSavedData;
				tempSavedData = nil;
				[self updateStoreValuesButtonImageWithStoringValuesAfterSearches:storeValuesAfterSearches];
				
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
