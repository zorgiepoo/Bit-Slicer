/*
 * Created by Mayur Pawashe on 3/9/14.
 *
 * Copyright (c) 2014 zgcoder
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

#import "ZGHotKeyController.h"
#import "ZGProcess.h"
#import "ZGProcessTaskManager.h"
#import "ZGDebuggerController.h"
#import "ZGUtilities.h"

#import <Carbon/Carbon.h>

@interface ZGHotKeyController ()

@property (nonatomic) ZGProcessTaskManager *processTaskManager;
@property (nonatomic) ZGDebuggerController *debuggerController;

@property (nonatomic) EventHotKeyRef pauseHotKeyRef;

@end

@implementation ZGHotKeyController

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		[NSUserDefaults.standardUserDefaults registerDefaults:@{ZG_HOT_KEY : @INVALID_KEY_CODE, ZG_HOT_KEY_MODIFIER : @INVALID_KEY_MODIFIER}];
	});
}

- (id)initWithProcessTaskManager:(ZGProcessTaskManager *)processTaskManager debuggerController:(ZGDebuggerController *)debuggerController
{
	self = [super init];
	if (self != nil)
	{
		self.processTaskManager = processTaskManager;
		self.debuggerController = debuggerController;
		
		NSInteger hotKeyCode = [NSUserDefaults.standardUserDefaults integerForKey:ZG_HOT_KEY];
		// INVALID_KEY_CODE used to be set at -999 (now it's at -1), so just take this into account
		if (hotKeyCode < INVALID_KEY_CODE)
		{
			hotKeyCode = INVALID_KEY_CODE;
			[NSUserDefaults.standardUserDefaults setInteger:INVALID_KEY_CODE forKey:ZG_HOT_KEY];
		}
		
		_pauseHotKeyCombo = (KeyCombo){.code = hotKeyCode, .flags = (NSUInteger)[NSUserDefaults.standardUserDefaults integerForKey:ZG_HOT_KEY_MODIFIER]};
		
		[self registerPauseAndUnpauseHotKey];
	}
	return self;
}

- (void)setPauseHotKeyCombo:(KeyCombo)pauseHotKeyCombo
{
	_pauseHotKeyCombo = pauseHotKeyCombo;
	
	[NSUserDefaults.standardUserDefaults setInteger:(NSInteger)_pauseHotKeyCombo.code forKey:ZG_HOT_KEY];
	[NSUserDefaults.standardUserDefaults setInteger:(NSInteger)_pauseHotKeyCombo.flags forKey:ZG_HOT_KEY_MODIFIER];
	
	[self registerPauseAndUnpauseHotKey];
}

static OSStatus pauseOrUnpauseHotKeyHandler(EventHandlerCallRef __unused nextHandler, EventRef __unused theEvent, void *userData)
{
	ZGHotKeyController *self = (__bridge ZGHotKeyController *)(userData);
	
	for (NSRunningApplication *runningApplication in NSWorkspace.sharedWorkspace.runningApplications)
	{
		if (runningApplication.isActive)
		{
			if (runningApplication.processIdentifier != getpid() && ![self.debuggerController isProcessIdentifierHalted:runningApplication.processIdentifier])
			{
				ZGMemoryMap processTask = 0;
				if ([self.processTaskManager getTask:&processTask forProcessIdentifier:runningApplication.processIdentifier])
				{
					[ZGProcess pauseOrUnpauseProcessTask:processTask];
				}
				else
				{
					ZG_LOG(@"Failed to pause/unpause process with pid %d", runningApplication.processIdentifier);
				}
			}
			
			break;
		}
	}
	
	return noErr;
}

- (void)registerPauseAndUnpauseHotKey
{
	if (self.pauseHotKeyRef != NULL)
	{
		UnregisterEventHotKey(self.pauseHotKeyRef);
	}
    
	if (self.pauseHotKeyCombo.code != INVALID_KEY_CODE)
	{
		EventTypeSpec eventType = {.eventClass = kEventClassKeyboard, .eventKind = kEventHotKeyPressed};
		InstallApplicationEventHandler(&pauseOrUnpauseHotKeyHandler, 1, &eventType, (__bridge void *)self, NULL);
		
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wfour-char-constants"
		RegisterEventHotKey((UInt32)self.pauseHotKeyCombo.code, (UInt32)self.pauseHotKeyCombo.flags, (EventHotKeyID){.signature = 'htk1', .id = 1}, GetApplicationEventTarget(), 0, &_pauseHotKeyRef);
#pragma clang diagnostic pop
	}
}

@end
