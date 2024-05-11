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

#import "ZGCalculator.h"
#import "NSStringAdditions.h"
#import "ZGVirtualMemory.h"
#import "ZGMachBinary.h"
#import "ZGMachBinaryInfo.h"
#import "ZGRegion.h"
#import "ZGProcess.h"
#import "ZGVariableController.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-umbrella"
#import <DDMathParser/DDMathEvaluator.h>
#import <DDMathParser/NSString+DDMathParsing.h>
#import <DDMathParser/DDExpression.h>
#import <DDMathParser/DDExpressionRewriter.h>
#pragma clang diagnostic pop
#import "ZGDebugLogging.h"
#import "ZGNullability.h"

#define ZGCalculatePointerFunction @"ZGCalculatePointerFunction"
#define ZGProcessVariable @"ZGProcessVariable"
#define ZGFailedImagesVariable @"ZGFailedImagesVariable"
#define ZGSymbolicatesVariable @"ZGSymbolicatesVariable"
#define ZGSymbolicationRequiresExactMatch @"ZGSymbolicationRequiresExactMatch"
#define ZGDidFindSymbol @"ZGDidFindSymbol"
#define ZGLastSearchInfoVariable @"ZGLastSearchInfoVariable"
#define ZGVariableControllerVariable @"ZGVariableControllerVariable"

@implementation ZGVariable (ZGCalculatorAdditions)

- (BOOL)usesDynamicPointerAddress
{
	return _addressFormula != nil && [_addressFormula rangeOfString:@"["].location != NSNotFound && [_addressFormula rangeOfString:@"]"].location != NSNotFound;
}

- (NSUInteger)numberOfDynamicPointersInAddress
{
	if (_addressFormula == nil)
	{
		return 0;
	}
	
	NSString *remainingAddressFormula = _addressFormula;
	NSUInteger length = remainingAddressFormula.length;
	NSUInteger pivotLocation = 0;
	NSUInteger numberOfDynamicPointers = 0;
	while (pivotLocation < length)
	{
		NSRange range = [remainingAddressFormula rangeOfString:@"[" options:(NSCaseInsensitiveSearch | NSLiteralSearch) range:NSMakeRange(pivotLocation, length - pivotLocation)];
		
		if (range.location == NSNotFound)
		{
			break;
		}
		
		numberOfDynamicPointers++;
		
		pivotLocation = range.location + 1;
	}
	
	return numberOfDynamicPointers;
}

- (BOOL)usesDynamicBaseAddress
{
	return _addressFormula != nil && [_addressFormula rangeOfString:[ZGBaseAddressFunction stringByAppendingString:@"("]].location != NSNotFound;
}

- (BOOL)usesDynamicSymbolAddress
{
	return _addressFormula != nil && [_addressFormula rangeOfString:[ZGFindSymbolFunction stringByAppendingString:@"("]].location != NSNotFound;
}

- (BOOL)usesDynamicLabelAddress
{
	return _addressFormula != nil && [_addressFormula rangeOfString:[ZGFindLabelFunction stringByAppendingString:@"("]].location != NSNotFound;
}

@end

@implementation ZGCalculator

+ (void)registerBaseAddressFunctionWithEvaluator:(DDMathEvaluator *)evaluator
{
	[evaluator registerFunction:^DDExpression *(NSArray<DDExpression *> *args, NSDictionary<NSString *, id> *vars, DDMathEvaluator * __unused eval, NSError *__autoreleasing *error) {
		ZGProcess *process = [vars objectForKey:ZGProcessVariable];
		ZGMemoryAddress foundAddress = 0x0;
		if (args.count == 0)
		{
			foundAddress = process.mainMachBinary.headerAddress;
		}
		else if (args.count == 1)
		{
			NSMutableArray<NSString *> *failedImages = [vars objectForKey:ZGFailedImagesVariable];
			
			DDExpression *expression = [args objectAtIndex:0];
			if (expression.expressionType == DDExpressionTypeVariable)
			{
				if ([failedImages containsObject:expression.variable])
				{
					if (error != NULL)
					{
						*error = [NSError errorWithDomain:DDMathParserErrorDomain code:DDErrorCodeInvalidArgument userInfo:@{NSLocalizedDescriptionKey:ZGBaseAddressFunction @" is ignoring image"}];
					}
				}
				else
				{
					foundAddress = [[ZGMachBinary machBinaryWithPartialImageName:expression.variable inProcess:process fromCachedMachBinaries:nil error:error] headerAddress];
					
					if (error != NULL && *error != nil)
					{
						NSError *imageError = *error;
						[failedImages addObject:ZGUnwrapNullableObject(imageError.userInfo[ZGFailedImageName])];
					}
				}
			}
			else if (error != NULL)
			{
				*error = [NSError errorWithDomain:DDMathParserErrorDomain code:DDErrorCodeInvalidArgument userInfo:@{NSLocalizedDescriptionKey:ZGBaseAddressFunction @" expects argument to be a variable"}];
			}
		}
		else if (error != NULL)
		{
			*error = [NSError errorWithDomain:DDMathParserErrorDomain code:DDErrorCodeInvalidNumberOfArguments userInfo:@{NSLocalizedDescriptionKey:ZGBaseAddressFunction @" expects 1 or 0 arguments"}];
		}
		return [DDExpression numberExpressionWithNumber:@(foundAddress)];
	} forName:ZGBaseAddressFunction];
}

+ (void)registerCalculatePointerFunctionWithEvaluator:(DDMathEvaluator *)evaluator
{
	[evaluator registerFunction:^DDExpression *(NSArray<DDExpression *> *args, NSDictionary<NSString *, id> *vars, DDMathEvaluator *eval, NSError *__autoreleasing *error) {
		ZGMemoryAddress pointer = 0x0;
		if (args.count == 1)
		{
			NSError *unusedError = nil;
			NSNumber *memoryAddressNumber = [eval evaluateExpression:args[0] withSubstitutions:vars error:&unusedError];
			
			ZGMemoryAddress memoryAddress = [memoryAddressNumber unsignedLongLongValue];
			ZGProcess *process = [vars objectForKey:ZGProcessVariable];
			
			void *bytes = NULL;
			ZGMemorySize sizeRead = process.pointerSize;
			if (ZGReadBytes(process.processTask, memoryAddress, &bytes, &sizeRead))
			{
				if (sizeRead == process.pointerSize)
				{
					pointer = (process.pointerSize == sizeof(ZGMemoryAddress)) ? *(ZGMemoryAddress *)bytes : *(ZG32BitMemoryAddress *)bytes;
				}
				else if (error != NULL)
				{
					*error = [NSError errorWithDomain:DDMathParserErrorDomain code:DDErrorCodeInvalidNumber userInfo:@{NSLocalizedDescriptionKey:ZGCalculatePointerFunction @" didn't read sufficient number of bytes"}];
				}
				ZGFreeBytes(bytes, sizeRead);
			}
			else if (error != NULL)
			{
				*error = [NSError errorWithDomain:DDMathParserErrorDomain code:DDErrorCodeInvalidNumber userInfo:@{NSLocalizedDescriptionKey:ZGCalculatePointerFunction @" failed to read bytes"}];
			}
		}
		else if (error != NULL)
		{
			*error = [NSError errorWithDomain:DDMathParserErrorDomain code:DDErrorCodeInvalidNumberOfArguments userInfo:@{NSLocalizedDescriptionKey:ZGCalculatePointerFunction @" expects 1 argument"}];
		}
		return [DDExpression numberExpressionWithNumber:@(pointer)];
	} forName:ZGCalculatePointerFunction];
}

