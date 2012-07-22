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

#import <Foundation/Foundation.h>
#import "ZGMemoryTypes.h"
#import "ZGVariable.h"

#define SIGNED_BUTTON_CELL_TAG 0

@class ZGDocument;

@interface ZGVariableController : NSObject
{
	IBOutlet ZGDocument *document;
	
	IBOutlet NSWindow *editVariablesValueWindow;
	IBOutlet NSTextField *editVariablesValueTextField;
	IBOutlet NSWindow *editVariablesAddressWindow;
	IBOutlet NSTextField *editVariablesAddressTextField;
	IBOutlet NSWindow *editVariablesSizeWindow;
	IBOutlet NSTextField *editVariablesSizeTextField;
}

- (void)freezeVariables;

- (void)copyVariables;
- (void)pasteVariables;

- (void)removeSelectedSearchValues;
- (void)addVariable:(id)sender;

- (void)changeVariable:(ZGVariable *)variable newName:(NSString *)newName;
- (void)changeVariable:(ZGVariable *)variable newAddress:(NSString *)newAddress;
- (void)changeVariable:(ZGVariable *)variable newType:(ZGVariableType)type newSize:(ZGMemorySize)size;
- (void)changeVariable:(ZGVariable *)variable newValue:(NSString *)stringObject shouldRecordUndo:(BOOL)recordUndoFlag;
- (void)changeVariableShouldBeSearched:(BOOL)shouldBeSearched rowIndexes:(NSIndexSet *)rowIndexes;

- (IBAction)editVariablesValueCancelButton:(id)sender;
- (IBAction)editVariablesValueOkayButton:(id)sender;
- (void)editVariablesValueRequest;

- (IBAction)editVariablesAddressCancelButton:(id)sender;
- (IBAction)editVariablesAddressOkayButton:(id)sender;
- (void)editVariablesAddressRequest;

- (IBAction)editVariablesSizeCancelButton:(id)sender;
- (IBAction)editVariablesSizeOkayButton:(id)sender;
- (void)editVariablesSizeRequest;

@end
