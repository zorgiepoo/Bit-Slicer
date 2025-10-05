/*
 * Copyright (c) 2015 Mayur Pawashe
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

#import "ZGDeliverUserNotifications.h"
#import <UserNotifications/UserNotifications.h>

#define ZGUserNotificationReplyCategory @"ZGUserNotificationReplyCategory"

void ZGInitializeDeliveredNotificationCategories(void)
{
	UNTextInputNotificationAction *textInputNotificationAction = [UNTextInputNotificationAction actionWithIdentifier:@"REPLY_ACTION" title:@"Reply" options:0 textInputButtonTitle:@"Send" textInputPlaceholder:@""];
	
	UNNotificationCategory *category = [UNNotificationCategory categoryWithIdentifier:ZGUserNotificationReplyCategory actions:@[textInputNotificationAction] intentIdentifiers:@[] options:0];
	
	UNUserNotificationCenter *notificationCenter = [UNUserNotificationCenter currentNotificationCenter];
	[notificationCenter setNotificationCategories:[NSSet setWithObject:category]];
}

void ZGDeliverUserNotificationWithReplyOption(NSString *title, NSString *subtitle, NSString *informativeText, NSString * _Nullable replyActionIdentifier, NSDictionary<NSString *, id> *userInfo)
{
	UNUserNotificationCenter *notificationCenter = [UNUserNotificationCenter currentNotificationCenter];
	UNAuthorizationOptions authorizationOptions = UNAuthorizationOptionAlert;
	[notificationCenter requestAuthorizationWithOptions:authorizationOptions completionHandler:^(BOOL granted, NSError * _Nullable __unused error) {
		if (!granted)
		{
			return;
		}
		
		dispatch_async(dispatch_get_main_queue(), ^{
			UNMutableNotificationContent *notificationContent = [[UNMutableNotificationContent alloc] init];
			notificationContent.title = title;
			notificationContent.subtitle = subtitle;
			notificationContent.body = informativeText;
			notificationContent.userInfo = userInfo;
			
			NSString *requestIdentifier;
			if (replyActionIdentifier != nil)
			{
				notificationContent.categoryIdentifier = ZGUserNotificationReplyCategory;
				requestIdentifier = replyActionIdentifier;
			}
			else
			{
				static uint64_t genericNotificationIDCounter = 0;
				
				requestIdentifier = [NSString stringWithFormat:@"GENERIC_%llu", genericNotificationIDCounter];
				genericNotificationIDCounter++;
			}
			
			UNTimeIntervalNotificationTrigger *trigger;
			if (replyActionIdentifier != nil && [NSApp isActive])
			{
				trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:5.0 repeats:NO];
			}
			else
			{
				trigger = nil;
			}
			
			UNNotificationRequest *notificationRequest = [UNNotificationRequest requestWithIdentifier:requestIdentifier content:notificationContent trigger:trigger];
			
			[notificationCenter addNotificationRequest:notificationRequest withCompletionHandler:nil];
		});
	}];
}

void ZGDeliverUserNotificationWithReply(NSString *title, NSString *subtitle, NSString *informativeText, NSString * _Nullable replyActionIdentifier, NSDictionary<NSString *, id> *userInfo)
{
	ZGDeliverUserNotificationWithReplyOption(title, subtitle, informativeText, replyActionIdentifier, userInfo);
}

void ZGDeliverUserNotification(NSString *title, NSString *subtitle, NSString *informativeText)
{
	ZGDeliverUserNotificationWithReplyOption(title, subtitle, informativeText, nil, @{});
}
