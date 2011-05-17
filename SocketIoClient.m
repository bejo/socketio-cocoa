//
//  SocketIoClient.m
//  SocketIoCocoa
//
//  Created by Fred Potter on 11/11/10.
//  Copyright 2010 Fred Potter. All rights reserved.
//

#import "SocketIoClient.h"
#import "WebSocket.h"

#define WEBSOCKET_SCHEME        @"ws"
#define WEBSOCKET_SECURE_SCHEME @"wss"

@interface SocketIoClient (FP_Private) <WebSocketDelegate>
- (void)log:(NSString *)message;
- (NSString *)encode:(NSArray *)messages;
- (void)onDisconnect;
- (void)notifyMessagesSent:(NSArray *)messages;
- (void)callDelegateWithSelector:(SEL)selector andObjects:(id)firstObject, ...;
@end

@implementation SocketIoClient

@synthesize sessionId = _sessionId, delegate = _delegate, connectTimeout = _connectTimeout, 
            tryAgainOnConnectTimeout = _tryAgainOnConnectTimeout, heartbeatTimeout = _heartbeatTimeout,
            isConnecting = _isConnecting, isConnected = _isConnected, isSecure = _isSecure, 
            tryAgainOnHeartbeatTimeout = _tryAgainOnHeartbeatTimeout;
// Selectors
@synthesize didConnectSelector = _didConnectSelector, didDisconnectSelector = _didDisconnectSelector,
            didReceiveMessageSelector = _didReceiveMessageSelector, didSendMessageSelector = _didSendMessageSelector,
            didFailSelector = _didFailSelector;

- (id)initWithHost:(NSString *)host resource:(NSString *)resourcePath port:(int)port {
  if ((self = [super init])) {
    _host = [host retain];
    if (resourcePath == nil) {
      _resourcePath = @"socket.io/websocket";
    } else {
      _resourcePath = [resourcePath retain];
    }
    _port = port;
    _queue = [[NSMutableArray array] retain];
    
    _connectTimeout = 5.0;
    _tryAgainOnConnectTimeout = YES;
    _tryAgainOnHeartbeatTimeout = YES;
    _heartbeatTimeout = 15.0;
    
    // Selectors
    self.didConnectSelector = @selector(socketIoClientDidConnect:);
    self.didDisconnectSelector = @selector(socketIoClientDidDisconnect:);
    self.didReceiveMessageSelector = @selector(socketIoClient:didReceiveMessage:isJSON:);
    self.didSendMessageSelector = @selector(socketIoClient:didSendMessage:isJSON:);
    self.didFailSelector = @selector(socketIoClient:didFailWithError:);
  }
  return self;
}

- (id)initWithSecureHost:(NSString *)host resource:(NSString *)resourcePath port:(int)port {
  if ((self = [self initWithHost:host resource:resourcePath port:port])) {
    _isSecure = YES;
  }
  return self;
}

- (void)dealloc {
  [_host release];
  [_resourcePath release];
  [_queue release];
  [_webSocket release];
  self.sessionId = nil;
  
  [super dealloc];
}

- (void)checkIfConnected {
  if (!_isConnected) {
    [self disconnect];
    
    if (_tryAgainOnConnectTimeout) {
      [self connect];
    }
  }
}

- (void)connect {
  if (!_isConnected) {
    
    if (_isConnecting) {
      [self disconnect];
    }
    
    _isConnecting = YES;
    
    NSString *webSocketScheme = WEBSOCKET_SCHEME;
    if (_isSecure) {
      webSocketScheme = WEBSOCKET_SECURE_SCHEME;
    }
    
    NSString *URL = [NSString stringWithFormat:@"%@://%@:%d/%@",
                     webSocketScheme,
                     _host,
                     _port,
                     _resourcePath];
    
    [self log:[NSString stringWithFormat:@"Opening %@", URL]];
    
    [_webSocket release];
    _webSocket = nil;
    
    _webSocket = [[WebSocket alloc] initWithURLString:URL delegate:self];
    
    [_webSocket open];
    
    if (_connectTimeout > 0.0) {
      [self performSelector:@selector(checkIfConnected) withObject:nil afterDelay:_connectTimeout];
    }
  }
}

