//
//  DDMathEvaluator.m
//  DDMathParser
//
//  Created by Dave DeLong on 11/17/10.
//  Copyright 2010 Home. All rights reserved.
//
#import "DDMathParser.h"
#import "DDMathEvaluator.h"
#import "DDMathEvaluator+Private.h"
#import "DDParser.h"
#import "DDMathParserMacros.h"
#import "DDExpression.h"
#import "_DDFunctionUtilities.h"
#import "_DDFunctionContainer.h"
#import "_DDRewriteRule.h"
#import <objc/runtime.h>

@interface DDMathEvaluator ()

+ (NSSet *) _standardFunctions;
+ (NSDictionary *) _standardAliases;
+ (NSSet *)_standardNames;
- (void) _registerStandardFunctions;
- (void)_registerStandardRewriteRules;
- (_DDFunctionContainer *)functionContainerWithName:(NSString *)functionName;

@end


@implementation DDMathEvaluator

@synthesize angleMeasurementMode=angleMeasurementMode;
@synthesize functionResolver=functionResolver;
@synthesize variableResolver=variableResolver;

static DDMathEvaluator * _sharedEvaluator = nil;

+ (id) sharedMathEvaluator {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
		_sharedEvaluator = [[DDMathEvaluator alloc] init];
    });
	return _sharedEvaluator;
}

- (id) init {
	self = [super init];
	if (self) {
		functions = [[NSMutableArray alloc] init];
        functionMap = [[NSMutableDictionary alloc] init];
        angleMeasurementMode = DDAngleMeasurementModeRadians;
        
		[self _registerStandardFunctions];
	}
	return self;
}

- (void) dealloc {
	if (self == _sharedEvaluator) {
		_sharedEvaluator = nil;
	}
#if !DD_HAS_ARC
	[functions release];
    [functionMap release];
    [rewriteRules release];
    [functionResolver release];
    [variableResolver release];
	[super dealloc];
#endif
}

#pragma mark - Functions

- (BOOL) registerFunction:(DDMathFunction)function forName:(NSString *)functionName {
    NSString *name = [_DDFunctionContainer normalizedAlias:functionName];
    
	if ([self functionWithName:functionName] != nil) { return NO; }
	if ([[[self class] _standardNames] containsObject:name]) { return NO; }
    
    _DDFunctionContainer *container = [[_DDFunctionContainer alloc] initWithFunction:function name:name];
    [functions addObject:container];
    [functionMap setObject:container forKey:name];
    DD_RELEASE(container);
	
	return YES;
}

- (void) unregisterFunctionWithName:(NSString *)functionName {
    NSString *name = [_DDFunctionContainer normalizedAlias:functionName];
	//can't unregister built-in functions
	if ([[[self class] _standardNames] containsObject:name]) { return; }
	
    _DDFunctionContainer *container = [self functionContainerWithName:functionName];
    for (NSString *alias in [container aliases]) {
        [functionMap removeObjectForKey:name];
    }
    [functions removeObject:container];
}

- (_DDFunctionContainer *)functionContainerWithName:(NSString *)functionName {
    NSString *name = [_DDFunctionContainer normalizedAlias:functionName];
    _DDFunctionContainer *container = [functionMap objectForKey:name];
    return container;
}

- (DDMathFunction) functionWithName:(NSString *)functionName {
    _DDFunctionContainer *container = [self functionContainerWithName:functionName];
    DDMathFunction function = [container function];
    if (function == nil && functionResolver != nil) {
        function = functionResolver(functionName);
    }
    return function;
}

- (NSArray *) registeredFunctions {
	return [functionMap allKeys];
}

- (BOOL) functionExpressionFailedToResolve:(_DDFunctionExpression *)functionExpression error:(NSError **)error {
    NSString *functionName = [functionExpression function];
	if (error) {
        *error = [NSError errorWithDomain:DDMathParserErrorDomain 
                                     code:DDErrorCodeUnresolvedFunction 
                                 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                           [NSString stringWithFormat:@"unable to resolve function: %@", functionName], NSLocalizedDescriptionKey,
                                           functionName, DDUnknownFunctionKey,
                                           nil]];
	}
	return NO;
}

- (id) variableWithName:(NSString *)variableName {
    id value = nil;
    if (variableResolver != nil) {
        value = variableResolver(variableName);
    }
    return value;
}

- (BOOL) addAlias:(NSString *)alias forFunctionName:(NSString *)functionName {
	//we can't add an alias for a function that already exists
	DDMathFunction function = [self functionWithName:alias];
	if (function != nil) { return NO; }
    
    _DDFunctionContainer *container = [self functionContainerWithName:functionName];
    alias = [_DDFunctionContainer normalizedAlias:alias];
    [container addAlias:alias];
    [functionMap setObject:container forKey:alias];
    
    return YES;
}

