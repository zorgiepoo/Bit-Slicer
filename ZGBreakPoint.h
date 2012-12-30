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

@interface ZGBreakPoint : NSObject

@property (assign, nonatomic) id delegate;
@property (readwrite, nonatomic) ZGMemoryMap task;
@property (strong, nonatomic) ZGVariable *variable;
@property (strong, nonatomic) ZGProcess *process;
@property (strong, nonatomic) NSArray *debugThreads;

@end
