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

#import "ZGHotKeyPreferencesViewController.h"
#import "ZGDebuggerController.h"
#import "ZGHotKeyCenter.h"
#import "ZGHotKey.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation-unknown-command"
#pragma clang diagnostic ignored "-Woverriding-method-mismatch"
#pragma clang diagnostic ignored "-Wobjc-messaging-id"
#import <ShortcutRecorder/ShortcutRecorder.h>
#pragma clang diagnostic pop

@interface ZGHotKeyPreferencesViewController () <SRRecorderControlDelegate>
@end

@implementation ZGHotKeyPreferencesViewController
{
	ZGHotKeyCenter * _Nonnull _hotKeyCenter;
	ZGDebuggerController * _Nonnull _debuggerController;
	
	IBOutlet SRRecorderControl *_pauseAndUnpauseHotKeyRecorder;
	IBOutlet SRRecorderControl *_stepInHotKeyRecorder;
	IBOutlet SRRecorderControl *_stepOverHotKeyRecorder;
	IBOutlet SRRecorderControl *_stepOutHotKeyRecorder;
}

- (id)initWithHotKeyCenter:(ZGHotKeyCenter *)hotKeyCenter debuggerController:(ZGDebuggerController *)debuggerController
{
	self = [super initWithNibName:@"Shortcuts View" bundle:nil];
	if (self != nil)
	{
		_hotKeyCenter = hotKeyCenter;
		_debuggerController = debuggerController;
	}
	return self;
}

- (void)_setUpRecorder:(SRRecorderControl *)recorder keyCombo:(ZGHotKey *)hotKey
{
	KeyCombo keyCombo = hotKey.keyCombo;
	
	recorder.delegate = self;
	
	if (keyCombo.code == INVALID_KEY_CODE && keyCombo.flags == INVALID_KEY_MODIFIER)
	{
		recorder.objectValue = nil;
	}
	else
	{
		recorder.objectValue =
		[SRShortcut
		 shortcutWithCode:(SRKeyCode)keyCombo.code
		 modifierFlags:SRCarbonToCocoaFlags((UInt32)keyCombo.flags)
		 characters:nil
		 charactersIgnoringModifiers:nil];
	}
}

- (void)loadView
{
	[super loadView];
	
	[self _setUpRecorder:_pauseAndUnpauseHotKeyRecorder keyCombo:_debuggerController.pauseAndUnpauseHotKey];
	
	[self _setUpRecorder:_stepInHotKeyRecorder keyCombo:_debuggerController.stepInHotKey];
	
	[self _setUpRecorder:_stepOverHotKeyRecorder keyCombo:_debuggerController.stepOverHotKey];
	
	[self _setUpRecorder:_stepOutHotKeyRecorder keyCombo:_debuggerController.stepOutHotKey];
}

- (BOOL)recorderControl:(SRRecorderControl *)aControl shouldUnconditionallyAllowModifierFlags:(NSEventModifierFlags)aModifierFlags forKeyCode:(SRKeyCode)aKeyCode
{
	return YES;
}

- (void)recorderControlDidEndRecording:(SRRecorderControl *)recorder
{
	SRShortcut *shortcut = recorder.objectValue;
	
	ZGHotKey *hotKey = nil;
	NSString *hotKeyDefaultsKey = nil;
	if (recorder == _pauseAndUnpauseHotKeyRecorder)
	{
		hotKey = _debuggerController.pauseAndUnpauseHotKey;
		hotKeyDefaultsKey = ZGPauseAndUnpauseHotKey;
	}
	else if (recorder == _stepInHotKeyRecorder)
	{
		hotKey = _debuggerController.stepInHotKey;
		hotKeyDefaultsKey = ZGStepInHotKey;
	}
	else if (recorder == _stepOverHotKeyRecorder)
	{
		hotKey = _debuggerController.stepOverHotKey;
		hotKeyDefaultsKey = ZGStepOverHotKey;
	}
	else if (recorder == _stepOutHotKeyRecorder)
	{
		hotKey = _debuggerController.stepOutHotKey;
		hotKeyDefaultsKey = ZGStepOutHotKey;
	}

	if (hotKey != nil)
	{
		[_hotKeyCenter unregisterHotKey:hotKey];
		
		if (shortcut == nil)
		{
			hotKey.keyCombo = [ZGHotKey hotKey].keyCombo;
			[[NSUserDefaults standardUserDefaults] removeObjectForKey:hotKeyDefaultsKey];
		}
		else
		{
			KeyCombo newCarbonKeyCode = {.code = shortcut.carbonKeyCode, .flags = shortcut.carbonModifierFlags};
			
			hotKey.keyCombo = newCarbonKeyCode;
			[_hotKeyCenter registerHotKey:hotKey delegate:_debuggerController];
			
			[[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:hotKey] forKey:hotKeyDefaultsKey];
		}
	}
}

@end
