#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/MacCare.app"
ICONSET="$BUILD/AppIcon.iconset"
SOURCE_ICON="$ROOT/icon/android-chrome-512x512.png"

[[ -f "$SOURCE_ICON" ]] || { echo "Missing supplied icon: $SOURCE_ICON" >&2; exit 1; }
plutil -lint "$ROOT/Resources/Info.plist" >/dev/null

cd "$ROOT"
swift build -c release --product MacCare
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"
cp "$BIN_DIR/MacCare" "$APP/Contents/MacOS/MacCare"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

make_icon() {
    local size="$1"
    local output="$2"
    sips -z "$size" "$size" "$SOURCE_ICON" --out "$ICONSET/$output" >/dev/null
}
make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

printf '%s\n' "$APP"
