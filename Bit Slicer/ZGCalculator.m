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
#import "ZGProcess.h"
#import "NSString+DDMathParsing.h"

@implementation ZGCalculator

+ (BOOL)isValidExpression:(NSString *)expression
{
	return [[expression stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0;
}

+ (NSString *)evaluateExpression:(NSString *)expression
{
	if (![self isValidExpression:expression])
	{
		return nil;
	}
	
	NSError *unusedError = nil;
	return [[expression ddNumberByEvaluatingStringWithSubstitutions:nil error:&unusedError] stringValue];
}

// Can evaluate [address] + [address2] + offset, [address + [address2 - [address3]]] + offset, etc...
+ (NSString *)evaluateAddress:(NSMutableString *)addressFormula process:(ZGProcess *)process
{
	NSUInteger addressFormulaIndex;
	NSInteger numberOfOpenBrackets = 0;
	NSInteger numberOfClosedBrackets = 0;
	NSInteger firstOpenBracket = -1;
	NSInteger matchingClosedBracket = -1;
	
	for (addressFormulaIndex = 0; addressFormulaIndex < [addressFormula length]; addressFormulaIndex++)
	{
		if ([addressFormula characterAtIndex:addressFormulaIndex] == '[')
		{
			numberOfOpenBrackets++;
			if (firstOpenBracket == -1)
			{
				firstOpenBracket = addressFormulaIndex;
			}
		}
		else if ([addressFormula characterAtIndex:addressFormulaIndex] == ']')
		{
			numberOfClosedBrackets++;
			if (numberOfClosedBrackets == numberOfOpenBrackets)
			{
				matchingClosedBracket = addressFormulaIndex;
				
				if (firstOpenBracket != -1 && matchingClosedBracket != -1)
				{
					NSString *innerExpression = [addressFormula substringWithRange:NSMakeRange(firstOpenBracket + 1, matchingClosedBracket - firstOpenBracket - 1)];
					NSString *addressExpression =
						[self
						 evaluateAddress:[NSMutableString stringWithString:innerExpression]
						 process:process];
					
					ZGMemoryAddress address;
					if ([addressExpression zgIsHexRepresentation])
					{
						[[NSScanner scannerWithString:addressExpression] scanHexLongLong:&address];
					}
					else
					{
						[[NSScanner scannerWithString:addressExpression] scanLongLong:(long long *)&address];
					}
					
					ZGMemorySize size = process.pointerSize;
					void *value = NULL;
					
					NSMutableString *newExpression;
					
					if (ZGReadBytes([process processTask], address, &value, &size))
					{
						if ([process is64Bit])
						{
							newExpression = [NSMutableString stringWithFormat:@"%llu", *((int64_t *)value)];
						}
						else
						{
							newExpression = [NSMutableString stringWithFormat:@"%u", *((int32_t *)value)];
						}
                        
						ZGFreeBytes([process processTask], value, size);
					}
					else
					{
						newExpression = [NSMutableString stringWithString:@"0x0"];
					}
					
					[addressFormula
					 replaceCharactersInRange:NSMakeRange(firstOpenBracket, matchingClosedBracket - firstOpenBracket + 1)
					 withString:newExpression];
				}
				else
				{
					// just a plain simple expression
					addressFormula = [NSMutableString stringWithString:[[self class] evaluateExpression:addressFormula]];
				}
				
				firstOpenBracket = -1;
				numberOfClosedBrackets = 0;
				numberOfOpenBrackets = 0;
				// Go back to 0 to scan the whole string again
				// We can't just continue from where we just were if a string replacement occurred
				addressFormulaIndex = -1;
			}
		}
	}
	
	return [[self class] evaluateExpression:addressFormula];
}

@end