+ (DDMathFunction)registerFindSymbolFunctionWithEvaluator:(DDMathEvaluator *)evaluator
{
	DDMathFunction findSymbolFunction = ^DDExpression *(NSArray<DDExpression *> *args, NSDictionary<NSString *, id> *vars, DDMathEvaluator * __unused eval, NSError *__autoreleasing *error) {
		NSNumber *symbolicatesNumber = vars[ZGSymbolicatesVariable];
		NSNumber *symbolicationRequiresExactMatch = vars[ZGSymbolicationRequiresExactMatch];
		ZGProcess *process = vars[ZGProcessVariable];
		NSNumber *currentAddressNumber = vars[ZGLastSearchInfoVariable];

		__block NSNumber *symbolAddressNumber = @(0);

		if (args.count == 0 || args.count > 2)
		{
			if (error != NULL)
			{
				*error = [NSError errorWithDomain:DDMathParserErrorDomain code:DDErrorCodeInvalidNumberOfArguments userInfo:@{NSLocalizedDescriptionKey:ZGFindSymbolFunction @" expects 1 or 2 arguments"}];
			}
		}
		else if (process == nil || ![symbolicatesNumber boolValue])
		{
			if (error != NULL)
			{
				*error = [NSError errorWithDomain:DDMathParserErrorDomain code:DDErrorCodeUnresolvedVariable userInfo:@{NSLocalizedDescriptionKey:ZGFindSymbolFunction @" expects symbolicator variable"}];
			}
		}
		else
		{
			DDExpression *symbolExpression = [args objectAtIndex:0];
			if (symbolExpression.expressionType != DDExpressionTypeVariable)
			{
				if (error != NULL)
				{
					*error = [NSError errorWithDomain:DDMathParserErrorDomain code:DDErrorCodeUnresolvedVariable userInfo:@{NSLocalizedDescriptionKey:ZGFindSymbolFunction @" expects first argument to be a string variable"}];
				}
			}
			else
			{
				NSString *symbolString = symbolExpression.variable;
				NSString *targetOwnerNameSuffix = nil;
				
				BOOL encounteredError = NO;
				
				if (args.count == 2)
				{
					DDExpression *targetOwnerExpression = [args objectAtIndex:1];
					if (targetOwnerExpression.expressionType == DDExpressionTypeVariable)
					{
						targetOwnerNameSuffix = targetOwnerExpression.variable;
					}
					else
					{
						encounteredError = YES;
						if (error != NULL)
						{
							*error = [NSError errorWithDomain:DDMathParserErrorDomain code:DDErrorCodeUnresolvedVariable userInfo:@{NSLocalizedDescriptionKey:ZGFindSymbolFunction @" expects second argument to be a string variable"}];
						}
					}
				}
				
				if (!encounteredError)
				{
					symbolAddressNumber = [process.symbolicator findSymbol:symbolString withPartialSymbolOwnerName:targetOwnerNameSuffix requiringExactMatch:symbolicationRequiresExactMatch.boolValue pastAddress:[currentAddressNumber unsignedLongLongValue] allowsWrappingToBeginning:YES];
					if (symbolAddressNumber == nil)
					{
						if (error != NULL)
						{
							*error = [NSError errorWithDomain:DDMathParserErrorDomain code:DDErrorCodeInvalidArgument userInfo:@{NSLocalizedDescriptionKey:ZGFindSymbolFunction @" could not find requested symbol"}];
						}
					}
				}
			}
		}
		
		return [DDExpression numberExpressionWithNumber:symbolAddressNumber];
	};
	
	[evaluator registerFunction:findSymbolFunction forName:ZGFindSymbolFunction];
	
	return findSymbolFunction;
}

+ (DDMathFunction)registerFindLabelFunctionWithEvaluator:(DDMathEvaluator *)evaluator
{
	DDMathFunction findLabelFunction = ^DDExpression *(NSArray<DDExpression *> *args, NSDictionary<NSString *, id> *vars, DDMathEvaluator * __unused eval, NSError *__autoreleasing *error) {
		ZGVariableController *variableController = [vars objectForKey:ZGVariableControllerVariable];
		
		__block NSNumber *labelAddressNumber = @(0);
		
		if (args.count == 0 || args.count > 1)
		{
			if (error != NULL)
			{
				*error = [NSError errorWithDomain:DDMathParserErrorDomain code:DDErrorCodeInvalidNumberOfArguments userInfo:@{NSLocalizedDescriptionKey:ZGFindLabelFunction @" expects 1 argument"}];
			}
		}
		else if (variableController == nil)
		{
			if (error != NULL)
			{
				*error = [NSError errorWithDomain:DDMathParserErrorDomain code:DDErrorCodeUnresolvedVariable userInfo:@{NSLocalizedDescriptionKey:ZGFindLabelFunction @" expects a labels variable"}];
			}
		}
		else
		{
			DDExpression *labelExpression = [args objectAtIndex:0];
			
			if (labelExpression.expressionType != DDExpressionTypeVariable)
			{
				if (error != NULL)
				{
					*error = [NSError errorWithDomain:DDMathParserErrorDomain code:DDErrorCodeUnresolvedVariable userInfo:@{NSLocalizedDescriptionKey:ZGFindLabelFunction @" expects a string variable"}];
				}
			}
			else
			{
				ZGVariable *variable = [variableController variableForLabel:labelExpression.variable];
				
				if (variable != nil)
				{
					labelAddressNumber = @(variable.address);
				}
			}
		}
		
		return [DDExpression numberExpressionWithNumber:labelAddressNumber];
	};
	
	[evaluator registerFunction:findLabelFunction forName:ZGFindLabelFunction];
	
	return findLabelFunction;
}

