/*
 * Created by Mayur Pawashe on 8/24/10.
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

#import "ZGCalculator.h"
#import "NSStringAdditions.h"
#import "ZGVirtualMemory.h"
#import "ZGVirtualMemoryHelpers.h"
#import "ZGRegion.h"
#import "ZGProcess.h"
#import "DDMathEvaluator.h"
#import "NSString+DDMathParsing.h"
#import "DDExpression.h"

#define ZGCalculatePointerFunction @"ZGCalculatePointerFunction"
#define ZGProcessTaskVariable @"ZGProcessTaskVariable"
#define ZGPointerSizeVariable @"ZGPointerSizeVariable"

@implementation ZGCalculator

+ (void)initialize
{
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		DDMathEvaluator *evaluator = [DDMathEvaluator sharedMathEvaluator];
		[evaluator registerFunction:^DDExpression *(NSArray *args, NSDictionary *vars, DDMathEvaluator *eval, NSError *__autoreleasing *error) {
			ZGMemoryAddress pointer = 0x0;
			if (args.count == 1)
			{
				NSError *unusedError = nil;
				NSNumber *memoryAddressNumber = [[args objectAtIndex:0] evaluateWithSubstitutions:vars evaluator:eval error:&unusedError];
				
				ZGMemoryAddress memoryAddress = [memoryAddressNumber unsignedLongLongValue];
				ZGMemoryMap processTask = [[vars objectForKey:ZGProcessTaskVariable] unsignedIntValue];
				ZGMemorySize pointerSize = [[vars objectForKey:ZGPointerSizeVariable] unsignedLongLongValue];
				
				void *bytes = NULL;
				ZGMemorySize sizeRead = pointerSize;
				if (ZGReadBytes(processTask, memoryAddress, &bytes, &sizeRead))
				{
					if (sizeRead == pointerSize)
					{
						pointer = (pointerSize == sizeof(ZGMemoryAddress)) ? *(ZGMemoryAddress *)bytes : *(ZG32BitMemoryAddress *)bytes;
					}
					else if (error != NULL)
					{
						*error = [NSError errorWithDomain:DDMathParserErrorDomain code:DDErrorCodeInvalidNumber userInfo:@{NSLocalizedDescriptionKey:ZGCalculatePointerFunction @" didn't read sufficient number of bytes"}];
					}
					ZGFreeBytes(processTask, bytes, sizeRead);
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
		
		[evaluator registerFunction:^DDExpression *(NSArray *args, NSDictionary *vars, DDMathEvaluator *eval, NSError *__autoreleasing *error) {
			ZGMemoryAddress foundAddress = 0x0;
			if (args.count == 1)
			{
				ZGMemoryMap processTask = [[vars objectForKey:ZGProcessTaskVariable] unsignedIntValue];
				
				DDExpression *expression = [args objectAtIndex:0];
				if (expression.expressionType == DDExpressionTypeVariable)
				{
					foundAddress = [ZGFindExecutableImage(processTask, expression.variable) address];
				}
				else if (error != NULL)
				{
					*error = [NSError errorWithDomain:DDMathParserErrorDomain code:DDErrorCodeInvalidArgument userInfo:@{NSLocalizedDescriptionKey:ZGBaseAddressFunction @" expects argument to be a variable"}];
				}
			}
			else if (error != NULL)
			{
				*error = [NSError errorWithDomain:DDMathParserErrorDomain code:DDErrorCodeInvalidNumberOfArguments userInfo:@{NSLocalizedDescriptionKey:ZGBaseAddressFunction @" expects 1 argument"}];
			}
			return [DDExpression numberExpressionWithNumber:@(foundAddress)];
		} forName:ZGBaseAddressFunction];
	});
}

+ (BOOL)isValidExpression:(NSString *)expression
{
	return [[expression stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0;
}

+ (NSString *)evaluateExpression:(NSString *)expression substitutions:(NSDictionary *)substitutions
{
	if (![self isValidExpression:expression])
	{
		return nil;
	}
	
	NSError *unusedError = nil;
	return [[expression ddNumberByEvaluatingStringWithSubstitutions:substitutions error:&unusedError] stringValue];
}

+ (NSString *)evaluateExpression:(NSString *)expression
{
	return [self evaluateExpression:expression substitutions:nil];
}

+ (NSString *)evaluateAddress:(NSMutableString *)addressFormula process:(ZGProcess *)process
{
	NSMutableString	 *newAddressFormula = [[NSMutableString alloc] initWithString:addressFormula];
	
	// Handle [expression] by renaming it as a function
	[newAddressFormula replaceOccurrencesOfString:@"[" withString:ZGCalculatePointerFunction@"(" options:NSLiteralSearch range:NSMakeRange(0, newAddressFormula.length)];
	[newAddressFormula replaceOccurrencesOfString:@"]" withString:@")" options:NSLiteralSearch range:NSMakeRange(0, newAddressFormula.length)];
	
	// Pass process task, and pointer size
	NSDictionary *substitutions = @{ZGProcessTaskVariable : @(process.processTask), ZGPointerSizeVariable : @(process.pointerSize)};
	
	return [self evaluateExpression:newAddressFormula substitutions:substitutions];
}

@end
