//
//  APTokenSearchField.h
//  TokenFieldTest
//
//  Created by Seth Willits on 12/4/13.
//  Copyright (c) 2013 Araelium Group. All rights reserved.
//

// Received permission from Seth to use this class

#import <Cocoa/Cocoa.h>

@interface APTokenSearchFieldCell : NSTokenFieldCell
@property (nonatomic, readwrite, retain) NSMenu * searchMenu;
@property (nonatomic, readwrite, assign) BOOL sendsSearchStringImmediately;
@property (nonatomic, readwrite, assign) BOOL sendsSearchStringOnlyAfterReturn; // Added by Mayur

@end


@interface APTokenSearchField : NSTokenField
- (APTokenSearchFieldCell *)cell;
@end



// Sample Delegate:
//
//	- (id)tokenField:(NSTokenField *)tokenField representedObjectForEditingString:(NSString *)editingString
//	{
//		return editingString;
//	}
//
//
//	- (NSString *)tokenField:(NSTokenField *)tokenField displayStringForRepresentedObject:(id)representedObject
//	{
//		assert([representedObject isKindOfClass:[NSString class]]);
//		NSString * string = representedObject;
//
//		if ([string hasPrefix:@"[#"] && [string hasSuffix:@"#]"] && string.length > 4) {
//			return [string substringWithRange:NSMakeRange(2, string.length - 4)];
//		}
//
//		return string;
//	}
//
//
//	- (NSTokenStyle)tokenField:(NSTokenField *)tokenField styleForRepresentedObject:(id)representedObject
//	{
//		assert([representedObject isKindOfClass:[NSString class]]);
//		NSString * string = representedObject;
//
//		if ([string hasPrefix:@"[#"] && [string hasSuffix:@"#]"] && string.length > 4) {
//			return NSRoundedTokenStyle;
//		}
//
//		return NSPlainTextTokenStyle;
//	}
//
//
//
//	- (NSString *)tokenField:(NSTokenField *)tokenField editingStringForRepresentedObject:(id)representedObject
//	{
//		assert([representedObject isKindOfClass:[NSString class]]);
//		NSString * string = representedObject;
//
//		if ([string hasPrefix:@"[#"] && [string hasSuffix:@"#]"] && string.length > 4) {
//			return nil;
//		}
//
//		return string;
//	}
//
