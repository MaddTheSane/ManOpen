//
//  ManOpenXPC.h
//  ManOpenXPC
//
//  Created by C.W. Betts on 8/21/17.
//

#import <Foundation/Foundation.h>
#import "ManOpenXPCProtocol.h"

// This object implements the protocol which we have defined. It provides the actual behavior for the service. It is 'exported' by the service to make it available to the process hosting the service over an NSXPCConnection.
@interface ManOpenXPC : NSObject <ManOpenXPCProtocol>
@end
