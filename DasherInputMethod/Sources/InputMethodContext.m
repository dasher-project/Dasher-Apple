#import "InputMethodContext.h"
#import <Security/Security.h>
#import <fcntl.h>
#import <mach/message.h>
#import <poll.h>
#import <sys/file.h>
#import <sys/socket.h>
#import <sys/stat.h>
#import <sys/un.h>
#import <unistd.h>

enum { MaxPrefixLength = 256, SocketTimeoutMillis = 120 };
static NSString *const AppGroup = @"TRKU383G7Z.at.dasher.inputmethod";
static NSString *const InputMethodID = @"at.dasher.inputmethod.direct";
static NSString *const DasherID = @"at.dasher.Dasher.mac";

typedef struct {
    uint64_t location;
    uint64_t selectionLength;
    uint32_t length;
    unichar prefix[MaxPrefixLength];
} ContextReply;

@implementation DasherInputMethodContext
- (instancetype)initWithPrefix:(NSString *)prefix selection:(NSRange)selection {
    self = [super init];
    if (self) {
        _prefix = [prefix copy];
        _selection = selection;
    }
    return self;
}
@end

static NSString *SocketPath(void) {
    NSURL *group = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:AppGroup];
    return [group URLByAppendingPathComponent:@"context.sock"].path;
}

static BOOL SetAddress(struct sockaddr_un *address, NSString *path) {
    const char *bytes = path.fileSystemRepresentation;
    if (!bytes || strlen(bytes) >= sizeof(address->sun_path)) return NO;
    address->sun_family = AF_UNIX;
    strlcpy(address->sun_path, bytes, sizeof(address->sun_path));
    address->sun_len = SUN_LEN(address);
    return YES;
}

static BOOL SetSocketOptions(int fd) {
    struct timeval timeout = {0, SocketTimeoutMillis * 1000};
    int noSignal = 1;
    return fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 &&
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal)) == 0 &&
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) == 0 &&
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout)) == 0;
}

static NSString *SigningTeam(void) {
    static NSString *team;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SecCodeRef selfCode = NULL;
        if (SecCodeCopySelf(kSecCSDefaultFlags, &selfCode) != errSecSuccess) return;
        CFDictionaryRef information = NULL;
        if (SecCodeCopySigningInformation(selfCode, kSecCSSigningInformation, &information) == errSecSuccess) {
            team = CFBridgingRelease(information)[(__bridge NSString *)kSecCodeInfoTeamIdentifier];
        }
        CFRelease(selfCode);
    });
    return team;
}

static BOOL IsTrustedPeer(int fd, NSString *identifier) {
    NSString *team = SigningTeam();
    if (!team.length) return NO;

    audit_token_t token;
    socklen_t length = sizeof(token);
    if (getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &length) != 0 || length != sizeof(token)) return NO;
    uid_t uid;
    gid_t gid;
    if (getpeereid(fd, &uid, &gid) != 0 || uid != geteuid()) return NO;

    NSData *audit = [NSData dataWithBytes:&token length:sizeof(token)];
    // The sandboxed app can validate the running peer without reading the
    // helper's installed bundle in ~/Library/Input Methods.
    NSDictionary *attributes = @{
        (__bridge NSString *)kSecGuestAttributeAudit: audit,
        (__bridge NSString *)kSecGuestAttributeDynamicCode: @YES
    };
    SecCodeRef code = NULL;
    if (SecCodeCopyGuestWithAttributes(NULL, (__bridge CFDictionaryRef)attributes, kSecCSDefaultFlags, &code) != errSecSuccess) {
        return NO;
    }
    NSString *rule = [NSString stringWithFormat:@"anchor apple generic and identifier \"%@\" and certificate leaf[subject.OU] = \"%@\"",
        identifier, team];
    SecRequirementRef requirement = NULL;
    BOOL trusted = SecRequirementCreateWithString((__bridge CFStringRef)rule, kSecCSDefaultFlags, &requirement) == errSecSuccess &&
        SecCodeCheckValidity(code, kSecCSDefaultFlags, requirement) == errSecSuccess;
    if (requirement) CFRelease(requirement);
    CFRelease(code);
    return trusted;
}

