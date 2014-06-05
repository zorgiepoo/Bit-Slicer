//
//  APTokenSearchField.m
//  TokenFieldTest
//
//  Created by Seth Willits on 12/4/13.
//  Copyright (c) 2013 Araelium Group. All rights reserved.
//

#import "APTokenSearchField.h"


@interface APTokenSearchFieldCell ()
- (void)valueDidChange;
@end


@interface APTokenSearchField ()
@end



@implementation APTokenSearchField
{
	
}


+ (Class)cellClass
{
	return [APTokenSearchFieldCell class];
}


- (APTokenSearchFieldCell *)cell
{
	return (APTokenSearchFieldCell *)[super cell];
}



- (void)resetCursorRects
{
	// We don't play well with super. We'll do it all ourselves.
	//[super resetCursorRects];
	
	
	[self addCursorRect:NSMakeRect(0, 0, 28, 22) cursor:[NSCursor arrowCursor]];
	
	if ([self.objectValue count] > 0) {
		[self addCursorRect:NSMakeRect(28, 0, self.bounds.size.width - 56, 22) cursor:[NSCursor IBeamCursor]];
		[self addCursorRect:NSMakeRect(self.bounds.size.width - 28, 0, 28, 22) cursor:[NSCursor arrowCursor]];
	} else {
		[self addCursorRect:NSMakeRect(28, 0, self.bounds.size.width - 28, 22) cursor:[NSCursor IBeamCursor]];
	}
}


- (void)setObjectValue:(id<NSCopying>)obj
{
	[super setObjectValue:obj];
	[self resetCursorRects];
	[self.currentEditor setSelectedRange:NSMakeRange(self.currentEditor.string.length, 0)];
	
}


- (BOOL)textView:(NSTextView *)__unused textView doCommandBySelector:(SEL)commandSelector
{
	if (commandSelector == @selector(insertNewline:)) {
		[self sendAction:self.action to:self.target];
		return YES;
	}
	
	if (commandSelector == @selector(cancelOperation:)) {
		self.objectValue = @[];
		[self.cell valueDidChange];
		return YES;
	}
	
	return NO;
}


- (void)textDidChange:(NSNotification *)notification
{
	[super textDidChange:notification];
	[self resetCursorRects];
}


@end




#pragma mark
@implementation APTokenSearchFieldCell
{
	NSSearchFieldCell * _searchFieldCell;
	NSTimer * _sendActionTimer;
	NSMenu * _searchMenu;
}


- (void)dealloc
{
	[_sendActionTimer invalidate];
	[_searchFieldCell release];
	[_searchMenu release];
	[super dealloc];
}


- (id)copyWithZone:(NSZone *)zone
{
	APTokenSearchFieldCell * copy = [super copyWithZone:zone];
	copy->_searchFieldCell = [_searchFieldCell copy];
	copy->_sendActionTimer = nil;
	copy->_searchMenu = [_searchMenu copy];
	return copy;
}



- (void)setSearchMenu:(NSMenu *)searchMenu
{
	[_searchMenu autorelease];
	_searchMenu = [searchMenu retain];
	
	self.searchFieldCell.menu = _searchMenu;
	[self.searchFieldCell setSearchMenuTemplate:searchMenu]; // Just so the image draws correctly
}


- (NSMenu *)searchMenu
{
	return _searchMenu;
}



//- (void)setObjectValue:(id<NSCopying>)obj;
//{
//	[super setObjectValue:obj];
//	[self valueDidChange];
//}





#pragma mark -

- (NSSearchFieldCell *)searchFieldCell
{
	if (!_searchFieldCell) {
		_searchFieldCell = [[NSSearchFieldCell alloc] init];
	}
	_searchFieldCell.controlView = self.controlView;
	return _searchFieldCell;
}


- (NSButtonCell *)searchButtonCell
{
	self.searchFieldCell.cancelButtonCell.controlView = self.controlView;
	return self.searchFieldCell.searchButtonCell;
}

- (NSButtonCell *)cancelButtonCell
{
	self.searchFieldCell.cancelButtonCell.controlView = self.controlView;
	return self.searchFieldCell.cancelButtonCell;
}


- (NSRect)searchTextRectForBounds:(NSRect)rect
{
	rect = [self.searchFieldCell searchTextRectForBounds:rect];
	return rect;
}

// For our hack below
#ifndef NSAppKitVersionNumber10_9
#define NSAppKitVersionNumber10_9 1265
#endif

- (NSRect)searchButtonRectForBounds:(NSRect)rect
{
	rect = [self.searchFieldCell searchButtonRectForBounds:rect];
	
	// Begin hack
	// Check if we need to offset the search magnifying glass button
	static BOOL checkedOffsetting;
	static BOOL shouldOffsetRect;
	if (!checkedOffsetting)
	{
		shouldOffsetRect = floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_9;
		checkedOffsetting = YES;
	}
	
	if (shouldOffsetRect)
	{
		rect.origin.x -= 53;
	}
	// End hack
	
	return rect;
}


- (NSRect)cancelButtonRectForBounds:(NSRect)rect
{
	return [self.searchFieldCell cancelButtonRectForBounds:rect];
}




#pragma mark -
#pragma mark


