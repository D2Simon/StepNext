#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
app="$ROOT/dist/拾序.app"
codesign --verify --deep --strict "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
kind=unnotarized
details="$(codesign -dv "$app" 2>&1)"
if [[ "$details" == *"Signature=adhoc"* ]]; then kind=adhoc; fi
if [[ "${NOTARIZED:-0}" == "1" ]]; then xcrun stapler validate "$app"; kind=notarized; fi
stage="$(mktemp -d "$ROOT/.build/package.XXXXXX")"
ditto "$app" "$stage/StepNext.app"
cp LICENSE "$stage/LICENSE"
cp docs/INSTALL.zh-CN.md "$stage/安装说明.md"
name="StepNext-${version}-macOS-arm64-${kind}.zip"
ditto -c -k --sequesterRsrc "$stage" "$ROOT/dist/$name"
(cd dist && shasum -a 256 "$name" > "$name.sha256")
printf 'Package: %s/dist/%s\n' "$ROOT" "$name"
