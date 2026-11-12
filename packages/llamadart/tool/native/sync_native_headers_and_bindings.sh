#!/usr/bin/env bash
set -euo pipefail

stable_tag_pattern='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
stable_wrapper_tag_pattern='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)-[1-9][0-9]*$'
nightly_tag_pattern='^b(0|[1-9][0-9]*)$'
nightly_wrapper_tag_pattern='^b(0|[1-9][0-9]*)-[1-9][0-9]*$'
legacy_wrapper_tag_pattern='^b(0|[1-9][0-9]*)-llamadart\.[1-9][0-9]*$'

is_supported_native_tag() {
  [[ "$1" =~ ${stable_tag_pattern} ]] ||
    [[ "$1" =~ ${stable_wrapper_tag_pattern} ]] ||
    [[ "$1" =~ ${nightly_tag_pattern} ]] ||
    [[ "$1" =~ ${nightly_wrapper_tag_pattern} ]] ||
    [[ "$1" =~ ${legacy_wrapper_tag_pattern} ]]
}

is_latest_eligible_tag() {
  [[ "$1" =~ ${stable_tag_pattern} ]]
}

is_stable_upstream_tag() {
  [[ "$1" =~ ${stable_tag_pattern} || "$1" =~ ${stable_wrapper_tag_pattern} ]]
}

is_allowed_native_tag_input() {
  [[ "$1" == "latest" ]] || is_supported_native_tag "$1"
}

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  return 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

native_repo="${LLAMADART_NATIVE_REPO:-leehack/llamadart-native}"
tag_input="${LLAMADART_NATIVE_TAG:-latest}"
header_root="${LLAMADART_FFIGEN_HEADER_ROOT:-.dart_tool/llamadart/ffigen_headers}"
run_ffigen=1

usage() {
  cat <<'EOF'
Usage: tool/native/sync_native_headers_and_bindings.sh [options]

Downloads llamadart-native release header bundle for a tag and regenerates
bindings using ffigen.

Options:
  --tag <tag|latest>      Explicit tag, or latest unsuffixed stable (default: latest)
  --repo <owner/name>     Native repository slug (default: leehack/llamadart-native)
  --header-root <path>    Header staging path (default: .dart_tool/llamadart/ffigen_headers)
  --skip-ffigen           Only sync headers, do not run ffigen
  --help                  Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      tag_input="$2"
      shift 2
      ;;
    --repo)
      native_repo="$2"
      shift 2
      ;;
    --header-root)
      header_root="$2"
      shift 2
      ;;
    --skip-ffigen)
      run_ffigen=0
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! is_allowed_native_tag_input "${tag_input}"; then
  echo "Invalid llamadart-native tag: ${tag_input}" >&2
  echo "Expected stable vMAJOR.MINOR.PATCH, stable wrapper" \
    "vMAJOR.MINOR.PATCH-N, canonical historical/nightly bNNNN without" \
    "leading zeros, nightly wrapper" \
    "bNNNN-N, or legacy wrapper artifact bNNNN-llamadart.N." >&2
  exit 1
