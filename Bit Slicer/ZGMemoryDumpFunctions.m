/*
 * Copyright (c) 2014 Mayur Pawashe
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
#import "ZGProtectionDescription.h"
#import "ZGMachBinary.h"
#import "ZGMachBinaryInfo.h"
#import "ZGProcess.h"
#import "NSArrayAdditions.h"
#import "ZGDebugLogging.h"

BOOL ZGDumpAllDataToDirectory(NSString *directory, ZGProcess *process, id <ZGSearchProgressDelegate> delegate)
{
	NSString *mergedPath = [directory stringByAppendingPathComponent:ZGLocalizedStringFromDumpAllMemoryTable(@"mergedFilename")];
	
	FILE *mergedFile = fopen(mergedPath.UTF8String, "w");
	if (mergedFile == NULL)
	{
		NSLog(@"Failed to create merged file at %@ with error %s", mergedPath, strerror(errno));
		return NO;
	}
	
	NSArray<ZGRegion *> *regions = [ZGRegion submapRegionsFromProcessTask:process.processTask];
	
	ZGSearchProgress *searchProgress = [[ZGSearchProgress alloc] initWithProgressType:ZGSearchProgressMemoryDumping maxProgress:regions.count];
	
	dispatch_async(dispatch_get_main_queue(), ^{
		[delegate progressWillBegin:searchProgress];
	});
	
	NSUInteger regionNumber = 0;
	for (ZGRegion *region in regions)
	{
		if ((region.protection & VM_PROT_READ) != 0)
		{
			ZGMemorySize outputSize = region.size;
			void *bytes = NULL;
			if (ZGReadBytes(process.processTask, region.address, &bytes, &outputSize))
			{
				NSString *regionPath = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"(%lu) 0x%llX - 0x%llX %@", (unsigned long)regionNumber, region.address, region.address + outputSize, ZGProtectionDescription(region.protection)]];
				
				NSData *regionData = [NSData dataWithBytesNoCopy:bytes length:outputSize freeWhenDone:NO];
				
				BOOL wroteRegionOutToFile = [regionData writeToFile:regionPath atomically:YES];
				if (wroteRegionOutToFile)
				{
					if (fwrite(regionData.bytes, regionData.length, 1, mergedFile) == 0)
					{
						ZG_LOG(@"Error: Failed to dump region bytes 0x%llX - 0x%llX to merge file", region.address, region.address + outputSize);
					}
					regionNumber++;
				}
				
				ZGFreeBytes(bytes, outputSize);
			}
		}
		
		dispatch_async(dispatch_get_main_queue(), ^{
			searchProgress.progress++;
			[delegate progress:searchProgress advancedWithResultSet:[NSData data]];
		});
		
		if (searchProgress.shouldCancelSearch)
		{
			break;
		}
	}
	
	fclose(mergedFile);
	
	if (!searchProgress.shouldCancelSearch)
	{
		NSString *imagesPath = [directory stringByAppendingPathComponent:ZGLocalizedStringFromDumpAllMemoryTable(@"machBinaryImagesFilename")];
		
		NSArray<ZGMachBinary *> *machBinaries = [ZGMachBinary machBinariesInProcess:process];
		NSError *machBinaryImagesError = nil;
		
		NSArray<NSString *> *header = @[[@"#" stringByAppendingString:[@[@"Path", @"Start", @"End"] componentsJoinedByString:@"\t"]]];
		if (![[[header arrayByAddingObjectsFromArray:[machBinaries zgMapUsingBlock:^(ZGMachBinary *machBinary) {
			NSString *filePath = [machBinary filePathInProcess:process];
			
			ZGMachBinaryInfo *machBinaryInfo = [machBinary machBinaryInfoInProcess:process];
			NSRange imageRange = machBinaryInfo.totalSegmentRange;
			
			return [@[filePath, [NSString stringWithFormat:@"0x%lX", imageRange.location], [NSString stringWithFormat:@"0x%lX", imageRange.location + imageRange.length]] componentsJoinedByString:@"\t"];
		}]] componentsJoinedByString:@"\n"] writeToFile:imagesPath atomically:YES encoding:NSUTF8StringEncoding error:&machBinaryImagesError])
		{
			NSLog(@"Failed to write mach binary images info file at %@ with error: %@", imagesPath, machBinaryImagesError);
		}
	}
	
	return YES;
}
