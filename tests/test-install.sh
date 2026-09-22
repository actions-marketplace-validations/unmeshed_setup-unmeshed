#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/mock-bin" "$test_dir/system-bin" "$test_dir/runner temp"
printf '#!/bin/sh\necho system-cli\n' > "$test_dir/system-bin/unmeshed"
chmod +x "$test_dir/system-bin/unmeshed"

cat > "$test_dir/mock-bin/curl" <<'MOCK_CURL'
#!/usr/bin/env bash
set -euo pipefail
[[ ${MOCK_HTTP_ERROR:-} != yes ]] || exit 22
destination=
flags=" $* "
[[ $flags == *' --fail '* && $flags == *' --proto '* && $flags == *' --proto-redir '* ]]
[[ $flags == *' https://unmeshed.io/files/install-cli.sh '* ]]
while (($#)); do
  if [[ $1 == --output ]]; then destination=$2; shift 2; else shift; fi
done
[[ -n $destination ]]
cp "$FIXTURE_INSTALLER" "$destination"
MOCK_CURL
chmod +x "$test_dir/mock-bin/curl"

cat > "$test_dir/installer" <<'MOCK_INSTALLER'
#!/usr/bin/env bash
set -euo pipefail
# Supported flags: --install-dir --require-checksum --version
install_dir= version=latest checksum=no
while (($#)); do
  case $1 in
    --install-dir) install_dir=$2; shift 2 ;;
    --require-checksum) checksum=yes; shift ;;
    --version) version=$2; shift 2 ;;
    *) exit 1 ;;
  esac
done
[[ -n $install_dir && $checksum == yes ]]
[[ $version == "$EXPECTED_VERSION" ]]
[[ ${CI:-} == true ]]
[[ ${MOCK_INSTALLER_ERROR:-} != yes ]] || exit 1
[[ ${MOCK_SKIP_BINARY:-} != yes ]] || exit 0
if [[ ${MOCK_SYMLINK_BINARY:-} == yes ]]; then
  ln -s "$SYSTEM_BINARY" "$install_dir/unmeshed"
  exit 0
fi
printf '#!/bin/sh\necho verified-cli\n' > "$install_dir/unmeshed"
MOCK_INSTALLER

export PATH="$test_dir/mock-bin:$test_dir/system-bin:$PATH" RUNNER_TEMP="$test_dir/runner temp"
export FIXTURE_INSTALLER="$test_dir/installer"
export GITHUB_PATH="$test_dir/github path" SYSTEM_BINARY="$test_dir/system-bin/unmeshed"

run_success() {
  : > "$GITHUB_PATH"
  bash "$repo_dir/install.sh" > "$test_dir/log"
  installed_dir=$(cat "$GITHUB_PATH")
  [[ "$installed_dir" == "$RUNNER_TEMP"/unmeshed.*/bin ]]
  [[ -x "$installed_dir/unmeshed" ]]
  [[ $("$installed_dir/unmeshed") == verified-cli ]]
  [[ $("$SYSTEM_BINARY") == system-cli ]]
}

run_failure() {
  : > "$GITHUB_PATH"
  if bash "$repo_dir/install.sh" > "$test_dir/log" 2>&1; then
    echo 'Expected installation to fail' >&2
    exit 1
  fi
  [[ ! -s "$GITHUB_PATH" ]]
  [[ $("$SYSTEM_BINARY") == system-cli ]]
}

for pair in 'Linux X64' 'Linux ARM64' 'macOS X64' 'macOS ARM64'; do
  read -r RUNNER_OS RUNNER_ARCH <<< "$pair"
  export RUNNER_OS RUNNER_ARCH
  EXPECTED_VERSION=latest run_success
  UNMESHED_VERSION=1.2.3 EXPECTED_VERSION=1.2.3 run_success
done

RUNNER_OS=Windows run_failure
UNMESHED_VERSION='../latest' run_failure
MOCK_HTTP_ERROR=yes run_failure
MOCK_INSTALLER_ERROR=yes EXPECTED_VERSION=latest run_failure
MOCK_SKIP_BINARY=yes EXPECTED_VERSION=latest run_failure
MOCK_SYMLINK_BINARY=yes EXPECTED_VERSION=latest run_failure

printf '#!/bin/sh\nexit 1\n' > "$test_dir/old-installer"
FIXTURE_INSTALLER="$test_dir/old-installer" run_failure

echo 'All installer tests passed'
