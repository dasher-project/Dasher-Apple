#import <AppKit/AppKit.h>
#import <InputMethodKit/InputMethodKit.h>
#import <os/log.h>
#import "ProbeText.h"

@interface ProbePanel : NSPanel
@end

@implementation ProbePanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface DasherProbeController : IMKInputController
@end

static __weak DasherProbeController *activeController;
static ProbePanel *panel;
static NSTextField *status;
static NSArray<NSButton *> *panelButtons;

static BOOL PostBackspace(pid_t process) {
    CGEventRef down = CGEventCreateKeyboardEvent(NULL, kVK_Delete, true);
    CGEventRef up = CGEventCreateKeyboardEvent(NULL, kVK_Delete, false);
    BOOL posted = down && up;
    if (posted) {
        CGEventSetFlags(down, 0);
        CGEventSetFlags(up, 0);
        CGEventPostToPid(process, down);
        CGEventPostToPid(process, up);
    }
    if (down) CFRelease(down);
    if (up) CFRelease(up);
    return posted;
}

@implementation DasherProbeController {
    ProbeSnapshot *_snapshot;
    NSString *_bundleID;
    NSUInteger _session;
    BOOL _verifying;
}

- (void)report:(NSString *)message {
    status.stringValue = message;
    // Messages contain only status and range lengths, never document text.
    os_log(OS_LOG_DEFAULT, "[%{public}@] %{public}@", _bundleID ?: @"No client", message);
}

- (void)showPanel {
    if (!panel) {
        panel = [[ProbePanel alloc] initWithContentRect:NSMakeRect(0, 0, 490, 140)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskNonactivatingPanel
            backing:NSBackingStoreBuffered defer:NO];
        panel.title = @"Dasher IME Probe";
        panel.level = NSFloatingWindowLevel;
        panel.hidesOnDeactivate = NO;
        panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
            NSWindowCollectionBehaviorFullScreenAuxiliary;
        [panel center];

        status = [NSTextField wrappingLabelWithString:@""];
        NSButton *read = [NSButton buttonWithTitle:@"Read Context" target:nil action:@selector(readContext:)];
        NSButton *insert = [NSButton buttonWithTitle:@"Insert Marker" target:nil action:@selector(insertMarker:)];
        NSButton *remove = [NSButton buttonWithTitle:@"Delete Marker" target:nil action:@selector(deleteMarker:)];
        NSButton *backspace = [NSButton buttonWithTitle:@"Backspace" target:nil action:@selector(backspace:)];
        panelButtons = @[read, insert, remove, backspace];
        NSStackView *buttons = [NSStackView stackViewWithViews:panelButtons];
        NSStackView *stack = [NSStackView stackViewWithViews:@[status, buttons]];
        stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        stack.alignment = NSLayoutAttributeLeading;
        stack.spacing = 12;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [panel.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:panel.contentView.leadingAnchor constant:16],
            [stack.trailingAnchor constraintEqualToAnchor:panel.contentView.trailingAnchor constant:-16],
            [stack.topAnchor constraintEqualToAnchor:panel.contentView.topAnchor constant:16],
            [status.widthAnchor constraintEqualToAnchor:stack.widthAnchor]
        ]];
    }
    for (NSButton *button in panelButtons) {
        button.target = self;
    }
    [panel orderFrontRegardless];
}

- (void)activateServer:(id)sender {
    id<IMKTextInput> client = sender;
    activeController = self;
    _session++;
    _snapshot = nil;
    _verifying = NO;
    _bundleID = [client bundleIdentifier];
    [self showPanel];
    [self report:[NSString stringWithFormat:@"%@ is active. Read Context to start.", _bundleID ?: @"Editor"]];
}

- (void)deactivateServer:(id)sender {
    (void)sender;
    _session++;
    _snapshot = nil;
    _verifying = NO;
    if (activeController == self) {
        activeController = nil;
        [panel orderOut:nil];
    }
}

- (void)inputControllerWillClose {
    [self deactivateServer:nil];
}

- (BOOL)handleEvent:(NSEvent *)event client:(id)sender {
    (void)event;
    (void)sender;
    _snapshot = nil;
    return NO;
}

