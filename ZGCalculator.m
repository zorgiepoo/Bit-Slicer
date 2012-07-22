/*
 * This file is part of Bit Slicer.
 *
 * Bit Slicer is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 
 * Bit Slicer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 
 * You should have received a copy of the GNU General Public License
 * along with Bit Slicer.  If not, see <http://www.gnu.org/licenses/>.
 * 
 * Created by Mayur Pawashe on 8/24/10.
 * Copyright 2010 zgcoder. All rights reserved.
 */

#import "ZGCalculator.h"
#import "NSStringAdditions.h"
#import "ZGVirtualMemory.h"
#import "ZGProcess.h"
#import <unistd.h>

#import <Ruby/ruby.h>

@implementation ZGCalculator

+ (void)initializeCalculator
{
	ruby_init();
	ruby_init_loadpath();
}

+ (NSString *)evaluateExpression:(NSString *)expression
{
	NSString *newExpression = expression;
	
	if (expression)
	{
		int resultState;
		VALUE result = rb_funcall(rb_eval_string_protect([expression UTF8String], &resultState), rb_intern("to_s"), 0);
		if (resultState == 0 && result != Qnil && TYPE(result) == T_STRING)
		{
			newExpression =
				[NSString
				 stringWithCString:((struct RString *)result)->ptr
				 encoding:NSUTF8StringEncoding];
		}
	}
	
	return newExpression;
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
					if ([addressExpression isHexRepresentation])
					{
						[[NSScanner scannerWithString:addressExpression] scanHexLongLong:&address];
					}
					else
					{
						[[NSScanner scannerWithString:addressExpression] scanLongLong:(long long *)&address];
					}
					
					ZGMemorySize size = process->is64Bit ? sizeof(int64_t) : sizeof(int32_t);
					void *value = NULL;
					
					NSMutableString *newExpression;
					
					if (ZGReadBytes([process processTask], address, &value, &size))
					{
						if (process->is64Bit)
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
