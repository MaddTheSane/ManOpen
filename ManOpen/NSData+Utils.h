#import <Foundation/Foundation.h>

@interface NSData (Utils)

/*!
 * Checks the data to see if it looks like the start of an nroff file.
 * Derived from logic in FreeBSD's **file(1)** command.
 */
@property (getter=isNroffData, readonly) BOOL nroffData;

@end

@interface NSFileHandle (Utils)

/*!
 * The `-[NSFileHandle readDataToEndOfFile]` method does not deal with `EINTR` errors, which in most
 * cases is fine, but sometimes not when running under a debugger.  So... this is more to help
 * folks working on the code, rather the users ;-)
 */
- (nullable NSData *)readDataToEndOfFileIgnoreInterruptAndReturnError:(NSError * __nullable * __nullable)error;

@end