- (void) removeAlias:(NSString *)alias {
    alias = [_DDFunctionContainer normalizedAlias:alias];
	//you can't unregister a standard alias (like "avg")
	if ([[[self class] _standardNames] containsObject:alias]) { return; }
    [self unregisterFunctionWithName:alias];
}

- (void)addRewriteRule:(NSString *)rule forExpressionsMatchingTemplate:(NSString *)template condition:(NSString *)condition {
    [self _registerStandardRewriteRules];
    _DDRewriteRule *rewriteRule = [_DDRewriteRule rewriteRuleWithTemplate:template replacementPattern:rule condition:condition];
    [rewriteRules addObject:rewriteRule];
}

#pragma mark Evaluation

- (NSNumber *) evaluateString:(NSString *)expressionString withSubstitutions:(NSDictionary *)substitutions {
	NSError *error = nil;
	NSNumber *returnValue = [self evaluateString:expressionString withSubstitutions:substitutions error:&error];
	if (!returnValue) {
		NSLog(@"error: %@", error);
	}
	return returnValue;
}

- (NSNumber *) evaluateString:(NSString *)expressionString withSubstitutions:(NSDictionary *)substitutions error:(NSError **)error {
	DDParser * parser = [DDParser parserWithString:expressionString error:error];
	if (!parser) {
		return nil;
	}
	DDExpression * parsedExpression = [parser parsedExpressionWithError:error];
	if (!parsedExpression) {
		return nil;
	}
	return [parsedExpression evaluateWithSubstitutions:substitutions evaluator:self error:error];
}

#pragma mark Built-In Functions

+ (NSSet *) _standardFunctions {
    static dispatch_once_t onceToken;
    static NSSet *standardFunctions = nil;
    dispatch_once(&onceToken, ^{
        NSMutableSet *names = [NSMutableSet set];
        
        Class utilitiesMetaClass = objc_getMetaClass("_DDFunctionUtilities");
        unsigned int count = 0;
        Method *methods = class_copyMethodList(utilitiesMetaClass, &count);
        for (unsigned int i = 0; i < count; ++i) {
            NSString *methodName = NSStringFromSelector(method_getName(methods[i]));
            if ([methodName hasSuffix:@"Function"]) {
                NSString *functionName = [methodName substringToIndex:[methodName length] - 8]; // 8 == [@"Function" length]
                [names addObject:functionName];
            }
        }
        
        free(methods);
        standardFunctions = [names copy];
    });
	return standardFunctions;
}

+ (NSDictionary *) _standardAliases {
    static dispatch_once_t onceToken;
    static NSDictionary *standardAliases = nil;
    dispatch_once(&onceToken, ^{
        standardAliases = [[NSDictionary alloc] initWithObjectsAndKeys:
                           @"average", @"avg",
                           @"average", @"mean",
                           @"floor", @"trunc",
                           @"mod", @"modulo",
                           @"pi", @"\u03C0", // π
                           @"pi", @"tau_2",
                           @"tau", @"\u03C4", // τ
                           @"phi", @"\u03D5", // ϕ
                           
                           @"versin", @"vers",
                           @"versin", @"ver",
                           @"vercosin", @"vercos",
                           @"coversin", @"cvs",
                           @"crd", @"chord",
                           
                           nil];
    });
    return standardAliases;
}

+ (NSSet *)_standardNames {
    static dispatch_once_t onceToken;
    static NSSet *names = nil;
    dispatch_once(&onceToken, ^{
        NSSet *functions = [self _standardFunctions];
        NSDictionary *aliases = [self _standardAliases];
        NSMutableSet *both = [NSMutableSet setWithSet:functions];
        [both addObjectsFromArray:[aliases allKeys]];
        names = [both copy];
    });
    return names;
}

+ (NSDictionary *)_standardRewriteRules {
    static dispatch_once_t onceToken;
    static NSDictionary *rules = nil;
    dispatch_once(&onceToken, ^{
        rules = [[NSDictionary alloc] initWithObjectsAndKeys:
                 //addition
                 @"__exp1", @"0+__exp1",
                 @"__exp1", @"__exp1+0",
                 @"2*__exp1", @"__exp1 + __exp1",
                 
                 //subtraction
                 @"0", @"__exp1 - __exp1",
                 
                 //multiplication
                 @"__exp1", @"1 * __exp1",
                 @"__exp1", @"__exp1 * 1",
                 @"pow(__exp1, 2)", @"__exp1 * __exp1",
                 @"multiply(__var1, __num1)", @"multiply(__num1, __var1)",
                 @"0", @"0 * __exp1",
                 @"0", @"__exp1 * 0",
                 
                 //other stuff
                 @"__exp1", @"--__exp1",
                 @"abs(__exp1)", @"abs(-__exp1)",
                 @"exp(__exp1 + __exp2)", @"exp(__exp1) * exp(__exp2)",
                 @"pow(__exp1 * __exp2, __exp3)", @"pow(__exp1, __exp3) * pow(__exp2, __exp3)",
                 @"1", @"pow(__exp1, 0)",
                 @"__exp1", @"pow(__exp1, 1)",
                 @"abs(__exp1)", @"sqrt(pow(__exp1, 2))",
                 
                 //
                 @"__exp1", @"dtor(rtod(__exp1))",
                 nil];
    });
    return rules;
}

