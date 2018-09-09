/*
 * Copyright (c) 2014 Mayur Pawashe
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
#import "ZGRunAlertPanel.h"
#import "ZGDeliverUserNotifications.h"
#import "ZGNullability.h"

@implementation ZGMemoryDumpAllWindowController
{
	IBOutlet NSButton *_cancelButton;
	IBOutlet NSProgressIndicator *_progressIndicator;
	
	ZGSearchProgress * _Nullable _searchProgress;
	BOOL _isBusy;
}

- (NSString *)windowNibName
{
	return @"Dump All Memory Dialog";
}

- (void)attachToWindow:(NSWindow *)parentWindow withProcess:(ZGProcess *)process
{
	NSSavePanel *savePanel = NSSavePanel.savePanel;
	savePanel.nameFieldStringValue = process.name;
	savePanel.message = ZGLocalizedStringFromDumpAllMemoryTable(@"savePanelPromptMessage");
	
	[savePanel beginSheetModalForWindow:parentWindow completionHandler:^(NSInteger result) {
		if (result != NSFileHandlingPanelOKButton)
		{
			return;
		}

		NSFileManager *fileManager = [[NSFileManager alloc] init];

		NSURL *saveURL = ZGUnwrapNullableObject(savePanel.URL);
		NSString *saveURLPath = ZGUnwrapNullableObject(saveURL.path);
		 
		if ([fileManager fileExistsAtPath:saveURLPath])
		{
			NSError *removeItemError = nil;
			if (![fileManager removeItemAtURL:saveURL error:&removeItemError])
			{
				NSLog(@"Failed to remove %@ with error %@", saveURLPath, removeItemError);
				return;
			}
		}

		NSError *createDirectoryError = nil;
		if (![fileManager createDirectoryAtURL:saveURL withIntermediateDirectories:NO attributes:nil error:&createDirectoryError])
		{
			NSLog(@"Failed to create directory at %@ with error %@", saveURLPath, createDirectoryError);
			return;
		}
		
		// Dispatch our task later so that the sheet shows up *after* our save panel is dismissed
		dispatch_async(dispatch_get_main_queue(), ^{
			NSWindow *window = ZGUnwrapNullableObject(self.window);
			
			[parentWindow beginSheet:window completionHandler:^(NSModalResponse __unused returnCode) {
			}];
			 
			[self->_cancelButton setEnabled:YES];

			self->_isBusy = YES;
			 
			id dumpMemoryActivity = [[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiated reason:@"Dumping All Memory"];
			
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				BOOL dumpedAllData = ZGDumpAllDataToDirectory(saveURLPath, process, self);
				
				dispatch_async(dispatch_get_main_queue(), ^{
					if (!self->_searchProgress.shouldCancelSearch)
					{
						if (dumpedAllData)
						{
							ZGDeliverUserNotification(ZGLocalizedStringFromDumpAllMemoryTable(@"finishedDumpingMemoryNotificationTitle"), nil, [NSString stringWithFormat:ZGLocalizedStringFromDumpAllMemoryTable(@"finishedDumpingMemoryNotificationMessageFormat"), process.name], nil);
						}
						else
						{
							ZGRunAlertPanelWithOKButton(ZGLocalizedStringFromDumpAllMemoryTable(@"failedMemoryDumpAlertTitle"), ZGLocalizedStringFromDumpAllMemoryTable(@"failedMemoryDumpAlertMessage"));
						}
					}

					self->_progressIndicator.doubleValue = 0.0;

					[NSApp endSheet:window];
					[window close];

					self->_isBusy = NO;
					self->_searchProgress = nil;

					if (dumpMemoryActivity != nil)
					{
						[[NSProcessInfo processInfo] endActivity:dumpMemoryActivity];
					}
				});
			});
		});
	}];
}

- (IBAction)cancelDumpingAllMemory:(id)__unused sender
{
	_searchProgress.shouldCancelSearch = YES;
	[_cancelButton setEnabled:NO];
}

- (void)progressWillBegin:(ZGSearchProgress *)searchProgress
{
	_searchProgress = searchProgress;
	_progressIndicator.maxValue = _searchProgress.maxProgress;
}

- (void)progress:(ZGSearchProgress *)searchProgress advancedWithResultSet:(NSData *)__unused resultSet
{
	_progressIndicator.doubleValue = searchProgress.progress;
}

@end
