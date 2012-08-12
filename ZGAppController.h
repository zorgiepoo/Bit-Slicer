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
 * Created by Mayur Pawashe on 2/5/10.
 * Copyright 2010 zgcoder. All rights reserved.
 */

#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
@class ZGPreferencesController;
@class ZGMemoryViewer;

#define BIT_SLICER_VERSION_FILE @"https://dl.dropbox.com/u/10108199/bit_slicer/bit_slicer_version.plist"

@interface ZGAppController : NSObject

@property (readonly, retain, nonatomic) ZGPreferencesController *preferencesController;
@property (readonly, retain, nonatomic) ZGMemoryViewer *memoryViewer;
// lastSelectedProcessName keeps track of the last targeted process in a document
@property (readwrite, copy, nonatomic) NSString *lastSelectedProcessName;

+ (id)sharedController;

+ (BOOL)isRunningLaterThanLion;

+ (void)registerPauseAndUnpauseHotKey;

@end
