#!/usr/bin/env bash

set -Eeuo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
validator_script="$script_directory/validate-efcore10-ci.sh"
package_consumer_script="$script_directory/../EFCore.MySql.PackageConsumer/scripts/package-consumer.sh"
portable_tool_path="/usr/bin:/bin"

fail() {
  printf 'EF Core 10 CI portability check failed: %s\n' "$1" >&2
  exit 1
}

[[ -x "$validator_script" ]] || fail "validator was not executable: $validator_script"
[[ -x "$package_consumer_script" ]] || fail "package consumer script was not executable: $package_consumer_script"

for required_tool in bash awk grep sort comm cut git dirname; do
  PATH="$portable_tool_path" command -v "$required_tool" >/dev/null 2>&1 \
    || fail "required POSIX tool is unavailable: $required_tool"
done
if PATH="$portable_tool_path" command -v rg >/dev/null 2>&1; then
  fail 'regression fixture unexpectedly exposes rg'
fi
PATH="$portable_tool_path" TMPDIR=/tmp PACKAGE_CONSUMER_SELF_TEST=true "$package_consumer_script" \
  || fail "package consumer asset self-test failed under the portable tool path"

PATH="$portable_tool_path" "$validator_script"
printf 'EF Core 10 CI portability check passed without ripgrep.\n'
