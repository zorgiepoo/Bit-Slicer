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
 * Created by Mayur Pawashe on 5/13/11
 * Copyright 2011 zgcoder. All rights reserved.
 */

#import <Foundation/Foundation.h>
@class MyDocument;

@interface ZGAdditionalTasksController : NSObject
{
	// MyDocument outlets
	IBOutlet MyDocument *document;
	IBOutlet NSWindow *watchWindow;
	IBOutlet NSProgressIndicator *searchingProgressIndicator;
	IBOutlet NSTextField *generalStatusTextField;
	
	// Memory Dumps
	IBOutlet NSWindow *memoryDumpWindow;
	IBOutlet NSTextField *memoryDumpFromAddressTextField;
	IBOutlet NSTextField *memoryDumpToAddressTextField;
	
	// Memory Protection
	IBOutlet NSWindow *changeProtectionWindow;
	IBOutlet NSTextField *changeProtectionAddressTextField;
	IBOutlet NSTextField *changeProtectionSizeTextField;
	IBOutlet NSButton *changeProtectionReadButton;
	IBOutlet NSButton *changeProtectionWriteButton;
	IBOutlet NSButton *changeProtectionExecuteButton;
}

- (IBAction)memoryDumpOkayButton:(id)sender;
- (IBAction)memoryDumpCancelButton:(id)sender;

- (void)memoryDumpRequest;
- (void)memoryDumpAllRequest;

- (IBAction)changeProtectionOkayButton:(id)sender;
- (IBAction)changeProtectionCancelButton:(id)sender;

- (void)changeMemoryProtectionRequest;

@end
