//
//  AGScopeBar.m
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

#import "AGScopeBar.h"




#define SCOPE_BAR_HORZ_INSET			8.0																		// inset on left and right
#define SCOPE_BAR_HEIGHT				25.0																	// used in -sizeToFit
#define SCOPE_BAR_START_COLOR_GRAY		[NSColor colorWithCalibratedWhite:0.75 alpha:1.0]						// bottom color of gray gradient
#define SCOPE_BAR_END_COLOR_GRAY		[NSColor colorWithCalibratedWhite:0.90 alpha:1.0]						// top color of gray gradient
#define SCOPE_BAR_BORDER_COLOR			[NSColor colorWithCalibratedWhite:0.5 alpha:1.0]						// bottom line's color

#define SCOPE_BAR_SEPARATOR_COLOR		[NSColor colorWithCalibratedWhite:0.52 alpha:1.0]	// color of vertical-line separators between groups
#define SCOPE_BAR_SEPARATOR_WIDTH		1.0													// width of vertical-line separators between groups
#define SCOPE_BAR_SEPARATOR_HEIGHT		16.0												// separators are vertically centered in the bar

#define SCOPE_BAR_LABEL_COLOR			[NSColor colorWithCalibratedWhite:0.45 alpha:1.0]	// color of groups' labels
#define SCOPE_BAR_FONTSIZE				12.0												// font-size of labels and buttons

#define SCOPE_BAR_FONT                  [NSFont boldSystemFontOfSize:SCOPE_BAR_FONTSIZE]
#define SCOPE_BAR_MENUITEM_FONT			[NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSRegularControlSize]]

#define SCOPE_BAR_GROUP_SPACING			8.0													// spacing between buttons/separators/labels
#define SCOPE_BAR_ITEM_SPACING			2.0													// spacing between buttons/separators/labels
#define SCOPE_BAR_BUTTON_IMAGE_SIZE		16.0												// size of buttons' images (width and height)

#define POPUP_MIN_WIDTH					40.0					// minimum width a popup-button can be narrowed to.
#define POPUP_MAX_WIDTH                 200.0
#define POPUP_RESIZES_TO_FIT_TITLE      1

#define POPUP_TITLE_EMPTY_SELECTION		NSLocalizedString(@"(None)", nil)		// title used when no items in the popup are selected.
#define POPUP_TITLE_MULTIPLE_SELECTION	NSLocalizedString(@"(Multiple)", nil)	// title used when multiple items in the popup are selected.





#pragma mark  
@interface AGScopeBarPopupButtonCell : NSPopUpButtonCell {
	NSButton * mRecessedButton;
	NSPopUpButtonCell * mPopupCell;
}
@end


@interface AGScopeBarItem ()
@property (nonatomic, readwrite, assign) AGScopeBarGroup * group;
@property (nonatomic, readonly) NSButton * button;
@property (nonatomic, readonly) NSMenuItem * menuItem;

- (void)_setSelected:(BOOL)isSelected;
- (void)_recreateButton;
- (void)_updateButton;
- (void)_updateEnabling;
@end


@interface AGScopeBarGroup ()
@property (nonatomic, readwrite, assign) AGScopeBar * scopeBar;
@property (nonatomic, readwrite, assign) BOOL isCollapsed;
@property (nonatomic, readonly) NSView * view;
@property (nonatomic, readonly) NSView * collapsedView;
- (void)tile;
- (void)validateSelectedItems;
- (void)_informDelegate_item:(AGScopeBarItem *)item wasSelected:(BOOL)selected;
- (void)_updateEnabling;
@end


@interface AGScopeBar ()
- (void)setNeedsTiling;
- (void)tile;
@end






#pragma mark  
#pragma mark ========================================
@implementation AGScopeBar


- (id)initWithFrame:(NSRect)frameRect
{
	if (!(self = [super initWithFrame:frameRect])) {
		return nil;
	}
	
	mBottomBorderColor = [SCOPE_BAR_BORDER_COLOR retain];
	mSmartResizeEnabled = YES;
	mGroups = [[NSArray array] retain];
	mIsEnabled = YES;
	
	return self;
}



- (void)dealloc
{
	for (AGScopeBarGroup * group in mGroups) {
		group.scopeBar = nil;
	}
	
	[mAccessoryView release];
	[mGroups release];
	[mBottomBorderColor release];
	[super dealloc];
}




#pragma mark -
#pragma mark Properties

@synthesize delegate = mDelegate;


- (void)setEnabled:(BOOL)enabled;
{
	if (enabled != mIsEnabled) {
		mIsEnabled = enabled;
		
		for (AGScopeBarGroup * group in self.groups) {
			[group _updateEnabling];
		}
	}
}


- (BOOL)isEnabled;
{
	return mIsEnabled;
}



- (void)setSmartResizeEnabled:(BOOL)smartResizeEnabled
{
	if (mSmartResizeEnabled != smartResizeEnabled) {
		mSmartResizeEnabled = smartResizeEnabled;
		[self tile];
	}
}


- (BOOL)smartResizeEnabled
{
	return mSmartResizeEnabled;
}


- (void)setAccessoryView:(NSView *)accessoryView;
{
	if (mAccessoryView != accessoryView) {
		[mAccessoryView removeFromSuperview];
		[mAccessoryView autorelease];
		
		mAccessoryView = [accessoryView retain];
		[self tile];
	}
}


- (NSView *)accessoryView;
{
	return mAccessoryView;
}



- (void)setGroups:(NSArray *)groups;
{
	for (AGScopeBarGroup * group in mGroups) {
		group.scopeBar = nil;
	}
	
	[mGroups autorelease];
	mGroups = [groups copy];
	
	for (AGScopeBarGroup * group in mGroups) {
		group.scopeBar = self;
	}
	
	[self setNeedsTiling];
}


