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
@property (readwrite, copy, nonatomic) NSString *lastEpsilonValue;
@property (readwrite, copy, nonatomic) NSString *lastAboveRangeValue;
@property (readwrite, copy, nonatomic) NSString *lastBelowRangeValue;
@property (readwrite, strong, nonatomic) NSArray *savedData;
@property (readwrite, strong, nonatomic) NSArray *tempSavedData;
@property (readwrite, nonatomic) BOOL shouldCompareStoredValues;
@property (readwrite, nonatomic) double epsilon;
@property (readwrite, nonatomic) BOOL shouldIgnoreStringCase;
@property (readwrite, nonatomic) BOOL shouldIncludeNullTerminator;
@property (readwrite, nonatomic) ZGMemoryAddress beginAddress;
@property (readwrite, nonatomic) ZGMemoryAddress endAddress;
@property (readwrite, nonatomic) BOOL shouldScanUnwritableValues;
@property (readwrite, assign, nonatomic) void *compareOffset;
@property (readwrite, nonatomic) unsigned char *byteArrayFlags;

@property (readwrite, nonatomic) BOOL shouldCancelSearch;
@property (readwrite, nonatomic) BOOL searchDidCancel;

@end
