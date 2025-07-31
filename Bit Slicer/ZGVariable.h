/*
 * Copyright (c) 2012 Mayur Pawashe
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
 *
 * ZGVariable
 * ----------
 * This class represents a variable in memory that can be monitored, modified, or frozen.
 * It encapsulates all the information needed to locate, read, and manipulate a value
 * in a process's memory space, including its address, type, size, and current value.
 *
 * Key responsibilities:
 * - Storing variable metadata (address, type, size, description)
 * - Managing variable values (reading, formatting, freezing)
 * - Supporting different data types (integers, floats, strings, byte arrays, scripts)
 * - Handling dynamic addresses through formulas
 * - Providing serialization for copy/paste and persistence
 *
 * Variable Structure:
 * +------------------------+     +------------------------+     +------------------------+
 * |      Identification    |     |      Value Storage     |     |      Presentation     |
 * |------------------------|     |------------------------|     |------------------------|
 * | - Address & formula    |     | - Raw binary value     |     | - String value        |
 * | - Type & size          | --> | - Freeze value         | --> | - Description         |
 * | - Dynamic address info |     | - Script value         |     | - Label               |
 * | - Qualifier & flags    |     | - Byte order           |     | - Annotations         |
 * +------------------------+     +------------------------+     +------------------------+
 */

#import <Foundation/Foundation.h>
#import "ZGMemoryTypes.h"
#import "ZGVariableTypes.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *ZGVariablePboardType;

@interface ZGVariable : NSObject <NSSecureCoding, NSCopying>
{
@public
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-interface-ivars"
	// For fast access
	NSString *_addressFormula;
#pragma clang diagnostic pop
}

/** Whether the variable is enabled for searching and monitoring */
@property (nonatomic) BOOL enabled;

/** 
 * The formula used to calculate the variable's address
 * This can be a static address or a dynamic expression (e.g., using pointers or labels)
 */
@property (copy, nonatomic) NSString *addressFormula;

/** The data type of the variable (int8, int16, int32, int64, float, double, string, etc.) */
@property (nonatomic) ZGVariableType type;

/** 
 * Whether the variable is frozen (locked to its current value)
 * When frozen, the value is continuously written back to memory
 */
@property (nonatomic) BOOL isFrozen;

/** The qualifier for the variable (equal to, not equal to, greater than, etc.) */
@property (nonatomic) ZGVariableQualifier qualifier;

/** The byte order used for interpreting the variable's value (little-endian or big-endian) */
@property(nonatomic) CFByteOrder byteOrder;

/** The resolved memory address of the variable */
@property (readonly, nonatomic) ZGMemoryAddress address;

/** The size of the variable in bytes */
@property (nonatomic) ZGMemorySize size;

/** The size of the variable when it was last updated */
@property (nonatomic) ZGMemorySize lastUpdatedSize;

/** Whether the variable uses a dynamic address that needs to be evaluated */
@property (nonatomic) BOOL usesDynamicAddress;

/** Whether the dynamic address has been fully evaluated */
@property (nonatomic) BOOL finishedEvaluatingDynamicAddress;

/**
 * Gets the raw binary value of the variable
 * @return Pointer to the variable's raw value, or NULL if not available
 */
- (nullable void *)rawValue;

/**
 * Sets the raw binary value of the variable
 * @param rawValue Pointer to the new raw value, or NULL to clear
 */
- (void)setRawValue:(nullable const void *)rawValue;

/**
 * Gets the frozen value of the variable
 * @return Pointer to the variable's frozen value, or NULL if not frozen
 */
- (nullable void *)freezeValue;

/**
 * Sets the frozen value of the variable
 * @param freezeValue Pointer to the new frozen value, or NULL to clear
 */
- (void)setFreezeValue:(nullable const void *)freezeValue;

/**
 * Gets the string representation of the variable's address
 * @return The address as a hexadecimal string
 */
- (NSString *)addressStringValue;

/**
 * Sets the variable's address from a string
 * @param newAddressString The new address as a string (hexadecimal or expression)
 */
- (void)setAddressStringValue:(nullable NSString *)newAddressString;

/** The string representation of the variable's value, formatted according to its type */
@property (readonly, nonatomic) NSString *stringValue;

/** The script content for script-type variables */
@property (copy, nonatomic, nullable) NSString *scriptValue;

/** The path to the cached script file */
@property (copy, nonatomic, nullable) NSString *cachedScriptPath;

/** The UUID of the cached script */
@property (copy, nonatomic, nullable) NSString *cachedScriptUUID;

/** The string representation of the variable's size */
@property (readonly, nonatomic) NSString *sizeStringValue;

