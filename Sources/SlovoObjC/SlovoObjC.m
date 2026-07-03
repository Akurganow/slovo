#import "SlovoObjC.h"

NSError *_Nullable SlovoRunCatchingNSException(void (NS_NOESCAPE ^block)(void)) {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        NSString *reason = exception.reason ?: (exception.name ?: @"unknown NSException");
        return [NSError errorWithDomain:@"com.slovo.objc.exception"
                                   code:1
                               userInfo:@{NSLocalizedDescriptionKey: reason}];
    }
}
