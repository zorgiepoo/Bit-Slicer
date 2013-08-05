//
//  __DDFunctionUtilities.m
//  DDMathParser
//
//  Created by Dave DeLong on 12/21/10.
//  Copyright 2010 Home. All rights reserved.
//

#import "DDMathParser.h"
#import "_DDFunctionUtilities.h"
#import "DDExpression.h"
#import "DDMathParserMacros.h"
#import "DDMathEvaluator.h"
#import "_DDOperatorInfo.h"

#define REQUIRE_N_ARGS(__n) { \
if ([arguments count] != (__n)) { \
	if (error != nil) { \
        *error = ERR(DDErrorCodeInvalidNumberOfArguments, @"%@ requires %d argument%@", NSStringFromSelector(_cmd), (__n), ((__n) == 1 ? @"" : @"s")); \
	} \
	return nil; \
} \
}

#define REQUIRE_GTOE_N_ARGS(__n) { \
if ([arguments count] < (__n)) { \
if (error != nil) { \
        *error = ERR(DDErrorCodeInvalidNumberOfArguments, @"%@ requires at least %d argument%@", NSStringFromSelector(_cmd), (__n), ((__n) == 1 ? @"" : @"s")); \
	} \
	return nil; \
} \
}

#define RETURN_IF_NIL(_n) if ((_n) == nil) { return nil; }



static inline DDExpression* _DDDTOR(DDExpression *e, DDMathEvaluator *evaluator, NSError **error) {
    DDExpression *final = e;
    if ([evaluator angleMeasurementMode] == DDAngleMeasurementModeDegrees) {
        if ([e expressionType] != DDExpressionTypeFunction || ![[e function] isEqualToString:@"dtor"]) {
            final = [DDExpression functionExpressionWithFunction:@"dtor"
                                                       arguments:[NSArray arrayWithObject:e]
                                                           error:error];
        }
    }
    return final;
}



static inline DDExpression* _DDRTOD(DDExpression *e, DDMathEvaluator *evaluator, NSError **error) {
    DDExpression *final = e;
    if ([evaluator angleMeasurementMode] == DDAngleMeasurementModeDegrees) {
        if ([e expressionType] != DDExpressionTypeFunction || ![[e function] isEqualToString:@"rtod"]) {
            final = [DDExpression functionExpressionWithFunction:@"rtod"
                                                       arguments:[NSArray arrayWithObject:e]
                                                           error:error];
        }
    }
    return final;
}

@implementation _DDFunctionUtilities

