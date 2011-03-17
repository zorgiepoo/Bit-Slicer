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

@implementation ZGCalculator

+ (NSString *)evaluateExpression:(NSString *)expression
{
#ifndef _DEBUG
	NSString *newExpression = nil;
	
	@try
	{
		if ([[NSFileManager defaultManager] fileExistsAtPath:CALC_PATH])
		{
			NSTask *task = [[NSTask alloc] init];
			
			[task setLaunchPath:CALC_PATH];
			[task setArguments:[NSArray arrayWithObjects:@"--", [NSString stringWithFormat:@"%@", expression], nil]];
			
			NSPipe *outputPipe = [NSPipe pipe];
			[task setStandardOutput:outputPipe];
			
			[task launch];
			[task waitUntilExit];
			
			NSString *dataString = [[NSString alloc] initWithData:[[outputPipe fileHandleForReading] readDataToEndOfFile]
														 encoding:NSUTF8StringEncoding];
			
			newExpression = [dataString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			[dataString release];
			
			if ([newExpression length] > 1 && [newExpression characterAtIndex:0] == '~')
			{
				// This is an approximation, just cut the character off..
				newExpression = [newExpression substringFromIndex:1];
			}
		}
	}
	@catch (NSException *exception)
	{
		NSLog(@"Calculator is broken: (%@) %@", [exception name], [exception reason]);
		newExpression = nil;
	}
	
	return (newExpression == nil ? expression : newExpression);
#else
	// The calculator will not run in debug mode if one process is still open for receiving input
	// so I'll do this instead..
	return expression;
#endif
}

// Only works with simple expressions where there are only numbers, spaces, +, and -, but it's much faster than
// what evaluateExpression: does
+ (NSString *)evaluateBasicExpression:(NSString *)anExpression
{
	NSMutableString *expression = [NSMutableString stringWithString:anExpression];
	[expression replaceOccurrencesOfString:@" "
								withString:@""
								   options:NSLiteralSearch
									 range:NSMakeRange(0, [expression length])];
	unsigned long long accumulator = 0;
	char operator = 0;
	NSUInteger characterIndex;
	NSUInteger numberIndex = 0;
	for (characterIndex = 0; characterIndex < [expression length]; characterIndex++)
	{
		if ([expression characterAtIndex:characterIndex] == '+' || [expression characterAtIndex:characterIndex] == '-' || characterIndex == [expression length] - 1)
		{
			NSString *number = [expression substringWithRange:NSMakeRange(numberIndex, (characterIndex == [expression length] - 1) ? (characterIndex + 1 - numberIndex) : (characterIndex - numberIndex))];
			unsigned long long value;
			if ([number isHexRepresentation])
			{
				[[NSScanner scannerWithString:number] scanHexLongLong:&value];
			}
			else
			{
				[[NSScanner scannerWithString:number] scanLongLong:(long long *)&value];
			}
			
			if (numberIndex == 0)
			{
				accumulator = value;
			}
			else if (operator == '+')
			{
				accumulator += value;
			}
			else if (operator == '-')
			{
				accumulator -= value;
			}
			
			numberIndex = characterIndex + 1;
			operator = [expression characterAtIndex:characterIndex];
		}
	}
	
	return [NSString stringWithFormat:@"%llu", accumulator];
}

// Can evaluate [address] + [address2] + offset, [address + [address2 - [address3]]] + offset, etc...
+ (NSString *)evaluateAddress:(NSMutableString *)addressFormula
					  process:(ZGProcess *)process
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
					NSString *addressExpression = [self evaluateAddress:[NSMutableString stringWithString:innerExpression]
																process:process];
					
					mach_vm_address_t address;
					if ([addressExpression isHexRepresentation])
					{
						[[NSScanner scannerWithString:addressExpression] scanHexLongLong:&address];
					}
					else
					{
						[[NSScanner scannerWithString:addressExpression] scanLongLong:(long long *)&address];
					}
					
					mach_vm_size_t size = process->is64Bit ? sizeof(int64_t) : sizeof(int32_t);
					void *value = malloc((size_t)size);
					
					NSMutableString *newExpression;
					
					if (ZGReadBytes([process processID], address, value, size))
					{
						if (process->is64Bit)
						{
							newExpression = [NSMutableString stringWithFormat:@"%llu", *((int64_t *)value)];
						}
						else
						{
							newExpression = [NSMutableString stringWithFormat:@"%u", *((int32_t *)value)];
						}
					}
					else
					{
						newExpression = [NSMutableString stringWithString:@"0x0"];
					}
					
					free(value);
					
					[addressFormula replaceCharactersInRange:NSMakeRange(firstOpenBracket, matchingClosedBracket - firstOpenBracket + 1)
												  withString:newExpression];
				}
				else
				{
					// just a plain simple expression
					addressFormula = [NSMutableString stringWithString:[ZGCalculator evaluateBasicExpression:addressFormula]];
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
	
	return [ZGCalculator evaluateBasicExpression:addressFormula];
}

@end
