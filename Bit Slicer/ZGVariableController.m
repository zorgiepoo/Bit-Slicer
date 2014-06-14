/*
 * Created by Mayur Pawashe on 7/20/12.
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

#import "ZGVariableController.h"
#import "ZGDocumentTableController.h"
#import "ZGMemoryViewerController.h"
#import "ZGVariable.h"
#import "ZGProcess.h"
#import "NSStringAdditions.h"
#import "ZGCalculator.h"
#import "ZGUtilities.h"
#import "ZGInstruction.h"
#import "ZGVirtualMemory.h"
#import "ZGVirtualMemoryHelpers.h"
#import "ZGDocumentSearchController.h"
#import "ZGSearchResults.h"
#import "ZGDocumentWindowController.h"
#import "ZGDocumentData.h"
#import "ZGScriptManager.h"
#import "ZGMachBinary.h"
#import "ZGMachBinaryInfo.h"
#import "ZGTableView.h"
#import "NSArrayAdditions.h"
#import "ZGNavigationPost.h"

@interface ZGVariableController ()

// last selection from memory viewer or debugger
@property (nonatomic) NSRange lastSelectedMemoryRangeFromOutside;

@property (nonatomic, assign) ZGDocumentWindowController *windowController;
@property (nonatomic, assign) ZGDocumentData *documentData;

@property (nonatomic) id frozenActivity;

@end

NSString *ZGScriptIndentationUsingTabsKey = @"ZGScriptIndentationUsingTabsKey";
static NSString *ZGScriptIndentationSpacesWidthKey = @"ZGScriptIndentationSpacesWidthKey";

@implementation ZGVariableController

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		[[NSUserDefaults standardUserDefaults] registerDefaults:@{ZGScriptIndentationUsingTabsKey : @NO, ZGScriptIndentationSpacesWidthKey : @4}];
	});
}

- (id)initWithWindowController:(ZGDocumentWindowController *)windowController
{
	self = [super init];
	if (self)
	{
		self.windowController = windowController;
		self.documentData = self.windowController.documentData;
		
		[[NSNotificationCenter defaultCenter]
		 addObserver:self
		 selector:@selector(memorySelectionChangedFromMemoryWindowNotification:)
		 name:ZGNavigationSelectionChangeNotification
		 object:nil];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter]
	 removeObserver:self
	 name:ZGNavigationSelectionChangeNotification
	 object:nil];
}

- (void)memorySelectionChangedFromMemoryWindowNotification:(NSNotification *)notification
{
	ZGProcess *process = [notification.userInfo objectForKey:ZGNavigationProcessKey];
	ZGMemoryAddress selectionAddress = [[notification.userInfo objectForKey:ZGNavigationMemoryAddressKey] unsignedLongLongValue];
	ZGMemoryAddress selectionSize = [[notification.userInfo objectForKey:ZGNavigationSelectionLengthKey] unsignedLongLongValue];
	
	if ([process isEqual:self.windowController.currentProcess])
	{
		self.lastSelectedMemoryRangeFromOutside = NSMakeRange(selectionAddress, selectionSize);
	}
}

#pragma mark Freezing variables

- (void)updateFrozenActivity
{
	BOOL hasFrozenVariable = [self.documentData.variables zgHasObjectMatchingCondition:^(ZGVariable *variable) { return (BOOL)(variable.isFrozen && variable.enabled); }];

	if (hasFrozenVariable && self.frozenActivity == nil && [[NSProcessInfo processInfo] respondsToSelector:@selector(beginActivityWithOptions:reason:)]	)
	{
		self.frozenActivity = [[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiated reason:@"Freezing Variables"];
	}
	else if (!hasFrozenVariable && self.frozenActivity != nil)
	{
		[[NSProcessInfo processInfo] endActivity:self.frozenActivity];
		self.frozenActivity = nil;
	}
}

- (void)freezeOrUnfreezeVariablesAtRoxIndexes:(NSIndexSet *)rowIndexes
{
	for (ZGVariable *variable in [self.documentData.variables objectsAtIndexes:rowIndexes])
	{
		variable.isFrozen = !variable.isFrozen;
		
		if (variable.isFrozen)
		{
			variable.freezeValue = variable.rawValue;
		}
	}
	
	[self updateFrozenActivity];
	[self.windowController.tableController.variablesTableView reloadData];
	
	// check whether we want to use "Undo Freeze" or "Redo Freeze" or "Undo Unfreeze" or "Redo Unfreeze"
	if ([[self.documentData.variables objectAtIndex:rowIndexes.firstIndex] isFrozen])
	{
		if (self.windowController.undoManager.isUndoing)
		{
			self.windowController.undoManager.actionName = @"Unfreeze";
		}
		else
		{
			self.windowController.undoManager.actionName = @"Freeze";
		}
	}
	else
	{
		if (self.windowController.undoManager.isUndoing)
		{
			self.windowController.undoManager.actionName = @"Freeze";
		}
		else
		{
			self.windowController.undoManager.actionName = @"Unfreeze";
		}
	}
	
	[[self.windowController.undoManager prepareWithInvocationTarget:self] freezeOrUnfreezeVariablesAtRoxIndexes:rowIndexes];
}

- (void)freezeVariables
{
	[self freezeOrUnfreezeVariablesAtRoxIndexes:self.windowController.selectedVariableIndexes];
}

#pragma mark Copying & Pasting

+ (void)copyVariableAddress:(ZGVariable *)variable
{
	[NSPasteboard.generalPasteboard
	 declareTypes:@[NSStringPboardType]
	 owner:self];
	
	[NSPasteboard.generalPasteboard
	 setString:variable.addressFormula
	 forType:NSStringPboardType];
}

- (void)copyAddress
{
	[[self class] copyVariableAddress:[[self.windowController selectedVariables] objectAtIndex:0]];
}

+ (void)copyVariablesToPasteboard:(NSArray *)variables
{
	[NSPasteboard.generalPasteboard
	 declareTypes:@[NSStringPboardType, ZGVariablePboardType]
	 owner:self];
	
	NSMutableArray *linesToWrite = [[NSMutableArray alloc] init];
	
	for (ZGVariable *variable in variables)
	{
		if (variable.type != ZGScript)
		{
			[linesToWrite addObject:[@[variable.shortDescription, variable.addressFormula, variable.stringValue] componentsJoinedByString:@"\t"]];
		}
	}
	
	[NSPasteboard.generalPasteboard
	 setString:[linesToWrite componentsJoinedByString:@"\n"]
	 forType:NSStringPboardType];
	
	[NSPasteboard.generalPasteboard
	 setData:[NSKeyedArchiver archivedDataWithRootObject:variables]
	 forType:ZGVariablePboardType];
}

- (void)copyVariables
{
	[[self class] copyVariablesToPasteboard:[self.windowController selectedVariables]];
}

- (void)pasteVariables
{
	NSData *pasteboardData = [NSPasteboard.generalPasteboard dataForType:ZGVariablePboardType];
	if (pasteboardData)
	{
		NSArray *variablesToInsertArray = [NSKeyedUnarchiver unarchiveObjectWithData:pasteboardData];
		NSUInteger currentIndex = self.windowController.selectedVariableIndexes.count == 0 ? 0 : self.windowController.selectedVariableIndexes.firstIndex + 1;
		
		NSIndexSet *indexesToInsert = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(currentIndex, variablesToInsertArray.count)];
		
		[self
		 addVariables:variablesToInsertArray
		 atRowIndexes:indexesToInsert];
	}
}

#pragma mark Adding & Removing Variables

- (void)clearSearchByFilteringForSearchVariables:(BOOL)shouldFilterForSearchVariables
{
	[[self.windowController.undoManager prepareWithInvocationTarget:self.windowController] updateVariables:self.windowController.documentData.variables searchResults:self.windowController.searchController.searchResults];
	
	NSArray *newVariables = nil;
	if (shouldFilterForSearchVariables)
	{
		newVariables = [self.documentData.variables zgFilterUsingBlock:(zg_array_filter_t)^(ZGVariable *variable) {
			return (variable.type == ZGScript || variable.isFrozen || !variable.enabled);
		}];
	}
	else
	{
		newVariables = [NSArray array];
	}
	
	self.windowController.documentData.variables = newVariables;
	self.windowController.searchController.searchResults = nil;
	
	self.windowController.runningApplicationsPopUpButton.enabled = YES;
	self.windowController.dataTypesPopUpButton.enabled = YES;
	
	if (self.windowController.currentProcess.valid)
	{
		[self.windowController updateNumberOfValuesDisplayedStatus];
	}
	
	[self.windowController markDocumentChange];
	
	[self.windowController.tableController.variablesTableView reloadData];
}

- (void)clear
{
	if ([self canClearSearch])
	{
		[self clearSearch];
	}
	else
	{
		[self clearSearchByFilteringForSearchVariables:NO];
	}
}

- (BOOL)canClearSearch
{
	return [self.documentData.variables zgHasObjectMatchingCondition:^(ZGVariable *variable) { return (BOOL)(variable.type != ZGScript && !variable.isFrozen && variable.enabled); }];
}

- (void)clearSearch
{
	[self clearSearchByFilteringForSearchVariables:YES];
}

- (void)removeVariablesAtRowIndexes:(NSIndexSet *)rowIndexes
{
	NSMutableArray *temporaryArray = [[NSMutableArray alloc] initWithCapacity:self.documentData.variables.count];
	
	if (self.windowController.undoManager.isUndoing)
	{
		self.windowController.undoManager.actionName = [NSString stringWithFormat:@"Add Variable%@", rowIndexes.count > 1 ? @"s" : @""];
	}
	else
	{
		self.windowController.undoManager.actionName = [NSString stringWithFormat:@"Delete Variable%@", rowIndexes.count > 1 ? @"s" : @""];
	}
	
	NSArray *variablesToRemove = [self.documentData.variables objectsAtIndexes:rowIndexes];
	
	[[self.windowController.undoManager prepareWithInvocationTarget:self]
	 addVariables:variablesToRemove
	 atRowIndexes:rowIndexes];
	
	for (ZGVariable *variable in variablesToRemove)
	{
		if (variable.enabled)
		{
			if (variable.type == ZGScript)
			{
				[self.windowController.scriptManager stopScriptForVariable:variable];
			}
			else if (variable.isFrozen)
			{
				// If the user undos this remove, the variable won't automatically rewrite values
				variable.isFrozen = NO;
			}
		}
	}
	
	[temporaryArray addObjectsFromArray:self.documentData.variables];
	[temporaryArray removeObjectsAtIndexes:rowIndexes];
	
	self.documentData.variables = [NSArray arrayWithArray:temporaryArray];
	[self.windowController.searchController fetchVariablesFromResults];
	
	[self updateFrozenActivity];
	[self.windowController.tableController updateWatchVariablesTimer];
	[self.windowController.tableController.variablesTableView reloadData];
}

- (void)disableHarmfulVariables:(NSArray *)variables
{
	for (ZGVariable *variable in variables)
	{
		if ((variable.type == ZGScript || variable.isFrozen) && variable.enabled)
		{
			variable.enabled = NO;
		}
	}
	
	[self updateFrozenActivity];
}

- (void)addVariables:(NSArray *)variables atRowIndexes:(NSIndexSet *)rowIndexes
{
	NSMutableArray *temporaryArray = [[NSMutableArray alloc] initWithArray:self.documentData.variables];
	[temporaryArray insertObjects:variables atIndexes:rowIndexes];
	
	[self disableHarmfulVariables:variables];
	
	self.documentData.variables = [NSArray arrayWithArray:temporaryArray];
	
	[self.windowController.tableController updateWatchVariablesTimer];
	[self.windowController.tableController.variablesTableView reloadData];
	
	if (self.windowController.undoManager.isUndoing)
	{
		self.windowController.undoManager.actionName = [NSString stringWithFormat:@"Delete Variable%@", rowIndexes.count > 1 ? @"s" : @""];
	}
	else
	{
		self.windowController.undoManager.actionName = [NSString stringWithFormat:@"Add Variable%@", rowIndexes.count > 1 ? @"s" : @""];
	}
	[[self.windowController.undoManager prepareWithInvocationTarget:self] removeVariablesAtRowIndexes:rowIndexes];
	
	[self.windowController updateNumberOfValuesDisplayedStatus];
}

- (void)removeSelectedSearchValues
{
	[self removeVariablesAtRowIndexes:self.windowController.selectedVariableIndexes];
	[self.windowController updateNumberOfValuesDisplayedStatus];
}

- (void)addVariable:(id)sender
{
	ZGVariableQualifier qualifier = (ZGVariableQualifier)self.documentData.qualifierTag;
	CFByteOrder byteOrder = self.documentData.byteOrderTag;
	ZGVariableType variableType = (ZGVariableType)[sender tag];
	
	// Try to get an initial address from the debugger or the memory viewer's selection
	ZGMemoryAddress initialAddress = self.lastSelectedMemoryRangeFromOutside.location;
	ZGMemorySize initialSize = self.lastSelectedMemoryRangeFromOutside.length;
	
	ZGVariable *variable =
		[[ZGVariable alloc]
		 initWithValue:NULL
		 size:initialSize
		 address:initialAddress
		 type:variableType
		 qualifier:qualifier
		 pointerSize:self.windowController.currentProcess.pointerSize
		 description:[[NSAttributedString alloc] initWithString:variableType == ZGScript ? @"My Script" : @""]
		 enabled:NO
		 byteOrder:byteOrder];
	
	if (variable.type == ZGScript)
	{
		BOOL usingTabs = [[NSUserDefaults standardUserDefaults] boolForKey:ZGScriptIndentationUsingTabsKey];
		NSUInteger spacesWidth = [[[NSUserDefaults standardUserDefaults] objectForKey:ZGScriptIndentationSpacesWidthKey] unsignedIntegerValue];
		NSString *indentationString =
		usingTabs ? @"\t" :
		[@"" stringByPaddingToLength:spacesWidth withString:@" " startingAtIndex:0]; // equivalent to " " * spacesWidth in a sane language
		
		NSString *scriptValue =
		@"#Edit Me!\n"
		@"#Introduction to scripting: https://github.com/zorgiepoo/Bit-Slicer/wiki/Introduction-to-Scripting\n"
		@"from bitslicer import VirtualMemoryError, DebuggerError\n\n"
		@"class Script(object):\n"
		@"`def __init__(self):\n"
		@"``debug.log('Initialization..')\n"
		@"`#def execute(self, deltaTime):\n"
		@"``#write some interesting code, or not\n"
		@"`def finish(self):\n"
		@"``debug.log('Cleaning up..')\n";
		
		variable.scriptValue = [scriptValue stringByReplacingOccurrencesOfString:@"`" withString:indentationString];
	}

	[self
	 addVariables:@[variable]
	 atRowIndexes:[NSIndexSet indexSetWithIndex:0]];
}

#pragma mark Changing Variables

- (BOOL)nopVariables:(NSArray *)variables withNewValues:(NSArray *)newValues
{
	BOOL completeSuccess = YES;
	
	NSMutableArray *oldValues = [[NSMutableArray alloc] init];
	for (ZGVariable *variable in variables)
	{
		[oldValues addObject:variable.stringValue];
	}
	
	for (NSUInteger variableIndex = 0; variableIndex < variables.count; variableIndex++)
	{
		ZGVariable *variable = [variables objectAtIndex:variableIndex];
		[self changeVariable:variable newValue:[newValues objectAtIndex:variableIndex] shouldRecordUndo:NO];
	}
	
	self.windowController.undoManager.actionName = @"NOP Change";
	[[self.windowController.undoManager prepareWithInvocationTarget:self]
	 nopVariables:variables
	 withNewValues:oldValues];
	
	return completeSuccess;
}

- (void)nopVariables:(NSArray *)variables
{
	NSMutableArray *nopValues = [[NSMutableArray alloc] init];
	
	for (ZGVariable *variable in variables)
	{
		NSMutableArray *nopComponents = [[NSMutableArray alloc] init];
		for (NSUInteger index = 0; index < variable.size; index++)
		{
			[nopComponents addObject:@"90"];
		}
		[nopValues addObject:[nopComponents componentsJoinedByString:@" "]];
	}
	
	if (![self nopVariables:variables withNewValues:nopValues])
	{
		NSRunAlertPanel(@"NOP Error", @"An error may have occured with nopping the instruction%@", nil, nil, nil, variables.count != 1 ? @"s" : @"");
	}
}

- (void)changeVariable:(ZGVariable *)variable newDescription:(NSAttributedString *)newDescription
{
	self.windowController.undoManager.actionName = @"Description Change";
	[[self.windowController.undoManager prepareWithInvocationTarget:self]
	 changeVariable:variable
	 newDescription:variable.fullAttributedDescription];
	
	variable.fullAttributedDescription = newDescription;
	
	if (self.windowController.undoManager.isUndoing || self.windowController.undoManager.isRedoing)
	{
		[self.windowController.tableController.variablesTableView reloadData];
	}
}

- (void)changeVariable:(ZGVariable *)variable newType:(ZGVariableType)type newSize:(ZGMemorySize)size
{
	self.windowController.undoManager.actionName = @"Type Change";
	[[self.windowController.undoManager prepareWithInvocationTarget:self]
	 changeVariable:variable
	 newType:variable.type
	 newSize:variable.size];
	
	[variable
	 setType:type
	 requestedSize:size
	 pointerSize:self.windowController.currentProcess.pointerSize];
	
	[self.windowController.tableController updateWatchVariablesTimer];
	[self.windowController.tableController.variablesTableView reloadData];
}

- (void)changeVariable:(ZGVariable *)variable newValue:(NSString *)stringObject shouldRecordUndo:(BOOL)recordUndoFlag
{	
	void *newValue = NULL;
	ZGMemorySize writeSize = variable.size; // specifically needed for byte arrays
	
	// It's important to retrieve this now instead of later as changing the variable's size may cause a bad side effect to this method
	NSString *oldStringValue = [variable.stringValue copy];
	
	int8_t *int8Value = malloc(sizeof(int8_t));
	int16_t *int16Value = malloc(sizeof(int16_t));
	int32_t *int32Value = malloc(sizeof(int32_t));
	int64_t *int64Value = malloc(sizeof(int64_t));
	float *floatValue = malloc(sizeof(float));
	double *doubleValue = malloc(sizeof(double));
	void *utf16Value = NULL;
	void *byteArrayValue = NULL;
	void *swappedValue = NULL;
	
	if (ZGIsNumericalDataType(variable.type))
	{
		stringObject = [ZGCalculator evaluateExpression:stringObject];
	}
	
	BOOL stringIsAHexRepresentation = stringObject.zgIsHexRepresentation;
	
	ZGVariableType variableType;
	if (variable.type == ZGPointer)
	{
		variableType = (variable.size == sizeof(int32_t)) ? ZGInt32 : ZGInt64;
	}
	else
	{
		variableType = variable.type;
	}
	
	switch (variableType)
	{
		case ZGInt8:
			if (stringIsAHexRepresentation)
			{
				[[NSScanner scannerWithString:stringObject] scanHexInt:(unsigned int *)int32Value];
				*int8Value = (int8_t)*int32Value;
			}
			else
			{
				*int8Value = (int8_t)stringObject.intValue;
			}
			
			newValue = int8Value;
			break;
		case ZGInt16:
			if (stringIsAHexRepresentation)
			{
				[[NSScanner scannerWithString:stringObject] scanHexInt:(unsigned int *)int32Value];
				*int16Value = (int16_t)*int32Value;
			}
			else
			{
				*int16Value = (int16_t)stringObject.intValue;
			}
			
			newValue = int16Value;
			break;
		case ZGInt32:
			if (stringIsAHexRepresentation)
			{
				[[NSScanner scannerWithString:stringObject] scanHexInt:(unsigned int *)int32Value];
			}
			else
			{
				*int32Value = stringObject.intValue;
			}
			
			newValue = int32Value;
			break;
		case ZGFloat:
			if (stringIsAHexRepresentation)
			{
				[[NSScanner scannerWithString:stringObject] scanHexFloat:floatValue];
			}
			else
			{
				*floatValue = stringObject.floatValue;
			}
			
			newValue = floatValue;
			break;
		case ZGInt64:
			if (stringIsAHexRepresentation)
			{
				[[NSScanner scannerWithString:stringObject] scanHexLongLong:(unsigned long long *)int64Value];
			}
			else
			{
				[[NSScanner scannerWithString:stringObject] scanLongLong:int64Value];
			}
			
			newValue = int64Value;
			break;
		case ZGDouble:
			if (stringIsAHexRepresentation)
			{
				[[NSScanner scannerWithString:stringObject] scanHexDouble:doubleValue];
			}
			else
			{
				*doubleValue = stringObject.doubleValue;
			}
			
			newValue = doubleValue;
			break;
		case ZGString8:
			newValue = (void *)[stringObject cStringUsingEncoding:NSUTF8StringEncoding];
			variable.size = strlen(newValue) + 1;
			writeSize = variable.size;
			break;
		case ZGString16:
			variable.size = [stringObject length] * sizeof(unichar);
			writeSize = variable.size;
			
			if (variable.size > 0)
			{
				utf16Value = malloc((size_t)variable.size);
				newValue = utf16Value;
				[stringObject
				 getCharacters:newValue
				 range:NSMakeRange(0, stringObject.length)];
			}
			else
			{
				// String "" can be of 0 length
				utf16Value = malloc(sizeof(unichar));
				newValue = utf16Value;
				
				if (newValue)
				{
					unichar nullTerminator = 0;
					memcpy(newValue, &nullTerminator, sizeof(unichar));
				}
			}
			
			break;
			
		case ZGByteArray:
		{
			NSArray *bytesArray = ZGByteArrayComponentsFromString(stringObject);
			
			if (variable.size != bytesArray.count)
			{
				// this is the size the user wants
				[self editVariables:@[variable] requestedSizes:@[@(bytesArray.count)]];
			}
			
			// Update old string value to be the same size as new string value, so that undo/redo's from one size to another will work more nicely
			void *oldData = NULL;
			ZGMemorySize oldSize = variable.size;
			
			if (ZGReadBytes(self.windowController.currentProcess.processTask, variable.address, &oldData, &oldSize))
			{
				ZGVariable *oldVariable = [[ZGVariable alloc] initWithValue:oldData size:oldSize address:variable.address type:ZGByteArray qualifier:variable.qualifier pointerSize:self.windowController.currentProcess.pointerSize description:variable.fullAttributedDescription enabled:variable.enabled byteOrder:variable.byteOrder];
				
				oldStringValue = oldVariable.stringValue;
				
				ZGFreeBytes(oldData, oldSize);
			}
			
			// this is the maximum size allocated needed
			byteArrayValue = malloc((size_t)variable.size);
			newValue = byteArrayValue;
			
			if (newValue != nil)
			{
				unsigned char *valuePtr = newValue;
				writeSize = 0;
				
				NSArray *oldComponents = ZGByteArrayComponentsFromString(oldStringValue);
				
				for (NSString *byteString in bytesArray)
				{
					// old string value will be same size as new string value so accessing this index is fine
					NSString *oldComponent = [oldComponents objectAtIndex:writeSize];
					
					unichar oldCharacters[2];
					[oldComponent getCharacters:oldCharacters];
					
					unichar newCharacters[2];
					[byteString getCharacters:newCharacters	];
					
					unichar replaceCharacters[2];
					replaceCharacters[0] = (newCharacters[0] == '?' || newCharacters[0] == '*') ? oldCharacters[0] : newCharacters[0];
					replaceCharacters[1] = (newCharacters[1] == '?' || newCharacters[1] == '*') ? oldCharacters[1] : newCharacters[1];
					
					unsigned int replaceValue = 0;
					[[NSScanner scannerWithString:[NSString stringWithCharacters:replaceCharacters length:2]] scanHexInt:&replaceValue];
					
					*valuePtr = (unsigned char)replaceValue;
					valuePtr++;
					
					if ([byteString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length == 0)
					{
						break;
					}
					
					writeSize++;
				}
			}
			else
			{
				variable.size = writeSize;
			}
			
			break;
		}
		case ZGPointer:
		case ZGScript:
			break;
	}
	
	if (newValue != nil)
	{
		if (variable.byteOrder != CFByteOrderGetCurrent())
		{
			swappedValue = ZGSwappedValue(self.windowController.currentProcess.is64Bit, newValue, variableType, writeSize);
			newValue = swappedValue;
		}
		
		if (variable.isFrozen)
		{
			variable.freezeValue = newValue;
			
			if (recordUndoFlag)
			{
				self.windowController.undoManager.actionName = @"Freeze Value Change";
				[[self.windowController.undoManager prepareWithInvocationTarget:self]
				 changeVariable:variable
				 newValue:variable.stringValue
				 shouldRecordUndo:YES];
				
				if (self.windowController.undoManager.isUndoing || self.windowController.undoManager.isRedoing)
				{
					[self.windowController.tableController.variablesTableView reloadData];
				}
			}
		}
		else
		{
			BOOL successfulWrite = YES;
			
			if (writeSize)
			{
				if (!ZGWriteBytesIgnoringProtection(self.windowController.currentProcess.processTask, variable.address, newValue, writeSize))
				{
					successfulWrite = NO;
				}
			}
			else
			{
				successfulWrite = NO;
			}
			
			if (successfulWrite && variableType == ZGString16)
			{
				// Don't forget to write the null terminator
				unichar nullTerminator = 0;
				if (!ZGWriteBytesIgnoringProtection(self.windowController.currentProcess.processTask, variable.address + writeSize, &nullTerminator, sizeof(unichar)))
				{
					successfulWrite = NO;
				}
			}
			
			if (successfulWrite && recordUndoFlag)
			{
				self.windowController.undoManager.actionName = @"Value Change";
				[[self.windowController.undoManager prepareWithInvocationTarget:self]
				 changeVariable:variable
				 newValue:oldStringValue
				 shouldRecordUndo:YES];
				
				if (self.windowController.undoManager.isUndoing || self.windowController.undoManager.isRedoing)
				{
					[self.windowController.tableController.variablesTableView reloadData];
				}
			}
		}
	}
	
	free(int8Value);
	free(int16Value);
	free(int32Value);
	free(int64Value);
	free(floatValue);
	free(doubleValue);
	free(utf16Value);
	free(byteArrayValue);
	free(swappedValue);
}

- (void)changeVariableEnabled:(BOOL)enabled rowIndexes:(NSIndexSet *)rowIndexes
{
	NSMutableIndexSet *undoableRowIndexes = [[NSMutableIndexSet alloc] init];
	NSUInteger currentIndex = rowIndexes.firstIndex;
	
	while (currentIndex != NSNotFound)
	{
		ZGVariable *variable = [self.documentData.variables objectAtIndex:currentIndex];
		variable.enabled = enabled;
		if (variable.type == ZGScript)
		{
			if (variable.enabled)
			{
				[self.windowController.scriptManager runScriptForVariable:variable];
			}
			else
			{
				[self.windowController.scriptManager stopScriptForVariable:variable];
			}
		}
		else
		{
			[undoableRowIndexes addIndex:currentIndex];
		}
		
		currentIndex = [rowIndexes indexGreaterThanIndex:currentIndex];
	}
	
	if (!self.windowController.undoManager.isUndoing && !self.windowController.undoManager.isRedoing && undoableRowIndexes.count > 1)
	{
		self.windowController.variablesTableView.shouldIgnoreNextSelection = YES;
	}
	
	[self updateFrozenActivity];
	
	// the table view always needs to be reloaded because of being able to select multiple indexes
	[self.windowController.tableController.variablesTableView reloadData];
	
	if (undoableRowIndexes.count > 0)
	{
		self.windowController.undoManager.actionName = [NSString stringWithFormat:@"Enabled Variable%@ Change", (rowIndexes.count > 1) ? @"s" : @""];
		[[self.windowController.undoManager prepareWithInvocationTarget:self]
		 changeVariableEnabled:!enabled
		 rowIndexes:undoableRowIndexes];
	}
}

#pragma mark Edit Variables Values

- (void)editVariables:(NSArray *)variables newValues:(NSArray *)newValues
{
	NSMutableArray *oldValues = [[NSMutableArray alloc] init];
	
	[variables enumerateObjectsUsingBlock:^(ZGVariable *variable, NSUInteger index, BOOL * __unused stop) {
		[oldValues addObject:variable.stringValue];
		 
		 [self
		  changeVariable:variable
		  newValue:[newValues objectAtIndex:index]
		  shouldRecordUndo:NO];
	 }];
	
	[self.windowController.tableController.variablesTableView reloadData];
	
	self.windowController.undoManager.actionName = @"Edit Variables";
	[[self.windowController.undoManager prepareWithInvocationTarget:self]
	 editVariables:variables
	 newValues:oldValues];
}

#pragma mark Edit Variables Address

- (void)editVariable:(ZGVariable *)variable addressFormula:(NSString *)newAddressFormula
{
	self.windowController.undoManager.actionName = @"Address Change";
	[[self.windowController.undoManager prepareWithInvocationTarget:self]
	 editVariable:variable
	 addressFormula:variable.addressFormula];
	
	variable.addressFormula = newAddressFormula;
	if (variable.usesDynamicPointerAddress || variable.usesDynamicBaseAddress)
	{
		variable.usesDynamicAddress = YES;
	}
	else
	{
		variable.usesDynamicAddress = NO;
		variable.addressStringValue = [ZGCalculator evaluateExpression:newAddressFormula];
		[self.windowController.tableController.variablesTableView reloadData];
	}
	variable.finishedEvaluatingDynamicAddress = NO;
}

#pragma mark Relativizing Variable Addresses

- (void)unrelativizeVariables:(NSArray *)variables
{
	for (ZGVariable *variable in variables)
	{
		variable.addressFormula = variable.addressStringValue;
		variable.usesDynamicAddress = NO;
	}
	
	self.windowController.undoManager.actionName = [NSString stringWithFormat:@"Unrelativize Variable%@", variables.count == 1 ? @"" : @"s"];
	[[self.windowController.undoManager prepareWithInvocationTarget:self] relativizeVariables:variables];
}

- (void)relativizeVariables:(NSArray *)variables
{
	[[self class] annotateVariables:variables process:self.windowController.currentProcess];
	
	self.windowController.undoManager.actionName = [NSString stringWithFormat:@"Relativize Variable%@", variables.count == 1 ? @"" : @"s"];
	[[self.windowController.undoManager prepareWithInvocationTarget:self] unrelativizeVariables:variables];
}

+ (NSString *)relativizeVariable:(ZGVariable * __unsafe_unretained)variable withMachBinaries:(NSArray *)machBinaries filePathDictionary:(NSDictionary *)machFilePathDictionary process:(ZGProcess *)process
{
	NSString *staticVariableDescription = nil;
	
	ZGMachBinary *machBinary = [ZGMachBinary machBinaryNearestToAddress:variable.address fromMachBinaries:machBinaries];
	
	NSString *machFilePath = [machFilePathDictionary objectForKey:@(machBinary.filePathAddress)];
	
	if (machFilePath != nil)
	{
		ZGMachBinaryInfo *machBinaryInfo = [machBinary machBinaryInfoInProcess:process];
		NSString *segmentName = [machBinaryInfo segmentNameAtAddress:variable.address];
		
		if (segmentName != nil)
		{
			NSString *partialPath = [machFilePath lastPathComponent];
			if (machBinaryInfo.slide > 0)
			{
				NSString *pathToUse = nil;
				NSString *baseArgument = @"";
				
				if (machBinary != [machBinaries objectAtIndex:0])
				{
					if ([[machFilePath stringByDeletingLastPathComponent] length] > 0)
					{
						partialPath = [@"/" stringByAppendingString:partialPath];
					}
					
					int numberOfMatchingPaths = 0;
					for (ZGMachBinary *binaryImage in machBinaries)
					{
						NSString *mappedPath = [machFilePathDictionary objectForKey:@(binaryImage.filePathAddress)];
						if ([mappedPath hasSuffix:partialPath])
						{
							numberOfMatchingPaths++;
							if (numberOfMatchingPaths > 1) break;
						}
					}
					
					pathToUse = numberOfMatchingPaths > 1 ? machFilePath : partialPath;
					baseArgument = [NSString stringWithFormat:@"\"%@\"", pathToUse];
				}
				
				variable.addressFormula = [NSString stringWithFormat:ZGBaseAddressFunction@"(%@) + 0x%llX", baseArgument, variable.address - machBinary.headerAddress];
				variable.usesDynamicAddress = YES;
				variable.finishedEvaluatingDynamicAddress = YES;
			}
			
			staticVariableDescription = [NSString stringWithFormat:@"%@ %@ (static)", partialPath, segmentName];
		}
	}
	
	return staticVariableDescription;
}

+ (void)annotateVariables:(NSArray *)variables process:(ZGProcess *)process
{
	ZGMemoryMap processTask = process.processTask;
	NSArray *machBinaries = [ZGMachBinary machBinariesInProcess:process];
	NSMutableDictionary *machFilePathDictionary = [[NSMutableDictionary alloc] init];
	
	for (ZGMachBinary *machBinary in machBinaries)
	{
		NSString *filePath = [machBinary filePathInProcess:process];
		if (filePath != nil)
		{
			[machFilePathDictionary setObject:filePath forKey:@(machBinary.filePathAddress)];
		}
	}
	
	ZGMemoryAddress cachedSubmapRegionAddress = 0;
	ZGMemorySize cachedSubmapRegionSize = 0;
	ZGMemorySubmapInfo cachedSubmapInfo;
	
	for (ZGVariable *variable in variables)
	{
		NSString *staticDescription = [self relativizeVariable:variable withMachBinaries:machBinaries filePathDictionary:machFilePathDictionary process:process];
		
		NSString *symbol = [process symbolAtAddress:variable.address relativeOffset:NULL];

		if (cachedSubmapRegionAddress >= variable.address + variable.size || cachedSubmapRegionAddress + cachedSubmapRegionSize <= variable.address)
		{
			cachedSubmapRegionAddress = variable.address;
			if (!ZGRegionSubmapInfo(processTask, &cachedSubmapRegionAddress, &cachedSubmapRegionSize, &cachedSubmapInfo))
			{
				cachedSubmapRegionAddress = 0;
				cachedSubmapRegionSize = 0;
			}
		}
		
		NSString *userTagDescription = nil;
		NSString *protectionDescription = nil;
		
		if (cachedSubmapRegionAddress <= variable.address && cachedSubmapRegionAddress + cachedSubmapRegionSize >= variable.address + variable.size)
		{
			userTagDescription = ZGUserTagDescription(cachedSubmapInfo.user_tag);
			protectionDescription = ZGProtectionDescription(cachedSubmapInfo.protection);
		}
		
		NSMutableArray *validDescriptionComponents = [NSMutableArray array];
		if (symbol.length > 0) [validDescriptionComponents addObject:symbol];
		if (staticDescription != nil) [validDescriptionComponents addObject:staticDescription];
		if (userTagDescription != nil) [validDescriptionComponents addObject:userTagDescription];
		if (protectionDescription != nil) [validDescriptionComponents addObject:protectionDescription];
		
		if (variable.fullAttributedDescription.length == 0)
		{
			variable.fullAttributedDescription = [[NSAttributedString alloc] initWithString:[validDescriptionComponents componentsJoinedByString:@", "]];
		}
		else
		{
			NSString *appendedString = [NSString stringWithFormat:@"\n\n%@", [validDescriptionComponents componentsJoinedByString:@"\n"]];
			NSMutableAttributedString *newDescription = [variable.fullAttributedDescription mutableCopy];
			[newDescription appendAttributedString:[[NSAttributedString alloc] initWithString:appendedString]];
			variable.fullAttributedDescription = newDescription;
		}
	}
}

#pragma mark Edit Variables Sizes (Byte Arrays)

- (void)editVariables:(NSArray *)variables requestedSizes:(NSArray *)requestedSizes
{
	NSMutableArray *currentVariableSizes = [[NSMutableArray alloc] init];
	NSMutableArray *validVariables = [[NSMutableArray alloc] init];
	
	// Make sure the size changes are possible. Only change the ones that seem possible.
	[variables enumerateObjectsUsingBlock:^(ZGVariable *variable, NSUInteger index, BOOL * __unused stop)
	 {
		 ZGMemorySize size = [[requestedSizes objectAtIndex:index] unsignedLongLongValue];
		 void *buffer = NULL;
		 
		 if (ZGReadBytes(self.windowController.currentProcess.processTask, variable.address, &buffer, &size))
		 {
			 if (size == [[requestedSizes objectAtIndex:index] unsignedLongLongValue])
			 {
				 [validVariables addObject:variable];
				 [currentVariableSizes addObject:@(variable.size)];
			 }
			 
			 ZGFreeBytes(buffer, size);
		 }
	 }];
	
	if (validVariables.count > 0)
	{
		self.windowController.undoManager.actionName = @"Size Change";
		[[self.windowController.undoManager prepareWithInvocationTarget:self]
		 editVariables:validVariables
		 requestedSizes:currentVariableSizes];
		
		[validVariables enumerateObjectsUsingBlock:^(ZGVariable *variable, NSUInteger index, BOOL * __unused stop)
		 {
			 variable.size = [[requestedSizes objectAtIndex:index] unsignedLongLongValue];
		 }];
		
		[self.windowController.tableController.variablesTableView reloadData];
	}
	else
	{
		NSRunAlertPanel(@"Failed to change size", @"The size that you have requested could not be changed. Perhaps it is too big of a value?", nil, nil, nil);
	}
}

@end
