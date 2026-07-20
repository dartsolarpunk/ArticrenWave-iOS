#import "AWExceptionCatcher.h"

NSString * _Nullable AWTryCatch(void (NS_NOESCAPE ^block)(void)) {
    @try {
        block();
        return nil;
    }
    @catch (NSException *exception) {
        return exception.reason ?: exception.name ?: @"NSException";
    }
}
