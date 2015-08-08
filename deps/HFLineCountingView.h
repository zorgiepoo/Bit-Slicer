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

//
//  HFLineCountingView.h
//  HexFiend_2
//
//  Created by Peter Ammon on 11/26/07.
//  Copyright 2007 ridiculous_fish. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <HexFiend/HFLineCountingRepresenter.h>

@interface HFLineCountingView : NSView
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-interface-ivars"
	NSFont *font;
	CGFloat lineHeight;
	HFFPRange lineRangeToDraw;
	NSLayoutManager *layoutManager;
	NSTextStorage *textStorage;
	NSTextContainer *textContainer;
	NSDictionary *textAttributes;
	HFLineCountingRepresenter *representer; //not retained
	
	NSUInteger bytesPerLine;
	unsigned long long storedLineIndex;
	NSUInteger storedLineCount;
	HFLineNumberFormat lineNumberFormat;
	BOOL useStringDrawingPath;
#pragma clang diagnostic pop
}

- (void)setFont:(NSFont *)val;
- (NSFont *)font;

- (void)setLineHeight:(CGFloat)height;
- (CGFloat)lineHeight;

- (void)setLineRangeToDraw:(HFFPRange)range;
- (HFFPRange)lineRangeToDraw;

- (void)setBytesPerLine:(NSUInteger)val;
- (NSUInteger)bytesPerLine;

- (void)setLineNumberFormat:(HFLineNumberFormat)format;
- (HFLineNumberFormat)lineNumberFormat;

- (void)setRepresenter:(HFLineCountingRepresenter *)rep;
- (HFLineCountingRepresenter *)representer;

+ (NSUInteger)digitsRequiredToDisplayLineNumber:(unsigned long long)lineNumber inFormat:(HFLineNumberFormat)format;

@end
