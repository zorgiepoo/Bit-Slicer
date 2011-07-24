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

#import <Cocoa/Cocoa.h>

#define INVALID_KEY_CODE            -999
#define ZG_HOT_KEY                  @"ZG_HOT_KEY_CODE"
#define ZGPreferencesIdentifier     @"ZGPreferencesID"

@interface ZGPreferencesController : NSWindowController
{
	IBOutlet NSPopUpButton *hotKeysPopUpButton;
}

- (IBAction)changeHotKey:(id)sender;

@end
