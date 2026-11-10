#!/usr/bin/env bash
# Vercel's build of the web app (lib/main_web.dart), with the Flutter
# version the Android release CI uses. Output: build/web (vercel.json).
set -euo pipefail

FLUTTER_VERSION="$(grep -m1 'FLUTTER_VERSION:' .github/workflows/android-release.yml \
  | sed -E 's/.*"([^"]+)".*/\1/')"
FLUTTER_DIR="${FLUTTER_HOME:-$HOME/flutter-$FLUTTER_VERSION}"

if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  git clone --quiet --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi
export PATH="$FLUTTER_DIR/bin:$PATH"

flutter config --no-analytics --enable-web >/dev/null
flutter --version
flutter pub get
flutter build web --release -t lib/main_web.dart --no-wasm-dry-run