- (pid_t)foregroundClientProcess {
    NSRunningApplication *front = NSWorkspace.sharedWorkspace.frontmostApplication;
    if (activeController == self && [_bundleID isEqualToString:front.bundleIdentifier]) {
        return front.processIdentifier;
    }
    return 0;
}

- (ProbeSnapshot *)capture {
    pid_t process = [self foregroundClientProcess];
    if (!process) return nil;
    NSUInteger session = _session;
    ProbeSnapshot *snapshot = CaptureProbeSnapshot([self client]);
    if (session != _session || process != [self foregroundClientProcess]) return nil;
    snapshot.process = process;
    return snapshot;
}

- (void)readContext:(id)sender {
    (void)sender;
    if (_verifying || activeController != self) return;
    _snapshot = [self capture];
    if (!_snapshot) {
        [self report:@"Context unavailable. Focus an editable scratch field and try again."];
        return;
    }
    [self report:[NSString stringWithFormat:@"Read OK. Caret %lu, selection %lu, before %lu (UTF-16).",
        _snapshot.selection.location, _snapshot.selection.length, _snapshot.before.length]];
}

- (void)insertMarker:(id)sender {
    (void)sender;
    [self applyEdit:ProbeInsertMarker name:@"Insert"];
}

- (void)deleteMarker:(id)sender {
    (void)sender;
    [self applyEdit:ProbeDeleteMarker name:@"Delete"];
}

- (void)backspace:(id)sender {
    (void)sender;
    [self applyEdit:ProbeBackspace name:@"Backspace"];
}

- (void)applyEdit:(ProbeOperation)operation name:(NSString *)name {
    if (_verifying || activeController != self) return;
    ProbeSnapshot *previous = _snapshot;
    _snapshot = nil;
    if (!previous) {
        [self report:@"Read Context before editing."];
        return;
    }
    NSUInteger session = _session;
    ProbeSnapshot *current = [self capture];
    if (session != _session || activeController != self) return;
    if (![previous matchesSnapshot:current]) {
        [self report:@"Edit rejected. Context changed. Read Context again."];
        return;
    }

    ProbeEdit *edit = PlanProbeEdit(current, operation);
    if (!edit) {
        [self report:operation == ProbeBackspace
            ? @"Backspace rejected. Select the marker or place the caret immediately after it."
            : @"Delete rejected. Place the caret immediately after the marker."];
        return;
    }
    if (operation == ProbeBackspace && !CGPreflightPostEventAccess()) {
        [self report:@"Backspace needs Accessibility access for Dasher IME Probe in System Settings."];
        return;
    }
    if (session != _session || [self foregroundClientProcess] != current.process) return;

    _verifying = YES;
    [self report:@"Checking editor readback…"];
    if (operation == ProbeBackspace) {
        if (!PostBackspace(current.process)) {
            _verifying = NO;
            [self report:@"Could not create the Backspace key event."];
            return;
        }
    } else {
        id<IMKTextInput> client = [self client];
        [client insertText:edit.replacement replacementRange:edit.range];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        [self checkEdit:edit previous:current session:session name:name readAgain:YES];
    });
}

- (void)checkEdit:(ProbeEdit *)edit previous:(ProbeSnapshot *)previous session:(NSUInteger)session
            name:(NSString *)name readAgain:(BOOL)readAgain {
    if (session != _session || activeController != self) return;
    ProbeSnapshot *after = [self capture];
    if (session != _session || activeController != self) return;

    BOOL sameEditor = after.process == previous.process;
    BOOL unchanged = [previous matchesSnapshot:after];
    if (readAgain && (!after || unchanged)) {
        // An editor can report its old selection while it applies the edit.
        // Check once more without sending another edit.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            [self checkEdit:edit previous:previous session:session name:name readAgain:NO];
        });
        return;
    }

    _verifying = NO;
    if (sameEditor && [edit matchesReadback:after]) {
        [self report:[NSString stringWithFormat:@"%@ readback matched.", name]];
        return;
    }

    NSUInteger expectedCaret = edit.range.location + edit.replacement.length;
    NSString *detail;
    if (!sameEditor) {
        detail = @"Editor context is unavailable.";
    } else if (unchanged) {
        detail = @"Editor still reports the original caret and context.";
    } else if (!NSEqualRanges(after.selection, NSMakeRange(expectedCaret, 0))) {
        detail = [NSString stringWithFormat:@"Caret %lu, selection %lu. Expected caret %lu with no selection.",
            after.selection.location, after.selection.length, expectedCaret];
    } else {
        detail = @"Caret matches, but the text before it differs.";
    }
    [self report:[NSString stringWithFormat:@"%@ unconfirmed. %@", name, detail]];
}

