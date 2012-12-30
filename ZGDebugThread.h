//
//  ZGDebugThread.h
//  Bit Slicer
//
//  Created by Mayur Pawashe on 12/29/12.
//
//

#import <Foundation/Foundation.h>

@interface ZGDebugThread : NSObject

@property (readwrite) thread_act_t thread;
@property (readwrite) int registerNumber;

@end
