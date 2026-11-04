#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Run Android runtime smoke checks in one shot.

Usage:
  ./scripts/android_runtime_smoke.sh \
    --app-id <application-id> \
    [--activity <activity-name>] \
    [--serial <device-serial>] \
    [--project-dir <flutter-project-dir>] \
    [--apk <apk-path>] \
    [--wait-seconds <seconds>] \
    [--log-file <path>] \
    [--skip-clean] [--skip-build] [--skip-install] [--skip-launch]

Examples:
  ./scripts/android_runtime_smoke.sh \
    --project-dir example/chat_app \
    --app-id com.example.llamadart_chat_example

  ./scripts/android_runtime_smoke.sh \
    --project-dir example/chat_app \
    --app-id com.example.llamadart_chat_example \
    --activity .MainActivity \
    --serial emulator-5554 \
    --wait-seconds 30

Notes:
  - By default, this script runs:
      flutter clean
      flutter pub get
      flutter build apk --release
      adb install -r <apk>
      adb logcat -c
      launch app
      adb logcat -d > <log-file>
  - Exit code is non-zero if crash signatures are detected in logcat.
USAGE
}

require_cmd() {
  local tool_name="$1"
  if ! command -v "$tool_name" >/dev/null 2>&1; then
    echo "Required tool not found: $tool_name" >&2
    exit 2
  fi
}

project_dir="."
apk_path="build/app/outputs/flutter-apk/app-release.apk"
log_file="build/android_runtime_smoke.log"
wait_seconds=20
serial=""
app_id=""
activity=""
skip_clean=0
skip_build=0
skip_install=0
skip_launch=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir)
      project_dir="$2"
      shift 2
      ;;
    --apk)
      apk_path="$2"
      shift 2
      ;;
    --log-file)
      log_file="$2"
      shift 2
      ;;
    --wait-seconds)
      wait_seconds="$2"
      shift 2
      ;;
    --serial)
      serial="$2"
      shift 2
      ;;
    --app-id)
      app_id="$2"
      shift 2
      ;;
    --activity)
      activity="$2"
      shift 2
      ;;
    --skip-clean)
      skip_clean=1
      shift
      ;;
    --skip-build)
      skip_build=1
      shift
      ;;
    --skip-install)
      skip_install=1
      shift
      ;;
    --skip-launch)
      skip_launch=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if ! [[ "$wait_seconds" =~ ^[0-9]+$ ]]; then
  echo "--wait-seconds must be a non-negative integer" >&2
  exit 2
fi

if [[ "$skip_launch" -eq 0 && -z "$app_id" ]]; then
  echo "--app-id is required unless --skip-launch is used" >&2
  exit 2
fi

require_cmd flutter
require_cmd adb
require_cmd grep

project_dir="$(cd "$project_dir" && pwd)"
if [[ "$apk_path" != /* ]]; then
  apk_path="$project_dir/$apk_path"
fi
if [[ "$log_file" != /* ]]; then
  log_file="$project_dir/$log_file"
fi

adb_cmd=(adb)
if [[ -n "$serial" ]]; then
  adb_cmd+=(-s "$serial")
fi

adb_run() {
  "${adb_cmd[@]}" "$@"
}

device_state="$(adb_run get-state 2>/dev/null || true)"
if [[ "$device_state" != "device" ]]; then
  echo "No ready Android device found. Use --serial when multiple devices exist." >&2
  exit 2
fi

pushd "$project_dir" >/dev/null

if [[ "$skip_clean" -eq 0 ]]; then
  echo "[android-smoke] flutter clean"
  flutter clean
fi

echo "[android-smoke] flutter pub get"
flutter pub get

if [[ "$skip_build" -eq 0 ]]; then
  echo "[android-smoke] flutter build apk --release"
  flutter build apk --release
fi

if [[ ! -f "$apk_path" ]]; then
  echo "APK not found: $apk_path" >&2
  exit 2
fi

if [[ "$skip_install" -eq 0 ]]; then
  echo "[android-smoke] adb install -r $apk_path"
  adb_run install -r "$apk_path"
fi

echo "[android-smoke] adb logcat -c"
adb_run logcat -c

if [[ "$skip_launch" -eq 0 ]]; then
  echo "[android-smoke] launching app: $app_id"
  adb_run shell am force-stop "$app_id" || true
  if [[ -n "$activity" ]]; then
    adb_run shell am start -W -n "$app_id/$activity"
  else
    adb_run shell monkey -p "$app_id" -c android.intent.category.LAUNCHER 1
  fi
fi

if [[ "$wait_seconds" -gt 0 ]]; then
  echo "[android-smoke] waiting ${wait_seconds}s for runtime activity"
  sleep "$wait_seconds"
fi

mkdir -p "$(dirname "$log_file")"
echo "[android-smoke] saving logcat to $log_file"
adb_run logcat -d > "$log_file"

crash_pattern='SIGILL|SIGSEGV|Fatal signal|Abort message|F libc\s+:\s+Fatal'
if grep -Eiq "$crash_pattern" "$log_file"; then
  echo "[android-smoke] crash signature detected:" >&2
  grep -Ein "$crash_pattern" "$log_file" || true
  popd >/dev/null
  exit 1
fi

echo "[android-smoke] no crash signatures detected"
echo "[android-smoke] recent llama/ggml lines (if any):"
grep -Ein 'llamadart|ggml|llama' "$log_file" | tail -n 40 || true

popd >/dev/null
