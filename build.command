#!/bin/zsh
set -eu
cd "$(dirname "$0")"
mkdir -p LidTone.app/Contents/MacOS
cp Source/Info.plist LidTone.app/Contents/Info.plist
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=13.0 Source/main.m -o LidTone.app/Contents/MacOS/LidTone -framework Cocoa -framework AVFoundation -framework IOKit
codesign --force --sign - LidTone.app
echo 'LidTone.app 빌드 완료'
