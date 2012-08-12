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
 * Created by Mayur Pawashe on 7/19/12.
 * Copyright 2012 zgcoder. All rights reserved.
 */

#import "ZGMemoryDumpController.h"
#import "ZGDocument.h"
#import "ZGProcess.h"
#import "ZGCalculator.h"
#import "ZGMemoryTypes.h"
#import "ZGUtilities.h"
#import "ZGVirtualMemory.h"
#import "ZGDocumentSearchController.h"

@interface ZGMemoryDumpController ()

@property (assign) IBOutlet ZGDocument *document;
@property (assign) IBOutlet NSWindow *memoryDumpWindow;
@property (assign) IBOutlet NSTextField *memoryDumpFromAddressTextField;
@property (assign) IBOutlet NSTextField *memoryDumpToAddressTextField;

@property (readwrite, retain, nonatomic) NSTimer *progressTimer;

@end

@implementation ZGMemoryDumpController

#pragma mark Death

- (void)cleanUp
{
	[self.progressTimer invalidate];
	self.progressTimer = nil;
	
	self.document = nil;
	self.memoryDumpWindow = nil;
	self.memoryDumpFromAddressTextField = nil;
	self.memoryDumpToAddressTextField = nil;
}

#pragma mark Memory Dump in Range

- (IBAction)memoryDumpOkayButton:(id)sender
{
	NSString *fromAddressExpression = [ZGCalculator evaluateExpression:self.memoryDumpFromAddressTextField.stringValue];
	ZGMemoryAddress fromAddress = memoryAddressFromExpression(fromAddressExpression);
	
	NSString *toAddressExpression = [ZGCalculator evaluateExpression:self.memoryDumpToAddressTextField.stringValue];
	ZGMemoryAddress toAddress = memoryAddressFromExpression(toAddressExpression);
	
	if (toAddress > fromAddress && ![fromAddressExpression isEqualToString:@""] && ![toAddressExpression isEqualToString:@""])
	{
		[NSApp endSheet:self.memoryDumpWindow];
		[self.memoryDumpWindow close];
		
		NSSavePanel *savePanel = NSSavePanel.savePanel;
		[savePanel
		 beginSheetModalForWindow:self.document.watchWindow
		 completionHandler:^(NSInteger result)
		 {
			 if (result == NSFileHandlingPanelOKButton)
			 {
				 BOOL success = YES;
				 
				 @try
				 {
					 ZGMemorySize size = toAddress - fromAddress;
					 void *bytes = NULL;
					 
					 if (ZGReadBytes(self.document.currentProcess.processTask, fromAddress, &bytes, &size))
					 {
						 NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)size];
						 success = [data writeToURL:savePanel.URL atomically:NO];
						 
						 ZGFreeBytes(self.document.currentProcess.processTask, bytes, size);
					 }
					 else
					 {
						 NSLog(@"Failed to read region");
						 success = NO;
					 }
				 }
				 @catch (NSException *exception)
				 {
					 NSLog(@"Failed to write data");
					 success = NO;
				 }
				 @finally
				 {
					 if (!success)
					 {
						 NSRunAlertPanel(
										 @"The Memory Dump failed",
										 @"An error resulted in writing the memory dump.",
										 @"OK", nil, nil);
					 }
				 }
			 }
		 }];
	}
	else
	{
		NSRunAlertPanel(
						@"Invalid range",
						@"Please make sure you typed in the addresses correctly.",
						@"OK", nil, nil);
	}
}

- (IBAction)memoryDumpCancelButton:(id)sender
{
	[NSApp endSheet:self.memoryDumpWindow];
	[self.memoryDumpWindow close];
}

- (void)memoryDumpRangeRequest
{
	// guess what the user may want if nothing is in the text fields
	NSArray *selectedVariables = self.document.selectedVariables;
	if (selectedVariables && [self.memoryDumpFromAddressTextField.stringValue isEqualToString:@""] && [self.memoryDumpToAddressTextField.stringValue isEqualToString:@""])
	{
		ZGVariable *firstVariable = [selectedVariables objectAtIndex:0];
		ZGVariable *lastVariable = [selectedVariables lastObject];
		
		self.memoryDumpFromAddressTextField.stringValue = firstVariable.addressStringValue;
		
		if (firstVariable != lastVariable)
		{
			self.memoryDumpToAddressTextField.stringValue = lastVariable.addressStringValue;
		}
	}
	
	[NSApp
	 beginSheet:self.memoryDumpWindow
	 modalForWindow:self.document.watchWindow
	 modalDelegate:self
	 didEndSelector:nil
	 contextInfo:NULL];
}

#pragma mark Memory Dump All

- (void)updateMemoryDumpProgress:(NSTimer *)timer
{
	if (self.document.searchController.canStartTask)
	{
		[self.document.searchController prepareTask];
	}
	
	self.document.searchingProgressIndicator.doubleValue = self.document.currentProcess.searchProgress;
}

- (void)memoryDumpAllRequest
{
	NSSavePanel *savePanel = NSSavePanel.savePanel;
	savePanel.message = @"Choose a folder name to save the memory dump files. This may take a while.";
	
	[savePanel
	 beginSheetModalForWindow:self.document.watchWindow
	 completionHandler:^(NSInteger result)
	 {
		 if (result == NSFileHandlingPanelOKButton)
		 {
			 if ([NSFileManager.defaultManager fileExistsAtPath:savePanel.URL.relativePath])
			 {
				 [NSFileManager.defaultManager
				  removeItemAtPath:savePanel.URL.relativePath
				  error:NULL];
			 }
			 
			 [NSFileManager.defaultManager
			  createDirectoryAtPath:savePanel.URL.relativePath
			  withIntermediateDirectories:NO
			  attributes:nil
			  error:NULL];
			 
			 self.document.searchingProgressIndicator.maxValue = self.document.currentProcess.numberOfRegions;
			 
			 self.progressTimer =
				[NSTimer
				 scheduledTimerWithTimeInterval:USER_INTERFACE_UPDATE_TIME_INTERVAL
				 target:self
				 selector:@selector(updateMemoryDumpProgress:)
				 userInfo:nil
				 repeats:YES];
			 
			 //not doing this here, there's a bug with setKeyEquivalent, instead i'm going to do this in the timer
			 //[self.document.searchController prepareTask];
			 self.document.generalStatusTextField.stringValue = @"Writing Memory Dump...";
			 
			 dispatch_block_t searchForDataCompleteBlock = ^
			 {
				 [self.progressTimer invalidate];
				 self.progressTimer = nil;
				 
				 if (!self.document.currentProcess.isDoingMemoryDump)
				 {
					 self.document.generalStatusTextField.stringValue = @"Canceled Memory Dump";
				 }
				 else
				 {
					 self.document.currentProcess.isDoingMemoryDump = NO;
					 self.document.generalStatusTextField.stringValue = @"Finished Memory Dump";
				 }
				 self.document.searchingProgressIndicator.doubleValue = 0.0;
				 [self.document.searchController resumeFromTask];
			 };
			 
			 dispatch_block_t searchForDataBlock = ^
			 {
				 if (!ZGSaveAllDataToDirectory(savePanel.URL.relativePath, self.document.currentProcess))
				 {
					 NSRunAlertPanel(
									 @"The Memory Dump failed",
									 @"An error resulted in writing the memory dump.",
									 @"OK", nil, nil);
				 }
				 
				 dispatch_async(dispatch_get_main_queue(), searchForDataCompleteBlock);
			 };
			 
			 dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), searchForDataBlock);
		 }
	 }];
}

@end
