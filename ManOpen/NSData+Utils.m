
#import "NSData+Utils.h"
#import <Foundation/NSException.h>
#include <stdlib.h>
#include <sys/types.h>
#include <errno.h>
#include <assert.h>
#include <alloca.h>

@implementation NSData (Utils)

/*
 * Checks the data to see if it looks like the start of an nroff file.
 * Derived from logic in FreeBSD's file(1) command.
 */
- (BOOL)isNroffData
{
    const char *bytes = [self bytes];
    const char *ptr = bytes;

#define MATCH(str) (strncmp(ptr, str, strlen(str)) == 0)

    while (isspace(*ptr)) ptr++;

    /* Some X11R6 pages have a weird #pragma line at the start */
    if (MATCH("#pragma")) {
        const char *nextline = strchr(ptr, '\n');
        if (nextline != NULL) {
            ptr = nextline;
            while (isspace(*ptr)) ptr++;
        }
    }
            
    /* If not at the beginning of a line, bail. */
    if (!(ptr == bytes || *(ptr-1) == '\n' || *(ptr-1) == '\r')) return NO;


    /* Try for some common prefixes: .\", '\", '.\", \", and .\<sp> */
    if (MATCH(".\\\""))         return YES;
    if (MATCH("'\\\""))         return YES;
    if (MATCH("'.\\\""))        return YES;
    if (MATCH("\\\""))          return YES;
    if (MATCH(".\\ "))          return YES;
    if (MATCH("\\.\""))         return YES;  // found this on a joke man page
    if (MATCH("\\\n.\\\" "))    return YES;  // found this on macptopbm man page

    /*
     * Now check for .[letter][letter], and .\" again.  In either case,
     * allow spaces after the '.'
     */
    if (*ptr == '.') {
        /* skip over '.' and whitespace */
        ptr++;
        while (isspace(*ptr)) ptr++;

        if (isalnum(ptr[0]) && isalnum(ptr[1])) return YES;
        if (ptr[0] == '\\'  && ptr[1] == '"')   return YES;
    }

    return NO;
}

@end

@implementation NSFileHandle (Utils)

/*
 * The NSData -readDataToEndOfFile method does not deal with EINTR errors, which in most
 * cases is fine, but sometimes not when running under a debugger.  So... this is more to help
 * folks working on the code, rather the users ;-)
 */
- (NSData *)readDataToEndOfFileIgnoreInterruptAndReturnError:(NSError *__autoreleasing  _Nullable *)error
{
    const int fd = [self fileDescriptor];
    static const size_t allocated = 8192;
    unsigned char *bytes = alloca(allocated);
    ssize_t bytesRead;
    NSMutableData *ourData = [[NSMutableData alloc] initWithCapacity:allocated*4];
    
    do {
        do {
            bytesRead = read(fd, bytes, allocated);
            if (bytesRead > 0) {
                [ourData appendBytes:bytes length:bytesRead];
            }
        } while (bytesRead < 0 && ((errno == EINTR) || (errno == EAGAIN) || (errno == EWOULDBLOCK)));
    } while (bytesRead > 0);
    
    if (bytesRead < 0) {
        if (error) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        }
        return nil;
    }

    return [ourData copy];
}

@end
