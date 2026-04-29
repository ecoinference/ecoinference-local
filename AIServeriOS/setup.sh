#!/usr/bin/env bash
# setup.sh — one-shot setup for AIServeriOS
# Run once after cloning.
#
# What it does:
#   1. Checks for required tools (xcodegen, curl, xcodebuild)
#   2. Downloads LiteRT-LM dylibs and wraps them in xcframeworks
#   3. Generates the Xcode project with XcodeGen
#
# Usage:
#   chmod +x setup.sh download_frameworks.sh
#   ./setup.sh

set -euo pipefail

cd "$(dirname "$0")"

echo "======================================================"
echo " AIServeriOS  Setup"
echo "======================================================"

# ── Check dependencies ────────────────────────────────────────────────────────

check() {
    if ! command -v "$1" &>/dev/null; then
        echo "ERROR: '$1' not found."
        echo "$2"
        exit 1
    fi
}

check xcodegen  "Install via: brew install xcodegen"
check curl      "Install Xcode Command Line Tools: xcode-select --install"
check xcodebuild "Install Xcode from the App Store."

echo ""

# ── Download & wrap frameworks ────────────────────────────────────────────────

echo "[1/2] Downloading LiteRT-LM frameworks …"
chmod +x download_frameworks.sh
./download_frameworks.sh

echo ""

# ── Generate Xcode project ────────────────────────────────────────────────────

echo "[2/2] Generating Xcode project …"
xcodegen generate

echo ""
echo "======================================================"
echo " Setup complete!"
echo " Open AIServeriOS.xcodeproj in Xcode."
echo " Set your Team ID in project.yml (DEVELOPMENT_TEAM)"
echo " before archiving for a real device."
echo "======================================================"