+ (void)registerFunctionResolverWithEvaluator:(DDMathEvaluator *)evaluator findSymbolFunction:(DDMathFunction)findSymbolFunction
{
	evaluator.functionResolver = (DDFunctionResolver)^(NSString *name) {
		return (DDMathFunction)^(NSArray<DDExpression *> *args, NSDictionary<NSString *, id> *vars, DDMathEvaluator *eval, NSError **error) {
			DDExpression *result = nil;
			if ([(NSNumber *)[vars objectForKey:ZGSymbolicatesVariable] boolValue] && args.count == 0)
			{
				if (vars[ZGDidFindSymbol] != nil && [vars isKindOfClass:[NSMutableDictionary class]])
				{
					((NSMutableDictionary *)vars)[ZGDidFindSymbol] = @YES;
				}
				
				result = findSymbolFunction(@[[DDExpression variableExpressionWithVariable:name]], vars, eval, error);
			}
			return result;
		};
	};
}

+ (void)initialize
{
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		DDMathEvaluator *evaluator = [DDMathEvaluator defaultMathEvaluator];
		[self registerCalculatePointerFunctionWithEvaluator:evaluator];
		[self registerBaseAddressFunctionWithEvaluator:evaluator];
		DDMathFunction findSymbolFunction = [self registerFindSymbolFunctionWithEvaluator:evaluator];
		[self registerFindLabelFunctionWithEvaluator:evaluator];
		[self registerFunctionResolverWithEvaluator:evaluator findSymbolFunction:findSymbolFunction];
	});
}

+ (NSString *)multiplicativeConstantStringFromExpression:(DDExpression *)expression
{
	if (expression.arguments.count != 2)
	{
		return nil;
	}
	
	NSString *multiplicativeConstantString = nil;
	
	DDExpression *firstExpression = [expression.arguments objectAtIndex:0];
	DDExpression *secondExpression = [expression.arguments objectAtIndex:1];
	if (firstExpression.expressionType == DDExpressionTypeVariable && secondExpression.expressionType == DDExpressionTypeNumber)
	{
		multiplicativeConstantString = secondExpression.number.stringValue;
	}
	else if (firstExpression.expressionType == DDExpressionTypeNumber && secondExpression.expressionType == DDExpressionTypeVariable)
	{
		multiplicativeConstantString = firstExpression.number.stringValue;
	}
	
	return multiplicativeConstantString;
}

+ (void)getAdditiveConstant:(NSString * __autoreleasing *)additiveConstantString andMultiplicativeConstantString:(NSString * __autoreleasing *)multiplicativeConstantString fromNumericalExpression:(DDExpression *)numericalExpression andVariableOrFunctionExpression:(DDExpression *)variableOrFunctionExpression
{
	if (variableOrFunctionExpression.expressionType == DDExpressionTypeVariable)
	{
		*multiplicativeConstantString = @"1";
	}
	else if (variableOrFunctionExpression.expressionType == DDExpressionTypeFunction && [variableOrFunctionExpression.function isEqualToString:@"multiply"])
	{
		*multiplicativeConstantString = [self multiplicativeConstantStringFromExpression:variableOrFunctionExpression];
	}
	
	*additiveConstantString = numericalExpression.number.stringValue;
}

