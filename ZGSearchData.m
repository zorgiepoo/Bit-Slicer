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

- (id)init
{
	self = [super init];
	if (self)
	{
		UCCreateCollator(NULL, 0, kUCCollateCaseInsensitiveMask, &_collator);
		self.beginAddress = 0x0;
		self.endAddress = MAX_MEMORY_ADDRESS;
		self.lastEpsilonValue = [NSString stringWithFormat:@"%.1f", DEFAULT_FLOATING_POINT_EPSILON];
	}
	return self;
}

- (void)dealloc
{
	UCDisposeCollator(&_collator);
	
	self.lastEpsilonValue = nil;
	self.lastAboveRangeValue = nil;
	self.lastBelowRangeValue = nil;
	self.savedData = nil;
	self.rangeValue = NULL;
	self.byteArrayFlags = NULL;
	
	[super dealloc];
}

- (void)setRangeValue:(void *)newRangeValue
{
	if (_rangeValue)
	{
		free(_rangeValue);
	}
	
	_rangeValue = newRangeValue;
}

- (void)setSavedData:(NSArray *)newSavedData
{
	if (_savedData)
	{
		ZGFreeData(_savedData);
	}
	
	[_savedData release];
	_savedData = [newSavedData retain];
}

- (void)setByteArrayFlags:(unsigned char *)newByteArrayFlags
{
	if (_byteArrayFlags)
	{
		free(_byteArrayFlags);
	}
	
	_byteArrayFlags = newByteArrayFlags;
}

@end
