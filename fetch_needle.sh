#!/usr/bin/env bash
# Fetches the Cactus Needle 3 engine + weights and installs them for both
# mobile platforms. Same policy as AIiOS/download_frameworks.sh: binaries are
# NEVER committed (see .gitignore / the 2026-08-20 history purge) — run this
# after cloning, before building the apps.
#
# Source: huggingface.co/Cactus-Compute/needle3 (Apache 2.0 — see NOTICE).
# Set NEEDLE_SRC_DIR to install from a local directory holding the platform
# subfolders (ios-arm64/, ios-sim-arm64/, android-arm64/) instead of downloading.
#
# Installs:
#   AIiOS/Frameworks/Needle.xcframework     (ios-arm64 + ios-sim-arm64 static libs)
#   AIiOS/Frameworks/Needle/needle.h        (header search path for NeedleBridge.m)
#   AIiOS/Frameworks/needle3.cact           (weights, bundled as an app resource)
#   AIAndroid/app/src/main/cpp/needle/arm64-v8a/{libneedle.a,needle.h}
#   AIAndroid/app/src/main/assets/needle3.cact
set -euo pipefail
cd "$(dirname "$0")"

REPO="https://huggingface.co/Cactus-Compute/needle3/resolve/main"
PLATFORMS=(ios-arm64 ios-sim-arm64 android-arm64)
FILES=(libneedle.a needle.h needle3.cact)
CACHE="${NEEDLE_SRC_DIR:-.cache-needle}"

fetch() { # fetch <platform> <file> -> echoes local path
    local dest="$CACHE/$1/$2"
    if [ -n "${NEEDLE_SRC_DIR:-}" ]; then
        [ -f "$dest" ] || { echo "missing $dest in NEEDLE_SRC_DIR" >&2; exit 1; }
    elif [ ! -f "$dest" ]; then
        mkdir -p "$CACHE/$1"
        echo "downloading $1/$2 ..."
        curl -fL --retry 3 -o "$dest" "$REPO/$1/$2"
    fi
    echo "$dest"
}

# ── iOS ──────────────────────────────────────────────────────────────────────
mkdir -p AIiOS/Frameworks/Needle
for p in ios-arm64 ios-sim-arm64; do
    fetch "$p" needle.h >/dev/null
    cp "$CACHE/$p/needle.h" AIiOS/Frameworks/Needle/needle.h
done
rm -rf AIiOS/Frameworks/Needle.xcframework
xcodebuild -create-xcframework \
    -library "$(fetch ios-arm64 libneedle.a)"     -headers AIiOS/Frameworks/Needle \
    -library "$(fetch ios-sim-arm64 libneedle.a)" -headers AIiOS/Frameworks/Needle \
    -output AIiOS/Frameworks/Needle.xcframework >/dev/null
cp "$(fetch ios-arm64 needle3.cact)" AIiOS/Frameworks/needle3.cact
echo "iOS: Needle.xcframework + needle3.cact installed"

# ── Android ──────────────────────────────────────────────────────────────────
mkdir -p AIAndroid/app/src/main/cpp/needle/arm64-v8a AIAndroid/app/src/main/assets
cp "$(fetch android-arm64 libneedle.a)" AIAndroid/app/src/main/cpp/needle/arm64-v8a/libneedle.a
cp "$(fetch android-arm64 needle.h)"    AIAndroid/app/src/main/cpp/needle/arm64-v8a/needle.h
cp "$(fetch android-arm64 needle3.cact)" AIAndroid/app/src/main/assets/needle3.cact
echo "Android: cpp/needle/arm64-v8a + assets/needle3.cact installed"

echo "done. (x86_64 emulator builds compile a stub JNI and the router fails open to keyword facts.)"
