//
//  AGScopeBar.h
//  AGScopeBar
//
//  Created by Seth Willits on 6/25/12.
//  https://github.com/swillits/AGScopeBar
//
//  Licensed under the "zlib" license.
//
//  Copyright (c) 2012-2014, Seth Willits
//
//	This software is provided 'as-is', without any express or implied
//	warranty. In no event will the authors be held liable for any damages
//	arising from the use of this software.
//
//	Permission is granted to anyone to use this software for any purpose,
//	including commercial applications, and to alter it and redistribute it
//	freely, subject to the following restrictions:
//
//	1. The origin of this software must not be misrepresented; you must not
//	claim that you wrote the original software. If you use this software
//	in a product, an acknowledgment in the product documentation would be
//	appreciated but is not required.
//
//	2. Altered source versions must be plainly marked as such, and must not be
//	misrepresented as being the original software.
//
//	3. This notice may not be removed or altered from any source
//	distribution.
//

// Modified slightly; see .m file

#import <Cocoa/Cocoa.h>
@protocol AGScopeBarDelegate;
@class AGScopeBar;
@class AGScopeBarGroup;
@class AGScopeBarAppearance;


typedef enum {
	AGScopeBarGroupSelectNone, // Momentary buttons
	AGScopeBarGroupSelectOne,  // Radio buttons
	AGScopeBarGroupSelectAny,  // Checkbox (0 or more)
	AGScopeBarGroupSelectAtLeastOne
} AGScopeBarGroupSelectionMode;





@interface AGScopeBarItem : NSObject

@property (nonatomic, readonly) AGScopeBarGroup * group;
@property (nonatomic, readonly) NSString * identifier;
@property (nonatomic, readwrite, copy) NSString * title;
@property (nonatomic, readwrite, copy) NSImage * image;
@property (nonatomic, readwrite, retain) NSMenu * menu;
@property (nonatomic, readwrite, copy) NSString * toolTip;
@property (nonatomic, readonly) BOOL isSelected;
@property (nonatomic, readwrite, assign, getter=isEnabled) BOOL enabled;

+ (AGScopeBarItem *)itemWithIdentifier:(NSString *)identifier;
- (id)initWithIdentifier:(NSString *)identifier;

@end




@interface AGScopeBarGroup : NSObject <NSMenuDelegate>


@property (nonatomic, readonly) NSString * identifier;
@property (nonatomic, readwrite, retain) NSString * label;
@property (nonatomic, readwrite, assign) BOOL showsSeparator;
@property (nonatomic, readwrite, assign) BOOL canBeCollapsed;
@property (nonatomic, readwrite, assign) AGScopeBarGroupSelectionMode selectionMode;
@property (nonatomic, readwrite, assign, getter=isEnabled) BOOL enabled;
@property (nonatomic, readwrite, copy) NSArray * items;
@property (nonatomic, readonly) NSArray * selectedItems;
@property (nonatomic, readonly) NSArray * selectedItemIdentifiers;

+ (AGScopeBarGroup *)groupWithIdentifier:(NSString *)identifier;
- (id)initWithIdentifier:(NSString *)identifier;

- (AGScopeBarItem *)addItemWithIdentifier:(NSString *)identifier title:(NSString *)title;
- (AGScopeBarItem *)insertItemWithIdentifier:(NSString *)identifier title:(NSString *)title atIndex:(NSUInteger)index;

- (void)addItem:(AGScopeBarItem *)item;
- (void)insertItem:(AGScopeBarItem *)item atIndex:(NSUInteger)index;
- (void)removeItemAtIndex:(NSUInteger)index;

- (AGScopeBarItem *)itemAtIndex:(NSUInteger)index;
- (AGScopeBarItem *)itemWithIdentifier:(NSString *)identifier;

- (void)setSelected:(BOOL)selected forItem:(AGScopeBarItem *)item;
- (void)setSelected:(BOOL)selected forItemWithIdentifier:(NSString *)identifier;

@end




@interface AGScopeBar : NSView


@property (nonatomic, readwrite, assign) IBOutlet id<AGScopeBarDelegate> delegate;
@property (nonatomic, readwrite, assign) BOOL smartResizeEnabled;
@property (nonatomic, readwrite, retain) NSView * accessoryView;
@property (nonatomic, readwrite, copy) NSArray * groups;
@property (nonatomic, readwrite, assign, getter=isEnabled) BOOL enabled;
@property (nonatomic, readwrite, retain) AGScopeBarAppearance * scopeBarAppearance;

@property (nonatomic, readwrite, retain) NSColor * bottomBorderColor; //! Deprecated. Use scopeBarAppearance.borderColor
+ (CGFloat)scopeBarHeight;
- (void)smartResize;

- (AGScopeBarGroup *)addGroupWithIdentifier:(NSString *)identifier label:(NSString *)label items:(NSArray *)items;
- (AGScopeBarGroup *)insertGroupWithIdentifier:(NSString *)identifier label:(NSString *)label items:(NSArray *)items atIndex:(NSUInteger)index;

- (void)addGroup:(AGScopeBarGroup *)group;
- (void)insertGroup:(AGScopeBarGroup *)group atIndex:(NSUInteger)index;
- (void)removeGroupAtIndex:(NSUInteger)index;

- (AGScopeBarGroup *)groupContainingItem:(AGScopeBarItem *)item;
- (AGScopeBarGroup *)groupAtIndex:(NSUInteger)index;
- (AGScopeBarGroup *)groupWithIdentifier:(NSString *)identifier;

@end






@protocol AGScopeBarDelegate <NSObject>
@optional

- (void)scopeBar:(AGScopeBar *)theScopeBar item:(AGScopeBarItem *)item wasSelected:(BOOL)selected;

// If the following method is not implemented, all groups except the first will have a separator before them.
- (BOOL)scopeBar:(AGScopeBar *)theScopeBar showSeparatorBeforeGroup:(AGScopeBarGroup *)group;

@end





@interface AGScopeBarAppearance : NSObject

@property (nonatomic, readwrite, copy)   NSColor * backgroundTopColor;
@property (nonatomic, readwrite, copy)   NSColor * backgroundBottomColor;
@property (nonatomic, readwrite, copy)   NSColor * inactiveBackgroundTopColor;
@property (nonatomic, readwrite, copy)   NSColor * inactiveBackgroundBottomColor;
@property (nonatomic, readwrite, copy)   NSColor * borderBottomColor;
@property (nonatomic, readwrite, copy)   NSColor * separatorColor; // color of vertical-line separators between groups
@property (nonatomic, readwrite, assign) CGFloat separatorWidth;   // width of vertical-line separators between groups
@property (nonatomic, readwrite, assign) CGFloat separatorHeight;  // separators are vertically centered in the bar
@property (nonatomic, readwrite, copy)   NSColor * labelColor;     // color of groups' labels
@property (nonatomic, readwrite, copy)   NSFont * labelFont;       // font of groups' labels
@property (nonatomic, readwrite, copy)   NSFont * itemButtonFont;  // font of group and item buttons
@property (nonatomic, readwrite, copy)   NSFont * menuItemFont;
@end

