//
//  DDParser.m
//  DDMathParser
//
//  Created by Dave DeLong on 11/24/10.
//  Copyright 2010 Home. All rights reserved.
//

#import "DDMathParser.h"
#import "DDParser.h"
#import "DDMathParserMacros.h"
#import "_DDParserTerm.h"
#import "DDParserTypes.h"
#import "DDMathStringTokenizer.h"
#import "DDMathStringTokenizer.h"
#import "DDMathStringToken.h"
#import "DDExpression.h"
#import "DDMathOperator_Internal.h"

@implementation DDParser {
	DDMathStringTokenizer * _tokenizer;
}

+ (instancetype)parserWithString:(NSString *)string error:(NSError * __autoreleasing *)error {
    return [[self alloc] initWithString:string error:error];
}

- (id)initWithString:(NSString *)string error:(NSError * __autoreleasing *)error {
    DDMathStringTokenizer *t = [[DDMathStringTokenizer alloc] initWithString:string operatorSet:nil error:error];
    return [self initWithTokenizer:t error:error];
}

+ (instancetype)parserWithTokenizer:(DDMathStringTokenizer *)tokenizer error:(NSError * __autoreleasing *)error {
	return [[self alloc] initWithTokenizer:tokenizer error:error];
}

- (id)initWithTokenizer:(DDMathStringTokenizer *)t error:(NSError * __autoreleasing *)error {
	ERR_ASSERT(error);
	self = [super init];
	if (self) {
        _operatorSet = t.operatorSet;
		_tokenizer = t;
		if (!_tokenizer) {
			return nil;
		}
	}
	return self;
}

- (DDOperatorAssociativity)associativityForOperatorFunction:(NSString *)function {
    DDMathOperator *operator = [_operatorSet operatorForFunction:function];
    return operator.associativity;
}

- (DDExpression *)parsedExpressionWithError:(NSError * __autoreleasing *)error {
	ERR_ASSERT(error);
	[_tokenizer reset]; //reset the token stream
    
    DDExpression *expression = nil;
    
    _DDParserTerm *root = [_DDParserTerm rootTermWithTokenizer:_tokenizer error:error];
    if ([root resolveWithParser:self error:error]) {
        expression = [root expressionWithError:error];
    }
    
	return expression;
}

@end
