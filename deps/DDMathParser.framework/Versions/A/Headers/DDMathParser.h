//
//  DDMathParser.h
//  DDMathParser
//
//  Created by Mayur Pawashe on 5/14/15.
//  Copyright (c) 2015 zgcoder. All rights reserved.
//

#import <Cocoa/Cocoa.h>

//! Project version number for DDMathParser.
FOUNDATION_EXPORT double DDMathParserVersionNumber;

//! Project version string for DDMathParser.
FOUNDATION_EXPORT const unsigned char DDMathParserVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <DDMathParser/PublicHeader.h>

#define DDRuleTemplateAnyNumber @"__num"
#define DDRuleTemplateAnyFunction @"__func"
#define DDRuleTemplateAnyVariable @"__var"
#define DDRuleTemplateAnyExpression @"__exp"

#import <DDMathParser/DDMathEvaluator.h>
#import <DDMathParser/DDExpression.h>
#import <DDMathParser/DDParser.h>
#import <DDMathParser/DDTypes.h>
#import <DDMathParser/DDMathOperator.h>
#import <DDMathParser/DDExpressionRewriter.h>
#import <DDMathParser/NSString+DDMathParsing.h>
#import <DDMathParser/DDMathStringToken.h>
#import <DDMathParser/DDMathStringTokenizer.h>

