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
#import "MyDocument.h"
#import "ZGProcess.h"
#import "ZGCalculator.h"
#import "ZGMemoryTypes.h"
#import "ZGUtilities.h"
#import "ZGVirtualMemory.h"

@implementation ZGMemoryDumpController

#pragma mark Memory Dump in Range

- (IBAction)memoryDumpOkayButton:(id)sender
{
	NSString *fromAddressExpression = [ZGCalculator evaluateExpression:[memoryDumpFromAddressTextField stringValue]];
	ZGMemoryAddress fromAddress = memoryAddressFromExpression(fromAddressExpression);
	
	NSString *toAddressExpression = [ZGCalculator evaluateExpression:[memoryDumpToAddressTextField stringValue]];
	ZGMemoryAddress toAddress = memoryAddressFromExpression(toAddressExpression);
	
	if (toAddress > fromAddress && ![fromAddressExpression isEqualToString:@""] && ![toAddressExpression isEqualToString:@""])
	{
		[NSApp endSheet:memoryDumpWindow];
		[memoryDumpWindow close];
		
		NSSavePanel *savePanel = [NSSavePanel savePanel];
		[savePanel
		 beginSheetModalForWindow:[document watchWindow]
		 completionHandler:^(NSInteger result)
		 {
			 if (result == NSFileHandlingPanelOKButton)
			 {
				 BOOL success = YES;
				 
				 @try
				 {
					 ZGMemorySize size = toAddress - fromAddress;
					 void *bytes = NULL;
					 
					 if (ZGReadBytes([[document currentProcess] processTask], fromAddress, &bytes, &size))
					 {
						 NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)size];
						 success = [data writeToURL:[savePanel URL] atomically:NO];
						 
						 ZGFreeBytes([[document currentProcess] processTask], bytes, size);
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
	[NSApp endSheet:memoryDumpWindow];
	[memoryDumpWindow close];
}

- (void)memoryDumpRangeRequest
{
	// guess what the user may want if nothing is in the text fields
	NSArray *selectedVariables = [document selectedVariables];
	if (selectedVariables && [[memoryDumpFromAddressTextField stringValue] isEqualToString:@""] && [[memoryDumpToAddressTextField stringValue] isEqualToString:@""])
	{
		ZGVariable *firstVariable = [selectedVariables objectAtIndex:0];
		ZGVariable *lastVariable = [selectedVariables lastObject];
		
		[memoryDumpFromAddressTextField setStringValue:[firstVariable addressStringValue]];
		
		if (firstVariable != lastVariable)
		{
			[memoryDumpToAddressTextField setStringValue:[lastVariable addressStringValue]];
		}
	}
	
	[NSApp
	 beginSheet:memoryDumpWindow
	 modalForWindow:[document watchWindow]
	 modalDelegate:self
	 didEndSelector:nil
	 contextInfo:NULL];
}

#pragma mark Memory Dump All

- (void)updateMemoryDumpProgress:(NSTimer *)timer
{
	if ([document canStartTask])
	{
		[document prepareDocumentTask];
	}
	
	[[document searchingProgressIndicator] setDoubleValue:[document currentProcess]->searchProgress];
}

- (void)memoryDumpAllRequest
{
	NSSavePanel *savePanel = [NSSavePanel savePanel];
	[savePanel setMessage:@"Choose a folder name to save the memory dump files. This may take a while."];
	
	[savePanel
	 beginSheetModalForWindow:[document watchWindow]
	 completionHandler:^(NSInteger result)
	 {
		 if (result == NSFileHandlingPanelOKButton)
		 {
			 if ([[NSFileManager defaultManager] fileExistsAtPath:[[savePanel URL] relativePath]])
			 {
				 [[NSFileManager defaultManager]
				  removeItemAtPath:[[savePanel URL] relativePath]
				  error:NULL];
			 }
			 
			 // Since Bit Slicer is running as root, we'll need to pass attributes dictionary so that
			 // the folder is owned by the user
			 [[NSFileManager defaultManager]
			  createDirectoryAtPath:[[savePanel URL] relativePath]
			  withIntermediateDirectories:NO
			  attributes:[NSDictionary dictionaryWithObjectsAndKeys:NSUserName(), NSFileGroupOwnerAccountName, NSUserName(), NSFileOwnerAccountName, nil]
			  error:NULL];
			 
			 [[document searchingProgressIndicator] setMaxValue:[[document currentProcess] numberOfRegions]];
			 
			 NSTimer *progressTimer =
			 [[NSTimer
			   scheduledTimerWithTimeInterval:USER_INTERFACE_UPDATE_TIME_INTERVAL
			   target:self
			   selector:@selector(updateMemoryDumpProgress:)
			   userInfo:nil
			   repeats:YES] retain];
			 
			 //not doing this here, there's a bug with setKeyEquivalent, instead i'm going to do this in the timer
			 //[document prepareDocumentTask];
			 [[document generalStatusTextField] setStringValue:@"Writing Memory Dump..."];
			 
			 dispatch_block_t searchForDataCompleteBlock = ^
			 {
				 [progressTimer invalidate];
				 [progressTimer release];
				 
				 if (!([document currentProcess]->isDoingMemoryDump))
				 {
					 [[document generalStatusTextField] setStringValue:@"Canceled Memory Dump"];
				 }
				 else
				 {
					 [document currentProcess]->isDoingMemoryDump = NO;
					 [[document generalStatusTextField] setStringValue:@"Finished Memory Dump"];
				 }
				 [[document searchingProgressIndicator] setDoubleValue:0.0];
				 [document resumeDocument];
			 };
			 
			 dispatch_block_t searchForDataBlock = ^
			 {
				 if (!ZGSaveAllDataToDirectory([[savePanel URL] relativePath], [document currentProcess]))
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