+ (BOOL)parseLinearExpression:(NSString *)linearExpression andGetAdditiveConstant:(NSString * __autoreleasing *)additiveConstantString multiplicateConstant:(NSString * __autoreleasing *)multiplicativeConstantString
{
	NSError *error = nil;
	DDMathEvaluator *evaluator = [[DDMathEvaluator alloc] init];
	DDExpressionRewriter *rewriter = [[DDExpressionRewriter alloc] init];
	
	[rewriter addRewriteRule:@"add(__exp1, negate(__exp2))" forExpressionsMatchingTemplate:@"subtract(__exp1, __exp2)" condition:nil];
	
	[rewriter addRewriteRule:@"add(add(__num1, __num2), __var1)" forExpressionsMatchingTemplate:@"add(__num1, add(__var1, __num2))" condition:nil];
	[rewriter addRewriteRule:@"add(add(__num1, __num2), __var1)" forExpressionsMatchingTemplate:@"add(__num1, add(__num2, __var1))" condition:nil];
	[rewriter addRewriteRule:@"add(add(__num1, __num2), __var1)" forExpressionsMatchingTemplate:@"add(add(__var1, __num2), __num1)" condition:nil];
	[rewriter addRewriteRule:@"add(add(__num1, __num2), __var1)" forExpressionsMatchingTemplate:@"add(add(__num2, __var1), __num1)" condition:nil];
	
	[rewriter addRewriteRule:@"add(add(__num1, __num2), __func1)" forExpressionsMatchingTemplate:@"add(add(__num1, __func1), __num2)" condition:nil];
	[rewriter addRewriteRule:@"add(add(__num1, __num2), __func1)" forExpressionsMatchingTemplate:@"add(add(__func1, __num1), __num2)" condition:nil];
	[rewriter addRewriteRule:@"add(add(__num1, __num2), __func1)" forExpressionsMatchingTemplate:@"add(__num2, add(__num1, __func1))" condition:nil];
	[rewriter addRewriteRule:@"add(add(__num1, __num2), __func1)" forExpressionsMatchingTemplate:@"add(__num2, add(__func1, __num1))" condition:nil];

	[rewriter addRewriteRule:@"multiply(__exp1, -1)" forExpressionsMatchingTemplate:@"negate(__exp1)" condition:nil];

	[rewriter addRewriteRule:@"multiply(__var1, divide(1, __num1))" forExpressionsMatchingTemplate:@"divide(__var1, __num1)" condition:nil];
	[rewriter addRewriteRule:@"multiply(__var1, divide(1, __func1))" forExpressionsMatchingTemplate:@"divide(__var1, __func1)" condition:nil];
	[rewriter addRewriteRule:@"multiply(__func1, divide(1, __num1))" forExpressionsMatchingTemplate:@"divide(__func1, __num1)" condition:nil];
	
	[rewriter addRewriteRule:@"multiply(multiply(__num1, __num2), __var1)" forExpressionsMatchingTemplate:@"multiply(multiply(__var1, __num1), __num2)" condition:nil];
	[rewriter addRewriteRule:@"multiply(multiply(__num1, __num2), __var1)" forExpressionsMatchingTemplate:@"multiply(multiply(__num1, __var1), __num2)" condition:nil];
	[rewriter addRewriteRule:@"multiply(multiply(__num1, __num2), __var1)" forExpressionsMatchingTemplate:@"multiply(__num2, multiply(__var1, __num1))" condition:nil];
	[rewriter addRewriteRule:@"multiply(multiply(__num1, __num2), __var1)" forExpressionsMatchingTemplate:@"multiply(__num2, multiply(__num1, __var1))" condition:nil];
	
	[rewriter addRewriteRule:@"multiply(multiply(__num1, __num2), __func1)" forExpressionsMatchingTemplate:@"multiply(multiply(__func1, __num1), __num2)" condition:nil];
	[rewriter addRewriteRule:@"multiply(multiply(__num1, __num2), __func1)" forExpressionsMatchingTemplate:@"multiply(multiply(__num1, __func1), __num2)" condition:nil];
	[rewriter addRewriteRule:@"multiply(multiply(__num1, __num2), __func1)" forExpressionsMatchingTemplate:@"multiply(__num2, multiply(__func1, __num1))" condition:nil];
	[rewriter addRewriteRule:@"multiply(multiply(__num1, __num2), __func1)" forExpressionsMatchingTemplate:@"multiply(__num2, multiply(__num1, __func1))" condition:nil];
	
	[rewriter addRewriteRule:@"add(multiply(__num2, __num1), multiply(__num2, __var1))" forExpressionsMatchingTemplate:@"multiply(__num2, add(__num1, __var1))" condition:nil];
	[rewriter addRewriteRule:@"add(multiply(__num2, __num1), multiply(__num2, __var1))" forExpressionsMatchingTemplate:@"multiply(__num2, add(__var1, __num1))" condition:nil];
	[rewriter addRewriteRule:@"add(multiply(__num2, __num1), multiply(__num2, __var1))" forExpressionsMatchingTemplate:@"multiply(add(__num1, __var1), __num2)" condition:nil];
	[rewriter addRewriteRule:@"add(multiply(__num2, __num1), multiply(__num2, __var1))" forExpressionsMatchingTemplate:@"multiply(add(__var1, __num1), __num2)" condition:nil];
	
	[rewriter addRewriteRule:@"add(multiply(__exp2, __exp1), multiply(__exp2, __func1))" forExpressionsMatchingTemplate:@"multiply(__exp2, add(__exp1, __func1))" condition:nil];
	[rewriter addRewriteRule:@"add(multiply(__exp2, __exp1), multiply(__exp2, __func1))" forExpressionsMatchingTemplate:@"multiply(__exp2, add(__func1, __exp1))" condition:nil];
	[rewriter addRewriteRule:@"add(multiply(__exp2, __exp1), multiply(__exp2, __func1))" forExpressionsMatchingTemplate:@"multiply(add(__exp1, __func1), __exp2)" condition:nil];
	[rewriter addRewriteRule:@"add(multiply(__exp2, __exp1), multiply(__exp2, __func1))" forExpressionsMatchingTemplate:@"multiply(add(__func1, __exp1), __exp2)" condition:nil];
	
	DDExpression *simplifiedExpression = [(DDExpression *)[DDExpression expressionFromString:linearExpression error:&error] simplifiedExpression];
	if (simplifiedExpression == nil)
	{
		ZG_LOG(@"Error simplifiying expression: %@", error);
		return NO;
	}
	
	DDExpression *rewrittenExpression = [[rewriter expressionByRewritingExpression:simplifiedExpression withEvaluator:evaluator] simplifiedExpression];
	
	if (rewrittenExpression == nil)
	{
		ZG_LOG(@"Error: Failed to rewrite expression %@", simplifiedExpression);
		return NO;
	}
	
	*additiveConstantString = nil;
	*multiplicativeConstantString = nil;
	
	if (rewrittenExpression.expressionType == DDExpressionTypeVariable)
	{
		*additiveConstantString = @"0";
		*multiplicativeConstantString = @"1";
	}
	else if (rewrittenExpression.expressionType != DDExpressionTypeFunction)
	{
		ZG_LOG(@"Error: Rewritten expression is not a function or variable");
		return NO;
	}
	else if ([rewrittenExpression.function isEqualToString:@"multiply"])
	{
		*multiplicativeConstantString = [self multiplicativeConstantStringFromExpression:rewrittenExpression];
		*additiveConstantString = @"0";
	}
	else if ([rewrittenExpression.function isEqualToString:@"add"])
	{
		if (rewrittenExpression.arguments.count != 2)
		{
			return NO;
		}
		
		DDExpression *firstExpression = [rewrittenExpression.arguments objectAtIndex:0];
		DDExpression *secondExpression = [rewrittenExpression.arguments objectAtIndex:1];
		
		if (secondExpression.expressionType == DDExpressionTypeNumber)
		{
			[self
			 getAdditiveConstant:additiveConstantString
			 andMultiplicativeConstantString:multiplicativeConstantString
			 fromNumericalExpression:secondExpression
			 andVariableOrFunctionExpression:firstExpression];
		}
		else if (firstExpression.expressionType == DDExpressionTypeNumber)
		{
			[self
			 getAdditiveConstant:additiveConstantString
			 andMultiplicativeConstantString:multiplicativeConstantString
			 fromNumericalExpression:firstExpression
			 andVariableOrFunctionExpression:secondExpression];
		}
	}
	
	return (*additiveConstantString != nil && *multiplicativeConstantString != nil);
}

