#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
project_dir="$PWD"
version="${1:-1.1.0}"
architecture="$(uname -m)"
export MACOSX_DEPLOYMENT_TARGET=14.0

swift build -c release
swift_bin="$(swift build -c release --show-bin-path)"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
app="$stage/BodianLyrics.app"
contents="$app/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources" "$contents/Library/LaunchAgents"
cp "$swift_bin/BodianLyrics" "$contents/MacOS/BodianLyrics"
cp "$swift_bin/BodianEngine" "$contents/MacOS/bodian-lyrics-engine"
xcrun clang -dynamiclib -fobjc-arc -O2 -mmacosx-version-min=14.0 -framework Foundation \
    -o "$contents/Resources/libnowplaying.dylib" native/nowplaying.m
cp native/nowplaying.pl LICENSE "$contents/Resources/"
cp packaging/me.taulee.bodianlyrics.engine.plist "$contents/Library/LaunchAgents/"

cat > "$contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>BodianLyrics</string>
    <key>CFBundleIdentifier</key><string>me.taulee.bodianlyrics</string>
    <key>CFBundleName</key><string>Bodian Lyrics</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$contents/MacOS/bodian-lyrics-engine"
codesign --force --sign - "$contents/Resources/libnowplaying.dylib"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"

mkdir -p "$project_dir/dist"
image="$project_dir/dist/BodianLyrics-$version-macos-$architecture.dmg"
ln -s /Applications "$stage/Applications"
hdiutil create -ov -srcfolder "$stage" -volname "Bodian Lyrics" -format UDZO "$image"
printf '%s\n' "$image"
