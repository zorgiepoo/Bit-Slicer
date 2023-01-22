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

#import "ZGDocumentLabelManager.h"
#import "ZGVariable.h"
#import "ZGDocumentData.h"
#import "ZGLabel.h"

@implementation ZGDocumentLabelManager
{
	NSMutableDictionary<NSString *, ZGLabel *> * _labels;
	ZGDocumentData * _documentData;
}


- (id)initWithDocumentData:(ZGDocumentData *)documentData
{
	if ((self = [super init]))
	{
		_documentData = documentData;
		_labels = [[NSMutableDictionary alloc] init];
		
		for (ZGLabel *label in documentData.labels)
		{
			if(label.name != nil)
			{
				[_labels setObject:label forKey:label.name];
			}
		}
	}
	
	return self;
}

- (void)addLabel:(ZGLabel *)label
{
	[_labels setObject:label forKey:label.name];
	
	NSMutableArray<ZGLabel *> *temporaryArray = [[NSMutableArray alloc] initWithArray:_documentData.labels];
	[temporaryArray addObject:label];
	
	_documentData.labels = [NSArray arrayWithArray:temporaryArray];
}

- (void)removeLabel:(NSString *)name
{
	ZGLabel *label = [_labels objectForKey:name];
	
	if(label == nil) {
		return;
	}
	
	[_labels removeObjectForKey:label.name];
	
	NSMutableArray<ZGLabel *> *temporaryArray = [[NSMutableArray alloc] initWithArray:_documentData.labels];
	[temporaryArray removeObject:label];
	
	_documentData.labels = [NSArray arrayWithArray:temporaryArray];
}

@end
