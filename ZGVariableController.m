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
 * Created by Mayur Pawashe on 7/20/12.
 * Copyright 2012 zgcoder. All rights reserved.
 */

#import "ZGVariableController.h"
#import "ZGDocument.h"
#import "ZGVariable.h"
#import "ZGProcess.h"
#import "NSStringAdditions.h"
#import "ZGCalculator.h"
#import "ZGUtilities.h"

@implementation ZGVariableController

#pragma mark Changing Variables

- (void)changeVariable:(ZGVariable *)variable newName:(NSString *)newName
{
	[[document undoManager] setActionName:@"Name Change"];
	[[[document undoManager] prepareWithInvocationTarget:self]
	 changeVariable:variable
	 newName:[variable name]];
	
	[variable setName:newName];
	
	if ([[document undoManager] isUndoing] || [[document undoManager] isRedoing])
	{
		[[document watchVariablesTableView] reloadData];
	}
}

- (void)changeVariable:(ZGVariable *)variable newAddress:(NSString *)newAddress
{
	[[document undoManager] setActionName:@"Address Change"];
	[[[document undoManager] prepareWithInvocationTarget:self]
	 changeVariable:variable
	 newAddress:[variable addressStringValue]];
	
	[variable setAddressStringValue:[ZGCalculator evaluateExpression:newAddress]];
	
	if ([[document undoManager] isUndoing] || [[document undoManager] isRedoing])
	{
		[[document watchVariablesTableView] reloadData];
	}
}

- (void)changeVariable:(ZGVariable *)variable newType:(ZGVariableType)type newSize:(ZGMemorySize)size
{
	[[document undoManager] setActionName:@"Type Change"];
	[[[document undoManager] prepareWithInvocationTarget:self]
	 changeVariable:variable
	 newType:variable->type
	 newSize:variable->size];
	
	[variable
	 setType:type
	 requestedSize:size
	 pointerSize:[document currentProcess]->is64Bit ? sizeof(int64_t) : sizeof(int32_t)];
	
	if ([[document undoManager] isUndoing] || [[document undoManager] isRedoing])
	{
		[[document watchVariablesTableView] reloadData];
	}
}