+ (DDMathFunction) addFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(2);
		NSNumber * firstValue = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(firstValue);
		
		NSNumber * secondValue = [[arguments objectAtIndex:1] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(secondValue);
		
        NSNumber *result = [NSNumber numberWithDouble:[firstValue doubleValue] + [secondValue doubleValue]];
        return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) subtractFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(2);
		NSNumber * firstValue = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(firstValue);
		NSNumber * secondValue = [[arguments objectAtIndex:1] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(secondValue);
		
        NSNumber *result = [NSNumber numberWithDouble:[firstValue doubleValue] - [secondValue doubleValue]];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) multiplyFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(2);
		NSNumber * firstValue = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(firstValue);
		NSNumber * secondValue = [[arguments objectAtIndex:1] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(secondValue);
		
        NSNumber *result = [NSNumber numberWithDouble:[firstValue doubleValue] * [secondValue doubleValue]];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) divideFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(2);
		NSNumber * firstValue = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(firstValue);
		NSNumber * secondValue = [[arguments objectAtIndex:1] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(secondValue);
		
        NSNumber *result = [NSNumber numberWithDouble:[firstValue doubleValue] / [secondValue doubleValue]];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) modFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(2);
		NSNumber * firstValue = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(firstValue);
		NSNumber * secondValue = [[arguments objectAtIndex:1] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(secondValue);
		
        NSNumber *result = [NSNumber numberWithDouble:fmod([firstValue doubleValue], [secondValue doubleValue])];
        return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) negateFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
		NSNumber * firstValue = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(firstValue);
		
        NSNumber *result = [NSNumber numberWithDouble:-1 * [firstValue doubleValue]];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) factorialFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
		NSNumber * firstValue = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(firstValue);
        
        NSNumber *result = [NSNumber numberWithDouble:tgamma([firstValue doubleValue]+1)];
        return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) powFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(2);
		NSNumber * base = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(base);
		NSNumber * exponent = [[arguments objectAtIndex:1] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(exponent);
        
        NSNumber *result = [NSNumber numberWithDouble:pow([base doubleValue], [exponent doubleValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) nthrootFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(2);
		NSNumber * base = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(base);
		NSNumber * root = [[arguments objectAtIndex:1] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(root);
        
        NSNumber *result = [NSNumber numberWithDouble:pow([base doubleValue], 1/[root doubleValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) andFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(2);
		NSNumber * first = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(first);
		NSNumber * second = [[arguments objectAtIndex:1] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(second);
        
		NSNumber * result = [NSNumber numberWithInteger:([first integerValue] & [second integerValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) orFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(2);
		NSNumber * first = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(first);
		NSNumber * second = [[arguments objectAtIndex:1] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(second);
        
		NSNumber * result = [NSNumber numberWithInteger:([first integerValue] | [second integerValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) notFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
		NSNumber * first = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(first);
        
		NSNumber * result = [NSNumber numberWithInteger:(~[first integerValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);	
}

+ (DDMathFunction) xorFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(2);
		NSNumber * first = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(first);
		NSNumber * second = [[arguments objectAtIndex:1] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(second);
        
		NSNumber * result = [NSNumber numberWithInteger:([first integerValue] ^ [second integerValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);	
}

+ (DDMathFunction) rshiftFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(2);
		NSNumber * first = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(first);
		NSNumber * second = [[arguments objectAtIndex:1] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(second);
        
		NSNumber * result = [NSNumber numberWithInteger:[first integerValue] >> [second integerValue]];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) lshiftFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(2);
		NSNumber * first = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(first);
		NSNumber * second = [[arguments objectAtIndex:1] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(second);
        
		NSNumber * result = [NSNumber numberWithInteger:[first integerValue] << [second integerValue]];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) averageFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_GTOE_N_ARGS(2);
		DDMathFunction sumFunction = [_DDFunctionUtilities sumFunction];
		DDExpression * sumExpression = sumFunction(arguments, variables, evaluator, error);
		RETURN_IF_NIL(sumExpression);
        
        double sum = [[sumExpression number] doubleValue];
        NSNumber *avg = [NSNumber numberWithDouble:sum / [arguments count]];
		return [DDExpression numberExpressionWithNumber:avg];
	};
	return DD_AUTORELEASE([function copy]);	
}

+ (DDMathFunction) sumFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_GTOE_N_ARGS(1);
		NSMutableArray * evaluatedNumbers = [NSMutableArray array];
		for (DDExpression * e in arguments) {
            NSNumber *n = [e evaluateWithSubstitutions:variables evaluator:evaluator error:error];
            RETURN_IF_NIL(n);
			[evaluatedNumbers addObject:n];
		}
        
        double sum = 0;
        for (NSNumber *value in evaluatedNumbers) {
            sum += [value doubleValue];
        }
        NSNumber *result = [NSNumber numberWithDouble:sum];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) countFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
#pragma unused(variables, evaluator)
		REQUIRE_GTOE_N_ARGS(1);
		return [DDExpression numberExpressionWithNumber:[NSDecimalNumber decimalNumberWithMantissa:[arguments count] exponent:0 isNegative:NO]];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) minFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_GTOE_N_ARGS(2);
        NSNumber *result = nil;
		for (NSUInteger index = 0; index < [arguments count]; ++index) {
			DDExpression *obj = [arguments objectAtIndex:index];
			NSNumber *value = [obj evaluateWithSubstitutions:variables evaluator:evaluator error:error];
			RETURN_IF_NIL(value);
            if (index == 0 || [result compare:value] == NSOrderedDescending) {
				//result > value (or is first index)
				//value is smaller
				result = value;
			}
		}
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) maxFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_GTOE_N_ARGS(2);
        NSNumber *result = nil;
		for (NSUInteger index = 0; index < [arguments count]; ++index) {
			DDExpression *obj = [arguments objectAtIndex:index];
			NSNumber *value = [obj evaluateWithSubstitutions:variables evaluator:evaluator error:error];
			RETURN_IF_NIL(value);
            if (index == 0 || [result compare:value] == NSOrderedAscending) {
				//result < value (or is first index)
				//value is larger
				result = value;
			}
		}
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) medianFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_GTOE_N_ARGS(2);
		NSMutableArray * evaluatedNumbers = [NSMutableArray array];
		for (DDExpression * e in arguments) {
            NSNumber *n = [e evaluateWithSubstitutions:variables evaluator:evaluator error:error];
            RETURN_IF_NIL(n);
			[evaluatedNumbers addObject:n];
		}
		[evaluatedNumbers sortUsingSelector:@selector(compare:)];
		
		NSNumber * median = nil;
		if (([evaluatedNumbers count] % 2) == 1) {
			NSUInteger index = floor([evaluatedNumbers count] / 2);
			median = [evaluatedNumbers objectAtIndex:index];
		} else {
			NSUInteger lowIndex = floor([evaluatedNumbers count] / 2);
			NSUInteger highIndex = ceil([evaluatedNumbers count] / 2);
            NSNumber *low = [evaluatedNumbers objectAtIndex:lowIndex];
            NSNumber *high = [evaluatedNumbers objectAtIndex:highIndex];
            median = [NSNumber numberWithDouble:([low doubleValue] + [high doubleValue])/2];
		}
		return [DDExpression numberExpressionWithNumber:median];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) stddevFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_GTOE_N_ARGS(2);
		DDMathFunction avgFunction = [_DDFunctionUtilities averageFunction];
		DDExpression * avgExpression = avgFunction(arguments, variables, evaluator, error);
		RETURN_IF_NIL(avgExpression);
        
        double avg = [[avgExpression number] doubleValue];
        double stddev = 0;
        for (DDExpression *arg in arguments) {
            NSNumber *argValue = [arg evaluateWithSubstitutions:variables evaluator:evaluator error:error];
            RETURN_IF_NIL(argValue);
            double diff = avg - [argValue doubleValue];
            diff = diff * diff;
            stddev += diff;
        }
        stddev /= [arguments count];
        stddev = sqrt(stddev);
        NSNumber *result = [NSNumber numberWithDouble:stddev];
		
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) sqrtFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
		NSNumber * n = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:sqrt([n doubleValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) randomFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		if ([arguments count] > 2) {
			if (error != nil) {
                *error = ERR(DDErrorCodeInvalidNumberOfArguments, @"random() may only have up to 2 arguments");
			}
			return nil;
		}
		
		NSMutableArray * params = [NSMutableArray array];
		for (DDExpression * argument in arguments) {
			NSNumber * value = [argument evaluateWithSubstitutions:variables evaluator:evaluator error:error];
			RETURN_IF_NIL(value);
			[params addObject:value];
		}
		
		NSInteger random = arc4random();
		
		if ([params count] == 1) {
			NSNumber * lowerBound = [params objectAtIndex:0];
			while (random < [lowerBound integerValue]) {
				random += [lowerBound integerValue];
			}
		} else if ([params count] == 2) {
			NSNumber * lowerBound = [params objectAtIndex:0];
			NSNumber * upperBound = [params objectAtIndex:1];
			
			if ([upperBound integerValue] <= [lowerBound integerValue]) {
				if (error != nil) {
                    *error = ERR(DDErrorCodeInvalidArgument, @"upper bound (%ld) of random() must be larger than lower bound (%ld)", [upperBound integerValue], [lowerBound integerValue]);
				}
				return nil;
			}
			
			long long range = llabs(([upperBound longLongValue] - [lowerBound longLongValue]) + 1);
			random = random % range;
			random += [lowerBound longLongValue];
		}
		
		return [DDExpression numberExpressionWithNumber:[NSNumber numberWithLongLong:random]];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) logFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
		NSNumber * n = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:log10([n doubleValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) lnFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
		NSNumber * n = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(n);
		return [DDExpression numberExpressionWithNumber:[NSNumber numberWithDouble:log([n doubleValue])]];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) log2Function {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
		NSNumber * n = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:log2([n doubleValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) expFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
		NSNumber * n = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:exp([n doubleValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) ceilFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        NSNumber *n = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);

        NSNumber *result = [NSNumber numberWithDouble:ceil([n doubleValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) absFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        NSNumber *n = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithLongLong:llabs([n longLongValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) floorFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        NSNumber *n = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:floor([n doubleValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) percentFunction {
    DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
        REQUIRE_N_ARGS(1);
        
        DDExpression *percentArgument = [arguments objectAtIndex:0];
        DDExpression *percentExpression = [percentArgument parentExpression];
        DDExpression *percentContext = [percentExpression parentExpression];
        
        NSString *parentFunction = [percentContext function];
        _DDOperatorInfo *operatorInfo = [[_DDOperatorInfo infosForOperatorFunction:parentFunction] lastObject];
        
        NSNumber *context = [NSNumber numberWithInt:1];
        
        if ([operatorInfo arity] == DDOperatorArityBinary) {
            if ([parentFunction isEqualToString:DDOperatorAdd] || [parentFunction isEqualToString:DDOperatorMinus]) {
                BOOL percentIsRightArgument = ([[percentContext arguments] objectAtIndex:1] == percentExpression);
                if (percentIsRightArgument) {
                    DDExpression *baseExpression = [[percentContext arguments] objectAtIndex:0];
                    context = [baseExpression evaluateWithSubstitutions:variables evaluator:evaluator error:error];
                }
            }
        }
        
        NSNumber *percent = [percentArgument evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        
        RETURN_IF_NIL(context);
        RETURN_IF_NIL(percent);
        
        NSNumber *result = [NSNumber numberWithDouble:[context doubleValue] * ([percent doubleValue] / 100.0)];
        return [DDExpression numberExpressionWithNumber:result];
    };
    return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) sinFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        DDExpression *argument = [arguments objectAtIndex:0];
        argument = _DDDTOR(argument, evaluator, error);
        NSNumber *n = [argument evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:sin([n doubleValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) cosFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        DDExpression *argument = [arguments objectAtIndex:0];
        argument = _DDDTOR(argument, evaluator, error);
        NSNumber *n = [argument evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:cos([n doubleValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) tanFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        DDExpression *argument = [arguments objectAtIndex:0];
        argument = _DDDTOR(argument, evaluator, error);
        NSNumber *n = [argument evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:tan([n doubleValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) asinFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        NSNumber *n = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:asin([n doubleValue])];
		return _DDRTOD([DDExpression numberExpressionWithNumber:result], evaluator, error);
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) acosFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        NSNumber *n = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:acos([n doubleValue])];
		return _DDRTOD([DDExpression numberExpressionWithNumber:result], evaluator, error);
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) atanFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        NSNumber *n = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:atan([n doubleValue])];
		return _DDRTOD([DDExpression numberExpressionWithNumber:result], evaluator, error);
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) sinhFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        DDExpression *argument = [arguments objectAtIndex:0];
        argument = _DDDTOR(argument, evaluator, error);
        NSNumber *n = [argument evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:sinh([n doubleValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) coshFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        DDExpression *argument = [arguments objectAtIndex:0];
        argument = _DDDTOR(argument, evaluator, error);
        NSNumber *n = [argument evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:cosh([n doubleValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) tanhFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        DDExpression *argument = [arguments objectAtIndex:0];
        argument = _DDDTOR(argument, evaluator, error);
        NSNumber *n = [argument evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:tanh([n doubleValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) asinhFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        NSNumber *n = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:asinh([n doubleValue])];
		return _DDRTOD([DDExpression numberExpressionWithNumber:result], evaluator, error);
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) acoshFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        NSNumber *n = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:acosh([n doubleValue])];
		return _DDRTOD([DDExpression numberExpressionWithNumber:result], evaluator, error);
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) atanhFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        NSNumber *n = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:atanh([n doubleValue])];
		return _DDRTOD([DDExpression numberExpressionWithNumber:result], evaluator, error);
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) cscFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        DDExpression *argument = [arguments objectAtIndex:0];
        argument = _DDDTOR(argument, evaluator, error);
        NSNumber *n = [argument evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:1/sin([n doubleValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) secFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        DDExpression *argument = [arguments objectAtIndex:0];
        argument = _DDDTOR(argument, evaluator, error);
        NSNumber *n = [argument evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:1/cos([n doubleValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) cotanFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        DDExpression *argument = [arguments objectAtIndex:0];
        argument = _DDDTOR(argument, evaluator, error);
        NSNumber *n = [argument evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:1/tan([n doubleValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) acscFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        NSNumber *n = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:1/asin([n doubleValue])];
		return _DDRTOD([DDExpression numberExpressionWithNumber:result], evaluator, error);
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) asecFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        NSNumber *n = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:1/acos([n doubleValue])];
		return _DDRTOD([DDExpression numberExpressionWithNumber:result], evaluator, error);
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) acotanFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        NSNumber *n = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:1/atan([n doubleValue])];
		return _DDRTOD([DDExpression numberExpressionWithNumber:result], evaluator, error);
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) cschFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        DDExpression *argument = [arguments objectAtIndex:0];
        argument = _DDDTOR(argument, evaluator, error);
        NSNumber *n = [argument evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:1/sinh([n doubleValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) sechFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        DDExpression *argument = [arguments objectAtIndex:0];
        argument = _DDDTOR(argument, evaluator, error);
        NSNumber *n = [argument evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:1/cosh([n doubleValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) cotanhFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        DDExpression *argument = [arguments objectAtIndex:0];
        argument = _DDDTOR(argument, evaluator, error);
        NSNumber *n = [argument evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:1/tanh([n doubleValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) acschFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        NSNumber *n = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:1/sinh([n doubleValue])];
		return _DDRTOD([DDExpression numberExpressionWithNumber:result], evaluator, error);
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) asechFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        NSNumber *n = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:1/cosh([n doubleValue])];
		return _DDRTOD([DDExpression numberExpressionWithNumber:result], evaluator, error);
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) acotanhFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        NSNumber *n = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:1/atanh([n doubleValue])];
		return _DDRTOD([DDExpression numberExpressionWithNumber:result], evaluator, error);
	};
	return DD_AUTORELEASE([function copy]);
}

// more trig functions
+ (DDMathFunction) versinFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        DDExpression *argument = [arguments objectAtIndex:0];
        argument = _DDDTOR(argument, evaluator, error);
        NSNumber *n = [argument evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:1-cos([n doubleValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) vercosinFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        DDExpression *argument = [arguments objectAtIndex:0];
        argument = _DDDTOR(argument, evaluator, error);
        NSNumber *n = [argument evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:1+cos([n doubleValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) coversinFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        DDExpression *argument = [arguments objectAtIndex:0];
        argument = _DDDTOR(argument, evaluator, error);
        NSNumber *n = [argument evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:1-sin([n doubleValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) covercosinFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        DDExpression *argument = [arguments objectAtIndex:0];
        argument = _DDDTOR(argument, evaluator, error);
        NSNumber *n = [argument evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:1+sin([n doubleValue])];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) haversinFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        DDExpression *argument = [arguments objectAtIndex:0];
        argument = _DDDTOR(argument, evaluator, error);
        NSNumber *n = [argument evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:(1-cos([n doubleValue]))/2];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) havercosinFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        DDExpression *argument = [arguments objectAtIndex:0];
        argument = _DDDTOR(argument, evaluator, error);
        NSNumber *n = [argument evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:(1+cos([n doubleValue]))/2];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) hacoversinFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        DDExpression *argument = [arguments objectAtIndex:0];
        argument = _DDDTOR(argument, evaluator, error);
        NSNumber *n = [argument evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:(1-sin([n doubleValue]))/2];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) hacovercosinFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        DDExpression *argument = [arguments objectAtIndex:0];
        argument = _DDDTOR(argument, evaluator, error);
        NSNumber *n = [argument evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:(1+sin([n doubleValue]))/2];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) exsecFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        DDExpression *argument = [arguments objectAtIndex:0];
        argument = _DDDTOR(argument, evaluator, error);
        NSNumber *n = [argument evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:(1/cos([n doubleValue]))-1];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) excscFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        DDExpression *argument = [arguments objectAtIndex:0];
        argument = _DDDTOR(argument, evaluator, error);
        NSNumber *n = [argument evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:(1/sin([n doubleValue]))-1];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) crdFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        DDExpression *argument = [arguments objectAtIndex:0];
        argument = _DDDTOR(argument, evaluator, error);
        NSNumber *n = [argument evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:2*sin([n doubleValue]/2)];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) dtorFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        NSNumber *n = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:[n doubleValue]/180 * M_PI];
		return [DDExpression numberExpressionWithNumber:result];
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) rtodFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
		REQUIRE_N_ARGS(1);
        NSNumber *n = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        
        NSNumber *result = [NSNumber numberWithDouble:[n doubleValue]/M_PI * 180];
		return [DDExpression numberExpressionWithNumber:result];
		
	};
	return DD_AUTORELEASE([function copy]);
}

#pragma mark Constant Functions

+ (DDMathFunction) phiFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
#pragma unused(variables, evaluator)
		REQUIRE_N_ARGS(0);
		return [DDExpression numberExpressionWithNumber:[NSNumber numberWithDouble:1.6180339887498948]];
		
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) piFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
#pragma unused(variables, evaluator)
		REQUIRE_N_ARGS(0);
        return [DDExpression numberExpressionWithNumber:[NSNumber numberWithDouble:M_PI]];
		
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) pi_2Function {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
#pragma unused(variables, evaluator)
		REQUIRE_N_ARGS(0);
		return [DDExpression numberExpressionWithNumber:[NSNumber numberWithDouble:M_PI_2]];
		
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) pi_4Function {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
#pragma unused(variables, evaluator)
		REQUIRE_N_ARGS(0);
		return [DDExpression numberExpressionWithNumber:[NSNumber numberWithDouble:M_PI_4]];
		
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) tauFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
#pragma unused(variables, evaluator)
		REQUIRE_N_ARGS(0);
		return [DDExpression numberExpressionWithNumber:[NSNumber numberWithDouble:2*M_PI]];
		
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) sqrt2Function {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
#pragma unused(variables, evaluator)
		REQUIRE_N_ARGS(0);
		return [DDExpression numberExpressionWithNumber:[NSNumber numberWithDouble:M_SQRT2]];
		
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) eFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
#pragma unused(variables, evaluator)
		REQUIRE_N_ARGS(0);
        return [DDExpression numberExpressionWithNumber:[NSNumber numberWithDouble:M_E]];
		
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) log2eFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
#pragma unused(variables, evaluator)
		REQUIRE_N_ARGS(0);
		return [DDExpression numberExpressionWithNumber:[NSNumber numberWithDouble:M_LOG2E]];
		
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) log10eFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
#pragma unused(variables, evaluator)
		REQUIRE_N_ARGS(0);
		return [DDExpression numberExpressionWithNumber:[NSNumber numberWithDouble:M_LOG10E]];
		
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) ln2Function {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
#pragma unused(variables, evaluator)
		REQUIRE_N_ARGS(0);
		return [DDExpression numberExpressionWithNumber:[NSNumber numberWithDouble:M_LN2]];
		
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) ln10Function {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
#pragma unused(variables, evaluator)
		REQUIRE_N_ARGS(0);
		return [DDExpression numberExpressionWithNumber:[NSNumber numberWithDouble:M_LN10]];
		
	};
	return DD_AUTORELEASE([function copy]);
}

