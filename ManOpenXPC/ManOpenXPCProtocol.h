//
//  ManOpenXPCProtocol.h
//  ManOpenXPC
//
//  Created by C.W. Betts on 8/21/17.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The protocol that this service will vend as its API. This header file will also need to be visible to the process hosting the service.
@protocol ManOpenXPCProtocol

- (void)openName:(bycopy NSString *)name section:(bycopy nullable NSString *)section manPath:(bycopy nullable NSString *)manPath forceToFront:(BOOL)force withReply:(void (^)(BOOL))reply;
- (void)openApropos:(bycopy NSString *)apropos manPath:(bycopy nullable NSString *)manPath forceToFront:(BOOL)force withReply:(void (^)(BOOL))reply;
- (void)openFile:(bycopy NSString *)filename forceToFront:(BOOL)force withReply:(void (^)(BOOL))reply;
- (void)setManOpenEndpoint:(NSXPCListenerEndpoint*)endPoint;
- (void)getManOpenEndpointWithReply:(void (^)(NSXPCListenerEndpoint * _Nullable))reply;

@end

NS_ASSUME_NONNULL_END

/*
 To use the service from an application or other process, use NSXPCConnection to establish a connection to the service by doing something like this:

     _connectionToService = [[NSXPCConnection alloc] initWithServiceName:@"com.github.maddthesane.ManOpenXPC"];
     _connectionToService.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(ManOpenXPCProtocol)];
     [_connectionToService resume];

Once you have a connection to the service, you can use it like this:

     [[_connectionToService remoteObjectProxy] upperCaseString:@"hello" withReply:^(NSString *aString) {
         // We have received a response. Update our text field, but do it on the main thread.
         NSLog(@"Result string was: %@", aString);
     }];

 And, when you are finished with the service, clean up the connection like this:

     [_connectionToService invalidate];
*/
