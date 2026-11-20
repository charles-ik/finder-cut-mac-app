#!/bin/zsh
# Builds and signs "Finder Cut.app" into ./build. Stable signing identity keeps the Accessibility grant across rebuilds.
set -e; cd "${0:A:h}"
APP="build/Finder Cut.app"; rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
swiftc -O main.swift -o "$APP/Contents/MacOS/FinderCut"
cp Info.plist "$APP/Contents/"
"$APP/Contents/MacOS/FinderCut" --selftest
# Use the first Apple Development identity; fall back to ad-hoc (then Accessibility must be re-granted after each rebuild).
ID=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')
codesign --force --options runtime --sign "${ID:--}" "$APP"
codesign --verify --strict "$APP" && echo "built $APP"
