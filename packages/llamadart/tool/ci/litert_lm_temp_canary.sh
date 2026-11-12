#!/usr/bin/env bash
# Points the system temp directory of later steps at a scratch directory whose
# default LiteRT-LM cache holds a program cache over the 1 GiB default cap. A
# test that prunes the default temp cache without useSuiteSystemTemp would
# delete user caches on a developer machine, so `check` fails the job.
#
# Usage: litert_lm_temp_canary.sh seed|check
set -euo pipefail

dir="${RUNNER_TEMP:?}/llamadart-test-tmp"
# Forward slashes keep the Windows path valid for both Git Bash and Dart.
if command -v cygpath >/dev/null; then dir="$(cygpath -m "$dir")"; fi
canary="$dir/llamadart_litert_lm/ci-canary.litertlm_1_2_mldrift_program_cache.bin"

case "${1:-}" in
  seed)
    mkdir -p "${canary%/*}"
    # Sparse: one byte over the cap without writing a GiB.
    dd if=/dev/zero of="$canary" bs=1 count=0 seek=$(((1 << 30) + 1)) 2>/dev/null
    {
      echo "TMPDIR=$dir"
      echo "TEMP=$dir"
      echo "TMP=$dir"
    } >>"${GITHUB_ENV:?}"
    ;;
  check)
    if [[ ! -f "$canary" ]]; then
      echo "::error::A test deleted $canary from the default LiteRT-LM temp cache; load models in suites that call useSuiteSystemTemp." >&2
      exit 1
    fi
    ;;
  *)
    echo "usage: $0 seed|check" >&2
    exit 64
    ;;
esac
