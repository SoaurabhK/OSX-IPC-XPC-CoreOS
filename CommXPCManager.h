//
//  CommXPCManager.h
//  FlightFinder
//
//  Created by Soaurabh Kakkar on 10/07/16.
//  Copyright © 2016 Apple, Inc. All rights reserved.
//
#import <XPCKit/XPCExtensions.h>
@class CommXPCManager;

typedef NS_ENUM(NSUInteger, CommXPCErrorType) {
    
    CommXPCErrorInvalid     = 1,
    CommXPCErrorInterrupted = 2,
    CommXPCErrorTermination = 3
};

typedef void (^XPCErrorHandler)(CommXPCManager *mgrXPC, CommXPCErrorType errorType, NSError *error);
typedef void (^XPCMessageHandler)(CommXPCManager *mgrXPC, xpc_object_t event, NSDictionary *message);
typedef void (^XPCConnectionHandler)(CommXPCManager *peerConnection);

@interface CommXPCManager : NSObject

@property (readwrite, copy, nonatomic) XPCErrorHandler errorHandler;
@property (readwrite, copy, nonatomic) XPCMessageHandler messageHandler;
@property (readwrite, copy, nonatomic) XPCConnectionHandler connectionHandler;

@property (readonly, nonatomic) BOOL clientConnection;
@property (readonly, nonatomic) BOOL serverConnection;
@property (readonly, nonatomic) BOOL peerConnection;

@property (readonly, nonatomic) __attribute__((NSObject)) xpc_connection_t connection;

@property (readonly, strong, nonatomic) NSString *connectionName;
@property (readonly, strong, nonatomic) NSNumber *connectionEUID;
@property (readonly, strong, nonatomic) NSNumber *connectionEGID;
@property (readonly, strong, nonatomic) NSNumber *connectionProcessID;
@property (readonly, strong, nonatomic) NSString *connectionAuditSessionID;

- (id) initWithConnection:(xpc_connection_t)aConnection;
- (id) initAsClientWithBundleID:(NSString *)bundleID;
- (id) initAsServer;

- (void) suspendConnection;
- (void) resumeConnection;
- (void) cancelConnection;

- (void) sendMessage:(NSDictionary *)dict;
- (void) sendMessage:(NSDictionary *)dict reply:(void (^)(NSDictionary *replyDict, NSError *error))reply;
+ (void) sendReply:(NSDictionary *)dict forEvent:(xpc_object_t)event;

@end

