#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p .build dist
xcodebuild -checkFirstLaunchStatus
identity="${SIGN_IDENTITY:--}"
sign_flags=("ENABLE_HARDENED_RUNTIME=NO")
if [[ "$identity" != "-" ]]; then sign_flags=("ENABLE_HARDENED_RUNTIME=YES" "OTHER_CODE_SIGN_FLAGS=--options=runtime"); fi
xcodebuild -project 拾序.xcodeproj -scheme 拾序 -configuration Release \
  -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual \
  "CODE_SIGN_IDENTITY=$identity" "DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM:-}" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  "DEBUG_INFORMATION_FORMAT=dwarf-with-dsym" "SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO" \
  "${sign_flags[@]}" build
# Always use a fresh stage, so obsolete files cannot survive a rebuild.
stage="$(mktemp -d "$ROOT/.build/stage.XXXXXX")"
ditto .build/DerivedData/Build/Products/Release/拾序.app "$stage/拾序.app"
# Remove local debug paths from the distributed binaries, then sign inside out.
xcrun strip -S "$stage/拾序.app/Contents/MacOS/拾序"
xcrun strip -S "$stage/拾序.app/Contents/PlugIns/ShixuWidget.appex/Contents/MacOS/ShixuWidget"
sign_arguments=(--force --sign "$identity")
if [[ "$identity" != "-" ]]; then sign_arguments+=(--options runtime --timestamp); fi
codesign "${sign_arguments[@]}" --entitlements Config/LocalWidget.entitlements "$stage/拾序.app/Contents/PlugIns/ShixuWidget.appex"
codesign "${sign_arguments[@]}" --entitlements Config/LocalApp.entitlements "$stage/拾序.app"
codesign --verify --deep --strict "$stage/拾序.app"
python3 - "$stage/拾序.app" "$ROOT/dist/拾序.app" <<'PY'
from pathlib import Path
import sys, shutil, uuid
source, destination = map(Path, sys.argv[1:])
if destination.exists():
    destination.rename(destination.parent.parent / '.build' / ('previous-app-' + uuid.uuid4().hex + '.app'))
shutil.move(str(source), str(destination))
PY
printf '\nBuild ready: %s/dist/拾序.app\n' "$ROOT"