- (NSArray *)groups;
{
	return mGroups;
}


- (void)setBottomBorderColor:(NSColor *)bottomBorderColor;
{
	[mBottomBorderColor autorelease];
	mBottomBorderColor = [bottomBorderColor retain];
}


- (NSColor *)bottomBorderColor;
{
	return mBottomBorderColor;
}


+ (CGFloat)scopeBarHeight;
{
	return SCOPE_BAR_HEIGHT;
}





#pragma mark -
#pragma mark Sizing

- (void)smartResize;
{
	[self tile];
	[self setNeedsDisplay:YES];
}


- (void)resizeSubviewsWithOldSize:(NSSize)oldBoundsSize
{
	[super resizeSubviewsWithOldSize:oldBoundsSize];
	[self smartResize];
}


- (void)setNeedsTiling;
{
	mNeedsTiling = YES;
	[self setNeedsDisplay:YES];
}





#pragma mark -
#pragma mark Groups

- (AGScopeBarGroup *)addGroupWithIdentifier:(NSString *)identifier label:(NSString *)label items:(NSArray *)items;
{
	AGScopeBarGroup * group = [AGScopeBarGroup groupWithIdentifier:identifier];
	group.label = label;
	group.items = items;
	[self addGroup:group];
	return group;
}


- (AGScopeBarGroup *)insertGroupWithIdentifier:(NSString *)identifier label:(NSString *)label items:(NSArray *)items atIndex:(NSUInteger)index;
{
	AGScopeBarGroup * group = [AGScopeBarGroup groupWithIdentifier:identifier];
	group.label = label;
	group.items = items;
	[self insertGroup:group atIndex:index];
	return group;
}



- (void)addGroup:(AGScopeBarGroup *)group;
{
	self.groups = [self.groups arrayByAddingObject:group];
}


- (void)insertGroup:(AGScopeBarGroup *)group atIndex:(NSUInteger)index;
{
	NSMutableArray * groups = [[self.groups mutableCopy] autorelease];
	[groups insertObject:group atIndex:index];
	self.groups = groups;
}


- (void)removeGroupAtIndex:(NSUInteger)index;
{
	NSMutableArray * groups = [[self.groups mutableCopy] autorelease];
	[groups removeObjectAtIndex:index];
	self.groups = groups;
}



- (AGScopeBarGroup *)groupContainingItem:(AGScopeBarItem *)item;
{
	for (AGScopeBarGroup * group in mGroups) {
		if ([group.items containsObject:item]) return group;
	}
	
	return nil;
}


- (AGScopeBarGroup *)groupAtIndex:(NSUInteger)index;
{
	return [self.groups objectAtIndex:index];
}


- (AGScopeBarGroup *)groupWithIdentifier:(NSString *)identifier;
{
	for (AGScopeBarGroup * group in mGroups) {
		if ([group.identifier isEqual:identifier]) return group;
	}
	
	return nil;
}





#pragma mark -
#pragma mark Drawing

- (void)viewWillDraw;
{
	if (mNeedsTiling) {
		[self tile];
	}
}



- (void)drawRect:(NSRect)dirtyRect;
{
	// Draw gradient background
	NSGradient * gradient = [[[NSGradient alloc] initWithStartingColor:SCOPE_BAR_START_COLOR_GRAY 
														   endingColor:SCOPE_BAR_END_COLOR_GRAY] autorelease];
	[gradient drawInRect:self.bounds angle:90.0];
	
	// Draw border
	if (self.bottomBorderColor) {
		NSRect lineRect = NSMakeRect(0, 0, self.bounds.size.width, 1);
		[self.bottomBorderColor set];
		NSRectFill(lineRect);
	}
	
	// Draw separators
	[self.groups enumerateObjectsUsingBlock:^(AGScopeBarGroup * group, NSUInteger groupIndex, BOOL *stop) {
		if ((groupIndex > 0) && (group.showsSeparator)) {
			NSRect sepRect = NSMakeRect(0, 0, SCOPE_BAR_SEPARATOR_WIDTH, SCOPE_BAR_SEPARATOR_HEIGHT);
			sepRect.origin.y = ((self.bounds.size.height - sepRect.size.height) / 2.0);
			sepRect.origin.x = NSMinX(group.view.frame) - SCOPE_BAR_GROUP_SPACING;
			
			[SCOPE_BAR_SEPARATOR_COLOR set];
			NSRectFill(sepRect);
		}
	}];
}





#pragma mark -
#pragma mark Private

- (void)scopeButtonClicked:(id)sender
{
	BOOL senderIsMenuItem = [sender isKindOfClass:[NSMenuItem class]];
	AGScopeBarItem * item = (senderIsMenuItem ? [sender representedObject] : [[sender cell] representedObject]);
	AGScopeBarGroup * group = [self groupContainingItem:item];
	
	[group setSelected:!item.isSelected forItem:item];
}



