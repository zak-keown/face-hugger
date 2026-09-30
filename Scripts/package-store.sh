#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

: "${FACEHUGGER_STORE_APP_IDENTITY:?Set a Mac App Store application signing identity}"
: "${FACEHUGGER_STORE_INSTALLER_IDENTITY:?Set a Mac App Store installer signing identity}"
: "${FACEHUGGER_STORE_PROFILE:?Set the installed Mac App Store provisioning profile name}"
: "${FACEHUGGER_TEAM_ID:?Set the Apple developer team ID}"

mkdir -p .build/store-package dist/store
xcodegen generate --spec project-store.yml
xcodebuild -project FaceHuggerStore.xcodeproj -scheme FaceHugger \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath .build/store-package/DerivedData \
    'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
    "CODE_SIGN_IDENTITY=$FACEHUGGER_STORE_APP_IDENTITY" \
    "PROVISIONING_PROFILE_SPECIFIER=$FACEHUGGER_STORE_PROFILE" \
    "DEVELOPMENT_TEAM=$FACEHUGGER_TEAM_ID" CODE_SIGN_STYLE=Manual \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    build > .build/store-package/build.log 2>&1 || {
        tail -n 40 .build/store-package/build.log >&2
        exit 1
    }
app='.build/store-package/DerivedData/Build/Products/Release/Face Hugger.app'
codesign --verify --strict --deep "$app"
test -f "$app/Contents/embedded.provisionprofile"
for architecture in arm64 x86_64; do
    lipo "$app/Contents/MacOS/Face Hugger" -verify_arch "$architecture"
done
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Contents/Info.plist")
output="dist/store/FaceHugger-$version-$build.pkg"
productbuild --component "$app" /Applications --sign "$FACEHUGGER_STORE_INSTALLER_IDENTITY" "$output"
pkgutil --check-signature "$output"
shasum -a 256 "$output" > "$output.sha256"
printf 'Store-signed package prepared: %s\nNo upload or submission was performed.\n' "$output"
