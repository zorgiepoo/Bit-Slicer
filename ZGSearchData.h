//
//  ZGSearchData.h
//  Bit Slicer
//
//  Created by Mayur Pawashe on 7/21/12.
//  Copyright (c) 2012 zgcoder. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ZGMemoryTypes.h"

@interface ZGSearchData : NSObject
{
@public
	double epsilon;
	void *rangeValue;
	BOOL shouldIgnoreStringCase;
	BOOL shouldIncludeNullTerminator;
	BOOL shouldCompareStoredValues;
	
	NSString *lastEpsilonValue;
	NSString *lastAboveRangeValue;
	NSString *lastBelowRangeValue;
	
	// these are not NSString's because there's no reason to save the values
	ZGMemoryAddress beginAddress;
	ZGMemoryAddress endAddress;
	BOOL beginAddressExists;
	BOOL endAddressExists;
	
	BOOL shouldCancelSearch;
	BOOL searchDidCancel;
	
	NSArray *savedData;
	NSArray *tempSavedData;
	
	BOOL shouldScanUnwritableValues;
	
	// For comparing unicode strings
	CollatorRef collator;
	
	// for wildcard byte array searches
	unsigned char *byteArrayFlags;
	
	void *compareOffset;
}

@property (readonly) void *rangeValue;
@property (readwrite, copy) NSString *lastEpsilonValue;
@property (readwrite, copy) NSString *lastAboveRangeValue;
@property (readwrite, copy) NSString *lastBelowRangeValue;
@property (readonly) NSArray *savedData;
@property (readwrite, retain) NSArray *tempSavedData;
@property (readwrite) BOOL shouldCompareStoredValues;
@property (readwrite) double epsilon;
@property (readwrite) BOOL shouldIgnoreStringCase;
@property (readwrite) BOOL shouldIncludeNullTerminator;
@property (readwrite) ZGMemoryAddress beginAddress;
@property (readwrite) BOOL beginAddressExists;
@property (readwrite) ZGMemoryAddress endAddress;
@property (readwrite) BOOL endAddressExists;
@property (readwrite) BOOL shouldScanUnwritableValues;
@property (readwrite, assign) void *compareOffset;

@property (readwrite) BOOL shouldCancelSearch;
@property (readwrite) BOOL searchDidCancel;

- (void)setRangeValue:(void *)newRangeValue;
- (void)setSavedData:(NSArray *)newSavedData;
- (void)setByteArrayFlags:(unsigned char *)newByteArrayFlags;

@end