// Note: this method assumes buffer is zero-initialized
+ (BOOL)_extractBaseAddressAndOffsetsFromExpression:(DDExpression *)expression intoBuffer:(void *)buffer levelsRecursed:(uint16_t)levelsRecursed maxLevels:(uint16_t)maxLevels filePaths:(NSArray<NSString *> *)filePaths filePathSuffixIndexCache:(NSMutableDictionary<NSString *, id> *)filePathSuffixIndexCache
{
	//	Struct {
	//		uintptr_t baseAddress;
	//		uint16_t baseImageIndex;
	//		uint16_t numLevels;
	//		int32_t offsets[MAX_NUM_LEVELS];
	//	}
	
	if (levelsRecursed > maxLevels)
	{
		return NO;
	}
	
	ZGMemorySize pointerSize = sizeof(ZGMemoryAddress);
	
	switch (expression.expressionType)
	{
		case DDExpressionTypeFunction:
		{
			BOOL isAddFunction = [expression.function isEqualToString:@"add"];
			if ((isAddFunction || [expression.function isEqualToString:@"subtract"]) && expression.arguments.count == 2)
			{
				DDExpression *argumentExpression1 = expression.arguments[0];
				DDExpression *argumentExpression2 = expression.arguments[1];
				
				DDExpression *pointerSubExpression;
				DDExpression *offsetExpression;
				if (argumentExpression1.expressionType == DDExpressionTypeFunction && [argumentExpression1.function isEqualToString:ZGCalculatePointerFunction])
				{
					pointerSubExpression = argumentExpression1;
					offsetExpression = argumentExpression2;
				}
				else if (argumentExpression2.expressionType == DDExpressionTypeFunction && [argumentExpression2.function isEqualToString:ZGCalculatePointerFunction])
				{
					pointerSubExpression = argumentExpression2;
					offsetExpression = argumentExpression1;
				}
				else
				{
					pointerSubExpression = nil;
					offsetExpression = nil;
				}
				
				if (pointerSubExpression != nil)
				{
					if (offsetExpression != nil && offsetExpression.expressionType != DDExpressionTypeNumber)
					{
						return NO;
					}
					
					if (pointerSubExpression.arguments.count != 1)
					{
						return NO;
					}
					
					if (![self _extractBaseAddressAndOffsetsFromExpression:pointerSubExpression.arguments[0] intoBuffer:buffer levelsRecursed:levelsRecursed + 1 maxLevels:maxLevels filePaths:filePaths filePathSuffixIndexCache:filePathSuffixIndexCache])
					{
						return NO;
					}
					
					// Fetch and store offset
					if (offsetExpression.expressionType != DDExpressionTypeNumber)
					{
						return NO;
					}
					
					// Number of levels is set when we recurse into base expression
					uint16_t numberOfLevels = 0;
					memcpy(&numberOfLevels, (uint8_t *)buffer + pointerSize + sizeof(uint16_t), sizeof(numberOfLevels));
					
					if (numberOfLevels == 0 || numberOfLevels - 1 < levelsRecursed)
					{
						// Shouldn't be possible
						assert(false);
						return NO;
					}
					
					int32_t initialOffset = (int32_t)offsetExpression.number.intValue;
					int32_t offset = isAddFunction ? initialOffset : -initialOffset;
					memcpy((uint8_t *)buffer + pointerSize + sizeof(uint16_t) + sizeof(numberOfLevels) + levelsRecursed * sizeof(offset), &offset, sizeof(offset));
				}
				else
				{
					// Found the static base expression
					
					DDExpression *baseAddressArgumentExpression1 = expression.arguments[0];
					DDExpression *baseAddressArgumentExpression2 = expression.arguments[1];
					
					DDExpression *baseFunctionExpression;
					DDExpression *baseImageOffsetExpression;
					
					if (baseAddressArgumentExpression1.expressionType == DDExpressionTypeFunction && [baseAddressArgumentExpression1.function isEqualToString:ZGBaseAddressFunction])
					{
						baseFunctionExpression = baseAddressArgumentExpression1;
						baseImageOffsetExpression = baseAddressArgumentExpression2;
					}
					else if (baseAddressArgumentExpression2.expressionType == DDExpressionTypeFunction && [baseAddressArgumentExpression2.function isEqualToString:ZGBaseAddressFunction])
					{
						baseFunctionExpression = baseAddressArgumentExpression2;
						baseImageOffsetExpression = baseAddressArgumentExpression1;
					}
					else
					{
						return NO;
					}
					
					if (baseImageOffsetExpression.expressionType != DDExpressionTypeNumber)
					{
						return NO;
					}
					
					ZGMemoryAddress baseImageOffset = baseImageOffsetExpression.number.unsignedLongLongValue;
					memcpy((uint8_t *)buffer, &baseImageOffset, sizeof(baseImageOffset));
					
					if (baseFunctionExpression.arguments.count == 0)
					{
						uint16_t baseImageIndex = 0;
						memcpy((uint8_t *)buffer + pointerSize, &baseImageIndex, sizeof(baseImageIndex));
					}
					else
					{
						DDExpression *baseImageSuffixExpression = baseFunctionExpression.arguments[0];
						if (baseImageSuffixExpression.expressionType != DDExpressionTypeVariable)
						{
							return NO;
						}
						
						NSString *baseImageSuffix = baseImageSuffixExpression.variable;
						
						id cachedBaseImageIndexNumber = filePathSuffixIndexCache[baseImageSuffix];
						if (cachedBaseImageIndexNumber == nil)
						{
							BOOL foundBaseImage = NO;
							uint16_t baseImageIndex = 0;
							for (NSString *filePath in filePaths)
							{
								if ([filePath hasSuffix:baseImageSuffix])
								{
									memcpy((uint8_t *)buffer + pointerSize, &baseImageIndex, sizeof(baseImageIndex));
									foundBaseImage = YES;
									break;
								}
								baseImageIndex++;
							}
							
							if (!foundBaseImage)
							{
								filePathSuffixIndexCache[baseImageSuffix] = NSNull.null;
								return NO;
							}
							
							filePathSuffixIndexCache[baseImageSuffix] = @(baseImageIndex);
						}
						else
						{
							if (cachedBaseImageIndexNumber == NSNull.null)
							{
								return NO;
							}
							
							uint16_t baseImageIndex = ((NSNumber *)cachedBaseImageIndexNumber).unsignedShortValue;
							memcpy((uint8_t *)buffer + pointerSize, &baseImageIndex, sizeof(baseImageIndex));
						}
					}
					
					memcpy((uint8_t *)buffer + pointerSize + sizeof(uint16_t), &levelsRecursed, sizeof(levelsRecursed));
				}
			}
			else if ([expression.function isEqualToString:ZGCalculatePointerFunction] && expression.arguments.count == 1)
			{
				if (![self _extractBaseAddressAndOffsetsFromExpression:expression.arguments[0] intoBuffer:buffer levelsRecursed:levelsRecursed + 1 maxLevels:maxLevels filePaths:filePaths filePathSuffixIndexCache:filePathSuffixIndexCache])
				{
					return NO;
				}
			}
			else
			{
				// While there can be a base() function in the base expression, we shouldn't encounter it here
				return NO;
			}
			break;
		}
		case DDExpressionTypeNumber:
		{
			// Found base address without any base()
			ZGMemoryAddress baseAddress = (ZGMemoryAddress)expression.number.unsignedLongLongValue;
			switch (pointerSize)
			{
				case sizeof(ZGMemoryAddress):
					memcpy(buffer, &baseAddress, sizeof(baseAddress));
					break;
				case sizeof(ZG32BitMemoryAddress):
				{
					ZG32BitMemoryAddress tempMemoryAddress = (ZG32BitMemoryAddress)baseAddress;
					memcpy(buffer, &tempMemoryAddress, sizeof(tempMemoryAddress));
					break;
				}
			}
			
			uint16_t baseIndex = UINT16_MAX;
			memcpy((uint8_t *)buffer + pointerSize, &baseIndex, sizeof(baseIndex));
			
			memcpy((uint8_t *)buffer + pointerSize + sizeof(uint16_t), &levelsRecursed, sizeof(levelsRecursed));
			
			break;
		}
		case DDExpressionTypeVariable:
			return NO;
	}
	
	return YES;
}

