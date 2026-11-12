#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <InputMethodKit/InputMethodKit.h>
#import "InputMethodContext.h"
#import "InputMethodInstallation.h"

@interface DasherInputController : IMKInputController
- (nullable DasherInputMethodContext *)contextForEditor:(pid_t)editor;
@end

static __weak DasherInputController *activeController;

@implementation DasherInputController {
    NSString *_editorBundleID;
    NSUInteger _activation;
}

- (void)activateServer:(id)sender {
    activeController = self;
    _editorBundleID = [(id<IMKTextInput>)sender bundleIdentifier];
    _activation++;
}

- (void)deactivateServer:(__unused id)sender {
    if (activeController == self) activeController = nil;
    _activation++;
}

- (void)inputControllerWillClose {
    [self deactivateServer:nil];
}

- (BOOL)handleEvent:(__unused NSEvent *)event client:(__unused id)sender {
    return NO;
}

- (BOOL)isActiveForEditor:(pid_t)editor {
    NSRunningApplication *front = NSWorkspace.sharedWorkspace.frontmostApplication;
    return activeController == self && front.processIdentifier == editor &&
        [_editorBundleID isEqualToString:front.bundleIdentifier] && !IsSecureEventInputEnabled();
}

- (DasherInputMethodContext *)contextForEditor:(pid_t)editor {
    if (![self isActiveForEditor:editor]) return nil;
    NSUInteger activation = _activation;
    id<IMKTextInput> client = [self client];
    if (!client) return nil;
    NSRange selection = [client selectedRange];
    NSRange marked = [client markedRange];
    if (selection.location >= NSNotFound || selection.length > NSNotFound - selection.location ||
        (marked.location != NSNotFound && marked.length > 0)) return nil;

    NSUInteger length = MIN(selection.location, 256);
    NSRange requested = NSMakeRange(selection.location - length, length);
    NSRange actual = NSMakeRange(NSNotFound, 0);
    NSString *prefix = length ? [client stringFromRange:requested actualRange:&actual] : @"";
    if (length && (!prefix.length || actual.location < requested.location || actual.location > selection.location ||
        actual.length != selection.location - actual.location || actual.length != prefix.length)) return nil;
    if (prefix.length && CFStringIsSurrogateLowCharacter([prefix characterAtIndex:0])) {
        prefix = [prefix substringFromIndex:1];
    }
    if (!NSEqualRanges(selection, [client selectedRange]) || activation != _activation ||
        ![self isActiveForEditor:editor]) return nil;
    return [[DasherInputMethodContext alloc] initWithPrefix:prefix selection:selection];
}
@end

int main(void) {
    @autoreleasepool {
        NSBundle *bundle = NSBundle.mainBundle;
        if (DasherIsBundledInputMethod(bundle)) {
            return DasherInstallInputMethod(bundle) ? EXIT_SUCCESS : EXIT_FAILURE;
        }

        NSString *connection = [bundle objectForInfoDictionaryKey:@"InputMethodConnectionName"];
        IMKServer *server __attribute__((objc_precise_lifetime)) =
            [[IMKServer alloc] initWithName:connection bundleIdentifier:bundle.bundleIdentifier];
        if (!server) return EXIT_FAILURE;
        DasherStartInputMethodContextServer(^DasherInputMethodContext *(pid_t editor) {
            return [activeController contextForEditor:editor];
        });
        [NSApplication.sharedApplication run];
    }
    return EXIT_SUCCESS;
}
