#!/bin/zsh
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
export CLANG_MODULE_CACHE_PATH="$task_root/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$task_root/.build/module-cache"
# Native SwiftPM avoids file-provider metadata on Xcode-built .xctest bundles.
xcrun swift test --build-system native --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
