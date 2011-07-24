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

#import "ZGPreferencesController.h"
#import "ZGAppController.h"

@implementation ZGPreferencesController

+ (void)initialize
{
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:INVALID_KEY_CODE]
																						forKey:ZG_HOT_KEY]];
}

- (id)init
{
	self = [super initWithWindowNibName:@"Preferences"];
	
	[self setWindowFrameAutosaveName:@"ZGPreferencesWindow"];
	
	return self;
}

- (void)windowDidLoad
{
    if ([[self window] respondsToSelector:@selector(setRestorable:)] && [[self window] respondsToSelector:@selector(setRestorationClass:)])
    {
        [[self window] setRestorable:YES];
        [[self window] setRestorationClass:[ZGAppController class]];
        [[self window] setIdentifier:ZGPreferencesIdentifier];
        [self invalidateRestorableState];
    }
	[hotKeysPopUpButton selectItemWithTag:[[NSUserDefaults standardUserDefaults] integerForKey:ZG_HOT_KEY]];
}

- (IBAction)changeHotKey:(id)sender
{
	[[NSUserDefaults standardUserDefaults] setInteger:[[sender selectedItem] tag]
											   forKey:ZG_HOT_KEY];
	
	[ZGAppController registerPauseAndUnpauseHotKey];
}

@end
