/*
 * Copyright (c) 2013 Mayur Pawashe
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

#import "ZGDocumentOptionsViewController.h"
#import "ZGDocument.h"
#import "ZGDocumentData.h"
#import "ZGSearchData.h"
#import "ZGVariable.h"

@implementation ZGDocumentOptionsViewController
{
	__weak ZGDocument * _Nullable _document;
	ZGDocumentData * _Nonnull _documentData;
	ZGSearchData * _Nonnull _searchData;
	
	IBOutlet NSButton *_ignoreDataAlignmentCheckbox;
	IBOutlet NSButton *_includeSharedMemoryCheckbox;
	IBOutlet NSTextField *_beginningAddressTextField;
	IBOutlet NSTextField *_endingAddressTextField;
	
	IBOutlet NSButton *_includeOnlyStaticStackAndHeapCheckbox;
	IBOutlet NSButton *_excludeStaticSystemLibrariesCheckbox;
	IBOutlet NSButton *_stopTraversingAtFirstStaticAddressCheckbox;
}

- (id)initWithDocument:(ZGDocument *)document
{
	self = [self initWithNibName:@"Search Options" bundle:nil];
	if (self != nil)
	{
		_document = document;
		_documentData = document.data;
		_searchData = document.searchData;
	}
	return self;
}

- (void)reloadInterface
{
	[_ignoreDataAlignmentCheckbox setState:_documentData.ignoreDataAlignment];
	[_includeSharedMemoryCheckbox setState:_searchData.includeSharedMemory];
	_beginningAddressTextField.stringValue = _documentData.beginningAddressStringValue;
	_endingAddressTextField.stringValue = _documentData.endingAddressStringValue;
	
	_stopTraversingAtFirstStaticAddressCheckbox.state = _searchData.indirectStopAtStaticAddresses;
	_includeOnlyStaticStackAndHeapCheckbox.state = _documentData.indirectFilterHeapAndStackData;
	_excludeStaticSystemLibrariesCheckbox.state = _documentData.indirectExcludeStaticDataFromSystemLibraries;
}

- (void)loadView
{
	[super loadView];
	
	[self reloadInterface];
}

- (IBAction)changeIgnoreDataAlignment:(id)sender
{
	_documentData.ignoreDataAlignment = ([(NSCell *)sender state] == NSControlStateValueOn);
	
	ZGDocument *document = _document;
	[document markChange];
}

- (IBAction)changeIncludeSharedMemory:(id)sender
{
	_searchData.includeSharedMemory = ([(NSCell *)sender state] == NSControlStateValueOn);
	
	ZGDocument *document = _document;
	[document markChange];
}

- (IBAction)changeBeginningAddress:(id)__unused sender
{
	if (![_documentData.beginningAddressStringValue isEqualToString:_beginningAddressTextField.stringValue])
	{
		_documentData.beginningAddressStringValue = _beginningAddressTextField.stringValue;
		
		ZGDocument *document = _document;
		[document markChange];
	}
}

- (IBAction)changeEndingAddress:(id)__unused sender
{
	if (![_documentData.endingAddressStringValue isEqualToString:_endingAddressTextField.stringValue])
	{
		_documentData.endingAddressStringValue = _endingAddressTextField.stringValue;
		
		ZGDocument *document = _document;
		[document markChange];
	}
}

- (IBAction)changeIncludeOnlyStaticStackAndHeapData:(id)sender
{
	_documentData.indirectFilterHeapAndStackData = ([(NSCell *)sender state] == NSControlStateValueOn);
	
	ZGDocument *document = _document;
	[document markChange];
}

- (IBAction)changeExcludeStaticSystemLibraries:(id)sender
{
	_documentData.indirectExcludeStaticDataFromSystemLibraries = ([(NSCell *)sender state] == NSControlStateValueOn);
	
	ZGDocument *document = _document;
	[document markChange];
}

- (IBAction)changeStopTraversingAtFirstStaticAddress:(id)sender
{
	_searchData.indirectStopAtStaticAddresses = ([(NSCell *)sender state] == NSControlStateValueOn);
	
	ZGDocument *document = _document;
	[document markChange];
}

@end
