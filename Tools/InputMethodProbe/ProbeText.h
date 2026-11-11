#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>

@interface ProbeSnapshot : NSObject
@property NSRange selection;
@property (copy) NSString *before;
@property (copy) NSString *selectedText;
@property pid_t process;
- (BOOL)matchesSnapshot:(ProbeSnapshot *)other;
@end

@interface ProbeEdit : NSObject
@property NSRange range;
@property (copy) NSString *replacement;
@property (copy) NSString *expectedBefore;
- (BOOL)matchesReadback:(ProbeSnapshot *)snapshot;
@end

ProbeSnapshot *CaptureProbeSnapshot(id<IMKTextInput> client);
ProbeEdit *PlanProbeEdit(ProbeSnapshot *snapshot, BOOL deleting);
