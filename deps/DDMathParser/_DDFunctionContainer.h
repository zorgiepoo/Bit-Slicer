//
//  _DDFunctionContainer.h
//  DDMathParser
//
//  Created by Dave DeLong on 7/14/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DDMathParser.h"
#import "DDTypes.h"

@interface _DDFunctionContainer : NSObject {
    DDMathFunction function;
    NSSet *aliases;
}

@property (nonatomic,copy) DDMathFunction function;
@property (nonatomic,readonly,DD_STRONG) NSSet *aliases;

+ (NSString *)normalizedAlias:(NSString *)alias;

- (id)initWithFunction:(DDMathFunction)f name:(NSString *)name;

- (void)addAlias:(NSString *)alias;
- (void)removeAlias:(NSString *)alias;
- (BOOL)containsAlias:(NSString *)alias;

@end
