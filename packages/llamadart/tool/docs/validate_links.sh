#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

"$ROOT_DIR/tool/docs/build_site.sh"

echo "[docs] Link validation passed (the site build fails on broken internal links)."
