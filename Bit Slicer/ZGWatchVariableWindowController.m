/*
 * Copyright (c) 2013 Mayur Pawashe
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

#import "ZGWatchVariableWindowController.h"
#import "ZGDocumentWindowController.h"
#import "ZGBreakPointController.h"
#import "ZGDebuggerUtilities.h"
#import "ZGInstruction.h"
#import "ZGBreakPoint.h"
#import "ZGRegistersState.h"
#import "ZGVariable.h"
#import "ZGWatchVariable.h"
#import "ZGProcess.h"
#import "ZGCalculator.h"
#import "ZGVirtualMemory.h"
#import "NSArrayAdditions.h"
#import "ZGVariableController.h"
#import "ZGDeliverUserNotifications.h"
#import "ZGRunAlertPanel.h"
#import "ZGLocalization.h"
#import "ZGRegisterEntries.h"
#import "ZGMachBinary.h"
#import "ZGTableView.h"
#import "ZGNullability.h"
#import "ZGDebugLogging.h"

#define ZGLocalizableWatchVariableString(string) NSLocalizedStringFromTable(string, @"[Code] Watch Variable", nil)

@implementation ZGWatchVariableWindowController
{
	IBOutlet NSProgressIndicator *_progressIndicator;
	IBOutlet NSTextField *_statusTextField;
	IBOutlet NSButton *_addButton;
	IBOutlet ZGTableView *_tableView;
	IBOutlet NSTableColumn *_addTableColumn;
	
	ZGBreakPointController * _Nonnull _breakPointController;
	ZGProcess * _Nullable _watchProcess;
	id _Nullable _watchActivity;
	NSMutableArray<ZGWatchVariable *> * _Nullable _foundWatchVariables;
	NSMutableDictionary<NSNumber *, ZGWatchVariable *> * _Nullable _foundWatchVariablesDictionary;
	watch_variable_completion_t _Nullable _completionHandler;
	
	__weak id <ZGShowMemoryWindow> _Nullable _delegate;
}

#pragma mark Birth & Death

- (id)initWithBreakPointController:(ZGBreakPointController *)breakPointController delegate:(id <ZGShowMemoryWindow>)delegate
{
	self = [super init];
	if (self != nil)
	{
		_breakPointController = breakPointController;
		_delegate = delegate;
	}
	return self;
}

- (void)windowDidLoad
{
	ZGAdjustLocalizableWidthsForWindowAndTableColumns(ZGUnwrapNullableObject(self.window), @[_addTableColumn], @{@"ru" : @[@20.0]});
}

// This method may not realistically be called due to the watch window sheet preventing normal app termination..
// But just in case..
- (void)cleanup
{
	[_breakPointController removeObserver:self];
}

- (NSString *)windowNibName
{
	return @"Watch Variable Dialog";
}

#pragma mark Stop Watching

- (void)stopWatchingAndInvokeCompletionHandler:(BOOL)shouldInvokeCompletionHandler
{
	[_breakPointController removeObserver:self];
	_watchProcess = nil;
	
	[_progressIndicator stopAnimation:nil];
	
	NSWindow *window = ZGUnwrapNullableObject([self window]);
	[NSApp endSheet:window];
	[window close];
	
	if (_watchActivity != nil)
	{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
		[[NSProcessInfo processInfo] endActivity:(id _Nonnull)_watchActivity];
#pragma clang diagnostic pop
		_watchActivity = nil;
	}
	
	if (shouldInvokeCompletionHandler)
	{
		NSArray<ZGWatchVariable *> *desiredWatchVariables = [_foundWatchVariables zgFilterUsingBlock:^(ZGWatchVariable *watchVariable) { return watchVariable.instruction.variable.enabled; }];
		
		for (ZGWatchVariable *watchVariable in desiredWatchVariables)
		{
			[self annotateWatchVariableDescription:watchVariable];
		}
		
		NSArray<ZGVariable *> *desiredVariables = [desiredWatchVariables zgMapUsingBlock:^id(ZGWatchVariable *watchVariable) { return watchVariable.instruction.variable; }];
		
		for (ZGVariable *variable in desiredVariables)
		{
			variable.enabled = NO;
		}
		_completionHandler(desiredVariables);
	}
	
	_completionHandler = nil;
	_foundWatchVariables = nil;
	_foundWatchVariablesDictionary = nil;
}

- (IBAction)stopWatchingAndAddInstructions:(id)__unused sender
{
	[self stopWatchingAndInvokeCompletionHandler:YES];
}

- (IBAction)cancel:(id)__unused sender
{
	[self stopWatchingAndInvokeCompletionHandler:NO];
}

- (void)triggerCurrentProcessChanged
{
	if (_foundWatchVariables.count == 0)
	{
		[self cancel:nil];
	}
	else
	{
		NSInteger result = ZGRunAlertPanelWithDefaultAndCancelButton([NSString stringWithFormat:ZGLocalizableWatchVariableString(@"targetTeriminatedAlertTitleFormat"), _watchProcess.name], ZGLocalizableWatchVariableString(@"targetTeriminatedAlertMessage"), ZGLocalizableWatchVariableString(@"targetTeriminatedAlertAddButton"));
		switch (result)
		{
			case NSAlertFirstButtonReturn:
				[self stopWatchingAndAddInstructions:nil];
				break;
			case NSAlertSecondButtonReturn:
				[self cancel:nil];
				break;
		}
	}
}

#pragma mark Misc.

- (void)updateAddButton
{
	NSUInteger variableCount = [[_foundWatchVariables zgFilterUsingBlock:^(ZGWatchVariable *watchVariable) { return watchVariable.instruction.variable.enabled; }] count];
	[_addButton setEnabled:variableCount > 0];
}

#pragma mark Watching

- (void)appendDescription:(NSMutableAttributedString *)description withRegisterEntries:(ZGRegisterEntry *)registerEntries registerLabel:(NSString *)registerLabel boldFont:(NSFont *)boldFont
{
	[description appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n\n" attributes:@{NSForegroundColorAttributeName : [NSColor textColor]}]];
	[description appendAttributedString:[[NSAttributedString alloc] initWithString:registerLabel attributes:@{NSForegroundColorAttributeName : [NSColor textColor], NSFontAttributeName : boldFont}]];
	[description appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:@{NSForegroundColorAttributeName : [NSColor textColor]}]];
	
	NSMutableArray<NSString *> *registerLines = [NSMutableArray array];
	
	for (ZGRegisterEntry *registerEntry = registerEntries; !ZG_REGISTER_ENTRY_IS_NULL(registerEntry); registerEntry++)
	{
		NSMutableString *registerLine = [NSMutableString stringWithFormat:@"%s = ", registerEntry->name];
		
		if (registerEntry->type == ZGRegisterGeneralPurpose)
		{
			switch (registerEntry->size)
			{
				case sizeof(uint32_t):
					[registerLine appendFormat:@"0x%X (%u)", *(uint32_t *)ZGRegisterEntryValue(registerEntry), *(uint32_t *)ZGRegisterEntryValue(registerEntry)];
					break;
				case sizeof(uint64_t):
					[registerLine appendFormat:@"0x%llX (%llu)", *(uint64_t *)ZGRegisterEntryValue(registerEntry), *(uint64_t *)ZGRegisterEntryValue(registerEntry)];
					break;
			}
		}
		else
		{
			[registerLine appendFormat:@"%@", [ZGVariable byteArrayStringFromValue:(unsigned char *)registerEntry->value size:registerEntry->size]];
		}
		
		[registerLines addObject:registerLine];
	}
	
	[description appendAttributedString:[[NSAttributedString alloc] initWithString:[registerLines componentsJoinedByString:@"\n"] attributes:@{NSForegroundColorAttributeName : [NSColor textColor]}]];
}

- (void)annotateWatchVariableDescription:(ZGWatchVariable *)watchVariable
{
	NSFont *userFont = [NSFont userFontOfSize:12];
	NSString *userFontFamilyName = userFont.familyName;
	
	if (userFontFamilyName == nil)
	{
		ZG_LOG(@"Failed to retrieve user font family name from %@", userFont);
		return;
	}
	
	NSFont *boldFont = [[NSFontManager sharedFontManager] fontWithFamily:userFontFamilyName traits:NSBoldFontMask weight:0 size:userFont.pointSize];
	
	if (boldFont == nil)
	{
		ZG_LOG(@"Failed to retrieve bold font from family name %@", userFontFamilyName);
		return;
	}
	
	ZGInstruction *instruction = watchVariable.instruction;
	ZGRegistersState *registersState = watchVariable.registersState;
	
	NSString *accessedTimes = [NSString stringWithFormat:ZGLocalizableWatchVariableString(@"accessedTimesFormat"), watchVariable.accessCount];
	
	NSMutableAttributedString *description = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n%@", instruction.text, accessedTimes] attributes:@{NSForegroundColorAttributeName : [NSColor textColor]}];
	
	ZGRegisterEntry registerEntries[ZG_MAX_REGISTER_ENTRIES];
	int numberOfGeneralRegisters = [ZGRegisterEntries getRegisterEntries:registerEntries fromGeneralPurposeThreadState:registersState.generalPurposeThreadState is64Bit:registersState.is64Bit];
	
	NSString *generalPurposeLabel = ZGLocalizableWatchVariableString(@"generalPurposeRegistersDescriptionLabel");
	NSString *generalPurposeAnnotatedLabel = watchVariable.accessCount > 1 ? [NSString stringWithFormat:@"%@ %@", generalPurposeLabel, ZGLocalizableWatchVariableString(@"firstRegisterAccessLabel")] : generalPurposeLabel;
	
	[self
	 appendDescription:description
	 withRegisterEntries:registerEntries
	 registerLabel:generalPurposeAnnotatedLabel
	 boldFont:boldFont];
	
	if (registersState.hasVectorState)
	{
		[ZGRegisterEntries getRegisterEntries:registerEntries + numberOfGeneralRegisters fromVectorThreadState:registersState.vectorState is64Bit:registersState.is64Bit hasAVXSupport:registersState.hasAVXSupport];
		
		NSString *vectorLabel = ZGLocalizableWatchVariableString(@"floatAndVectorRegistersDescriptionLabel");
		NSString *vectorAnnotatedLabel = watchVariable.accessCount > 1 ? [NSString stringWithFormat:@"%@ %@", vectorLabel, ZGLocalizableWatchVariableString(@"firstRegisterAccessLabel")] : vectorLabel;
		
		[self
		 appendDescription:description
		 withRegisterEntries:registerEntries + numberOfGeneralRegisters
		 registerLabel:vectorAnnotatedLabel
		 boldFont:boldFont];
	}
	
	instruction.variable.fullAttributedDescription = description;
}

- (void)dataAccessedByBreakPoint:(ZGBreakPoint *)__unused breakPoint fromInstructionPointer:(ZGMemoryAddress)instructionAddress withRegistersState:(ZGRegistersState *)registersState
{
	ZGProcess *watchProcess = _watchProcess;
	if (!watchProcess.valid)
	{
		return;
	}
	
	NSNumber *instructionAddressNumber = @(instructionAddress);
	
	ZGWatchVariable *existingWatchVariable = _foundWatchVariablesDictionary[instructionAddressNumber];
	if (existingWatchVariable != nil)
	{
		[existingWatchVariable increaseAccessCount];
		[_tableView reloadData];
		return;
	}
	
	NSArray<ZGMachBinary *> *machBinaries = [ZGMachBinary machBinariesInProcess:watchProcess];
	ZGInstruction *instruction = [ZGDebuggerUtilities findInstructionBeforeAddress:instructionAddress inProcess:watchProcess withBreakPoints:_breakPointController.breakPoints machBinaries:machBinaries];
	
	if (instruction == nil)
	{
		NSLog(@"ERROR: Couldn't parse instruction before 0x%llX", instructionAddress);
		return;
	}
	
	instruction.variable.enabled = YES;
	
	ZGWatchVariable *newWatchVariable = [[ZGWatchVariable alloc] initWithInstruction:instruction registersState:registersState];
	
	[_foundWatchVariablesDictionary setObject:newWatchVariable forKey:instructionAddressNumber];
	[_foundWatchVariables addObject:newWatchVariable];
	
	[self updateAddButton];
	
	[_tableView reloadData];
	
	ZGDeliverUserNotification(ZGLocalizableWatchVariableString(@"foundInstructionNotificationTitle"), _watchProcess.name, [NSString stringWithFormat:ZGLocalizableWatchVariableString(@"foundInstructionNotificationMessageFormat"), instruction.text], nil);
}

- (void)watchVariable:(ZGVariable *)variable withWatchPointType:(ZGWatchPointType)watchPointType inProcess:(ZGProcess *)process attachedToWindow:(NSWindow *)parentWindow completionHandler:(watch_variable_completion_t)completionHandler
{
	ZGBreakPoint *breakPoint = nil;
	if (![_breakPointController addWatchpointOnVariable:variable inProcess:process watchPointType:watchPointType delegate:self getBreakPoint:&breakPoint])
	{
		ZGRunAlertPanelWithOKButton(
						ZGLocalizableWatchVariableString(@"failedToWatchVariableAlertTitle"),
						ZGLocalizableWatchVariableString(@"failedToWatchVariableAlertMessage"));
		return;
	}
	
	NSWindow *window = ZGUnwrapNullableObject([self window]); // ensure window is loaded
	
	[self updateAddButton];
	
	_statusTextField.stringValue = [NSString stringWithFormat:ZGLocalizableWatchVariableString((watchPointType == ZGWatchPointWrite) ? @"watchWriteAccessesStatusFormat" : @"watchReadAndWriteAccessesStatusFormat"), breakPoint.watchSize * 8, variable.addressStringValue];
	
	[_progressIndicator startAnimation:nil];
	[_tableView reloadData];
	
	[parentWindow beginSheet:window completionHandler:^(NSModalResponse __unused returnCode) {
	}];
	
	_watchProcess = process;
	_completionHandler = [completionHandler copy];
	
	_foundWatchVariables = [[NSMutableArray alloc] init];
	_foundWatchVariablesDictionary = [[NSMutableDictionary alloc] init];
	
	_watchActivity = [[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiated reason:@"Watching Data Accesses"];
}

#pragma mark Selection Accessors

- (NSIndexSet *)selectedWatchVariableIndexes
{
	NSIndexSet *tableIndexSet = _tableView.selectedRowIndexes;
	NSInteger clickedRow = _tableView.clickedRow;
	
	return (clickedRow >= 0 && ![tableIndexSet containsIndex:(NSUInteger)clickedRow]) ? [NSIndexSet indexSetWithIndex:(NSUInteger)clickedRow] : tableIndexSet;
}

- (NSArray<ZGWatchVariable *> *)selectedWatchVariables
{
	return [_foundWatchVariables objectsAtIndexes:[self selectedWatchVariableIndexes]];
}

#pragma mark Table View

- (NSInteger)numberOfRowsInTableView:(NSTableView *)__unused tableView
{
	return (NSInteger)_foundWatchVariables.count;
}

- (id)tableView:(NSTableView *)__unused tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if (rowIndex < 0 || (NSUInteger)rowIndex >= _foundWatchVariables.count)
	{
		return nil;
	}
	
	ZGWatchVariable *watchVariable = _foundWatchVariables[(NSUInteger)rowIndex];
	
	if ([tableColumn.identifier isEqualToString:@"count"])
	{
		return @(watchVariable.accessCount);
	}
	else if ([tableColumn.identifier isEqualToString:@"address"])
	{
		return [watchVariable.instruction.variable addressStringValue];
	}
	else if ([tableColumn.identifier isEqualToString:@"instruction"])
	{
		return watchVariable.instruction.text;
	}
	else if ([tableColumn.identifier isEqualToString:@"enabled"])
	{
		return @(watchVariable.instruction.variable.enabled);
	}
	
	return nil;
}

- (void)tableView:(NSTableView *)__unused tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if (rowIndex < 0 || (NSUInteger)rowIndex >= _foundWatchVariables.count)
	{
		return;
	}
	
	ZGWatchVariable *watchVariable = _foundWatchVariables[(NSUInteger)rowIndex];
	if ([tableColumn.identifier isEqualToString:@"enabled"])
	{
		watchVariable.instruction.variable.enabled = [(NSString *)object boolValue];
		
		NSArray<ZGWatchVariable *> *selectedWatchVariables = [self selectedWatchVariables];
		if (selectedWatchVariables.count > 1 && [selectedWatchVariables containsObject:watchVariable])
		{
			_tableView.shouldIgnoreNextSelection = YES;
			for (ZGWatchVariable *selectedWatchVariable in selectedWatchVariables)
			{
				if (watchVariable != selectedWatchVariable)
				{
					selectedWatchVariable.instruction.variable.enabled = watchVariable.instruction.variable.enabled;
				}
			}
		}
		
		[self updateAddButton];
	}
}

- (BOOL)validateUserInterfaceItem:(NSMenuItem *)menuItem
{
	if ([menuItem action] == @selector(showMemoryViewer:) || [menuItem action] == @selector(showDebugger:))
	{
		if ([[self selectedWatchVariables] count] != 1 || _watchProcess == nil)
		{
			return NO;
		}
	}
	else if ([menuItem action] == @selector(copy:))
	{
		if ([[self selectedWatchVariables] count] == 0)
		{
			return NO;
		}
	}
	else if ([menuItem action] == @selector(copyAddress:))
	{
		if ([[self selectedWatchVariables] count] != 1)
		{
			return NO;
		}
	}
	
	return YES;
}

#pragma mark Actions

- (IBAction)copy:(id)__unused sender
{
	NSArray<ZGWatchVariable *> *selectedWatchVariables = [self selectedWatchVariables];
	for (ZGWatchVariable *watchVariable in selectedWatchVariables)
	{
		[self annotateWatchVariableDescription:watchVariable];
	}
	
	NSArray<ZGVariable *> *variables = [selectedWatchVariables zgMapUsingBlock:^(ZGWatchVariable *watchVariable) {
		return watchVariable.instruction.variable;
	}];
	
	[ZGVariableController copyVariablesToPasteboard:variables];
}

- (IBAction)copyAddress:(id)__unused sender
{
	ZGWatchVariable *watchVariable = [[self selectedWatchVariables] firstObject];
	[ZGVariableController copyVariableAddress:watchVariable.instruction.variable];
}

- (IBAction)showMemoryViewer:(id)__unused sender
{
	ZGWatchVariable *selectedWatchVariable = [[self selectedWatchVariables] firstObject];
	id <ZGShowMemoryWindow> delegate = _delegate;
	ZGProcess *watchProcess = _watchProcess;
	if (watchProcess != nil)
	{
		[delegate showMemoryViewerWindowWithProcess:watchProcess address:selectedWatchVariable.instruction.variable.address selectionLength:selectedWatchVariable.instruction.variable.size];
	}
}

- (IBAction)showDebugger:(id)__unused sender
{
	ZGWatchVariable *selectedWatchVariable = [[self selectedWatchVariables] firstObject];
	id <ZGShowMemoryWindow> delegate = _delegate;
	ZGProcess *watchProcess = _watchProcess;
	if (watchProcess != nil)
	{
		[delegate showDebuggerWindowWithProcess:watchProcess address:selectedWatchVariable.instruction.variable.address];
	}
}

@end
