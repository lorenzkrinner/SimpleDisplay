#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
# This Mac's 27.0 command-line SDK omits SwiftUIMacros; 26.5 builds the same sources.
preview_sdk="${SIMPLEDISPLAY_SDK_PATH:-$(xcrun --show-sdk-path)}"
if [[ -z "${SIMPLEDISPLAY_SDK_PATH:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
    preview_sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
preview_identity="${SIMPLEDISPLAY_SIGN_IDENTITY:--}"
swift build -c release --sdk "$preview_sdk" --product SimpleDisplay
preview_bin_dir="$(swift build -c release --sdk "$preview_sdk" --show-bin-path)"
preview_bundle="$PWD/.build/local-preview/SimpleDisplay.app"
mkdir -p "$preview_bundle/Contents/MacOS" "$preview_bundle/Contents/Resources"
cp "$preview_bin_dir/SimpleDisplay" "$preview_bundle/Contents/MacOS/SimpleDisplay"
cp Info.plist "$preview_bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 1.6.6-preview5' "$preview_bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 1.6.6.5' "$preview_bundle/Contents/Info.plist"
cp branding/assets/AppIcon.icns "$preview_bundle/Contents/Resources/AppIcon.icns"
ditto "$preview_bin_dir/SimpleDisplay_SimpleDisplay.bundle" "$preview_bundle/Contents/Resources/SimpleDisplay_SimpleDisplay.bundle"
codesign --force --sign "$preview_identity" --options runtime --entitlements Entitlements.plist "$preview_bundle"
codesign --verify --deep --strict "$preview_bundle"
printf 'Built local preview: %s\n' "$preview_bundle"
