
/*
 * Protocol for the 'openman' command line util to communicate with us
 * through
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(ManOpenProtocol)
@protocol ManOpen <NSObject>

- (oneway void)openName:(bycopy NSString *)name section:(bycopy nullable NSString *)section manPath:(bycopy nullable NSString *)manPath forceToFront:(BOOL)force;
- (oneway void)openApropos:(bycopy NSString *)apropos manPath:(bycopy nullable NSString *)manPath forceToFront:(BOOL)force;
- (oneway void)openFile:(bycopy NSString *)filename forceToFront:(BOOL)force;

@end

NS_ASSUME_NONNULL_END
