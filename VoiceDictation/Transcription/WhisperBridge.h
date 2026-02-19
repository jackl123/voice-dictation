#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Objective-C++ wrapper around the whisper.cpp C API.
/// This class is the only place in the project that touches whisper.cpp directly,
/// keeping all C++ complexity isolated from Swift.
@interface WhisperBridge : NSObject

/// Load a whisper model from the given file path (ggml format).
/// Returns nil if the model cannot be loaded.
+ (nullable instancetype)bridgeWithModelPath:(NSString *)path;

/// Transcribe raw 16 kHz mono Float32 PCM samples.
/// @param samples  Pointer to the sample array.
/// @param count    Number of samples.
/// @param language BCP-47 language code, e.g. "en". Pass nil to auto-detect.
/// @returns The transcribed text, or nil on failure.
- (nullable NSString *)transcribeSamples:(const float *)samples
                                   count:(NSInteger)count
                                language:(nullable NSString *)language;

@end

NS_ASSUME_NONNULL_END
