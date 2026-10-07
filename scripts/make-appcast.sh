#!/bin/zsh
set -euo pipefail

task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
task_tools="$task_root/.build/artifacts/sparkle/Sparkle/bin"
task_account="${SPARKLE_KEY_ACCOUNT:-mac-pulse}"
task_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' Resources/Info.plist)"
task_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
task_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"
task_public="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Resources/Info.plist)"
task_app="$task_root/dist/$task_name.app"
task_slug="${task_name// /-}"
task_archive="$task_slug-$(uname -m).zip"

if [[ ! -x "$task_tools/generate_appcast" || ! -f "$task_root/dist/$task_archive" ]]; then
  print -u2 'Run ./scripts/build.sh and ./scripts/package.sh --skip-build first.'
  exit 1
fi
if [[ "$task_public" != "$("$task_tools/generate_keys" --account "$task_account" -p)" ]]; then
  print -u2 'The Keychain signing key does not match SUPublicEDKey. Do not replace a published update key.'
  exit 1
fi
if [[ "$task_version" != "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$task_app/Contents/Info.plist")" ||
      "$task_build" != "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$task_app/Contents/Info.plist")" ]]; then
  print -u2 'The packaged app is stale. Rebuild and repackage it before making the feed.'
  exit 1
fi

task_stage="$(mktemp -d "${TMPDIR:-/private/tmp}/mac-pulse-appcast.XXXXXX")"
trap 'rm -rf "$task_stage"' EXIT
cp "$task_root/dist/$task_archive" "$task_stage/$task_archive"
cp "$task_root/docs/releases/v$task_version.md" "$task_stage/${task_archive%.zip}.md"
if [[ -f "$task_root/appcast.xml" ]]; then
  cp "$task_root/appcast.xml" "$task_stage/appcast.xml"
fi
"$task_tools/generate_appcast" --account "$task_account" \
  --versions "$task_build" --maximum-versions 0 --maximum-deltas 0 \
  --download-url-prefix "https://github.com/thelordzeus/mac-monitor/releases/download/v$task_version/" \
  --link "https://github.com/thelordzeus/mac-monitor/releases/tag/v$task_version" \
  --embed-release-notes "$task_stage"
"$task_tools/sign_update" --account "$task_account" --verify "$task_stage/appcast.xml"
cp "$task_stage/appcast.xml" "$task_root/appcast.xml"
cp "$task_stage/appcast.xml" "$task_root/dist/appcast.xml"
python3 "$task_root/scripts/verify-appcast.py" "$task_root/appcast.xml" "$task_root/dist/$task_archive"
print "Signed appcast ready for Mac Pulse $task_version (build $task_build)."
