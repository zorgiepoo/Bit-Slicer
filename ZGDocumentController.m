/*
 * This file is part of Bit Slicer.
 *
 * Bit Slicer is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 
 * Bit Slicer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 
 * You should have received a copy of the GNU General Public License
 * along with Bit Slicer.  If not, see <http://www.gnu.org/licenses/>.
 * 
 * Created by Mayur Pawashe on 3/11/10.
 * Copyright 2010 zgcoder. All rights reserved.
 */

#import "ZGDocumentController.h"

@implementation ZGDocumentController

- (id)openDocumentWithContentsOfURL:(NSURL *)absoluteURL
							display:(BOOL)displayDocument
							  error:(NSError **)outError
{	
	if (![appController applicationIsAuthenticated])
	{
		[appController authenticateWithURL:absoluteURL];
	}
	
	return [super openDocumentWithContentsOfURL:absoluteURL
										display:displayDocument
										  error:outError];
}

// lastSelectedProcessName keeps track of the last targeted process
// useful for guessing what process the user may want to target
// when creating a new document
static NSString *lastSelectedProcessName = nil;
+ (void)setLastSelectedProcessName:(NSString *)processName
{
	[lastSelectedProcessName release];
	lastSelectedProcessName = [processName copy];
}

+ (NSString *)lastSelectedProcessName
{
	return lastSelectedProcessName;
}

@end