// logical functions

+ (DDMathFunction) l_andFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
#pragma unused(variables, evaluator)
		REQUIRE_N_ARGS(2);
		NSNumber *left = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		NSNumber *right = [[arguments objectAtIndex:1] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(left);
        RETURN_IF_NIL(right);
        NSNumber *result = [NSNumber numberWithBool:[left boolValue] && [right boolValue]];
		return [DDExpression numberExpressionWithNumber:result];
		
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) l_orFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
#pragma unused(variables, evaluator)
		REQUIRE_N_ARGS(2);
		NSNumber *left = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		NSNumber *right = [[arguments objectAtIndex:1] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(left);
        RETURN_IF_NIL(right);
        NSNumber *result = [NSNumber numberWithBool:[left boolValue] ||
                            [right boolValue]];
		return [DDExpression numberExpressionWithNumber:result];
		
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) l_notFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
#pragma unused(variables, evaluator)
		REQUIRE_N_ARGS(1);
		NSNumber *n = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(n);
        NSNumber *result = [NSNumber numberWithBool:![n boolValue]];
		return [DDExpression numberExpressionWithNumber:result];
		
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) l_eqFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
#pragma unused(variables, evaluator)
		REQUIRE_N_ARGS(2);
		NSNumber *left = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		NSNumber *right = [[arguments objectAtIndex:1] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(left);
        RETURN_IF_NIL(right);
        NSComparisonResult compare = [left compare:right];
        NSNumber *result = [NSNumber numberWithBool:compare == NSOrderedSame];
		return [DDExpression numberExpressionWithNumber:result];
		
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) l_neqFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
#pragma unused(variables, evaluator)
		REQUIRE_N_ARGS(2);
		NSNumber *left = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		NSNumber *right = [[arguments objectAtIndex:1] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(left);
        RETURN_IF_NIL(right);
        NSComparisonResult compare = [left compare:right];
        NSNumber *result = [NSNumber numberWithBool:compare != NSOrderedSame];
		return [DDExpression numberExpressionWithNumber:result];
		
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) l_ltFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
#pragma unused(variables, evaluator)
		REQUIRE_N_ARGS(2);
		NSNumber *left = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		NSNumber *right = [[arguments objectAtIndex:1] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(left);
        RETURN_IF_NIL(right);
        NSComparisonResult compare = [left compare:right];
        NSNumber *result = [NSNumber numberWithBool:compare == NSOrderedAscending];
		return [DDExpression numberExpressionWithNumber:result];
		
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) l_gtFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
#pragma unused(variables, evaluator)
		REQUIRE_N_ARGS(2);
		NSNumber *left = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		NSNumber *right = [[arguments objectAtIndex:1] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(left);
        RETURN_IF_NIL(right);
        NSComparisonResult compare = [left compare:right];
        NSNumber *result = [NSNumber numberWithBool:compare == NSOrderedDescending];
		return [DDExpression numberExpressionWithNumber:result];
		
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) l_ltoeFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
#pragma unused(variables, evaluator)
		REQUIRE_N_ARGS(2);
		NSNumber *left = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		NSNumber *right = [[arguments objectAtIndex:1] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(left);
        RETURN_IF_NIL(right);
        NSComparisonResult compare = [left compare:right];
        NSNumber *result = [NSNumber numberWithBool:compare == NSOrderedSame || compare == NSOrderedAscending];
		return [DDExpression numberExpressionWithNumber:result];
		
	};
	return DD_AUTORELEASE([function copy]);
}

+ (DDMathFunction) l_gtoeFunction {
	DDMathFunction function = ^ DDExpression* (NSArray *arguments, NSDictionary *variables, DDMathEvaluator *evaluator, NSError **error) {
#pragma unused(variables, evaluator)
		REQUIRE_N_ARGS(2);
		NSNumber *left = [[arguments objectAtIndex:0] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
		NSNumber *right = [[arguments objectAtIndex:1] evaluateWithSubstitutions:variables evaluator:evaluator error:error];
        RETURN_IF_NIL(left);
        RETURN_IF_NIL(right);
        NSComparisonResult compare = [left compare:right];
        NSNumber *result = [NSNumber numberWithBool:compare == NSOrderedSame || compare == NSOrderedDescending];
		return [DDExpression numberExpressionWithNumber:result];
		
	};
	return DD_AUTORELEASE([function copy]);
}

@end
