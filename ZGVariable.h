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

@property (assign, nonatomic) BOOL shouldBeSearched;
@property (copy, nonatomic) NSString *addressFormula;
@property (readwrite, nonatomic) ZGVariableType type;
@property (readwrite, nonatomic) BOOL isFrozen;
@property (readwrite, nonatomic) ZGVariableQualifier qualifier;
@property (readonly, nonatomic) ZGMemoryAddress address;
@property (readwrite, nonatomic) ZGMemorySize size;
@property (readwrite, nonatomic) ZGMemorySize lastUpdatedSize;
@property (readwrite, nonatomic) BOOL isPointer;
@property (readwrite, nonatomic) void *value;
@property (readwrite, copy, nonatomic) NSString *addressStringValue;
@property (readwrite, copy, nonatomic) NSString *stringValue;
@property (readwrite, nonatomic) void *freezeValue;
@property (readonly, nonatomic) NSString *sizeStringValue;
@property (readwrite, copy, nonatomic) NSString *name;

- (id)initWithValue:(void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)aType qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize;

- (void)updateStringValue;

- (void)setType:(ZGVariableType)newType requestedSize:(ZGMemorySize)requestedSize pointerSize:(ZGMemorySize)pointerSize;
- (void)setPointerSize:(ZGMemorySize)pointerSize;

@end