+ (BOOL)extractIndirectAddressesAndOffsetsFromIntoBuffer:(void *)buffer expression:(NSString *)initialExpression filePaths:(NSArray<NSString *> *)filePaths filePathSuffixIndexCache:(NSMutableDictionary<NSString *, id> *)filePathSuffixIndexCache maxLevels:(uint16_t)maxLevels stride:(ZGMemorySize)stride
{
	NSString *substitutedExpression = [ZGCalculator expressionBySubstitutingCalculatePointerFunctionInExpression:initialExpression];
	
	NSError *expressionError = NULL;
	DDExpression *expression = [DDExpression expressionFromString:substitutedExpression error:&expressionError];
	if (expression == nil)
	{
		return NO;
	}

	memset(buffer, 0, stride);
	if (![self _extractBaseAddressAndOffsetsFromExpression:expression intoBuffer:buffer levelsRecursed:0 maxLevels:maxLevels filePaths:filePaths filePathSuffixIndexCache:filePathSuffixIndexCache])
	{
		return NO;
	}

	return YES;
}

+ (BOOL)_extractIndirectBaseAddress:(ZGMemoryAddress *)outBaseAddress foundPointerFunction:(BOOL *)foundPointerFunction expression:(DDExpression *)expression process:(ZGProcess *)process variableController:(ZGVariableController *)variableController visitedLabels:(NSMutableSet<NSString *> *)visitedLabels failedImages:(NSMutableArray<NSString *> * __unsafe_unretained)failedImages
{
	switch (expression.expressionType)
	{
		case DDExpressionTypeFunction:
			if ([expression.function isEqualToString:ZGFindLabelFunction] && expression.arguments.count == 1)
			{
				DDExpression *argumentExpression = expression.arguments[0];
				if (argumentExpression.expressionType != DDExpressionTypeVariable)
				{
					return NO;
				}
				
				NSString *label = argumentExpression.variable;
				
				if ([visitedLabels containsObject:label])
				{
					// Prevent recursive/cyclic lookups
					return NO;
				}
				
				ZGVariable *labelVariable = [variableController variableForLabel:label];
				if (labelVariable == nil)
				{
					return NO;
				}
				
				// Recurse into the labeled variable's address
				NSString *addressFormula = labelVariable.addressFormula;
				NSString *substitutedAddressFormulaExpression = [ZGCalculator expressionBySubstitutingCalculatePointerFunctionInExpression:addressFormula];
				
				NSError *expressionError = NULL;
				DDExpression *addressFormulaExpression = [DDExpression expressionFromString:substitutedAddressFormulaExpression error:&expressionError];
				if (addressFormulaExpression == nil)
				{
					return NO;
				}
				
				[visitedLabels addObject:label];
				
				return [self _extractIndirectBaseAddress:outBaseAddress foundPointerFunction:foundPointerFunction expression:addressFormulaExpression process:process variableController:variableController visitedLabels:visitedLabels failedImages:failedImages];
			}
			else if (([expression.function isEqualToString:@"add"] || [expression.function isEqualToString:@"subtract"]) && expression.arguments.count == 2)
			{
				DDExpression *argumentExpression1 = expression.arguments[0];
				DDExpression *argumentExpression2 = expression.arguments[1];
				
				if (argumentExpression1.expressionType == DDExpressionTypeFunction && [argumentExpression1.function isEqualToString:ZGCalculatePointerFunction])
				{
					return [self _extractIndirectBaseAddress:outBaseAddress foundPointerFunction:foundPointerFunction expression:argumentExpression1 process:process variableController:variableController visitedLabels:visitedLabels failedImages:failedImages];
				}
				else if (argumentExpression2.expressionType == DDExpressionTypeFunction && [argumentExpression2.function isEqualToString:ZGCalculatePointerFunction])
				{
					return [self _extractIndirectBaseAddress:outBaseAddress foundPointerFunction:foundPointerFunction expression:argumentExpression2 process:process variableController:variableController visitedLabels:visitedLabels failedImages:failedImages];
				}
				
				if (argumentExpression1.expressionType == DDExpressionTypeFunction && [argumentExpression1.function isEqualToString:ZGFindLabelFunction])
				{
					return [self _extractIndirectBaseAddress:outBaseAddress foundPointerFunction:foundPointerFunction expression:argumentExpression1 process:process variableController:variableController visitedLabels:visitedLabels failedImages:failedImages];
				}
				else if (argumentExpression2.expressionType == DDExpressionTypeFunction && [argumentExpression2.function isEqualToString:ZGFindLabelFunction])
				{
					return [self _extractIndirectBaseAddress:outBaseAddress foundPointerFunction:foundPointerFunction expression:argumentExpression2 process:process variableController:variableController visitedLabels:visitedLabels failedImages:failedImages];
				}
				
				// Found base() +- offset expression which we need to evaluate
				NSDictionary<NSString *, id> *substitutions = [self _evaluatorSubstitutionsForProcess:process variableController:nil failedImages:failedImages symbolicates:NO symbolicationRequiresExactMatch:YES currentAddress:0x0];
				
				NSError *evaluateError = nil;
				NSNumber *evaluatedBaseAddressNumber = [[DDMathEvaluator defaultMathEvaluator] evaluateExpression:expression withSubstitutions:substitutions error:&evaluateError];
				
				if (evaluatedBaseAddressNumber == nil)
				{
					return NO;
				}
				
				ZGMemoryAddress baseAddress = (ZGMemoryAddress)evaluatedBaseAddressNumber.unsignedLongLongValue;
				if (outBaseAddress != NULL)
				{
					*outBaseAddress = baseAddress;
				}
				
				return YES;
			}
			else if ([expression.function isEqualToString:ZGCalculatePointerFunction] && expression.arguments.count == 1)
			{
				if (foundPointerFunction != NULL)
				{
					*foundPointerFunction = YES;
				}
				
				return [self _extractIndirectBaseAddress:outBaseAddress foundPointerFunction:foundPointerFunction expression:expression.arguments[0] process:process variableController:variableController visitedLabels:visitedLabels failedImages:failedImages];
			}
			else
			{
				// While there can be a base() function in the base expression, we shouldn't encounter it here
				return NO;
			}
		case DDExpressionTypeNumber:
		{
			// Found base expression as the evaluated expression
			ZGMemoryAddress baseAddress = expression.number.unsignedLongLongValue;
			if (outBaseAddress != NULL)
			{
				*outBaseAddress = baseAddress;
			}
			
			return YES;
		}
		case DDExpressionTypeVariable:
			return NO;
	}
}

