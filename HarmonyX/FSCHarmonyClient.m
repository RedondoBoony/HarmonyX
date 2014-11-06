//
//  FSCHarmonyClient.m
//  HarmonyX
//
//  Created by Philippe Boudreau on 2014-11-06.
//  Copyright (c) 2014 Fasterre. All rights reserved.
//

#import "FSCHarmonyClient.h"

#import <AFNetworking/AFNetworking.h>
#import <XMPPFramework/XMPP.h>

#import "FSCHarmonyCommon.h"

static NSString * const MY_HARMONY_AUTH_URL = @"https://svcs.myharmony.com/CompositeSecurityServices/Security.svc/json/GetUserAuthToken";

static NSString * const GENERAL_HARMONY_HUB_USERNAME = @"guest@connect.logitech.com/harmony";
static NSString * const GENERAL_HARMONY_HUB_PASSWORD = @"harmony";

@interface FSCHarmonyClient ()
{
    BOOL didDisconnectWhileConnecting;
    BOOL isXMPPConnected;
    BOOL isXMPPAuthenticated;
    BOOL didXMPPFailAuthentication;
    BOOL validOAResponseReceived;
}

@property (nonatomic, copy) NSString * myHarmonyUsername;
@property (nonatomic, copy) NSString * myHarmonyPassword;
@property (nonatomic, copy) NSString * harmonyHubIPAddress;
@property (nonatomic, assign) NSUInteger harmonyHubPort;

@property (nonatomic, strong) XMPPStream * xmppStream;

@property (nonatomic, strong) NSXMLElement * authenticationFailureError;

@property (nonatomic, copy) BOOL(^OAResponseValidationBlock)(NSXMLElement * OAResponse);
@property (nonatomic, strong) id validOAResponse;

@end

@implementation FSCHarmonyClient

#pragma mark - Class Methods

- (id) initWithMyHarmonyUsername: (NSString *) username
               myHarmonyPassword: (NSString *) password
             harmonyHubIPAddress: (NSString *) IPAddress
                  harmonyHubPort: (NSUInteger) port
{
    if (self = [super init])
    {
        [self setMyHarmonyUsername: username];
        [self setMyHarmonyPassword: password];
        [self setHarmonyHubIPAddress: IPAddress];
        [self setHarmonyHubPort: port];
        
        didDisconnectWhileConnecting = NO;
        isXMPPConnected = NO;
        isXMPPAuthenticated = NO;
        didXMPPFailAuthentication = NO;
        validOAResponseReceived = NO;
    }
    
    return self;
}

+ (id) clientWithMyHarmonyUsername: (NSString *) username
                 myHarmonyPassword: (NSString *) password
               harmonyHubIPAddress: (NSString *) IPAddress
                    harmonyHubPort: (NSUInteger) port
{
    FSCHarmonyClient * client = [[self alloc] initWithMyHarmonyUsername: username
                                                      myHarmonyPassword: password
                                                    harmonyHubIPAddress: IPAddress
                                                         harmonyHubPort: port];
    
    [client setupXMPPStream];
    
    [client connectToHarmonyHub];
    
    return  client;
}

#pragma mark - Initialization & Connection

- (void) connectToHarmonyHub
{
    didDisconnectWhileConnecting = NO;
    isXMPPConnected = NO;
    isXMPPAuthenticated = NO;
    didXMPPFailAuthentication = NO;
    validOAResponseReceived = NO;
    [self setAuthenticationFailureError: nil];
    
    NSString * myHarmonyToken = [self requestMyHarmonyToken];
    
    [self connectAndAuthenticateXMPPStreamWithUsername: GENERAL_HARMONY_HUB_USERNAME
                                              password: GENERAL_HARMONY_HUB_PASSWORD];
    
    NSString * harmonyHubToken = [self swapMyHarmonyTokenForHarmonyHubToken: myHarmonyToken];
    
    [self disconnect];

    [self connectAndAuthenticateXMPPStreamWithUsername: [NSString stringWithFormat:
                                                         @"%@@connect.logitech.com/harmony",
                                                         harmonyHubToken]
                                              password: harmonyHubToken];
}

