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

#import <HexFiend/HexFiend.h>

//notification posted when our DataInspector's height changes.  Has a single key "height" which is the new height for the scroll view
extern NSString * const DataInspectorDidChangeRowCount;

// notification posted when all rows are deleted
extern NSString * const DataInspectorDidDeleteAllRows;

@interface DataInspectorRepresenter : HFRepresenter

- (void)loadDefaultInspectors;

- (NSUInteger)rowCount;

- (IBAction)addRow:(id)sender;
- (IBAction)removeRow:(id)sender;
- (IBAction)doubleClickedTable:(id)sender;
- (void)resizeTableViewAfterChangingRowCount;

@end

@interface DataInspectorScrollView : NSScrollView
@end

@interface DataInspectorPlusMinusButtonCell : NSButtonCell
@end

@interface DataInspectorTableView : NSTableView
@end
