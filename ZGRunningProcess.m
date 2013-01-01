/*
 * Created by Mayur Pawashe on 1/1/13.
 *
 * Copyright (c) 2012 zgcoder
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

#import "ZGRunningProcess.h"
#import <sys/types.h>
#import <sys/sysctl.h>

@interface ZGRunningProcess ()

@property (assign, nonatomic) BOOL is64Bit;
@property (assign, nonatomic) BOOL hasCachedArchitecture;

@end

@implementation ZGRunningProcess

#pragma mark Comparisons

- (BOOL)isEqual:(id)object
{
	return self.processIdentifier == [object processIdentifier];
}

#pragma mark On-the-fly Accessors

- (NSApplicationActivationPolicy)activationPolicy
{
	NSApplicationActivationPolicy activationPolicy = NSApplicationActivationPolicyProhibited;
	NSRunningApplication *runningApplication = [NSRunningApplication runningApplicationWithProcessIdentifier:self.processIdentifier];
	if (runningApplication)
	{
		activationPolicy = runningApplication.activationPolicy;
	}
	
	return activationPolicy;
}

- (NSImage *)icon
{
	NSRunningApplication *runningApplication = [NSRunningApplication runningApplicationWithProcessIdentifier:self.processIdentifier];
	return runningApplication ? runningApplication.icon : [NSImage imageNamed:@"NSDefaultApplicationIcon"];
}

// http://stackoverflow.com/questions/1350181/determine-a-processs-architecture
- (BOOL)is64Bit
{
	BOOL is64Bit = YES; // as we're migrating to 64-bit it's probably safer to default to this
	if (!self.hasCachedArchitecture)
	{
		BOOL error = NO;
		size_t mibLen = CTL_MAXNAME;
		int mib[mibLen];
		
		if (!(error = (sysctlnametomib("sysctl.proc_cputype", mib, &mibLen) != 0)))
		{
			mib[mibLen] = self.processIdentifier;
			mibLen++;
			
			cpu_type_t cpuType;
			size_t cpuTypeSize;
			cpuTypeSize = sizeof(cpuType);
			
			if (!(error = (sysctl(mib, (u_int)mibLen, &cpuType, &cpuTypeSize, 0, 0) != 0)))
			{
				is64Bit = (cpuType & CPU_ARCH_ABI64);
				self.is64Bit = is64Bit;
				self.hasCachedArchitecture = YES;
			}
		}
		
		if (error)
		{
			NSLog(@"ERROR obtaining architecture from process %d, %@.. Assuming 64-bit.", self.processIdentifier, self.name);
		}
	}
	else
	{
		is64Bit = _is64Bit;
	}
	
	return is64Bit;
}

@end
