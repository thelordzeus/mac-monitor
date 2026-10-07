#!/bin/zsh
set -euo pipefail

task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
if [[ "${1:-}" != "--skip-build" ]]; then
  ./scripts/build.sh
fi

task_app="$task_root/dist/Mac Monitor.app"
if [[ ! -x "$task_app/Contents/MacOS/MacMonitor" ]]; then
  print -u2 'Build the app first with ./scripts/build.sh.'
  exit 1
fi

task_arch="$(uname -m)"
task_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$task_app/Contents/Info.plist")"
task_stage="$(mktemp -d "${TMPDIR:-/private/tmp}/mac-monitor-release.XXXXXX")"
trap 'rm -rf "$task_stage"' EXIT
mkdir -p "$task_stage/image"
ditto --norsrc --noextattr "$task_app" "$task_stage/image/Mac Monitor.app"
xattr -cr "$task_stage/image/Mac Monitor.app"
codesign --verify --deep --strict "$task_stage/image/Mac Monitor.app"
ln -s /Applications "$task_stage/image/Applications"
cp "$task_root/docs/INSTALL.txt" "$task_stage/image/Install Mac Monitor.txt"

task_dmg="$task_root/dist/Mac-Monitor-$task_arch.dmg"
task_zip="$task_root/dist/Mac-Monitor-$task_arch.zip"
hdiutil create -ov -volname "Mac Monitor $task_version" -fs HFS+ -format UDZO \
  -srcfolder "$task_stage/image" "$task_dmg"
hdiutil verify "$task_dmg"
ditto --norsrc --noextattr -c -k --keepParent \
  "$task_stage/image/Mac Monitor.app" "$task_zip"
cp "$task_zip" "$task_root/dist/Mac-Monitor.zip"
(
  cd "$task_root/dist"
  shasum -a 256 "Mac-Monitor-$task_arch.dmg" "Mac-Monitor-$task_arch.zip" > SHA256SUMS
)
printf 'Release %s (%s) ready:\n%s\n%s\n' "$task_version" "$task_arch" "$task_dmg" "$task_zip"
