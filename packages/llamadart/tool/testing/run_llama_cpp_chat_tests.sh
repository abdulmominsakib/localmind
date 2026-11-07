#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
src_dir="${LLAMA_CPP_CHAT_TEST_SOURCE_DIR:-${LLAMA_CPP_SOURCE_DIR:-${repo_root}/.dart_tool/llama_cpp}}"
build_dir="${LLAMA_CPP_CHAT_TEST_BUILD_DIR:-${repo_root}/.dart_tool/llama_cpp_chat_tests}"
include_full="${LLAMA_CPP_CHAT_TEST_INCLUDE_FULL:-0}"
full_verbose="${LLAMA_CPP_CHAT_TEST_FULL_VERBOSE:-0}"

export LLAMA_CPP_SOURCE_DIR="${src_dir}"
"${repo_root}/tool/testing/prepare_llama_cpp_source.sh" >/dev/null

if [[ ! -f "${src_dir}/CMakeLists.txt" ]]; then
  echo "llama.cpp source not found at: ${src_dir}" >&2
  exit 1
fi

build_tools=OFF
build_server=OFF
if [[ "${include_full}" == "1" ]]; then
  build_tools=ON
  build_server=ON
fi

cmake_args=(
  -DLLAMA_BUILD_TESTS=ON
  "-DLLAMA_BUILD_TOOLS=${build_tools}"
  -DLLAMA_BUILD_EXAMPLES=OFF
  "-DLLAMA_BUILD_SERVER=${build_server}"
  -DGGML_CCACHE=OFF
  -DGGML_OPENMP=OFF
)

if [[ "${include_full}" == "1" && -d "${src_dir}/tools/mtmd" ]]; then
  # Newer llama.cpp releases include mtmd.h from server headers while the
  # test-chat target only exposes tools/server. Add the include path at configure
  # time instead of patching the prepared upstream source.
  cxx_flags="${LLAMA_CPP_CHAT_TEST_CXX_FLAGS:-}"
  cxx_flags="${cxx_flags:+${cxx_flags} }-I${src_dir}/tools/mtmd"
  cmake_args+=("-DCMAKE_CXX_FLAGS=${cxx_flags}")
fi

echo "[chat-tests] configure: ${build_dir}"
cmake -S "${src_dir}" -B "${build_dir}" "${cmake_args[@]}"

available_targets="$(cmake --build "${build_dir}" --target help 2>/dev/null || true)"
resolve_target() {
  local label="$1"
  shift
  local candidate
  for candidate in "$@"; do
    if grep -Eq "(^|[[:space:]])${candidate}(:|$|[[:space:]])" <<<"${available_targets}"; then
      echo "${candidate}"
      return 0
    fi
  done
  echo "No llama.cpp build target found for ${label}. Tried: $*" >&2
  exit 1
}

# llama.cpp renamed test-chat-parser to test-chat-auto-parser in newer releases.
# Keep both names so this local-only E2E works across old pinned tags and the
# current latest release used by prepare_llama_cpp_source.sh.
chat_parser_target="$(resolve_target chat-parser test-chat-parser test-chat-auto-parser)"
peg_parser_target="$(resolve_target peg-parser test-chat-peg-parser)"
template_target="$(resolve_target chat-template test-chat-template)"

ctest_targets=("${chat_parser_target}" "${peg_parser_target}" "${template_target}")
targets=("${ctest_targets[@]}")
if [[ "${include_full}" == "1" ]]; then
  full_target="$(resolve_target full-chat test-chat)"
  targets+=("${full_target}")
fi

echo "[chat-tests] build targets: ${targets[*]}"
cmake --build "${build_dir}" --target "${targets[@]}" --parallel

library_path_entries=(
  "${build_dir}/bin"
  "${build_dir}/src"
  "${build_dir}/common"
  "${build_dir}/ggml/src"
  "${build_dir}/ggml/src/ggml-cpu"
  "${build_dir}/ggml/src/ggml-blas"
  "${build_dir}/ggml/src/ggml-metal"
)
library_path="$(IFS=:; echo "${library_path_entries[*]}")"
export DYLD_LIBRARY_PATH="${library_path}${DYLD_LIBRARY_PATH:+:${DYLD_LIBRARY_PATH}}"
export LD_LIBRARY_PATH="${library_path}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

ctest_pattern="^($(IFS='|'; echo "${ctest_targets[*]}"))$"
echo "[chat-tests] running ctest selection: ${ctest_pattern}"
ctest --test-dir "${build_dir}" --output-on-failure -R "${ctest_pattern}"

if [[ "${include_full}" == "1" ]]; then
  echo "[chat-tests] running full test-chat (source-root cwd required)"
  full_test_bin="${build_dir}/bin/test-chat"
  if [[ ! -x "${full_test_bin}" ]]; then
    echo "Missing executable: ${full_test_bin}" >&2
    exit 1
  fi

  if [[ "${full_verbose}" == "1" ]]; then
    (
      cd "${src_dir}"
      "${full_test_bin}"
    )
  else
    full_log="${build_dir}/test-chat.log"
    if ! (
      cd "${src_dir}"
      "${full_test_bin}" >"${full_log}" 2>&1
    ); then
      echo "[chat-tests] full test-chat failed. Log:" >&2
      cat "${full_log}" >&2
      exit 1
    fi
    echo "[chat-tests] full test-chat passed (log: ${full_log})"
  fi
fi
