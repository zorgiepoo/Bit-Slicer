/*
 * Created by Mayur Pawashe on 8/9/13.
 *
 * Copyright (c) 2013 zgcoder
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

#import "ZGMemoryTypes.h"
#import "ZGVariableTypes.h"

#ifdef __cplusplus
extern "C" {
#endif

@class ZGSearchData;
@class ZGSearchProgress;
@class ZGRegion;

BOOL ZGTaskExistsForProcess(pid_t process, ZGMemoryMap *task);
BOOL ZGGetTaskForProcess(pid_t process, ZGMemoryMap *task);
void ZGFreeTask(ZGMemoryMap task);

ZGRegion *ZGBaseExecutableRegion(ZGMemoryMap processTask);
ZGMemoryAddress ZGBaseExecutableAddress(ZGMemoryMap processTask);
NSRange ZGTextRange(ZGMemoryMap processTask, ZGRegion *region, NSString **mappedFilePath, ZGMemoryAddress *machHeaderAddress, ZGMemoryAddress *slide);

NSArray *ZGRegionsForProcessTask(ZGMemoryMap processTask);
NSUInteger ZGNumberOfRegionsForProcessTask(ZGMemoryMap processTask);

NSArray *ZGRegionsForProcessTaskRecursively(ZGMemoryMap processTask);
	
NSString *ZGUserTagDescription(ZGMemoryMap processTask, ZGMemoryAddress address, ZGMemorySize size);

ZGMemoryAddress ZGFindExecutableImageWithCache(ZGMemoryMap processTask, NSString *partialImageName, NSMutableDictionary *cacheDictionary, NSError **error);
ZGRegion *ZGFindExecutableImage(ZGMemoryMap processTask, NSString *partialImageName);

ZGMemoryAddress ZGInstructionOffset(ZGMemoryMap processTask, NSMutableDictionary *cacheDictionary, ZGMemoryAddress instructionAddress, ZGMemorySize instructionSize, ZGMemoryAddress *slide, NSString **partialImageName);

NSArray *ZGMachBinaryRegions(ZGMemoryMap processTask);
NSString *ZGSectionName(ZGMemoryMap processTask, ZGMemoryAddress address, ZGMemorySize size, NSString **mappedFilePath, ZGMemoryAddress *relativeOffset, ZGMemoryAddress *slide);

void ZGFreeData(NSArray *dataArray);
NSArray *ZGGetAllData(ZGMemoryMap processTask, ZGSearchData *searchData, ZGSearchProgress *searchProgress);

BOOL ZGSaveAllDataToDirectory(NSString *directory, ZGMemoryMap processTask, ZGSearchProgress *searchProgress);

ZGMemorySize ZGGetStringSize(ZGMemoryMap processTask, ZGMemoryAddress address, ZGVariableType dataType, ZGMemorySize oldSize, ZGMemorySize maxStringSizeLimit);
	
#ifdef __cplusplus
}
#endif
