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
#import "_DDOperatorInfo.h"

static inline void DDOperatorSetAssociativity(NSString *o, DDOperatorAssociativity a) {
    NSArray *ops = [_DDOperatorInfo infosForOperatorFunction:o];
    for (_DDOperatorInfo *info in ops) {
        [info setDefaultAssociativity:a];
    }
}

static inline DDOperatorAssociativity DDOperatorGetAssociativity(NSString *o) {
    NSArray *ops = [_DDOperatorInfo infosForOperatorFunction:o];
    _DDOperatorInfo *info = [ops objectAtIndex:0];
    return [info defaultAssociativity];
}

@implementation DDParser

@synthesize bitwiseOrAssociativity;
@synthesize bitwiseXorAssociativity;
@synthesize bitwiseAndAssociativity;
@synthesize bitwiseLeftShiftAssociativity;
@synthesize bitwiseRightShiftAssociativity;
@synthesize additionAssociativity;
@synthesize multiplicationAssociativity;
@synthesize modAssociativity;
@synthesize powerAssociativity;

+ (void) initialize {
	if (self == [DDParser class]) {
		//determine what associativity NSPredicate/NSExpression is using
		//mathematically, it should be right associative, but it's usually parsed as left associative
		//rdar://problem/8692313
		NSExpression * powerExpression = [(NSComparisonPredicate *)[NSPredicate predicateWithFormat:@"2 ** 3 ** 2 == 0"] leftExpression];
		NSNumber * powerResult = [powerExpression expressionValueWithObject:nil context:nil];
		if ([powerResult intValue] == 512) {
			[self setDefaultPowerAssociativity:DDOperatorAssociativityRight];
		}
	}
    [super initialize];
}

+ (DDOperatorAssociativity) defaultBitwiseOrAssociativity { return DDOperatorGetAssociativity(DDOperatorBitwiseOr); }
+ (void) setDefaultBitwiseOrAssociativity:(DDOperatorAssociativity)newAssociativity {  DDOperatorSetAssociativity(DDOperatorBitwiseOr, newAssociativity); }

+ (DDOperatorAssociativity) defaultBitwiseXorAssociativity { return DDOperatorGetAssociativity(DDOperatorBitwiseXor); }
+ (void) setDefaultBitwiseXorAssociativity:(DDOperatorAssociativity)newAssociativity { DDOperatorSetAssociativity(DDOperatorBitwiseXor, newAssociativity); }

+ (DDOperatorAssociativity) defaultBitwiseAndAssociativity { return DDOperatorGetAssociativity(DDOperatorBitwiseAnd); }
+ (void) setDefaultBitwiseAndAssociativity:(DDOperatorAssociativity)newAssociativity { DDOperatorSetAssociativity(DDOperatorBitwiseAnd, newAssociativity); }

+ (DDOperatorAssociativity) defaultBitwiseLeftShiftAssociativity { return DDOperatorGetAssociativity(DDOperatorLeftShift); }
+ (void) setDefaultBitwiseLeftShiftAssociativity:(DDOperatorAssociativity)newAssociativity { DDOperatorSetAssociativity(DDOperatorLeftShift, newAssociativity); }

+ (DDOperatorAssociativity) defaultBitwiseRightShiftAssociativity { return DDOperatorGetAssociativity(DDOperatorRightShift); }
+ (void) setDefaultBitwiseRightShiftAssociativity:(DDOperatorAssociativity)newAssociativity { DDOperatorSetAssociativity(DDOperatorRightShift, newAssociativity); }

+ (DDOperatorAssociativity) defaultAdditionAssociativity { return DDOperatorGetAssociativity(DDOperatorAdd); }
+ (void) setDefaultAdditionAssociativity:(DDOperatorAssociativity)newAssociativity {
    DDOperatorSetAssociativity(DDOperatorAdd, newAssociativity);
    DDOperatorSetAssociativity(DDOperatorMinus, newAssociativity);
}

+ (DDOperatorAssociativity) defaultMultiplicationAssociativity { return DDOperatorGetAssociativity(DDOperatorMultiply); }
+ (void) setDefaultMultiplicationAssociativity:(DDOperatorAssociativity)newAssociativity {
    DDOperatorSetAssociativity(DDOperatorMultiply, newAssociativity);
    DDOperatorSetAssociativity(DDOperatorDivide, newAssociativity);
}

