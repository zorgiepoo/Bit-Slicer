//
//  ZGBreakPoint.h
//  Bit Slicer
//
//  Created by Mayur Pawashe on 12/29/12.
//
//

#import <Foundation/Foundation.h>
#import "ZGMemoryTypes.h"

@class ZGVariable;
@class ZGProcess;

typedef enum
{
	ZGBreakPointWatchDataWrite,
	ZGBreakPointInstruction,
	ZGBreakPointSingleStepInstruction,
} ZGBreakPointType;

@interface ZGBreakPoint : NSObject

@property (assign, nonatomic) id delegate;
@property (readwrite, nonatomic) ZGMemoryMap task;
@property (readwrite, nonatomic) thread_act_t thread;
@property (strong, nonatomic) ZGVariable *variable;
@property (readwrite) ZGMemorySize watchSize;
@property (strong, nonatomic) ZGProcess *process;
@property (strong, nonatomic) NSArray *debugThreads;
@property (assign) ZGBreakPointType type;
@property (assign) BOOL needsToRestore;
@property (assign) BOOL steppingOver;
@property (assign) BOOL oneShot;
@property (assign) ZGMemoryAddress basePointer;

@end
