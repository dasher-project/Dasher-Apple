#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DasherInputMethodContext : NSObject
@property (nonatomic, readonly) NSString *prefix;
@property (nonatomic, readonly) NSRange selection;
- (instancetype)initWithPrefix:(NSString *)prefix selection:(NSRange)selection;
@end

// The listener calls this block on the input method's main thread.
typedef DasherInputMethodContext * _Nullable (^DasherInputMethodReader)(pid_t);

void DasherStartInputMethodContextServer(DasherInputMethodReader reader);
DasherInputMethodContext * _Nullable DasherReadInputMethodContext(pid_t editor);

NS_ASSUME_NONNULL_END
