#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/mock-bin" "$test_dir/work"

ruby -e '
  require "yaml"
  workflow = YAML.load_file(ARGV[0])
  detect = workflow["jobs"]["detect"]["steps"].find { |step| step["id"] == "version" }
  update = workflow["jobs"]["update"]["steps"].find { |step| step["id"] == "readme" }
  commit = workflow["jobs"]["update"]["steps"].find { |step| step["name"] == "Commit updated example to default branch" }
  abort "detect job must be read-only" unless workflow["jobs"]["detect"]["permissions"] == {"contents" => "read"}
  abort "updater must only have contents:write" unless workflow["jobs"]["update"]["permissions"] == {"contents" => "write"}
  File.write(ARGV[1], detect.fetch("run"))
  File.write(ARGV[2], update.fetch("run"))
  File.write(ARGV[3], commit.fetch("run"))
' "$repo_dir/.github/workflows/update-cli-readme.yml" "$test_dir/detect.sh" "$test_dir/update.sh" "$test_dir/commit.sh"
bash -n "$test_dir/commit.sh"
if grep -Eq -- 'force|gh pr|pull-requests:' "$test_dir/commit.sh"; then
  echo 'Direct update must not force-push or use PR commands' >&2
  exit 1
fi

cat > "$test_dir/mock-bin/unmeshed" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$MOCK_VERSION_OUTPUT"
MOCK
chmod +x "$test_dir/mock-bin/unmeshed"

export PATH="$test_dir/mock-bin:$PATH"
export GITHUB_OUTPUT="$test_dir/output" GITHUB_STEP_SUMMARY="$test_dir/summary"
: > "$GITHUB_OUTPUT"; : > "$GITHUB_STEP_SUMMARY"
MOCK_VERSION_OUTPUT='unmeshed version v1.4.0 commit abc' bash "$test_dir/detect.sh"
[[ $(cat "$GITHUB_OUTPUT") == 'version=1.4.0' ]]
[[ $(cat "$GITHUB_STEP_SUMMARY") == *'`1.4.0`'* ]]

: > "$GITHUB_OUTPUT"
if MOCK_VERSION_OUTPUT='unmeshed version 1.04.0' bash "$test_dir/detect.sh" > "$test_dir/log" 2>&1; then
  echo 'Expected invalid semantic version to fail' >&2
  exit 1
fi
[[ ! -s $GITHUB_OUTPUT ]]

cp "$repo_dir/README.md" "$test_dir/work/README.md"
: > "$GITHUB_OUTPUT"
(cd "$test_dir/work" && CLI_VERSION=1.5.0 bash "$test_dir/update.sh")
[[ $(cat "$GITHUB_OUTPUT") == 'changed=true' ]]
grep -Fq "version: '1.5.0'" "$test_dir/work/README.md"

: > "$GITHUB_OUTPUT"
(cd "$test_dir/work" && CLI_VERSION=1.5.0 bash "$test_dir/update.sh")
[[ $(cat "$GITHUB_OUTPUT") == 'changed=false' ]]

: > "$GITHUB_OUTPUT"
if (cd "$test_dir/work" && CLI_VERSION='1.5.0;exit 0' bash "$test_dir/update.sh") > "$test_dir/log" 2>&1; then
  echo 'Expected unsafe version to fail' >&2
  exit 1
fi
[[ ! -s $GITHUB_OUTPUT ]]

echo 'README update workflow tests passed'
