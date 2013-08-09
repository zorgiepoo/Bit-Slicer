//
//  ZGVirtualMemoryHelpers.h
//  Bit Slicer
//
//  Created by Mayur Pawashe on 8/9/13.
//
//

#import "ZGMemoryTypes.h"
#import "ZGVariableTypes.h"

@class ZGSearchData;
@class ZGSearchProgress;
@class ZGRegion;

BOOL ZGTaskExistsForProcess(pid_t process, ZGMemoryMap *task);
BOOL ZGGetTaskForProcess(pid_t process, ZGMemoryMap *task);
void ZGFreeTask(ZGMemoryMap task);

NSArray *ZGRegionsForProcessTask(ZGMemoryMap processTask);
NSUInteger ZGNumberOfRegionsForProcessTask(ZGMemoryMap processTask);

void ZGFreeData(NSArray *dataArray);
NSArray *ZGGetAllData(ZGMemoryMap processTask, ZGSearchData *searchData, ZGSearchProgress *searchProgress);
void *ZGSavedValue(ZGMemoryAddress address, ZGSearchData * __unsafe_unretained searchData, ZGRegion **hintedRegionReference, ZGMemorySize dataSize);
BOOL ZGSaveAllDataToDirectory(NSString *directory, ZGMemoryMap processTask, ZGSearchProgress *searchProgress);

ZGMemorySize ZGGetStringSize(ZGMemoryMap processTask, ZGMemoryAddress address, ZGVariableType dataType, ZGMemorySize oldSize);
