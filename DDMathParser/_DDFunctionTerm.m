//
//  _DDFunctionTerm.m
//  DDMathParser
//
//  Created by Dave DeLong on 7/12/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "DDMathParser.h"
#import "_DDFunctionTerm.h"
#import "DDMathStringToken.h"
#import "DDMathStringTokenizer.h"
#import "DDMathParserMacros.h"
#import "_DDOperatorTerm.h"

#import "DDExpression.h"

@implementation _DDFunctionTerm
@synthesize functionName;

- (id)_initWithFunction:(NSString *)function subterms:(NSArray *)terms error:(NSError **)error {
    self = [super _initWithSubterms:terms error:error];
    if (self) {
        functionName = [function copy];
    }
    return self;
}

- (id)_initWithTokenizer:(DDMathStringTokenizer *)tokenizer error:(NSError **)error {
    ERR_ASSERT(error);
    DDMathStringToken *t = [tokenizer nextToken];
    
    self = [super _initWithTokenizer:tokenizer error:error];
    if (self) {
        functionName = [[t token] copy];
        
        // process the subterms to group them up by commas
        NSMutableArray *newSubterms = [NSMutableArray array];
        NSRange subrange = NSMakeRange(0, 0);
        for (_DDParserTerm *term in [self subterms]) {
            if ([term type] == DDParserTermTypeOperator && [(_DDOperatorTerm *)term operatorType] == DDOperatorComma) {
                NSArray *parameterGroupTerms = [[self subterms] subarrayWithRange:subrange];
                
                if ([parameterGroupTerms count] != 1) {
                    _DDGroupTerm *parameterGroup = [[_DDGroupTerm alloc] _initWithSubterms:parameterGroupTerms error:error];
                    if (parameterGroup) {
                        [newSubterms addObject:parameterGroup];
                    }
                    DD_RELEASE(parameterGroup);
                } else {
                    // there's only one term in this parameter; no need to group it in parentheses
                    [newSubterms addObject:[parameterGroupTerms objectAtIndex:0]];
                }
                
                subrange.location = NSMaxRange(subrange)+1;
                subrange.length = 0;
            } else {
                subrange.length++;
            }
        }
        
        // get the last parameter
        NSRange rangeOfLastParameter;
        rangeOfLastParameter.location = subrange.location;
        rangeOfLastParameter.length = [[self subterms] count]-rangeOfLastParameter.location;
        if (rangeOfLastParameter.length > 1) {
            NSArray *lastParameters = [[self subterms] subarrayWithRange:rangeOfLastParameter];
            _DDGroupTerm *parameterGroup = [[_DDGroupTerm alloc] _initWithSubterms:lastParameters error:error];
            [newSubterms addObject:parameterGroup];
            DD_RELEASE(parameterGroup);
        } else if (rangeOfLastParameter.length == 1) {
            [newSubterms addObject:[[self subterms] objectAtIndex:rangeOfLastParameter.location]];
        }
        
        [self _setSubterms:newSubterms];
    } else {
        *error = ERR(DDErrorCodeImbalancedParentheses, @"missing parentheses after function \"%@\"", t);
    }
    return self;
}

#if !DD_HAS_ARC
- (void)dealloc {
    [functionName release];
    [super dealloc];
}
#endif

- (DDParserTermType)type { return DDParserTermTypeFunction; }

- (NSString *)description {
    NSArray *parameterDescriptions = [[self subterms] valueForKey:@"description"];
    NSString *parameters = [parameterDescriptions componentsJoinedByString:@","];
    return [NSString stringWithFormat:@"%@(%@)", functionName, parameters];
}

- (BOOL)resolveWithParser:(DDParser *)parser error:(NSError **)error {
    if ([self isResolved]) { return YES; }
    
    for (_DDParserTerm *term in [self subterms]) {
        if (![term resolveWithParser:parser error:error]) {
            return NO;
        }
    }
    
    [self setResolved:YES];
    return YES;
}

- (DDExpression *)expressionWithError:(NSError **)error {
    ERR_ASSERT(error);
    
    NSMutableArray *parameters = [NSMutableArray array];
    for (_DDParserTerm *term in [self subterms]) {
        DDExpression *parameter = [term expressionWithError:error];
        if (!parameter) { return nil; }
        
        [parameters addObject:parameter];
    }
    
    return [DDExpression functionExpressionWithFunction:functionName arguments:parameters error:error];
}

@end
