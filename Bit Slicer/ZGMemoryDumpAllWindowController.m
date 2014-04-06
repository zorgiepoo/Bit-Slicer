/*
 * Created by Mayur Pawashe on 4/6/14.
 *
 * Copyright (c) 2014 zgcoder
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

#import "ZGMemoryDumpAllWindowController.h"
#import "ZGSearchProgress.h"
#import "ZGProcess.h"
#import "ZGMemoryDumpFunctions.h"
#import "ZGUtilities.h"

@interface ZGMemoryDumpAllWindowController ()

@property (nonatomic, assign) IBOutlet NSButton *cancelButton;
@property (nonatomic, assign) IBOutlet NSProgressIndicator *progressIndicator;

@property (nonatomic) ZGSearchProgress *searchProgress;
@property (nonatomic) BOOL isBusy;

@end

@implementation ZGMemoryDumpAllWindowController

- (NSString *)windowNibName
{
	return NSStringFromClass([self class]);
}

- (void)attachToWindow:(NSWindow *)parentWindow withProcess:(ZGProcess *)process
{
	NSSavePanel *savePanel = NSSavePanel.savePanel;
	savePanel.message = @"Choose a folder name to save the memory dump files to.";
	
	[savePanel
	 beginSheetModalForWindow:parentWindow
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
				  beginSheet:self.window
				  modalForWindow:parentWindow
				  modalDelegate:self
				  didEndSelector:nil
				  contextInfo:NULL];
				 
				 [self.cancelButton setEnabled:YES];
				 
				 self.isBusy = YES;
				 
				 id dumpMemoryActivity = nil;
				 if ([[NSProcessInfo processInfo] respondsToSelector:@selector(beginActivityWithOptions:reason:)])
				 {
					 dumpMemoryActivity = [[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiated reason:@"Dumping All Memory"];
				 }
				 
				 dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
					 if (!ZGDumpAllDataToDirectory(savePanel.URL.relativePath, process.processTask, self))
					 {
						 NSRunAlertPanel(
										 @"The Memory Dump failed",
										 @"An error resulted in writing the memory dump.",
										 @"OK", nil, nil);
					 }
					 
					 dispatch_async(dispatch_get_main_queue(), ^{
						 if (!self.searchProgress.shouldCancelSearch)
						 {
							 ZGDeliverUserNotification(@"Finished Dumping Memory", nil, [NSString stringWithFormat:@"Dumped all memory for %@", process.name]);
						 }
						 
						 self.progressIndicator.doubleValue = 0.0;
						 
						 [NSApp endSheet:self.window];
						 [self.window close];
						 
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
	[self.cancelButton setEnabled:NO];
}

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
