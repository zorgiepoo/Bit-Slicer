/*
 * Copyright (c) 2013 Mayur Pawashe
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
#import "ZGRunAlertPanel.h"
#import "ZGNullability.h"

#define ZGEditValueLocalizableTable @"[Code] Edit Variable Value"

@implementation ZGEditValueWindowController
{
	ZGVariableController * _Nonnull _variableController;
	NSArray<ZGVariable *> * _Nullable _variablesToEdit;
	ZGMemoryMap _processTask;
	
	IBOutlet NSTextField *_valueTextField;
}

- (id)initWithVariableController:(ZGVariableController *)variableController
{
	self = [super init];
	if (self != nil)
	{
		_variableController = variableController;
	}
	return self;
}

- (NSString *)windowNibName
{
	return @"Edit Value Dialog";
}

- (NSString *)commonByteArrayPatternFromVariables:(NSArray<ZGVariable *> *)variables
{
	ZGVariable *shortestVariable = nil;
	for (ZGVariable *variable in variables)
	{
		if (shortestVariable == nil || variable.size < shortestVariable.size)
		{
			shortestVariable = variable;
		}
	}
	
	NSMutableArray<NSString *> *commonComponents = [NSMutableArray arrayWithArray:[shortestVariable.stringValue componentsSeparatedByString:@" "]];
	for (ZGVariable *variable in variables)
	{
		if (shortestVariable == variable) continue;
		
		NSArray<NSString *> *components = [variable.stringValue componentsSeparatedByString:@" "];
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

- (void)requestEditingValuesFromVariables:(NSArray<ZGVariable *> *)variables withProcessTask:(ZGMemoryMap)processTask attachedToWindow:(NSWindow *)parentWindow scriptManager:(ZGScriptManager *)scriptManager
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
	
	NSWindow *window = ZGUnwrapNullableObject([self window]); // ensure window is loaded
	
	if (!isAllByteArrays)
	{
		_valueTextField.stringValue = firstNonScriptVariable.stringValue;
	}
	else
	{
		_valueTextField.stringValue = [self commonByteArrayPatternFromVariables:variables];
	}
	
	[_valueTextField selectText:nil];
	
	_variablesToEdit = variables;
	_processTask = processTask;
	
	[parentWindow beginSheet:window completionHandler:^(NSModalResponse __unused returnCode) {
	}];
}

- (IBAction)editValues:(id)__unused sender
{
	NSWindow *window = ZGUnwrapNullableObject(self.window);
	[NSApp endSheet:window];
	[window close];
	
	NSMutableArray<ZGVariable *> *validVariables = [[NSMutableArray alloc] init];
	
	for (ZGVariable *variable in _variablesToEdit)
	{
		if (variable.type == ZGScript) continue;
		
		ZGMemoryProtection memoryProtection;
		ZGMemoryAddress memoryAddress = variable.address;
		ZGMemorySize memorySize = variable.size;
		
		if (!ZGMemoryProtectionInRegion(_processTask, &memoryAddress, &memorySize, &memoryProtection)) continue;
		
		if (variable.address >= memoryAddress && variable.address + variable.size <= memoryAddress + memorySize)
		{
			[validVariables addObject:variable];
		}
	}
	
	_variablesToEdit = nil;
	
	if (validVariables.count == 0)
	{
		ZGRunAlertPanelWithOKButton(NSLocalizedStringFromTable(@"overwriteValueFailedAlertTitle", ZGEditValueLocalizableTable, nil), NSLocalizedStringFromTable(@"overwriteValueFailedAlertMessage", ZGEditValueLocalizableTable, nil));
		return;
	}
	
	NSMutableArray<NSString *> *newValues = [[NSMutableArray alloc] init];
	NSString *replaceString = _valueTextField.stringValue;
	
	for (NSUInteger index = 0; index < validVariables.count; index++)
	{
		[newValues addObject:replaceString];
	}
	
	[_variableController editVariables:validVariables newValues:newValues];
}

- (IBAction)cancelEditingValues:(id)__unused sender
{
	NSWindow *window = ZGUnwrapNullableObject(self.window);
	[NSApp endSheet:window];
	[window close];
	_variablesToEdit = nil;
}

@end
