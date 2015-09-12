//
//  CoreSymbolication.h
//
//  Created by R J Cooper on 05/06/2012.
//  This file: Copyright (c) 2012 Mountainstorm
//  API: Copyright (c) 2008 Apple Inc. All rights reserved.
//  
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//  
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//  
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

//
// Derived by looking at use within the dtrace source and a little bit of IDA work
//
// See the unit testcases for examples of how to use the API; its a really nice symbol
// api, a real shame Apple dont make it a public framework. 
//
// Things you might want to know;
//  - a Symbolicator is a top level object representing the kernel/process etc
//  - a Symbolicator contains multiple SymbolOwners
// 
//  - a SymbolOwner represents a blob which owns symbols e.g. executable, library
//  - a SymbolOwner contains multiple regions and contains multiple symbols
//
//  - a Region represents a continuous block of memory within a symbol owner e.g. the __TEXT section
//  - a Region contains multiple symbols ... not it doesn't own them, just contains them
//
//  - a Symbol represents a symbol e.g. function, variable
//

#if !defined(CS_CORESYMBOLICATION_CORESYMBOLICATION__)
#define CS_CORESYMBOLICATION_CORESYMBOLICATION__ 1
#define CS_CORESYMBOLICATION_CORESYMBOLICATION__ 1


#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach.h>




/*
 * Defines
 */
#define kCSNull								((CSTypeRef) {NULL, NULL})

//#define kCSNow								0x80000000u
// See https://github.com/mountainstorm/CoreSymbolication/issues/2
#define kCSNow								0x8000000000000000llu

// we've no idea what value kCSSymbolOwnerDataFoundDsym has; its only use in dtrace has been optimised out
#define kCSSymbolOwnerDataFoundDsym			0
#define kCSSymbolOwnerIsAOut				0
#define kCSSymbolicatorTrackDyldActivity	1

#define kCSNotificationPing 		1
#define kCSNotificationInitialized	0x10
#define kCSNotificationDyldLoad		0x100
#define kCSNotificationDyldUnload	0x101
// kCSNotificationTimeout must be a value greater than 0xFFF, but not 0x1000 or 0x1001
#define kCSNotificationTimeout		0x1002
#define kCSNotificationTaskExit		0x1000
#define kCSNotificationFini			0x80000000




/*
 * Types
 */
// Under the hood the framework basically just calls through to a set of C++ libraries
struct CSTypeRef {
	void* csCppData;	// typically retrieved using CSCppSymbol...::data(csData & 0xFFFFFFF8)
	void* csCppObj;		// a pointer to the actual CSCppObject
};
typedef struct CSTypeRef CSTypeRef;


typedef CSTypeRef CSSymbolicatorRef;
typedef CSTypeRef CSSymbolOwnerRef;
typedef CSTypeRef CSSymbolRef;
typedef CSTypeRef CSRegionRef;


struct CSRange {
   unsigned long long location;
   unsigned long long length;
};
typedef struct CSRange CSRange;


// Note: this structure may well be wrong
typedef struct CSNotificationData {
	CSSymbolicatorRef symbolicator;
	union {
		struct {
			long value;
		} ping;
		
		struct {
			CSSymbolOwnerRef symbolOwner;
		} dyldLoad;
	} u;
} CSNotificationData;


typedef void (^CSNotification)(uint32_t notification_type, CSNotificationData data);
typedef void (^CSSymbolOwnerInterator)(CSSymbolOwnerRef owner);
typedef void (^CSSymbolIterator)(CSSymbolRef symbol);




/*
 * Generic/Utility functions
 */
// I'm guessing CSTypeRef stuff follows the standard Apple/CoreFoundation Create/Get ownership rules
void CSRelease(CSTypeRef type);

Boolean CSIsNull(CSTypeRef type);
Boolean CSArchitectureIs64Bit(cpu_type_t type);




/*
 * Symbolicator functions
 */