/** Whether the variable has been manually annotated by the user */
@property (nonatomic) BOOL userAnnotated;

/** The full description of the variable, with formatting */
@property (copy, nonatomic) NSAttributedString *fullAttributedDescription;

/** A short description of the variable (typically the first line of the full description) */
@property (nonatomic, readonly) NSString *shortDescription;

/** The name of the variable (derived from the description) */
@property (nonatomic, readonly) NSString *name;

/** A user-assigned label for the variable, which can be referenced in address formulas */
@property (nonatomic, copy) NSString *label;

/**
 * Initializes a variable with basic information
 *
 * @param value Pointer to the initial value, or NULL
 * @param size Size of the variable in bytes
 * @param address Memory address of the variable
 * @param type Data type of the variable
 * @param qualifier Qualifier for the variable (equal to, not equal to, etc.)
 * @param pointerSize Size of pointers in the target process
 * @return An initialized variable object
 */
- (id)initWithValue:(nullable const void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)type qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize;

/**
 * Initializes a variable with a description
 *
 * @param value Pointer to the initial value, or NULL
 * @param size Size of the variable in bytes
 * @param address Memory address of the variable
 * @param type Data type of the variable
 * @param qualifier Qualifier for the variable (equal to, not equal to, etc.)
 * @param pointerSize Size of pointers in the target process
 * @param description Description of the variable
 * @return An initialized variable object
 */
- (id)initWithValue:(nullable const void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)type qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize description:(nullable NSAttributedString *)description;

/**
 * Initializes a variable with a description and enabled state
 *
 * @param value Pointer to the initial value, or NULL
 * @param size Size of the variable in bytes
 * @param address Memory address of the variable
 * @param type Data type of the variable
 * @param qualifier Qualifier for the variable (equal to, not equal to, etc.)
 * @param pointerSize Size of pointers in the target process
 * @param description Description of the variable
 * @param enabled Whether the variable is initially enabled
 * @return An initialized variable object
 */
- (id)initWithValue:(nullable const void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)type qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize description:(nullable NSAttributedString *)description enabled:(BOOL)enabled;

/**
 * Initializes a variable with a specific byte order
 *
 * @param value Pointer to the initial value, or NULL
 * @param size Size of the variable in bytes
 * @param address Memory address of the variable
 * @param type Data type of the variable
 * @param qualifier Qualifier for the variable (equal to, not equal to, etc.)
 * @param pointerSize Size of pointers in the target process
 * @param byteOrder Byte order for interpreting the variable's value
 * @return An initialized variable object
 */
- (id)initWithValue:(nullable const void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)type qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize byteOrder:(CFByteOrder)byteOrder;

/**
 * Initializes a variable with all properties specified
 *
 * This is the designated initializer that all other initializers call.
 *
 * @param value Pointer to the initial value, or NULL
 * @param size Size of the variable in bytes
 * @param address Memory address of the variable
 * @param type Data type of the variable
 * @param qualifier Qualifier for the variable (equal to, not equal to, etc.)
 * @param pointerSize Size of pointers in the target process
 * @param description Description of the variable
 * @param enabled Whether the variable is initially enabled
 * @param byteOrder Byte order for interpreting the variable's value
 * @return An initialized variable object
 */
- (id)initWithValue:(nullable const void *)value size:(ZGMemorySize)size address:(ZGMemoryAddress)address type:(ZGVariableType)type qualifier:(ZGVariableQualifier)qualifier pointerSize:(ZGMemorySize)pointerSize description:(nullable NSAttributedString *)description enabled:(BOOL)enabled byteOrder:(CFByteOrder)byteOrder;

/**
 * Creates a string representation of a byte array
 *
 * @param value Pointer to the byte array
 * @param size Size of the byte array in bytes
 * @return A string representation of the byte array in hexadecimal format
 */
+ (NSString *)byteArrayStringFromValue:(unsigned char *)value size:(ZGMemorySize)size;

/**
 * Updates the string representation of the variable's value
 *
 * This method is called when the variable's value changes to update its string representation.
 */
- (void)updateStringValue;

/**
 * Changes the variable's type and size
 *
 * @param newType The new data type for the variable
 * @param requestedSize The requested size for the variable
 * @param pointerSize Size of pointers in the target process
 */
- (void)setType:(ZGVariableType)newType requestedSize:(ZGMemorySize)requestedSize pointerSize:(ZGMemorySize)pointerSize;

/**
 * Updates the variable's pointer size
 *
 * This is typically called when the target process changes.
 *
 * @param pointerSize The new pointer size
 */
- (void)changePointerSize:(ZGMemorySize)pointerSize;

@end

NS_ASSUME_NONNULL_END
