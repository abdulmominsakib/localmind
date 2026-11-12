#!/usr/bin/env bash
set -euo pipefail

# Builds llama.cpp's test-gbnf-validator at the upstream release the native
# runtime ships, and prints its path. Grammar load limits follow the shipped
# runtime, not the template-parity ref in llama_cpp_templates.ref.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
pin_file="${repo_root}/lib/src/hook/native_release_pins.dart"
native_tag="$(sed -nE "s/^const llamaCppTag = '([^']+)';$/\1/p" "${pin_file}")"
if [[ -z "${native_tag}" ]]; then
  echo "llamaCppTag not found in ${pin_file}" >&2
  exit 1
fi
# Wrapper rebuilds append -N (or legacy -llamadart.N) to the upstream tag.
upstream_ref="$(sed -E 's/-(llamadart\.)?[1-9][0-9]*$//' <<<"${native_tag}")"
src_dir="${LLAMA_CPP_RUNTIME_SOURCE_DIR:-${repo_root}/.dart_tool/llama_cpp_runtime}"
build_dir="${LLAMA_CPP_RUNTIME_BUILD_DIR:-${repo_root}/.dart_tool/llama_cpp_runtime_build}"
build_jobs="${LLAMA_CPP_RUNTIME_BUILD_JOBS:-2}"
if [[ ! "${build_jobs}" =~ ^[1-9][0-9]*$ ]]; then
  echo "LLAMA_CPP_RUNTIME_BUILD_JOBS must be a positive integer." >&2
  exit 64
fi

# An empty GITHUB_OUTPUT keeps the runtime ref from overwriting the template
# parity ref that callers publish as a step output.
GITHUB_OUTPUT="" LLAMA_CPP_SOURCE_DIR="${src_dir}" \
  LLAMA_CPP_REF="${upstream_ref}" \
  "${repo_root}/tool/testing/prepare_llama_cpp_source.sh" >&2

echo "[runtime-gbnf] ${native_tag} -> upstream ${upstream_ref}: ${build_dir}" >&2
cmake -S "${src_dir}" -B "${build_dir}" \
  -DLLAMA_BUILD_TESTS=ON \
  -DLLAMA_BUILD_TOOLS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_SERVER=OFF \
  -DGGML_CCACHE=OFF \
  -DGGML_OPENMP=OFF >&2
cmake --build "${build_dir}" --target test-gbnf-validator \
  --parallel "${build_jobs}" >&2

echo "${build_dir}/bin/test-gbnf-validator"
