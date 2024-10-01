
#import <Foundation/Foundation.h>
#import <AppKit/NSWorkspace.h>
#include <stdlib.h>


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
        NSMutableArray    *files = [NSMutableArray array];
        BOOL              aproposMode = NO;
        BOOL              forceToFront = YES;
        NSInteger         argIndex;
        char              c;
        const NSInteger   maxConnectTries = 8;
        NSInteger         connectCount = 0;
        CFErrorRef        lsError = NULL;
        NSArray           *manOpenURLs;
        if (@available(macOS 12.0, *)) {
            manOpenURLs = [[NSWorkspace sharedWorkspace] URLsForApplicationsWithBundleIdentifier:@"org.clindberg.ManOpen"];
        } else {
            manOpenURLs = CFBridgingRelease(LSCopyApplicationURLsForBundleIdentifier(CFSTR("org.clindberg.ManOpen"), &lsError));
        }
        NSMutableDictionary *distributedDictionary = [[NSMutableDictionary alloc] init];
        NSMutableArray    *namesAndSections = [[NSMutableArray alloc] init];
        CFMessagePortRef  remotePort;
        SInt32            status;
        
        while ((c = getopt(argc,argv,"hbm:M:f:kaCcw")) != EOF) {
            switch(c) {
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
                    return EXIT_SUCCESS;
            }
        }
        
        if (optind >= argc && [files count] <= 0) {
            usage(argv[0]);
            //exit(0);
            return EXIT_SUCCESS;
        }
        
        if (optind < argc && !aproposMode) {
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
                [tmp isEqualToString:@"local"]) {
                section = tmp;
                optind++;
            }
        }
        
        if (optind >= argc) {
            if ([section length] > 0) {
                /* MacOS X assumes it's a man page name */
                section = nil;
                optind--;
            }
            
            if (optind >= argc && [files count] <= 0) {
                return EXIT_SUCCESS;
            }
        }
        
        // Use Launch Services to find ManOpen.
        if (!manOpenURLs) {
            fprintf(stderr, "Cannot locate ManOpen.\n");
            return EXIT_FAILURE;
        } else if (![manOpenURLs.firstObject isKindOfClass:[NSURL class]]) {
            fprintf(stderr, "Received an unknown object type from Launch Services.\n");
            return EXIT_FAILURE;
        }
        
        // Use NSWorkspace to launch ManOpen.
        if (@available(macOS 10.15, *)) {
            NSWorkspaceOpenConfiguration *configuration = [[NSWorkspaceOpenConfiguration alloc] init];
            dispatch_semaphore_t launchLock = dispatch_semaphore_create(0);
            
            configuration.activates = forceToFront;
            [[NSWorkspace sharedWorkspace] openApplicationAtURL:manOpenURLs.firstObject configuration:configuration completionHandler:^(NSRunningApplication * _Nullable app, NSError * _Nullable error) {
                if (!app)
                {
                    fprintf(stderr, "Could not launch ManOpen\n");
                    exit(EXIT_FAILURE);
                }
                dispatch_semaphore_signal(launchLock);
            }];
            dispatch_semaphore_wait(launchLock, dispatch_time(DISPATCH_TIME_NOW, 10000000000)); // wait until the open event has gone through
        } else {
            NSError *launchErr = nil;
            
            if (![[NSWorkspace sharedWorkspace] launchApplicationAtURL:manOpenURLs.firstObject options:forceToFront ? 0UL : NSWorkspaceLaunchWithoutActivation configuration:@{} error:&launchErr])
            {
                fprintf(stderr, "Could not launch ManOpen\n");
                exit(EXIT_FAILURE);
            }
        }
        
        // Use a Mach port to open a connection; keep trying until one connects.
        do {
            remotePort = CFMessagePortCreateRemote(NULL, CFSTR("8D98N325TG.org.clindberg.ManOpen.MachIPC"));
            if (!remotePort) {
                sleep(1);
            }
        } while (remotePort == nil && connectCount++ < maxConnectTries);
        
        if (remotePort == nil) {
            fprintf(stderr,"Could not open connection to ManOpen\n");
            return EXIT_FAILURE;
        }
        
        if (files.count) {
            distributedDictionary[@"Files"] = files;
        }
        
        if (manPath == nil && getenv("MANPATH") != NULL) {
            manPath = MakeNSStringFromPath(getenv("MANPATH"));
        }
        
        for (argIndex = optind; argIndex < argc; argIndex++) {
            NSString *currFile = MakeNSStringFromPath(argv[argIndex]);
            NSDictionary *nameAndSection;
            
            if (section) {
                nameAndSection = @{@"Name": currFile, @"Section": section};
            } else {
                nameAndSection = @{@"Name": currFile};
            }
            [namesAndSections addObject:nameAndSection];
        }
        if (aproposMode) {
            distributedDictionary[@"Apropos"] = @YES;
        }
        if (manPath) {
            distributedDictionary[@"ManPath"] = manPath;
        }
        distributedDictionary[@"NamesAndSections"] = namesAndSections;
        
        // Once we've got all our data together, send the message to the app. The message ID below is intentional, because I feel like I went mental writing this (it was my third attempt at replacing the original DO code).
        status = CFMessagePortSendRequest(remotePort, 5150, (CFDataRef)[NSKeyedArchiver archivedDataWithRootObject:distributedDictionary requiringSecureCoding:YES error:NULL], 10.0, 10.0, NULL, NULL);
        return status == kCFMessagePortSuccess ? EXIT_SUCCESS : EXIT_FAILURE;
    }
}