- (NSString *) requestMyHarmonyToken
{
    AFHTTPRequestOperationManager * manager = [AFHTTPRequestOperationManager manager];
    [manager setCompletionQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)];
    
    [manager setRequestSerializer: [AFJSONRequestSerializer new]];
    
    NSDictionary * parameters = @{@"email": [self myHarmonyUsername],
                                  @"password": [self myHarmonyPassword]};
    
    __block NSString * myHarmonyToken = nil;
    __block BOOL asyncOperationCompleted = NO;
    __block NSError * error = nil;
    
    [manager POST: MY_HARMONY_AUTH_URL
       parameters: parameters
          success: ^(AFHTTPRequestOperation *operation, id responseObject)
     {
         NSDictionary * result = [responseObject objectForKey: @"GetUserAuthTokenResult"];
         
         if (!result)
         {
             error = [NSError errorWithDomain: FSCErrorDomain
                                         code: FSCErrorCodeUnexpectedMyHarmonyResponse
                                     userInfo: @{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                                                                             @"Could not find user auth token result keyed on 'GetUserAuthTokenResult' in JSON: %@",
                                                                             responseObject]}];
         }
         
         if (!error)
         {
             myHarmonyToken = [result objectForKey: @"UserAuthToken"];
             
             if (!myHarmonyToken)
             {
                 error = [NSError errorWithDomain: FSCErrorDomain
                                             code: FSCErrorCodeUnexpectedMyHarmonyResponse
                                         userInfo: @{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                                                                                 @"Could not find token keyed on 'UserAuthToken' in JSON: %@",
                                                                                 responseObject]}];
             }
         }
         
         asyncOperationCompleted = YES;
     }
          failure: ^(AFHTTPRequestOperation *operation, NSError *myHarmonyError)
     {
         error = [NSError errorWithDomain: FSCErrorDomain
                                     code: FSCErrorCodeUnexpectedMyHarmonyResponse
                                 userInfo: @{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                                                                         @"An error occurred in GetUserToken: %@",
                                                                         [myHarmonyError localizedDescription]]}];
         
         asyncOperationCompleted = YES;
     }];
    
    dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        
        while (!asyncOperationCompleted)
        {
            [NSThread sleepForTimeInterval: 0.25];
        }
    });
    
    if (error)
    {
        @throw [NSException exceptionWithName: FSCExceptionMyHarmonyConnection
                                       reason: [NSString stringWithFormat:
                                                @"An error occurred while requesting My Harmony token: %@",
                                                [error description]]
                                     userInfo: nil];
    }
    
    return myHarmonyToken;
}

- (void) setupXMPPStream
{
    NSAssert([self xmppStream] == nil, @"Method setupXMPPStream invoked multiple times");
    
    [self setXmppStream: [[XMPPStream alloc] init]];
    
    [[self xmppStream] addDelegate: self
                     delegateQueue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)];
    
    [[self xmppStream] setHostName: [self harmonyHubIPAddress]];
    [[self xmppStream] setHostPort: [self harmonyHubPort]];
}

- (void) connectAndAuthenticateXMPPStreamWithUsername: (NSString *) username
                                             password: (NSString *) password
{
    NSLog(@"%@", NSStringFromSelector(_cmd));
    
    if ([[self xmppStream] isDisconnected])
    {
        [[self xmppStream] setMyJID: [XMPPJID jidWithString: username]];
        
        NSError * error = nil;
        
        if (![[self xmppStream] connectWithTimeout: 5
                                             error: &error])
        {
            @throw [NSException exceptionWithName: FSCExceptionHarmonyHubConnection
                                           reason: [NSString stringWithFormat:
                                                    @"Could not connect to Harmony Hub: %@",
                                                    [error localizedDescription]]
                                         userInfo: nil];
        }
        
        dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
           
            while (!isXMPPConnected &&
                   !didDisconnectWhileConnecting)
            {
                [NSThread sleepForTimeInterval: 0.25];
            }
        });
        
        if (didDisconnectWhileConnecting)
        {
            didDisconnectWhileConnecting = NO;
            
            @throw [NSException exceptionWithName: FSCExceptionHarmonyHubConnection
                                           reason: [NSString stringWithFormat:
                                                    @"Could not connect to Harmony Hub: %@",
                                                    [error localizedDescription]]
                                         userInfo: nil];
        }
        
        if (![[self xmppStream] authenticateWithPassword: password
                                                   error: &error])
        {
            @throw [NSException exceptionWithName: FSCExceptionHarmonyHubConnection
                                           reason: [NSString stringWithFormat:
                                                    @"Could not authenticate to Harmony Hub: %@",
                                                    [error localizedDescription]]
                                         userInfo: nil];
        }
        
        dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            
            while (!isXMPPAuthenticated &&
                   !didXMPPFailAuthentication)
            {
                [NSThread sleepForTimeInterval: 0.25];
            }
        });
        
        if (didXMPPFailAuthentication)
        {
            [self disconnect];
            
            @throw [NSException exceptionWithName: FSCExceptionHarmonyHubConnection
                                           reason: [NSString stringWithFormat:
                                                    @"Could not authenticate to Harmony Hub: %@",
                                                    [self authenticationFailureError]]
                                         userInfo: nil];
        }
    }
    else
    {
        @throw [NSException exceptionWithName: FSCExceptionHarmonyHubConnection
                                       reason: @"XMPP Stream is already connected"
                                     userInfo: nil];
    }
}

