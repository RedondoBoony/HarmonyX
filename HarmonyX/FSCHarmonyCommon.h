//
//  FSCHarmonyCommon.h
//  HarmonyX
//
//  Created by Philippe Boudreau on 2014-10-28.
//  Copyright (c) 2014 Fasterre. All rights reserved.
//

#ifndef HarmonyX_FSCHarmonyCommon_h
#define HarmonyX_FSCHarmonyCommon_h

#ifdef DEBUG
#    define DLog(...) NSLog(__VA_ARGS__)
#else
#    define DLog(...)
#endif
#define ALog(...) NSLog(__VA_ARGS__)

#import <Foundation/Foundation.h>

static NSString * const FSCExceptionSetup = @"FSCExceptionSetup";
static NSString * const FSCExceptionCredentials = @"FSCExceptionCredentials";
static NSString * const FSCExceptionMyHarmonyConnection = @"FSCExceptionMyHarmonyConnection";
static NSString * const FSCExceptionHarmonyHubConnection = @"FSCExceptionHarmonyHubConnection";
static NSString * const FSCExceptionHarmonyHubConfiguration = @"FSCExceptionHarmonyHubConfiguration";
static NSString * const FSCExceptionHarmonyHubCurrentActivity = @"FSCExceptionHarmonyHubCurrentActivity";
static NSString * const FSCExceptionHarmonyHubIQCmdTimedOut = @"FSCExceptionHarmonyHubIQCmdTimedOut";

static NSString * const FSCErrorDomain = @"com.trov.trov";

static int const FSCErrorCodeUnexpectedMyHarmonyResponse = 1;
static int const FSCErrorCodeErrorPerformingClientAction = 2;
static int const FSCErrorCodeMissingSetup = 3;
static int const FSCErrorCodeMissingCredentials = 4;

static NSString * const FSCErrorUserInfoKeyOriginalError = @"FSCErrorUserInfoKeyOriginalError";

static NSString * const FSCErrorHarmonyXMPPNetworkUnreachable = @"Network is unreachable";
static NSString * const FSCErrorHarmonyXMPPConnectionRefused = @"Connection refused";

#endif
