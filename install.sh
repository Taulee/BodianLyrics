#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
app="$HOME/Applications/BodianLyrics.app"
agents="$HOME/Library/LaunchAgents"
data="$HOME/Library/Application Support/Bodian Lyrics"
label="me.taulee.bodianlyrics.engine"
plist="$agents/$label.plist"
domain="gui/$(id -u)"

mkdir -p "$HOME/Applications" "$agents" "$data"
if launchctl print "$domain/$label" >/dev/null 2>&1; then
    launchctl bootout "$domain/$label"
fi
ditto BodianLyrics.app "$app"

stage="$(mktemp "$agents/.bodian-lyrics.XXXXXXXX")"
trap 'rm -f "$stage"' EXIT
plutil -create xml1 "$stage"
plutil -insert Label -string "$label" "$stage"
plutil -insert ProgramArguments -json '[]' "$stage"
plutil -insert ProgramArguments.0 -string "$app/Contents/MacOS/bodian-lyrics-engine" "$stage"
plutil -insert ProgramArguments.1 -string "$app" "$stage"
plutil -insert RunAtLoad -bool YES "$stage"
plutil -insert KeepAlive -bool YES "$stage"
plutil -insert StandardErrorPath -string "$data/engine.log" "$stage"
mv "$stage" "$plist"

launchctl bootstrap "$domain" "$plist"
open "$app" --args --settings
