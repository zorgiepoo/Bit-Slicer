/*
 * Copyright (c) 2014 Mayur Pawashe
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * Redistributions of source code must retain the above copyright notice,
 * this list of conditions and the following disclaimer.
 *
 * Redistributions in binary form must reproduce the above copyright
 * notice, this list of conditions and the following disclaimer in the
 * documentation and/or other materials provided with the distribution.
 *
 * Neither the name of the project's author nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
 * TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "ZGHotKeyCenter.h"
#import <Carbon/Carbon.h>
#import "ZGHotKey.h"

@implementation ZGHotKeyCenter
{
	NSMutableArray<ZGHotKey *> * _Nullable _registeredHotKeys;
	UInt32 _nextRegisteredHotKeyID;
}

static OSStatus hotKeyHandler(EventHandlerCallRef __unused nextHandler, EventRef theEvent, void *userData)
{
	@autoreleasepool
	{
		ZGHotKeyCenter *self = (__bridge ZGHotKeyCenter *)(userData);
	
		EventHotKeyID hotKeyID;
        if (GetEventParameter(theEvent, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(hotKeyID), NULL, &hotKeyID) == noErr)
		{
			for (ZGHotKey *registeredHotKey in self->_registeredHotKeys)
			{
				if (registeredHotKey.internalID == hotKeyID.id)
				{
					id <ZGHotKeyDelegate> delegate = registeredHotKey.delegate;
					[delegate hotKeyDidTrigger:registeredHotKey];
					break;
				}
			}
		}
	}

	return noErr;
}

- (BOOL)registerHotKey:(ZGHotKey *)hotKey delegate:(id <ZGHotKeyDelegate>)delegate
{
	for (ZGHotKey *registeredHotKey in _registeredHotKeys)
	{
		if (registeredHotKey.valid && registeredHotKey.keyCombo.code == hotKey.keyCombo.code && registeredHotKey.keyCombo.flags == hotKey.keyCombo.flags)
		{
			return NO;
		}
	}

	if (hotKey.valid)
	{
		if (_registeredHotKeys == nil)
		{
			_registeredHotKeys = [NSMutableArray array];

			EventTypeSpec eventType = {.eventClass = kEventClassKeyboard, .eventKind = kEventHotKeyPressed};
			if (InstallApplicationEventHandler(&hotKeyHandler, 1, &eventType, (__bridge void *)self, NULL) != noErr)
			{
				return NO;
			}
		}

		_nextRegisteredHotKeyID++;
		hotKey.delegate = delegate;
		hotKey.internalID = _nextRegisteredHotKeyID;

		EventHotKeyRef newHotKeyRef = hotKey.hotKeyRef;
		if (RegisterEventHotKey((UInt32)hotKey.keyCombo.code, (UInt32)hotKey.keyCombo.flags, (EventHotKeyID){.signature = hotKey.internalID, .id = hotKey.internalID}, GetApplicationEventTarget(), 0, &newHotKeyRef) != noErr)
		{
			return NO;
		}
		hotKey.hotKeyRef = newHotKeyRef;
	}

	[_registeredHotKeys addObject:hotKey];

	return YES;
}

- (BOOL)unregisterHotKey:(ZGHotKey *)hotKey
{
	if (![_registeredHotKeys containsObject:hotKey])
	{
		return NO;
	}
	
	if (hotKey.valid)
	{
		if (UnregisterEventHotKey(hotKey.hotKeyRef) != noErr)
		{
			return NO;
		}
	}
	
	[_registeredHotKeys removeObject:hotKey];
	
	return YES;
}

- (ZGHotKey *)unregisterHotKeyWithInternalID:(UInt32)internalID
{
	ZGHotKey *foundHotKey = nil;
	for (ZGHotKey *hotKey in _registeredHotKeys)
	{
		if (hotKey.internalID == internalID)
		{
			foundHotKey = hotKey;
			break;
		}
	}
	
	if (foundHotKey == nil || ![self unregisterHotKey:foundHotKey])
	{
		return nil;
	}
	
	return foundHotKey;
}

- (NSArray<ZGHotKey *> *)unregisterHotKeysWithDelegate:(id <ZGHotKeyDelegate>)delegate
{
	NSMutableArray<ZGHotKey *> *foundHotKeys = [NSMutableArray array];
	for (ZGHotKey *hotKey in _registeredHotKeys)
	{
		if (hotKey.delegate == delegate)
		{
			[foundHotKeys addObject:hotKey];
		}
	}
	
	for (ZGHotKey *hotKey in foundHotKeys)
	{
		[self unregisterHotKey:hotKey];
	}
	return [NSArray arrayWithArray:foundHotKeys];
}

- (BOOL)isRegisteredHotKey:(ZGHotKey *)hotKey
{
	for (ZGHotKey *registeredHotKey in _registeredHotKeys)
	{
		if (registeredHotKey.keyCombo.code == hotKey.keyCombo.code && registeredHotKey.keyCombo.flags == hotKey.keyCombo.flags)
		{
			return YES;
		}
	}
	
	CFArrayRef cfSystemHotKeyDictionaries = NULL;
	if (CopySymbolicHotKeys(&cfSystemHotKeyDictionaries) == noErr)
	{
		NSArray<NSDictionary<NSString *, id> *> *systemHotKeyDictionaries = (__bridge_transfer NSArray *)cfSystemHotKeyDictionaries;
		for (NSDictionary<NSString *, id> *hotKeyDictionary in systemHotKeyDictionaries)
		{
			BOOL enabled = [(NSNumber *)[hotKeyDictionary objectForKey:(__bridge NSString *)kHISymbolicHotKeyEnabled] boolValue];
			if (enabled)
			{
				UInt32 keyCode = [(NSNumber *)[hotKeyDictionary objectForKey:(__bridge NSString *)kHISymbolicHotKeyCode] unsignedIntValue];
				UInt32 modifierFlags = [(NSNumber *)[hotKeyDictionary objectForKey:(__bridge NSString *)kHISymbolicHotKeyModifiers] unsignedIntValue];
				if (hotKey.keyCombo.code == keyCode && hotKey.keyCombo.flags == modifierFlags)
				{
					return YES;
				}
			}
		}
	}
	
	return NO;
}

@end
