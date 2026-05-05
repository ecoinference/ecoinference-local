#!/usr/bin/env bash
# download_frameworks.sh
# Downloads the LiteRT-LM arm64 dylibs and wraps each one in an xcframework
# so Xcode can embed and sign them.
#
# Usage:
#   ./download_frameworks.sh
#
# Requirements:  curl, tar, xcodebuild (Xcode CLI tools)

set -euo pipefail

FRAMEWORKS_DIR="Frameworks"
TARBALL_URL="https://github.com/DenisovAV/flutter_gemma/releases/download/native-v0.10.2/litertlm-ios_arm64.tar.gz"
TARBALL="litertlm-ios_arm64.tar.gz"
EXTRACT_DIR="litertlm_extracted"

DYLIBS=(
    "libLiteRtLm.dylib"
    "libGemmaModelConstraintProvider.dylib"
    "libLiteRtMetalAccelerator.dylib"
    "libStreamProxy.dylib"
)

echo "==> Creating $FRAMEWORKS_DIR/"
mkdir -p "$FRAMEWORKS_DIR"

# ── Download ──────────────────────────────────────────────────────────────────

if [ ! -f "$TARBALL" ]; then
    echo "==> Downloading $TARBALL_URL …"
    curl -L -o "$TARBALL" "$TARBALL_URL"
else
    echo "==> Tarball already present, skipping download."
fi

# ── Extract ───────────────────────────────────────────────────────────────────

echo "==> Extracting …"
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"
tar -xzf "$TARBALL" -C "$EXTRACT_DIR"

# Find the directory that actually contains the dylibs (may be nested)
DYLIB_DIR=$(find "$EXTRACT_DIR" -name "libLiteRtLm.dylib" -exec dirname {} \; | head -1)
if [ -z "$DYLIB_DIR" ]; then
    echo "ERROR: libLiteRtLm.dylib not found in archive. Check the tarball structure."
    exit 1
fi
echo "    Found dylibs in: $DYLIB_DIR"

# ── Wrap each dylib in an xcframework ────────────────────────────────────────

for DYLIB in "${DYLIBS[@]}"; do
    SRC="$DYLIB_DIR/$DYLIB"
    if [ ! -f "$SRC" ]; then
        echo "WARNING: $DYLIB not found in archive, skipping."
        continue
    fi

    BASENAME="${DYLIB%.dylib}"
    XCFW="$FRAMEWORKS_DIR/${BASENAME}.xcframework"

    if [ -d "$XCFW" ]; then
        echo "==> $XCFW already exists, skipping."
        continue
    fi

    echo "==> Creating $XCFW …"

    # Wrap the dylib in a minimal .framework bundle first
    TMP_FW="$EXTRACT_DIR/${BASENAME}.framework"
    rm -rf "$TMP_FW"
    mkdir -p "$TMP_FW"
    cp "$SRC" "$TMP_FW/$BASENAME"

    # Fix the dylib install name so dyld resolves it via @rpath at runtime.
    # Without this the install name is an absolute build-time path and the app
    # crashes immediately with dyld __abort_with_payload on device.
    install_name_tool -id "@rpath/${BASENAME}.framework/${BASENAME}" \
        "$TMP_FW/$BASENAME"

    # Rewrite any cross-references between our dylibs from bare
    # "@rpath/libFoo.dylib" to "@rpath/libFoo.framework/libFoo".
    # libLiteRtLm references libGemmaModelConstraintProvider as a bare .dylib
    # which dyld cannot resolve once the library is wrapped in a .framework.
    for OTHER in "${DYLIBS[@]}"; do
        OTHER_BASE="${OTHER%.dylib}"
        OLD_REF="@rpath/${OTHER_BASE}.dylib"
        NEW_REF="@rpath/${OTHER_BASE}.framework/${OTHER_BASE}"
        # install_name_tool -change is a no-op if OLD_REF isn't present.
        install_name_tool -change "$OLD_REF" "$NEW_REF" "$TMP_FW/$BASENAME" 2>/dev/null || true
    done

    # Minimal Info.plist required by xcodebuild -create-xcframework.
    # CFBundleExecutable is mandatory — iOS installd rejects the bundle without it.
    cat > "$TMP_FW/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>        <string>${BASENAME}</string>
    <key>CFBundleIdentifier</key>        <string>com.google.ai.edge.${BASENAME}</string>
    <key>CFBundleName</key>              <string>${BASENAME}</string>
    <key>CFBundlePackageType</key>       <string>FMWK</string>
    <key>CFBundleShortVersionString</key><string>0.10.2</string>
    <key>CFBundleVersion</key>           <string>1</string>
    <key>MinimumOSVersion</key>          <string>17.0</string>
</dict>
</plist>
PLIST

    xcodebuild -create-xcframework \
        -framework "$TMP_FW" \
        -output "$XCFW"

    echo "    Created: $XCFW"
done

# ── Cleanup ───────────────────────────────────────────────────────────────────

echo "==> Cleaning up …"
rm -rf "$EXTRACT_DIR"

echo ""
echo "Done. xcframeworks are in ./$FRAMEWORKS_DIR/"
echo "Now run: xcodegen generate"
