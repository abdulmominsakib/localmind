#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

"${repo_root}/tool/testing/prepare_llama_cpp_source.sh"
export REQUIRE_LLAMA_CPP_TEMPLATES=1

echo "[template-parity] detection parity"
dart test -p vm -j 1 test/integration/core/template/llama_cpp_template_detection_integration_test.dart

echo "[template-parity] diagnostic fixture matrix"
dart test -p vm -j 1 test/integration/core/template/template_diagnostic_integration_test.dart

echo "[template-parity] unit template suite"
dart test -p vm -j 1 test/unit/core/template --exclude-tags local-only

echo "[template-parity] upstream llama.cpp chat/template parser suites"
dart test -p vm -j 1 test/e2e/template/llama_cpp_chat_tests_e2e_test.dart --run-skipped

echo "[template-parity] compiled structured-output grammar acceptance"
# Grammar load limits must match the llama.cpp release the native runtime ships.
gbnf_validator="${LLAMA_CPP_GBNF_VALIDATOR:-$("${repo_root}/tool/testing/build_llama_cpp_runtime_gbnf_validator.sh")}"
LLAMA_CPP_GBNF_VALIDATOR="${gbnf_validator}" \
  dart test -p vm -j 1 test/e2e/template/specialized_tool_grammar_validation_e2e_test.dart --run-skipped