- (void)tile;
{
	__block CGFloat maxNeededSpaceForGroups = 0.0;
	CGFloat availableSpace = 0.0;
	
	availableSpace = self.bounds.size.width;
	availableSpace -= SCOPE_BAR_HORZ_INSET;
	availableSpace -= (self.accessoryView ? (SCOPE_BAR_HORZ_INSET + self.accessoryView.frame.size.width) : 0.0);
	
	
	
	// Remove all group views (clears out any old ones too)
	for (NSView * view in [[self.subviews copy] autorelease]) {
		[view removeFromSuperview];
	}
	
	
	// Layout items in group views
	for (AGScopeBarGroup * group in self.groups) {
		[group tile];
	}
	
	
	// Get maxNeededSpaceForGroups
	[self.groups enumerateObjectsUsingBlock:^(AGScopeBarGroup * group, NSUInteger groupIndex, BOOL *stop){
		if (groupIndex > 0) {
			if (group.showsSeparator) maxNeededSpaceForGroups += SCOPE_BAR_SEPARATOR_WIDTH;
			maxNeededSpaceForGroups += SCOPE_BAR_GROUP_SPACING;
		}
		
		maxNeededSpaceForGroups += group.view.bounds.size.width;
	}];
	
	
	
	// Do not collapse any groups
	if (!self.smartResizeEnabled || (maxNeededSpaceForGroups < availableSpace)) {
		for (AGScopeBarGroup * group in self.groups) {
			group.isCollapsed = NO;
		}
	
	// Collapse as many groups as we need to
	} else {
		
		__block BOOL hasCollapsedAllGroups = NO;
		__block BOOL notEnoughSpace = YES;
		
		for (AGScopeBarGroup * group in self.groups) {
			group.isCollapsed = NO;
		}
		
		while (!hasCollapsedAllGroups && notEnoughSpace) {
			__block CGFloat neededSpace = 0.0;
			
			hasCollapsedAllGroups = YES;
			
			// Collapse a group
			[self.groups enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(AGScopeBarGroup * group, NSUInteger groupIndex, BOOL *stop){
				if (group.canBeCollapsed && !group.isCollapsed) {
					hasCollapsedAllGroups = NO;
					group.isCollapsed = YES;
					*stop = YES;
				}
			}];
			
			// Calculate needed space for groups
			[self.groups enumerateObjectsUsingBlock:^(AGScopeBarGroup * group, NSUInteger groupIndex, BOOL *stop){
				if (groupIndex > 0) {
					if (group.showsSeparator) maxNeededSpaceForGroups += SCOPE_BAR_SEPARATOR_WIDTH;
					neededSpace += SCOPE_BAR_GROUP_SPACING;
				}
				
				if (group.isCollapsed) {
					neededSpace += group.collapsedView.bounds.size.width;
				} else {
					neededSpace += group.view.bounds.size.width;
				}
			}];
			
			notEnoughSpace = (neededSpace > availableSpace);
		}
	}
	
	
	
	// Arrange group views
	{
		NSUInteger groupIndex = 0;
		CGFloat xOffset = 0.0;
		
		xOffset += SCOPE_BAR_HORZ_INSET;
		
		for (AGScopeBarGroup * group in self.groups) {
			if (groupIndex > 0) {
				if (group.showsSeparator) xOffset += SCOPE_BAR_SEPARATOR_WIDTH;
				xOffset += SCOPE_BAR_GROUP_SPACING;
			}
			
			NSView * view = (group.isCollapsed ? group.collapsedView : group.view);
			NSRect groupFrame = view.frame;
			groupFrame.origin.x = xOffset;
			groupFrame.origin.y = 0.0;
			view.frame = groupFrame;
			[self addSubview:view];
			
			xOffset += view.frame.size.width;
			groupIndex++;
		}
	}
	
	
	if (self.accessoryView) {
		NSRect frame = self.accessoryView.frame;
		frame.origin.x = round(NSMaxX(self.bounds) - (frame.size.width + SCOPE_BAR_HORZ_INSET));
		frame.origin.y = round(((SCOPE_BAR_HEIGHT - frame.size.height) / 2.0));
		self.accessoryView.frame = frame;
		self.accessoryView.autoresizingMask = NSViewMinXMargin;
		[self addSubview:self.accessoryView];
	}
	
	mNeedsTiling = NO;
}

@end









#pragma mark  
#pragma mark ========================================
@implementation AGScopeBarGroup


+ (AGScopeBarGroup *)groupWithIdentifier:(NSString *)identifier;
{
	return [[[[self class] alloc] initWithIdentifier:identifier] autorelease];
}


- (id)initWithIdentifier:(NSString *)identifier;
{
	if (!(self = [super init])) {
		return nil;
	}
	
	mIdentifier = [identifier retain];
	mItems = [[NSArray alloc] init];
	mSelectedItems = [[NSArray alloc] init];
	mShowsSeparator = YES;
	mCanBeCollapsed = YES;
	mIsEnabled = YES;
	
	mView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 0, [AGScopeBar scopeBarHeight])];
	
	mLabelField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 0, 0)];
	mLabelField.editable = NO;
	mLabelField.bordered = NO;
	mLabelField.drawsBackground = NO;
	mLabelField.textColor = SCOPE_BAR_LABEL_COLOR;
	mLabelField.font = SCOPE_BAR_FONT;
	
	mCollapsedView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 0, [AGScopeBar scopeBarHeight])];
	mCollapsedLabelField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 0, 0)];
	mCollapsedLabelField.editable = NO;
	mCollapsedLabelField.bordered = NO;
	mCollapsedLabelField.drawsBackground = NO;
	mCollapsedLabelField.textColor = SCOPE_BAR_LABEL_COLOR;
	mCollapsedLabelField.font = SCOPE_BAR_FONT;
	
	mGroupPopupButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
	mGroupPopupButton.cell = [[[AGScopeBarPopupButtonCell alloc] initTextCell:@"" pullsDown:NO] autorelease];
	mGroupPopupButton.menu.autoenablesItems = NO;
	mGroupPopupButton.menu.delegate = self;
	
	[mCollapsedView addSubview:mCollapsedLabelField];
	[mCollapsedView addSubview:mGroupPopupButton];
	
	return self;
}


- (id)init;
{
	[self doesNotRecognizeSelector:_cmd];
	return nil;
}


