//
//  DDMathEvaluator.h
//  DDMathParser
//
//  Created by Dave DeLong on 11/17/10.
//  Copyright 2010 Home. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DDTypes.h"

@class DDMathEvaluator;
@class DDExpression;

typedef DDMathFunction (^DDFunctionResolver)(NSString *);
typedef NSNumber* (^DDVariableResolver)(NSString *);

@interface DDMathEvaluator : NSObject {
    NSMutableArray *functions;
	NSMutableDictionary * functionMap;
    NSMutableArray *rewriteRules;
    DDFunctionResolver functionResolver;
    DDVariableResolver variableResolver;
    DDAngleMeasurementMode angleMeasurementMode;
}

@property (nonatomic) DDAngleMeasurementMode angleMeasurementMode; // default is Radians
@property (nonatomic, copy) DDFunctionResolver functionResolver;
@property (nonatomic, copy) DDVariableResolver variableResolver;

+ (id) sharedMathEvaluator;

- (BOOL) registerFunction:(DDMathFunction)function forName:(NSString *)functionName;
- (void) unregisterFunctionWithName:(NSString *)functionName;
- (NSArray *) registeredFunctions;

- (NSNumber *) evaluateString:(NSString *)expressionString withSubstitutions:(NSDictionary *)substitutions;
- (NSNumber *) evaluateString:(NSString *)expressionString withSubstitutions:(NSDictionary *)substitutions error:(NSError **)error;

- (BOOL) addAlias:(NSString *)alias forFunctionName:(NSString *)functionName;
- (void) removeAlias:(NSString *)alias;

- (void)addRewriteRule:(NSString *)rule forExpressionsMatchingTemplate:(NSString *)template condition:(NSString *)condition;
- (DDExpression *)expressionByRewritingExpression:(DDExpression *)expression;

@end
