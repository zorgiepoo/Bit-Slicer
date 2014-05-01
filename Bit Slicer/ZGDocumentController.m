/*
 * Created by Mayur Pawashe on 3/8/14.
 *
 * Copyright (c) 2014 zgcoder
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
#import "ZGDebuggerController.h"
#import "ZGProcessTaskManager.h"
#import "ZGHotKeyCenter.h"
#import "ZGDocument.h"

@implementation ZGDocumentController
{
	ZGProcessTaskManager *_processTaskManager;
	ZGDebuggerController *_debuggerController;
	ZGBreakPointController *_breakPointController;
	ZGHotKeyCenter *_hotKeyCenter;
	ZGLoggerWindowController *_loggerWindowController;
}

- (id)initWithProcessTaskManager:(ZGProcessTaskManager *)processTaskManager debuggerController:(ZGDebuggerController *)debuggerController breakPointController:(ZGBreakPointController *)breakPointController hotKeyCenter:(ZGHotKeyCenter *)hotKeyCenter loggerWindowController:(ZGLoggerWindowController *)loggerWindowController
{
	self = [super init];
	if (self != nil)
	{
		_processTaskManager = processTaskManager;
		_debuggerController = debuggerController;
		_breakPointController = breakPointController;
		_hotKeyCenter = hotKeyCenter;
		_loggerWindowController = loggerWindowController;
	}
	return self;
}

- (void)initializeDocument:(ZGDocument *)document
{
	document.processTaskManager = _processTaskManager;
	document.debuggerController = _debuggerController;
	document.breakPointController = _breakPointController;
	document.hotKeyCenter = _hotKeyCenter;
	document.loggerWindowController = _loggerWindowController;
	
	document.lastChosenInternalProcessName = self.lastChosenInternalProcessName;
}

// Override makeDocumentXXX methods so we can initialize the document's properties
// instead of overriding addDocument: which will not handle all cases (eg: browsing different versions to revert back to)

- (id)makeDocumentForURL:(NSURL *)absoluteDocumentURL withContentsOfURL:(NSURL *)absoluteDocumentContentsURL ofType:(NSString *)typeName error:(NSError * __autoreleasing *)outError
{
	id document = [super makeDocumentForURL:absoluteDocumentURL withContentsOfURL:absoluteDocumentContentsURL ofType:typeName error:outError];
	
	[self initializeDocument:document];
	
	return document;
}

- (id)makeDocumentWithContentsOfURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError * __autoreleasing *)outError
{
	id document = [super makeDocumentWithContentsOfURL:absoluteURL ofType:typeName error:outError];
	
	[self initializeDocument:document];
	
	return document;
}

- (id)makeUntitledDocumentOfType:(NSString *)typeName error:(NSError * __autoreleasing *)outError
{
	id document = [super makeUntitledDocumentOfType:typeName error:outError];
	
	[self initializeDocument:document];
	
	return document;
}

@end
