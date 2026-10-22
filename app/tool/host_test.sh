#!/bin/sh
# Run the Dart/Flutter unit tests on this Mac (host), including the native
# OpenCV detector tests. Works with only the Command Line Tools installed.
#   tool/host_test.sh [flutter test args...]
set -e
cd "$(dirname "$0")/.."
TOOLS="${BUILDTOOLS:-$HOME/development/buildtools/bin}"   # cmake + ninja (pip install cmake ninja)
if [ ! -x /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild ]; then
  PATH="$PWD/tool/host_shims:$PATH"
fi
PATH="$TOOLS:$PATH" exec flutter test "$@"