+ (BOOL)extractIndirectBaseAddress:(ZGMemoryAddress *)outBaseAddress expression:(NSString *)initialExpression process:(ZGProcess * __unsafe_unretained)process variableController:(ZGVariableController * __unsafe_unretained)variableController failedImages:(NSMutableArray<NSString *> * __unsafe_unretained)failedImages
{
	NSString *substitutedExpression = [ZGCalculator expressionBySubstitutingCalculatePointerFunctionInExpression:initialExpression];
	
	NSError *expressionError = NULL;
	DDExpression *expression = [DDExpression expressionFromString:substitutedExpression error:&expressionError];
	if (expression == nil)
	{
		return NO;
	}
	
	NSMutableSet<NSString *> *visitedLabels = [NSMutableSet set];
	BOOL foundPointerFunction = NO;
	if (![self _extractIndirectBaseAddress:outBaseAddress foundPointerFunction:&foundPointerFunction expression:expression process:process variableController:variableController visitedLabels:visitedLabels failedImages:failedImages])
	{
		return NO;
	}
	
	if (!foundPointerFunction)
	{
		return NO;
	}
	
	return YES;
}

+ (nullable NSString *)_extractFirstDependentLabelFromExpression:(DDExpression *)expression
{
	switch (expression.expressionType)
	{
		case DDExpressionTypeFunction:
		{
			if ([expression.function isEqualToString:ZGFindLabelFunction])
			{
				if (expression.arguments.count != 1)
				{
					return nil;
				}
				
				DDExpression *argumentExpression1 = expression.arguments[0];
				if (argumentExpression1.expressionType != DDExpressionTypeVariable)
				{
					return nil;
				}
				
				return argumentExpression1.variable;
			}
			
			if (expression.arguments.count != 2)
			{
				return nil;
			}
			
			DDExpression *argumentExpression1 = expression.arguments[0];
			DDExpression *argumentExpression2 = expression.arguments[1];
			
			if (argumentExpression1.expressionType == DDExpressionTypeFunction && [argumentExpression1.function isEqualToString:ZGFindLabelFunction])
			{
				return [self _extractFirstDependentLabelFromExpression:argumentExpression1];
			}
			
			if (argumentExpression2.expressionType == DDExpressionTypeFunction && [argumentExpression2.function isEqualToString:ZGFindLabelFunction])
			{
				return [self _extractFirstDependentLabelFromExpression:argumentExpression2];
			}
			
			if (argumentExpression1.expressionType == DDExpressionTypeFunction)
			{
				NSString *dependentLabelCandidate1 = [self _extractFirstDependentLabelFromExpression:argumentExpression1];
				if (dependentLabelCandidate1 != nil)
				{
					return dependentLabelCandidate1;
				}
			}
			
			if (argumentExpression2.expressionType == DDExpressionTypeFunction)
			{
				return [self _extractFirstDependentLabelFromExpression:argumentExpression1];
			}
			
			return nil;
		}
		case DDExpressionTypeVariable:
		case DDExpressionTypeNumber:
			return nil;
	}
}

+ (nullable NSString *)extractFirstDependentLabelFromExpression:(NSString *)initialExpression
{
	NSError *expressionError = NULL;
	NSString *substitutedExpression = [self expressionBySubstitutingCalculatePointerFunctionInExpression:initialExpression];
	DDExpression *expression = [DDExpression expressionFromString:substitutedExpression error:&expressionError];
	if (expression == nil)
	{
		return nil;
	}
	
	return [self _extractFirstDependentLabelFromExpression:expression];
}

+ (BOOL)_expressionIsCyclic:(DDExpression *)expression cycle:(NSArray<NSString *> * __autoreleasing *)outCycle variableController:(ZGVariableController *)variableController visitedLabels:(NSMutableOrderedSet<NSString *> *)visitedLabels
{
	switch (expression.expressionType)
	{
		case DDExpressionTypeFunction:
		{
			if ([expression.function isEqualToString:ZGFindLabelFunction])
			{
				if (expression.arguments.count != 1)
				{
					return NO;
				}
				
				DDExpression *argumentExpression1 = expression.arguments[0];
				if (argumentExpression1.expressionType != DDExpressionTypeVariable)
				{
					return NO;
				}
				
				NSString *label = argumentExpression1.variable;
				if ([visitedLabels containsObject:label])
				{
					if (outCycle != NULL)
					{
						*outCycle = [visitedLabels.array arrayByAddingObject:label];
					}
					return YES;
				}
				
				[visitedLabels addObject:label];
				
				ZGVariable *newLabelVariable = [variableController variableForLabel:label];
				if (newLabelVariable == nil)
				{
					return NO;
				}
				
				// Recurse into the new variable label
				NSString *addressFormula = newLabelVariable.addressFormula;
				NSString *substitutedAddressFormulaExpression = [self expressionBySubstitutingCalculatePointerFunctionInExpression:addressFormula];
				
				NSError *expressionError = NULL;
				DDExpression *addressFormulaExpression = [DDExpression expressionFromString:substitutedAddressFormulaExpression error:&expressionError];
				if (addressFormulaExpression == nil)
				{
					return NO;
				}
				
				return [self _expressionIsCyclic:addressFormulaExpression cycle:outCycle variableController:variableController visitedLabels:visitedLabels];
			}
			
			if (expression.arguments.count != 2)
			{
				return NO;
			}
			
			DDExpression *argumentExpression1 = expression.arguments[0];
			DDExpression *argumentExpression2 = expression.arguments[1];
			
			BOOL hasCycleInExpression1 = NO;
			if (argumentExpression1.expressionType == DDExpressionTypeFunction)
			{
				// If we have label("A") + label("B") we want to use two different copies of visitedLabels
				hasCycleInExpression1 = [self _expressionIsCyclic:argumentExpression1 cycle:outCycle variableController:variableController visitedLabels:[visitedLabels mutableCopy]];
				if (hasCycleInExpression1)
				{
					return YES;
				}
			}
			
			if (argumentExpression2.expressionType == DDExpressionTypeFunction)
			{
				return [self _expressionIsCyclic:argumentExpression2 cycle:outCycle variableController:variableController visitedLabels:visitedLabels];
			}
			
			return NO;
		}
		case DDExpressionTypeVariable:
		case DDExpressionTypeNumber:
			return NO;
	}
}

