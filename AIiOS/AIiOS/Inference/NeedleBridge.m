// NeedleBridge.m — see NeedleBridge.h. The engine is vendored by
// fetch_needle.sh into Frameworks/Needle.xcframework (+ Frameworks/Needle/
// needle.h on the header search path); without it every entry point reports
// unavailable and the router fails open to keyword facts.

#import "NeedleBridge.h"

#if __has_include("needle.h")
#include "needle.h"
#define ECO_NEEDLE_ENGINE 1
#endif

static NSString *const kUnavailable =
    @"needle engine not vendored (run fetch_needle.sh)";

@implementation NeedleBridge

+ (NSInteger)loadModelFromData:(NSData *)cact {
#ifndef ECO_NEEDLE_ENGINE
    (void)cact;
    return -100;
#else
    if (needle_load((const unsigned char *)cact.bytes,
                    (unsigned long long)cact.length) < 0) {
        return -1;
    }
    // Same two-step init as the probe harness (needle-probe/embedder.c):
    // empty system prompt first, minimal fallback for builds that reject it.
    if (needle_init("", "[]", NULL) < 0) {
        if (needle_init("You are an embedding engine.", "[]", NULL) < 0) {
            return -2;
        }
    }
    int dim = needle_embed("dim?", NULL, 0);
    return dim > 0 ? (NSInteger)dim : -3;
#endif
}

+ (NSInteger)embedText:(NSString *)text
                  into:(float *)out
              capacity:(NSInteger)capacity {
#ifndef ECO_NEEDLE_ENGINE
    (void)text; (void)out; (void)capacity;
    return -100;
#else
    return (NSInteger)needle_embed([text UTF8String], out, (int)capacity);
#endif
}

+ (NSString *)lastErrorMessage {
#ifndef ECO_NEEDLE_ENGINE
    return kUnavailable;
#else
    const char *e = needle_last_error();
    return e ? [NSString stringWithUTF8String:e] : kUnavailable;
#endif
}

+ (void)reset {
#ifdef ECO_NEEDLE_ENGINE
    needle_reset();
#endif
}

@end