- (void)disconnect {
  [self log:@"Disconnect"];
  [_webSocket close];
  
  // invalidate any timers that were previously set to attempt to reconnect
  [_timeout invalidate];
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkIfConnected) object:nil];
  
  [self onDisconnect];
}

- (void)send:(NSString *)data isJSON:(BOOL)isJSON {
  [self log:[NSString stringWithFormat:@"Sending %@:\n%@", isJSON ? @"JSON" : @"TEXT", data]];
  
  NSDictionary *message = [NSDictionary dictionaryWithObjectsAndKeys:
                           data,
                           @"data",
                           isJSON ? @"json" : @"text",
                           @"type",
                           nil];
  
  if (!_isConnected) {
    [self queueOfflineMessage:message];
  } else {
    NSArray *messages = [NSArray arrayWithObject:message];

    [_webSocket send:[self encode:messages]];
    
    [self notifyMessagesSent:messages];
  }
}

- (void)queueOfflineMessage:(NSDictionary *)message {
  [_queue addObject:message];
}

#pragma mark SocketIO Related Protocol

- (void)notifyMessagesSent:(NSArray *)messages {
  for (NSDictionary *message in messages) {
    NSString *data = [message objectForKey:@"data"];
    NSString *type = [message objectForKey:@"type"];
    
    [self callDelegateWithSelector:self.didSendMessageSelector andObjects:self, data, [NSNumber numberWithBool:[type isEqualToString:@"json"]], nil];
  }
}

- (NSString *)encode:(NSArray *)messages {
  NSMutableString *buffer = [[[NSMutableString alloc] initWithCapacity:0] autorelease];
  
  for (NSDictionary *message in messages) {
    
    NSString *data = [message objectForKey:@"data"];
    NSString *type = [message objectForKey:@"type"];
    
    NSString *dataWithType = nil;
    
    if ([type isEqualToString:@"json"]) {
      dataWithType = [NSString stringWithFormat:@"~j~%@", data];
    } else {
      dataWithType = data;
    }
    
    [buffer appendString:@"~m~"];
    [buffer appendFormat:@"%d", [dataWithType length]];
    [buffer appendString:@"~m~"];
    [buffer appendString:dataWithType];
  }

  return buffer;
}

- (NSArray *)decode:(NSString *)data {
  NSMutableArray *messages = [NSMutableArray array];
  
  int i = 0;
  int len = (int)[data length];
  while (i < len) {
    if ([[data substringWithRange:NSMakeRange(i, 3)] isEqualToString:@"~m~"]) {
      
      i += 3;
      
      int lengthOfLengthString = 0;
      
      for (int j = i; j < len; j++) {
        unichar c = [data characterAtIndex:j];
        
        if ('0' <= c && c <= '9') {
          lengthOfLengthString++;
        } else {
          break;
        }
      }
      
      int messageLength = [[data substringWithRange:NSMakeRange(i, lengthOfLengthString)] intValue];
      i += lengthOfLengthString;
      
      // skip past the next frame
      i += 3;
      
      NSString *message = [data substringWithRange:NSMakeRange(i, messageLength)];
      i += messageLength;
      
      [messages addObject:message];
      
    } else {
      // No frame marker
      break;
    }
  }
  
  return messages;
}

- (void)onTimeout {
  [self log:@"Timed out waiting for heartbeat."];
  [self onDisconnect];
  
  if (_tryAgainOnHeartbeatTimeout) [self checkIfConnected];
}

- (void)setTimeout {  
  if (_timeout != nil) {
    [_timeout invalidate];
    [_timeout release];
    _timeout = nil;
  }
  
  _timeout = [[NSTimer scheduledTimerWithTimeInterval:_heartbeatTimeout
                                               target:self 
                                             selector:@selector(onTimeout) 
                                             userInfo:nil 
                                              repeats:NO] retain];
  
}