- (void) _registerStandardFunctions {
	for (NSString *functionName in [[self class] _standardFunctions]) {
		
		NSString *methodName = [NSString stringWithFormat:@"%@Function", functionName];
		SEL methodSelector = NSSelectorFromString(methodName);
		if ([_DDFunctionUtilities respondsToSelector:methodSelector]) {
			DDMathFunction function = [_DDFunctionUtilities performSelector:methodSelector];
			if (function != nil) {
                _DDFunctionContainer *container = [[_DDFunctionContainer alloc] initWithFunction:function name:functionName];
                [functions addObject:container];
                [functionMap setObject:container forKey:functionName];
                DD_RELEASE(container);
			} else {
                // this would only happen when a function name has been misspelled = programmer error = raise an exception
                [NSException raise:NSInvalidArgumentException format:@"error registering function: %@", functionName];
			}
		}
	}
	
	NSDictionary *aliases = [[self class] _standardAliases];
	for (NSString *alias in aliases) {
		NSString *function = [aliases objectForKey:alias];
		(void)[self addAlias:alias forFunctionName:function];
	}
}

- (void)_registerStandardRewriteRules {
    if (rewriteRules != nil) { return; }
    
    rewriteRules = [[NSMutableArray alloc] init];
    
    NSDictionary *templates = [[self class] _standardRewriteRules];
    for (NSString *template in templates) {
        NSString *replacement = [templates objectForKey:template];
        
        [self addRewriteRule:replacement forExpressionsMatchingTemplate:template condition:nil];
    }
    
    //division
    [self addRewriteRule:@"1" forExpressionsMatchingTemplate:@"__exp1 / __exp1" condition:@"__exp1 != 0"];
    [self addRewriteRule:@"__exp1" forExpressionsMatchingTemplate:@"(__exp1 * __exp2) / __exp2" condition:@"__exp2 != 0"];
    [self addRewriteRule:@"__exp1" forExpressionsMatchingTemplate:@"(__exp2 * __exp1) / __exp2" condition:@"__exp2 != 0"];
    [self addRewriteRule:@"1/__exp1" forExpressionsMatchingTemplate:@"__exp2 / (__exp2 * __exp1)" condition:@"__exp2 != 0"];
    [self addRewriteRule:@"1/__exp1" forExpressionsMatchingTemplate:@"__exp2 / (__exp1 * __exp2)" condition:@"__exp2 != 0"];
    
    //exponents and roots
    [self addRewriteRule:@"abs(__exp1)" forExpressionsMatchingTemplate:@"nthroot(pow(__exp1, __exp2), __exp2)" condition:@"__exp2 % 2 == 0"];
    [self addRewriteRule:@"__exp1" forExpressionsMatchingTemplate:@"nthroot(pow(__exp1, __exp2), __exp2)" condition:@"__exp2 % 2 == 1"];
    [self addRewriteRule:@"__exp1" forExpressionsMatchingTemplate:@"abs(__exp1)" condition:@"__exp1 >= 0"];
}

- (DDExpression *)_rewriteExpression:(DDExpression *)expression usingRule:(_DDRewriteRule *)rule {
    DDExpression *rewritten = [rule expressionByRewritingExpression:expression withEvaluator:self];
    
    // if the rule did not match, return the expression
    if (rewritten == expression && [expression expressionType] == DDExpressionTypeFunction) {
        NSMutableArray *newArguments = [NSMutableArray array];
        BOOL argsChanged = NO;
        for (DDExpression *arg in [expression arguments]) {
            DDExpression *newArg = [self _rewriteExpression:arg usingRule:rule];
            argsChanged |= (newArg != arg);
            [newArguments addObject:newArg];
        }
        
        if (argsChanged) {
            rewritten = [_DDFunctionExpression functionExpressionWithFunction:[expression function] arguments:newArguments error:nil];
        }
    }
    
    return rewritten;
}

- (DDExpression *)expressionByRewritingExpression:(DDExpression *)expression {
    [self _registerStandardRewriteRules];
    DDExpression *tmp = expression;
    NSUInteger iterationCount = 0;
    
    do {
        expression = tmp;
        BOOL changed = NO;
        
        for (_DDRewriteRule *rule in rewriteRules) {
            DDExpression *rewritten = [self _rewriteExpression:tmp usingRule:rule];
            if (rewritten != tmp) {
                tmp = rewritten;
                changed = YES;
            }
        }
        
        // we applied all the rules and nothing changed
        if (!changed) { break; }
        iterationCount++;
    } while (tmp != nil && iterationCount < 256);
    
    if (iterationCount >= 256) {
        NSLog(@"ABORT: replacement limit reached");
    }
    
    return expression;
}

@end
