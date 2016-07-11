//
//  CommXPCManager.m
//  FlightFinder
//
//  Created by Soaurabh Kakkar on 10/07/16.
//  Copyright © 2016 Apple, Inc. All rights reserved.
//

#import "CommXPCManager.h"

@implementation NSError (CategoryXPCMessage)
+ (NSError *) errorFromXObject:(xpc_object_t)xObject {
    
    char *description = xpc_copy_description( xObject );
    NSError *xpcError = [NSError errorWithDomain:NSPOSIXErrorDomain code:EINVAL userInfo:@{
                                                                                           NSLocalizedDescriptionKey:
                                                                                               [NSString stringWithCString:description encoding:[NSString defaultCStringEncoding]] }];
    free( description );
    return xpcError;
}
@end


@interface CommXPCManager ()
@property (readwrite, nonatomic) BOOL clientConnection;
@property (readwrite, nonatomic) BOOL serverConnection;
@property (readwrite, nonatomic) BOOL peerConnection;
@property (readwrite, strong, nonatomic) __attribute__((NSObject)) dispatch_queue_t dispatchQueue;
@end

@implementation CommXPCManager

@synthesize clientConnection, serverConnection, peerConnection;
@synthesize errorHandler, messageHandler, connectionHandler;
@synthesize connection    = _connection;
@synthesize dispatchQueue = _dispatchQueue;

#pragma mark - Message Methods:

- (void) sendMessage:(NSDictionary *)dict {
    
    dispatch_async( self.dispatchQueue, ^{
        
        xpc_object_t message = [dict newXPCObject];
        xpc_connection_send_message( _connection, message );
    });
}

- (void) sendMessage:(NSDictionary *)dict reply:(void (^)(NSDictionary *replyDict, NSError *error))reply {
    
    dispatch_async( self.dispatchQueue, ^{
        
        xpc_object_t message = [dict newXPCObject];
        xpc_connection_send_message_with_reply( _connection, message, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(xpc_object_t object) {
            
            xpc_type_t type = xpc_get_type( object );
            
            if ( type == XPC_TYPE_ERROR ) {
                
                /*! @discussion Reply: XPC Error */
                reply( [NSDictionary dictionary], [NSError errorFromXObject:object] );
                
            } else if ( type == XPC_TYPE_DICTIONARY ) {
                
                /*! @discussion Reply: XPC Dictionary */
                reply( [NSDictionary dictionaryWithContentsOfXPCObject:object], nil );
            }
        });
    });
}

+ (void) sendReply:(NSDictionary *)dict forEvent:(xpc_object_t)event {
//    xpc_object_t message = [dict xObjectReply:event];
//    xpc_connection_t replyConnection = xpc_dictionary_get_remote_connection( message );
//    xpc_connection_send_message( replyConnection, message );
}

#pragma mark - Connection Methods:

- (void) suspendConnection {
    
    dispatch_async(self.dispatchQueue, ^{ xpc_connection_suspend( _connection ); });
}

- (void) resumeConnection {
    
    dispatch_async(self.dispatchQueue, ^{ xpc_connection_resume(_connection); });
}

- (void) cancelConnection {
    
    dispatch_async(self.dispatchQueue, ^{ xpc_connection_cancel(_connection); });
}

#pragma mark - Accessor Overrides:

- (void) setDispatchQueue:(dispatch_queue_t)queue {
    
    if ( queue ) dispatch_retain( queue );
    if ( _dispatchQueue ) dispatch_release( _dispatchQueue );
    _dispatchQueue = queue;
    
    xpc_connection_set_target_queue( self.connection, self.dispatchQueue );
}

#pragma mark - Getter Overrides:

- (NSString *) connectionName {
    
    __block char* name = NULL;
    dispatch_sync(self.dispatchQueue, ^{ name = (char*)xpc_connection_get_name( _connection ); });
    
    if(!name) return nil;
    return [NSString stringWithCString:name encoding:[NSString defaultCStringEncoding]];
}

- (NSNumber *) connectionEUID {
    
    __block uid_t uid = 0;
    dispatch_sync(self.dispatchQueue, ^{ uid = xpc_connection_get_euid( _connection ); });
    return [NSNumber numberWithUnsignedInt:uid];
}

