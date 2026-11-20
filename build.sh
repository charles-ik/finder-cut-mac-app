#!/bin/zsh
# Builds and signs "Finder Cut.app" into ./build. Stable signing identity keeps the Accessibility grant across rebuilds.
set -e; cd "${0:A:h}"
APP="build/Finder Cut.app"; rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
swiftc -O main.swift -o "$APP/Contents/MacOS/FinderCut"
cp Info.plist "$APP/Contents/"
"$APP/Contents/MacOS/FinderCut" --selftest
codesign --force --options runtime --sign "Apple Development: chaikegwu@gmail.com (FAN762XX9J)" "$APP"
codesign --verify --strict "$APP" && echo "built $APP"
