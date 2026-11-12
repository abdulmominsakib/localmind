#!/usr/bin/env bash
# Builds the Jaspr docs site into website/build/jaspr and fails on broken
# internal links. Needs Dart (the pinned Flutter SDK) and Node.js for npx.
set -euo pipefail

usage() {
  echo "Usage: ./tool/docs/build_site.sh [--port PORT]"
  echo "PORT must be a decimal integer from 1 to 65535, without leading zeros."
}

case "$#" in
  0) ;;
  1)
    [[ "$1" == "--help" ]] || { usage >&2; exit 64; }
    usage
    exit 0
    ;;
  2)
    [[ "$1" == "--port" && "$2" =~ ^[1-9][0-9]{0,4}$ ]] &&
      (( 10#$2 <= 65535 )) || { usage >&2; exit 64; }
    ;;
  *) usage >&2; exit 64 ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEBSITE_DIR="$ROOT_DIR/website"
PAGEFIND_VERSION="1.5.2"

echo "[docs] Checking the observability example"
(
  cd "$WEBSITE_DIR/examples/observability"
  dart pub get
  dart format --output=none --set-exit-if-changed .
  dart analyze --fatal-infos
  dart test -p vm
)

cd "$WEBSITE_DIR"

echo "[docs] Resolving website dependencies"
dart pub get

echo "[docs] Building Jaspr site"
dart run jaspr_cli:jaspr build "$@"

echo "[docs] Finalizing output and checking links"
dart run tool/finalize_site.dart build/jaspr

echo "[docs] Indexing search with Pagefind $PAGEFIND_VERSION"
npx --yes "pagefind@$PAGEFIND_VERSION" --site build/jaspr

echo "[docs] Site build ready: $WEBSITE_DIR/build/jaspr"
