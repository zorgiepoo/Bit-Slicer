//
//  DDMathParser.h
//  DDMathParser
//
//  Created by Dave DeLong on 11/20/10.
//  Copyright 2010 Home. All rights reserved.
//

#import "DDMathEvaluator.h"
#import "DDExpression.h"
#import "DDParser.h"
#import "DDTypes.h"
#import "NSString+DDMathParsing.h"

#define DDRuleTemplateAnyNumber @"__num"
#define DDRuleTemplateAnyFunction @"__func"
#define DDRuleTemplateAnyVariable @"__var"
#define DDRuleTemplateAnyExpression @"__exp"

#ifdef __clang__
#define DD_STRONG strong
#else
#define DD_STRONG retain
#endif


#if __has_feature(objc_arc)

#define DD_HAS_ARC 1
#define DD_RETAIN(_o) (_o)
#define DD_RELEASE(_o) 
#define DD_AUTORELEASE(_o) (_o)

#else

#define DD_HAS_ARC 0
#define DD_RETAIN(_o) [(_o) retain]
#define DD_RELEASE(_o) [(_o) release]
#define DD_AUTORELEASE(_o) [(_o) autorelease]

#endif

// change this to 0 if you want the "%" character to mean a percentage
// please see the wiki for more information about what this switch means:
// https://github.com/davedelong/DDMathParser/wiki
#define DD_INTERPRET_PERCENT_SIGN_AS_MOD 1

