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
#import <ShortcutRecorder/ShortcutRecorder.h>

// INVALID_KEY_CODE used to be -999, take in account
#define INVALID_KEY_CODE            -1
#define ZG_HOT_KEY_MODIFIER         @"ZG_HOT_KEY_MODIFIER"
#define ZG_HOT_KEY                  @"ZG_HOT_KEY_CODE"
#define ZG_CHECK_FOR_UPDATES		@"ZG_CHECK_FOR_UPDATES_1"
#define ZG_CHECK_FOR_ALPHA_UPDATES  @"ZG_CHECK_FOR_ALPHA_UPDATES_1"
#define ZGPreferencesIdentifier     @"ZGPreferencesID"

@interface ZGPreferencesController : NSWindowController
{
    IBOutlet SRRecorderControl *hotkeyRecorder;
	IBOutlet NSButton *checkForUpdatesButton;
	IBOutlet NSButton *checkForAlphaUpdatesButton;
}

- (IBAction)checkForUpdatesButton:(id)sender;
- (IBAction)checkForAlphaUpdatesButton:(id)sender;
- (void)updateAlphaUpdatesUI;

@end
