/*
 * Created by Mayur Pawashe on 2/12/14.
 *
 * Copyright (c) 2014 zgcoder
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

#import "ZGMemoryDumpFunctions.h"
#import "ZGVirtualMemory.h"
#import "ZGSearchProgress.h"
#import "ZGRegion.h"

// helper function for ZGSaveAllDataToDirectory
static void ZGDumpPieceOfData(NSMutableData *currentData, ZGMemoryAddress currentStartingAddress, NSString *directory, int *fileNumber, FILE *mergedFile)
{
	if (currentData != nil)
	{
		ZGMemoryAddress endAddress = currentStartingAddress + [currentData length];
		(*fileNumber)++;
		[currentData
		 writeToFile:[directory stringByAppendingPathComponent:[[NSString alloc] initWithFormat:@"(%d) 0x%llX - 0x%llX", *fileNumber, currentStartingAddress, endAddress]]
		 atomically:NO];
		
		if (mergedFile != NULL)
		{
			fwrite(currentData.bytes, currentData.length, 1, mergedFile);
		}
	}
}

BOOL ZGDumpAllDataToDirectory(NSString *directory, ZGMemoryMap processTask, id <ZGSearchProgressDelegate> delegate)
{
	NSMutableData *currentData = nil;
	ZGMemoryAddress currentStartingAddress = 0;
	ZGMemoryAddress lastAddress = currentStartingAddress;
	int fileNumber = 0;
	
	FILE *mergedFile = fopen([directory stringByAppendingPathComponent:@"(All) Merged"].UTF8String, "w");
	
	NSArray *regions = [ZGRegion submapRegionsFromProcessTask:processTask];
	
	ZGSearchProgress *searchProgress = [[ZGSearchProgress alloc] initWithProgressType:ZGSearchProgressMemoryDumping maxProgress:regions.count];
	
	dispatch_async(dispatch_get_main_queue(), ^{
		[delegate progressWillBegin:searchProgress];
	});
	
	for (ZGRegion *region in regions)
	{
		if (lastAddress != region.address || !(region.protection & VM_PROT_READ))
		{
			// We're done with this piece of data
			ZGDumpPieceOfData(currentData, currentStartingAddress, directory, &fileNumber, mergedFile);
			currentData = nil;
		}
		
		if (region.protection & VM_PROT_READ)
		{
			if (!currentData)
			{
				currentData = [[NSMutableData alloc] init];
				currentStartingAddress = region.address;
			}
			
			// outputSize should not differ from size
			ZGMemorySize outputSize = region.size;
			void *bytes = NULL;
			if (ZGReadBytes(processTask, region.address, &bytes, &outputSize))
			{
				[currentData appendBytes:bytes length:(NSUInteger)outputSize];
				ZGFreeBytes(bytes, outputSize);
			}
		}
		
		lastAddress = region.address;
		
		dispatch_async(dispatch_get_main_queue(), ^{
			searchProgress.progress++;
			[delegate progress:searchProgress advancedWithResultSet:nil];
		});
  	    
		if (searchProgress.shouldCancelSearch)
		{
			break;
		}
	}
	
	if (!searchProgress.shouldCancelSearch)
	{
		ZGDumpPieceOfData(currentData, currentStartingAddress, directory, &fileNumber, mergedFile);
	}
	
	if (mergedFile != NULL)
	{
		fclose(mergedFile);
	}
	
	return YES;
}