- (void)dealloc;
{
	for (AGScopeBarItem * item in mItems) {
		item.group = nil;
	}
	
	[mIdentifier release];
	[mLabel release];
	[mItems release];
	[mSelectedItems release];
	
	[mView release];
	[mLabelField release];
	[mCollapsedView release];
	[mGroupPopupButton release];
	[mCollapsedLabelField release];
	[super dealloc];
}





#pragma mark -
#pragma mark Properties

@synthesize identifier = mIdentifier;
@synthesize showsSeparator = mShowsSeparator;
@synthesize canBeCollapsed = mCanBeCollapsed;


- (void)setLabel:(NSString *)label;
{
	[mLabel autorelease];
	mLabel = [label retain];
	
	[self.scopeBar setNeedsTiling];
}


- (NSString *)label;
{
	return mLabel;
}



- (void)setSelectionMode:(AGScopeBarGroupSelectionMode)selectionMode;
{
	mSelectionMode = selectionMode;
	[self validateSelectedItems];
}


- (AGScopeBarGroupSelectionMode)selectionMode;
{
	return mSelectionMode;
}


- (BOOL)requiresSelection;
{
	switch (self.selectionMode) {
		case AGScopeBarGroupSelectOne:
		case AGScopeBarGroupSelectAtLeastOne:
			return YES;
			
		case AGScopeBarGroupSelectNone:
		case AGScopeBarGroupSelectAny:
			return NO;
	}
}


- (BOOL)allowsMultipleSelection;
{
	switch (self.selectionMode) {
		case AGScopeBarGroupSelectAny:
		case AGScopeBarGroupSelectAtLeastOne:
			return YES;
			
		case AGScopeBarGroupSelectNone:
		case AGScopeBarGroupSelectOne:
			return NO;
	}
}



- (void)setEnabled:(BOOL)enabled;
{
	if (enabled != mIsEnabled) {
		mIsEnabled = enabled;
		
		[self _updateEnabling];
	}
}


- (BOOL)isEnabled;
{
	return mIsEnabled;
}







#pragma mark -
#pragma mark Items

- (void)setItems:(NSArray *)items;
{
	for (AGScopeBarItem * item in mItems) {
		item.group = nil;
	}
	
	[mItems autorelease];
	mItems = [items copy];
	if (!mItems) mItems = [[NSArray alloc] init];
	
	for (AGScopeBarItem * item in mItems) {
		item.group = self;
	}
	
	[self validateSelectedItems];
	[self.scopeBar setNeedsTiling];
}



- (NSArray *)items;
{
	return mItems;
}



- (NSArray *)selectedItems;
{
	return [[mSelectedItems retain] autorelease];
}


- (NSArray *)selectedItemIdentifiers;
{
	return [mSelectedItems valueForKeyPath:@"@unionOfObjects.identifier"];
}



#pragma mark -

- (AGScopeBarItem *)addItemWithIdentifier:(NSString *)identifier title:(NSString *)title;
{
	AGScopeBarItem * item = [AGScopeBarItem itemWithIdentifier:identifier];
	item.title = title;
	[self addItem:item];
	return item;
}


- (AGScopeBarItem *)insertItemWithIdentifier:(NSString *)identifier title:(NSString *)title atIndex:(NSUInteger)index;
{
	AGScopeBarItem * item = [AGScopeBarItem itemWithIdentifier:identifier];
	item.title = title;
	[self insertItem:item atIndex:index];
	return item;
}



- (void)addItem:(AGScopeBarItem *)item;
{
	self.items = [self.items arrayByAddingObject:item];
}


- (void)insertItem:(AGScopeBarItem *)item atIndex:(NSUInteger)index;
{
	NSMutableArray * items = [[self.items mutableCopy] autorelease];
	[items insertObject:item atIndex:index];
	self.items = items;
}


- (void)removeItemAtIndex:(NSUInteger)index;
{
	NSMutableArray * items = [[self.items mutableCopy] autorelease];
	[items removeObjectAtIndex:index];
	self.items = items;
}



- (AGScopeBarItem *)itemAtIndex:(NSUInteger)index;
{
	return [self.items objectAtIndex:index];
}


- (AGScopeBarItem *)itemWithIdentifier:(NSString *)identifier;
{
	for (AGScopeBarItem * item in self.items) {
		if ([item.identifier isEqual:identifier]) return item;
	}
	
	return nil;
}



#pragma mark -
#pragma mark Group Menu Delegate

- (void)menuWillOpen:(NSMenu *)menu;
{
	if (menu == mGroupPopupButton.menu) {
		[mGroupPopupButton removeAllItems];
		
		for (AGScopeBarItem * item in self.items) {
			[mGroupPopupButton.menu addItem:item.menuItem];
			item.menuItem.enabled = item.isEnabled;
		}
		
		[self _updatePopup];
	}
}


- (void)menuDidClose:(NSMenu *)menu;
{
	if (menu == mGroupPopupButton.menu) {
		
		// Hmm. Was doing this for some reason that I unfortunately cannot recall.
		// The issue in doing it though is that the clicked-on menu item's action
		// will not be sent to the target if it's removed from the menu! I thought
		// it use to work though. This may be a recent change in 10.9?
		//[mGroupPopupButton removeAllItems];
	}
}


#pragma mark -
#pragma mark Private

@synthesize scopeBar = mScopeBar;
@synthesize isCollapsed = mIsCollapsed;
@synthesize view = mView;
@synthesize collapsedView = mCollapsedView;


