//
//  _DDOperatorInfo.m
//  DDMathParser
//
//  Created by Dave DeLong on 10/1/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "_DDOperatorInfo.h"

@implementation _DDOperatorInfo

@synthesize arity=_arity;
@synthesize defaultAssociativity=_defaultAssociativity;
@synthesize precedence=_precedence;
@synthesize token=_token;
@synthesize function=_function;

- (id)initWithOperatorFunction:(NSString *)function token:(NSString *)token arity:(DDOperatorArity)arity precedence:(NSInteger)precedence associativity:(DDOperatorAssociativity)associativity {
    self = [super init];
    if (self) {
        _arity = arity;
        _defaultAssociativity = associativity;
        _precedence = precedence;
        _token = DD_RETAIN(token);
        _function = DD_RETAIN(function);        
    }
    return self;
}

+ (id)infoForOperatorFunction:(NSString *)function token:(NSString *)token arity:(DDOperatorArity)arity precedence:(NSInteger)precedence associativity:(DDOperatorAssociativity)associativity {
    return DD_AUTORELEASE([[self alloc] initWithOperatorFunction:function token:token arity:arity precedence:precedence associativity:associativity]);
}

+ (NSArray *)infosForOperatorFunction:(NSString *)operator {
    static dispatch_once_t onceToken;
    static NSMutableDictionary *_operatorLookup = nil;
    dispatch_once(&onceToken, ^{
        _operatorLookup = [[NSMutableDictionary alloc] init];
        
        NSArray *operators = [self allOperators];
        for (_DDOperatorInfo *info in operators) {
            NSString *key = [info function];
            
            NSMutableArray *value = [_operatorLookup objectForKey:key];
            if (value == nil) {
                value = [NSMutableArray array];
                [_operatorLookup setObject:value forKey:key];
            }
            [value addObject:info];
        }
        
        // this is to make sure all of the operators are defined correctly
        _DDOperatorInfo *baseInfo = nil;
        for (NSString *functionName in _operatorLookup) {
            NSArray *operatorInfos = [_operatorLookup objectForKey:functionName];
            baseInfo = [operatorInfos lastObject];
            for (_DDOperatorInfo *info in operatorInfos) {
                NSAssert([info precedence] == [baseInfo precedence], @"mismatched operator precedences");
                NSAssert([info arity] == [baseInfo arity], @"mismatched operator arity");
                NSAssert([info defaultAssociativity] == [baseInfo defaultAssociativity], @"mismatched operator associativity");
            }
        }
    });
    return [_operatorLookup objectForKey:operator];
}

+ (NSArray *)infosForOperatorToken:(NSString *)token {
    static dispatch_once_t onceToken;
    static NSMutableDictionary *_operatorLookup = nil;
    dispatch_once(&onceToken, ^{
        _operatorLookup = [[NSMutableDictionary alloc] init];
        
        NSArray *operators = [self allOperators];
        for (_DDOperatorInfo *info in operators) {
            
            NSMutableArray *value = [_operatorLookup objectForKey:[info token]];
            if (value == nil) {
                value = [NSMutableArray array];
                [_operatorLookup setObject:value forKey:[info token]];
            }
            [value addObject:info];
        }
    });
    return [_operatorLookup objectForKey:token];
}

#if !DD_HAS_ARC
- (void)dealloc {
    [_token release];
    [_function release];
    [super dealloc];
}
#endif

