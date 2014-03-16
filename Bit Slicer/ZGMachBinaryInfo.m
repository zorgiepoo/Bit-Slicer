/*
 * Created by Mayur Pawashe on 1/30/14.
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

#import "ZGMachBinaryInfo.h"

#import <mach-o/loader.h>

typedef struct
{
	char name[16];
	NSRange range;
} ZGMachBinarySegment;

@interface ZGMachBinaryInfo ()

@property (nonatomic) ZGMemorySize slide;
@property (nonatomic) ZGMemoryAddress firstInstructionAddress; // aka location of __text section

@property (nonatomic) uint32_t numberOfSegments;
@property (nonatomic) ZGMachBinarySegment *segments;

@end

@implementation ZGMachBinaryInfo

- (id)initWithMachHeaderAddress:(ZGMemoryAddress)machHeaderAddress segmentBytes:(const void * const)segmentBytes commandSize:(uint32_t)commandSize
{
	self = [super init];
	if (self == nil)
	{
		return nil;
	}
	
	uint32_t maxNumberOfSegmentCommands = 0;
	const struct load_command *loadCommand = NULL;
	for (const void *commandBytes = segmentBytes; commandBytes < segmentBytes + commandSize; commandBytes += loadCommand->cmdsize)
	{
		loadCommand = commandBytes;
		if (loadCommand->cmd == LC_SEGMENT_64 || loadCommand->cmd == LC_SEGMENT)
		{
			maxNumberOfSegmentCommands++;
		}
	}
	
	if (maxNumberOfSegmentCommands == 0)
	{
		return nil;
	}
	
	self.segments = malloc(sizeof(*_segments) * maxNumberOfSegmentCommands);
	
	loadCommand = NULL;
	for (const void *commandBytes = segmentBytes; commandBytes < segmentBytes + commandSize; commandBytes += loadCommand->cmdsize)
	{
		loadCommand = commandBytes;
		
		if (loadCommand->cmd != LC_SEGMENT_64 && loadCommand->cmd != LC_SEGMENT)
		{
			continue;
		}
		
		const struct segment_command_64 *segmentCommand64 = commandBytes;
		const struct segment_command *segmentCommand32 = commandBytes;
		
		if ((loadCommand->cmd == LC_SEGMENT_64 && segmentCommand64->vmsize == 0) || (loadCommand->cmd == LC_SEGMENT && segmentCommand32->vmsize == 0))
		{
			continue;
		}
		
		ZGMachBinarySegment newSegment = {};
		strncpy(newSegment.name, segmentCommand32->segname, sizeof(newSegment.name));
		
		if (strcmp(newSegment.name, "__TEXT") == 0)
		{
			const void *sectionsOffset = loadCommand->cmd == LC_SEGMENT_64 ? commandBytes + sizeof(*segmentCommand64) : commandBytes + sizeof(*segmentCommand32);
			const struct section_64 *firstSection64 = sectionsOffset;
			const struct section *firstSection32 = sectionsOffset;
			
			const void *segmentVMAddressPointer = &segmentCommand32->vmaddr;
			
			// struct section has enough relevant fields to make this test for 64-bit as well
			if (sectionsOffset + sizeof(*firstSection32) <= commandBytes + loadCommand->cmdsize)
			{
				if (loadCommand->cmd == LC_SEGMENT_64)
				{
					// We could use firstSection64->offset instead, but this seems to catch some obfuscation cases
					uint64_t offset = firstSection64->addr - *(uint64_t *)segmentVMAddressPointer;
					self.firstInstructionAddress = machHeaderAddress + offset;
					self.slide = machHeaderAddress + offset - firstSection64->addr;
				}
				else
				{
					// We could use firstSection32->offset instead, but this seems to catch some obfuscation cases
					uint32_t offset = firstSection32->addr - *(uint32_t *)segmentVMAddressPointer;
					self.firstInstructionAddress = machHeaderAddress + offset;
					self.slide = machHeaderAddress + offset - firstSection32->addr;
				}
			}
		}
		// We assume __TEXT is the first segment, so we can obtain the slide needed by other segments
		// This is also assumed precondition below in -textSegmentRange
		// This might skip __PAGEZERO in some cases, but I don't think it's that important anyway
		else if (self.numberOfSegments == 0)
		{
			continue;
		}
		
		if (loadCommand->cmd == LC_SEGMENT_64)
		{
			newSegment.range = NSMakeRange(segmentCommand64->vmaddr + self.slide, segmentCommand64->vmsize);
		}
		else
		{
			newSegment.range = NSMakeRange(segmentCommand32->vmaddr + self.slide, segmentCommand32->vmsize);
		}
		
		self.segments[self.numberOfSegments] = newSegment;
		self.numberOfSegments++;
	}
	
	return self;
}

- (void)dealloc
{
	free(self.segments);
}

- (NSRange)totalSegmentRange
{
	if (self.numberOfSegments == 0) return NSMakeRange(0, 0);
	
	ZGMachBinarySegment firstSegment = self.segments[0];
	ZGMachBinarySegment lastSegment = self.segments[self.numberOfSegments - 1];
	
	return NSMakeRange(firstSegment.range.location, lastSegment.range.location - firstSegment.range.location + lastSegment.range.length);
}

- (NSString *)segmentNameAtAddress:(ZGMemoryAddress)address
{
	for (ZGMemorySize segmentIndex = 0; segmentIndex < self.numberOfSegments; segmentIndex++)
	{
		ZGMachBinarySegment *segment = self.segments + segmentIndex;
		if (segment->range.location <= address && address < segment->range.location + segment->range.length)
		{
			return @(segment->name);
		}
	}
	
	return nil;
}

@end

