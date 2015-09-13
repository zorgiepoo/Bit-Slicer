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
#import "ZGSearchProgressDelegate.h"
#import "ZGVariableTypes.h"
#import "ZGSearchFunctions.h"

#define USER_INTERFACE_UPDATE_TIME_INTERVAL	 0.33

@class ZGSearchProgress;
@class ZGSearchResults;
@class ZGDocumentWindowController;

#define MAX_NUMBER_OF_VARIABLES_TO_FETCH ((NSUInteger)1000)

NS_ASSUME_NONNULL_BEGIN

@interface ZGDocumentSearchController : NSObject <ZGSearchProgressDelegate>

+ (BOOL)hasStoredValueTokenFromExpression:(NSString *)expression isLinearlyExpressed:(nullable BOOL *)isLinearlyExpressedReference;
+ (BOOL)hasStoredValueTokenFromExpression:(NSString *)expression;

- (id)initWithWindowController:(ZGDocumentWindowController *)windowController;

@property (nonatomic, nullable) ZGSearchResults *searchResults;
@property (nonatomic, readonly) ZGSearchProgress *searchProgress;

- (BOOL)canStartTask;
- (BOOL)canCancelTask;
- (void)cancelTask;
- (void)prepareTask;
- (void)resumeFromTaskAndMakeSearchFieldFirstResponder:(BOOL)shouldMakeSearchFieldFirstResponder;
- (void)resumeFromTask;

- (void)fetchNumberOfVariables:(NSUInteger)numberOfVariables;
- (void)fetchVariablesFromResults;

- (void)searchVariablesWithString:(NSString *)searchStringValue withDataType:(ZGVariableType)dataType functionType:(ZGFunctionType)functionType allowsNarrowing:(BOOL)allowsNarrowing;
- (void)storeAllValues;

- (void)cleanUp;

@end

NS_ASSUME_NONNULL_END
