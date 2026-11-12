#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
CHAT_APP_DIR="$ROOT_DIR/example/chat_app"
BUILD_DIR="$CHAT_APP_DIR/build/web"
BASE_HREF="${CHAT_APP_BASE_HREF:-/}"
BUILD_TARGET="lib/main.dart"
if [[ "${1:-}" == "--validation" ]]; then
  BUILD_TARGET="lib/validation_main.dart"
  shift
  for argument in "$@"; do
    case "$argument" in --dart-define=VALIDATION_*) ;; *) echo "Unsupported validation option" >&2; exit 64 ;; esac
  done
elif [[ $# -gt 0 ]]; then
  echo "Unsupported build option: $1" >&2
  exit 64
fi

(
  cd "$CHAT_APP_DIR"
  flutter build web --release --base-href "$BASE_HREF" --target "$BUILD_TARGET" "$@"
)

WEBGPU_BRIDGE_OUT_DIR="$BUILD_DIR/webgpu_bridge" \
  "$ROOT_DIR/scripts/fetch_webgpu_bridge_assets.sh"

if [[ -n "${CHAT_APP_BUILD_SHA:-}" ]]; then
  export CHAT_APP_BUILD_TARGET="$BUILD_TARGET" CHAT_APP_BUILD_BASE_HREF="$BASE_HREF"
  python3 - "$BUILD_DIR/llamadart-build.json" "$ROOT_DIR" <<'PYTHON'
import json, os, subprocess, sys
from pathlib import Path
commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
if os.environ['CHAT_APP_BUILD_SHA'] != commit:
    raise SystemExit('CHAT_APP_BUILD_SHA must match the checked-out source')
subprocess.run(['git', 'diff', '--quiet', 'HEAD', '--'], check=True)
flutter = json.loads(subprocess.check_output(['flutter', '--version', '--machine'], text=True))['frameworkVersion']
if flutter != (Path(sys.argv[2]) / '.flutter-version').read_text().strip():
    raise SystemExit('Stamped deployment builds require the pinned Flutter SDK')
Path(sys.argv[1]).write_text(json.dumps({
    'commit': commit,
    'tree': subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], text=True).strip(),
    'base_href': os.environ['CHAT_APP_BUILD_BASE_HREF'],
    'target': os.environ['CHAT_APP_BUILD_TARGET'],
    'flutter_version': flutter,
}, separators=(',', ':')) + '\n')
PYTHON
fi

"$ROOT_DIR/scripts/validate_chat_app_web_build.sh" "$BUILD_DIR"