- (NSNumber *) connectionEGID {
    
    __block gid_t egid = 0;
    dispatch_sync(self.dispatchQueue, ^{ egid = xpc_connection_get_egid( _connection ); });
    return [NSNumber numberWithUnsignedInt:egid];
}

- (NSNumber *) connectionProcessID {
    
    __block pid_t pid = 0;
    dispatch_sync(self.dispatchQueue, ^{ pid = xpc_connection_get_pid( _connection ); });
    return [NSNumber numberWithUnsignedInt:pid];
}

- (NSNumber *) connectionAuditSessionID{
    
    __block au_asid_t auasid = 0;
    dispatch_sync(self.dispatchQueue, ^{ auasid = xpc_connection_get_asid( _connection ); });
    return [NSNumber numberWithUnsignedInt:auasid];
}

#pragma mark - Setup Methods:

- (void) setupConnectionHandler:(xpc_connection_t)conn {
    
    __block CommXPCManager *this = self;
    
    xpc_connection_set_event_handler( conn, ^(xpc_object_t object) {
        
        xpc_type_t type = xpc_get_type( object );
        
        if ( type == XPC_TYPE_ERROR ) {
            
            /*! @discussion Client | Peer: XPC Error */
            
            NSError *xpcError = [NSError errorFromXObject:object];
            
            if ( object == XPC_ERROR_CONNECTION_INVALID ) {
                
                if ( this.errorHandler )
                    this.errorHandler( this, CommXPCErrorInvalid, xpcError );
                
            } else if ( object == XPC_ERROR_CONNECTION_INTERRUPTED ) {
                
                if ( this.errorHandler )
                    this.errorHandler( this, CommXPCErrorInterrupted, xpcError );
                
            } else if ( object == XPC_ERROR_TERMINATION_IMMINENT ) {
                
                if ( this.errorHandler )
                    this.errorHandler( this, CommXPCErrorTermination, xpcError );
            }
            
            xpcError = nil; return;
            
        } else if ( type == XPC_TYPE_CONNECTION ) {
            
            /*! @discussion XPC Server: XPC Connection */
            
            CommXPCManager *xpcPeer = [[CommXPCManager alloc] initWithConnection:object];
            
            if ( this.connectionHandler )
                this.connectionHandler( xpcPeer );
            
            xpcPeer = nil; return;
            
        } else if ( type == XPC_TYPE_DICTIONARY ) {
            
            /*! @discussion Client | Peer: XPC Dictionary */
            
            if ( this.messageHandler )
                this.messageHandler( this, object, [NSDictionary dictionaryWithContentsOfXPCObject:object] );
        }
        
    });
}

- (void) setupDispatchQueue {
    
    dispatch_queue_t queue = dispatch_queue_create( xpc_connection_get_name(_connection), 0 );
    self.dispatchQueue = queue;
    dispatch_release( queue );
}

- (void) setupConnection:(xpc_connection_t)aConnection {
    
    _connection = xpc_retain( aConnection );
    
    [self setupConnectionHandler:aConnection];
    [self setupDispatchQueue];
    [self resumeConnection];
}

#pragma mark - Initialization:

- (id) initWithConnection:(xpc_connection_t)aConnection {
    
    if ( !aConnection ) return nil;
    
    if ( (self = [super init]) ) {
        
        self.peerConnection = YES;
        [self setupConnection:aConnection];
        
    } return self;
}

- (id) initAsClientWithBundleID:(NSString *)bundleID {
    
    xpc_connection_t xpcConnection = xpc_connection_create_mach_service( [bundleID UTF8String], nil, 0 );
    
    if ( (self = [super init]) ) {
        
        self.clientConnection = YES;
        [self setupConnection:xpcConnection];
    }
    
    xpc_release( xpcConnection );
    return self;
}

- (id) initAsServer {
    
    xpc_connection_t xpcConnection = xpc_connection_create_mach_service( [[[NSBundle mainBundle] bundleIdentifier] UTF8String],
                                                                        dispatch_get_main_queue(),
                                                                        XPC_CONNECTION_MACH_SERVICE_LISTENER );
    if ( (self = [super init]) ) {
        
        self.serverConnection = YES;
        [self setupConnection:xpcConnection];
    }
    
    xpc_release( xpcConnection );
    return self;
}

@end