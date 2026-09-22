#!/usr/bin/env bash
set -euo pipefail

: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_PATH:?GITHUB_PATH is required}"

case "${RUNNER_OS:-}/${RUNNER_ARCH:-}" in
  Linux/X64|Linux/ARM64|macOS/X64|macOS/ARM64) ;;
  *)
    echo "Unsupported runner: ${RUNNER_OS:-unset}/${RUNNER_ARCH:-unset}" >&2
    exit 1
    ;;
esac

version=${UNMESHED_VERSION:-latest}
if [[ ! $version =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo 'version must contain only letters, numbers, dots, underscores, or hyphens' >&2
  exit 1
fi

stage=$(mktemp -d "$RUNNER_TEMP/unmeshed.XXXXXXXX")
trap 'rm -rf "$stage"' EXIT

if ! curl --fail --silent --show-error --location \
  --proto '=https' --proto-redir '=https' --retry 3 \
  --output "$stage/install-cli.sh" \
  'https://unmeshed.io/files/install-cli.sh'; then
  echo 'Could not download the Unmeshed installer. Check runner network access.' >&2
  exit 1
fi

# The deployed installer must support noninteractive, user-writable installs
# and checksum enforcement. Fail before executing an older installer.
for flag in --install-dir --require-checksum; do
  if ! grep -Fq -- "$flag" "$stage/install-cli.sh"; then
    echo 'The Unmeshed installer is not ready for GitHub Actions yet. Please retry after the installer is updated.' >&2
    exit 1
  fi
done

bin_dir="$RUNNER_TEMP/unmeshed/bin"
mkdir -p "$bin_dir"
args=(--install-dir "$bin_dir" --require-checksum)
if [[ $version != latest ]]; then
  if ! grep -Fq -- '--version' "$stage/install-cli.sh"; then
    echo 'The Unmeshed installer does not support version selection yet. Please retry after the installer is updated.' >&2
    exit 1
  fi
  args+=(--version "$version")
fi

if ! CI=true bash "$stage/install-cli.sh" "${args[@]}"; then
  echo 'Unmeshed installation failed. Check the selected version and runner network access.' >&2
  exit 1
fi
if [[ ! -x "$bin_dir/unmeshed" ]]; then
  echo 'Unmeshed installation did not produce an executable.' >&2
  exit 1
fi

printf '%s\n' "$bin_dir" >> "$GITHUB_PATH"
echo "Installed Unmeshed CLI $version"
