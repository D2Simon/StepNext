#!/bin/bash
# StepNext installer. Downloads a ready-built macOS app; Xcode is not required.
set -euo pipefail
DEFAULT_REPOSITORY="D2Simon/StepNext"
EXPECTED_BUNDLE_ID="local.shixu.app"

say() { printf 'StepNext: %s\n' "$*"; }
die() { printf 'StepNext: %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'TXT'
Usage: bash install.sh [options]
  --repo OWNER/REPO      GitHub release source (default: D2Simon/StepNext)
  --archive FILE.zip    Install an already-downloaded ZIP with adjacent .sha256
  --destination DIR     Application directory (default: /Applications, or ~/Applications)
  --no-open             Install without launching the app
  --no-register         Skip Launch Services and widget registration
  --help                Show help
No Xcode, Apple Developer account, sudo, or task-data upload is required.
TXT
}
valid_repo() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; }
json_get() { /usr/bin/plutil -extract "$2" raw -o - "$1" 2>/dev/null; }
# Prints URL, asset name, checksum URL, release tag, signing kind (one per line).
select_release_asset() {
  local metadata="$1" release asset name url tag draft checksum_url checksum_name kind
  local chosen_name chosen_url index checksum_index
  for ((release=0; release<20; release++)); do
    tag="$(json_get "$metadata" "$release.tag_name")" || break
    draft="$(json_get "$metadata" "$release.draft")" || continue
    [[ "$draft" == "true" ]] && continue
    for kind in notarized unnotarized adhoc; do
      chosen_name=""; chosen_url=""
      for ((asset=0; asset<200; asset++)); do
        name="$(json_get "$metadata" "$release.assets.$asset.name")" || break
        if [[ "$name" =~ ^StepNext-[A-Za-z0-9._-]+-macOS-arm64-${kind}\.zip$ ]]; then
          chosen_name="$name"
          chosen_url="$(json_get "$metadata" "$release.assets.$asset.browser_download_url")" || return 1
          break
        fi
      done
      [[ -n "$chosen_name" ]] || continue
      checksum_url=""
      for ((checksum_index=0; checksum_index<200; checksum_index++)); do
        checksum_name="$(json_get "$metadata" "$release.assets.$checksum_index.name")" || break
        if [[ "$checksum_name" == "$chosen_name.sha256" ]]; then
          checksum_url="$(json_get "$metadata" "$release.assets.$checksum_index.browser_download_url")" || return 1
          break
        fi
      done
      [[ -n "$checksum_url" ]] || continue
      printf '%s\n%s\n%s\n%s\n%s\n' "$chosen_url" "$chosen_name" "$checksum_url" "$tag" "$kind"
      return 0
    done
  done
  return 1
}
valid_download_url() { [[ "$1" == "https://github.com/$2/releases/download/"* && "$1" != *$'\n'* ]]; }
verify_checksum() {
  local archive="$1" checksum="$2" expected actual
  expected="$(/usr/bin/awk 'NR==1 {print $1}' "$checksum" | /usr/bin/tr '[:upper:]' '[:lower:]')"
  [[ "$expected" =~ ^[a-f0-9]{64}$ ]] || die "Invalid SHA-256 file. Nothing was installed."
  actual="$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || die "SHA-256 mismatch. Nothing was installed."
}
validate_zip_paths() {
  local archive="$1" entry
  /usr/bin/unzip -Z -1 "$archive" > "$work_dir/zip-entries.txt" || die "Invalid ZIP file."
  while IFS= read -r entry; do
    case "$entry" in /*|../*|*/../*|*/..|*\\*) die "Unsafe ZIP path. Nothing was installed.";; esac
  done < "$work_dir/zip-entries.txt"
}
fetch() { /usr/bin/curl --proto '=https' --tlsv1.2 --fail --location --retry 3 --connect-timeout 15 --max-time 600 --silent --show-error "$1" -o "$2"; }
cleanup() {
  # Only delete directories created by mktemp in this invocation; never the app or its data.
  if [[ -n "${staging:-}" && -d "$staging" && "${staging##*/}" == .stepnext-install.* ]]; then /bin/rm -r -- "$staging"; fi
  if [[ -n "${work_dir:-}" && -d "$work_dir" && "${work_dir##*/}" == stepnext-install.* ]]; then /bin/rm -r -- "$work_dir"; fi
}
main() {
  local repository="${STEPNEXT_REPO:-$DEFAULT_REPOSITORY}" archive="" destination="" launch=1 register=1
  local selection url asset checksum_url release kind version app_path target existing_id executable backup=""
  work_dir=""; staging=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo|--archive|--destination)
        [[ $# -ge 2 && -n "$2" ]] || die "Missing value for $1"
        case "$1" in --repo) repository="$2";; --archive) archive="$2";; --destination) destination="$2";; esac
        shift 2;;
      --no-open) launch=0; shift;;
      --no-register) register=0; shift;;
      --help|-h) usage; return 0;;
      *) die "Unknown option: $1 (use --help)";;
    esac
  done
  [[ "$(uname -s)" == "Darwin" ]] || die "macOS is required."
  [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" == "1" ]] || die "This release requires an Apple Silicon Mac."
  version="$(/usr/bin/sw_vers -productVersion)"
  [[ "${version%%.*}" -ge 14 ]] || die "macOS 14 or later is required."
  valid_repo "$repository" || die "Repository must be OWNER/REPO."
  if [[ -z "$destination" ]]; then
    if [[ -w /Applications ]]; then destination=/Applications; else destination="$HOME/Applications"; fi
  fi
  [[ "$destination" != / && -n "$destination" ]] || die "Choose an application directory."
  /bin/mkdir -p "$destination"
  destination="$(cd "$destination" && pwd -P)"
  target="$destination/StepNext.app"
  if [[ -e "$target" ]]; then
    existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target/Contents/Info.plist" 2>/dev/null || true)"
    [[ "$existing_id" == "$EXPECTED_BUNDLE_ID" ]] || die "A different app already exists at $target; it was not changed."
    executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$target/Contents/Info.plist")"
    if /bin/ps -axo comm= | /usr/bin/grep -F -x "$target/Contents/MacOS/$executable" >/dev/null; then
      die "Quit StepNext first, then run bash install.sh again. Your tasks were not changed."
    fi
  fi
  work_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/stepnext-install.XXXXXX")"
  trap cleanup EXIT
  if [[ -n "$archive" ]]; then
    [[ -f "$archive" && -f "$archive.sha256" ]] || die "Local ZIP and matching .sha256 are required."
    /bin/cp "$archive" "$work_dir/app.zip"
    /bin/cp "$archive.sha256" "$work_dir/app.sha256"
    case "${archive##*/}" in *-notarized.zip) kind=notarized;; *) kind=local-test;; esac
  else
    say "Looking for a release in $repository..."
    fetch "https://api.github.com/repos/$repository/releases?per_page=20" "$work_dir/releases.json" || die "Could not read GitHub releases. Check the repository and network."
    selection="$(select_release_asset "$work_dir/releases.json")" || die "No compatible release with a SHA-256 file was found. The maintainer must publish an arm64 app ZIP and checksum first."
    url="$(printf '%s\n' "$selection" | /usr/bin/sed -n '1p')"
    asset="$(printf '%s\n' "$selection" | /usr/bin/sed -n '2p')"
    checksum_url="$(printf '%s\n' "$selection" | /usr/bin/sed -n '3p')"
    release="$(printf '%s\n' "$selection" | /usr/bin/sed -n '4p')"
    kind="$(printf '%s\n' "$selection" | /usr/bin/sed -n '5p')"
    valid_download_url "$url" "$repository" && valid_download_url "$checksum_url" "$repository" || die "Unexpected download host or repository."
    say "Downloading $asset ($release)..."
    fetch "$url" "$work_dir/app.zip"
    fetch "$checksum_url" "$work_dir/app.sha256"
  fi
  verify_checksum "$work_dir/app.zip" "$work_dir/app.sha256"
  validate_zip_paths "$work_dir/app.zip"
  /usr/bin/ditto -x -k "$work_dir/app.zip" "$work_dir/unpacked"
  app_path="$work_dir/unpacked/StepNext.app"
  [[ -d "$app_path" && ! -L "$app_path" ]] || die "The ZIP does not contain StepNext.app."
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")" == "$EXPECTED_BUNDLE_ID" ]] || die "Unexpected application identifier."
  /usr/bin/codesign --verify --deep --strict "$app_path" || die "Application signature integrity check failed."
  if [[ "$kind" == notarized ]]; then /usr/sbin/spctl --assess --type execute "$app_path" || die "macOS did not approve this notarized release."; fi
  staging="$(/usr/bin/mktemp -d "$destination/.stepnext-install.XXXXXX")"
  /usr/bin/ditto "$app_path" "$staging/StepNext.app"
  /usr/bin/codesign --verify --deep --strict "$staging/StepNext.app"
  if [[ -e "$target" ]]; then
    backup="$destination/.StepNext-backup.$(/bin/date +%Y%m%d-%H%M%S).$$"
    /bin/mv "$target" "$backup"
  fi
  if ! /bin/mv "$staging/StepNext.app" "$target"; then
    [[ -z "$backup" ]] || /bin/mv "$backup" "$target"
    die "Could not finish installation; the previous app was restored."
  fi
  if [[ "$register" == 1 ]]; then
    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f "$target" || say "Launch Services registration was deferred."
    /usr/bin/pluginkit -a "$target/Contents/PlugIns/ShixuWidget.appex" || say "Open the app once to finish widget registration."
  fi
  say "Installed: $target"
  [[ -z "$backup" ]] || say "Previous app kept at: $backup"
  if [[ "$kind" != notarized ]]; then say "This is an unnotarized test build. macOS may block opening it; no security settings were changed."; fi
  if [[ "$launch" == 1 ]]; then /usr/bin/open "$target" || say "Open StepNext manually from Applications."; fi
  say "Add a widget: right-click the desktop > Edit Widgets > search StepNext."
  say "Your existing task data was not deleted or uploaded."
}
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
