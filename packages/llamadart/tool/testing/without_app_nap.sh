#!/usr/bin/env bash
# Runs a command with App Nap disabled for one macOS app, then restores the
# app's previous setting. A Flutter macOS integration test app that the tool
# cannot bring to the foreground is napped, and on a busy host it can then get
# no CPU for minutes, so worker-startup deadlines expire (#1674).
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <bundle-id> <command> [arguments...]" >&2
  exit 64
fi

bundle_id="$1"
shift
key=NSAppSleepDisabled
previous="$(defaults read "$bundle_id" "$key" 2>/dev/null || true)"

restore() {
  case "$previous" in
    '') defaults delete "$bundle_id" "$key" >/dev/null 2>&1 || true ;;
    1) defaults write "$bundle_id" "$key" -bool YES ;;
    *) defaults write "$bundle_id" "$key" -bool NO ;;
  esac
}
trap restore EXIT

defaults write "$bundle_id" "$key" -bool YES
"$@"
