#!/bin/zsh
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
task_repo=thelordzeus/mac-monitor
task_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
task_arch="$(uname -m)"
task_slug=Mac-Pulse
task_commit="$(git rev-parse HEAD)"
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  print -u2 'Commit the completed code, notes and signed appcast before publishing.'
  exit 1
fi
task_remote="$(git ls-remote origin refs/heads/main | cut -f1)"
if [[ "$task_remote" != "$task_commit" ]]; then
  print -u2 'Push the completed release commit to main before publishing.'
  exit 1
fi
cmp appcast.xml dist/appcast.xml
python3 scripts/verify-appcast.py appcast.xml "dist/$task_slug-$task_arch.zip"
# Verify the app that users will receive, rather than a running local bundle
# whose Finder metadata may have changed during UI testing.
task_verify="$(mktemp -d "${TMPDIR:-/private/tmp}/mac-pulse-release-verify.XXXXXX")"
trap 'rm -rf "$task_verify"' EXIT
ditto -x -k "dist/$task_slug-$task_arch.zip" "$task_verify"
codesign --verify --deep --strict "$task_verify/Mac Pulse.app"
hdiutil verify "dist/$task_slug-$task_arch.dmg"
(cd dist && shasum -a 256 -c SHA256SUMS)
gh release create "v$task_version" --repo "$task_repo" --target "$task_commit" \
  --title "Mac Pulse $task_version" --notes-file "docs/releases/v$task_version.md" \
  --latest \
  "dist/$task_slug-$task_arch.dmg#Mac Pulse installer (DMG)" \
  "dist/$task_slug-$task_arch.zip#Mac Pulse app (ZIP)" \
  "dist/SHA256SUMS#SHA-256 checksums" \
  "dist/appcast.xml#Signed update feed"
gh release view "v$task_version" --repo "$task_repo" \
  --json tagName,targetCommitish,assets,url
