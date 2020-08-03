//
//  NSString+DDMathParsing.h
//  DDMathParser
//
//  Created by Dave DeLong on 11/21/10.
//  Copyright 2010 Home. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface NSString (DDMathParsing)

- (NSNumber *)ddNumberByEvaluatingString;
- (NSNumber *)ddNumberByEvaluatingStringWithSubstitutions:(NSDictionary *)substitutions;
- (NSNumber *)ddNumberByEvaluatingStringWithSubstitutions:(NSDictionary *)substitutions error:(NSError **)error;

@end
