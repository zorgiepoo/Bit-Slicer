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

#import "ZGLocalization.h"
#import "NSArrayAdditions.h"

static void ZGAdjustWindowAndTableColumnByWidthDelta(NSWindow * _Nullable window, NSTableColumn *tableColumn, CGFloat widthDelta)
{
	tableColumn.maxWidth += widthDelta;
	tableColumn.width += widthDelta;
	tableColumn.minWidth += widthDelta;
	
	if (window != nil)
	{
		NSSize minSize = window.minSize;
		minSize.width += widthDelta;
		window.minSize = minSize;
		
		NSRect frame = window.frame;
		frame.size = NSMakeSize(frame.size.width + widthDelta, frame.size.height);
		[window setFrame:frame display:YES];
	}
}

void _ZGAdjustLocalizableWidthsForWindowAndTableColumns(NSWindow *window, NSArray<NSTableColumn *> *tableColumns, NSDictionary<ZGLocalizationLanguage, ZGLocalizationWidths> *deltaWidthsDictionary)
{
	NSString *preferredLanguage =
	[[NSLocale preferredLanguages] zgFirstObjectThatMatchesCondition:^BOOL(NSString *language) {
		return [language isEqualToString:@"en"] || deltaWidthsDictionary[language] != nil;
	}];
	
	if (preferredLanguage != nil)
	{
		NSArray<NSNumber *> *deltaWidths = deltaWidthsDictionary[preferredLanguage];
		if (deltaWidths != nil)
		{
			[tableColumns enumerateObjectsUsingBlock:^(NSTableColumn *tableColumn, NSUInteger tableColumnIndex, __unused BOOL *stop) {
				NSNumber *deltaWidth = deltaWidths[tableColumnIndex];
				assert([deltaWidth isKindOfClass:[NSNumber class]]);
				ZGAdjustWindowAndTableColumnByWidthDelta(window, tableColumn, deltaWidth.doubleValue);
			}];
		}
	}
}

void ZGAdjustLocalizableWidthsForWindowAndTableColumns(NSWindow *window, NSArray<NSTableColumn *> *tableColumns, NSDictionary<ZGLocalizationLanguage, ZGLocalizationWidths> *deltaWidthsDictionary)
{
	_ZGAdjustLocalizableWidthsForWindowAndTableColumns(window, tableColumns, deltaWidthsDictionary);
}

void ZGAdjustLocalizableWidthsForTableColumns(NSArray<NSTableColumn *> *tableColumns, NSDictionary<ZGLocalizationLanguage, ZGLocalizationWidths> *deltaWidthsDictionary)
{
	_ZGAdjustLocalizableWidthsForWindowAndTableColumns(nil, tableColumns, deltaWidthsDictionary);
}
