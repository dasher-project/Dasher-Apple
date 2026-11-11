#import "ProbeText.h"

static NSString *const ProbeMarker = @"DasherProbe";
static const NSUInteger Lookback = 32;
static const NSUInteger MaxSelection = 128;

@implementation ProbeSnapshot
- (BOOL)matchesSnapshot:(ProbeSnapshot *)other {
    return other && self.process == other.process && NSEqualRanges(self.selection, other.selection) &&
        [self.before isEqualToString:other.before] && [self.selectedText isEqualToString:other.selectedText];
}
@end

@implementation ProbeEdit
- (BOOL)matchesReadback:(ProbeSnapshot *)snapshot {
    NSUInteger caret = self.range.location + self.replacement.length;
    return snapshot && NSEqualRanges(snapshot.selection, NSMakeRange(caret, 0)) &&
        (self.expectedBefore.length == 0 || [snapshot.before hasSuffix:self.expectedBefore]);
}
@end

ProbeSnapshot *CaptureProbeSnapshot(id<IMKTextInput> client) {
    if (!client) return nil;
    NSRange selection = [client selectedRange];
    if (selection.location >= NSNotFound || selection.length > MaxSelection ||
        selection.length > NSNotFound - selection.location) return nil;

    NSRange marked = [client markedRange];
    if (marked.location != NSNotFound && marked.length > 0) return nil;

    NSUInteger length = MIN(selection.location, Lookback);
    NSRange requested = NSMakeRange(selection.location - length, length);
    NSRange actual = NSMakeRange(NSNotFound, 0);
    NSString *before = length ? [client stringFromRange:requested actualRange:&actual] : @"";
    if (length && (!before.length || actual.length > Lookback || actual.length != before.length ||
        actual.location > selection.location || actual.length != selection.location - actual.location)) return nil;

    actual = NSMakeRange(NSNotFound, 0);
    NSString *selected = selection.length ? [client stringFromRange:selection actualRange:&actual] : @"";
    if (selection.length && (selected.length != selection.length || !NSEqualRanges(actual, selection))) return nil;
    if (!NSEqualRanges(selection, [client selectedRange])) return nil;

    ProbeSnapshot *snapshot = [ProbeSnapshot new];
    snapshot.selection = selection;
    snapshot.before = before;
    snapshot.selectedText = selected;
    return snapshot;
}

ProbeEdit *PlanProbeEdit(ProbeSnapshot *snapshot, ProbeOperation operation) {
    ProbeEdit *edit = [ProbeEdit new];
    if (operation == ProbeBackspace && snapshot.selection.length) {
        if (![snapshot.selectedText isEqualToString:ProbeMarker]) return nil;
        edit.range = snapshot.selection;
        edit.replacement = @"";
        edit.expectedBefore = snapshot.before;
        return edit;
    }
    if (operation != ProbeInsertMarker) {
        if (snapshot.selection.length || ![snapshot.before hasSuffix:ProbeMarker]) return nil;
        NSUInteger length = operation == ProbeBackspace ? 1 : ProbeMarker.length;
        edit.range = NSMakeRange(snapshot.selection.location - length, length);
        edit.replacement = @"";
        edit.expectedBefore = [snapshot.before substringToIndex:snapshot.before.length - length];
        return edit;
    }

    edit.range = snapshot.selection;
    edit.replacement = ProbeMarker;
    NSString *expected = [snapshot.before stringByAppendingString:ProbeMarker];
    NSUInteger start = expected.length - MIN(expected.length, Lookback);
    if (CFStringIsSurrogateLowCharacter([expected characterAtIndex:start])) start++;
    edit.expectedBefore = [expected substringFromIndex:start];
    return edit;
}
