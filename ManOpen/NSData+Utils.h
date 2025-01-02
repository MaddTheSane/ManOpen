#import <Foundation/Foundation.h>

@interface NSData (Utils)

/*!
 * Checks the data to see if it looks like the start of an nroff file.
 * Derived from logic in FreeBSD's <b>file(1)</b> command.
 */
@property (getter=isNroffData, readonly) BOOL nroffData;

@end

@interface NSFileHandle (Utils)

/*!
 * The <code>-[NSFileHandle readDataToEndOfFile]</code> method does not deal with \c EINTR errors, which in most
 * cases is fine, but sometimes not when running under a debugger.  So... this is more to help
 * folks working on the code, rather the users ;-)
 */
- (nullable NSData *)readDataToEndOfFileIgnoreInterruptAndReturnError:(NSError * __nullable * __nullable)error;

@end
