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
#import <DDMathParser/DDMathEvaluator.h>
#import <DDMathParser/NSString+DDMathParsing.h>
#import <DDMathParser/DDExpression.h>
#import <DDMathParser/DDExpressionRewriter.h>
#import "ZGDebugLogging.h"
#import "ZGNullability.h"

#define ZGCalculatePointerFunction @"ZGCalculatePointerFunction"
#define ZGFindSymbolFunction @"symbol"
#define ZGProcessVariable @"ZGProcessVariable"
#define ZGFailedImagesVariable @"ZGFailedImagesVariable"
#define ZGSymbolicatesVariable @"ZGSymbolicatesVariable"
#define ZGDidFindSymbol @"ZGDidFindSymbol"
#define ZGLastSearchInfoVariable @"ZGLastSearchInfoVariable"

@implementation ZGVariable (ZGCalculatorAdditions)

- (BOOL)usesDynamicPointerAddress
{
	return _addressFormula != nil && [_addressFormula rangeOfString:@"["].location != NSNotFound && [_addressFormula rangeOfString:@"]"].location != NSNotFound;
}

- (BOOL)usesDynamicBaseAddress
{
	return _addressFormula != nil && [_addressFormula rangeOfString:ZGBaseAddressFunction].location != NSNotFound;
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
					symbolAddressNumber = [process.symbolicator findSymbol:symbolString withPartialSymbolOwnerName:targetOwnerNameSuffix requiringExactMatch:NO pastAddress:[currentAddressNumber unsignedLongLongValue] allowsWrappingToBeginning:YES];
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

+ (NSString *)evaluateExpression:(NSString *)expression process:(ZGProcess * __unsafe_unretained)process failedImages:(NSMutableArray<NSString *> * __unsafe_unretained)failedImages symbolicates:(BOOL)symbolicates foundSymbol:(BOOL *)foundSymbol currentAddress:(ZGMemoryAddress)currentAddress error:(NSError * __autoreleasing *)error
{
	NSString *newExpression = [self expressionBySubstitutingCalculatePointerFunctionInExpression:expression];
	
	NSMutableDictionary<NSString *, id> *substitutions = [NSMutableDictionary dictionaryWithDictionary:@{ZGProcessVariable : process, ZGSymbolicatesVariable : @(symbolicates), ZGLastSearchInfoVariable : @(currentAddress), ZGDidFindSymbol : @(NO)}];

	if (failedImages != nil)
	{
		[substitutions setObject:failedImages forKey:ZGFailedImagesVariable];
	}

	NSString *evaluatedExpression = [self evaluateExpression:newExpression substitutions:substitutions error:error];
	if (foundSymbol != NULL)
	{
		*foundSymbol = [(NSNumber *)[substitutions objectForKey:ZGDidFindSymbol] boolValue];
	}
	
	return evaluatedExpression;
}

+ (NSString *)evaluateAndSymbolicateExpression:(NSString *)expression process:(ZGProcess * __unsafe_unretained)process currentAddress:(ZGMemoryAddress)currentAddress didSymbolicate:(BOOL *)didSymbolicate error:(NSError * __autoreleasing *)error
{
	return [self evaluateExpression:expression process:process failedImages:nil symbolicates:YES foundSymbol:didSymbolicate currentAddress:currentAddress error:error];
}

+ (NSString *)evaluateExpression:(NSString *)expression process:(ZGProcess * __unsafe_unretained)process failedImages:(NSMutableArray<NSString *> * __unsafe_unretained)failedImages error:(NSError * __autoreleasing *)error
{
	return [self evaluateExpression:expression process:process failedImages:failedImages symbolicates:NO foundSymbol:NULL currentAddress:0x0 error:error];
}

@end