+ (DDOperatorAssociativity) defaultModAssociativity { return DDOperatorGetAssociativity(DDOperatorModulo); }
+ (void) setDefaultModAssociativity:(DDOperatorAssociativity)newAssociativity { DDOperatorSetAssociativity(DDOperatorModulo, newAssociativity); }

+ (DDOperatorAssociativity) defaultPowerAssociativity { return DDOperatorGetAssociativity(DDOperatorPower); }
+ (void) setDefaultPowerAssociativity:(DDOperatorAssociativity)newAssociativity { DDOperatorSetAssociativity(DDOperatorPower, newAssociativity); }


+ (id) parserWithString:(NSString *)string error:(NSError **)error {
    return DD_AUTORELEASE([[self alloc] initWithString:string error:error]);
}

- (id) initWithString:(NSString *)string error:(NSError **)error {
    DDMathStringTokenizer *t = [DDMathStringTokenizer tokenizerWithString:string error:error];
    return [self initWithTokenizer:t error:error];
}

+ (id)parserWithTokenizer:(DDMathStringTokenizer *)tokenizer error:(NSError **)error {
	return DD_AUTORELEASE([[self alloc] initWithTokenizer:tokenizer error:error]);
}

- (id)initWithTokenizer:(DDMathStringTokenizer *)t error:(NSError **)error {
	ERR_ASSERT(error);
	self = [super init];
	if (self) {
		tokenizer = DD_RETAIN(t);
		if (!tokenizer) {
			DD_RELEASE(self);
			return nil;
		}
		
		bitwiseOrAssociativity = [[self class] defaultBitwiseOrAssociativity];
		bitwiseXorAssociativity = [[self class] defaultBitwiseXorAssociativity];
		bitwiseAndAssociativity = [[self class] defaultBitwiseAndAssociativity];
		bitwiseLeftShiftAssociativity = [[self class] defaultBitwiseLeftShiftAssociativity];
		bitwiseRightShiftAssociativity = [[self class] defaultBitwiseRightShiftAssociativity];
		additionAssociativity = [[self class] defaultAdditionAssociativity];
		multiplicationAssociativity = [[self class] defaultMultiplicationAssociativity];
		modAssociativity = [[self class] defaultModAssociativity];
		powerAssociativity = [[self class] defaultPowerAssociativity];
	}
	return self;
}

#if !DD_HAS_ARC
- (void) dealloc {
	[tokenizer release];
	[super dealloc];
}
#endif

- (DDOperatorAssociativity) associativityForOperator:(NSString *)operatorType {
    if (operatorType == DDOperatorBitwiseOr) {
        return bitwiseOrAssociativity;
    }
    if (operatorType == DDOperatorBitwiseXor) {
        return bitwiseXorAssociativity;
    }
    if (operatorType == DDOperatorBitwiseAnd) {
        return bitwiseAndAssociativity;
    }
    if (operatorType == DDOperatorLeftShift) {
        return bitwiseLeftShiftAssociativity;
    }
    if (operatorType == DDOperatorRightShift) {
        return bitwiseRightShiftAssociativity;
    }
    if (operatorType == DDOperatorMinus || operatorType == DDOperatorAdd) {
        return additionAssociativity;
    }
    if (operatorType == DDOperatorDivide || operatorType == DDOperatorMultiply) {
        return multiplicationAssociativity;
    }
    if (operatorType == DDOperatorModulo) {
        return modAssociativity;
    }
    if (operatorType == DDOperatorPower) {
        return powerAssociativity;
    }
    
    return DDOperatorGetAssociativity(operatorType);
}

- (DDExpression *) parsedExpressionWithError:(NSError **)error {
	ERR_ASSERT(error);
	[tokenizer reset]; //reset the token stream
    
    DDExpression *expression = nil;
    
    _DDParserTerm *root = [_DDParserTerm rootTermWithTokenizer:tokenizer error:error];
    if ([root resolveWithParser:self error:error]) {
        expression = [root expressionWithError:error];
    }
    
	return expression;
}

@end
