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
#import "ZGMemoryViewer.h"
#import "ZGProcess.h"
#import "ZGCalculator.h"
#import "ZGMemoryTypes.h"
#import "ZGUtilities.h"
#import "ZGVirtualMemory.h"
#import "ZGDocumentSearchController.h"

@interface ZGMemoryDumpController ()

@property (assign, nonatomic) IBOutlet ZGMemoryViewer *memoryViewer;

@property (assign) IBOutlet NSWindow *memoryDumpWindow;
@property (assign) IBOutlet NSTextField *memoryDumpFromAddressTextField;
@property (assign) IBOutlet NSTextField *memoryDumpToAddressTextField;

@property (assign) IBOutlet NSWindow *memoryDumpProgressWindow;
@property (assign) IBOutlet NSButton *memoryDumpProgressCancelButton;

@property (assign) IBOutlet NSProgressIndicator *progressIndicator;

@property (readwrite, strong, nonatomic) NSTimer *progressTimer;

@end

@implementation ZGMemoryDumpController

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
		 beginSheetModalForWindow:self.memoryViewer.window
		 completionHandler:^(NSInteger result)
		 {
			 if (result == NSFileHandlingPanelOKButton)
			 {
				 BOOL success = YES;
				 
				 @try
				 {
					 ZGMemorySize size = toAddress - fromAddress;
					 void *bytes = NULL;
					 
					 if (ZGReadBytes(self.memoryViewer.currentProcess.processTask, fromAddress, &bytes, &size))
					 {
						 NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)size];
						 success = [data writeToURL:savePanel.URL atomically:NO];
						 
						 ZGFreeBytes(self.memoryViewer.currentProcess.processTask, bytes, size);
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
	HFRange selectedRange = self.memoryViewer.selectedAddressRange;
	if (selectedRange.length > 0)
	{
		self.memoryDumpFromAddressTextField.stringValue = [NSString stringWithFormat:@"0x%llX", selectedRange.location];
		self.memoryDumpToAddressTextField.stringValue = [NSString stringWithFormat:@"0x%llX", selectedRange.location + selectedRange.length];
	}
	
	[NSApp
	 beginSheet:self.memoryDumpWindow
	 modalForWindow:self.memoryViewer.window
	 modalDelegate:self
	 didEndSelector:nil
	 contextInfo:NULL];
}

#pragma mark Memory Dump All

- (void)updateMemoryDumpProgress:(NSTimer *)timer
{
	self.progressIndicator.doubleValue = self.memoryViewer.currentProcess.searchProgress;
}

- (void)memoryDumpAllRequest
{
	NSSavePanel *savePanel = NSSavePanel.savePanel;
	savePanel.message = @"Choose a folder name to save the memory dump files. This may take a while.";
	
	[savePanel
	 beginSheetModalForWindow:self.memoryViewer.window
	 completionHandler:^(NSInteger result)
	 {
		 if (result == NSFileHandlingPanelOKButton)
		 {
			 dispatch_async(dispatch_get_main_queue(), ^{
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
				 
				 [NSApp
				  beginSheet:self.memoryDumpProgressWindow
				  modalForWindow:self.memoryViewer.window
				  modalDelegate:self
				  didEndSelector:nil
				  contextInfo:NULL];
				 
				 [self.memoryDumpProgressCancelButton setEnabled:YES];
				 
				 self.progressIndicator.maxValue = self.memoryViewer.currentProcess.numberOfRegions;
				 
				 self.progressTimer =
				 [NSTimer
				  scheduledTimerWithTimeInterval:USER_INTERFACE_UPDATE_TIME_INTERVAL
				  target:self
				  selector:@selector(updateMemoryDumpProgress:)
				  userInfo:nil
				  repeats:YES];
				 
				 dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
					 if (!ZGSaveAllDataToDirectory(savePanel.URL.relativePath, self.memoryViewer.currentProcess))
					 {
						 NSRunAlertPanel(
										 @"The Memory Dump failed",
										 @"An error resulted in writing the memory dump.",
										 @"OK", nil, nil);
					 }
					 
					 dispatch_async(dispatch_get_main_queue(), ^{
						 [self.progressTimer invalidate];
						 self.progressTimer = nil;
						 
						 if (self.memoryViewer.currentProcess.isDoingMemoryDump && NSClassFromString(@"NSUserNotification"))
						 {
							 NSUserNotification *userNotification = [[NSUserNotification alloc] init];
							 userNotification.title = @"Finished Dumping Memory";
							 userNotification.informativeText = [NSString stringWithFormat:@"Dumped all memory for %@", self.memoryViewer.currentProcess.name];
							 [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:userNotification];
						 }
						 
						 self.progressIndicator.doubleValue = 0.0;
						 self.memoryViewer.currentProcess.isDoingMemoryDump = NO;
						 
						 [NSApp endSheet:self.memoryDumpProgressWindow];
						 [self.memoryDumpProgressWindow close];
					 });
				 });
			 });
		 }
	 }];
}

- (IBAction)cancelDumpingAllMemory:(id)sender
{
	self.memoryViewer.currentProcess.isDoingMemoryDump = NO;
	[self.memoryDumpProgressCancelButton setEnabled:NO];
}

@end
