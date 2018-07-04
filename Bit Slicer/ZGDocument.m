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

#import "ZGDocument.h"
#import "ZGDocumentWindowController.h"
#import "ZGDocumentData.h"
#import "ZGSearchData.h"
#import "ZGVariable.h"
#import "ZGScriptManager.h"

@implementation ZGDocument
{
	ZGDocumentWindowController * _Nullable _windowController;
}

#pragma mark Document stuff

- (id)init
{
	self = [super init];
	if (self != nil)
	{
		_data = [[ZGDocumentData alloc] init];
		_searchData = [[ZGSearchData alloc] init];
	}
	return self;
}

+ (BOOL)autosavesInPlace
{
	// If user is running as root for some reason, disable autosaving
    return geteuid() != 0;
}

- (void)markChange
{
	[self updateChangeCount:NSChangeDone];
}

- (void)makeWindowControllers
{
	ZGDocumentWindowController *windowController = _makeDocumentWindowController();
	assert(windowController != nil);
	
	_windowController = windowController;
	[self addWindowController:windowController];
}

// Since there appears to be an AppKit bug where window controllers are removed *before* the app is asked if it really wants to terminate (if the document is marked dirty), we'll make a workaround for cleaning the document's state
- (void)removeWindowController:(NSWindowController *)windowController
{
	ZGDocumentWindowController *documentWindowController = (ZGDocumentWindowController *)windowController;
	[documentWindowController cleanup];
	
	[super removeWindowController:windowController];
}

- (NSFileWrapper *)fileWrapperOfType:(NSString *)__unused typeName error:(NSError * __autoreleasing *)__unused outError
{
	NSMutableData *writeData = [[NSMutableData alloc] init];
	NSKeyedArchiver *keyedArchiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:writeData];
	
	NSArray<ZGVariable *> *watchVariablesArrayToSave = nil;
	
	watchVariablesArrayToSave = _data.variables;
	
	[keyedArchiver
	 encodeObject:watchVariablesArrayToSave
	 forKey:ZGWatchVariablesArrayKey];
	
	[keyedArchiver
	 encodeObject:_data.desiredProcessInternalName != nil ? _data.desiredProcessInternalName : [NSNull null]
	 forKey:ZGProcessInternalNameKey];
    
	[keyedArchiver
	 encodeInt32:(int32_t)_data.selectedDatatypeTag
	 forKey:ZGSelectedDataTypeTag];
    
	[keyedArchiver
	 encodeInt32:(int32_t)_data.qualifierTag
	 forKey:ZGQualifierTagKey];
	
	[keyedArchiver
	 encodeInt32:(int32_t)_data.byteOrderTag
	 forKey:ZGByteOrderTagKey];
    
	[keyedArchiver
	 encodeInt32:(int32_t)_data.functionTypeTag
	 forKey:ZGFunctionTypeTagKey];
	
	[keyedArchiver
	 encodeInt32:_searchData.protectionMode
	 forKey:ZGProtectionModeKey];
    
	[keyedArchiver
	 encodeBool:_data.ignoreDataAlignment
	 forKey:ZGIgnoreDataAlignmentKey];
    
	[keyedArchiver
	 encodeBool:_searchData.shouldIncludeNullTerminator
	 forKey:ZGExactStringLengthKey];
    
	[keyedArchiver
	 encodeBool:_searchData.shouldIgnoreStringCase
	 forKey:ZGIgnoreStringCaseKey];
    
	[keyedArchiver
	 encodeObject:_data.beginningAddressStringValue
	 forKey:ZGBeginningAddressKey];
    
	[keyedArchiver
	 encodeObject:_data.endingAddressStringValue
	 forKey:ZGEndingAddressKey];
    
	[keyedArchiver
	 encodeObject:_data.lastEpsilonValue
	 forKey:ZGEpsilonKey];
    
	[keyedArchiver
	 encodeObject:_data.lastAboveRangeValue
	 forKey:ZGAboveValueKey];
    
	[keyedArchiver
	 encodeObject:_data.lastBelowRangeValue
	 forKey:ZGBelowValueKey];
    
	[keyedArchiver
	 encodeObject:_data.searchValue
	 forKey:ZGSearchStringValueKeyNew];
	
	[keyedArchiver finishEncoding];
	
	return [[NSFileWrapper alloc] initRegularFileWithContents:writeData];
}

- (NSString *)parseStringSafely:(NSString *)string
{
	return string != nil ? string : @"";
}