CSSymbolicatorRef CSSymbolicatorCreateWithMachKernel(void);
CSSymbolicatorRef CSSymbolicatorCreateWithTask(vm_map_t task);
pid_t CSSymbolicatorGetPid(CSSymbolicatorRef symbolicator);
cpu_type_t CSSymbolicatorGetArchitecture(CSSymbolicatorRef symbolicator);
CSSymbolOwnerRef CSSymbolicatorGetSymbolOwnerWithAddressAtTime(CSSymbolicatorRef symbolicator, mach_vm_address_t addr, uint64_t time);
CSSymbolRef CSSymbolicatorGetSymbolWithAddressAtTime(CSSymbolicatorRef symbolicator, mach_vm_address_t addr, uint64_t time);
CSSymbolOwnerRef CSSymbolicatorGetSymbolOwnerWithUUIDAtTime(CSSymbolicatorRef symbolicator, CFUUIDRef uuid, uint64_t time);

long CSSymbolicatorForeachSymbolOwnerAtTime(CSSymbolicatorRef symbolicator, uint64_t time, CSSymbolOwnerInterator it);
long CSSymbolicatorForeachSymbolOwnerWithFlagsAtTime(CSSymbolicatorRef symbolicator, long flags, uint64_t time, CSSymbolOwnerInterator it);
long CSSymbolicatorForeachSymbolOwnerWithPathAtTime(CSSymbolicatorRef symbolicator, const char* name, uint64_t time, CSSymbolOwnerInterator it);
long CSSymbolicatorForeachSymbolOwnerWithNameAtTime(CSSymbolicatorRef symbolicator, const char* name, uint64_t time, CSSymbolOwnerInterator it);

CSSymbolicatorRef CSSymbolicatorCreateWithTaskFlagsAndNotification(task_t task, 
																   long flags, 
																   CSNotification notification);




/*
 * SymbolOwner functions
 */
const char* CSSymbolOwnerGetPath(CSSymbolOwnerRef symbol);
const char* CSSymbolOwnerGetName(CSSymbolOwnerRef symbol);
vm_address_t CSSymbolOwnerGetBaseAddress(CSSymbolOwnerRef owner);
cpu_type_t CSSymbolOwnerGetArchitecture(CSSymbolOwnerRef owner);
Boolean CSSymbolOwnerIsObject(CSSymbolOwnerRef owner);
long CSSymbolOwnerGetDataFlags(CSSymbolOwnerRef owner);
CSRegionRef CSSymbolOwnerGetRegionWithName(CSSymbolOwnerRef owner, const char* name);
CSSymbolRef CSSymbolOwnerGetSymbolWithName(CSSymbolOwnerRef owner, const char* name);
CSSymbolRef CSSymbolOwnerGetSymbolWithAddress(CSSymbolOwnerRef owner, mach_vm_address_t addr);

long CSSymbolOwnerForeachSymbol(CSSymbolOwnerRef owner, CSSymbolIterator each);




/*
 * Symbol functions
 */
Boolean CSSymbolIsExternal(CSSymbolRef symbol);
Boolean CSSymbolIsFunction(CSSymbolRef symbol);
Boolean CSSymbolIsUnnamed(CSSymbolRef symbol);

const char* CSSymbolGetName(CSSymbolRef symbol);
const char* CSSymbolGetMangledName(CSSymbolRef symbol);
CSRange CSSymbolGetRange(CSSymbolRef symbol);
CSSymbolOwnerRef CSSymbolGetSymbolOwner(CSSymbolRef symbol);




/*
 * Region functions
 */
const char* CSRegionGetName(CSRegionRef region);

long CSRegionForeachSymbol(CSRegionRef region, CSSymbolIterator each);




