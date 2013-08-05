//
//  _DDFunctionContainer.m
//  DDMathParser
//
//  Created by Dave DeLong on 7/14/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "_DDFunctionContainer.h"

@implementation _DDFunctionContainer
@synthesize function;
@synthesize aliases;

+ (NSString *)normalizedAlias:(NSString *)alias {
    return [alias lowercaseString];
}

- (id)initWithFunction:(DDMathFunction)f name:(NSString *)name {
    self = [super init];
    if (self) {
        [self setFunction:f];
        aliases = [[NSMutableSet alloc] init];
        [self addAlias:name];
    }
    return self;
}

#if !DD_HAS_ARC
- (void)dealloc {
    [function release];
    [aliases release];
    [super dealloc];
}
#endif

- (NSMutableSet *)_aliases {
    return (NSMutableSet *)aliases;
}

- (NSString *)_normalizedAlias:(NSString *)alias {
    return [alias lowercaseString];
}

- (void)addAlias:(NSString *)alias {
    [[self _aliases] addObject:[_DDFunctionContainer normalizedAlias:alias]];
}

- (void)removeAlias:(NSString *)alias {
    [[self _aliases] removeObject:[_DDFunctionContainer normalizedAlias:alias]];
}

- (BOOL)containsAlias:(NSString *)alias {
    return [aliases containsObject:[_DDFunctionContainer normalizedAlias:alias]];
}

@end
