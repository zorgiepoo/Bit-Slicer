/*
 * Created by Mayur Pawashe on 9/2/13.
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

#import "ZGLoggerWindowController.h"

#define ZGLoggerWindowText @"ZGLoggerWindowText"
#define MIN_LOG_LINES_TO_RESTORE 50U

@interface ZGLoggerWindowController ()

@property (nonatomic, assign) IBOutlet NSTextView *loggerTextView;
@property (nonatomic, assign) IBOutlet NSButton *clearButton;
@property (nonatomic, assign) IBOutlet NSTextField *statusTextField;
@property (nonatomic) NSMutableString *loggerText;
@property (nonatomic) NSUInteger numberOfMessages;

@end

@implementation ZGLoggerWindowController

- (id)init
{
	self = [super init];
	if (self != nil)
	{
		self.loggerText = [[NSMutableString alloc] init];
	}
	return self;
}

- (NSString *)windowNibName
{
	return NSStringFromClass([self class]);
}

- (void)encodeRestorableStateWithCoder:(NSCoder *)coder
{
    [super encodeRestorableStateWithCoder:coder];
	
	NSArray *lines = [self.loggerText componentsSeparatedByString:@"\n"];
	NSUInteger numberOfLinesToTake = MIN(MIN_LOG_LINES_TO_RESTORE, lines.count);
	NSArray *lastFewLines = [lines subarrayWithRange:NSMakeRange(lines.count - numberOfLinesToTake, numberOfLinesToTake)];
	
	[coder encodeObject:[lastFewLines componentsJoinedByString:@"\n"] forKey:ZGLoggerWindowText];
}

- (void)restoreStateWithCoder:(NSCoder *)coder
{
	[super restoreStateWithCoder:coder];
	
	self.loggerText = [NSMutableString stringWithString:[coder decodeObjectForKey:ZGLoggerWindowText]];
	[self writeLine:@"\t[Restored]" withDateFormatting:NO];
}

- (void)updateDisplay
{	
	[self.clearButton setEnabled:[[self.loggerTextView textStorage] mutableString].length > 0];
	
	if ([[self.loggerTextView textStorage] mutableString].length == 0)
	{
		[self.statusTextField setTextColor:[NSColor disabledControlTextColor]];
	}
	else
	{
		[self.statusTextField setTextColor:[NSColor controlTextColor]];
	}
	
	[self.statusTextField setStringValue:[NSString stringWithFormat:@"Logged %lu message%@", self.numberOfMessages, self.numberOfMessages == 1 ? @"" : @"s"]];
	
	[self invalidateRestorableState];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
	
	[[[self.loggerTextView textStorage] mutableString] setString:self.loggerText];
	[self.loggerTextView scrollRangeToVisible:NSMakeRange(self.loggerText.length, 0)];
	
	[self updateDisplay];
}

- (IBAction)clearText:(id)__unused sender
{
	[self.loggerText setString:@""];
	[[[self.loggerTextView textStorage] mutableString] setString:self.loggerText];
	self.numberOfMessages = 0;
	[self updateDisplay];
}

- (void)writeLine:(NSString *)text withDateFormatting:(BOOL)shouldIncludeDateFormatting
{
	if (text == nil)
	{
		text = @"(null)";
	}
	
	NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
	[dateFormatter setDateStyle:NSDateFormatterNoStyle];
	[dateFormatter setTimeStyle:NSDateFormatterMediumStyle];
	
	NSMutableString *newText = [[NSMutableString alloc] init];
	
	if (shouldIncludeDateFormatting)
	{
		[newText appendString:[dateFormatter stringFromDate:[NSDate date]]];
		[newText appendString:@": "];
	}
	[newText appendString:text];
	[newText appendString:@"\n"];
	
	[self.loggerText appendString:newText];
	[[[self.loggerTextView textStorage] mutableString] setString:self.loggerText];
	
	[self.loggerTextView scrollRangeToVisible:NSMakeRange(self.loggerText.length, 0)];
	
	self.numberOfMessages++;
	
	[self updateDisplay];
}

- (void)writeLine:(NSString *)text
{
	[self writeLine:text withDateFormatting:YES];
}

@end
