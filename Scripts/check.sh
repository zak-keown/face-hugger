#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

case "${1:-}" in
  ""|--build) ;;
  *) echo "Usage: Scripts/check.sh [--build]" >&2; exit 2 ;;
esac

swift test
python3 -m unittest discover -s TestsPython -v

if [ "${1:-}" = "--build" ]; then
  xcodegen generate
  xcodebuild -project FaceHugger.xcodeproj -scheme FaceHugger \
    -configuration Debug -derivedDataPath .build/xcode build CODE_SIGN_IDENTITY=-
fi