- (void)tile;
{
	// Full View
	// -----------------------------------------
	{
		for (NSView * view in [[self.view.subviews copy] autorelease]) {
			[view removeFromSuperview];
		}
		
		
		NSRect viewFrame = NSZeroRect;
		CGFloat xOffset = 0.0;
		
		viewFrame.size.height = self.scopeBar.frame.size.height;
		
		
		// Label
		if (self.label) {
			mLabelField.stringValue = self.label;
			mLabelField.hidden = NO;
			[mLabelField sizeToFit];
			[mView addSubview:mLabelField];
			
			NSRect frame = mLabelField.frame;
			frame.origin.x = 0;
			frame.origin.y = 6;//floor((self.scopeBar.frame.size.height - frame.size.height) / 2.0);
			mLabelField.frame = frame;
			
			xOffset += mLabelField.frame.size.width;
			xOffset += SCOPE_BAR_ITEM_SPACING * 2.0;
		} else {
			mLabelField.stringValue = @"";
			mLabelField.hidden = YES;
		}
		
		
		// Items
		for (AGScopeBarItem * item in self.items) {
			[item _updateEnabling];
			[mView addSubview:item.button];
			
			NSRect itemFrame = item.button.frame;
			itemFrame.origin.x = xOffset;
			itemFrame.origin.y = floor((self.scopeBar.frame.size.height - itemFrame.size.height) / 2.0);
			item.button.frame = itemFrame;
			
			xOffset += item.button.frame.size.width + SCOPE_BAR_ITEM_SPACING;
		}
		
		viewFrame.size.width = xOffset;
		mView.frame = viewFrame;
	}
	
	
	// Collapsed View
	// -----------------------------------------
	{
		NSRect viewFrame = NSZeroRect;
		CGFloat xOffset = 0.0;
		
		viewFrame.size.height = self.scopeBar.frame.size.height;
		
		
		if (self.label) {
			mCollapsedLabelField.stringValue = self.label;
			mCollapsedLabelField.hidden = NO;
			[mCollapsedLabelField sizeToFit];
			
			NSRect frame = mCollapsedLabelField.frame;
			frame.origin.x = 0;
			frame.origin.y = 6;//floor((self.scopeBar.frame.size.height - frame.size.height) / 2.0);
			mCollapsedLabelField.frame = frame;
			
			xOffset += mLabelField.frame.size.width;
			xOffset += SCOPE_BAR_ITEM_SPACING * 2.0;
		} else {
			mCollapsedLabelField.stringValue = @"";
			mCollapsedLabelField.hidden = YES;
		}
		
		
		// Popup
		{
			[mGroupPopupButton removeAllItems];
			
			//for (AGScopeBarItem * item in self.items) {
			//	[mGroupPopupButton.menu addItem:item.menuItem];
			//}
			
			
			if (YES) { //self.allowsMultipleSelection) {
				NSPopUpButtonCell * cell = [mGroupPopupButton cell];
				cell.usesItemFromMenu = NO;
				cell.menuItem = [[[NSMenuItem alloc] init] autorelease];
				[self _updatePopup];
			}
			
			
			[mGroupPopupButton.menu setFont:SCOPE_BAR_MENUITEM_FONT];
			[mGroupPopupButton setFont:SCOPE_BAR_FONT];
			[mGroupPopupButton setBezelStyle:NSRecessedBezelStyle];
			[mGroupPopupButton setButtonType:NSPushOnPushOffButton];
			[mGroupPopupButton.cell setHighlightsBy:NSCellIsBordered | NSCellIsInsetButton];
			[mGroupPopupButton setShowsBorderOnlyWhileMouseInside:YES];
			[mGroupPopupButton.cell setAltersStateOfSelectedItem:NO];
			[mGroupPopupButton.cell setArrowPosition:NSPopUpArrowAtBottom];
			[mGroupPopupButton.cell setBackgroundStyle:NSBackgroundStyleRaised];
			
			[mGroupPopupButton sizeToFit];
			NSRect popFrame = mGroupPopupButton.frame;
			popFrame.origin.x = xOffset;
			popFrame.origin.y = ceil((mCollapsedView.frame.size.height - popFrame.size.height) / 2.0);
			popFrame.size.width = [self _widthForPopup:mGroupPopupButton];
			mGroupPopupButton.frame = popFrame;
			xOffset += mGroupPopupButton.frame.size.width;
		}
		
		viewFrame.size.width = xOffset;
		mCollapsedView.frame = viewFrame;
	}
}



- (CGFloat)_widthForPopup:(NSPopUpButton *)popup
{
	CGFloat width = 0.0;
	
	#if POPUP_RESIZES_TO_FIT_TITLE
		[popup sizeToFit];
		width = popup.frame.size.width;
		
	#else
		NSPopUpButtonCell * inCell = [[[popup cell] retain] autorelease];
		NSPopUpButtonCell * cell = [[[NSPopUpButtonCell alloc] initTextCell:inCell.title pullsDown:inCell.pullsDown] autorelease];
		
		popup.cell = cell;
		[cell setBezelStyle:NSRecessedBezelStyle];
		[cell setFont:SCOPE_BAR_FONT];
		[cell setBackgroundStyle:NSBackgroundStyleRaised];
		[cell setMenu:inCell.menu];
		
		[popup sizeToFit];
		width = popup.frame.size.width;
		
		popup.cell = inCell;
		[popup.cell setUsesItemFromMenu:NO];
		[popup.cell setMenuItem:[[[NSMenuItem alloc] init] autorelease]];
		[self _updatePopup];
	#endif
	
	
	return MIN(MAX(POPUP_MIN_WIDTH, width), POPUP_MAX_WIDTH);
}



