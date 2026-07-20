#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs the block, catching any Objective-C NSException (which Swift cannot catch).
/// Returns the exception reason on failure, nil on success.
FOUNDATION_EXPORT NSString * _Nullable AWTryCatch(void (NS_NOESCAPE ^block)(void));

NS_ASSUME_NONNULL_END
