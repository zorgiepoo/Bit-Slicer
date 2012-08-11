//
//  ZGSearchData.h
//  Bit Slicer
//
//  Created by Mayur Pawashe on 7/21/12.
//  Copyright (c) 2012 zgcoder. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ZGMemoryTypes.h"

#define DEFAULT_FLOATING_POINT_EPSILON 0.1

@interface ZGSearchData : NSObject
{
@public
	// All for fast access, for comparison functions
	void *_rangeValue;
	double _epsilon;
	BOOL _shouldIgnoreStringCase;
	BOOL _shouldIncludeNullTerminator;
	void *_compareOffset;
	CollatorRef _collator; // For comparing unicode strings
	unsigned char *_byteArrayFlags; // For wildcard byte array searches
}

@property (readwrite, nonatomic) void *rangeValue;
@property (readwrite, copy) NSString *lastEpsilonValue;
@property (readwrite, copy) NSString *lastAboveRangeValue;
@property (readwrite, copy) NSString *lastBelowRangeValue;
@property (readwrite, nonatomic, retain) NSArray *savedData;
@property (readwrite, retain) NSArray *tempSavedData;
@property (readwrite) BOOL shouldCompareStoredValues;
@property (readwrite) double epsilon;
@property (readwrite) BOOL shouldIgnoreStringCase;
@property (readwrite) BOOL shouldIncludeNullTerminator;
@property (readwrite) ZGMemoryAddress beginAddress;
@property (readwrite) ZGMemoryAddress endAddress;
@property (readwrite) BOOL shouldScanUnwritableValues;
@property (readwrite, assign) void *compareOffset;
@property (readwrite, nonatomic) unsigned char *byteArrayFlags;

@property (readwrite) BOOL shouldCancelSearch;
@property (readwrite) BOOL searchDidCancel;

@end
