/* Copyright (c) 2005-2011, Peter Ammon
 * All rights reserved.
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE REGENTS AND CONTRIBUTORS BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

// This class is *largely* copied from HFLineCountingView.m - The major difference is that we draw according to a beginning offset

#import "ZGLineCountingView.h"
#import <HexFiend/HexFiend.h>
#import "ZGLineCountingRepresenter.h"
#import <math.h>

#define HFASSERT assert

#ifndef TIME_LINE_NUMBERS
#define TIME_LINE_NUMBERS 0
#endif

#ifndef check_malloc
#define check_malloc(x) ({ size_t _count = x; void* result = malloc(_count); if (! result) { fprintf(stderr, "Out of memory allocating %lu bytes\n", (unsigned long)_count); exit(EXIT_FAILURE); } result; })
#endif

@interface ZGLineCountingView (PrivateInheritedMethods)

- (void)getLineNumberFormatString:(char *)outString length:(NSUInteger)length;

@end

@implementation ZGLineCountingView

- (NSUInteger)characterCountForLineRange:(HFRange)range
{
	HFASSERT(range.length <= NSUIntegerMax);
	NSUInteger characterCount;
	
	NSUInteger lineCount = ll2l(range.length);
	const NSUInteger stride = self.bytesPerLine;
	ZGLineCountingRepresenter *rep = (ZGLineCountingRepresenter *)[self representer];
	HFLineNumberFormat format = [self lineNumberFormat];
	if (format == HFLineNumberFormatDecimal) {
		unsigned long long lineValue = HFProductULL(range.location, self.bytesPerLine) + [rep beginningMemoryAddress];
		characterCount = lineCount /* newlines */;
		while (lineCount--) {
			characterCount += HFCountDigitsBase10(lineValue);
			lineValue += stride;
		}
	}
	else if (format == HFLineNumberFormatHexadecimal) {
		characterCount = ([rep digitCount] + 1) * lineCount; // +1 for newlines
	}
	else {
		//characterCount = -1;
		characterCount = 0;
	}
	return characterCount;
}

- (NSString *)createLineStringForRange:(HFRange)range NS_RETURNS_RETAINED
{
	HFASSERT(range.length <= NSUIntegerMax);
	NSUInteger lineCount = ll2l(range.length);
	const NSUInteger stride = self.bytesPerLine;
	unsigned long long lineValue = HFProductULL(range.location, self.bytesPerLine) + [((ZGLineCountingRepresenter *)[self representer]) beginningMemoryAddress];
	NSUInteger characterCount = [self characterCountForLineRange:range];
	if (characterCount == 0)
	{
		NSLog(@"ERROR: Couldn't create line string for range");
		return nil;
	}
	char *buffer = check_malloc(characterCount);
	NSUInteger bufferIndex = 0;

	char formatString[64];
	[self getLineNumberFormatString:formatString length:sizeof formatString];

	while (lineCount--) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat-nonliteral"
		int charCount = sprintf(buffer + bufferIndex, formatString, lineValue);
#pragma clang diagnostic pop
		HFASSERT(charCount > 0);
		bufferIndex += (NSUInteger)charCount;
		buffer[bufferIndex++] = '\n';   
		lineValue += stride;
	}
	HFASSERT(bufferIndex == characterCount);
	
	// ownership is transferred
	NSString *string = [[NSString alloc] initWithBytesNoCopy:(void *)buffer length:bufferIndex encoding:NSASCIIStringEncoding freeWhenDone:YES];
	return string;
}

static inline int common_prefix_length(const char *a, const char *b)
{
	int i;
	for (i=0; ; i++) {
		char ac = a[i];
		char bc = b[i];
		if (ac != bc || ac == 0 || bc == 0) break;
	}
	return i;
}

