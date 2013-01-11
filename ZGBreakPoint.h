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
	ZGBreakPointInstruction
} ZGBreakPointType;

@interface ZGBreakPoint : NSObject

@property (assign, nonatomic) id delegate;
@property (readwrite, nonatomic) ZGMemoryMap task;
@property (strong, nonatomic) ZGVariable *variable;
@property (readwrite) ZGMemorySize watchSize;
@property (strong, nonatomic) ZGProcess *process;
@property (strong, nonatomic) NSArray *debugThreads;
@property (assign) ZGBreakPointType type;

@end
