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

@class ZGProcess;

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
	ZGPointer
} ZGVariableType;

typedef enum
{
	ZGSigned = 0,
	ZGUnsigned,
} ZGVariableQualifier;

@interface ZGVariable : NSObject <NSCoding>
{
	NSString *addressStringValue;
	NSString *addressFormula;
	NSString *stringValue;
	NSString *name;
@public
	BOOL shouldBeSearched;
	BOOL isFrozen;
	BOOL isPointer;
	unsigned long long address;
	unsigned long long size;
	unsigned long long lastUpdatedSize;
	ZGVariableType type;
	ZGVariableQualifier qualifier;
	void *value;
	void *freezeValue;
}

@property (assign) BOOL shouldBeSearched;
@property (copy, nonatomic) NSString *addressFormula;

- (id)initWithValue:(void *)aValue
			   size:(unsigned long long)aSize
			address:(unsigned long long)anAddress
			   type:(ZGVariableType)aType
		  qualifier:(ZGVariableQualifier)aQualifier
		pointerSize:(unsigned long long)pointerSize;

- (NSString *)name;
- (NSString *)stringValue;
- (void)updateStringValue;
- (NSString *)addressStringValue;
- (void)setAddressStringValue:(NSString *)newAddressString;
- (void)setVariableValue:(void *)newValue;
- (void)setFreezeValue:(void *)newFreezeValue;
- (void)setName:(NSString *)newName;
- (void)setType:(ZGVariableType)newType pointerSize:(unsigned long long)pointerSize;
- (void)setPointerSize:(unsigned long long)pointerSize;

@end
