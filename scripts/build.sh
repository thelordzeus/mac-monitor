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
task_app="$task_root/dist/Mac Monitor.app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
cp "$task_bin/MacMonitor" "$task_app/Contents/MacOS/MacMonitor"
cp "$task_root/Resources/Info.plist" "$task_app/Contents/Info.plist"
if [ ! -f "$task_root/Resources/AppIcon.icns" ]; then
  xcrun swift "$task_root/scripts/create-icon.swift" "$task_root/Resources"
  iconutil -c icns "$task_root/Resources/AppIcon.iconset" -o "$task_root/Resources/AppIcon.icns"
fi
cp "$task_root/Resources/AppIcon.icns" "$task_app/Contents/Resources/AppIcon.icns"
xattr -cr "$task_app"
codesign --force --sign - --identifier local.macmonitor.app --requirements '=designated => identifier "local.macmonitor.app"' "$task_app"
printf 'Built: %s\n' "$task_app"
