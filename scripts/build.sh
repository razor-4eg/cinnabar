#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "→ icon"
mkdir -p build Resources
swift scripts/make-icon.swift "$ROOT/build/icon-1024.png"
ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ROOT/build/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$ROOT/build/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"

echo "→ compile"
swift build -c release

APP="$ROOT/build/Lumen.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/Lumen" "$APP/Contents/MacOS/Lumen"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/HelperInfo.plist" "$APP/Contents/Resources/HelperInfo.plist"
for lproj in "$ROOT"/Resources/*.lproj; do
  cp -R "$lproj" "$APP/Contents/Resources/"
done
chmod +x "$APP/Contents/MacOS/Lumen"
codesign --force --sign - --identifier app.lumen.downloader "$APP/Contents/MacOS/Lumen"

YTDLP="${HOME}/Library/Application Support/Lumen/bin"
if [[ -x "$YTDLP/yt-dlp" && -e "$YTDLP/_internal/Python" ]]; then
  echo "→ embed yt-dlp"
  HELPER="$APP/Contents/Helpers/YtDlp.app"
  mkdir -p "$HELPER/Contents/MacOS" "$HELPER/Contents/Resources"
  cp "$ROOT/Resources/HelperInfo.plist" "$HELPER/Contents/Info.plist"
  cp "$ROOT/Resources/AppIcon.icns" "$HELPER/Contents/Resources/AppIcon.icns"
  SIGNED="$(mktemp)"
  cp "$YTDLP/yt-dlp" "$SIGNED"
  codesign --force --sign - --identifier app.lumen.downloader.ytdlp "$SIGNED"
  cp "$SIGNED" "$HELPER/Contents/MacOS/yt-dlp"
  rm -f "$SIGNED"
  rm -rf "$HELPER/Contents/MacOS/_internal"
  cp -R "$YTDLP/_internal" "$HELPER/Contents/MacOS/_internal"
  chmod +x "$HELPER/Contents/MacOS/yt-dlp"
  ln -sfn "MacOS/_internal" "$HELPER/Contents/Frameworks"
  xattr -dr com.apple.quarantine "$HELPER" || true
fi

codesign --force --sign - --identifier app.lumen.downloader "$APP" || true

echo "→ $APP"
