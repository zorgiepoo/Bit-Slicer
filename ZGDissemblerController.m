/*
 * Created by Mayur Pawashe on 12/27/12.
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

#import "ZGDissemblerController.h"
#import "ZGAppController.h"
#import "ZGProcess.h"
#import "ZGCalculator.h"
#import "ZGUtilities.h"
#import "ZGInstruction.h"
#import "udis86.h"

@interface ZGDissemblerController ()

@property (assign) IBOutlet NSPopUpButton *runningApplicationsPopUpButton;
@property (assign) IBOutlet NSTextField *addressTextField;
@property (assign) IBOutlet NSTableView *instructionsTableView;

@property (readwrite) ZGMemoryAddress currentMemoryAddress;
@property (readwrite) ZGMemorySize currentMemorySize;

@property (nonatomic, strong) NSArray *instructions;

@end

@implementation ZGDissemblerController

- (id)init
{
	self = [super initWithWindowNibName:NSStringFromClass([self class])];
	
	return self;
}

- (void)setCurrentProcess:(ZGProcess *)newProcess
{
	BOOL shouldUpdate = NO;
	
	if (_currentProcess.processID != newProcess.processID)
	{
		shouldUpdate = YES;
	}
	_currentProcess = newProcess;
	if (_currentProcess && ![_currentProcess hasGrantedAccess])
	{
		if (![_currentProcess grantUsAccess])
		{
			shouldUpdate = YES;
			//NSLog(@"Debugger failed to grant access to PID %d", _currentProcess.processID);
		}
	}
	
	if (shouldUpdate)
	{
		self.instructions = @[];
		[self.instructionsTableView reloadData];
	}
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
	// Add processes to popup button,
	[self updateRunningApplicationProcesses:[[ZGAppController sharedController] lastSelectedProcessName]];
	
	[[NSWorkspace sharedWorkspace]
	 addObserver:self
	 forKeyPath:@"runningApplications"
	 options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew
	 context:NULL];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (object == NSWorkspace.sharedWorkspace)
	{
		[self updateRunningApplicationProcesses:nil];
	}
}

- (void)updateRunningApplicationProcesses:(NSString *)desiredProcessName
{
	[self.runningApplicationsPopUpButton removeAllItems];
	
	NSMenuItem *firstRegularApplicationMenuItem = nil;
	
	BOOL foundTargettedProcess = NO;
	NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"activationPolicy" ascending:YES];
	for (NSRunningApplication *runningApplication in  [NSWorkspace.sharedWorkspace.runningApplications sortedArrayUsingDescriptors:@[sortDescriptor]])
	{
		if (runningApplication.processIdentifier != NSRunningApplication.currentApplication.processIdentifier)
		{
			NSMenuItem *menuItem = [[NSMenuItem alloc] init];
			menuItem.title = [NSString stringWithFormat:@"%@ (%d)", runningApplication.localizedName, runningApplication.processIdentifier];
			NSImage *iconImage = runningApplication.icon;
			iconImage.size = NSMakeSize(16, 16);
			menuItem.image = iconImage;
			ZGProcess *representedProcess =
			[[ZGProcess alloc]
			 initWithName:runningApplication.localizedName
			 processID:runningApplication.processIdentifier
			 set64Bit:(runningApplication.executableArchitecture == NSBundleExecutableArchitectureX86_64)];
			
			menuItem.representedObject = representedProcess;
			
			[self.runningApplicationsPopUpButton.menu addItem:menuItem];
			
			if (!firstRegularApplicationMenuItem && runningApplication.activationPolicy == NSApplicationActivationPolicyRegular)
			{
				firstRegularApplicationMenuItem = menuItem;
			}
			
			if (self.currentProcess.processID == runningApplication.processIdentifier || [desiredProcessName isEqualToString:runningApplication.localizedName])
			{
				[self.runningApplicationsPopUpButton selectItem:self.runningApplicationsPopUpButton.lastItem];
				foundTargettedProcess = YES;
			}
		}
	}
	
	if (!foundTargettedProcess)
	{
		if (firstRegularApplicationMenuItem)
		{
			[self.runningApplicationsPopUpButton selectItem:firstRegularApplicationMenuItem];
		}
		else if ([self.runningApplicationsPopUpButton indexOfSelectedItem] >= 0)
		{
			[self.runningApplicationsPopUpButton selectItemAtIndex:0];
		}
	}
	
	self.currentProcess = self.runningApplicationsPopUpButton.selectedItem.representedObject;
}

- (IBAction)runningApplicationsPopUpButton:(id)sender
{
	if ([self.runningApplicationsPopUpButton.selectedItem.representedObject processID] != self.currentProcess.processID)
	{
		self.currentProcess = self.runningApplicationsPopUpButton.selectedItem.representedObject;
	}
}

- (void)selectAddress:(ZGMemoryAddress)address
{
	NSUInteger selectionIndex = 0;
	for (ZGInstruction *instruction in self.instructions)
	{
		if (instruction.variable.address >= address)
		{
			break;
		}
		selectionIndex++;
	}
	
	[self.instructionsTableView scrollRowToVisible:selectionIndex];
	[self.instructionsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:selectionIndex] byExtendingSelection:NO];
	[self.window makeFirstResponder:self.instructionsTableView];
}

- (ZGMemoryAddress)findInstructionAddressFromBreakPointAddress:(ZGMemoryAddress)breakPointAddress inProcess:(ZGProcess *)process
{
	ZGMemoryAddress instructionAddress = 0x0;
	
	for (ZGRegion *region in ZGRegionsForProcessTask(process.processTask))
	{
		if (breakPointAddress >= region.address && breakPointAddress < region.address + region.size)
		{
			void *bytes;
			ZGMemorySize size = region.size;
			if (ZGReadBytes(process.processTask, region.address, &bytes, &size))
			{
				ud_t object;
				ud_init(&object);
				ud_set_input_buffer(&object, bytes, size);
				ud_set_mode(&object, process.pointerSize * 8);
				ud_set_syntax(&object, UD_SYN_INTEL);
				
				ZGMemoryAddress previousOffset = 0;
				BOOL foundAddress = NO;
				while (ud_disassemble(&object) > 0)
				{
					if (region.address + ud_insn_off(&object) >= breakPointAddress)
					{
						foundAddress = YES;
						break;
					}
					
					previousOffset = ud_insn_off(&object);
				}
				
				if (foundAddress)
				{
					instructionAddress = region.address + previousOffset;
				}
				
				ZGFreeBytes(process.processTask, bytes, size);
			}
			
			break;
		}
	}
	
	return instructionAddress;
}

- (BOOL)updateDissemblerWithAddress:(ZGMemoryAddress)address size:(ZGMemorySize)size
{
	BOOL success = NO;
	void *bytes;
	if ((success = ZGReadBytes(self.currentProcess.processTask, address, &bytes, &size)))
	{
		ud_t object;
		ud_init(&object);
		ud_set_input_buffer(&object, bytes, size);
		ud_set_mode(&object, self.currentProcess.pointerSize * 8);
		ud_set_syntax(&object, UD_SYN_INTEL);
		
		NSMutableArray *newInstructions = [[NSMutableArray alloc] init];
		
		while (ud_disassemble(&object) > 0)
		{
			ZGInstruction *instruction = [[ZGInstruction alloc] init];
			instruction.text = @(ud_insn_asm(&object));
			instruction.variable = [[ZGVariable alloc] initWithValue:bytes + ud_insn_off(&object) size:ud_insn_len(&object) address:address + ud_insn_off(&object) type:ZGByteArray qualifier:0 pointerSize:self.currentProcess.pointerSize];
			
			[newInstructions addObject:instruction];
		}
		
		self.instructions = [NSArray arrayWithArray:newInstructions];
		
		[self.instructionsTableView reloadData];
		
		ZGFreeBytes(self.currentProcess.processTask, bytes, size);
	}
	
	return success;
}

- (IBAction)readMemory:(id)sender
{
	BOOL success = NO;
	
	if (![self.currentProcess hasGrantedAccess])
	{
		goto END_DEBUGGER_CHANGE;
	}
	
	// create scope block to allow for goto
	{
		NSString *calculatedMemoryAddressExpression = [ZGCalculator evaluateExpression:self.addressTextField.stringValue];
		
		ZGMemoryAddress calculatedMemoryAddress = 0;
		
		if (isValidNumber(calculatedMemoryAddressExpression))
		{
			calculatedMemoryAddress = memoryAddressFromExpression(calculatedMemoryAddressExpression);
		}
		
		NSArray *memoryRegions = ZGRegionsForProcessTask(self.currentProcess.processTask);
		if (memoryRegions.count == 0)
		{
			goto END_DEBUGGER_CHANGE;
		}
		
		if (calculatedMemoryAddress >= self.currentMemoryAddress && calculatedMemoryAddress < self.currentMemoryAddress + self.currentMemorySize)
		{
			[self selectAddress:calculatedMemoryAddress];
			success = YES;
			goto END_DEBUGGER_CHANGE;
		}
		
		ZGRegion *chosenRegion = nil;
		if (calculatedMemoryAddress != 0)
		{
			for (ZGRegion *region in memoryRegions)
			{
				if ((region.protection & VM_PROT_READ && region.protection & VM_PROT_EXECUTE) && calculatedMemoryAddress >= region.address && calculatedMemoryAddress < region.address + region.size)
				{
					chosenRegion = region;
					break;
				}
			}
		}
		else
		{
			for (ZGRegion *region in memoryRegions)
			{
				if (region.protection & VM_PROT_READ && region.protection & VM_PROT_EXECUTE)
				{
					chosenRegion = region;
					calculatedMemoryAddress = region.address;
					break;
				}
			}
		}
		
		if (!chosenRegion)
		{
			goto END_DEBUGGER_CHANGE;
		}
		
		self.currentMemorySize = chosenRegion.size;
		self.currentMemoryAddress = chosenRegion.address;
		
		NSLog(@"Trying to do of size %lld", self.currentMemorySize);
		[self updateDissemblerWithAddress:self.currentMemoryAddress size:self.currentMemorySize];
		if (calculatedMemoryAddress > 0)
		{
			[self selectAddress:calculatedMemoryAddress];
		}
		else
		{
			[self selectAddress:self.currentMemoryAddress];
		}
		
		success = YES;
	}
	
END_DEBUGGER_CHANGE:
	if (!success)
	{
		// clear data
		self.instructions = [NSArray array];
		[self.instructionsTableView reloadData];
	}
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return self.instructions.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	id result = nil;
	if (rowIndex >= 0 && (NSUInteger)rowIndex < self.instructions.count)
	{
		ZGInstruction *instruction = [self.instructions objectAtIndex:rowIndex];
		if ([tableColumn.identifier isEqualToString:@"address"])
		{
			result = instruction.variable.addressStringValue;
		}
		else if ([tableColumn.identifier isEqualToString:@"instruction"])
		{
			result = instruction.text;
		}
		else if ([tableColumn.identifier isEqualToString:@"bytes"])
		{
			result = instruction.variable.stringValue;
		}
	}
	
	return result;
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
}

@end
