#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SCRIPT_DIR/Info.plist")"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
BUILD_ROOT="${EDGE_APP_BUILD_ROOT:-$SCRIPT_DIR/dist/builds/$RUN_ID}"
APP_NAME="Spartan Build & Program.app"
APP_PATH="$BUILD_ROOT/$APP_NAME"
EXECUTABLE="$APP_PATH/Contents/MacOS/EdgeProgrammer"
RESOURCES="$APP_PATH/Contents/Resources"
ARCH_BUILD_ROOT="$BUILD_ROOT/arch"
APP_ZIP="$BUILD_ROOT/Spartan-Build-Program-macOS-$APP_VERSION.zip"
SHARE_FOLDER="$BUILD_ROOT/Spartan-Build-Program-macOS-$APP_VERSION"
SHARE_ZIP="$BUILD_ROOT/Spartan-Build-Program-macOS-$APP_VERSION-with-guide.zip"
SIGNING_IDENTITY="${EDGE_CODESIGN_IDENTITY:--}"
NOTARY_PROFILE="${EDGE_NOTARY_PROFILE:-}"

if [[ -n "$NOTARY_PROFILE" && "$SIGNING_IDENTITY" == "-" ]]; then
  print -u2 "Notarization ต้องใช้ Developer ID Application ผ่าน EDGE_CODESIGN_IDENTITY"
  exit 2
fi

xcrun --find swiftc >/dev/null

if [[ "$BUILD_ROOT" == "/" ]]; then
  print -u2 "ไม่อนุญาตให้ใช้ / เป็น Build root"
  exit 2
fi

if [[ -e "$BUILD_ROOT" ]]; then
  print -u2 "หยุดเพื่อป้องกันการเขียนทับ: $BUILD_ROOT (เลือก Build root ใหม่)"
  exit 3
fi

mkdir -p "$APP_PATH/Contents/MacOS" "$RESOURCES"

for ARCH in arm64 x86_64; do
  ARCH_ROOT="$ARCH_BUILD_ROOT/$ARCH"
  MODULE_CACHE="$ARCH_ROOT/module-cache"
  ARCH_EXECUTABLE="$ARCH_ROOT/EdgeProgrammer"
  mkdir -p "$MODULE_CACHE"

  CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
  SWIFT_MODULECACHE_PATH="$MODULE_CACHE" \
  xcrun --sdk macosx swiftc -parse-as-library \
    -O \
    -whole-module-optimization \
    -target "$ARCH-apple-macos13.0" \
    "$SCRIPT_DIR/EdgeProgrammer.swift" \
    "$SCRIPT_DIR/VHDLSupport.swift" \
    "$SCRIPT_DIR/PinMappingSupport.swift" \
    "$SCRIPT_DIR/LogSupport.swift" \
    "$SCRIPT_DIR/BuildNotifications.swift" \
    "$SCRIPT_DIR/LocalBuild.swift" \
    "$SCRIPT_DIR/SetupGuide.swift" \
    -o "$ARCH_EXECUTABLE"
done

lipo -create \
  "$ARCH_BUILD_ROOT/arm64/EdgeProgrammer" \
  "$ARCH_BUILD_ROOT/x86_64/EdgeProgrammer" \
  -output "$EXECUTABLE"
lipo -info "$EXECUTABLE"

cp "$SCRIPT_DIR/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$SCRIPT_DIR/AppIcon.png" "$RESOURCES/AppIcon.png"
cp "$SCRIPT_DIR/edge-spartan7.json" "$RESOURCES/edge-spartan7.json"
cp "$SCRIPT_DIR/LICENSE" "$SCRIPT_DIR/THIRD_PARTY_NOTICES.md" "$RESOURCES/"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP_PATH"
  print "SIGNING=ad-hoc (not notarized; ดูคู่มือติดตั้งเรื่อง Gatekeeper)"
else
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_PATH"
  print "SIGNING=Developer ID"
fi

"$EXECUTABLE" --self-test
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ditto -c -k --sequesterRsrc --keepParent \
  "$APP_PATH" "$APP_ZIP"

if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
  spctl --assess --type execute --verbose=2 "$APP_PATH"
  ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$APP_ZIP"
fi

mkdir -p "$SHARE_FOLDER"
ditto "$APP_PATH" "$SHARE_FOLDER/$APP_NAME"
cp "$SCRIPT_DIR/README.md" "$SCRIPT_DIR/INSTALL_MANUAL_TH.md" \
  "$SCRIPT_DIR/LICENSE" "$SCRIPT_DIR/THIRD_PARTY_NOTICES.md" "$SHARE_FOLDER/"
ditto "$SCRIPT_DIR/docs" "$SHARE_FOLDER/docs"
ditto "$SCRIPT_DIR/examples" "$SHARE_FOLDER/examples"
ditto -c -k --sequesterRsrc --keepParent "$SHARE_FOLDER" "$SHARE_ZIP"

(
  cd "$BUILD_ROOT"
  shasum -a 256 "${APP_ZIP:t}" "${SHARE_ZIP:t}" > SHA256SUMS.txt
)

print "APP_PATH=$APP_PATH"
print "ZIP_PATH=$APP_ZIP"
print "SHARE_ZIP_PATH=$SHARE_ZIP"
print "CHECKSUMS_PATH=$BUILD_ROOT/SHA256SUMS.txt"
