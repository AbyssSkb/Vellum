#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP_NAME="${APP_NAME:-Vellum}"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.abyssskb.vellum}"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
SPARKLE_ARTIFACT_DIR="$ROOT_DIR/.build/artifacts/sparkle/Sparkle"
SPARKLE_PUBLIC_KEY="$(cat "$ROOT_DIR/Resources/UpdateSigningPublicKey.txt")"

cd "$ROOT_DIR"

if [ -z "${APP_VERSION:-}" ]; then
    APP_VERSION="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null | sed 's/^v//')"
    APP_VERSION="${APP_VERSION:-0.1.1}"
fi

CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache" \
    swift build --configuration "$BUILD_CONFIG" --arch arm64 --arch x86_64 --cache-path "$ROOT_DIR/.build/SwiftPMCache"
PRODUCT_DIR="$(CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache" swift build --configuration "$BUILD_CONFIG" --arch arm64 --arch x86_64 --cache-path "$ROOT_DIR/.build/SwiftPMCache" --show-bin-path)"
EXECUTABLE="$PRODUCT_DIR/Vellum"
/usr/bin/lipo "$EXECUTABLE" -verify_arch arm64 x86_64

SPARKLE_SOURCE="$SPARKLE_ARTIFACT_DIR/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
/usr/bin/lipo "$SPARKLE_SOURCE/Sparkle" -verify_arch arm64 x86_64

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

cp "$EXECUTABLE" "$MACOS_DIR/Vellum"
ditto "$SPARKLE_SOURCE" "$FRAMEWORKS_DIR/Sparkle.framework"

if command -v strip >/dev/null 2>&1; then
    strip -S -x "$MACOS_DIR/Vellum"
fi

ICONSET_DIR="$ROOT_DIR/.build/AppIcon.iconset"
SOURCE_ICON="$ROOT_DIR/Resources/AppIcon/icon.png"
rm -rf "$ICONSET_DIR"
CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache" \
    swift "$ROOT_DIR/scripts/make-app-icon.swift" "$ICONSET_DIR" "$SOURCE_ICON"
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleExecutable</key>
    <string>Vellum</string>
    <key>CFBundleIdentifier</key>
    <string>$APP_BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_VERSION</string>
    <key>SUFeedURL</key>
    <string>https://github.com/AbyssSkb/Vellum/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>$SPARKLE_PUBLIC_KEY</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUAutomaticallyUpdate</key>
    <true/>
    <key>SUAllowsAutomaticUpdates</key>
    <true/>
    <key>SUVerifyUpdateBeforeExtraction</key>
    <true/>
    <key>SURequireSignedFeed</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSQuitAlwaysKeepsWindows</key>
    <false/>
    <key>NSWindowRestoresWorkspaceAtLaunch</key>
    <false/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>PDF Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.adobe.pdf</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

printf "APPL????" > "$CONTENTS_DIR/PkgInfo"

if command -v codesign >/dev/null 2>&1; then
    SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
    SIGN_TIMESTAMP="--timestamp=none"
    if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
        SIGN_TIMESTAMP="--timestamp"
    fi

    SPARKLE_FRAMEWORK="$FRAMEWORKS_DIR/Sparkle.framework"
    SPARKLE_VERSION="$SPARKLE_FRAMEWORK/Versions/Current"
    codesign --force "$SIGN_TIMESTAMP" --options runtime --sign "$SIGN_IDENTITY" "$SPARKLE_VERSION/XPCServices/Installer.xpc" >/dev/null
    codesign --force "$SIGN_TIMESTAMP" --options runtime --preserve-metadata=entitlements --sign "$SIGN_IDENTITY" "$SPARKLE_VERSION/XPCServices/Downloader.xpc" >/dev/null
    codesign --force "$SIGN_TIMESTAMP" --options runtime --sign "$SIGN_IDENTITY" "$SPARKLE_VERSION/Autoupdate" >/dev/null
    codesign --force "$SIGN_TIMESTAMP" --options runtime --sign "$SIGN_IDENTITY" "$SPARKLE_VERSION/Updater.app" >/dev/null
    codesign --force "$SIGN_TIMESTAMP" --options runtime --sign "$SIGN_IDENTITY" "$SPARKLE_FRAMEWORK" >/dev/null

    if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
        codesign --force --timestamp --options runtime --sign "$CODE_SIGN_IDENTITY" "$APP_DIR" >/dev/null
    else
        codesign --force --sign - "$APP_DIR" >/dev/null
    fi
    codesign --verify --deep --strict "$APP_DIR"
fi

echo "$APP_DIR"
