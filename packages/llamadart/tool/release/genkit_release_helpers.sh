# Only an explicit 404 means absent. Network, authentication and service errors
# must stop release mutations rather than masquerade as an unpublished version.
release_url_exists() {
  local status
  status="$(curl --silent --show-error --location --output /dev/null \
    --write-out '%{http_code}' --connect-timeout 10 --max-time 30 --retry 2 "$@")" || return 1
  case "$status" in
    200) echo true ;;
    404) echo false ;;
    *) echo "Release lookup failed (HTTP $status)." >&2; return 1 ;;
  esac
}

# Check configuration before creating tags or starting publication, and also
# when the wait step is replayed on its own.
release_validate_wait_settings() {
  if [[ ! "$RELEASE_WAIT_ATTEMPTS" =~ ^[1-9][0-9]*$ ]]; then
    echo "RELEASE_WAIT_ATTEMPTS must be a positive integer." >&2
    return 1
  fi
  if [[ ! "$RELEASE_WAIT_INTERVAL_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
    echo "RELEASE_WAIT_INTERVAL_SECONDS must be a positive integer." >&2
    return 1
  fi
}