- (BOOL)readFromFileWrapper:(NSFileWrapper *)fileWrapper ofType:(NSString *)__unused typeName error:(NSError * __autoreleasing *)__unused outError
{
	NSData *readData = [fileWrapper regularFileContents];
	NSKeyedUnarchiver *keyedUnarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:readData];
	
	NSArray<ZGVariable *> *newVariables = [keyedUnarchiver decodeObjectOfClass:[NSArray class] forKey:ZGWatchVariablesArrayKey];
	if (newVariables != nil)
	{
		_data.variables = newVariables;
	}
	else
	{
		_data.variables = [NSArray array];
	}
	
	id desiredProcessInternalName = [keyedUnarchiver decodeObjectOfClass:[NSObject class] forKey:ZGProcessInternalNameKey];
	if (desiredProcessInternalName == [NSNull null] || ![(id<NSObject>)desiredProcessInternalName isKindOfClass:[NSString class]])
	{
		_data.desiredProcessInternalName = nil;
	}
	else
	{
		_data.desiredProcessInternalName = desiredProcessInternalName;
	}
	
	_data.selectedDatatypeTag = (NSInteger)[keyedUnarchiver decodeInt32ForKey:ZGSelectedDataTypeTag];
	_data.qualifierTag = (NSInteger)[keyedUnarchiver decodeInt32ForKey:ZGQualifierTagKey];
	_data.functionTypeTag = (NSInteger)[keyedUnarchiver decodeInt32ForKey:ZGFunctionTypeTagKey];
	_searchData.protectionMode = (ZGProtectionMode)[keyedUnarchiver decodeInt32ForKey:ZGProtectionModeKey];
	_data.ignoreDataAlignment = [keyedUnarchiver decodeBoolForKey:ZGIgnoreDataAlignmentKey];
	_searchData.shouldIncludeNullTerminator = [keyedUnarchiver decodeBoolForKey:ZGExactStringLengthKey];
	_searchData.shouldIgnoreStringCase = [keyedUnarchiver decodeBoolForKey:ZGIgnoreStringCaseKey];
	
	_data.beginningAddressStringValue = [self parseStringSafely:[keyedUnarchiver decodeObjectOfClass:[NSString class] forKey:ZGBeginningAddressKey]];
	_data.endingAddressStringValue = [self parseStringSafely:[keyedUnarchiver decodeObjectOfClass:[NSString class] forKey:ZGEndingAddressKey]];
	
	_data.byteOrderTag = [keyedUnarchiver decodeInt32ForKey:ZGByteOrderTagKey];
	if (_data.byteOrderTag == CFByteOrderUnknown)
	{
		_data.byteOrderTag = CFByteOrderGetCurrent();
	}
	
	NSString *searchValue = nil;
	NSString *newSearchStringValue = [keyedUnarchiver decodeObjectOfClass:[NSString class] forKey:ZGSearchStringValueKeyNew];
	if (newSearchStringValue == nil)
	{
		NSString *legacySearchStringValue = [keyedUnarchiver decodeObjectOfClass:[NSString class] forKey:ZGSearchStringValueKeyOld];
		searchValue = legacySearchStringValue;
	}
	else
	{
		searchValue = newSearchStringValue;
	}
	
	_data.searchValue = (searchValue != nil) ? searchValue : @"";
	
	NSString *lastEpsilonValue = [keyedUnarchiver decodeObjectOfClass:[NSString class] forKey:ZGEpsilonKey];
	_data.lastEpsilonValue = lastEpsilonValue != nil ? lastEpsilonValue : @"";
	
	_data.lastAboveRangeValue = [keyedUnarchiver decodeObjectOfClass:[NSString class] forKey:ZGAboveValueKey];
	_data.lastBelowRangeValue = [keyedUnarchiver decodeObjectOfClass:[NSString class] forKey:ZGBelowValueKey];
	
	return YES;
}

- (BOOL)revertToContentsOfURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError * __autoreleasing *)outError
{
	// Stop and remove all scripts before attempting to revert
	for (ZGVariable *variable in _data.variables)
	{
		if (variable.type == ZGScript)
		{
			if (variable.enabled)
			{
				[_windowController.scriptManager stopScriptForVariable:variable];
			}
			[_windowController.scriptManager removeScriptForVariable:variable];
		}
	}
	
	BOOL reverted = [super revertToContentsOfURL:absoluteURL ofType:typeName error:outError];
	if (reverted)
	{
		[_windowController loadDocumentUserInterface];
	}
	return reverted;
}

@end
