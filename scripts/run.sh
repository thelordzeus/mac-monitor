#!/bin/zsh
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
if [ ! -d "$task_root/dist/Mac Monitor.app" ]; then "$task_root/scripts/build.sh"; fi
open "$task_root/dist/Mac Monitor.app"
