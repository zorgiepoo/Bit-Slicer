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

#import "ZGLoggerWindowController.h"

#define ZGLoggerWindowText @"ZGLoggerWindowText"
#define MIN_LOG_LINES_TO_RESTORE 50U

#define ZGLocalizedStringFromLoggerWindowTable(string) NSLocalizedStringFromTable((string), @"[Code] Logger Window", nil)

@implementation ZGLoggerWindowController
{
	NSMutableString * _Nonnull _loggerText;
	NSUInteger _numberOfMessages;
	
	IBOutlet NSTextView *_loggerTextView;
	IBOutlet NSButton *_clearButton;
	IBOutlet NSTextField *_statusTextField;
}

- (id)init
{
	self = [super init];
	if (self != nil)
	{
		_loggerText = [[NSMutableString alloc] init];
	}
	return self;
}

- (NSString *)windowNibName
{
	return @"Logs Window";
}

- (void)encodeRestorableStateWithCoder:(NSCoder *)coder
{
    [super encodeRestorableStateWithCoder:coder];
	
	NSArray<NSString *> *lines = [_loggerText componentsSeparatedByString:@"\n"];
	NSUInteger numberOfLinesToTake = MIN(MIN_LOG_LINES_TO_RESTORE, lines.count);
	NSArray<NSString *> *lastFewLines = [lines subarrayWithRange:NSMakeRange(lines.count - numberOfLinesToTake, numberOfLinesToTake)];
	
	[coder encodeObject:[lastFewLines componentsJoinedByString:@"\n"] forKey:ZGLoggerWindowText];
}

- (void)restoreStateWithCoder:(NSCoder *)coder
{
	[super restoreStateWithCoder:coder];
	
	NSString *restoredText = [coder decodeObjectOfClass:[NSString class] forKey:ZGLoggerWindowText];
	
	_loggerText = [NSMutableString stringWithString:restoredText != nil ? restoredText : @""];
	if (restoredText != nil)
	{
		[self writeLine:ZGLocalizedStringFromLoggerWindowTable(@"restoredText") withDateFormatting:NO];
	}
}

- (void)updateDisplay
{	
	[_clearButton setEnabled:[[_loggerTextView textStorage] mutableString].length > 0];
	
	if ([[_loggerTextView textStorage] mutableString].length == 0)
	{
		[_statusTextField setTextColor:[NSColor disabledControlTextColor]];
	}
	else
	{
		[_statusTextField setTextColor:[NSColor controlTextColor]];
	}
	
	[_statusTextField setStringValue:[NSString stringWithFormat:ZGLocalizedStringFromLoggerWindowTable(@"loggedMessagesFormat"), _numberOfMessages]];
	
	[self invalidateRestorableState];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
	
	[[[_loggerTextView textStorage] mutableString] setString:_loggerText];
	[[_loggerTextView textStorage] setForegroundColor:[NSColor textColor]];
	[_loggerTextView scrollRangeToVisible:NSMakeRange(_loggerText.length, 0)];
	
	[self updateDisplay];
}

- (IBAction)clearText:(id)__unused sender
{
	[_loggerText setString:@""];
	[[[_loggerTextView textStorage] mutableString] setString:_loggerText];
	[[_loggerTextView textStorage] setForegroundColor:[NSColor textColor]];
	_numberOfMessages = 0;
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
	
	[_loggerText appendString:newText];
	[[[_loggerTextView textStorage] mutableString] setString:_loggerText];
	[[_loggerTextView textStorage] setForegroundColor:[NSColor textColor]];
	
	[_loggerTextView scrollRangeToVisible:NSMakeRange(_loggerText.length, 0)];
	
	_numberOfMessages++;
	
	[self updateDisplay];
}

- (void)writeLine:(NSString *)text
{
	[self writeLine:text withDateFormatting:YES];
}

@end
