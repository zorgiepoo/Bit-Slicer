/*
 * Copyright (c) 2013 Mayur Pawashe
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
 * ZGSearchResults
 * --------------
 * This class represents the results of memory searches in a process.
 * It efficiently stores and provides access to memory addresses that match
 * search criteria, supporting both direct memory addresses and indirect
 * pointer paths (for pointer scanning).
 *
 * Key responsibilities:
 * - Storing search result addresses efficiently
 * - Managing result metadata (stride, type, count)
 * - Supporting both direct and indirect search results
 * - Providing enumeration capabilities for processing results
 * - Handling binary image information for relocatable results
 *
 * Search Results Structure:
 * +------------------------+     +------------------------+     +------------------------+
 * |      Result Storage    |     |      Result Types      |     |      Enumeration      |
 * |------------------------|     |------------------------|     |------------------------|
 * | - Multiple result sets |     | - Direct results       |     | - Block-based access  |
 * | - Compact binary data  | --> | - Indirect results     | --> | - Efficient iteration |
 * | - Memory-efficient     |     |   with pointer paths   |     | - Optional removal    |
 * | - Stride-based access  |     | - Binary image info    |     |   during enumeration  |
 * +------------------------+     +------------------------+     +------------------------+
 */

#import <Foundation/Foundation.h>
#import "ZGMemoryTypes.h"
#import "ZGVariableTypes.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Defines the type of search results
 *
 * - ZGSearchResultTypeDirect: Results are direct memory addresses
 * - ZGSearchResultTypeIndirect: Results are indirect pointer paths
 */
typedef NS_ENUM(NSInteger, ZGSearchResultType)
{
	ZGSearchResultTypeDirect = 0,
	ZGSearchResultTypeIndirect
};

@interface ZGSearchResults : NSObject

/** The total number of search results across all result sets */
@property (nonatomic, readonly) ZGMemorySize count;

/** 
 * The stride (size in bytes) of each result entry
 * For direct results, this is typically the size of a memory address
 * For indirect results, this includes the base address, image index, and offsets
 */
@property (nonatomic, readonly) ZGMemorySize stride;

/** Whether the search results can include unaligned memory accesses */
@property (nonatomic, readonly) BOOL unalignedAccess;

/** 
 * The array of NSData objects containing the raw search results
 * Each NSData object contains multiple results, with each result occupying 'stride' bytes
 */
@property (nonatomic, readonly) NSArray<NSData *> *resultSets;

/** The type of search results (direct or indirect) */
@property (nonatomic, readonly) ZGSearchResultType resultType;

/** 
 * The maximum number of indirection levels for indirect search results
 * Only applicable when resultType is ZGSearchResultTypeIndirect
 */
@property (nonatomic) uint16_t indirectMaxLevels;

/** 
 * The memory ranges of static segments in the process
 * Used for relocating search results when the process is restarted
 */
@property (nonatomic, nullable) NSArray<NSValue *> *totalStaticSegmentRanges;

/** 
 * The header addresses of binary images in the process
 * Used for relocating search results when the process is restarted
 */
@property (nonatomic, nullable) NSArray<NSNumber *> *headerAddresses;

/** 
 * The file paths of binary images in the process
 * Used for relocating search results when the process is restarted
 */
@property (nonatomic, nullable) NSArray<NSString *> *filePaths;

/** The data type of the search results (used by clients) */
@property (nonatomic, readonly) ZGVariableType dataType;

/**
 * Block type for enumerating search results
 *
 * @param data Pointer to the current result data (size depends on stride)
 * @param stop Set to YES to stop enumeration
 */
typedef void (^zg_enumerate_search_results_t)(const void *data, BOOL *stop);

/**
 * Calculates the stride needed for indirect search results with the given number of levels
 *
 * Indirect search results need to store the base address, image index, number of levels,
 * and offsets for each level. This method calculates the total size needed.
 *
 * @param maxNumberOfLevels The maximum number of indirection levels
 * @param pointerSize The size of pointers in the target process
 * @return The stride (in bytes) needed for each indirect search result
 */
+ (ZGMemorySize)indirectStrideWithMaxNumberOfLevels:(ZGMemorySize)maxNumberOfLevels pointerSize:(ZGMemorySize)pointerSize;

/**
 * Default initializer is unavailable
 * Use initWithResultSets:resultType:dataType:stride:unalignedAccess: instead
 */
- (instancetype)init NS_UNAVAILABLE;

/**
 * Initializes search results with the given parameters
 *
 * @param resultSets Array of NSData objects containing the raw search results
 * @param resultType The type of search results (direct or indirect)
 * @param dataType The data type of the search results
 * @param stride The stride (size in bytes) of each result entry
 * @param unalignedAccess Whether the search results can include unaligned memory accesses
 * @return An initialized search results object
 */
- (instancetype)initWithResultSets:(NSArray<NSData *> *)resultSets resultType:(ZGSearchResultType)resultType dataType:(ZGVariableType)dataType stride:(ZGMemorySize)stride unalignedAccess:(BOOL)unalignedAccess;

/**
 * Creates a new search results object by appending indirect search results
 *
 * This method is used for pointer scanning to combine multiple levels of indirection.
 * It creates a new search results object with the combined results.
 *
 * @param newSearchResults The search results to append
 * @return A new search results object with the combined results
 */
- (instancetype)indirectSearchResultsByAppendingIndirectSearchResults:(ZGSearchResults *)newSearchResults;

/**
 * Enumerates through the search results
 *
 * This method provides efficient access to the raw search results data.
 * It calls the provided block for each result, allowing processing of the results.
 *
 * @param count The maximum number of results to enumerate (0 for all)
 * @param removeResults Whether to remove the enumerated results
 * @param addressCallback The block to call for each result
 */
- (void)enumerateWithCount:(ZGMemorySize)count removeResults:(BOOL)removeResults usingBlock:(zg_enumerate_search_results_t)addressCallback;

/**
 * Updates the binary image information for relocating search results
 *
 * This method is used when the process is restarted to update the information
 * needed for relocating search results to the new process.
 *
 * @param headerAddresses The header addresses of binary images in the process
 * @param totalStaticSegmentRanges The memory ranges of static segments in the process
 * @param filePaths The file paths of binary images in the process
 */
- (void)updateHeaderAddresses:(NSArray<NSNumber *> *)headerAddresses totalStaticSegmentRanges:(NSArray<NSValue *> *)totalStaticSegmentRanges usingFilePaths:(NSArray<NSString *> *)filePaths;

@end

NS_ASSUME_NONNULL_END