- (void)_updatePopup;
{
	NSPopUpButtonCell * cell = [mGroupPopupButton cell];
	NSArray * selectedItems = self.selectedItems;
	
	if (selectedItems.count == 0) {
		[mGroupPopupButton setTitle:POPUP_TITLE_EMPTY_SELECTION];
		[cell.menuItem setTitle:POPUP_TITLE_EMPTY_SELECTION];
	} else if (selectedItems.count == 1) {
		NSString * title = [(AGScopeBarItem *)[selectedItems lastObject] title];
		if (!title) title = @"";
		[mGroupPopupButton setTitle:title];
		[cell.menuItem setTitle:title];
	} else if (selectedItems.count > 1) {
		[mGroupPopupButton setTitle:POPUP_TITLE_MULTIPLE_SELECTION];
		[cell.menuItem setTitle:POPUP_TITLE_MULTIPLE_SELECTION];
	}
	
	for (AGScopeBarItem * item in self.items) {
		item.menuItem.state = (item.isSelected ? NSOnState : NSOffState);
	}
	
	
	mGroupPopupButton.enabled = (self.scopeBar.isEnabled && self.isEnabled);
}



- (void)_updateEnabling;
{
	mGroupPopupButton.enabled = (self.scopeBar.isEnabled && self.isEnabled);
	
	for (AGScopeBarItem * item in self.items) {
		[item _updateEnabling];
	}
}



- (void)setSelected:(BOOL)willBeSelected forItemWithIdentifier:(NSString *)identifier;
{
	[self setSelected:willBeSelected forItem:[self itemWithIdentifier:identifier]];
}



- (void)setSelected:(BOOL)willBeSelected forItem:(AGScopeBarItem *)item;
{
	if (item.isSelected == willBeSelected) return;
	
	
	// Special case for momentary buttons
	// ------------------------------------------
	if (self.selectionMode == AGScopeBarGroupSelectNone) {
		[item _setSelected:NO]; // Deselect its button
		[self _updatePopup];
		[self _informDelegate_item:item wasSelected:willBeSelected];
		return;
	}
	
	
	// Validate the selected items list
	// ------------------------------------------
	NSArray * oldSelectedItems = [self selectedItems];
	NSArray * newSelectedItems = nil;
	
	
	if (willBeSelected) {
		if (self.allowsMultipleSelection) {
			newSelectedItems = [oldSelectedItems arrayByAddingObject:item];
		} else {
			newSelectedItems = [NSArray arrayWithObject:item];
		}
	} else {
		
		NSMutableArray * items = [[oldSelectedItems mutableCopy] autorelease];
		[items removeObject:item];
		newSelectedItems = [[items copy] autorelease];
		
		if (self.requiresSelection) {
			if (newSelectedItems.count == 0) {
				[item _setSelected:YES]; // Reselect its button
				[self _updatePopup];
				return; // Can't deselect
			}
		}
	}
	
	
	// Save and send selection notifications
	// ------------------------------------------
	[self _setSelectedItems:newSelectedItems];
}



- (void)validateSelectedItems;
{
	NSArray * selectedItems = self.selectedItems;
	
	
	if (self.requiresSelection) {
		if (selectedItems.count == 0) {
			if (self.items.count > 0) {
				selectedItems = [NSArray arrayWithObject:[self.items objectAtIndex:0]];
			}
		}
	}
	
	if (!self.allowsMultipleSelection) {
		if (selectedItems.count > 1) {
			selectedItems = [NSArray arrayWithObject:[selectedItems lastObject]];
		}
	}
	
	
	[self _setSelectedItems:selectedItems];
}



- (void)_setSelectedItems:(NSArray *)newSelectedItems;
{
	NSArray * oldSelectedItems = mSelectedItems;
	
	[mSelectedItems autorelease];
	mSelectedItems = [newSelectedItems copy];
	
	for (AGScopeBarItem * item in self.items) {
		if ([oldSelectedItems containsObject:item] && ![newSelectedItems containsObject:item]) {
			[item _setSelected:NO];
			
			// If item is part of a AGScopeBarGroupSelectOne group, then don't inform
			// the delegate of an item being deselected because they'll be informed
			// about the new item being selected.
			// Preeeeeetty sure this would be the desired behavior.
			if (item.group.selectionMode != AGScopeBarGroupSelectOne) {
				[self _informDelegate_item:item wasSelected:NO];
			}
			
		} else if (![oldSelectedItems containsObject:item] && [newSelectedItems containsObject:item]) {
			[item _setSelected:YES];
			[self _informDelegate_item:item wasSelected:YES];
		}
	}
	
	
	[self _updatePopup];
	
	
	// Show the border only on hover when no item are selected
	// but always show it if one or more items is selected.
	if (newSelectedItems.count == 0) {
		[mGroupPopupButton setShowsBorderOnlyWhileMouseInside:YES];
		[mGroupPopupButton setBordered:YES];
	} else {
		[mGroupPopupButton setShowsBorderOnlyWhileMouseInside:NO];
		[mGroupPopupButton setBordered:YES];
	}
}



- (void)_informDelegate_item:(AGScopeBarItem *)item wasSelected:(BOOL)selected;
{
	if ([self.scopeBar.delegate respondsToSelector:@selector(scopeBar:item:wasSelected:)]) {
		[self.scopeBar.delegate scopeBar:self.scopeBar item:item wasSelected:selected];
	}
}



@end









#pragma mark  
#pragma mark ========================================
@implementation AGScopeBarItem


+ (AGScopeBarItem *)itemWithIdentifier:(NSString *)identifier;
{
	return [[[[self class] alloc] initWithIdentifier:identifier] autorelease];
}



- (id)initWithIdentifier:(NSString *)identifier;
{
	if (!(self = [super init])) {
		return nil;
	}
	
	mIdentifier = [identifier retain];
	mIsEnabled = YES;
	
	return self;
}



- (id)init;
{
	[self doesNotRecognizeSelector:_cmd];
	return nil;
}



