/*
 * Created by Mayur Pawashe on 11/28/13.
 *
 * Copyright (c) 2013 zgcoder
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

#import "ZGEditValueWindowController.h"
#import "ZGVariableController.h"
#import "ZGScriptManager.h"
#import "ZGVariable.h"
#import "ZGProcess.h"
#import "ZGVirtualMemory.h"
#import "ZGUtilities.h"

@interface ZGEditValueWindowController ()

@property (assign) IBOutlet NSTextField *valueTextField;
@property (assign) ZGVariableController *variableController;

@property (nonatomic) NSArray *variablesToEdit;
@property (nonatomic) ZGMemoryMap processTask;

@end

@implementation ZGEditValueWindowController

- (id)initWithVariableController:(ZGVariableController *)variableController
{
	self = [super init];
	if (self != nil)
	{
		self.variableController = variableController;
	}
	return self;
}

- (NSString *)windowNibName
{
	return NSStringFromClass([self class]);
}

- (NSString *)commonByteArrayPatternFromVariables:(NSArray *)variables
{
	ZGVariable *shortestVariable = nil;
	for (ZGVariable *variable in variables)
	{
		if (shortestVariable == nil || variable.size < shortestVariable.size)
		{
			shortestVariable = variable;
		}
	}
	
	NSMutableArray *commonComponents = [NSMutableArray arrayWithArray:[shortestVariable.stringValue componentsSeparatedByString:@" "]];
	for (ZGVariable *variable in variables)
	{
		if (shortestVariable == variable) continue;
		
		NSArray *components = [variable.stringValue componentsSeparatedByString:@" "];
		for (NSUInteger componentIndex = 0; componentIndex < commonComponents.count; componentIndex++)
		{
			NSString *commonComponent = [commonComponents objectAtIndex:componentIndex];
			NSString *candidateComponent = [components objectAtIndex:componentIndex];
			
			if (commonComponent.length != 2 || candidateComponent.length != 2) continue;
			
			unichar commonCharacters[2];
			[commonComponent getCharacters:commonCharacters];
			
			if (commonCharacters[0] == '?' && commonCharacters[1] == '?') continue;
			
			unichar candidateCharacters[2];
			[candidateComponent getCharacters:candidateCharacters];
			
			if (commonCharacters[0] != '?' && candidateCharacters[0] != commonCharacters[0])
			{
				commonCharacters[0] = '?';
			}
			
			if (commonCharacters[1] != '?' && candidateCharacters[1] != commonCharacters[1])
			{
				commonCharacters[1] = '?';
			}
			
			NSString *newCommonComponent = [NSString stringWithCharacters:commonCharacters length:2];
			[commonComponents replaceObjectAtIndex:componentIndex withObject:newCommonComponent];
		}
	}
	
	return [commonComponents componentsJoinedByString:@" "];
}

- (void)requestEditingValuesFromVariables:(NSArray *)variables withProcessTask:(ZGMemoryMap)processTask attachedToWindow:(NSWindow *)parentWindow scriptManager:(ZGScriptManager *)scriptManager
{
	ZGVariable *firstNonScriptVariable = nil;
	BOOL isAllByteArrays = YES;
	for (ZGVariable *variable in variables)
	{
		if (variable.type == ZGScript)
		{
			[scriptManager openScriptForVariable:variable];
		}
		else if (firstNonScriptVariable == nil)
		{
			firstNonScriptVariable = variable;
		}
		
		if (variable.type != ZGByteArray)
		{
			isAllByteArrays = NO;
		}
	}
	
	if (firstNonScriptVariable == nil) return;
	
	[self window]; // ensure window is loaded
	
	if (!isAllByteArrays)
	{
		self.valueTextField.stringValue = firstNonScriptVariable.stringValue;
	}
	else
	{
		self.valueTextField.stringValue = [self commonByteArrayPatternFromVariables:variables];
	}
	
	self.variablesToEdit = variables;
	self.processTask = processTask;
	
	[NSApp
	 beginSheet:self.window
	 modalForWindow:parentWindow
	 modalDelegate:self
	 didEndSelector:nil
	 contextInfo:NULL];
}

- (IBAction)editValues:(id)sender
{
	[NSApp endSheet:self.window];
	[self.window close];
	
	NSMutableArray *validVariables = [[NSMutableArray alloc] init];
	
	for (ZGVariable *variable in self.variablesToEdit)
	{
		if (variable.type == ZGScript) continue;
		
		ZGMemoryProtection memoryProtection;
		ZGMemoryAddress memoryAddress = variable.address;
		ZGMemorySize memorySize = variable.size;
		
		if (!ZGMemoryProtectionInRegion(self.processTask, &memoryAddress, &memorySize, &memoryProtection)) continue;
		
		if (variable.address >= memoryAddress && variable.address + variable.size <= memoryAddress + memorySize)
		{
			[validVariables addObject:variable];
		}
	}
	
	if (validVariables.count == 0)
	{
		NSRunAlertPanel(@"Writing Variables Failed", @"The selected variables could not be overwritten.", nil, nil, nil);
	}
	else
	{
		NSMutableArray *valuesArray = [[NSMutableArray alloc] init];
		
		NSString *replaceString = self.valueTextField.stringValue;
		NSArray *replaceComponents = nil;
		
		for (NSUInteger variableIndex = 0; variableIndex < validVariables.count; variableIndex++)
		{
			ZGVariable *variable = [validVariables objectAtIndex:variableIndex];
			
			if (variable.type != ZGByteArray || ([replaceString rangeOfString:@"?"].location == NSNotFound &&  [replaceString rangeOfString:@"*"].location == NSNotFound))
			{
				[valuesArray addObject:replaceString];
			}
			else
			{
				NSArray *variableComponents = ZGByteArrayComponentsFromString(variable.stringValue);
				if (replaceComponents == nil)
				{
					replaceComponents = ZGByteArrayComponentsFromString(replaceString);
				}
				
				NSMutableArray *newReplaceComponents = [NSMutableArray array];
				for (NSUInteger componentIndex = 0; componentIndex < MIN(variableComponents.count, replaceComponents.count); componentIndex++)
				{
					NSString *variableComponent = [variableComponents objectAtIndex:componentIndex];
					NSString *replaceComponent = [replaceComponents objectAtIndex:componentIndex];
					
					unichar variableCharacters[2];
					[variableComponent getCharacters:variableCharacters];
					
					unichar replaceCharacters[2];
					[replaceComponent getCharacters:replaceCharacters	];
					
					unichar newCharacters[2];
					newCharacters[0] = (replaceCharacters[0] == '?' || replaceCharacters[0] == '*') ? variableCharacters[0] : replaceCharacters[0];
					newCharacters[1] = (replaceCharacters[1] == '?' || replaceCharacters[1] == '*') ? variableCharacters[1] : replaceCharacters[1];
					
					[newReplaceComponents addObject:[NSString stringWithCharacters:newCharacters length:2]];
				}
				
				[valuesArray addObject:[newReplaceComponents componentsJoinedByString:@" "]];
			}
		}
		
		[self.variableController editVariables:validVariables newValues:valuesArray];
	}
	
	self.variablesToEdit = nil;
}

- (IBAction)cancelEditingValues:(id)sender
{
	[NSApp endSheet:self.window];
	[self.window close];
	self.variablesToEdit = nil;
}

@end
