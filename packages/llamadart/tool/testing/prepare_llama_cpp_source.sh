#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_dir="${LLAMA_CPP_SOURCE_DIR:-${repo_root}/.dart_tool/llama_cpp}"
repo_url="${LLAMA_CPP_REPO_URL:-https://github.com/ggml-org/llama.cpp.git}"
ref_input="${LLAMA_CPP_REF:-latest}"

curl_headers=(
  -H "Accept: application/vnd.github+json"
  -H "X-GitHub-Api-Version: 2022-11-28"
)
if [[ -n "${GH_TOKEN:-}" ]]; then
  curl_headers+=(-H "Authorization: Bearer ${GH_TOKEN}")
fi

resolve_ref() {
  if [[ "${ref_input}" != "latest" ]]; then
    echo "${ref_input}"
    return
  fi

  curl -fsSL "${curl_headers[@]}" \
    "https://api.github.com/repos/ggml-org/llama.cpp/releases/latest" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['tag_name'])"
}

resolved_ref="$(resolve_ref)"

if [[ -d "${source_dir}" && ! -d "${source_dir}/.git" ]]; then
  echo "Path exists but is not a git checkout: ${source_dir}" >&2
  exit 1
fi

if [[ ! -d "${source_dir}/.git" ]]; then
  mkdir -p "$(dirname "${source_dir}")"
  git clone --quiet --depth 1 --no-tags "${repo_url}" "${source_dir}"
fi

checkout_target=""
if git -C "${source_dir}" rev-parse -q --verify "refs/tags/${resolved_ref}" \
  >/dev/null; then
  checkout_target="tags/${resolved_ref}"
else
  if git -C "${source_dir}" fetch --quiet --depth 1 --no-tags origin \
    "refs/tags/${resolved_ref}:refs/tags/${resolved_ref}"; then
    checkout_target="tags/${resolved_ref}"
  else
    git -C "${source_dir}" fetch --quiet --depth 1 --no-tags origin \
      "${resolved_ref}"
    checkout_target="FETCH_HEAD"
  fi
fi

git -C "${source_dir}" checkout --quiet --force --detach "${checkout_target}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "llama_cpp_ref=${resolved_ref}" >> "${GITHUB_OUTPUT}"
  echo "llama_cpp_source_dir=${source_dir}" >> "${GITHUB_OUTPUT}"
fi

echo "Prepared llama.cpp source:"
echo "  dir: ${source_dir}"
echo "  ref: ${resolved_ref}"
