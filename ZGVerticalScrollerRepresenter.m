/*
 * Created by Mayur Pawashe on 5/12/11
 * Copyright 2011 zgcoder. All rights reserved.
 */

#import "ZGVerticalScrollerRepresenter.h"

@implementation ZGVerticalScrollerRepresenter

// Fixes a bug in Hex Fiend's scrollByLines: where clicking the up button in the scroll wheel would scroll
// all the way down
- (void)scrollByLines:(long long)linesInt
{
    if (linesInt == 0) return;
    
    long double lines = HFULToFP(linesInt);
    
    HFController *controller = [self controller];
    //HFASSERT(controller != NULL);
    HFFPRange displayedRange = [[self controller] displayedLineRange];
    if (linesInt < 0) {
        displayedRange.location += MIN((long double)linesInt, displayedRange.location);
    }
    else {
        long double availableLines = HFULToFP([controller totalLineCount]);
        displayedRange.location = MIN(availableLines - displayedRange.length, displayedRange.location + lines);
    }
    [controller setDisplayedLineRange:displayedRange];
}

@end