/*
 * complete exported function list - if I get bored I'll add them all :)
 *
 _CSArchitectureGetCurrent
 _CSArchitectureGetFamilyName
 _CSArchitectureIs32Bit
 _CSArchitectureIs64Bit
 _CSArchitectureIsArm
 _CSArchitectureIsBigEndian
 _CSArchitectureIsI386
 _CSArchitectureIsLittleEndian
 _CSArchitectureIsPPC
 _CSArchitectureIsPPC64
 _CSArchitectureIsX86_64
 _CSArchitectureMatchesArchitecture
 _CSCopyDescription
 _CSCopyDescriptionWithIndent
 _CSEqual
 _CSGetRetainCount
 _CSIsNull
 _CSRangeContainsRange
 _CSRangeIntersectsRange
 _CSRegionCopyDescriptionWithIndent
 _CSRegionForeachSourceInfo
 _CSRegionForeachSymbol
 _CSRegionGetName
 _CSRegionGetRange
 _CSRegionGetSymbolOwner
 _CSRegionGetSymbolicator
 _CSRelease
 _CSRetain
 _CSShow
 _CSSignatureAddSegment
 _CSSignatureAllocateSegments
 _CSSignatureCopy
 _CSSignatureEncodeSymbolOwner
 _CSSignatureEncodeSymbolicator
 _CSSignatureFreeSegments
 _CSSignatureSlideSegments
 _CSSourceInfoCopyDescriptionWithIndent
 _CSSourceInfoGetColumn
 _CSSourceInfoGetFilename
 _CSSourceInfoGetLineNumber
 _CSSourceInfoGetPath
 _CSSourceInfoGetRange
 _CSSourceInfoGetRegion
 _CSSourceInfoGetSymbol
 _CSSourceInfoGetSymbolOwner
 _CSSourceInfoGetSymbolicator
 _CSSymbolCopyDescriptionWithIndent
 _CSSymbolForeachSourceInfo
 _CSSymbolGetFlags
 _CSSymbolGetInstructionData
 _CSSymbolGetMangledName
 _CSSymbolGetName
 _CSSymbolGetRange
 _CSSymbolGetRegion
 _CSSymbolGetSymbolOwner
 _CSSymbolGetSymbolicator
 _CSSymbolIsArm
 _CSSymbolIsDwarf
 _CSSymbolIsDyldStub
 _CSSymbolIsExternal
 _CSSymbolIsFunction
 _CSSymbolIsObjcMethod
 _CSSymbolIsPrivateExternal
 _CSSymbolIsThumb
 _CSSymbolOwnerCacheFlush
 _CSSymbolOwnerCacheGetEntryCount
 _CSSymbolOwnerCacheGetFlags
 _CSSymbolOwnerCacheGetMemoryLimit
 _CSSymbolOwnerCacheGetMemoryUsed
 _CSSymbolOwnerCachePrintEntries
 _CSSymbolOwnerCachePrintStats
 _CSSymbolOwnerCacheResetStats
 _CSSymbolOwnerCacheSetFlags
 _CSSymbolOwnerCacheSetMemoryLimit
 _CSSymbolOwnerCopyDescriptionWithIndent
 _CSSymbolOwnerForeachRegion
 _CSSymbolOwnerForeachRegionWithName
 _CSSymbolOwnerForeachSourceInfo
 _CSSymbolOwnerForeachSymbol
 _CSSymbolOwnerForeachSymbolWithMangledName
 _CSSymbolOwnerForeachSymbolWithName
 _CSSymbolOwnerGetArchitecture
 _CSSymbolOwnerGetBaseAddress
 _CSSymbolOwnerGetCompatibilityVersion
 _CSSymbolOwnerGetCurrentVersion
 _CSSymbolOwnerGetDataFlags
 _CSSymbolOwnerGetDsymPath
 _CSSymbolOwnerGetDsymVersion
 _CSSymbolOwnerGetFlags
 _CSSymbolOwnerGetLastModifiedTimestamp
 _CSSymbolOwnerGetLoadTimestamp
 _CSSymbolOwnerGetName
 _CSSymbolOwnerGetPath
 _CSSymbolOwnerGetRegionCount
 _CSSymbolOwnerGetRegionWithAddress
 _CSSymbolOwnerGetSourceInfoCount
 _CSSymbolOwnerGetSourceInfoWithAddress
 _CSSymbolOwnerGetSymbolCount
 _CSSymbolOwnerGetSymbolWithAddress
 _CSSymbolOwnerGetSymbolWithMangledName
 _CSSymbolOwnerGetSymbolWithName
 _CSSymbolOwnerGetSymbolicator
 _CSSymbolOwnerGetTransientUserData
 _CSSymbolOwnerGetUUID
 _CSSymbolOwnerGetUnloadTimestamp
 _CSSymbolOwnerIsAOut
 _CSSymbolOwnerIsBundle
 _CSSymbolOwnerIsCommpage
 _CSSymbolOwnerIsDsym
 _CSSymbolOwnerIsDyld
 _CSSymbolOwnerIsDyldSharedCache
 _CSSymbolOwnerIsDylib
 _CSSymbolOwnerIsMachO
 _CSSymbolOwnerIsObjCGCSupported
 _CSSymbolOwnerIsObjCRetainReleaseSupported
 _CSSymbolOwnerIsProtected
 _CSSymbolOwnerIsSlid
 _CSSymbolOwnerSetTransientUserData
 _CSSymbolicatorAddSymbolOwner
 _CSSymbolicatorCopyDescriptionWithIndent
 _CSSymbolicatorCreateSignature
 _CSSymbolicatorCreateWithPathAndArchitecture
 _CSSymbolicatorCreateWithPathArchitectureFlagsAndNotification
 _CSSymbolicatorCreateWithPid
 _CSSymbolicatorCreateWithPidFlagsAndNotification
 _CSSymbolicatorCreateWithSignature
 _CSSymbolicatorCreateWithTask
 _CSSymbolicatorCreateWithTaskFlagsAndNotification
 _CSSymbolicatorForceFullSymbolExtraction
 _CSSymbolicatorForeachRegionAtTime
 _CSSymbolicatorForeachRegionWithNameAtTime
 _CSSymbolicatorForeachSourceInfoAtTime
 _CSSymbolicatorForeachSymbolAtTime
 _CSSymbolicatorForeachSymbolOwnerAtTime
 _CSSymbolicatorForeachSymbolOwnerWithFlagsAtTime
 _CSSymbolicatorForeachSymbolOwnerWithNameAtTime
 _CSSymbolicatorForeachSymbolOwnerWithPathAtTime
 _CSSymbolicatorForeachSymbolWithMangledNameAtTime
 _CSSymbolicatorForeachSymbolWithNameAtTime
 _CSSymbolicatorForeachSymbolicatorWithPath
 _CSSymbolicatorForeachSymbolicatorWithPathFlagsAndNotification
 _CSSymbolicatorGetArchitecture
 _CSSymbolicatorGetDyldAllImageInfosAddress
 _CSSymbolicatorGetPid
 _CSSymbolicatorGetRegionCountAtTime
 _CSSymbolicatorGetRegionWithAddressAtTime
 _CSSymbolicatorGetSourceInfoCountAtTime
 _CSSymbolicatorGetSourceInfoWithAddressAtTime
 _CSSymbolicatorGetSymbolCountAtTime
 _CSSymbolicatorGetSymbolOwnerCountAtTime
 _CSSymbolicatorGetSymbolOwnerWithAddressAtTime
 _CSSymbolicatorGetSymbolOwnerWithNameAtTime
 _CSSymbolicatorGetSymbolWithAddressAtTime
 _CSSymbolicatorGetSymbolWithMangledNameAtTime
 _CSSymbolicatorGetSymbolWithMangledNameFromSymbolOwnerWithNameAtTime
 _CSSymbolicatorGetSymbolWithNameAtTime
 _CSSymbolicatorGetSymbolWithNameFromSymbolOwnerWithNameAtTime
 _CSSymbolicatorGetTask
 _CSSymbolicatorIsTaskTranslated
 _CSSymbolicatorIsTaskValid
 _CSSymbolicatorResymbolicate
 _CSSymbolicatorSetForceGlobalSafeMachVMReads
 _CSSymbolisStabs
 */
 
#endif /* ! __CORESYMBOLICATION_CORESYMBOLICATION__ */
