//
//  ManOpenXPC.m
//  ManOpenXPC
//
//  Created by C.W. Betts on 8/21/17.
//

#import "ManOpenXPC.h"
#import "ManOpenProtocol.h"

@implementation ManOpenXPC

// This implements the example protocol. Replace the body of this class with the implementation of this service's protocol.
- (void)upperCaseString:(NSString *)aString withReply:(void (^)(NSString *))reply {
    NSString *response = [aString uppercaseString];
    reply(response);
}

@end
