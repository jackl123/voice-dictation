//
// VoiceDictation-Bridging-Header.h
// Exposes Obj-C and C headers to Swift.
//

// whisper.cpp C API — exposed via the WhisperBridge Obj-C wrapper.
// The direct whisper.h include is only needed if you ever call the C API from Swift directly.
// Normally it is included only in WhisperBridge.mm (Obj-C++).
// #include "whisper.h"

// Obj-C++ bridge to whisper.cpp — this IS needed by Swift.
#import "WhisperBridge.h"