+ (BOOL)getVariableCycle:(NSArray<NSString *> * __autoreleasing *)outCycle variable:(ZGVariable *)variable variableController:(ZGVariableController *)variableController
{
	NSString *label = variable.label;
	if (label.length == 0 || !variable.usesDynamicLabelAddress)
	{
		return NO;
	}
	
	NSString *initialExpression = [self expressionBySubstitutingCalculatePointerFunctionInExpression:variable.addressFormula];
	
	NSError *expressionError = NULL;
	DDExpression *expression = [DDExpression expressionFromString:initialExpression error:&expressionError];
	if (expression == nil)
	{
		return NO;
	}
	
	NSMutableOrderedSet<NSString *> *visitedLabels = [NSMutableOrderedSet orderedSetWithObject:label];
	return [self _expressionIsCyclic:expression cycle:outCycle variableController:variableController visitedLabels:visitedLabels];
}

+ (BOOL)isValidExpression:(NSString *)expression
{
	return [[expression stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0;
}

+ (NSString *)evaluateExpression:(NSString *)expression substitutions:(NSDictionary<NSString *, id> *)substitutions error:(NSError * __autoreleasing *)error
{
	if (![self isValidExpression:expression])
	{
		return nil;
	}
	
	return [[expression ddNumberByEvaluatingStringWithSubstitutions:substitutions error:error] stringValue];
}

+ (NSString *)evaluateExpression:(NSString *)expression
{
	NSError *unusedError = nil;
	return [self evaluateExpression:expression substitutions:nil error:&unusedError];
}

+ (NSString *)expressionBySubstitutingCalculatePointerFunctionInExpression:(NSString *)expression
{
	BOOL isInsideSingleQuote = NO;
	BOOL isInsideDoubleQuote = NO;
	
	const char *characters = [expression UTF8String];
	size_t charactersLength = strlen(characters);
	char previousCharacter = 0;
	NSMutableData *newData = [NSMutableData data];
	
	for (size_t characterIndex = 0; characterIndex < charactersLength; characterIndex++)
	{
		char character = characters[characterIndex];
		NSString *substitutionString = nil;
		switch (character)
		{
			case '\'':
				if (!isInsideDoubleQuote && previousCharacter != '\\') isInsideSingleQuote = !isInsideSingleQuote;
				break;
			case '"':
				if (!isInsideSingleQuote && previousCharacter != '\\') isInsideDoubleQuote = !isInsideDoubleQuote;
				break;
			case '[':
				if (!isInsideDoubleQuote && !isInsideSingleQuote) substitutionString = ZGCalculatePointerFunction@"(";
				break;
			case ']':
				if (!isInsideDoubleQuote && !isInsideSingleQuote) substitutionString = @")";
				break;
		}
		
		if (substitutionString != nil)
		{
			const char *substitutionCString = [substitutionString UTF8String];
			[newData appendBytes:substitutionCString length:strlen(substitutionCString)];
		}
		else
		{
			[newData appendBytes:&character length:sizeof(character)];
		}
		
		previousCharacter = character;
	}
	
	return [[NSString alloc] initWithData:newData encoding:NSUTF8StringEncoding];
}

+ (NSDictionary<NSString *, id> *)_evaluatorSubstitutionsForProcess:(ZGProcess * __unsafe_unretained)process variableController:(ZGVariableController *)variableController failedImages:(NSMutableArray<NSString *> * __unsafe_unretained)failedImages symbolicates:(BOOL)symbolicates symbolicationRequiresExactMatch:(BOOL)symbolicationRequiresExactMatch currentAddress:(ZGMemoryAddress)currentAddress
{
	NSMutableDictionary<NSString *, id> *substitutions = [NSMutableDictionary dictionaryWithDictionary:@{ZGProcessVariable : process, ZGSymbolicatesVariable : @(symbolicates), ZGSymbolicationRequiresExactMatch : @(symbolicationRequiresExactMatch), ZGLastSearchInfoVariable : @(currentAddress), ZGDidFindSymbol : @(NO)}];

	if (failedImages != nil)
	{
		[substitutions setObject:failedImages forKey:ZGFailedImagesVariable];
	}
	
	if (variableController != nil)
	{
		[substitutions setObject:variableController forKey:ZGVariableControllerVariable];
	}
	
	return substitutions;
}

+ (NSString *)evaluateExpression:(NSString *)expression variableController:(ZGVariableController *)variableController process:(ZGProcess * __unsafe_unretained)process failedImages:(NSMutableArray<NSString *> * __unsafe_unretained)failedImages symbolicates:(BOOL)symbolicates symbolicationRequiresExactMatch:(BOOL)symbolicationRequiresExactMatch foundSymbol:(BOOL *)foundSymbol currentAddress:(ZGMemoryAddress)currentAddress error:(NSError * __autoreleasing *)error
{
	NSString *newExpression = [self expressionBySubstitutingCalculatePointerFunctionInExpression:expression];
	
	NSDictionary<NSString *, id> *substitutions = [self _evaluatorSubstitutionsForProcess:process variableController:variableController failedImages:failedImages symbolicates:symbolicates symbolicationRequiresExactMatch:symbolicationRequiresExactMatch currentAddress:currentAddress];

	NSString *evaluatedExpression = [self evaluateExpression:newExpression substitutions:substitutions error:error];
	if (foundSymbol != NULL)
	{
		*foundSymbol = [(NSNumber *)[substitutions objectForKey:ZGDidFindSymbol] boolValue];
	}
	
	return evaluatedExpression;
}

+ (NSString *)evaluateAndSymbolicateExpression:(NSString *)expression process:(ZGProcess * __unsafe_unretained)process currentAddress:(ZGMemoryAddress)currentAddress didSymbolicate:(BOOL *)didSymbolicate error:(NSError * __autoreleasing *)error
{
	return [self evaluateExpression:expression variableController:nil process:process failedImages:nil symbolicates:YES symbolicationRequiresExactMatch:NO foundSymbol:didSymbolicate currentAddress:currentAddress error:error];
}

+ (NSString *)evaluateExpression:(NSString *)expression variableController:(ZGVariableController *)variableController process:(ZGProcess * __unsafe_unretained)process failedImages:(NSMutableArray<NSString *> * __unsafe_unretained)failedImages error:(NSError * __autoreleasing *)error
{
	return [self evaluateExpression:expression variableController:variableController process:process failedImages:failedImages symbolicates:YES symbolicationRequiresExactMatch:YES foundSymbol:NULL currentAddress:0x0 error:error];
}

@end
