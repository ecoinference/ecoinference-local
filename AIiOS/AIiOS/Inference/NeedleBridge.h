// NeedleBridge.h
// Thin ObjC wrapper over the Cactus Needle 3 C API for NeedleEmbedder.swift.
//
// Kept as a separate compilation unit (app target only) so the standalone
// AIiOSTests target never links the engine: this header is pure declarations,
// and when needle.h is not vendored (fresh clone — run fetch_needle.sh) the
// implementation compiles down to an "unavailable" stub, which makes
// NeedleEmbedder fail open to keyword facts. Design: docs/ROUTING.md §4.
//
// The needle API is one process-global, NOT thread-safe model; callers
// (NeedleEmbedder) serialize every call through a private queue.

#ifndef NeedleBridge_h
#define NeedleBridge_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NeedleBridge : NSObject

/// Loads the .cact weights and initializes the engine.
/// Returns the embedding dimension (> 0) on success; negative on failure —
/// call +lastErrorMessage for the reason.
+ (NSInteger)loadModelFromData:(NSData *)cact;

/// Embeds one text into `out` (capacity floats). Returns 0 on success,
/// negative on failure (+lastErrorMessage has the reason). Passing a NULL
/// `out` returns the model's embedding dimension without computing.
+ (NSInteger)embedText:(NSString *)text
                  into:(nullable float *)out
              capacity:(NSInteger)capacity;

/// Last process-global engine error (empty string when none/unavailable).
+ (NSString *)lastErrorMessage;

/// Releases engine state. Not used in production (engine lives for the
/// process lifetime); exposed for parity with the C API.
+ (void)reset;

@end

NS_ASSUME_NONNULL_END

#endif /* NeedleBridge_h */
