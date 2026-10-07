#!/bin/zsh
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$task_root/Resources/Info.plist")"
if [ ! -d "$task_root/dist/$task_name.app" ]; then "$task_root/scripts/build.sh"; fi
open "$task_root/dist/$task_name.app"
