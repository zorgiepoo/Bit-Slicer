/*
 * Copyright (c) 2015 Mayur Pawashe
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

#define ZGLocalizedStringFromAboutWindowTable(string) NSLocalizedStringFromTable((string), @"[Code] About Window", nil)

#import "ZGAboutWindowController.h"
#import "ZGAppUpdaterController.h"
#import "ZGNullability.h"

@implementation ZGAboutWindowController
{
	IBOutlet NSTextView *_textView;
	IBOutlet NSButton *_creditsAndAcknowledgementsButton;
	IBOutlet NSTextField *_versionAndBuildTextField;
	BOOL _isShowingAcknowledgements;
}

- (NSString *)windowNibName
{
	return @"About Window";
}

- (void)windowDidLoad
{
	[super windowDidLoad];
	[self showCredits];
	[self showVersion];
	[_versionAndBuildTextField setSelectable:YES];
}

- (void)showVersion
{
	NSBundle *mainBundle = [NSBundle mainBundle];
	if (mainBundle == nil) return;
	
	NSString *shortVersion = [mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
	if (shortVersion == nil) return;
	
	NSString *bundleVersionKey = (__bridge NSString *)kCFBundleVersionKey;
	NSString *buildNumber = [mainBundle objectForInfoDictionaryKey:bundleVersionKey];
	if (buildNumber == nil) return;
	
	[_versionAndBuildTextField setStringValue:[NSString stringWithFormat:@"%@ (%@)", shortVersion, buildNumber]];
}

#define VERSION_HISTORY_URL @"https://zgcoder.net/bitslicer/update/releasenotes.html"
#define VERSION_HISTORY_ALPHA_URL @"https://zgcoder.net/bitslicer/update/releasenotes_alpha.html"

- (IBAction)viewVersionHistory:(id)__unused sender
{
	NSString *urlString = ![ZGAppUpdaterController runningAlpha] ? VERSION_HISTORY_URL : VERSION_HISTORY_ALPHA_URL;
	NSURL *versionHistoryURL = [NSURL URLWithString:urlString];
	if (versionHistoryURL != nil)
	{
		[[NSWorkspace sharedWorkspace] openURL:versionHistoryURL];
	}
}

- (IBAction)toggleShowingCreditsAndAcknowledgements:(id)__unused sender
{
	_isShowingAcknowledgements = !_isShowingAcknowledgements;
	
	if (_isShowingAcknowledgements)
	{
		[self showAcknowledgements];
	}
	else
	{
		[self showCredits];
	}
	
	[_textView scrollRangeToVisible:NSMakeRange(0, 1)];
}

- (void)showCredits
{
	NSString *creditsPath = [[NSBundle mainBundle] pathForResource:@"Credits" ofType:@"rtf"];
	if (creditsPath == nil) return;
	
	NSAttributedString *attributedCredits = [[NSAttributedString alloc] initWithPath:creditsPath documentAttributes:NULL];
	if (attributedCredits == nil) return;
	
	[_textView.textStorage setAttributedString:attributedCredits];
	_textView.textColor = [NSColor textColor];
	[_creditsAndAcknowledgementsButton setTitle:ZGLocalizedStringFromAboutWindowTable(@"acknowledgements")];
}

- (void)showAcknowledgements
{
	NSURL *licenseURL = [[NSBundle mainBundle] URLForResource:@"LICENSE" withExtension:@""];
	if (licenseURL == nil) return;
	
	NSError *readLicenseError = nil;
	NSString *licenseString = [[NSString alloc] initWithContentsOfURL:licenseURL encoding:NSUTF8StringEncoding error:&readLicenseError];
	
	if (licenseString == nil)
	{
		NSLog(@"Error reading LICENSE: %@", readLicenseError);
		return;
	}
	
	NSMutableAttributedString *attributedLicense = [[NSMutableAttributedString alloc] init];
	for (NSString *line in [licenseString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]])
	{
		if ([line hasPrefix:@"=="])
		{
			NSString *newLine = [[[line stringByReplacingOccurrencesOfString:@"==" withString:@""] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] stringByAppendingString:@"\n"];
			
			NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:newLine];
			[attributedString beginEditing];
			[attributedString applyFontTraits:NSBoldFontMask range:NSMakeRange(0, attributedString.length - 1)];
			[attributedString endEditing];
			
			[attributedLicense appendAttributedString:attributedString];
		}
		else if ([line hasPrefix:@"https://"])
		{
			NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:[line stringByAppendingString:@"\n"]];
			
			[attributedString addAttribute:NSLinkAttributeName value:line range:NSMakeRange(0, attributedString.length - 1)];
			[attributedLicense appendAttributedString:attributedString];
		}
		else if ([line hasPrefix:@"* "])
		{
			NSString *newLine = [[@"•" stringByAppendingString:[line substringFromIndex:1]] stringByAppendingString:@"\n"];
			[attributedLicense appendAttributedString:[[NSAttributedString alloc] initWithString:newLine]];
		}
		else if ([line hasPrefix:@"THIS SOFTWARE IS PROVIDED "] || [line hasPrefix:@"THE SOFTWARE IS PROVIDED "])
		{
			NSString *newLine = [line stringByAppendingString:@"\n"];
			
			NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:newLine];
			[attributedString beginEditing];
			[attributedString applyFontTraits:NSItalicFontMask range:NSMakeRange(0, attributedString.length - 1)];
			[attributedString endEditing];
			
			[attributedLicense appendAttributedString:attributedString];
		}
		else
		{
			[attributedLicense appendAttributedString:[[NSAttributedString alloc] initWithString:[line stringByAppendingString:@"\n"]]];
		}
	}
	
	[_textView.textStorage setAttributedString:attributedLicense];
	_textView.textColor = [NSColor textColor];
	[_creditsAndAcknowledgementsButton setTitle:ZGLocalizedStringFromAboutWindowTable(@"credits")];
}

@end