fi
if [[ ! "${native_repo}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "Invalid native repository slug." >&2
  exit 1
fi

curl_opts=(
  -fsSL
  --retry 2
  --retry-connrefused
  --retry-delay 2
  --retry-max-time 300
  --connect-timeout 15
  --max-time 100
  -H "Accept: application/vnd.github+json"
  -H "X-GitHub-Api-Version: 2022-11-28"
)
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/llamadart-native-sync.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT
if [[ -n "${GH_TOKEN:-}" ]]; then
  auth_config="${tmp_dir}/curl.conf"
  (umask 077 && printf 'header = "Authorization: Bearer %s"\n' \
    "${GH_TOKEN}" > "${auth_config}")
  curl_opts+=(--config "${auth_config}")
fi

if [[ "${tag_input}" == "latest" || -z "${tag_input}" ]]; then
  release_api_url="https://api.github.com/repos/${native_repo}/releases/latest"
else
  release_api_url="https://api.github.com/repos/${native_repo}/releases/tags/${tag_input}"
fi

if ! release_json="$(curl "${curl_opts[@]}" "${release_api_url}" 2>/dev/null)"; then
  echo "Failed to fetch llamadart-native release metadata for" \
    "${native_repo}@${tag_input}." >&2
  exit 1
fi

if ! resolved_tag="$(
  python3 -c 'import json, sys
data = json.load(sys.stdin)
tag = data.get("tag_name") if isinstance(data, dict) else None
if not isinstance(tag, str) or not tag:
    raise SystemExit(1)
print(tag)' <<<"${release_json}" 2>/dev/null
)"; then
  echo "Release metadata for ${native_repo}@${tag_input} is not JSON with a" \
    "non-empty tag_name." >&2
  exit 1
fi

if ! is_supported_native_tag "${resolved_tag}"; then
  echo "Release metadata resolved unsupported tag for" \
    "${native_repo}@${tag_input}." >&2
  exit 1
fi
if [[ "${tag_input}" == "latest" ]] && ! is_latest_eligible_tag "${resolved_tag}"; then
  echo "llamadart-native latest resolved to ${resolved_tag};" \
    "automatic discovery accepts only unsuffixed vMAJOR.MINOR.PATCH releases;" \
    "select wrapper rebuilds and historical or nightly tags explicitly." >&2
  exit 1
fi
if [[ "${tag_input}" != "latest" && -n "${tag_input}" ]] &&
  [[ "${resolved_tag}" != "${tag_input}" ]]; then
  echo "Requested ${tag_input}, but release metadata resolved" \
    "${resolved_tag}; refusing version skew." >&2
  exit 1
fi

asset_name="llamadart-native-headers-${resolved_tag}.tar.gz"
if ! asset_fields="$(
  python3 -c 'import json, re, sys
from urllib.parse import urlsplit
name = sys.argv[1]
data = json.load(sys.stdin)
assets = data.get("assets") if isinstance(data, dict) else None
if not isinstance(assets, list) or any(not isinstance(a, dict) for a in assets):
    raise SystemExit("release asset inventory is not a list of objects")
matching = [a for a in assets if a.get("name") == name]
if not matching:
    raise SystemExit(f"Could not find release asset: {name}")
if len(matching) != 1:
    raise SystemExit(f"release asset inventory duplicates {name}")
asset = matching[0]
url = asset.get("browser_download_url")
if not isinstance(url, str) or not url:
    raise SystemExit(f"asset {name} has no download URL")
parsed = urlsplit(url)
if (
    parsed.scheme != "https"
    or parsed.hostname != "github.com"
    or parsed.username is not None
    or parsed.password is not None
    or any(character.isspace() for character in url)
    or any(character in url for character in ("\\", "\""))
):
    raise SystemExit(f"asset {name} has an invalid download URL")
digest = asset.get("digest") or ""
if not isinstance(digest, str) or (
    digest and not re.fullmatch(r"sha256:[0-9a-f]{64}", digest)
):
    raise SystemExit(f"asset {name} has an invalid SHA-256 digest")
print(url)
print(digest)' "${asset_name}" <<<"${release_json}"
)"; then
  echo "Unusable release metadata for ${native_repo}@${resolved_tag}." >&2
  exit 1
fi
{
  IFS= read -r asset_url
  IFS= read -r asset_digest || asset_digest=""
} <<<"${asset_fields}"
asset_config="${tmp_dir}/asset.curl.conf"
(umask 077 && printf 'url = "%s"\n' "${asset_url}" > "${asset_config}")

header_root_parent="$(dirname "${header_root}")"
mkdir -p "${header_root_parent}"
header_root_name="$(basename "${header_root}")"
header_root="$(cd "${header_root_parent}" && pwd)/${header_root_name}"
if [[ "${header_root_name}" == "." || "${header_root_name}" == ".." ||
  "${header_root}" == "/" || "${header_root}" == "${repo_root}" ]]; then
  echo "Refusing unsafe generated-header root: ${header_root}." >&2
  exit 1
