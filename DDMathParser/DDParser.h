//
//  DDParser.h
//  DDMathParser
//
//  Created by Dave DeLong on 11/24/10.
//  Copyright 2010 Home. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DDParserTypes.h"

@class DDMathStringTokenizer;
@class DDExpression;

@interface DDParser : NSObject {
	DDMathStringTokenizer * tokenizer;
	
	DDOperatorAssociativity bitwiseOrAssociativity;
	DDOperatorAssociativity bitwiseXorAssociativity;
	DDOperatorAssociativity bitwiseAndAssociativity;
	DDOperatorAssociativity bitwiseLeftShiftAssociativity;
	DDOperatorAssociativity bitwiseRightShiftAssociativity;
	DDOperatorAssociativity additionAssociativity;
	DDOperatorAssociativity multiplicationAssociativity;
	DDOperatorAssociativity modAssociativity;
	DDOperatorAssociativity powerAssociativity;
	
}

@property DDOperatorAssociativity bitwiseOrAssociativity;
@property DDOperatorAssociativity bitwiseXorAssociativity;
@property DDOperatorAssociativity bitwiseAndAssociativity;
@property DDOperatorAssociativity bitwiseLeftShiftAssociativity;
@property DDOperatorAssociativity bitwiseRightShiftAssociativity;
@property DDOperatorAssociativity additionAssociativity;
@property DDOperatorAssociativity multiplicationAssociativity;
@property DDOperatorAssociativity modAssociativity;
@property DDOperatorAssociativity powerAssociativity;

+ (DDOperatorAssociativity) defaultBitwiseOrAssociativity;
+ (void) setDefaultBitwiseOrAssociativity:(DDOperatorAssociativity)newAssociativity;

+ (DDOperatorAssociativity) defaultBitwiseXorAssociativity;
+ (void) setDefaultBitwiseXorAssociativity:(DDOperatorAssociativity)newAssociativity;

+ (DDOperatorAssociativity) defaultBitwiseAndAssociativity;
+ (void) setDefaultBitwiseAndAssociativity:(DDOperatorAssociativity)newAssociativity;

+ (DDOperatorAssociativity) defaultBitwiseLeftShiftAssociativity;
+ (void) setDefaultBitwiseLeftShiftAssociativity:(DDOperatorAssociativity)newAssociativity;

+ (DDOperatorAssociativity) defaultBitwiseRightShiftAssociativity;
+ (void) setDefaultBitwiseRightShiftAssociativity:(DDOperatorAssociativity)newAssociativity;

+ (DDOperatorAssociativity) defaultAdditionAssociativity;
+ (void) setDefaultAdditionAssociativity:(DDOperatorAssociativity)newAssociativity;

+ (DDOperatorAssociativity) defaultMultiplicationAssociativity;
+ (void) setDefaultMultiplicationAssociativity:(DDOperatorAssociativity)newAssociativity;

+ (DDOperatorAssociativity) defaultModAssociativity;
+ (void) setDefaultModAssociativity:(DDOperatorAssociativity)newAssociativity;

+ (DDOperatorAssociativity) defaultPowerAssociativity;
+ (void) setDefaultPowerAssociativity:(DDOperatorAssociativity)newAssociativity;

+ (id)parserWithTokenizer:(DDMathStringTokenizer *)tokenizer error:(NSError **)error;
- (id)initWithTokenizer:(DDMathStringTokenizer *)tokenizer error:(NSError **)error;

+ (id) parserWithString:(NSString *)string error:(NSError **)error;
- (id) initWithString:(NSString *)string error:(NSError **)error;

- (DDExpression *) parsedExpressionWithError:(NSError **)error;
- (DDOperatorAssociativity) associativityForOperator:(NSString *)operator;

@end
