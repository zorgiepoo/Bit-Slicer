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
//  DataInspectorPlusMinusButtonCell.m
//  HexFiend_2
//
//  Copyright © 2019 ridiculous_fish. All rights reserved.
//

#import "DataInspectorPlusMinusButtonCell.h"

// Don't want to include these macros, so not using them

#ifndef USE
#define USE(x) (void)(x)
#endif

@implementation DataInspectorPlusMinusButtonCell

- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	[self setBezelStyle:NSRoundRectBezelStyle];
	return self;
}

- (void)drawDataInspectorTitleWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
	const BOOL isPlus = [[self title] isEqual:@"+"];
	const unsigned char grayColor = 0x73;
	const unsigned char alpha = 0xFF;
#if __LITTLE_ENDIAN__
	const unsigned short X = (alpha << 8) | grayColor;
#else
	const unsigned short X = (grayColor << 8) | alpha ;
#endif
	const NSUInteger bytesPerPixel = sizeof X;
	const unsigned short plusData[] = {
	0,0,0,X,X,0,0,0,
	0,0,0,X,X,0,0,0,
	0,0,0,X,X,0,0,0,
	X,X,X,X,X,X,X,X,
	X,X,X,X,X,X,X,X,
	0,0,0,X,X,0,0,0,
	0,0,0,X,X,0,0,0,
	0,0,0,X,X,0,0,0
	};
	
	const unsigned short minusData[] = {
	0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,
	X,X,X,X,X,X,X,X,
	X,X,X,X,X,X,X,X,
	0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0
	};
	
	const unsigned char * const bitmapData = (const unsigned char *)(isPlus ? plusData : minusData);
	
	NSUInteger width = 8, height = 8;
	assert(width * height * bytesPerPixel == sizeof plusData);
	assert(width * height * bytesPerPixel == sizeof minusData);
	NSRect bitmapRect = NSMakeRect(NSMidX(cellFrame) - width/2, NSMidY(cellFrame) - height/2, width, height);
	bitmapRect = [controlView centerScanRect:bitmapRect];

	CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceGenericGray);
	CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, bitmapData, width * height * bytesPerPixel, NULL);
	CGImageRef image = CGImageCreate(width, height, CHAR_BIT, bytesPerPixel * CHAR_BIT, bytesPerPixel * width, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast, provider, NULL, YES, kCGRenderingIntentDefault);
	CGDataProviderRelease(provider);
	CGColorSpaceRelease(space);
	[[NSGraphicsContext currentContext] setCompositingOperation:NSCompositingOperationSourceOver];
	CGContextDrawImage([[NSGraphicsContext currentContext] graphicsPort], *(CGRect *)&bitmapRect, image);
	CGImageRelease(image);
}

- (NSRect)drawTitle:(NSAttributedString*)title withFrame:(NSRect)frame inView:(NSView*)controlView {
	/* Defeat title drawing by doing nothing */
	USE(title);
	USE(frame);
	USE(controlView);
	return NSZeroRect;
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
	[super drawWithFrame:cellFrame inView:controlView];
	[self drawDataInspectorTitleWithFrame:cellFrame inView:controlView];

}

@end