fi

archive_path="${tmp_dir}/${asset_name}"
extract_dir="${tmp_dir}/extract"
transaction_root="$(mktemp -d \
  "${header_root_parent}/.${header_root_name}.sync.XXXXXX")"
staging_root="${transaction_root}/staging"
backup_root="${transaction_root}/backup"
restore_backup=0
published=0

cleanup() {
  local status=$?
  trap - EXIT
  set +e
  if [[ "${restore_backup}" == "1" ]]; then
    if rm -rf -- "${header_root}" &&
      [[ ! -e "${header_root}" && ! -L "${header_root}" ]] &&
      mv -- "${backup_root}" "${header_root}"; then
      echo "Restored the previous header root at ${header_root}." >&2
      restore_backup=0
    else
      echo "Could not restore ${header_root}; preserved its backup at" \
        "${backup_root}." >&2
      status=1
    fi
  elif [[ "${published}" == "1" ]]; then
    rm -rf -- "${header_root}" || status=1
  fi
  if [[ "${restore_backup}" == "0" ]]; then
    rm -rf -- "${transaction_root}"
  fi
  rm -rf -- "${tmp_dir}"
  exit "${status}"
}
trap cleanup EXIT

mkdir -p "${extract_dir}"
echo "Downloading ${asset_name} from ${native_repo} (${resolved_tag})..."
if ! curl "${curl_opts[@]}" --config "${asset_config}" \
  -o "${archive_path}" 2>/dev/null; then
  echo "Failed to download ${asset_name} from ${native_repo}" \
    "(${resolved_tag})." >&2
  exit 1
fi
if [[ "${asset_digest}" == sha256:* ]]; then
  expected_sha256="${asset_digest#sha256:}"
  if command -v shasum >/dev/null 2>&1; then
    actual_sha256="$(shasum -a 256 "${archive_path}" | awk '{print $1}')"
  elif command -v sha256sum >/dev/null 2>&1; then
    actual_sha256="$(sha256sum "${archive_path}" | awk '{print $1}')"
  else
    echo "No SHA-256 tool available to verify ${asset_name}" >&2
    exit 1
  fi
  if [[ "${actual_sha256}" != "${expected_sha256}" ]]; then
    echo "Header archive checksum mismatch for ${native_repo}@${resolved_tag}:" \
      "expected ${expected_sha256}, got ${actual_sha256}." >&2
    exit 1
  fi
elif is_stable_upstream_tag "${resolved_tag}"; then
  echo "Stable release ${resolved_tag} does not publish a SHA-256 digest for ${asset_name}." >&2
  exit 1
else
  echo "Warning: historical release ${resolved_tag} has no GitHub SHA-256" \
    "digest for ${asset_name}." >&2
fi
if ! python3 "${repo_root}/tool/native/native_header_archive.py" \
  --archive "${archive_path}" \
  --extract-dir "${extract_dir}" \
  --staging "${staging_root}"; then
  echo "Rejected header archive ${asset_name} from ${native_repo}" \
    "(${resolved_tag}); left ${header_root} unchanged." >&2
  exit 1
fi

if [[ -e "${header_root}" || -L "${header_root}" ]]; then
  restore_backup=1
  if ! mv -- "${header_root}" "${backup_root}"; then
    restore_backup=0
    echo "Failed to preserve the previous header root at ${header_root}." >&2
    exit 1
  fi
fi
published=1
if ! mv -- "${staging_root}" "${header_root}"; then
  echo "Failed to publish the staged header root at ${header_root}." >&2
  exit 1
fi

echo "Synced headers to ${header_root}"

if [[ "${run_ffigen}" == "1" ]]; then
  echo "Running ffigen..."
  if ! dart run ffigen --config ffigen.yaml; then
    echo "ffigen failed for ${native_repo} (${resolved_tag})." >&2
    exit 1
  fi
fi
restore_backup=0
published=0

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "resolved_tag=${resolved_tag}" >> "${GITHUB_OUTPUT}"
fi

echo "Resolved tag: ${resolved_tag}"