- (void)onHeartbeat:(NSString *)heartbeat {
  [self send:[NSString stringWithFormat:@"~h~%@", heartbeat] isJSON:NO];
}

- (void)doQueue {
  if ([_queue count] > 0) {
    [_webSocket send:[self encode:_queue]];
    
    [self notifyMessagesSent:_queue];
    
    [_queue removeAllObjects];
  }
}

- (void)onConnect {
  _isConnected = YES;
  _isConnecting = NO;
  
  [self doQueue];
  
  [self callDelegateWithSelector:self.didConnectSelector andObjects:self, nil];
  
  [self setTimeout];
}

- (void)onDisconnect {
  BOOL wasConnected = _isConnected;
  
  _isConnected = NO;
  _isConnecting = NO;
  self.sessionId = nil;
  
  [_queue removeAllObjects];
  
  if (wasConnected) {
    [self callDelegateWithSelector:self.didDisconnectSelector andObjects:self, nil];
  }
}

- (void)onMessage:(NSString *)message {
  [self log:[NSString stringWithFormat:@"Message: %@", message]];
  
  if (self.sessionId == nil) {
    self.sessionId = message;
    [self onConnect];
  } else if ([[message substringWithRange:NSMakeRange(0, 3)] isEqualToString:@"~h~"]) {
    [self onHeartbeat:[message substringFromIndex:3]];
  } else if ([[message substringWithRange:NSMakeRange(0, 3)] isEqualToString:@"~j~"]) {
    [self callDelegateWithSelector:self.didReceiveMessageSelector andObjects:self, [message substringFromIndex:3], [NSNumber numberWithBool:YES], nil];
  } else {
    [self callDelegateWithSelector:self.didReceiveMessageSelector andObjects:self, message, [NSNumber numberWithBool:NO], nil];
  }
}

- (void)onData:(NSString *)data {
  [self setTimeout];
  
  NSArray *messages = [self decode:data];
  
  for (NSString *message in messages) {
    [self onMessage:message];
  }
}

- (void)callDelegateWithSelector:(SEL)selector andObjects:(id)firstObject, ... {
    if ([self.delegate respondsToSelector:selector]) {
        // get method signature and create an invocation
		NSMethodSignature *signature = [(NSObject *)self.delegate methodSignatureForSelector:selector];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        [invocation setSelector:selector];
        [invocation setTarget:self.delegate];
        
        // add arguments
        va_list args;
        va_start(args, firstObject);
        id arg = firstObject;
        int i = 2;
        while(arg) {
            if (strcmp([signature getArgumentTypeAtIndex:i], "c") == 0) {
                int argc = [arg intValue];
                [invocation setArgument:&argc atIndex:i++];
            } else {
                [invocation setArgument:&arg atIndex:i++];
            }
            arg = va_arg(args, id); // get next argument from list
        } 
        va_end(args);
        
        // send a message to delegate
        [invocation invokeWithTarget:self.delegate];
    }
}

#pragma mark WebSocket Delegate Methods

- (void)webSocket:(WebSocket *)ws didFailWithError:(NSError *)error {
  [self log:[NSString stringWithFormat:@"Connection failed with error: %@", [error localizedDescription]]];
  [self callDelegateWithSelector:self.didFailSelector andObjects:self, error, nil];
}

- (void)webSocketDidClose:(WebSocket*)webSocket {
  [self log:[NSString stringWithFormat:@"Connection closed."]];
  [self onDisconnect];
}

- (void)webSocketDidOpen:(WebSocket *)ws {
  [self log:[NSString stringWithFormat:@"Connection opened."]];
  [self onConnect];
}

- (void)webSocket:(WebSocket *)ws didReceiveMessage:(NSString*)message {  
  [self log:[NSString stringWithFormat:@"Received %@", message]];
  [self onData:message];
}

- (void)webSocketDidSecure:(WebSocket*)ws {
  [self log:[NSString stringWithFormat:@"Websocket connection secured."]];
  [self onConnect];
}

- (void)log:(NSString *)message {
  //NSLog(@"%@", message);
}

@end