- (void)changeVariable:(ZGVariable *)variable newValue:(NSString *)stringObject shouldRecordUndo:(BOOL)recordUndoFlag
{
	void *newValue = NULL;
	ZGMemorySize writeSize = variable->size; // specifically needed for byte arrays
	
	// It's important to retrieve this now instead of later as changing the variable's size may cause a bad side effect to this method
	NSString *oldStringValue = [[variable stringValue] copy];
	
	int8_t int8Value = 0;
	int16_t int16Value = 0;
	int32_t int32Value = 0;
	int64_t int64Value = 0;
	float floatValue = 0.0;
	double doubleValue = 0.0;
	
	if (variable->type != ZGUTF8String && variable->type != ZGUTF16String && variable->type != ZGByteArray)
	{
		stringObject = [ZGCalculator evaluateExpression:stringObject];
	}
	
	BOOL stringIsAHexRepresentation = [stringObject isHexRepresentation];
	
	switch (variable->type)
	{
		case ZGInt8:
			if (stringIsAHexRepresentation)
			{
				[[NSScanner scannerWithString:stringObject] scanHexInt:(unsigned int *)&int32Value];
				int8Value = int32Value;
			}
			else
			{
				int8Value = [stringObject intValue];
			}
			
			newValue = &int8Value;
			break;
		case ZGInt16:
			if (stringIsAHexRepresentation)
			{
				[[NSScanner scannerWithString:stringObject] scanHexInt:(unsigned int *)&int32Value];
				int16Value = int32Value;
			}
			else
			{
				int16Value = [stringObject intValue];
			}
			
			newValue = &int16Value;
			break;
		case ZGPointer:
			if (variable->size == sizeof(int32_t))
			{
				goto INT32_BIT_CHANGE_VARIABLE;
			}
			else if (variable->size == sizeof(int64_t))
			{
				goto INT64_BIT_CHANGE_VARIABLE;
			}
			
			break;
		case ZGInt32:
		INT32_BIT_CHANGE_VARIABLE:
			if (stringIsAHexRepresentation)
			{
				[[NSScanner scannerWithString:stringObject] scanHexInt:(unsigned int *)&int32Value];
			}
			else
			{
				int32Value = [stringObject intValue];
			}
			
			newValue = &int32Value;
			break;
		case ZGFloat:
			if (stringIsAHexRepresentation)
			{
				[[NSScanner scannerWithString:stringObject] scanHexFloat:&floatValue];
			}
			else
			{
				floatValue = [stringObject floatValue];
			}
			
			newValue = &floatValue;
			break;
		case ZGInt64:
		INT64_BIT_CHANGE_VARIABLE:
			if (stringIsAHexRepresentation)
			{
				[[NSScanner scannerWithString:stringObject] scanHexLongLong:(unsigned long long *)&int64Value];
			}
			else
			{
				[[NSScanner scannerWithString:stringObject] scanLongLong:&int64Value];
			}
			
			newValue = &int64Value;
			break;
		case ZGDouble:
			if (stringIsAHexRepresentation)
			{
				[[NSScanner scannerWithString:stringObject] scanHexDouble:&doubleValue];
			}
			else
			{
				doubleValue = [stringObject doubleValue];
			}
			
			newValue = &doubleValue;
			break;
		case ZGUTF8String:
			newValue = (void *)[stringObject cStringUsingEncoding:NSUTF8StringEncoding];
			variable->size = strlen(newValue) + 1;
			writeSize = variable->size;
			break;
		case ZGUTF16String:
			variable->size = [stringObject length] * sizeof(unichar);
			writeSize = variable->size;
			
			if (variable->size)
			{
				newValue = malloc((size_t)variable->size);
				[stringObject
				 getCharacters:newValue
				 range:NSMakeRange(0, [stringObject length])];
			}
			else
			{
				// String "" can be of 0 length
				newValue = malloc(sizeof(unichar));
				
				if (newValue)
				{
					unichar nullTerminator = 0;
					memcpy(newValue, &nullTerminator, sizeof(unichar));
				}
			}
			
			break;
			
		case ZGByteArray:
		{
			NSArray *bytesArray = [stringObject componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			
			// this is the size the user wants
			variable->size = [bytesArray count];
			
			// this is the maximum size allocated needed
			newValue = malloc((size_t)variable->size);
			
			if (newValue)
			{
				unsigned char *valuePtr = newValue;
				writeSize = 0;
				
				for (NSString *byteString in bytesArray)
				{
					unsigned int theValue = 0;
					[[NSScanner scannerWithString:byteString] scanHexInt:&theValue];
					*valuePtr = (unsigned char)theValue;
					valuePtr++;
					
					if ([[byteString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] == 0)
					{
						break;
					}
					
					writeSize++;
				}
			}
			else
			{
				variable->size = writeSize;
			}
			
			break;
		}
	}
	
	if (newValue)
	{
		if (variable->isFrozen)
		{
			[variable setFreezeValue:newValue];
			
			if (recordUndoFlag)
			{
				[[document undoManager] setActionName:@"Freeze Value Change"];
				[[[document undoManager] prepareWithInvocationTarget:self]
				 changeVariable:variable
				 newValue:[variable stringValue]
				 shouldRecordUndo:YES];
				
				if ([[document undoManager] isUndoing] || [[document undoManager] isRedoing])
				{
					[[document watchVariablesTableView] reloadData];
				}
			}
		}
		else
		{
			BOOL successfulWrite = YES;
			
			if (writeSize)
			{
				if (!ZGWriteBytes([[document currentProcess] processTask], variable->address, newValue, writeSize))
				{
					successfulWrite = NO;
				}
			}
			else
			{
				successfulWrite = NO;
			}
			
			if (successfulWrite && variable->type == ZGUTF16String)
			{
				// Don't forget to write the null terminator
				unichar nullTerminator = 0;
				if (!ZGWriteBytes([[document currentProcess] processTask], variable->address + writeSize, &nullTerminator, sizeof(unichar)))
				{
					successfulWrite = NO;
				}
			}
			
			if (successfulWrite && recordUndoFlag)
			{
				[[document undoManager] setActionName:@"Value Change"];
				[[[document undoManager] prepareWithInvocationTarget:self]
				 changeVariable:variable
				 newValue:oldStringValue
				 shouldRecordUndo:YES];
				
				if ([[document undoManager] isUndoing] || [[document undoManager] isRedoing])
				{
					[[document watchVariablesTableView] reloadData];
				}
			}
		}
		
		if (variable->type == ZGUTF16String || variable->type == ZGByteArray)
		{
			free(newValue);
		}
	}
	
	[oldStringValue release];
}

- (void)changeVariableShouldBeSearched:(BOOL)shouldBeSearched rowIndexes:(NSIndexSet *)rowIndexes
{
	NSUInteger currentIndex = [rowIndexes firstIndex];
	while (currentIndex != NSNotFound)
	{
		[[[document watchVariablesArray] objectAtIndex:currentIndex] setShouldBeSearched:shouldBeSearched];
		currentIndex = [rowIndexes indexGreaterThanIndex:currentIndex];
	}
	
	if (![[document undoManager] isUndoing] && ![[document undoManager] isRedoing] && [rowIndexes count] > 1)
	{
		[document setShouldIgnoreTableViewSelectionChange:YES];
	}
	
	// the table view always needs to be reloaded because of being able to select multiple indexes
	[[document watchVariablesTableView] reloadData];
	
	[[document undoManager] setActionName:[NSString stringWithFormat:@"Search Variable%@ Change", ([rowIndexes count] > 1) ? @"s" : @""]];
	[[[document undoManager] prepareWithInvocationTarget:self]
	 changeVariableShouldBeSearched:!shouldBeSearched
	 rowIndexes:rowIndexes];
}

#pragma mark Edit Variables Values

- (IBAction)editVariablesValueCancelButton:(id)sender
{
	[NSApp endSheet:editVariablesValueWindow];
	[editVariablesValueWindow close];
}

- (void)editVariables:(NSArray *)variables newValues:(NSArray *)newValues
{
	NSMutableArray *oldValues = [[NSMutableArray alloc] init];
	
	[variables enumerateObjectsUsingBlock:^(id object, NSUInteger index, BOOL *stop)
	 {
		 ZGVariable *variable = object;
		 
		 [oldValues addObject:[variable stringValue]];
		 
		 [self
		  changeVariable:variable
		  newValue:[newValues objectAtIndex:index]
		  shouldRecordUndo:NO];
	 }];
	
	[[document watchVariablesTableView] reloadData];
	
	[[document undoManager] setActionName:@"Edit Variables"];
	[[[document undoManager] prepareWithInvocationTarget:self]
	 editVariables:variables
	 newValues:oldValues];
	
	[oldValues release];
}

- (IBAction)editVariablesValueOkayButton:(id)sender
{
	[NSApp endSheet:editVariablesValueWindow];
	[editVariablesValueWindow close];
	
	NSArray *variables = [[document watchVariablesArray] objectsAtIndexes:[[document watchVariablesTableView] selectedRowIndexes]];
	NSMutableArray *validVariables = [[NSMutableArray alloc] init];
	
	for (ZGVariable *variable in variables)
	{
		ZGMemoryProtection memoryProtection;
		ZGMemoryAddress memoryAddress = variable->address;
		ZGMemorySize memorySize;
		
		if (ZGMemoryProtectionInRegion([[document currentProcess] processTask], &memoryAddress, &memorySize, &memoryProtection))
		{
			// if !(the variable is within a single memory region and the memory region is not writable), then the variable is editable
			if (!(memoryAddress <= variable->address && memoryAddress + memorySize >= variable->address + variable->size && !(memoryProtection & VM_PROT_WRITE)))
			{
				[validVariables addObject:variable];
			}
		}
	}
	
	if ([validVariables count] == 0)
	{
		NSRunAlertPanel(@"Writing Variables Failed", @"The selected variables could not be overwritten. Perhaps try to change the memory protection on the variable?", nil, nil, nil);
	}
	else
	{
		NSMutableArray *valuesArray = [[NSMutableArray alloc] init];
		
		NSUInteger variableIndex;
		for (variableIndex = 0; variableIndex < [validVariables count]; variableIndex++)
		{
			[valuesArray addObject:[editVariablesValueTextField stringValue]];
		}
		
		[self
		 editVariables:validVariables
		 newValues:valuesArray];
        
		[valuesArray release];
	}
	
	[validVariables release];
}

- (void)editVariablesValueRequest
{
	[editVariablesValueTextField setStringValue:[[[document watchVariablesArray] objectAtIndex:[[document watchVariablesTableView] selectedRow]] stringValue]];
	
	[NSApp
	 beginSheet:editVariablesValueWindow
	 modalForWindow:[document watchWindow]
	 modalDelegate:self
	 didEndSelector:nil
	 contextInfo:NULL];
}

#pragma mark Edit Variables Address

- (IBAction)editVariablesAddressCancelButton:(id)sender
{
	[NSApp endSheet:editVariablesAddressWindow];
	[editVariablesAddressWindow close];
}

- (void)editVariable:(ZGVariable *)variable addressFormula:(NSString *)newAddressFormula
{
	[[document undoManager] setActionName:@"Address Change"];
	[[[document undoManager] prepareWithInvocationTarget:self]
	 editVariable:variable
	 addressFormula:[variable addressFormula]];
	
	[variable setAddressFormula:newAddressFormula];
	if ([newAddressFormula rangeOfString:@"["].location != NSNotFound && [newAddressFormula rangeOfString:@"]"].location != NSNotFound)
	{
		variable->isPointer = YES;
	}
	else
	{
		variable->isPointer = NO;
		[variable setAddressStringValue:[ZGCalculator evaluateExpression:newAddressFormula]];
		[[document watchVariablesTableView] reloadData];
	}
}

- (IBAction)editVariablesAddressOkayButton:(id)sender
{
	[NSApp endSheet:editVariablesAddressWindow];
	[editVariablesAddressWindow close];
	
	[self
	 editVariable:[[document watchVariablesArray] objectAtIndex:[[document watchVariablesTableView] selectedRow]]
	 addressFormula:[editVariablesAddressTextField stringValue]];
}

- (void)editVariablesAddressRequest
{
	ZGVariable *variable = [[document watchVariablesArray] objectAtIndex:[[document watchVariablesTableView] selectedRow]];
	[editVariablesAddressTextField setStringValue:[variable addressFormula]];
	
	[NSApp
	 beginSheet:editVariablesAddressWindow
	 modalForWindow:[document watchWindow]
	 modalDelegate:self
	 didEndSelector:nil
	 contextInfo:NULL];
}

#pragma mark Edit Variables Sizes (Byte Arrays)

- (IBAction)editVariablesSizeCancelButton:(id)sender
{
	[NSApp endSheet:editVariablesSizeWindow];
	[editVariablesSizeWindow close];
}

- (void)editVariables:(NSArray *)variables requestedSizes:(NSArray *)requestedSizes
{
	NSMutableArray *currentVariableSizes = [[NSMutableArray alloc] init];
	NSMutableArray *validVariables = [[NSMutableArray alloc] init];
	
	// Make sure the size changes are possible. Only change the ones that seem possible.
	[variables enumerateObjectsUsingBlock:^(ZGVariable *variable, NSUInteger index, BOOL *stop)
	 {
		 ZGMemorySize size = [[requestedSizes objectAtIndex:index] unsignedLongLongValue];
		 void *buffer = NULL;
		 
		 if (ZGReadBytes([[document currentProcess] processTask], variable->address, &buffer, &size))
		 {
			 if (size == [[requestedSizes objectAtIndex:index] unsignedLongLongValue])
			 {
				 [validVariables addObject:variable];
				 [currentVariableSizes addObject:[NSNumber numberWithUnsignedLongLong:variable->size]];
			 }
			 
			 ZGFreeBytes([[document currentProcess] processTask], buffer, size);
		 }
	 }];
	
	if ([validVariables count] > 0)
	{
		[[document undoManager] setActionName:@"Size Change"];
		[[[document undoManager] prepareWithInvocationTarget:self]
		 editVariables:validVariables
		 requestedSizes:currentVariableSizes];
		
		[validVariables enumerateObjectsUsingBlock:^(ZGVariable *variable, NSUInteger index, BOOL *stop)
		 {
			 variable->size = [[requestedSizes objectAtIndex:index] unsignedLongLongValue];
		 }];
		
		[[document watchVariablesTableView] reloadData];
	}
	else
	{
		NSRunAlertPanel(@"Failed to change size", @"The size that you have requested could not be changed. Perhaps it is too big of a value?", nil, nil, nil);
	}
	
	[currentVariableSizes release];
	[validVariables release];
}

- (IBAction)editVariablesSizeOkayButton:(id)sender
{
	NSString *sizeExpression = [ZGCalculator evaluateExpression:[editVariablesSizeTextField stringValue]];
	
	ZGMemorySize requestedSize = 0;
	if ([sizeExpression isHexRepresentation])
	{
		[[NSScanner scannerWithString:sizeExpression] scanHexLongLong:&requestedSize];
	}
	else
	{
		requestedSize = [sizeExpression unsignedLongLongValue];
	}
	
	if (!isValidNumber(sizeExpression))
	{
		NSRunAlertPanel(@"Invalid size", @"The size you have supplied is not valid.", nil, nil, nil);
	}
	else if (requestedSize <= 0)
	{
		NSRunAlertPanel(@"Failed to edit size", @"The size must be greater than 0.", nil, nil, nil);
	}
	else
	{
		[NSApp endSheet:editVariablesSizeWindow];
		[editVariablesSizeWindow close];
		
		NSArray *variables = [[document watchVariablesArray] objectsAtIndexes:[[document watchVariablesTableView] selectedRowIndexes]];
		NSMutableArray *requestedSizes = [[NSMutableArray alloc] init];
		
		NSUInteger variableIndex;
		for (variableIndex = 0; variableIndex < [variables count]; variableIndex++)
		{
			[requestedSizes addObject:[NSNumber numberWithUnsignedLongLong:requestedSize]];
		}
		
		[self
		 editVariables:variables
		 requestedSizes:requestedSizes];
        
		[requestedSizes release];
	}
}

- (void)editVariablesSizeRequest
{
	ZGVariable *firstVariable = [[document watchVariablesArray] objectAtIndex:[[document watchVariablesTableView] selectedRow]];
	[editVariablesSizeTextField setStringValue:[firstVariable sizeStringValue]];
	
	[NSApp
	 beginSheet:editVariablesSizeWindow
	 modalForWindow:[document watchWindow]
	 modalDelegate:self
	 didEndSelector:nil
	 contextInfo:NULL];
}

@end
