
#import <Foundation/Foundation.h>
#import <AppKit/NSWorkspace.h>
#include <stdlib.h>
#import "ManOpenProtocol.h"
#import "ManOpenXPCProtocol.h"


static NSString *MakeNSStringFromPath(const char *filename) NS_RETURNS_RETAINED;
NSString *MakeNSStringFromPath(const char *filename)
{
    return [[NSFileManager defaultManager] stringWithFileSystemRepresentation:filename length:strlen(filename)];
}

static NSString *MakeAbsolutePath(const char *filename) NS_RETURNS_RETAINED;
NSString *MakeAbsolutePath(const char *filename)
{
    NSString *currFile = MakeNSStringFromPath(filename);
    
    if (!currFile.absolutePath) {
        NSURL *theURL = [NSURL fileURLWithPath:currFile];
        theURL = [theURL absoluteURL];
        currFile = [theURL path];
    }
    
    return currFile;
}

static inline void usage(const char *progname)
{
    fprintf(stderr, "%s: [-bk] [-M path] [-f file] [section] [name ...]\n", progname);
}

int main (int argc, char * const *argv)
{
    @autoreleasepool {
        NSString          *manPath = nil;
        NSString          *section = nil;
        BOOL              aproposMode = NO;
        BOOL              forceToFront = YES;
        NSInteger         argIndex;
        char              c;
        NSXPCConnection   *_connectionToService;
        NSMutableArray<NSString*>   *files = [[NSMutableArray alloc] init];

        while ((c = getopt(argc,argv,"hbm:M:f:kaCcw")) != EOF)
        {
            switch(c)
            {
                case 'm':
                case 'M':
                    manPath = MakeNSStringFromPath(optarg);
                    break;
                case 'f':
                    [files addObject:MakeAbsolutePath(optarg)];
                    break;
                case 'b':
                    forceToFront = NO;
                    break;
                case 'k':
                    aproposMode = YES;
                    break;
                case 'a':
                case 'C':
                case 'c':
                case 'w':
                    // MacOS X man(1) options; no-op here.
                    break;
                case 'h':
                case '?':
                default:
                    usage(argv[0]);
                    return 0;
            }
        }
        
        if (optind >= argc && [files count] <= 0)
        {
            usage(argv[0]);
            //exit(0);
            return 0;
        }
        
        if (optind < argc && !aproposMode)
        {
            NSString *tmp = @(argv[optind]);
            
            if (isdigit(argv[optind][0])          ||
                /* These are configurable in /etc/man.conf; these are just the default strings.  Hm, they are invalid as of Panther. */
                [tmp isEqualToString:@"system"]   ||
                [tmp isEqualToString:@"commands"] ||
                [tmp isEqualToString:@"syscalls"] ||
                [tmp isEqualToString:@"libc"]     ||
                [tmp isEqualToString:@"special"]  ||
                [tmp isEqualToString:@"files"]    ||
                [tmp isEqualToString:@"games"]    ||
                [tmp isEqualToString:@"miscellaneous"] ||
                [tmp isEqualToString:@"misc"]     ||
                [tmp isEqualToString:@"admin"]    ||
                [tmp isEqualToString:@"n"]        || // Tcl pages on >= Panther
                [tmp isEqualToString:@"local"])
            {
                section = tmp;
                optind++;
            }
        }
        
        if (optind >= argc)
        {
            if ([section length] > 0)
            {
                /* MacOS X assumes it's a man page name */
                section = nil;
                optind--;
            }
            
            if (optind >= argc && [files count] <= 0)
            {
                return 0;
            }
        }
        
        //initWithListenerEndpoint
        _connectionToService = [[NSXPCConnection alloc] initWithServiceName:@"com.github.maddthesane.ManOpenXPC"];
        _connectionToService.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(ManOpenXPCProtocol)];
        [_connectionToService resume];
        
        [_connectionToService.remoteObjectProxy getManOpenEndpointWithReply:^(NSXPCListenerEndpoint * _Nullable endPt) {
            if (!endPt) {
                return;
            }
            NSXPCConnection *conn2 = [[NSXPCConnection alloc] initWithListenerEndpoint:endPt];
            conn2.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(ManOpen)];
        }];

        for (NSString *fileName in files)
        {
            [[_connectionToService remoteObjectProxy] openFile:fileName forceToFront:forceToFront withReply:^(BOOL success) {
                //Do nothing for now
            }];
        }
        
        if (manPath == nil && getenv("MANPATH") != NULL)
            manPath = MakeNSStringFromPath(getenv("MANPATH"));
        
        for (argIndex = optind; argIndex < argc; argIndex++)
        {
            NSString *currFile = MakeNSStringFromPath(argv[argIndex]);
            if (aproposMode) {
                [[_connectionToService remoteObjectProxy] openApropos:currFile manPath:manPath forceToFront:forceToFront withReply:^(BOOL success) {
                    //Do nothing for now
                }];
            } else {
                [[_connectionToService remoteObjectProxy] openName:currFile section:section manPath:manPath forceToFront:forceToFront withReply:^(BOOL success) {
                    //Do nothing for now
                }];
            }
        }
        
        [_connectionToService invalidate];
        return 0;
    }
}
