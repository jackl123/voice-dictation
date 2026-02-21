#import "WhisperBridge.h"
#import "whisper.h"
#import <Foundation/Foundation.h>

@interface WhisperBridge ()
@property (nonatomic, assign) struct whisper_context *ctx;
@end

@implementation WhisperBridge

+ (nullable instancetype)bridgeWithModelPath:(NSString *)path {
    WhisperBridge *bridge = [[WhisperBridge alloc] init];

    struct whisper_context_params params = whisper_context_default_params();
    // CPU-only mode. The Metal backend in this Xcode build has incomplete
    // shader/runtime setup that causes ggml_abort. CPU on Apple Silicon
    // is fast enough for base.en and smaller models.
    params.use_gpu = false;

    struct whisper_context *ctx = whisper_init_from_file_with_params(path.UTF8String, params);
    if (ctx == NULL) {
        NSLog(@"[WhisperBridge] Failed to load model at path: %@", path);
        return nil;
    }

    bridge.ctx = ctx;
    return bridge;
}

- (void)dealloc {
    if (_ctx != NULL) {
        whisper_free(_ctx);
        _ctx = NULL;
    }
}

- (nullable NSString *)transcribeSamples:(const float *)samples
                                   count:(NSInteger)count
                                language:(nullable NSString *)language {
    if (_ctx == NULL || samples == NULL || count == 0) {
        return nil;
    }

    struct whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);

    // Language setting.
    const char *lang = (language != nil) ? language.UTF8String : "auto";
    params.language = lang;

    // Disable translations — we want the original spoken language.
    params.translate = false;

    // Print progress to stderr during development (disable for release).
    params.print_progress = false;
    params.print_timestamps = false;
    params.print_realtime = false;
    params.print_special = false;

    // Single-thread is fine for short clips; whisper handles multi-threading internally.
    params.n_threads = (int)MIN(4, [[NSProcessInfo processInfo] processorCount]);

    int result = whisper_full(_ctx, params, samples, (int)count);
    if (result != 0) {
        NSLog(@"[WhisperBridge] whisper_full returned error: %d", result);
        return nil;
    }

    int segmentCount = whisper_full_n_segments(_ctx);
    NSMutableString *transcript = [NSMutableString string];

    for (int i = 0; i < segmentCount; i++) {
        const char *text = whisper_full_get_segment_text(_ctx, i);
        if (text != NULL) {
            [transcript appendString:[NSString stringWithUTF8String:text]];
        }
    }

    return [transcript stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@end
