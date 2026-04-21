#!/usr/bin/env bash
# build.sh — Compile and package Contexto.app
# Run setup_signing.sh first if you haven't already.

set -e

APP_NAME="Contexto"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
CERT_NAME="Contexto Developer"

ARCH=$(uname -m)
if   [ "$ARCH" = "arm64"  ]; then TARGET="arm64-apple-macos12.0"
elif [ "$ARCH" = "x86_64" ]; then TARGET="x86_64-apple-macos12.0"
else TARGET=""
fi

SDK=$(xcrun --show-sdk-path 2>/dev/null || echo "")

echo "==========================================="
echo "  Building $APP_NAME  ($ARCH)"
echo "==========================================="

# ── Clean ─────────────────────────────────────────────────────────────────────
echo "Cleaning previous build..."
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# ── Compile ───────────────────────────────────────────────────────────────────
echo "Compiling Swift sources..."
SWIFT_ARGS=(
    Sources/main.swift
    Sources/AppDelegate.swift
    Sources/AIService.swift
    Sources/BrowserService.swift
    Sources/DefinitionWindow.swift
    Sources/PreferencesWindow.swift
    -framework PDFKit
    -o "$MACOS_DIR/$APP_NAME"
)
[ -n "$TARGET" ] && SWIFT_ARGS+=(-target "$TARGET")
[ -n "$SDK"    ] && SWIFT_ARGS+=(-sdk    "$SDK")

swiftc "${SWIFT_ARGS[@]}"
echo "  Compiled successfully"

# ── Copy Info.plist ───────────────────────────────────────────────────────────
cp Resources/Info.plist "$CONTENTS/Info.plist"

# ── Generate icon ─────────────────────────────────────────────────────────────
echo "Generating icon..."
python3 create_icon.py > /dev/null
if command -v iconutil &>/dev/null; then
    iconutil -c icns AppIcon.iconset -o "$RESOURCES_DIR/AppIcon.icns"
fi
rm -rf AppIcon.iconset

# ── Sign ──────────────────────────────────────────────────────────────────────
echo "Signing..."
xattr -cr "$APP_BUNDLE"
find "$APP_BUNDLE" -name "._*"       -delete 2>/dev/null || true
find "$APP_BUNDLE" -name ".DS_Store" -delete 2>/dev/null || true

# Use the persistent developer certificate if it exists; otherwise ad-hoc.
if security find-identity -v -p codesigning \
        "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null \
        | grep -q "\"$CERT_NAME\""; then
    codesign --force --deep --sign "$CERT_NAME" "$APP_BUNDLE"
    echo "  Signed with persistent certificate (Accessibility permissions will be remembered)"
else
    codesign --force --deep --sign - "$APP_BUNDLE"
    echo "  Signed ad-hoc (run setup_signing.sh once to fix Accessibility permission resets)"
fi

echo ""
echo "==========================================="
echo "  Build complete: $APP_BUNDLE"
echo "==========================================="
echo ""
echo "Run ./install.sh to install and launch."
