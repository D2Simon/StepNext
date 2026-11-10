#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to an existing notarytool keychain profile}"
app="$ROOT/dist/拾序.app"
details="$(codesign -dv "$app" 2>&1)"
if [[ "$details" == *"Signature=adhoc"* ]]; then
  printf 'A Developer ID Application signed build is required. See docs/RELEASING.md.\n' >&2
  exit 1
fi
codesign --verify --deep --strict "$app"
submission="$(mktemp -d "$ROOT/.build/notary.XXXXXX")"
ditto -c -k --keepParent "$app" "$submission/submission.zip"
xcrun notarytool submit "$submission/submission.zip" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$submission/result.json"
python3 - "$submission/result.json" <<'PY'
import json, sys
result=json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization was not accepted; inspect ' + sys.argv[1])
PY
xcrun stapler staple "$app"
NOTARIZED=1 ./scripts/package.sh
