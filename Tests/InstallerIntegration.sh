#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
archive="${1:?Pass the built StepNext ZIP}"
archive="$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")"
mkdir -p "$ROOT/.build"
test_root="$(mktemp -d "$ROOT/.build/installer-test.XXXXXX")"
trap '[[ ! -d "$test_root" ]] || /bin/rm -r -- "$test_root"' EXIT
bash "$ROOT/install.sh" --archive "$archive" --destination "$test_root/Applications with spaces" --no-open --no-register > "$test_root/install.log"
app="$test_root/Applications with spaces/StepNext.app"
[[ -d "$app/Contents/PlugIns/ShixuWidget.appex" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == local.shixu.app ]]
codesign --verify --deep --strict "$app"
bash "$ROOT/install.sh" --archive "$archive" --destination "$test_root/Applications with spaces" --no-open --no-register > "$test_root/update.log"
find "$test_root/Applications with spaces" -maxdepth 1 -name '.StepNext-backup.*' | grep . >/dev/null
cp "$archive" "$test_root/corrupt.zip"
printf '%064d  corrupt.zip\n' 0 > "$test_root/corrupt.zip.sha256"
if bash "$ROOT/install.sh" --archive "$test_root/corrupt.zip" --destination "$test_root/Bad checksum" --no-open --no-register > "$test_root/hash.log" 2>&1; then
  printf 'FAIL: invalid checksum accepted\n' >&2; exit 1
fi
[[ ! -e "$test_root/Bad checksum/StepNext.app" ]]
mkdir -p "$test_root/Other app/StepNext.app/Contents"
/usr/bin/plutil -create xml1 "$test_root/Other app/StepNext.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.example.other-app' "$test_root/Other app/StepNext.app/Contents/Info.plist"
if bash "$ROOT/install.sh" --archive "$archive" --destination "$test_root/Other app" --no-open --no-register > "$test_root/other.log" 2>&1; then
  printf 'FAIL: unrelated app replaced\n' >&2; exit 1
fi
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$test_root/Other app/StepNext.app/Contents/Info.plist")" == com.example.other-app ]]
printf 'PASS: installer ZIP install, paths with spaces, update backup, checksum rejection, unrelated-app protection\n'
