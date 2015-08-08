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

// Derived from HexFiend's MyDocument.m

#import "ZGTextViewLayoutController.h"
#import "DataInspectorRepresenter.h"

@implementation ZGTextViewLayoutController

- (NSSize)minimumWindowFrameSizeForProposedSize:(NSSize)frameSize textView:(HFTextView *)textView
{
	NSView *layoutView = [textView.layoutRepresenter view];
	NSSize proposedSizeInLayoutCoordinates = [layoutView convertSize:frameSize fromView:nil];
	CGFloat resultingWidthInLayoutCoordinates = [textView.layoutRepresenter minimumViewWidthForLayoutInProposedWidth:proposedSizeInLayoutCoordinates.width];
	NSSize resultSize = [layoutView convertSize:NSMakeSize(resultingWidthInLayoutCoordinates, proposedSizeInLayoutCoordinates.height) toView:nil];
	return resultSize;
}

- (void)relayoutAndResizeWindow:(NSWindow *)window preservingBytesPerLineWithTextView:(HFTextView *)textView
{
	const NSUInteger bytesMultiple = 4;
	NSUInteger remainder = textView.controller.bytesPerLine % bytesMultiple;
	NSUInteger bytesPerLineRoundedUp = (remainder == 0) ? (textView.controller.bytesPerLine) : (textView.controller.bytesPerLine + bytesMultiple - remainder);
	NSUInteger bytesPerLineRoundedDown = bytesPerLineRoundedUp - bytesMultiple;
	
	// Pick bytes per line that is closest to what we already have and is multiple of bytesMultiple
	NSUInteger bytesPerLine = (bytesPerLineRoundedUp - textView.controller.bytesPerLine) > (textView.controller.bytesPerLine - bytesPerLineRoundedDown) ? bytesPerLineRoundedDown : bytesPerLineRoundedUp;
	
	NSRect windowFrame = [window frame];
	NSView *layoutView = [textView.layoutRepresenter view];
	CGFloat minViewWidth = [textView.layoutRepresenter minimumViewWidthForBytesPerLine:bytesPerLine];
	CGFloat minWindowWidth = [layoutView convertSize:NSMakeSize(minViewWidth, 1) toView:nil].width;
	windowFrame.size.width = minWindowWidth;
	[window setFrame:windowFrame display:YES];
}

// Relayout the window without increasing its window frame size
- (void)relayoutAndResizeWindow:(NSWindow *)window preservingFrameWithTextView:(HFTextView *)textView
{
	NSRect windowFrame = [window frame];
	windowFrame.size = [self minimumWindowFrameSizeForProposedSize:windowFrame.size textView:textView];
	[window setFrame:windowFrame display:YES];
}

- (void)dataInspectorDeletedAllRows:(DataInspectorRepresenter *)inspector window:(NSWindow *)window textView:(HFTextView *)textView
{
	[textView.controller removeRepresenter:inspector];
	[[textView layoutRepresenter] removeRepresenter:inspector];
	[self relayoutAndResizeWindow:window preservingFrameWithTextView:textView];
}

// Called when our data inspector changes its size (number of rows)
- (void)dataInspectorChangedRowCount:(DataInspectorRepresenter *)inspector withHeight:(NSNumber *)height textView:(HFTextView *)textView
{
	NSView *dataInspectorView = [inspector view];
	CGFloat newHeight = height.doubleValue;
	NSSize size = [dataInspectorView frame].size;
	size.height = newHeight;
	size.width = 1; // this is a hack that makes the data inspector's width actually resize..
	[dataInspectorView setFrameSize:size];
	
	[textView.layoutRepresenter performLayout];
}

@end
