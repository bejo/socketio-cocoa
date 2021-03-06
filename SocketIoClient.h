//
//  SocketIoClient.h
//  SocketIoCocoa
//
//  Created by Fred Potter on 11/11/10.
//  Copyright 2010 Fred Potter. All rights reserved.
//

#import <Foundation/Foundation.h>

@class WebSocket;
@protocol SocketIoClientDelegate;

@interface SocketIoClient : NSObject {
  NSString *_host;
  NSString *_resourcePath;
  NSInteger _port;
  BOOL _isSecure;
  WebSocket *_webSocket;
  
  NSTimeInterval _connectTimeout;
  BOOL _tryAgainOnConnectTimeout;
  BOOL _tryAgainOnHeartbeatTimeout;
  
  NSTimeInterval _heartbeatTimeout;
  
  NSTimer *_timeout;

  BOOL _isConnected;
  BOOL _isConnecting;
  NSString *_sessionId;
  
  id<SocketIoClientDelegate> _delegate;
  // Selectors
  SEL _didStartSelector;
  SEL _didDisconnectSelector;
  SEL _didReceiveMessageSelector;
  SEL _didSendMessageSelector;
  SEL _didFailSelector;
  
  NSMutableArray *_queue;
}

@property (nonatomic, readonly) BOOL isSecure;

@property (nonatomic, retain) NSString *sessionId;
@property (nonatomic, readonly) BOOL isConnected;
@property (nonatomic, readonly) BOOL isConnecting;

@property (nonatomic, assign) id<SocketIoClientDelegate> delegate;

@property (nonatomic, assign) NSTimeInterval connectTimeout;
@property (nonatomic, assign) BOOL tryAgainOnConnectTimeout;
@property (nonatomic, assign) BOOL tryAgainOnHeartbeatTimeout;

@property (nonatomic, assign) NSTimeInterval heartbeatTimeout;

// Selectors
@property (assign) SEL didConnectSelector;
@property (assign) SEL didDisconnectSelector;
@property (assign) SEL didReceiveMessageSelector;
@property (assign) SEL didSendMessageSelector;
@property (assign) SEL didFailSelector;

- (id)initWithHost:(NSString *)host resource:(NSString *)resourcePath port:(int)port;
- (id)initWithSecureHost:(NSString *)host resource:(NSString *)resourcePath port:(int)port;

- (void)connect;
- (void)disconnect;

/**
 * Rather than coupling this with any specific JSON library, you always
 * pass in a string (either _the_ string, or the the JSON-encoded version
 * of your object), and indicate whether or not you're passing a JSON object.
 */
- (void)send:(NSString *)data isJSON:(BOOL)isJSON;

/**
 * Adds the NSDictionary representation of a message to the offline queue. 
 * This allows subclass implementations to have more granular control over what
 * is happening to their writes that happen without a connection instead of 
 * only keeping an in memory copy that gets erased on connection. This also allows
 * messages to be queued directly into an offline data structure.
 */
- (void)queueOfflineMessage:(NSDictionary *)message;

@end

@protocol SocketIoClientDelegate <NSObject>

/**
 * Message is always returned as a string, even when the message was meant to come
 * in as a JSON object.  Decoding the JSON is left as an exercise for the receiver.
 */
- (void)socketIoClient:(SocketIoClient *)client didReceiveMessage:(NSString *)message isJSON:(BOOL)isJSON;

- (void)socketIoClientDidConnect:(SocketIoClient *)client;
- (void)socketIoClientDidDisconnect:(SocketIoClient *)client;

@optional

- (void)socketIoClient:(SocketIoClient *)client didSendMessage:(NSString *)message isJSON:(BOOL)isJSON;
- (void)socketIoClient:(SocketIoClient *)client didFailWithError:(NSError *)error;

@end
