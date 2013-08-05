//
//  _DDVariableExpression.h
//  DDMathParser
//
//  Created by Dave DeLong on 11/18/10.
//  Copyright 2010 Home. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DDExpression.h"

@interface _DDVariableExpression : DDExpression {
	
	NSString * variable;
}

- (id) initWithVariable:(NSString *)v;

@end
