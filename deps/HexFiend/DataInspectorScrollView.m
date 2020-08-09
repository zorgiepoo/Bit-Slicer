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
//  DataInspectorScrollView.m
//  HexFiend_2
//
//  Copyright © 2019 ridiculous_fish. All rights reserved.
//

#import "DataInspectorScrollView.h"

#import <HexFiend/HFFunctions.h>

@implementation DataInspectorScrollView

- (void)drawDividerWithClip:(NSRect)clipRect {
	NSColor *separatorColor = [NSColor lightGrayColor];
#if defined(MAC_OS_X_VERSION_10_14) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_14
	if (HFDarkModeEnabled()) {
		if (@available(macOS 10.14, *)) {
			separatorColor = [NSColor separatorColor];
		}
	}
#endif
	[separatorColor set];
	NSRect bounds = [self bounds];
	NSRect lineRect = bounds;
	lineRect.size.height = 1;
	NSRectFillUsingOperation(NSIntersectionRect(lineRect, clipRect), NSCompositeSourceOver);
}

- (void)drawRect:(NSRect)rect {
	if (!HFDarkModeEnabled()) {
		[[NSColor colorWithCalibratedWhite:(CGFloat).91 alpha:1] set];
		NSRectFillUsingOperation(rect, NSCompositeSourceOver);
	}
	
	if (HFDarkModeEnabled()) {
		[[NSColor colorWithCalibratedWhite:(CGFloat).09 alpha:1] set];
	} else {
		[[NSColor colorWithCalibratedWhite:(CGFloat).91 alpha:1] set];
	}
	NSRectFillUsingOperation(rect, NSCompositeSourceOver);
	[self drawDividerWithClip:rect];
}

@end
