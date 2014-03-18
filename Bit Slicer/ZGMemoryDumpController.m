/*
 * Created by Mayur Pawashe on 7/19/12.
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

#import "ZGMemoryDumpController.h"
#import "ZGMemoryViewerController.h"
#import "ZGMemoryDumpFunctions.h"
#import "ZGProcess.h"
#import "ZGCalculator.h"
#import "ZGMemoryTypes.h"
#import "ZGUtilities.h"
#import "ZGVirtualMemory.h"
#import "ZGSearchProgress.h"

@interface ZGMemoryDumpController ()

@property (assign, nonatomic) IBOutlet ZGMemoryViewerController *memoryViewer;

@property (nonatomic, assign) IBOutlet NSWindow *memoryDumpWindow;
@property (nonatomic, assign) IBOutlet NSTextField *memoryDumpFromAddressTextField;
@property (nonatomic, assign) IBOutlet NSTextField *memoryDumpToAddressTextField;

@property (nonatomic, assign) IBOutlet NSWindow *memoryDumpProgressWindow;
@property (nonatomic, assign) IBOutlet NSButton *memoryDumpProgressCancelButton;

@property (nonatomic, assign) IBOutlet NSProgressIndicator *progressIndicator;

@property (nonatomic) ZGSearchProgress *searchProgress;
@property (nonatomic) BOOL isBusy;

@end

@implementation ZGMemoryDumpController

#pragma mark Memory Dump in Range

- (IBAction)memoryDumpOkayButton:(id)__unused sender
{
	NSString *fromAddressExpression = [ZGCalculator evaluateExpression:self.memoryDumpFromAddressTextField.stringValue];
	ZGMemoryAddress fromAddress = ZGMemoryAddressFromExpression(fromAddressExpression);
	
	NSString *toAddressExpression = [ZGCalculator evaluateExpression:self.memoryDumpToAddressTextField.stringValue];
	ZGMemoryAddress toAddress = ZGMemoryAddressFromExpression(toAddressExpression);
	
	if (toAddress > fromAddress && ![fromAddressExpression isEqualToString:@""] && ![toAddressExpression isEqualToString:@""])
	{
		[NSApp endSheet:self.memoryDumpWindow];
		[self.memoryDumpWindow close];
		
		NSSavePanel *savePanel = NSSavePanel.savePanel;
		[savePanel
		 beginSheetModalForWindow:self.memoryViewer.window
		 completionHandler:^(NSInteger result)
		 {
			 if (result == NSFileHandlingPanelOKButton)
			 {
				 BOOL success = NO;
				 ZGMemorySize size = toAddress - fromAddress;
				 void *bytes = NULL;
				 
				 if ((success = ZGReadBytes(self.memoryViewer.currentProcess.processTask, fromAddress, &bytes, &size)))
				 {
					 NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)size];
					 success = [data writeToURL:savePanel.URL atomically:NO];
					 
					 ZGFreeBytes(bytes, size);
				 }
				 else
				 {
					 NSLog(@"Failed to read region");
				 }
				 
				 if (!success)
				 {
					 NSRunAlertPanel(
									 @"The Memory Dump failed",
									 @"An error resulted in writing the memory dump.",
									 @"OK", nil, nil);
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

- (IBAction)memoryDumpCancelButton:(id)__unused sender
{
	[NSApp endSheet:self.memoryDumpWindow];
	[self.memoryDumpWindow close];
}

- (void)memoryDumpRangeRequest
{
	// guess what the user may want if nothing is in the text fields
	HFRange selectedRange = self.memoryViewer.selectedAddressRange;
	if (selectedRange.length > 0)
	{
		self.memoryDumpFromAddressTextField.stringValue = [NSString stringWithFormat:@"0x%llX", selectedRange.location];
		self.memoryDumpToAddressTextField.stringValue = [NSString stringWithFormat:@"0x%llX", selectedRange.location + selectedRange.length];
	}
	else
	{
		self.memoryDumpFromAddressTextField.stringValue = [NSString stringWithFormat:@"0x%llX", self.memoryViewer.currentMemoryAddress];
		self.memoryDumpToAddressTextField.stringValue = [NSString stringWithFormat:@"0x%llX", self.memoryViewer.currentMemoryAddress + self.memoryViewer.currentMemorySize];
	}
	
	[NSApp
	 beginSheet:self.memoryDumpWindow
	 modalForWindow:self.memoryViewer.window
	 modalDelegate:self
	 didEndSelector:nil
	 contextInfo:NULL];
}

#pragma mark Memory Dump All

- (void)memoryDumpAllRequest
{
	NSSavePanel *savePanel = NSSavePanel.savePanel;
	savePanel.message = @"Choose a folder name to save the memory dump files to.";
	
	[savePanel
	 beginSheetModalForWindow:self.memoryViewer.window
	 completionHandler:^(NSInteger result)
	 {
		 if (result == NSFileHandlingPanelOKButton)
		 {
			 dispatch_async(dispatch_get_main_queue(), ^{
				 NSFileManager *fileManager = [[NSFileManager alloc] init];
				 
				 if ([fileManager fileExistsAtPath:savePanel.URL.relativePath])
				 {
					 [fileManager
					  removeItemAtPath:savePanel.URL.relativePath
					  error:NULL];
				 }
				 
				 [fileManager
				  createDirectoryAtPath:savePanel.URL.relativePath
				  withIntermediateDirectories:NO
				  attributes:nil
				  error:NULL];
				 
				 [NSApp
				  beginSheet:self.memoryDumpProgressWindow
				  modalForWindow:self.memoryViewer.window
				  modalDelegate:self
				  didEndSelector:nil
				  contextInfo:NULL];
				 
				 [self.memoryDumpProgressCancelButton setEnabled:YES];
				 
				 self.isBusy = YES;
				 
				 id dumpMemoryActivity = nil;
				 if ([[NSProcessInfo processInfo] respondsToSelector:@selector(beginActivityWithOptions:reason:)])
				 {
					 dumpMemoryActivity = [[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiated reason:@"Dumping All Memory"];
				 }
				 
				 dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
					 if (!ZGDumpAllDataToDirectory(savePanel.URL.relativePath, self.memoryViewer.currentProcess.processTask, self))
					 {
						 NSRunAlertPanel(
										 @"The Memory Dump failed",
										 @"An error resulted in writing the memory dump.",
										 @"OK", nil, nil);
					 }
					 
					 dispatch_async(dispatch_get_main_queue(), ^{
						 if (!self.searchProgress.shouldCancelSearch)
						 {
							 ZGDeliverUserNotification(@"Finished Dumping Memory", nil, [NSString stringWithFormat:@"Dumped all memory for %@", self.memoryViewer.currentProcess.name]);
						 }
						 
						 self.progressIndicator.doubleValue = 0.0;
						 
						 [NSApp endSheet:self.memoryDumpProgressWindow];
						 [self.memoryDumpProgressWindow close];
						 
						 self.isBusy = NO;
						 self.searchProgress = nil;
						 
						 if (dumpMemoryActivity != nil)
						 {
							 [[NSProcessInfo processInfo] endActivity:dumpMemoryActivity];
						 }
					 });
				 });
			 });
		 }
	 }];
}

- (IBAction)cancelDumpingAllMemory:(id)__unused sender
{
	self.searchProgress.shouldCancelSearch = YES;
	[self.memoryDumpProgressCancelButton setEnabled:NO];
}

#pragma mark Memory Dump All Progress

- (void)progressWillBegin:(ZGSearchProgress *)searchProgress
{
	self.searchProgress = searchProgress;
	self.progressIndicator.maxValue = self.searchProgress.maxProgress;
}

- (void)progress:(ZGSearchProgress *)searchProgress advancedWithResultSet:(NSData *)__unused resultSet
{
	self.progressIndicator.doubleValue = searchProgress.progress;
}

@end
