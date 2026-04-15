#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AudioAvailabilityResult) {
    AudioAvailabilityResultAvailable = 0,
    AudioAvailabilityResultNoInputDevice = 1,
    AudioAvailabilityResultException = 2,
    AudioAvailabilityResultEngineStartFailed = 3
};

@interface AudioAvailabilityChecker : NSObject

+ (AudioAvailabilityResult)checkAudioInputAvailability;
+ (nullable NSString *)lastErrorMessage;

@end

NS_ASSUME_NONNULL_END
