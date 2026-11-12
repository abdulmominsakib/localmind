#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir .started || exit 73
mkdir -p results
trap 'result=$?; printf "%s\n" "$result" > exit-code.txt' EXIT
python3 - <<'PY'
import hashlib, json
from pathlib import Path
root = Path.cwd()
manifest = json.loads((root / 'bundle-manifest.json').read_text())
for name, expected in manifest['files'].items():
    path = root / name
    if path.is_symlink() or not path.resolve().is_relative_to(root):
        raise SystemExit('Unsafe bundle member')
    if path.stat().st_size != expected['bytes']:
        raise SystemExit('Bundle size mismatch')
    with path.open('rb') as stream:
        hasher = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            hasher.update(chunk)
        digest = hasher.hexdigest()
    if digest != expected['sha256']:
        raise SystemExit('Bundle checksum mismatch')
PY
nvidia-smi -q > results/gpu.txt
set +e
timeout --signal=TERM --kill-after=10s 20m ./bin/llamadart-validate \
  --profile "$1" --out results --cache model-cache \
  --environment-file environment.json > results/stdout.log 2> results/stderr.log

engine_status=$?
./bin/llamadart-report results --native-log results/stderr.log
report_status=$?
if [ "$engine_status" -gt 1 ]; then exit "$engine_status"; fi
exit "$report_status"
