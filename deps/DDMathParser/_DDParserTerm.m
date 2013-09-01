//
//  _DDParserTerm.m
//  DDMathParser
//
//  Created by Dave DeLong on 7/11/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "DDMathParser.h"
#import "_DDParserTerm.h"
#import "DDMathStringTokenizer.h"
#import "DDMathStringToken.h"
#import "DDParser.h"
#import "DDMathParserMacros.h"

#import "_DDGroupTerm.h"
#import "_DDFunctionTerm.h"
#import "_DDNumberTerm.h"
#import "_DDVariableTerm.h"
#import "_DDOperatorTerm.h"

@interface _DDParserTerm ()

- (id)_initWithTokenizer:(DDMathStringTokenizer *)tokenizer error:(NSError **)error;

@end

@implementation _DDParserTerm

@synthesize resolved;
@synthesize type;
@synthesize token;

+ (id)rootTermWithTokenizer:(DDMathStringTokenizer *)tokenizer error:(NSError **)error {
    NSMutableArray *terms = [NSMutableArray array];
    while ([tokenizer peekNextToken] != nil) {
        _DDParserTerm *nextTerm = [_DDParserTerm termWithTokenizer:tokenizer error:error];
        if (!nextTerm) {
            return nil;
        }
        
        [terms addObject:nextTerm];
    }
    
    return DD_AUTORELEASE([[_DDGroupTerm alloc] _initWithSubterms:terms error:error]);
}

+ (id)termWithTokenizer:(DDMathStringTokenizer *)tokenizer error:(NSError **)error {
    ERR_ASSERT(error);
    DDMathStringToken *next = [tokenizer peekNextToken];
    if (next) {
        _DDParserTerm *term = nil;
        if ([next tokenType] == DDTokenTypeNumber) {
            term = [[_DDNumberTerm alloc] _initWithTokenizer:tokenizer error:error];
        } else if ([next tokenType] == DDTokenTypeVariable) {
            term = [[_DDVariableTerm alloc] _initWithTokenizer:tokenizer error:error];
        } else if ([next tokenType] == DDTokenTypeOperator) {
            if ([next operatorType] == DDOperatorParenthesisOpen) {
                term = [[_DDGroupTerm alloc] _initWithTokenizer:tokenizer error:error];
            } else {
                term = [[_DDOperatorTerm alloc] _initWithTokenizer:tokenizer error:error];
            }
        } else if ([next tokenType] == DDTokenTypeFunction) {
            term = [[_DDFunctionTerm alloc] _initWithTokenizer:tokenizer error:error];
        }
        
        return DD_AUTORELEASE(term);
    } else {
        *error = ERR(DDErrorCodeInvalidFormat, @"can't create a term with a nil token");
    }
    return nil;
}

- (id)_initWithToken:(DDMathStringToken *)t error:(NSError **)error {
#pragma unused(error)
    self = [super init];
    if (self) {
        resolved = NO;
        token = DD_RETAIN(t);
    }
    return self;
}

- (id)_initWithTokenizer:(DDMathStringTokenizer *)tokenizer error:(NSError **)error {
    return [self _initWithToken:[tokenizer nextToken] error:error];
}

#if !DD_HAS_ARC
- (void)dealloc {
    [token release];
    [super dealloc];
}
#endif

- (BOOL)resolveWithParser:(DDParser *)parser error:(NSError **)error {
#pragma unused(parser,error)
    return NO;
}

- (DDExpression *)expressionWithError:(NSError **)error {
    ERR_ASSERT(error);
    [NSException raise:NSInvalidArgumentException format:@"Subclasses must override the -%@ method", NSStringFromSelector(_cmd)];
    return nil;
}

@end
