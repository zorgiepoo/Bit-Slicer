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

#import "ZGVerticalScrollerRepresenter.h"

@implementation ZGVerticalScrollerRepresenter

// Fixes a bug in Hex Fiend's scrollByLines: where clicking the up button in the scroll wheel would scroll
// all the way down
- (void)scrollByLines:(long long)linesInt
{
	if (linesInt == 0) return;
	
	long double lines = HFULToFP((unsigned long long)linesInt);
	
	HFController *controller = [self controller];
	//HFASSERT(controller != NULL);
	HFFPRange displayedRange = [[self controller] displayedLineRange];
	if (linesInt < 0) {
		displayedRange.location += MIN((long double)linesInt, displayedRange.location);
	}
	else {
		long double availableLines = HFULToFP([controller totalLineCount]);
		displayedRange.location = MIN(availableLines - displayedRange.length, displayedRange.location + lines);
	}
	[controller setDisplayedLineRange:displayedRange];
}

@end
