/*
 * Copyright (c) 2014 Mayur Pawashe
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

#import "ZGDocumentController.h"
#import "ZGDocument.h"
#import "ZGDocumentWindowController.h"

@implementation ZGDocumentController
{
	ZGDocumentWindowController * _Nonnull (^_makeDocumentWindowController)(void);
}

- (id)initWithMakeDocumentWindowController:(ZGDocumentWindowController * _Nonnull (^)(void))makeDocumentWindowController
{
	self = [super init];
	if (self != nil)
	{
		assert(makeDocumentWindowController != NULL);
		_makeDocumentWindowController = [makeDocumentWindowController copy];
	}
	return self;
}

// Override makeDocumentXXX methods so we can initialize the document's properties
// instead of overriding addDocument: which will not handle all cases (eg: browsing different versions to revert back to)

- (id)makeDocumentForURL:(NSURL *)absoluteDocumentURL withContentsOfURL:(NSURL *)absoluteDocumentContentsURL ofType:(NSString *)typeName error:(NSError * __autoreleasing *)outError
{
	ZGDocument *document = [super makeDocumentForURL:absoluteDocumentURL withContentsOfURL:absoluteDocumentContentsURL ofType:typeName error:outError];
	
	document.makeDocumentWindowController = _makeDocumentWindowController;
	
	return document;
}

- (id)makeDocumentWithContentsOfURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError * __autoreleasing *)outError
{
	ZGDocument *document = [super makeDocumentWithContentsOfURL:absoluteURL ofType:typeName error:outError];
	
	document.makeDocumentWindowController = _makeDocumentWindowController;
	
	return document;
}

- (id)makeUntitledDocumentOfType:(NSString *)typeName error:(NSError * __autoreleasing *)outError
{
	ZGDocument *document = [super makeUntitledDocumentOfType:typeName error:outError];

	document.makeDocumentWindowController = _makeDocumentWindowController;
	
	return document;
}

@end