@end

static NSString *sourceID(TISInputSourceRef source) {
    return (__bridge NSString *)TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
}

static NSArray *matchingSources(NSString *identifier, BOOL includeDisabled) {
    NSDictionary *filter = @{(__bridge NSString *)kTISPropertyInputSourceID: identifier};
    return CFBridgingRelease(TISCreateInputSourceList((__bridge CFDictionaryRef)filter, includeDisabled));
}

static int manageSource(NSArray<NSString *> *arguments, NSBundle *bundle) {
    NSString *command = arguments[1];
    if ([command isEqualToString:@"current"] && arguments.count == 2) {
        TISInputSourceRef current = TISCopyCurrentKeyboardInputSource();
        if (!current) return EXIT_FAILURE;
        puts(sourceID(current).UTF8String);
        CFRelease(current);
        return EXIT_SUCCESS;
    }

    OSStatus result;
    if ([command isEqualToString:@"register"] && arguments.count == 2) {
        result = TISRegisterInputSource((__bridge CFURLRef)bundle.bundleURL);
    } else if (([command isEqualToString:@"enable"] || [command isEqualToString:@"disable"] ||
                [command isEqualToString:@"status"]) && arguments.count == 2) {
        NSArray *sources = matchingSources(bundle.bundleIdentifier, YES);
        if (!sources.count) {
            fprintf(stderr, "Input source is not registered.\n");
            return EXIT_FAILURE;
        }
        TISInputSourceRef source = (__bridge TISInputSourceRef)sources.firstObject;
        if ([command isEqualToString:@"status"]) {
            BOOL enabled = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) == kCFBooleanTrue;
            BOOL selectable = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) == kCFBooleanTrue;
            NSString *type = (__bridge NSString *)TISGetInputSourceProperty(source, kTISPropertyInputSourceType);
            printf("Registered (%s), enabled: %s, selectable: %s\n", type.UTF8String,
                enabled ? "yes" : "no", selectable ? "yes" : "no");
            return EXIT_SUCCESS;
        }
        result = [command isEqualToString:@"enable"] ? TISEnableInputSource(source) : TISDisableInputSource(source);
    } else if ([command isEqualToString:@"select"] && arguments.count <= 3) {
        NSString *identifier = arguments.count == 3 ? arguments[2] : bundle.bundleIdentifier;
        NSArray *sources = matchingSources(identifier, NO);
        if (!sources.count) {
            fprintf(stderr, "Input source is unavailable or disabled: %s\n", identifier.UTF8String);
            return EXIT_FAILURE;
        }
        result = TISSelectInputSource((__bridge TISInputSourceRef)sources.firstObject);
    } else {
        fprintf(stderr, "Usage: DasherInputMethodProbe [register | status | enable | disable | current | select [source-id]]\n");
        return EXIT_FAILURE;
    }
    if (result != noErr) fprintf(stderr, "%s failed (%d)\n", command.UTF8String, (int)result);
    return result == noErr ? EXIT_SUCCESS : EXIT_FAILURE;
}

int main(void) {
    @autoreleasepool {
        NSBundle *bundle = NSBundle.mainBundle;
        NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
        if (arguments.count > 1) return manageSource(arguments, bundle);

        NSString *connection = [bundle objectForInfoDictionaryKey:@"InputMethodConnectionName"];
        IMKServer *server __attribute__((objc_precise_lifetime)) =
            [[IMKServer alloc] initWithName:connection bundleIdentifier:bundle.bundleIdentifier];
        if (!server) return EXIT_FAILURE;
        NSLog(@"Dasher IME Probe server started");
        [NSApplication.sharedApplication run];
    }
    return EXIT_SUCCESS;
}
