#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/install.sh"
valid_repo D2Simon/StepNext
if valid_repo '../StepNext'; then exit 1; fi
if valid_repo 'owner/repo/extra'; then exit 1; fi
selected="$(select_release_asset "$ROOT/Tests/Fixtures/releases.json")"
[[ "$(printf '%s\n' "$selected" | sed -n '2p')" == 'StepNext-1.2.1-macOS-arm64-adhoc.zip' ]]
[[ "$(printf '%s\n' "$selected" | sed -n '4p')" == 'v1.2.1' ]]
valid_download_url 'https://github.com/D2Simon/StepNext/releases/download/v1.2.1/app.zip' 'D2Simon/StepNext'
if valid_download_url 'https://example.com/app.zip' 'D2Simon/StepNext'; then exit 1; fi
if valid_download_url 'https://github.com/other/repo/releases/download/v1/app.zip' 'D2Simon/StepNext'; then exit 1; fi
printf 'PASS: installer repository validation, prerelease selection, draft exclusion, download URL restrictions\n'
