/*
 * Created by Mayur Pawashe on 12/25/13.
 *
 * Copyright (c) 2013 zgcoder
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
#import "ZGVirtualMemoryHelpers.h"
#import "NSArrayAdditions.h"
#import "ZGVariableController.h"
#import "ZGUtilities.h"
#import "ZGRegisterEntries.h"
#import "ZGMachBinary.h"
#import "ZGNavigationPost.h"
#import "ZGTableView.h"

#define ZGLocalizableWatchVariableString(string) NSLocalizedStringFromTable(string, @"[Code] Watch Variable", nil)

@interface ZGWatchVariableWindowController ()

@property (nonatomic) ZGBreakPointController *breakPointController;

@property (nonatomic, assign) IBOutlet NSProgressIndicator *progressIndicator;
@property (nonatomic, assign) IBOutlet NSTextField *statusTextField;
@property (nonatomic, assign) IBOutlet NSButton *addButton;
@property (nonatomic, assign) IBOutlet ZGTableView *tableView;
@property (nonatomic, assign) IBOutlet NSTableColumn *addTableColumn;

@property (nonatomic) ZGProcess *watchProcess;
@property (nonatomic) id watchActivity;
@property (nonatomic) NSMutableArray *foundWatchVariables;
@property (nonatomic) NSMutableDictionary *foundWatchVariablesDictionary;
@property (nonatomic, copy) watch_variable_completion_t completionHandler;

@end

@implementation ZGWatchVariableWindowController

#pragma mark Birth & Death

- (id)initWithBreakPointController:(ZGBreakPointController *)breakPointController
{
	self = [super init];
	if (self != nil)
	{
		[[NSNotificationCenter defaultCenter]
		 addObserver:self
		 selector:@selector(applicationWillTerminate:)
		 name:NSApplicationWillTerminateNotification
		 object:nil];
		
		self.breakPointController = breakPointController;
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	self.watchProcess = nil;
}

- (void)windowDidLoad
{
	ZGAdjustLocalizableWidthsForTableColumns(self.window, @[self.addTableColumn], @{@"ru" : @[@20.0]});
}

- (void)applicationWillTerminate:(NSNotification *)__unused notification
{
	[self.breakPointController removeObserver:self];
}

- (NSString *)windowNibName
{
	return @"Watch Variable Dialog";
}

#pragma mark Stop Watching

- (void)stopWatchingAndInvokeCompletionHandler:(BOOL)shouldInvokeCompletionHandler
{
	[self.breakPointController removeObserver:self];
	self.watchProcess = nil;
	
	[self.progressIndicator stopAnimation:nil];
	
	[NSApp endSheet:self.window];
	[self.window close];
	
	if (self.watchActivity != nil)
	{
		[[NSProcessInfo processInfo] endActivity:self.watchActivity];
		self.watchActivity = nil;
	}
	
	if (shouldInvokeCompletionHandler)
	{
		NSArray *desiredWatchVariables = [self.foundWatchVariables zgFilterUsingBlock:^(ZGWatchVariable *watchVariable) { return watchVariable.instruction.variable.enabled; }];
		
		for (ZGWatchVariable *watchVariable in desiredWatchVariables)
		{
			[self annotateWatchVariableDescription:watchVariable];
		}
		
		NSArray *desiredVariables = [desiredWatchVariables zgMapUsingBlock:^id(ZGWatchVariable *watchVariable) { return watchVariable.instruction.variable; }];
		
		for (ZGVariable *variable in desiredVariables)
		{
			variable.enabled = NO;
		}
		self.completionHandler(desiredVariables);
	}
	
	self.completionHandler = nil;
	self.foundWatchVariables = nil;
	self.foundWatchVariablesDictionary = nil;
}

- (IBAction)stopWatchingAndAddInstructions:(id)__unused sender
{
	[self stopWatchingAndInvokeCompletionHandler:YES];
}

- (IBAction)cancel:(id)__unused sender
{
	[self stopWatchingAndInvokeCompletionHandler:NO];
}

- (void)watchProcessDied:(NSNotification *)__unused notification
{
	if (self.foundWatchVariables.count == 0)
	{
		[self cancel:nil];
	}
	else
	{
		NSInteger result = ZGRunAlertPanelWithDefaultAndCancelButton(
						[NSString stringWithFormat:ZGLocalizableWatchVariableString(@"targetTeriminatedAlertTitleFormat"), self.watchProcess.name],
						ZGLocalizableWatchVariableString(@"targetTeriminatedAlertMessage"),
						ZGLocalizableWatchVariableString(@"targetTeriminatedAlertAddButton"));
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

- (void)setWatchProcess:(ZGProcess *)watchProcess
{
	if (_watchProcess != nil)
	{
		[[NSNotificationCenter defaultCenter]
		 removeObserver:self
		 name:ZGTargetProcessDiedNotification
		 object:watchProcess];
	}
	
	_watchProcess = watchProcess;
	
	if (_watchProcess != nil)
	{
		[[NSNotificationCenter defaultCenter]
		 addObserver:self
		 selector:@selector(watchProcessDied:)
		 name:ZGTargetProcessDiedNotification
		 object:watchProcess];
	}
}

- (void)updateAddButton
{
	NSUInteger variableCount = [[self.foundWatchVariables zgFilterUsingBlock:^(ZGWatchVariable *watchVariable) { return watchVariable.instruction.variable.enabled; }] count];
	[self.addButton setEnabled:variableCount > 0];
}

#pragma mark Watching

- (void)appendDescription:(NSMutableAttributedString *)description withRegisterEntries:(ZGRegisterEntry *)registerEntries registerLabel:(NSString *)registerLabel boldFont:(NSFont *)boldFont
{
	[description appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n\n"]];
	[description appendAttributedString:[[NSAttributedString alloc] initWithString:registerLabel attributes:@{NSFontAttributeName : boldFont}]];
	[description appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
	
	NSMutableArray *registerLines = [NSMutableArray array];
	
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
	
	[description appendAttributedString:[[NSAttributedString alloc] initWithString:[registerLines componentsJoinedByString:@"\n"]]];
}

- (void)annotateWatchVariableDescription:(ZGWatchVariable *)watchVariable
{
	NSFont *userFont = [NSFont userFontOfSize:12];
	NSFont *boldFont = [[NSFontManager sharedFontManager] fontWithFamily:userFont.familyName traits:NSBoldFontMask weight:0 size:userFont.pointSize];
	
	ZGInstruction *instruction = watchVariable.instruction;
	ZGRegistersState *registersState = watchVariable.registersState;
	
	NSString *accessedTimes = @"";
	if (floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_8)
	{
		accessedTimes = [NSString stringWithFormat:ZGLocalizableWatchVariableString(@"accessedTimesFormat"), watchVariable.accessCount];
	}
	else if (watchVariable.accessCount == 1)
	{
		accessedTimes = [NSString stringWithFormat:ZGLocalizableWatchVariableString(@"accessedSingleTimeFormat"), watchVariable.accessCount];
	}
	else
	{
		accessedTimes = [NSString stringWithFormat:ZGLocalizableWatchVariableString(@"accessedMultipleTimesFormat"), watchVariable.accessCount];
	}
	
	NSMutableAttributedString *description = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n%@", instruction.text, accessedTimes]];
	
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
	if (!self.watchProcess.valid)
	{
		return;
	}
	
	NSNumber *instructionAddressNumber = @(instructionAddress);
	
	ZGWatchVariable *existingWatchVariable = [self.foundWatchVariablesDictionary objectForKey:instructionAddressNumber];
	if (existingWatchVariable != nil)
	{
		[existingWatchVariable increaseAccessCount];
		[self.tableView reloadData];
		return;
	}
	
	NSArray *machBinaries = [ZGMachBinary machBinariesInProcess:self.watchProcess];
	ZGInstruction *instruction = [ZGDebuggerUtilities findInstructionBeforeAddress:instructionAddress inProcess:self.watchProcess withBreakPoints:self.breakPointController.breakPoints machBinaries:machBinaries];
	
	if (instruction == nil)
	{
		NSLog(@"ERROR: Couldn't parse instruction before 0x%llX", instructionAddress);
		return;
	}
	
	instruction.variable.enabled = YES;
	
	ZGWatchVariable *newWatchVariable = [[ZGWatchVariable alloc] initWithInstruction:instruction registersState:registersState];
	
	[self.foundWatchVariablesDictionary setObject:newWatchVariable forKey:instructionAddressNumber];
	[self.foundWatchVariables addObject:newWatchVariable];
	
	[self updateAddButton];
	
	[self.tableView reloadData];
	
	ZGDeliverUserNotification(ZGLocalizableWatchVariableString(@"foundInstructionNotificationTitle"), self.watchProcess.name, [NSString stringWithFormat:ZGLocalizableWatchVariableString(@"foundInstructionNotificationMessageFormat"), instruction.text], nil);
}

- (void)watchVariable:(ZGVariable *)variable withWatchPointType:(ZGWatchPointType)watchPointType inProcess:(ZGProcess *)process attachedToWindow:(NSWindow *)parentWindow completionHandler:(watch_variable_completion_t)completionHandler
{
	ZGBreakPoint *breakPoint = nil;
	if (![self.breakPointController addWatchpointOnVariable:variable inProcess:process watchPointType:watchPointType delegate:self getBreakPoint:&breakPoint])
	{
		ZGRunAlertPanelWithOKButton(
						ZGLocalizableWatchVariableString(@"failedToWatchVariableAlertTitle"),
						ZGLocalizableWatchVariableString(@"failedToWatchVariableAlertMessage"));
		return;
	}
	
	[self window]; // ensure window is loaded
	
	[self updateAddButton];
	
	self.statusTextField.stringValue = [NSString stringWithFormat:ZGLocalizableWatchVariableString((watchPointType == ZGWatchPointWrite) ? @"watchWriteAccessesStatusFormat" : @"watchReadAndWriteAccessesStatusFormat"), breakPoint.watchSize * 8, variable.addressStringValue];
	
	[self.progressIndicator startAnimation:nil];
	[self.tableView reloadData];
	
	[NSApp
	 beginSheet:self.window
	 modalForWindow:parentWindow
	 modalDelegate:nil
	 didEndSelector:nil
	 contextInfo:NULL];
	
	self.watchProcess = process;
	self.completionHandler = completionHandler;
	
	self.foundWatchVariables = [[NSMutableArray alloc] init];
	self.foundWatchVariablesDictionary = [[NSMutableDictionary alloc] init];
	
	if ([[NSProcessInfo processInfo] respondsToSelector:@selector(beginActivityWithOptions:reason:)])
	{
		self.watchActivity = [[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiated reason:@"Watching Data Accesses"];
	}
}

#pragma mark Selection Accessors

- (NSIndexSet *)selectedWatchVariableIndexes
{
	NSIndexSet *tableIndexSet = self.tableView.selectedRowIndexes;
	NSInteger clickedRow = self.tableView.clickedRow;
	
	return (clickedRow >= 0 && ![tableIndexSet containsIndex:(NSUInteger)clickedRow]) ? [NSIndexSet indexSetWithIndex:(NSUInteger)clickedRow] : tableIndexSet;
}

- (NSArray *)selectedWatchVariables
{
	return [self.foundWatchVariables objectsAtIndexes:[self selectedWatchVariableIndexes]];
}

#pragma mark Table View

- (NSInteger)numberOfRowsInTableView:(NSTableView *)__unused tableView
{
	return (NSInteger)self.foundWatchVariables.count;
}

- (id)tableView:(NSTableView *)__unused tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if (rowIndex < 0 || (NSUInteger)rowIndex >= self.foundWatchVariables.count)
	{
		return nil;
	}
	
	ZGWatchVariable *watchVariable = self.foundWatchVariables[(NSUInteger)rowIndex];
	
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
	if (rowIndex < 0 || (NSUInteger)rowIndex >= self.foundWatchVariables.count)
	{
		return;
	}
	
	ZGWatchVariable *watchVariable = self.foundWatchVariables[(NSUInteger)rowIndex];
	if ([tableColumn.identifier isEqualToString:@"enabled"])
	{
		watchVariable.instruction.variable.enabled = [object boolValue];
		
		NSArray *selectedWatchVariables = [self selectedWatchVariables];
		if (selectedWatchVariables.count > 1 && [selectedWatchVariables containsObject:watchVariable])
		{
			self.tableView.shouldIgnoreNextSelection = YES;
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
		if ([[self selectedWatchVariables] count] != 1 || self.watchProcess == nil)
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
	NSArray *selectedWatchVariables = [self selectedWatchVariables];
	for (ZGWatchVariable *watchVariable in selectedWatchVariables)
	{
		[self annotateWatchVariableDescription:watchVariable];
	}
	
	NSArray *variables = [selectedWatchVariables zgMapUsingBlock:^(ZGWatchVariable *watchVariable) {
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
	[ZGNavigationPost postShowMemoryViewerWithProcess:self.watchProcess address:selectedWatchVariable.instruction.variable.address selectionLength:selectedWatchVariable.instruction.variable.size];
}

- (IBAction)showDebugger:(id)__unused sender
{
	ZGWatchVariable *selectedWatchVariable = [[self selectedWatchVariables] firstObject];
	[ZGNavigationPost postShowDebuggerWithProcess:self.watchProcess address:selectedWatchVariable.instruction.variable.address];
}

@end
