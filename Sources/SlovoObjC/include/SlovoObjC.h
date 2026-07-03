#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` and converts any Objective-C exception it raises into an
/// `NSError`, so a Swift caller can recover instead of the process aborting.
///
/// AVFoundation's audio engine reports an invalid or mismatched tap format by
/// raising an `NSException` (for example when the input hardware sample rate
/// changes after an audio device switch). Swift cannot catch that exception, so
/// it becomes a `SIGABRT`. Wrapping the call here turns it into a thrown error.
///
/// @return `nil` when the block completes normally; otherwise an `NSError`
///   carrying the exception name and reason.
NSError *_Nullable SlovoRunCatchingNSException(void (NS_NOESCAPE ^block)(void));

NS_ASSUME_NONNULL_END
