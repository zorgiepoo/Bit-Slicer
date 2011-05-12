/*
 * This file is part of Bit Slicer.
 *
 * Bit Slicer is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 
 * Bit Slicer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 
 * You should have received a copy of the GNU General Public License
 * along with Bit Slicer.  If not, see <http://www.gnu.org/licenses/>.
 * 
 * Created by Mayur Pawashe on 5/12/11
 * Copyright 2011 zgcoder. All rights reserved.
 */

#import <Foundation/Foundation.h>
#import <HexFiend/HexFiend.h>
#import "ZGMemoryTypes.h"

@interface ZGLineCountingRepresenter : HFLineCountingRepresenter
{
	ZGMemoryAddress _beginningMemoryAddress;
}

- (void)setBeginningMemoryAddress:(ZGMemoryAddress)newBeginningMemoryAddress;
- (ZGMemoryAddress)beginningMemoryAddress;

@end