- (NSString *) swapMyHarmonyTokenForHarmonyHubToken: (NSString *) myHarmonyToken
{
    NSLog(@"%@", NSStringFromSelector(_cmd));
    
    NSXMLElement * actionCmd = [[NSXMLElement alloc] initWithName: @"oa"
                                                            xmlns: @"connect.logitech.com"];
    [actionCmd addAttributeWithName: @"mime"
                        stringValue: @"vnd.logitech.connect/vnd.logitech.pair"];
    [actionCmd setStringValue: [NSString stringWithFormat:
                                @"token=%@:name=%@",
                                myHarmonyToken,
                                @"harmony#iOS6.0.1#iPhone"]];
    
    XMPPIQ * iqCmd = [XMPPIQ iqWithType: @"get"
                                  child: actionCmd];
    
    __block NSString * OAAttributesAndValuesString = nil;
    
    [self sendIQCmd: iqCmd
andWaitForValidResponse: ^BOOL(DDXMLElement *OAResponse)
    {
        BOOL validResponse = NO;
        
        NSString * OAString = [OAResponse stringValue];
        
        if (OAString)
        {
            validResponse = YES;
            
            OAAttributesAndValuesString = OAString;
        }
        
        return validResponse;
    }];
    
    NSString * harmonyHubToken = nil;
    
    NSArray * OAAttributesAndValues = [OAAttributesAndValuesString componentsSeparatedByString: @":"];
    
    for (NSString * anAttributeAndValue in OAAttributesAndValues)
    {
        NSArray * attributeAndValue = [anAttributeAndValue componentsSeparatedByString: @"="];
        
        if ([attributeAndValue count] == 2 &&
            [attributeAndValue[0] isEqualToString: @"identity"])
        {
            harmonyHubToken = attributeAndValue[1];
            
            break;
        }
    }
    
    if (!harmonyHubToken)
    {
        @throw [NSException exceptionWithName: FSCExceptionHarmonyHubConnection
                                       reason: [NSString stringWithFormat:
                                                @"Unexpected pairing response from HUB: %@",
                                                OAAttributesAndValuesString]
                                     userInfo: nil];
    }

    return harmonyHubToken;
}

- (void) sendIQCmd: (XMPPIQ *) IQCmd
andWaitForValidResponse: (BOOL (^)(NSXMLElement * OAResponse))responseValidationBlock;
{
    NSLog(@"%@", NSStringFromSelector(_cmd));
    
    validOAResponseReceived = NO;
    
    [self setOAResponseValidationBlock: responseValidationBlock];
    
    [[self xmppStream] sendElement: IQCmd];
    
    dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        
        while (!validOAResponseReceived)
        {
            [NSThread sleepForTimeInterval: 0.25];
        }
    });
    
    [self setOAResponseValidationBlock: nil];
}

#pragma mark - Operations

- (void) disconnect
{
    NSLog(@"%@", NSStringFromSelector(_cmd));
    
    [[self xmppStream] disconnect];
    
    dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        
        while (isXMPPConnected)
        {
            [NSThread sleepForTimeInterval: 0.25];
        }
    });
}

#pragma mark XMPPStream Delegate

- (void) xmppStreamDidConnect: (XMPPStream *) sender
{
    NSLog(@"%@", NSStringFromSelector(_cmd));
    
    isXMPPConnected = YES;
}

- (void) xmppStreamDidAuthenticate: (XMPPStream *) sender
{
    NSLog(@"%@", NSStringFromSelector(_cmd));
    
    isXMPPAuthenticated = YES;
}

- (void) xmppStream:(XMPPStream *) sender
 didNotAuthenticate: (NSXMLElement *) error
{
    NSLog(@"%@ %@", NSStringFromSelector(_cmd), error);
    
    didXMPPFailAuthentication = YES;
    
    [self setAuthenticationFailureError: error];
}

- (BOOL) xmppStream: (XMPPStream *) sender
       didReceiveIQ: (XMPPIQ *) iq
{
    NSLog(@"%@: %@", NSStringFromSelector(_cmd), iq);
    
    NSXMLElement * oaResponse = [iq elementForName: @"oa"];
    
    if (oaResponse &&
        (![self OAResponseValidationBlock] ||
         [self OAResponseValidationBlock](oaResponse)))
    {
        validOAResponseReceived = YES;
    }
    
    return NO;
}

- (void) xmppStream: (XMPPStream *) sender
    didReceiveError: (id) error
{
    NSLog(@"%@", NSStringFromSelector(_cmd));
}

- (void) xmppStreamDidDisconnect: (XMPPStream *) sender
                       withError: (NSError *) error
{
    NSLog(@"%@ %@", NSStringFromSelector(_cmd), [error localizedDescription]);
    
    if (!isXMPPConnected)
    {
        didDisconnectWhileConnecting = YES;
    }
    
    isXMPPConnected = NO;
    isXMPPAuthenticated = NO;
}

@end
