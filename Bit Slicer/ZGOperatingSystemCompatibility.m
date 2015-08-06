/*
 * Created by Mayur Pawashe on 8/5/15.
 *
 * Copyright (c) 2015 zgcoder
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

#import "ZGOperatingSystemCompatibility.h"

#if __MAC_OS_X_VERSION_MAX_ALLOWED <= 1090

typedef struct
{
	NSInteger majorVersion;
	NSInteger minorVersion;
	NSInteger patchVersion;
} NSOperatingSystemVersion;

@interface NSProcessInfo (OperatingSystemCompatibility)

- (BOOL)isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion)operatingSystemVersion;

@end

#endif

BOOL ZGIsOnAtLeast10Dot(NSInteger minorVersion)
{
	NSProcessInfo *processInfo = [NSProcessInfo processInfo];
	// This selector exists in at least 10.10 (and possibly even 10.9 as a private API but we shouldn't rely on that)
	if ([processInfo respondsToSelector:@selector(isOperatingSystemAtLeastVersion:)])
	{
		return [processInfo isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){10, minorVersion, 0}];
	}
	
	assert(minorVersion == 9);
	return floor(NSFoundationVersionNumber) > NSFoundationVersionNumber10_8;
}

BOOL ZGIsOnElCapitanOrLater(void)
{
	return ZGIsOnAtLeast10Dot(11);
}

BOOL ZGIsOnYosemiteOrLater(void)
{
	return ZGIsOnAtLeast10Dot(10);
}

BOOL ZGIsOnMavericksOrLater(void)
{
	return ZGIsOnAtLeast10Dot(9);
}
