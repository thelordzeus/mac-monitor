#!/bin/zsh
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
export CLANG_MODULE_CACHE_PATH="$task_root/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$task_root/.build/module-cache"
build_flags=(--disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security)
xcrun swift build -c release "${build_flags[@]}"
task_bin="$(xcrun swift build -c release --show-bin-path "${build_flags[@]}")"
task_stage="$(mktemp -d "${TMPDIR:-/private/tmp}/mac-monitor-build.XXXXXX")"
trap 'rm -rf "$task_stage"' EXIT
task_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$task_root/Resources/Info.plist")"
task_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$task_root/Resources/Info.plist")"
task_app="$task_stage/$task_name.app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
cp "$task_bin/$task_executable" "$task_app/Contents/MacOS/$task_executable"
cp "$task_root/Resources/Info.plist" "$task_app/Contents/Info.plist"
if [ ! -f "$task_root/Resources/AppIcon.icns" ]; then
  xcrun swift "$task_root/scripts/create-icon.swift" "$task_root/Resources"
  iconutil -c icns "$task_root/Resources/AppIcon.iconset" -o "$task_root/Resources/AppIcon.icns"
fi
cp "$task_root/Resources/AppIcon.icns" "$task_app/Contents/Resources/AppIcon.icns"
cp "$task_root/Resources/ThirdPartyNotices.txt" "$task_app/Contents/Resources/ThirdPartyNotices.txt"
task_sparkle="$task_root/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
mkdir -p "$task_app/Contents/Frameworks"
ditto --norsrc --noextattr "$task_sparkle" "$task_app/Contents/Frameworks/Sparkle.framework"
task_framework="$task_app/Contents/Frameworks/Sparkle.framework"
# This app is not sandboxed; use Sparkle's regular installer instead of XPC services.
rm -rf "$task_framework/Versions/B/XPCServices" "$task_framework/XPCServices"
cp "$task_root/.build/artifacts/sparkle/Sparkle/LICENSE" "$task_app/Contents/Resources/Sparkle-LICENSE.txt"
xattr -cr "$task_app"
# Sign nested code before its containing framework and app, preserving bundle symlinks.
codesign --force --sign - --options=0 "$task_framework/Versions/B/Autoupdate"
codesign --force --sign - --options=0 "$task_framework/Versions/B/Updater.app"
codesign --force --sign - --options=0 "$task_framework"
codesign --force --sign - --identifier local.macmonitor.app --requirements '=designated => identifier "local.macmonitor.app"' "$task_app"
codesign --verify --deep --strict "$task_app"
task_output="$task_root/dist/$task_name.app"
mkdir -p "$task_root/dist"
# Replace the generated bundle so renamed or removed resources cannot survive a rebuild.
if [[ -e "$task_output" ]]; then
  rm -rf "$task_output"
fi
ditto --norsrc --noextattr "$task_app" "$task_output"
xattr -cr "$task_output"
codesign --verify --deep --strict "$task_output"
printf 'Built: %s\n' "$task_output"
