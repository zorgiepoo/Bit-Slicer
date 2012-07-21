//
//  ZGSearchData.m
//  Bit Slicer
//
//  Created by Mayur Pawashe on 7/21/12.
//  Copyright (c) 2012 zgcoder. All rights reserved.
//

#import "ZGSearchData.h"
#import "ZGVirtualMemory.h"

@implementation ZGSearchData

@synthesize rangeValue;
@synthesize lastEpsilonValue;
@synthesize lastAboveRangeValue;
@synthesize lastBelowRangeValue;
@synthesize savedData;
@synthesize tempSavedData;
@synthesize shouldCompareStoredValues;
@synthesize epsilon;
@synthesize shouldIgnoreStringCase;
@synthesize shouldIncludeNullTerminator;
@synthesize beginAddress;
@synthesize endAddress;
@synthesize shouldScanUnwritableValues;
@synthesize compareOffset;

@synthesize shouldCancelSearch;
@synthesize searchDidCancel;

- (id)init
{
	self = [super init];
	if (self)
	{
		UCCreateCollator(NULL, 0, kUCCollateCaseInsensitiveMask, &collator);
		[self setBeginAddress:0x0];
		[self setEndAddress:MAX_MEMORY_ADDRESS];
	}
	return self;
}

- (void)dealloc
{
	UCDisposeCollator(&collator);
	
	[self setLastEpsilonValue:nil];
	[self setLastAboveRangeValue:nil];
	[self setLastBelowRangeValue:nil];
	[self setSavedData:nil];
	[self setRangeValue:NULL];
	[self setByteArrayFlags:NULL];
	
	[super dealloc];
}

- (void)setRangeValue:(void *)newRangeValue
{
	if ([self rangeValue])
	{
		free([self rangeValue]);
	}
	
	rangeValue = newRangeValue;
}

- (void)setSavedData:(NSArray *)newSavedData
{
	if ([self savedData])
	{
		ZGFreeData([self savedData]);
	}
	
	[savedData release];
	savedData = [newSavedData retain];
}

- (void)setByteArrayFlags:(unsigned char *)newByteArrayFlags
{
	if (byteArrayFlags)
	{
		free(byteArrayFlags);
	}
	
	byteArrayFlags = newByteArrayFlags;
}

@end
