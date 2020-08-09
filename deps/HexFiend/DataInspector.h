/* Copyright (c) 2005-2011, Peter Ammon
 * All rights reserved.
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE REGENTS AND CONTRIBUTORS BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

//
//  DataInspector.h
//  HexFiend_2
//
//  Copyright © 2019 ridiculous_fish. All rights reserved.
//

#import <Foundation/Foundation.h>

@class HFController;

/* The largest number of bytes that any inspector type can edit */
#define MAX_EDITABLE_BYTE_COUNT 128

// Inspector types
// Needs to match menu order in DataInspectorView.xib
enum InspectorType_t {
	eInspectorTypeSignedInteger,
	eInspectorTypeUnsignedInteger,
	eInspectorTypeFloatingPoint,
	eInspectorTypeUTF8Text,
	eInspectorTypeSLEB128,
	eInspectorTypeULEB128,
	eInspectorTypeBinary,
	
	// Total number of inspector types.
	eInspectorTypeCount
};

// Needs to match menu order in DataInspectorView.xib
enum Endianness_t {
	eEndianLittle, // (Endianness_t)0 is the default endianness.
	eEndianBig,

	// Total number of endiannesses.
	eEndianCount,
	
#if __LITTLE_ENDIAN__
	eNativeEndianness = eEndianLittle
#else
	eNativeEndianness = eEndianBig
#endif
};

enum NumberBase_t {
	eNumberBaseDecimal,
	eNumberBaseHexadecimal,
};

/* A class representing a single row of the data inspector */
@interface DataInspector : NSObject<NSCoding> {
	enum InspectorType_t inspectorType;
	enum Endianness_t endianness;
	enum NumberBase_t numberBase;
}

/* A data inspector that is different from the given inspectors, if possible. */
+ (DataInspector*)dataInspectorSupplementing:(NSArray*)inspectors;

@property (nonatomic) enum InspectorType_t type;
@property (nonatomic) enum Endianness_t endianness;
@property (nonatomic) enum NumberBase_t numberBase;

- (NSAttributedString *)valueForController:(HFController *)controller ranges:(NSArray*)ranges isError:(BOOL *)outIsError;
- (NSAttributedString *)valueForData:(NSData *)data isError:(BOOL *)outIsError;
- (NSAttributedString *)valueForBytes:(const unsigned char *)bytes length:(NSUInteger)length isError:(BOOL *)outIsError;

/* Returns YES if we can replace the given number of bytes with this string value */
- (BOOL)acceptStringValue:(NSString *)value replacingByteCount:(NSUInteger)count intoData:(unsigned char *)outData;

/* Get and set a property list representation, for persisting to user defaults */
@property (nonatomic, strong) id propertyListRepresentation;

@end