static BOOL ConnectSocket(int fd, struct sockaddr_un *address) {
    if (fcntl(fd, F_SETFL, O_NONBLOCK) != 0) return NO;
    if (connect(fd, (struct sockaddr *)address, address->sun_len) != 0) {
        if (errno != EINPROGRESS) return NO;
        struct pollfd item = { .fd = fd, .events = POLLOUT };
        int error;
        socklen_t length = sizeof(error);
        if (poll(&item, 1, SocketTimeoutMillis) != 1 ||
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) != 0 || error != 0) return NO;
    }
    return fcntl(fd, F_SETFL, 0) == 0;
}

DasherInputMethodContext *DasherReadInputMethodContext(pid_t editor) {
    struct sockaddr_un address = {0};
    if (editor <= 0 || !SetAddress(&address, SocketPath())) return nil;
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return nil;
    ContextReply reply = {0};
    BOOL received = SetSocketOptions(fd) && ConnectSocket(fd, &address) && IsTrustedPeer(fd, InputMethodID) &&
        send(fd, &editor, sizeof(editor), 0) == sizeof(editor) &&
        recv(fd, &reply, sizeof(reply), MSG_WAITALL) == sizeof(reply);
    close(fd);

    if (!received || reply.length > MaxPrefixLength || reply.length > reply.location ||
        reply.location >= NSNotFound || reply.selectionLength > NSNotFound - reply.location) return nil;
    NSString *prefix = [NSString stringWithCharacters:reply.prefix length:reply.length];
    return [[DasherInputMethodContext alloc] initWithPrefix:prefix selection:NSMakeRange(reply.location, reply.selectionLength)];
}

static void ReplyToReader(int fd, DasherInputMethodReader reader) {
    pid_t editor;
    if (fcntl(fd, F_SETFL, 0) != 0 || !SetSocketOptions(fd) || !IsTrustedPeer(fd, DasherID) ||
        recv(fd, &editor, sizeof(editor), MSG_WAITALL) != sizeof(editor) || editor <= 0) return;

    __block DasherInputMethodContext *context;
    dispatch_sync(dispatch_get_main_queue(), ^{ context = reader(editor); });
    if (!context || context.prefix.length > MaxPrefixLength) return;
    ContextReply reply = {0};
    reply.location = context.selection.location;
    reply.selectionLength = context.selection.length;
    reply.length = (uint32_t)context.prefix.length;
    [context.prefix getCharacters:reply.prefix range:NSMakeRange(0, reply.length)];
    send(fd, &reply, sizeof(reply), 0);
}

void DasherStartInputMethodContextServer(DasherInputMethodReader reader) {
    static dispatch_source_t listener;
    if (listener || !SigningTeam()) return;
    NSString *path = SocketPath();
    struct sockaddr_un address = {0};
    if (!SetAddress(&address, path)) return;

    // Only one process may bind this path. The lock survives a stale socket
    // left by an input method that macOS terminated without a shutdown callback.
    NSString *lockPath = [path stringByAppendingString:@".lock"];
    int lock = open(lockPath.fileSystemRepresentation, O_CREAT | O_CLOEXEC | O_NOFOLLOW | O_RDWR, 0600);
    if (lock < 0) return;
    if (flock(lock, LOCK_EX | LOCK_NB) != 0) {
        close(lock);
        return;
    }

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0 || fcntl(fd, F_SETFD, FD_CLOEXEC) != 0 || fcntl(fd, F_SETFL, O_NONBLOCK) != 0) {
        if (fd >= 0) close(fd);
        close(lock);
        return;
    }
    unlink(address.sun_path);
    if (bind(fd, (struct sockaddr *)&address, address.sun_len) != 0 ||
        chmod(address.sun_path, 0600) != 0 || listen(fd, 4) != 0) {
        close(fd);
        close(lock);
        return;
    }

    dispatch_queue_t queue = dispatch_queue_create("at.dasher.input-method.context", DISPATCH_QUEUE_SERIAL);
    listener = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, queue);
    dispatch_source_set_event_handler(listener, ^{
        @autoreleasepool {
            int client = accept(fd, NULL, NULL);
            if (client < 0) return;
            ReplyToReader(client, reader);
            close(client);
        }
    });
    // The listener and lock have the lifetime of the input method process.
    dispatch_resume(listener);
}
