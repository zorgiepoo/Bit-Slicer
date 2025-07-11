/*
 * Copyright (c) 2012 Mayur Pawashe
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
 *
 * ZGMemoryViewerController
 * -----------------------
 * This class provides a user interface for viewing and navigating memory in a process.
 * It displays memory contents in a hex editor view, allows navigation to specific
 * addresses, and provides tools for inspecting and analyzing memory data.
 *
 * Key responsibilities:
 * - Displaying memory contents in a hex editor view
 * - Navigating to specific memory addresses
 * - Handling user interactions with memory view
 * - Updating the view when memory changes
 * - Providing data inspection tools
 *
 * Memory Viewer Architecture:
 * +------------------------+     +------------------------+     +------------------------+
 * |  Memory Navigation     |     |  Memory Display        |     |  User Interaction     |
 * |------------------------|     |------------------------|     |------------------------|
 * | - Address navigation   |     | - Hex editor view      |     | - Selection handling  |
 * | - Process selection    | --> | - Line counting        | --> | - Copy/paste          |
 * | - Memory region        |     | - Status bar           |     | - Data inspection     |
 * |   browsing             |     | - Data formatting      |     | - Context menus       |
 * +------------------------+     +------------------------+     +------------------------+
 */

#import <Cocoa/Cocoa.h>
#import <HexFiend/HexFiend.h>
#import "ZGMemoryTypes.h"
#import "ZGMemoryNavigationWindowController.h"
#import "ZGMemorySelectionDelegate.h"

@class ZGBreakPoint;
@class ZGProcess;

NS_ASSUME_NONNULL_BEGIN

@interface ZGMemoryViewerController : ZGMemoryNavigationWindowController <NSWindowDelegate>

- (id)initWithProcessTaskManager:(ZGProcessTaskManager *)processTaskManager rootlessConfiguration:(nullable ZGRootlessConfiguration *)rootlessConfiguration haltedBreakPoints:(NSMutableArray<ZGBreakPoint *> *)haltedBreakPoints delegate:(nullable id <ZGChosenProcessDelegate, ZGShowMemoryWindow, ZGMemorySelectionDelegate>)delegate;

@property (nonatomic, readonly) ZGMemoryAddress currentMemoryAddress;
@property (nonatomic, readonly) ZGMemorySize currentMemorySize;

- (void)updateWindowAndReadMemory:(BOOL)shouldReadMemory;

- (void)jumpToMemoryAddress:(ZGMemoryAddress)memoryAddress withSelectionLength:(ZGMemorySize)selectionLength inProcess:(ZGProcess *)requestedProcess;

- (IBAction)toggleDataInspector:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
