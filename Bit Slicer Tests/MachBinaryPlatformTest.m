/*
 * Copyright (c) 2026 Mayur Pawashe
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

#import <XCTest/XCTest.h>
#import "ZGMachBinaryInfo.h"
#import <mach-o/loader.h>

#define TEST_SEGMENT_ADDRESS 0x100000000

// A binary info instance needs at least one segment command, so pair the build version with a __TEXT segment
static struct segment_command_64 ZGTextSegmentCommand(void)
{
	struct segment_command_64 segmentCommand = {0};
	segmentCommand.cmd = LC_SEGMENT_64;
	segmentCommand.cmdsize = sizeof(segmentCommand);
	strncpy(segmentCommand.segname, "__TEXT", sizeof(segmentCommand.segname));
	segmentCommand.vmaddr = TEST_SEGMENT_ADDRESS;
	segmentCommand.vmsize = 0x1000;
	return segmentCommand;
}

@interface MachBinaryPlatformTest : XCTestCase

@end

@implementation MachBinaryPlatformTest

- (ZGMachBinaryInfo *)machBinaryInfoWithPlatform:(uint32_t)platform
{
	struct segment_command_64 segmentCommand = ZGTextSegmentCommand();
	
	struct build_version_command buildVersionCommand = {0};
	buildVersionCommand.cmd = LC_BUILD_VERSION;
	buildVersionCommand.cmdsize = sizeof(buildVersionCommand);
	buildVersionCommand.platform = platform;
	
	uint8_t commandBytes[sizeof(segmentCommand) + sizeof(buildVersionCommand)];
	memcpy(commandBytes, &segmentCommand, sizeof(segmentCommand));
	memcpy(commandBytes + sizeof(segmentCommand), &buildVersionCommand, sizeof(buildVersionCommand));
	
	return [[ZGMachBinaryInfo alloc] initWithMachHeaderAddress:TEST_SEGMENT_ADDRESS segmentBytes:commandBytes commandSize:sizeof(commandBytes)];
}

- (void)testIOSPlatform
{
	XCTAssertEqual([self machBinaryInfoWithPlatform:PLATFORM_IOS].platform, (uint32_t)PLATFORM_IOS);
}

- (void)testMacOSPlatform
{
	XCTAssertEqual([self machBinaryInfoWithPlatform:PLATFORM_MACOS].platform, (uint32_t)PLATFORM_MACOS);
}

- (void)testMissingBuildVersionHasNoPlatform
{
	struct segment_command_64 segmentCommand = ZGTextSegmentCommand();
	
	ZGMachBinaryInfo *machBinaryInfo = [[ZGMachBinaryInfo alloc] initWithMachHeaderAddress:TEST_SEGMENT_ADDRESS segmentBytes:&segmentCommand commandSize:sizeof(segmentCommand)];
	
	XCTAssertEqual(machBinaryInfo.platform, (uint32_t)0);
}

- (void)testTruncatedBuildVersionHasNoPlatform
{
	struct segment_command_64 segmentCommand = ZGTextSegmentCommand();
	
	// Advertise a build version command that is too small to read a platform from
	struct load_command truncatedCommand = {0};
	truncatedCommand.cmd = LC_BUILD_VERSION;
	truncatedCommand.cmdsize = sizeof(truncatedCommand);
	
	uint8_t commandBytes[sizeof(segmentCommand) + sizeof(truncatedCommand)];
	memcpy(commandBytes, &segmentCommand, sizeof(segmentCommand));
	memcpy(commandBytes + sizeof(segmentCommand), &truncatedCommand, sizeof(truncatedCommand));
	
	ZGMachBinaryInfo *machBinaryInfo = [[ZGMachBinaryInfo alloc] initWithMachHeaderAddress:TEST_SEGMENT_ADDRESS segmentBytes:commandBytes commandSize:sizeof(commandBytes)];
	
	XCTAssertEqual(machBinaryInfo.platform, (uint32_t)0);
}

@end
