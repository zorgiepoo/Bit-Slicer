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
	NSInteger characterIndex;
	NSInteger numberIndex = 0;
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

@end
