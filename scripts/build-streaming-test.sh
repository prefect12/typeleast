#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

INSTALL=false
if [[ "${1:-}" == "--install" ]]; then
  INSTALL=true
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--install]"
  exit 1
fi

APP_NAME="Typeleast Streaming Test"
BUNDLE_ID="com.typeleast.streaming-test"
SCRATCH_DIR="$ROOT_DIR/.build-streaming-test"
ARTIFACT_DIR="$ROOT_DIR/.artifacts/streaming-test"
APP_BUNDLE="$ARTIFACT_DIR/$APP_NAME.app"
INSTALL_PATH="/Applications/$APP_NAME.app"
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="${VERSION//./}99"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources/bin"

swift build \
  -c release \
  --scratch-path "$SCRATCH_DIR" \
  --arch arm64 \
  --arch x86_64 \
  -Xswiftc -D \
  -Xswiftc TYPELEAST_STREAMING_TEST

BINARY="$SCRATCH_DIR/apple/Products/Release/Typeleast"
test -x "$BINARY"
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/Typeleast"
if [[ -d "$SCRATCH_DIR/apple/Products/Release/Typeleast_Typeleast.bundle" ]]; then
  cp -R "$SCRATCH_DIR/apple/Products/Release/Typeleast_Typeleast.bundle" "$APP_BUNDLE/Contents/Resources/"
fi

for file in DashboardLogo.jpg; do
  [[ -f "Sources/Resources/$file" ]] && cp "Sources/Resources/$file" "$APP_BUNDLE/Contents/Resources/"
done
for file in parakeet_transcribe_pcm.py mlx_semantic_correct.py verify_parakeet.py verify_mlx.py ml_daemon.py; do
  [[ -f "Sources/$file" ]] && cp "Sources/$file" "$APP_BUNDLE/Contents/Resources/"
done
[[ -d Sources/ml ]] && cp -R Sources/ml "$APP_BUNDLE/Contents/Resources/"
[[ -f Sources/Resources/pyproject.toml ]] && cp Sources/Resources/pyproject.toml "$APP_BUNDLE/Contents/Resources/"
[[ -f Sources/Resources/uv.lock ]] && cp Sources/Resources/uv.lock "$APP_BUNDLE/Contents/Resources/"

if [[ -f Sources/Resources/bin/uv ]]; then
  cp Sources/Resources/bin/uv "$APP_BUNDLE/Contents/Resources/bin/uv"
elif command -v uv >/dev/null 2>&1; then
  cp "$(command -v uv)" "$APP_BUNDLE/Contents/Resources/bin/uv"
fi
[[ -f "$APP_BUNDLE/Contents/Resources/bin/uv" ]] && chmod +x "$APP_BUNDLE/Contents/Resources/bin/uv"

cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string '$APP_NAME'" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName '$APP_NAME'" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :NSSpeechRecognitionUsageDescription 'This isolated test build uses OpenAI Realtime transcription and does not use Apple Speech Recognition.'" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true

if [[ -f TypeleastIcon.png ]]; then
  "$SCRIPT_DIR/generate-icons.sh" >/dev/null
  iconutil -c icns Typeleast.iconset -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
  rm -rf Typeleast.iconset
fi

ENTITLEMENTS="$ARTIFACT_DIR/streaming-test.entitlements"
mkdir -p "$ARTIFACT_DIR"
cp Info.plist "$ENTITLEMENTS"
/usr/libexec/PlistBuddy -c 'Clear dict' "$ENTITLEMENTS"
/usr/libexec/PlistBuddy -c 'Add :com.apple.security.device.audio-input bool true' "$ENTITLEMENTS"
/usr/libexec/PlistBuddy -c 'Add :com.apple.security.network.client bool true' "$ENTITLEMENTS"

IDENTITY="$(security find-identity -v -p codesigning | awk '/"Typeleast Local Development"/ { print $2; exit }')"
if [[ -z "$IDENTITY" ]]; then
  echo "Typeleast Local Development signing identity is required"
  exit 1
fi

if [[ -f "$APP_BUNDLE/Contents/Resources/bin/uv" ]]; then
  codesign --force --sign "$IDENTITY" --options runtime --entitlements "$ENTITLEMENTS" "$APP_BUNDLE/Contents/Resources/bin/uv"
fi
codesign --force --deep --sign "$IDENTITY" --options runtime --entitlements "$ENTITLEMENTS" --identifier "$BUNDLE_ID" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

if [[ "$INSTALL" == true ]]; then
  while read -r pid; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done < <(pgrep -f '^/Applications/Typeleast Streaming Test\.app/Contents/MacOS/Typeleast$' || true)
  rm -rf "$INSTALL_PATH"
  ditto "$APP_BUNDLE" "$INSTALL_PATH"
  codesign --verify --deep --strict --verbose=2 "$INSTALL_PATH"
fi

echo "$APP_BUNDLE"
