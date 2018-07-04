/*
 * Copyright (c) 2015 Mayur Pawashe
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
 */

#import "ZGPrivateCoreSymbolicator.h"
#import "CoreSymbolication.h"

@implementation ZGPrivateCoreSymbolicator
{
	CSSymbolicatorRef _symbolicator;
}

- (nullable id)initWithTask:(ZGMemoryMap)task
{
	self = [super init];
	if (self != nil)
	{
		_symbolicator = CSSymbolicatorCreateWithTask(task);
		
		// this is very possible to occur
		if (CSIsNull(_symbolicator))
		{
			return nil;
		}
	}
	return self;
}

- (void)invalidate
{
	CSRelease(_symbolicator);
	_symbolicator = kCSNull;
}

- (nullable NSString *)symbolAtAddress:(ZGMemoryAddress)address relativeOffset:(nullable ZGMemoryAddress *)relativeOffset
{
	NSString *symbolName = nil;
	if (!CSIsNull(_symbolicator))
	{
		CSSymbolRef symbol = CSSymbolicatorGetSymbolWithAddressAtTime(_symbolicator, address, kCSNow);
		if (!CSIsNull(symbol))
		{
			const char *symbolNameCString = CSSymbolGetName(symbol);
			if (symbolNameCString != NULL)
			{
				symbolName = @(symbolNameCString);
			}
			
			if (relativeOffset != NULL)
			{
				CSRange symbolRange = CSSymbolGetRange(symbol);
				*relativeOffset = address - symbolRange.location;
			}
		}
	}
	
	return symbolName;
}

- (NSArray<NSValue *> *)findSymbolsWithName:(NSString *)symbolName partialSymbolOwnerName:(nullable NSString *)partialSymbolOwnerName requiringExactMatch:(BOOL)requiresExactMatch
{
	NSMutableArray<NSValue *> *symbolRanges = [NSMutableArray array];
	
	const char *symbolCString = [symbolName UTF8String];
	
	CSSymbolicatorForeachSymbolOwnerAtTime(_symbolicator, kCSNow, ^(CSSymbolOwnerRef owner) {
		const char *symbolOwnerName = CSSymbolOwnerGetName(owner); // this really returns a suffix
		NSString *symbolOwnerNameValue;
		if (partialSymbolOwnerName == nil || (symbolOwnerName != NULL && ((symbolOwnerNameValue = @(symbolOwnerName)) != nil) && [partialSymbolOwnerName hasSuffix:symbolOwnerNameValue]))
		{
			CSSymbolOwnerForeachSymbol(owner, ^(CSSymbolRef symbol) {
				const char *symbolFound = CSSymbolGetName(symbol);
				if (symbolFound != NULL && ((requiresExactMatch && strcmp(symbolCString, symbolFound) == 0) || (!requiresExactMatch && strstr(symbolFound, symbolCString) != NULL)))
				{
					CSRange csSymbolRange = CSSymbolGetRange(symbol);
					const ZGSymbolRange symbolRange = {csSymbolRange.location, csSymbolRange.length};
					[symbolRanges addObject:[NSValue valueWithBytes:&symbolRange objCType:@encode(ZGSymbolRange)]];
				}
			});
		}
	});
	
	return [symbolRanges sortedArrayUsingComparator:^(NSValue *rangeValue1, NSValue *rangeValue2) {
		ZGSymbolRange symbolRange1 = {};
		[rangeValue1	getValue:&symbolRange1];
		
		ZGSymbolRange symbolRange2 = {};
		[rangeValue2	getValue:&symbolRange2];
		
		if (symbolRange1.location > symbolRange2.location)
		{
			return NSOrderedDescending;
		}
		
		if (symbolRange1.location < symbolRange2.location)
		{
			return NSOrderedAscending;
		}
		
		return NSOrderedSame;
	}];
}

- (nullable NSNumber *)findSymbol:(NSString *)symbolName withPartialSymbolOwnerName:(nullable NSString *)partialSymbolOwnerName requiringExactMatch:(BOOL)requiresExactMatch pastAddress:(ZGMemoryAddress)pastAddress allowsWrappingToBeginning:(BOOL)allowsWrapping
{
	NSArray<NSValue *> *symbols = [self findSymbolsWithName:symbolName partialSymbolOwnerName:partialSymbolOwnerName requiringExactMatch:requiresExactMatch];
	
	ZGSymbolRange symbolRange = {};
	BOOL foundSymbol = NO;
	for (NSValue *symbolValue in symbols)
	{
		[symbolValue getValue:&symbolRange];
		if (symbolRange.location > pastAddress)
		{
			foundSymbol = YES;
			break;
		}
	}
	
	if (foundSymbol)
	{
		return @(symbolRange.location);
	}
	
	if (allowsWrapping && symbols.count > 0)
	{
		ZGSymbolRange firstSymbolRange = {};
		[symbols[0] getValue:&firstSymbolRange];
		
		return @(firstSymbolRange.location);
	}
	
	return nil;
}

@end
