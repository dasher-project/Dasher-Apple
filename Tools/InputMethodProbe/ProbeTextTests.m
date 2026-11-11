#import "ProbeText.h"

@interface ScratchClient : NSObject
@property (copy) NSString *text;
@property NSRange selectedRange;
@property NSRange markedRange;
@property NSUInteger accessibleStart;
@property BOOL ignoresReplacementRange;
@end

@implementation ScratchClient
- (NSString *)stringFromRange:(NSRange)range actualRange:(NSRangePointer)actual {
    *actual = NSIntersectionRange(range, NSMakeRange(self.accessibleStart, self.text.length - self.accessibleStart));
    return actual->length ? [self.text substringWithRange:*actual] : nil;
}

- (void)insertText:(NSString *)text replacementRange:(NSRange)range {
    if (self.ignoresReplacementRange) range = self.selectedRange;
    self.text = [self.text stringByReplacingCharactersInRange:range withString:text];
    self.selectedRange = NSMakeRange(range.location + text.length, 0);
}
@end

static ProbeSnapshot *snapshot(ScratchClient *client) {
    return CaptureProbeSnapshot((id<IMKTextInput>)client);
}

static void check(BOOL condition, const char *message) {
    if (condition) return;
    fprintf(stderr, "FAIL: %s\n", message);
    exit(EXIT_FAILURE);
}

int main(void) {
    @autoreleasepool {
        ScratchClient *client = [ScratchClient new];
        client.text = @"😀 left replace right";
        client.selectedRange = [client.text rangeOfString:@"replace"];
        ProbeSnapshot *first = snapshot(client);
        check([first.before isEqualToString:@"😀 left "], "reads UTF-16 context before a selection");
        check([first.selectedText isEqualToString:@"replace"], "reads the entire selection");
        check(!PlanProbeEdit(first, ProbeDeleteMarker), "refuses marker deletion over a selection");
        check(!PlanProbeEdit(first, ProbeBackspace), "refuses Backspace over ordinary selected text");

        ProbeEdit *insert = PlanProbeEdit(first, ProbeInsertMarker);
        [client insertText:insert.replacement replacementRange:insert.range];
        check([client.text isEqualToString:@"😀 left DasherProbe right"], "replaces the exact selection");
        check([insert matchesReadback:snapshot(client)], "verifies insertion through a fresh read");
        check(![first matchesSnapshot:snapshot(client)], "invalidates a stale selection");

        ScratchClient *keyClient = [ScratchClient new];
        keyClient.text = client.text;
        keyClient.selectedRange = client.selectedRange;
        ProbeEdit *backspace = PlanProbeEdit(snapshot(keyClient), ProbeBackspace);
        [keyClient insertText:backspace.replacement replacementRange:backspace.range];
        check([keyClient.text isEqualToString:@"😀 left DasherProb right"], "checks a single-character Backspace at the caret");
        check([backspace matchesReadback:snapshot(keyClient)], "matches the result of Backspace at the caret");
        check(!PlanProbeEdit(snapshot(keyClient), ProbeBackspace), "refuses a second Backspace after the marker changes");

        keyClient.text = client.text;
        keyClient.selectedRange = [keyClient.text rangeOfString:@"DasherProbe"];
        backspace = PlanProbeEdit(snapshot(keyClient), ProbeBackspace);
        [keyClient insertText:backspace.replacement replacementRange:backspace.range];
        check([keyClient.text isEqualToString:@"😀 left  right"], "checks Backspace over a selected marker");
        check([backspace matchesReadback:snapshot(keyClient)], "matches the result of Backspace over a selection");

        ProbeEdit *remove = PlanProbeEdit(snapshot(client), ProbeDeleteMarker);
        client.ignoresReplacementRange = YES;
        [client insertText:remove.replacement replacementRange:remove.range];
        check(![remove matchesReadback:snapshot(client)], "detects an ignored deletion range");
        client.ignoresReplacementRange = NO;
        [client insertText:remove.replacement replacementRange:remove.range];
        check([client.text isEqualToString:@"😀 left  right"], "deletes only the marker");
        check([remove matchesReadback:snapshot(client)], "verifies deletion through a fresh read");
        check(!PlanProbeEdit(snapshot(client), ProbeDeleteMarker), "refuses deletion of ordinary text");

        client.selectedRange = NSMakeRange(0, 0);
        check([snapshot(client).before isEqualToString:@""], "accepts a caret at document start");
        client.text = @"DasherProbe right";
        client.selectedRange = NSMakeRange(11, 0);
        remove = PlanProbeEdit(snapshot(client), ProbeDeleteMarker);
        [client insertText:remove.replacement replacementRange:remove.range];
        check([client.text isEqualToString:@" right"], "deletes the marker at document start");
        check([remove matchesReadback:snapshot(client)], "accepts empty context after deletion at document start");
        client.selectedRange = NSMakeRange(NSNotFound, 0);
        check(!snapshot(client), "rejects unavailable selection");
        client.selectedRange = NSMakeRange(0, 129);
        check(!snapshot(client), "rejects an oversized selection");
        client.selectedRange = NSMakeRange(0, 0);
        client.markedRange = NSMakeRange(0, 1);
        check(!snapshot(client), "leaves active composition alone");
        client.markedRange = NSMakeRange(NSNotFound, 0);

        client.text = @"0123456789012345678901234567890123456789";
        client.selectedRange = NSMakeRange(client.text.length, 0);
        check(snapshot(client).before.length == 32, "bounds context at 32 UTF-16 units");
        client.accessibleStart = client.text.length - 4;
        check([snapshot(client).before isEqualToString:@"6789"], "accepts a clipped range ending at the caret");
        client.selectedRange = NSMakeRange(client.text.length - 5, 4);
        check(!snapshot(client), "rejects a range that cannot reach the caret");

        puts("Probe text tests passed");
    }
    return EXIT_SUCCESS;
}