/* Drawing with NSLayoutManager is necessary because the 10_2 typesetting behavior used by the old string drawing does the wrong thing for fonts like Bitstream Vera Sans Mono.  Also it's an optimization for drawing the shadow. */
- (void)drawLineNumbersWithClipLayoutManagerPerLine:(NSRect)clipRect
{
#if TIME_LINE_NUMBERS
	CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
#endif
	NSUInteger previousTextStorageCharacterCount = [textStorage length];
	
	CGFloat verticalOffset = ld2f(self.lineRangeToDraw.location - floorl(self.lineRangeToDraw.location));
	NSRect textRect = [self bounds];
	textRect.size.height = self.lineHeight;
	textRect.origin.y -= verticalOffset * self.lineHeight;
	unsigned long long lineIndex = HFFPToUL(floorl(self.lineRangeToDraw.location));
	unsigned long long lineValue = lineIndex * self.bytesPerLine + [((ZGLineCountingRepresenter *)[self representer]) beginningMemoryAddress];
	NSUInteger linesRemaining = ll2l(HFFPToUL(ceill(self.lineRangeToDraw.length + self.lineRangeToDraw.location) - floorl(self.lineRangeToDraw.location)));
	char previousBuff[256];
	int previousStringLength = (int)previousTextStorageCharacterCount;
	/* BOOL conversionResult = */
	[[textStorage string] getCString:previousBuff maxLength:sizeof previousBuff encoding:NSASCIIStringEncoding];
	//HFASSERT(conversionResult);
	while (linesRemaining--) {
		char formatString[64];
		[self getLineNumberFormatString:formatString length:sizeof formatString];
		   
		if (NSIntersectsRect(textRect, clipRect)) {
			NSString *replacementCharacters = nil;
			NSRange replacementRange;
			char buff[256];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat-nonliteral"
			int newStringLength = snprintf(buff, sizeof buff, formatString, lineValue);
#pragma clang diagnostic pop
			HFASSERT(newStringLength > 0);
			int prefixLength = common_prefix_length(previousBuff, buff);
			HFASSERT(prefixLength <= newStringLength);
			HFASSERT(prefixLength <= previousStringLength);
			replacementRange = NSMakeRange((NSUInteger)prefixLength, (NSUInteger)(previousStringLength - prefixLength));
			replacementCharacters = [[NSString alloc] initWithBytesNoCopy:buff + prefixLength length:(NSUInteger)(newStringLength - prefixLength) encoding:NSASCIIStringEncoding freeWhenDone:NO];
			NSUInteger glyphCount;
			[textStorage replaceCharactersInRange:replacementRange withString:replacementCharacters];
			if (previousTextStorageCharacterCount == 0) {
				NSDictionary *atts = [[NSDictionary alloc] initWithObjectsAndKeys:self.font, NSFontAttributeName, [NSColor colorWithCalibratedWhite:(CGFloat).1 alpha:(CGFloat).8], NSForegroundColorAttributeName, nil];
				[textStorage setAttributes:atts range:NSMakeRange(0, (NSUInteger)newStringLength)];
				[atts release];
			}
			glyphCount = [layoutManager numberOfGlyphs];
			if (glyphCount > 0) {
				CGFloat maxX = NSMaxX([layoutManager lineFragmentUsedRectForGlyphAtIndex:glyphCount - 1 effectiveRange:NULL]);
				[layoutManager drawGlyphsForGlyphRange:NSMakeRange(0, glyphCount) atPoint:NSMakePoint(textRect.origin.x + textRect.size.width - maxX, textRect.origin.y)];
			}
			previousTextStorageCharacterCount = (NSUInteger)newStringLength;
			[replacementCharacters release];
			memcpy(previousBuff, buff, (size_t)(newStringLength + 1));
			previousStringLength = newStringLength;
		}
		textRect.origin.y += self.lineHeight;
		lineIndex++;
		lineValue = HFSum(lineValue, self.bytesPerLine);
	}
#if TIME_LINE_NUMBERS
	CFAbsoluteTime endTime = CFAbsoluteTimeGetCurrent();
	NSLog(@"Line number time: %f", endTime - startTime);
#endif
}

- (void)drawLineNumbersWithClipStringDrawing:(NSRect)clipRect
{
	CGFloat verticalOffset = ld2f(self.lineRangeToDraw.location - floorl(self.lineRangeToDraw.location));
	NSRect textRect = [self bounds];
	textRect.size.height = self.lineHeight;
	textRect.size.width -= 5;
	textRect.origin.y -= verticalOffset * self.lineHeight + 1;
	unsigned long long lineIndex = HFFPToUL(floorl(self.lineRangeToDraw.location));
	unsigned long long lineValue = lineIndex * self.bytesPerLine + [((ZGLineCountingRepresenter *)[self representer]) beginningMemoryAddress];
	NSUInteger linesRemaining = ll2l(HFFPToUL(ceill(self.lineRangeToDraw.length + self.lineRangeToDraw.location) - floorl(self.lineRangeToDraw.location)));
	if (! textAttributes) {
		NSMutableParagraphStyle *mutableStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
		[mutableStyle setAlignment:NSRightTextAlignment];
		NSParagraphStyle *paragraphStyle = [mutableStyle copy];
		[mutableStyle release];
		textAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:self.font, NSFontAttributeName, [NSColor colorWithCalibratedWhite:(CGFloat).1 alpha:(CGFloat).8], NSForegroundColorAttributeName, paragraphStyle, NSParagraphStyleAttributeName, nil];
		[paragraphStyle release];
	}

	char formatString[64];
	[self getLineNumberFormatString:formatString length:sizeof formatString];

	while (linesRemaining--) {
		if (NSIntersectsRect(textRect, clipRect)) {
			char buff[256];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat-nonliteral"
			int newStringLength = snprintf(buff, sizeof buff, formatString, lineValue);
#pragma clang diagnostic pop
			HFASSERT(newStringLength > 0);
			NSString *string = [[NSString alloc] initWithBytesNoCopy:buff length:(NSUInteger)newStringLength encoding:NSASCIIStringEncoding freeWhenDone:NO];
			[string drawInRect:textRect withAttributes:textAttributes];
			[string release];
		}
		textRect.origin.y += self.lineHeight;
		lineIndex++;
		lineValue = HFSum(lineValue, self.bytesPerLine);
	}
}

@end
