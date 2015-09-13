/*
 * Copyright (c) 2012 Mayur Pawashe
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

#import <Foundation/Foundation.h>
#import "ZGMemoryTypes.h"
#import "ZGVariable.h"

#define SIGNED_BUTTON_CELL_TAG 0

NS_ASSUME_NONNULL_BEGIN

extern NSString *ZGScriptIndentationUsingTabsKey;

@class ZGDocumentWindowController;
@class ZGProcess;

@interface ZGVariableController : NSObject

- (id)initWithWindowController:(ZGDocumentWindowController *)windowController;

- (void)freezeVariables;

+ (void)copyVariablesToPasteboard:(NSArray<ZGVariable *> *)variables;
+ (void)copyVariableAddress:(ZGVariable *)variable;

- (void)copyVariables;
- (void)copyAddress;
- (void)pasteVariables;

- (void)clear;
- (void)clearSearch;
- (BOOL)canClearSearch;
- (void)removeVariablesAtRowIndexes:(NSIndexSet *)rowIndexes;
- (void)removeSelectedSearchValues;
- (void)disableHarmfulVariables:(NSArray<ZGVariable *> *)variables;
- (void)addVariable:(nullable id)sender;
- (void)addVariables:(NSArray<ZGVariable *> *)variables atRowIndexes:(NSIndexSet *)rowIndexes;

- (void)nopVariables:(NSArray<ZGVariable *> *)variables;

- (void)changeVariable:(ZGVariable *)variable newDescription:(NSAttributedString *)newDescription;
- (void)changeVariable:(ZGVariable *)variable newType:(ZGVariableType)type newSize:(ZGMemorySize)size;
- (void)changeVariable:(ZGVariable *)variable newValue:(NSString *)stringObject shouldRecordUndo:(BOOL)recordUndoFlag;
- (void)changeVariableEnabled:(BOOL)enabled rowIndexes:(NSIndexSet *)rowIndexes;

- (void)relativizeVariables:(NSArray<ZGVariable *> *)variables;
+ (void)annotateVariables:(NSArray<ZGVariable *> *)variables process:(ZGProcess *)process;

- (void)editVariables:(NSArray<ZGVariable *> *)variables newValues:(NSArray<NSString *> *)newValues;
- (void)editVariable:(ZGVariable *)variable addressFormula:(NSString *)newAddressFormula;
- (void)editVariables:(NSArray<ZGVariable *> *)variables requestedSizes:(NSArray<NSNumber *> *)requestedSizes;

@end

NS_ASSUME_NONNULL_END
