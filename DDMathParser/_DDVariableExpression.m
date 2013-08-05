//
//  _DDVariableExpression.m
//  DDMathParser
//
//  Created by Dave DeLong on 11/18/10.
//  Copyright 2010 Home. All rights reserved.
//

#import "DDMathParser.h"
#import "_DDVariableExpression.h"
#import "DDMathEvaluator.h"
#import "DDMathEvaluator+Private.h"
#import "DDMathParserMacros.h"

@implementation _DDVariableExpression

- (id) initWithVariable:(NSString *)v {
	self = [super init];
	if (self) {
        if ([v hasPrefix:@"$"]) {
            v = [v substringFromIndex:1];
        }
        if ([v length] == 0) {
            DD_RELEASE(self);
            return nil;
        }
		variable = [v copy];
	}
	return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    return [self initWithVariable:[aDecoder decodeObjectForKey:@"variable"]];
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:[self variable] forKey:@"variable"];
}

#if !DD_HAS_ARC
- (void) dealloc {
	[variable release];
	[super dealloc];
}
#endif

- (DDExpressionType) expressionType { return DDExpressionTypeVariable; }

- (NSString *) variable { return variable; }

- (DDExpression *)simplifiedExpressionWithEvaluator:(DDMathEvaluator *)evaluator error:(NSError **)error {
#pragma unused(evaluator, error)
	return self;
}

- (NSNumber *) evaluateWithSubstitutions:(NSDictionary *)substitutions evaluator:(DDMathEvaluator *)evaluator error:(NSError **)error {
	if (evaluator == nil) { evaluator = [DDMathEvaluator sharedMathEvaluator]; }
	
	id variableValue = [substitutions objectForKey:[self variable]];
    
    if (variableValue == nil) {
        variableValue = [evaluator variableWithName:[self variable]];
    }
    
	if ([variableValue isKindOfClass:[DDExpression class]]) {
		return [variableValue evaluateWithSubstitutions:substitutions evaluator:evaluator error:error];
	}
    if ([variableValue isKindOfClass:[NSString class]]) {
        return [evaluator evaluateString:variableValue withSubstitutions:substitutions error:error];
    }
	if ([variableValue isKindOfClass:[NSNumber class]]) {
		return variableValue;
	}
	if (error != nil) {
        *error = [NSError errorWithDomain:DDMathParserErrorDomain 
                                     code:DDErrorCodeUnresolvedVariable 
                                 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                           [NSString stringWithFormat:@"unable to resolve variable: %@", self], NSLocalizedDescriptionKey,
                                           [self variable], DDUnknownVariableKey,
                                           nil]];
	}
	return nil;
}

- (NSExpression *) expressionValueForEvaluator:(DDMathEvaluator *)evaluator {
#pragma unused(evaluator)
	return [NSExpression expressionForVariable:[self variable]];
}

- (NSString *) description {
	return [NSString stringWithFormat:@"$%@", [self variable]];
}

@end
