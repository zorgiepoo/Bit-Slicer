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
 * Created by Mayur Pawashe on 10/29/09.
 * Copyright 2010 zgcoder. All rights reserved.
 */

#import <Cocoa/Cocoa.h>
#import "ZGMemoryTypes.h"

extern NSString *ZGVariablePboardType;

typedef enum
{
	ZGInt8 = 0,
	ZGInt16,
	ZGInt32,
	ZGInt64,
	ZGFloat,
	ZGDouble,
	ZGUTF8String,
	ZGUTF16String,
	ZGPointer,
    ZGByteArray
} ZGVariableType;

typedef enum
{
	ZGSigned = 0,
	ZGUnsigned,
} ZGVariableQualifier;

@interface ZGVariable : NSObject <NSCoding>
{
	NSString *_addressStringValue;
}

@property (assign) BOOL shouldBeSearched;
@property (copy, nonatomic) NSString *addressFormula;
@property (readwrite) ZGVariableType type;
@property (readwrite) BOOL isFrozen;
@property (readwrite) ZGVariableQualifier qualifier;
@property (readonly) ZGMemoryAddress address;
@property (readwrite) ZGMemorySize size;
@property (readwrite) ZGMemorySize lastUpdatedSize;
@property (readwrite) BOOL isPointer;
@property (readwrite, nonatomic) void *value;
@property (readwrite, copy, nonatomic) NSString *addressStringValue;
@property (readwrite, copy, nonatomic) NSString *stringValue;
@property (readwrite, nonatomic) void *freezeValue;
@property (readonly) NSString *sizeStringValue;
@property (readwrite, copy) NSString *name;

- (id)initWithValue:(void *)aValue size:(ZGMemorySize)aSize address:(ZGMemoryAddress)anAddress type:(ZGVariableType)aType qualifier:(ZGVariableQualifier)aQualifier pointerSize:(ZGMemorySize)pointerSize;

- (void)updateStringValue;

- (void)setType:(ZGVariableType)newType requestedSize:(ZGMemorySize)requestedSize pointerSize:(ZGMemorySize)pointerSize;
- (void)setPointerSize:(ZGMemorySize)pointerSize;

@end
