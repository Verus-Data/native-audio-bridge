#import "AudioAvailabilityChecker.h"

@implementation AudioAvailabilityChecker {
    NSString *_lastErrorMessage;
}

+ (AudioAvailabilityResult)checkAudioInputAvailability {
    AudioAvailabilityChecker *checker = [[AudioAvailabilityChecker alloc] init];
    return [checker performCheck];
}

- (AudioAvailabilityResult)performCheck {
    @try {
        AVAudioEngine *engine = [[AVAudioEngine alloc] init];
        
        @try {
            AVAudioInputNode *inputNode = engine.inputNode;
            if (inputNode == nil) {
                _lastErrorMessage = @"Input node is nil - no audio input available";
                return AudioAvailabilityResultNoInputDevice;
            }
        } @catch (NSException *exception) {
            _lastErrorMessage = [NSString stringWithFormat:@"Exception accessing input node: %@", exception.reason];
            return AudioAvailabilityResultException;
        }
        
        @try {
            NSError *error = nil;
            [engine startAndReturnError:&error];
            if (error) {
                _lastErrorMessage = [NSString stringWithFormat:@"Engine start failed: %@", error.localizedDescription];
                [engine stop];
                return AudioAvailabilityResultEngineStartFailed;
            }
            [engine stop];
        } @catch (NSException *exception) {
            _lastErrorMessage = [NSString stringWithFormat:@"Exception starting engine: %@", exception.reason];
            return AudioAvailabilityResultException;
        }
        
        return AudioAvailabilityResultAvailable;
        
    } @catch (NSException *exception) {
        _lastErrorMessage = [NSString stringWithFormat:@"Unexpected exception: %@", exception.reason];
        return AudioAvailabilityResultException;
    }
}

+ (nullable NSString *)lastErrorMessage {
    return [[AudioAvailabilityChecker alloc] init]->_lastErrorMessage;
}

@end