- (void)dealloc
{
	[mIdentifier release];
	[mTitle release];
	[mImage release];
	[mMenu release];
	[mButton release];
	[mMenuItem release];
	[super dealloc];
}




#pragma mark -
#pragma mark Properties

@synthesize identifier = mIdentifier;


- (void)setTitle:(NSString *)title;
{
	[mTitle autorelease];
	mTitle = [title copy];
	
	[self _updateButton];
}


- (NSString *)title;
{
	return mTitle;
}




- (void)setToolTip:(NSString *)tooltip;
{
	[mToolTip autorelease];
	mToolTip = [tooltip copy];
	
	[self _updateButton];
}


- (NSString *)toolTip;
{
	return mToolTip;
}




- (void)setImage:(NSImage *)image;
{
	[mImage autorelease];
	mImage = [image copy];
	[mImage setSize:NSMakeSize(SCOPE_BAR_BUTTON_IMAGE_SIZE, SCOPE_BAR_BUTTON_IMAGE_SIZE)];
	[self _updateButton];
}


- (NSImage *)image;
{
	return mImage;
}


- (void)setMenu:(NSMenu *)menu;
{
	[mMenu autorelease];
	mMenu = [menu retain];
	[self _updateButton];
}


- (NSMenu *)menu;
{
	return mMenu;
}


- (BOOL)isSelected;
{
	return mIsSelected;
}


- (void)setEnabled:(BOOL)isEnabled;
{
	mIsEnabled = isEnabled;
	[self _updateEnabling];
}


- (BOOL)isEnabled;
{
	return mIsEnabled;
}




#pragma mark -
#pragma mark Private

@synthesize group = mGroup;


- (NSButton *)button;
{
	return mButton;
}


- (NSMenuItem *)menuItem;
{
	NSString * title = (self.title ? : @"");
	
	if (!mMenuItem) {
		mMenuItem = [[NSMenuItem alloc] initWithTitle:title action:@selector(scopeButtonClicked:) keyEquivalent:@""];
	}
	
	[mMenuItem setTitle:title];
	[mMenuItem setTarget:self];
	[mMenuItem setImage:self.image];
	[mMenuItem setRepresentedObject:self];
	[mMenuItem setSubmenu:self.menu];
	[mMenuItem setState:(self.isSelected ? NSOnState : NSOffState)];
	
	return mMenuItem;
}



// ONLY CALLED BY THE GROUP
- (void)_setSelected:(BOOL)isSelected;
{
	mIsSelected = isSelected;
	[self _updateButton];
}



- (void)_recreateButton;
{
	NSButton * button = nil;
	
	
	
	// Popup Button
	// --------------------------------------------
	if (self.menu) {
		BOOL pullsDown = (self.title != nil); // Popups get their title from the selected item, so having a title means a pulldown. Use @"" if needed.
		AGScopeBarPopupButtonCell * cell = [[[AGScopeBarPopupButtonCell alloc] initTextCell:@"" pullsDown:pullsDown] autorelease];
		NSMenuItem * titleItem = [[[NSMenuItem alloc] init] autorelease];
		
		button = [[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:pullsDown] autorelease];
		[button setCell:cell];
		[cell setMenu:self.menu];
		[cell setUsesItemFromMenu:NO];
		[cell setMenuItem:titleItem];
		[cell setAltersStateOfSelectedItem:NO];
		[cell setArrowPosition:NSPopUpArrowAtBottom];
		[(NSPopUpButton *)button setPreferredEdge:NSMaxYEdge];
		
		// When it pulls down, the popup cell will take the title and image
		// from its menuItem property  and uses that for drawing. The menuItem's
		// title gets set when the button's title is set, but the image is not,
		// so we need to set the image manually.
		if (pullsDown) {
			titleItem.image = self.image;
			[self.menu insertItem:titleItem atIndex:0];
		}
		
		[self.menu setFont:SCOPE_BAR_MENUITEM_FONT];
		
		
		// Standard Button
		// --------------------------------------------
	} else {
		button = [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];
	}
	
	
	
	if (self.title) {
		[button setImage:nil];
		[button setTitle:self.title];
		[button setImagePosition:NSNoImage];
	} else if (self.image) {
		[button setImage:self.image];
		[button setTitle:@""];
		[button setImagePosition:NSImageOnly];
	} else {
		[button setImage:nil];
		[button setTitle:@""];
		[button setImagePosition:NSNoImage];
	}
	
	[button setToolTip:self.toolTip];
	[button.cell setRepresentedObject:self];
	[button setFont:SCOPE_BAR_FONT];
	[button setTarget:self];
	[button setAction:@selector(scopeButtonClicked:)];
	[button setBezelStyle:NSRecessedBezelStyle];
	[button setButtonType:NSPushOnPushOffButton];
	[button.cell setHighlightsBy:NSCellIsBordered | NSCellIsInsetButton];
	[button setShowsBorderOnlyWhileMouseInside:YES];
	[button.cell setBackgroundStyle:NSBackgroundStyleRaised];
	
	
	// ------------------------
	[mButton removeFromSuperview];
	[mButton release];
	mButton = [button retain];
}



- (void)_updateButton;
{
	if (!mButton ||
		(![mButton isKindOfClass:[NSPopUpButton class]] && self.menu) ||
		([mButton isKindOfClass:[NSPopUpButton class]] && !self.menu))
	{
		[self _recreateButton];
	}
	
	mButton.toolTip = self.toolTip;
	mButton.title = (self.title ? : @"");
	mButton.image = self.image;
	
	if ([mButton isKindOfClass:[NSPopUpButton class]]) {
		[[[mButton cell] menuItem] setImage:self.image];
	}
	
	if (self.image) {
		[mButton setImagePosition:((mButton.title.length == 0) ? NSImageOnly : NSImageLeft)];
	} else {
		[mButton setImagePosition:NSNoImage];
	}
	
	[[mButton cell] setImageScaling:NSImageScaleProportionallyDown];
	
	mButton.state = (self.isSelected ? NSOnState : NSOffState);
	[self _updateEnabling];
	
	[mButton sizeToFit];
	[self.group.scopeBar setNeedsTiling];
}



