/*
 * Created by Mayur Pawashe on 10/25/09.
 *
 * Copyright (c) 2012 zgcoder
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

@interface ZGDocument ()

@property (nonatomic) ZGDocumentWindowController *windowController;

@end

@implementation ZGDocument

#pragma mark Document stuff

- (id)init
{
	self = [super init];
	if (self)
	{
		self.data = [[ZGDocumentData alloc] init];
		self.searchData = [[ZGSearchData alloc] init];
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
	self.windowController = [[ZGDocumentWindowController alloc] initWithDocument:self];
	
	[self addWindowController:self.windowController];
}

- (NSFileWrapper *)fileWrapperOfType:(NSString *)__unused typeName error:(NSError * __autoreleasing *)__unused outError
{
	NSMutableData *writeData = [[NSMutableData alloc] init];
	NSKeyedArchiver *keyedArchiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:writeData];
	
	NSArray *watchVariablesArrayToSave = nil;
	
	watchVariablesArrayToSave = self.data.variables;
	
	[keyedArchiver
	 encodeObject:watchVariablesArrayToSave
	 forKey:ZGWatchVariablesArrayKey];
	
	[keyedArchiver
	 encodeObject:self.data.desiredProcessInternalName != nil ? self.data.desiredProcessInternalName : [NSNull null]
	 forKey:ZGProcessInternalNameKey];
    
	[keyedArchiver
	 encodeInt32:(int32_t)self.data.selectedDatatypeTag
	 forKey:ZGSelectedDataTypeTag];
    
	[keyedArchiver
	 encodeInt32:(int32_t)self.data.qualifierTag
	 forKey:ZGQualifierTagKey];
	
	[keyedArchiver
	 encodeInt32:(int32_t)self.data.byteOrderTag
	 forKey:ZGByteOrderTagKey];
    
	[keyedArchiver
	 encodeInt32:(int32_t)self.data.functionTypeTag
	 forKey:ZGFunctionTypeTagKey];
	
	[keyedArchiver
	 encodeInt32:self.searchData.protectionMode
	 forKey:ZGProtectionModeKey];
    
	[keyedArchiver
	 encodeBool:self.data.ignoreDataAlignment
	 forKey:ZGIgnoreDataAlignmentKey];
    
	[keyedArchiver
	 encodeBool:self.searchData.shouldIncludeNullTerminator
	 forKey:ZGExactStringLengthKey];
    
	[keyedArchiver
	 encodeBool:self.searchData.shouldIgnoreStringCase
	 forKey:ZGIgnoreStringCaseKey];
    
	[keyedArchiver
	 encodeObject:self.data.beginningAddressStringValue
	 forKey:ZGBeginningAddressKey];
    
	[keyedArchiver
	 encodeObject:self.data.endingAddressStringValue
	 forKey:ZGEndingAddressKey];
    
	[keyedArchiver
	 encodeObject:self.data.lastEpsilonValue
	 forKey:ZGEpsilonKey];
    
	[keyedArchiver
	 encodeObject:self.data.lastAboveRangeValue
	 forKey:ZGAboveValueKey];
    
	[keyedArchiver
	 encodeObject:self.data.lastBelowRangeValue
	 forKey:ZGBelowValueKey];
    
	[keyedArchiver
	 encodeObject:self.data.searchValue
	 forKey:ZGSearchValueKey];
	
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
	
	NSArray *newVariables = [keyedUnarchiver decodeObjectForKey:ZGWatchVariablesArrayKey];
	
	if (newVariables != nil)
	{
		self.data.variables = newVariables;
	}
	else
	{
		self.data.variables = [NSArray array];
	}
	
	self.data.desiredProcessInternalName = [keyedUnarchiver decodeObjectForKey:ZGProcessInternalNameKey];
	if ((id)self.data.desiredProcessInternalName == [NSNull null])
	{
		self.data.desiredProcessInternalName = nil;
	}
	
	self.data.selectedDatatypeTag = (NSInteger)[keyedUnarchiver decodeInt32ForKey:ZGSelectedDataTypeTag];
	self.data.qualifierTag = (NSInteger)[keyedUnarchiver decodeInt32ForKey:ZGQualifierTagKey];
	self.data.functionTypeTag = (NSInteger)[keyedUnarchiver decodeInt32ForKey:ZGFunctionTypeTagKey];
	self.searchData.protectionMode = (ZGProtectionMode)[keyedUnarchiver decodeInt32ForKey:ZGProtectionModeKey];
	self.data.ignoreDataAlignment = [keyedUnarchiver decodeBoolForKey:ZGIgnoreDataAlignmentKey];
	self.searchData.shouldIncludeNullTerminator = [keyedUnarchiver decodeBoolForKey:ZGExactStringLengthKey];
	self.searchData.shouldIgnoreStringCase = [keyedUnarchiver decodeBoolForKey:ZGIgnoreStringCaseKey];
	self.data.beginningAddressStringValue = [self parseStringSafely:[keyedUnarchiver decodeObjectForKey:ZGBeginningAddressKey]];
	self.data.endingAddressStringValue = [self parseStringSafely:[keyedUnarchiver decodeObjectForKey:ZGEndingAddressKey]];
	
	self.data.byteOrderTag = [keyedUnarchiver decodeInt32ForKey:ZGByteOrderTagKey];
	if (self.data.byteOrderTag == CFByteOrderUnknown)
	{
		self.data.byteOrderTag = CFByteOrderGetCurrent();
	}
	
	id searchValue = [keyedUnarchiver decodeObjectForKey:ZGSearchValueKey];
	if (searchValue == nil)
	{
		NSString *legacySearchStringValue = [keyedUnarchiver decodeObjectForKey:ZGSearchStringValueKey];
		if (legacySearchStringValue != nil)
		{
			searchValue = @[legacySearchStringValue];
		}
	}
	if (searchValue != nil)
	{
		self.data.searchValue = searchValue;
	}
	else
	{
		self.data.searchValue = @[@""];
	}
	
	self.data.lastEpsilonValue = [keyedUnarchiver decodeObjectForKey:ZGEpsilonKey];
	self.data.lastAboveRangeValue = [keyedUnarchiver decodeObjectForKey:ZGAboveValueKey];
	self.data.lastBelowRangeValue = [keyedUnarchiver decodeObjectForKey:ZGBelowValueKey];
	
	return YES;
}

- (BOOL)revertToContentsOfURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError * __autoreleasing *)outError
{
	// Stop and remove all scripts before attempting to revert
	for (ZGVariable *variable in self.data.variables)
	{
		if (variable.type == ZGScript)
		{
			if (variable.enabled)
			{
				[self.windowController.scriptManager stopScriptForVariable:variable];
			}
			[self.windowController.scriptManager removeScriptForVariable:variable];
		}
	}
	
	BOOL reverted = [super revertToContentsOfURL:absoluteURL ofType:typeName error:outError];
	if (reverted)
	{
		[self.windowController loadDocumentUserInterface];
	}
	return reverted;
}

@end