- (NSUInteger)hitTestForEvent:(NSEvent *)event inRect:(NSRect)cellFrame ofView:(NSView *)controlView
{
	NSPoint pointInView = [controlView convertPoint:event.locationInWindow fromView:nil];
	NSPoint pointInCell = NSMakePoint(pointInView.x - cellFrame.origin.x, pointInView.y - cellFrame.origin.y);
	
	if (NSPointInRect(pointInCell, [self searchButtonRectForBounds:cellFrame])) {
		return NSCellHitTrackableArea;
	}
	
	if (NSPointInRect(pointInCell, [self cancelButtonRectForBounds:cellFrame])) {
		return NSCellHitTrackableArea;
	}
	
	return [super hitTestForEvent:event inRect:cellFrame ofView:controlView];
}


- (BOOL)trackMouse:(NSEvent *)event inRect:(NSRect)cellFrame ofView:(NSView *)controlView untilMouseUp:(BOOL)flag
{
	NSPoint pointInView = [controlView convertPoint:event.locationInWindow fromView:nil];
	NSPoint pointInCell = NSMakePoint(pointInView.x - cellFrame.origin.x, pointInView.y - cellFrame.origin.y);
	
	if (NSPointInRect(pointInCell, [self searchButtonRectForBounds:cellFrame])) {
		[self.searchMenu popUpMenuPositioningItem:nil atLocation:NSMakePoint(cellFrame.origin.x, NSMaxY(cellFrame) + 6.0) inView:controlView];
		return YES;
	}
	
	if (NSPointInRect(pointInCell, [self cancelButtonRectForBounds:cellFrame])) {
		NSRect cancelButtonRect = [self cancelButtonRectForBounds:cellFrame];
		BOOL stop = NO;
		
		self.cancelButtonCell.highlighted = YES;
		[controlView setNeedsDisplay:YES];
		
		while (!stop) {
			event = [[controlView window] nextEventMatchingMask:NSLeftMouseUpMask | NSLeftMouseDraggedMask];
			pointInView = [controlView convertPoint:event.locationInWindow fromView:nil];
			BOOL isInside = [controlView mouse:pointInView inRect:cancelButtonRect];
			
			switch (event.type) {
				case NSLeftMouseDragged:
					if (self.cancelButtonCell.isHighlighted != isInside) {
						self.cancelButtonCell.highlighted = isInside;
						[controlView setNeedsDisplay:YES];
					}
					break;
				case NSLeftMouseUp:
					self.cancelButtonCell.highlighted = NO;
					[controlView setNeedsDisplay:YES];
					if (isInside) {
						self.objectValue = @[];
						[self valueDidChange];
					}
					stop = YES;
					break;
			}
		}
	}
	
	return [super trackMouse:event inRect:cellFrame ofView:controlView untilMouseUp:flag];
}


//- (void)editWithFrame:(NSRect)aRect inView:(NSView *)controlView editor:(NSText *)textObj delegate:(id)anObject event:(NSEvent *)theEvent
//{
//	[super editWithFrame:aRect inView:controlView editor:textObj delegate:anObject event:theEvent];
//}
//
//
//- (void)selectWithFrame:(NSRect)aRect inView:(NSView *)controlView editor:(NSText *)textObj delegate:(id)anObject start:(NSInteger)selStart length:(NSInteger)selLength
//{
//	[super selectWithFrame:aRect inView:controlView editor:textObj delegate:anObject start:selStart length:selLength];
//}



#pragma mark -
#pragma mark Editing

// The *text* interior bounds. Such a confusingly named method.
// This is called by drawInteriorWithFrame:
- (NSRect)drawingRectForBounds:(NSRect)cellFrame
{
	// We need to use the NSTokenField's values in order to get the right y and height
	NSRect rect = [super drawingRectForBounds:cellFrame];
	
	// But the searchFieldCell's x and width work better for handling the buttons.
	NSRect sfrect = [self.searchFieldCell drawingRectForBounds:cellFrame];
	rect.origin.x = sfrect.origin.x;
	rect.size.width = sfrect.size.width;
	
	return rect;
}


- (void)textDidChange:(NSNotification *)__unused notification
{
	if (!self.sendsSearchStringOnlyAfterReturn)
	{
		[self valueDidChange];
	}
}


- (void)valueDidChange
{
	if (self.sendsSearchStringImmediately) {
		[self sendActionToTarget];
	} else {
		[_sendActionTimer invalidate];
		_sendActionTimer = nil;
		
		_sendActionTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(sendActionToTarget) userInfo:nil repeats:NO];
	}
}


- (void)sendActionToTarget
{
	_sendActionTimer = nil;
	dispatch_async(dispatch_get_main_queue(), ^{
		[(NSControl *)self.controlView sendAction:self.action to:self.target];
	});
	
}



- (NSText *)setUpFieldEditorAttributes:(NSText *)textObj
{
	//	[textObj setBackgroundColor:[NSColor blueColor]];
	//	[textObj setDrawsBackground:YES];
	return textObj;
}


#pragma mark -
#pragma mark Drawing

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	NSRect searchButtonRect = [self searchButtonRectForBounds:cellFrame];
	NSRect cancelButtonRect = [self cancelButtonRectForBounds:cellFrame];
	//NSRect searchTextRect = [self searchTextRectForBounds:cellFrame];
	
	[self.searchButtonCell drawWithFrame:searchButtonRect inView:controlView];
	
	BOOL hasSearch = NO;
	if ([(NSArray *)self.objectValue count] > 0) hasSearch = YES;
	if (hasSearch) {
		[self.cancelButtonCell drawWithFrame:cancelButtonRect inView:controlView];
	}
	
	[super drawInteriorWithFrame:cellFrame inView:controlView];
}

@end