+ (NSArray *)_buildOperators {
    NSMutableArray *operators = [NSMutableArray array];
    NSInteger precedence = 0;
    
    [operators addObject:[self infoForOperatorFunction:DDOperatorLogicalOr token:@"||" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    // \u2228 is ∨
    [operators addObject:[self infoForOperatorFunction:DDOperatorLogicalOr token:@"\u2228" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    precedence++;
    
    [operators addObject:[self infoForOperatorFunction:DDOperatorLogicalAnd token:@"&&" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    // \u2227 is ∧
    [operators addObject:[self infoForOperatorFunction:DDOperatorLogicalAnd token:@"\u2227" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    precedence++;
    
    // == and != have the same precedence
    [operators addObject:[self infoForOperatorFunction:DDOperatorLogicalEqual token:@"==" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    [operators addObject:[self infoForOperatorFunction:DDOperatorLogicalEqual token:@"=" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    [operators addObject:[self infoForOperatorFunction:DDOperatorLogicalNotEqual token:@"!=" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    precedence++;
    
    [operators addObject:[self infoForOperatorFunction:DDOperatorLogicalLessThan token:@"<" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    precedence++;
    
    [operators addObject:[self infoForOperatorFunction:DDOperatorLogicalGreaterThan token:@">" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    precedence++;
    
    [operators addObject:[self infoForOperatorFunction:DDOperatorLogicalLessThanOrEqual token:@"<=" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    // \u2264 is ≤
    [operators addObject:[self infoForOperatorFunction:DDOperatorLogicalLessThanOrEqual token:@"\u2264" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    precedence++;
    
    [operators addObject:[self infoForOperatorFunction:DDOperatorLogicalGreaterThanOrEqual token:@">=" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    // \u2265 is ≥
    [operators addObject:[self infoForOperatorFunction:DDOperatorLogicalGreaterThanOrEqual token:@"\u2265" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    precedence++;
    
    [operators addObject:[self infoForOperatorFunction:DDOperatorLogicalNot token:@"!" arity:DDOperatorArityUnary precedence:precedence associativity:DDOperatorAssociativityRight]];
    // \u00AC is ¬
    [operators addObject:[self infoForOperatorFunction:DDOperatorLogicalNot token:@"\u00ac" arity:DDOperatorArityUnary precedence:precedence associativity:DDOperatorAssociativityRight]];
    precedence++;
    
    [operators addObject:[self infoForOperatorFunction:DDOperatorBitwiseOr token:@"|" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    precedence++;
    
    [operators addObject:[self infoForOperatorFunction:DDOperatorBitwiseXor token:@"^" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    precedence++;
    
    [operators addObject:[self infoForOperatorFunction:DDOperatorBitwiseAnd token:@"&" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    precedence++;
    
    [operators addObject:[self infoForOperatorFunction:DDOperatorLeftShift token:@"<<" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    precedence++;
    
    [operators addObject:[self infoForOperatorFunction:DDOperatorRightShift token:@">>" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    precedence++;
    
    // addition and subtraction have the same precedence
    [operators addObject:[self infoForOperatorFunction:DDOperatorAdd token:@"+" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    [operators addObject:[self infoForOperatorFunction:DDOperatorMinus token:@"-" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    // \u2212 is −
    [operators addObject:[self infoForOperatorFunction:DDOperatorMinus token:@"\u2212" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    precedence++;
    
    // multiplication and division have the same precedence
    [operators addObject:[self infoForOperatorFunction:DDOperatorMultiply token:@"*" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    // \u00d7 is ×
    [operators addObject:[self infoForOperatorFunction:DDOperatorMultiply token:@"\u00d7" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    [operators addObject:[self infoForOperatorFunction:DDOperatorDivide token:@"/" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    // \u00f7 is ÷
    [operators addObject:[self infoForOperatorFunction:DDOperatorDivide token:@"\u00f7" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    precedence++;
    
#if DD_INTERPRET_PERCENT_SIGN_AS_MOD
    [operators addObject:[self infoForOperatorFunction:DDOperatorModulo token:@"%" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    precedence++;
#endif
    
    [operators addObject:[self infoForOperatorFunction:DDOperatorBitwiseNot token:@"~" arity:DDOperatorArityUnary precedence:precedence associativity:DDOperatorAssociativityRight]];
    precedence++;
    
    // right associative unary operators have the same precedence
    [operators addObject:[self infoForOperatorFunction:DDOperatorUnaryMinus token:@"-" arity:DDOperatorArityUnary precedence:precedence associativity:DDOperatorAssociativityRight]];
    // \u2212 is −
    [operators addObject:[self infoForOperatorFunction:DDOperatorUnaryMinus token:@"\u2212" arity:DDOperatorArityUnary precedence:precedence associativity:DDOperatorAssociativityRight]];
    [operators addObject:[self infoForOperatorFunction:DDOperatorUnaryPlus token:@"+" arity:DDOperatorArityUnary precedence:precedence associativity:DDOperatorAssociativityRight]];
    precedence++;
    
    // all the left associative unary operators have the same precedence
    [operators addObject:[self infoForOperatorFunction:DDOperatorFactorial token:@"!" arity:DDOperatorArityUnary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    // \u00ba is º (option-0); not necessary a degree sign, but common enough for it
    [operators addObject:[self infoForOperatorFunction:DDOperatorDegree token:@"\u00ba" arity:DDOperatorArityUnary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    // \u00b0 is °
    [operators addObject:[self infoForOperatorFunction:DDOperatorDegree token:@"\u00b0" arity:DDOperatorArityUnary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    
#if !DD_INTERPRET_PERCENT_SIGN_AS_MOD
    [operators addObject:[self infoForOperatorFunction:DDOperatorPercent token:@"%" arity:DDOperatorArityUnary precedence:precedence associativity:DDOperatorAssociativityLeft]];
#endif
    
    precedence++;
    
    [operators addObject:[self infoForOperatorFunction:DDOperatorPower token:@"**" arity:DDOperatorArityBinary precedence:precedence associativity:DDOperatorAssociativityRight]];
    precedence++;
    
    // ( and ) have the same precedence
    // these are defined as unary right/left associative for convenience
    [operators addObject:[self infoForOperatorFunction:DDOperatorParenthesisOpen token:@"(" arity:DDOperatorArityUnary precedence:precedence associativity:DDOperatorAssociativityRight]];
    [operators addObject:[self infoForOperatorFunction:DDOperatorParenthesisClose token:@")" arity:DDOperatorArityUnary precedence:precedence associativity:DDOperatorAssociativityLeft]];
    precedence++;
    
    [operators addObject:[self infoForOperatorFunction:DDOperatorComma token:@"," arity:DDOperatorArityUnknown precedence:precedence associativity:DDOperatorAssociativityLeft]];
    precedence++;
    
    return operators;
}

+ (NSArray *)allOperators {
    static NSArray *_allOperators;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _allOperators = [[self _buildOperators] copy];
    });
    return _allOperators;
}

@end