- (void)_updateEnabling;
{
	mButton.enabled = (self.group.scopeBar.isEnabled && self.group.isEnabled && self.isEnabled);
}



- (void)scopeButtonClicked:(id)sender;
{
	[self.group.scopeBar scopeButtonClicked:sender];
}


@end








#pragma mark  
#pragma mark ========================================
@implementation AGScopeBarPopupButtonCell

- (id)initTextCell:(NSString *)title pullsDown:(BOOL)pullsDown
{
	if (!(self = [super initTextCell:title pullsDown:pullsDown])) {
		return nil;
	}
	
	// The button is only used for drawing the button *background*.
	// The title/image is always drawn by this AGScopeBarPopupButtonCell itself.
	mRecessedButton = [[NSButton alloc] initWithFrame:NSZeroRect];
	mRecessedButton.title = @"";
	mRecessedButton.buttonType = NSPushOnPushOffButton;
	mRecessedButton.bezelStyle = NSRecessedBezelStyle;
	mRecessedButton.showsBorderOnlyWhileMouseInside = NO;
	[mRecessedButton.cell setHighlightsBy:NSCellIsBordered | NSCellIsInsetButton];
	mRecessedButton.state = NSOnState;
	
	// We use another popup cell so that the font of the displayed menu does not
	// have to be the font of the cell itself. The only other solid way around
	// that problem is to do the tracking and popup the menu ourselves. It may
	// be a bit odd, but it's easier to override methods and pass to mPopupCell
	mPopupCell = [[NSPopUpButtonCell alloc] initTextCell:title pullsDown:pullsDown];
	
	return self;
}



- (void)dealloc
{
	[mPopupCell release];
	[mRecessedButton release];
	[super dealloc];
}



- (id)copyWithZone:(NSZone *)zone;
{
	AGScopeBarPopupButtonCell * copy = [[AGScopeBarPopupButtonCell alloc] initTextCell:self.title pullsDown:self.pullsDown];
	
	copy.altersStateOfSelectedItem = self.altersStateOfSelectedItem;
	copy.menu = self.menu;
	copy.usesItemFromMenu = self.usesItemFromMenu;
	copy.menuItem = self.menuItem;
	
	return copy;
}






#pragma mark -

- (void)drawBezelWithFrame:(NSRect)frame inView:(NSView *)controlView
{
	[mRecessedButton setFrame:frame];
	[mRecessedButton drawRect:frame];
}



- (NSSize)cellSizeForBounds:(NSRect)frame
{
	// We customize cellSizeForBounds because NSPopupButtonCell's
	// implementation adds a ton of padding in some cases.
	// In our case we want the cell to fit to the title, icon, and
	// popup/pulldown indicator image exactly (with minor padding).
	
	NSSize superSize = [super cellSizeForBounds:frame];
	NSSize size = NSMakeSize(0, superSize.height);
	NSRect titleRect = [self titleRectForBounds:frame];
	NSRect imageRect = [self imageRectForBounds:frame];
	CGFloat titleWidth = round(self.attributedTitle.size.width);
	CGFloat widthForPopupImage = 0.0;
	CGFloat imgWidthPlusPadding = 0;
	CGFloat padding = 0;
	
	// Width of the space needed for the popup/pull down indicator image
	// including the padding to the left of it (between it and title or icon)
	widthForPopupImage = 10.0;
	
	// The padding that we should use on the left and right sides of everything
	padding = 7.0;
	
	// When there's an image, determine the width of it
	if (imageRect.size.width > 0) {
		
		// When there's a title, the icon is to the left of the title.
		// So, imgWidthPlusPadding is the distance between the left of
		// the title and icon.
		if (titleRect.size.width > 0) {
			imgWidthPlusPadding = (NSMinX(titleRect) - NSMinX(imageRect));
		
		// Otherwise if there is not title, it's just the image
		} else {
			imgWidthPlusPadding = NSWidth(imageRect);
		}
	}
	
	size.width = padding + imgWidthPlusPadding + titleWidth + widthForPopupImage + padding;
	size.width = MIN(frame.size.width, size.width);
	
	return size;
}






#pragma mark -

- (void)setAltersStateOfSelectedItem:(BOOL)flag
{
	[mPopupCell setAltersStateOfSelectedItem:flag];
}


- (BOOL)altersStateOfSelectedItem
{
	return [mPopupCell altersStateOfSelectedItem];
}


- (void)selectItem:(NSMenuItem *)item
{
	[mPopupCell selectItem:item];
}


- (NSMenuItem *)selectedItem
{
	return [mPopupCell selectedItem];
}


- (void)attachPopUpWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	[mPopupCell attachPopUpWithFrame:cellFrame inView:controlView];
}


- (void)dismissPopUp
{
	[mPopupCell dismissPopUp];
}


- (BOOL)trackMouse:(NSEvent *)theEvent inRect:(NSRect)cellFrame ofView:(NSView *)controlView untilMouseUp:(BOOL)untilMouseUp
{
	mPopupCell.controlView = controlView;
	mPopupCell.menu = self.menu;
	return [mPopupCell trackMouse:theEvent inRect:cellFrame ofView:controlView untilMouseUp:untilMouseUp];
}


@end
