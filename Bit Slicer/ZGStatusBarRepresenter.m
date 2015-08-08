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

// Originally derived from and extends HFStatusBarRepresenter.m
// Made alterations to include beginningMemoryAddress property as well as localizations

#import "ZGStatusBarRepresenter.h"

#define ZGStatusBarLocalizationTable @"[Code] Memory Viewer Status Bar"

@interface ZGStatusBarRepresenter (InheritedPrivateMethods)

- (NSString *)describeOffset:(unsigned long long)offset;
- (NSString *)describeLength:(unsigned long long)length;
- (NSString *)describeOffsetExcludingApproximate:(unsigned long long)offset;

@end

@interface HFStatusBarRepresenter (PrivateMethods)

- (void)updateString;

@end

@implementation ZGStatusBarRepresenter

- (NSString *)stringForEmptySelectionAtOffset:(unsigned long long)offset length:(unsigned long long)__unused length
{
	return [NSString stringWithFormat:NSLocalizedStringFromTable(@"emptySelectionFormat", ZGStatusBarLocalizationTable, nil), [self describeOffset:offset + _beginningMemoryAddress]];
}

- (NSString *)stringForSingleByteSelectionAtOffset:(unsigned long long)offset length:(unsigned long long)__unused length
{
	return [NSString stringWithFormat:NSLocalizedStringFromTable(@"singleByteSelectionFormat", ZGStatusBarLocalizationTable, nil), [self describeOffset:offset + _beginningMemoryAddress]];
}

- (NSString *)stringForSingleRangeSelection:(HFRange)range length:(unsigned long long)__unused length
{
	return [NSString stringWithFormat:NSLocalizedStringFromTable(@"singleRangeSelectionFormat", ZGStatusBarLocalizationTable, nil), [self describeLength:range.length], [self describeOffsetExcludingApproximate:range.location + _beginningMemoryAddress]];
}

- (NSString *)stringForMultipleSelectionsWithLength:(unsigned long long)multipleSelectionLength length:(unsigned long long)__unused length
{
	return [NSString stringWithFormat:NSLocalizedStringFromTable(@"multipleSelectionLengthFormat", ZGStatusBarLocalizationTable, nil), [self describeLength:multipleSelectionLength]];
}

- (void)setStatusMode:(HFStatusBarMode)mode
{
	if (mode == HFStatusModeHexadecimal)
	{
		[super setStatusMode:mode];
	}
}

- (void)updateString
{
	[super updateString];
}

@end
