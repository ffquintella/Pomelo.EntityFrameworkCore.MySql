#!/usr/bin/env bash

set -Eeuo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_directory="$(cd -- "$script_directory/../.." && pwd)"
workflow_file="$repository_directory/.github/workflows/build.yml"
package_consumer_script="$repository_directory/test/EFCore.MySql.PackageConsumer/scripts/package-consumer.sh"

fail() {
  printf 'EF Core 10 CI contract failed: %s\n' "$1" >&2
  exit 1
}

[[ -f "$workflow_file" ]] || fail "workflow was not found: $workflow_file"
[[ -f "$package_consumer_script" ]] || fail "package consumer script was not found: $package_consumer_script"

# Keep comments out of the structural checks so a commented-out or decoy job cannot satisfy them.
workflow_content="$(awk '{ sub(/[[:space:]]+#.*/, ""); print }' "$workflow_file")"

job_block() {
  local requested_job="$1"

  printf '%s\n' "$workflow_content" | awk -v requested_job="$requested_job" '
    /^  [A-Za-z0-9_-]+:/ {
      current = $0
      sub(/^  /, "", current)
      sub(/:.*/, "", current)
      if (found) {
        exit
      }
      if (current == requested_job) {
        found = 1
        print
      }
      next
    }
    found { print }
  '
}

step_block() {
  local job="$1"
  local requested_step="$2"

  printf '%s\n' "$job" | awk -v requested_step="$requested_step" '
    /^      - name: / {
      current = $0
      sub(/^      - name: /, "", current)
      if (found) {
        exit
      }
      if (current == requested_step) {
        found = 1
        print
      }
      next
    }
    found { print }
  '
}

trigger_block() {
  local requested_trigger="$1"

  printf '%s\n' "$workflow_content" | awk -v requested_trigger="$requested_trigger" '
    /^on:/ { in_on = 1; next }
    in_on && /^[^[:space:]]/ { exit }
    in_on && /^  [A-Za-z0-9_-]+:/ {
      current = $0
      sub(/^  /, "", current)
      sub(/:.*/, "", current)
      if (found) {
        exit
      }
      if (current == requested_trigger) {
        found = 1
        print
      }
      next
    }
    in_on && found { print }
  '
}

require_job_literal() {
  local job_name="$1"
  local job="$2"
  local literal="$3"

  printf '%s\n' "$job" | grep -F -q -- "$literal" \
    || fail "$job_name job is missing: $literal"
}

require_step_literal() {
  local job_name="$1"
  local step_name="$2"
  local step="$3"
  local literal="$4"

  [[ -n "$step" ]] || fail "$job_name is missing step: $step_name"
  printf '%s\n' "$step" | grep -F -q -- "$literal" \
    || fail "$job_name/$step_name is missing: $literal"
}

run_body() {
  local step="$1"

  printf '%s\n' "$step" | awk '
    /^        run:[[:space:]]*\|[[:space:]]*$/ {
      in_run = 1
      next
    }
    /^        run:[[:space:]]+/ {
      line = $0
      sub(/^        run:[[:space:]]+/, "", line)
      print line
      in_run = 0
      next
    }
    in_run {
      if ($0 !~ /^          /) {
        if ($0 ~ /^[[:space:]]*$/) {
          next
        }
        in_run = 0
        next
      }
      line = $0
      sub(/^          /, "", line)
      if (line != "" && line !~ /^[[:space:]]/) {
        print line
      }
    }
  '
}

require_run_body_literals_in_order() {
  local job_name="$1"
  local step_name="$2"
  local step="$3"
  local previous_line=0
  local literal

  shift 3
  local commands

  commands="$(run_body "$step")"
  [[ -n "$commands" ]] || fail "$job_name/$step_name has no executable run body"

  for literal in "$@"; do
    local line

    line="$(printf '%s\n' "$commands" | awk -v literal="$literal" -v previous_line="$previous_line" '
      $0 == literal && NR > previous_line {
        print NR
        exit
      }
    ')"

    [[ -n "$line" ]] || fail "$job_name/$step_name is missing top-level run command: $literal"
    previous_line="$line"
  done
}

run_body_all_lines() {
  local step="$1"

  printf '%s\n' "$step" | awk '
    /^        run:[[:space:]]*\|[[:space:]]*$/ {
      in_run = 1
      next
    }
    /^        run:[[:space:]]+/ {
      line = $0
      sub(/^        run:[[:space:]]+/, "", line)
      if (line !~ /^[[:space:]]*#/ && line !~ /^[[:space:]]*$/) {
        print line
      }
      in_run = 0
      next
    }
    in_run {
      if ($0 !~ /^          /) {
        if ($0 ~ /^[[:space:]]*$/) {
          next
        }
        in_run = 0
        next
      }
      line = $0
      sub(/^          /, "", line)
      if (line !~ /^[[:space:]]*#/ && line !~ /^[[:space:]]*$/) {
        print line
      }
    }
  '
}

require_run_body_exact_commands() {
  local job_name="$1"
  local step_name="$2"
  local step="$3"
  local commands
  local expected_commands

  shift 3
  commands="$(run_body_all_lines "$step")"
  expected_commands="$(printf '%s\n' "$@")"
  [[ "$commands" == "$expected_commands" ]] \
    || fail "$job_name/$step_name must contain exactly the expected PowerShell commands"
}

require_run_body_unique_command() {
  local job_name="$1"
  local step_name="$2"
  local step="$3"
  local marker="$4"
  local expected_command="$5"
  local commands

  commands="$(run_body "$step")"
  if printf '%s\n' "$commands" | awk -v marker="$marker" -v expected_command="$expected_command" '
    index($0, marker) > 0 {
      count++
      if ($0 != expected_command) {
        invalid = 1
      }
    }
    END { exit(count == 1 && !invalid ? 0 : 1) }
  '; then
    return
  fi
  fail "$job_name/$step_name has an unexpected or repeated top-level command: $expected_command"
}

require_run_command() {
  local job_name="$1"
  local step_name="$2"
  local step="$3"
  local command_pattern="$4"

  if printf '%s\n' "$step" | grep -E -q -- "^[[:space:]]+run:[[:space:]]+${command_pattern}"; then
    return
  fi
  if printf '%s\n' "$step" | grep -E -q -- "^[[:space:]]+${command_pattern}"; then
    return
  fi
  fail "$job_name/$step_name is missing executable command: $command_pattern"
}

require_run_command_suffix() {
  local job_name="$1"
  local step_name="$2"
  local step="$3"
  local command_suffix="$4"

  if printf '%s\n' "$step" | awk -v command_suffix="$command_suffix" '
    /^[[:space:]]+run:/ {
      line = $0
      sub(/[[:space:]]+$/, "", line)
      if (length(line) >= length(command_suffix) && substr(line, length(line) - length(command_suffix) + 1) == command_suffix) {
        found = 1
      }
    }
    END { exit(found ? 0 : 1) }
  '; then
    return
  fi
  fail "$job_name/$step_name is missing command suffix: $command_suffix"
}

assert_full_history_checkout() {
  local job_name="$1"
  local job="$2"
  local checkout_step

  checkout_step="$(step_block "$job" Checkout)"
  require_step_literal "$job_name" Checkout "$checkout_step" 'uses: actions/checkout@v4'
  require_step_literal "$job_name" Checkout "$checkout_step" 'fetch-depth: 0'
}

assert_job_not_disabled() {
  local job_name="$1"
  local job="$2"
  local job_conditions

  job_conditions="$(printf '%s\n' "$job" | awk '/^    if:/ { print }')"
  [[ -z "$job_conditions" ]] \
    || fail "$job_name has a job-level if condition that can skip a required gate: $job_conditions"
}

assert_step_not_disabled() {
  local job_name="$1"
  local step_name="$2"
  local step="$3"
  local condition_lines
  local condition_count
  local expected_skip_condition='if: ${{ env.skipTests != '\''true'\'' }}'

  condition_lines="$(printf '%s\n' "$step" | awk '/^[[:space:]]+if:/ { value = $0; sub(/^[[:space:]]+/, "", value); print value }')"
  condition_count="$(printf '%s\n' "$condition_lines" | awk 'NF { count++ } END { print count + 0 }')"
  [[ "$condition_count" -le 1 ]] || fail "$job_name/$step_name has multiple conditions"
  if [[ "$condition_count" == 1 && "$condition_lines" != "$expected_skip_condition" ]]; then
    fail "$job_name/$step_name has an unexpected or disabling condition: $condition_lines"
  fi
}

assert_gate_step() {
  local job_name="$1"
  local job="$2"
  local step_name="$3"
  local step

  step="$(step_block "$job" "$step_name")"
  [[ -n "$step" ]] || fail "$job_name is missing required gate: $step_name"
  assert_step_not_disabled "$job_name" "$step_name" "$step"
}

ci_job="$(job_block CIContract)"
build_job="$(job_block BuildAndTest)"
package_consumer_job="$(job_block PackageConsumer)"
nuget_job="$(job_block NuGet)"
[[ -n "$ci_job" ]] || fail 'CIContract job was not found'
[[ -n "$build_job" ]] || fail 'BuildAndTest job was not found'
[[ -n "$package_consumer_job" ]] || fail 'PackageConsumer job was not found'
[[ -n "$nuget_job" ]] || fail 'NuGet job was not found'

for trigger_name in push pull_request; do
  trigger="$(trigger_block "$trigger_name")"
  [[ -n "$trigger" ]] || fail "on.$trigger_name trigger was not found"
  if printf '%s\n' "$trigger" | grep -E -q '^[[:space:]]+paths(-ignore)?:'; then
    fail "on.$trigger_name must not use paths or paths-ignore so EF Core 10 ledger changes trigger CI"
  fi
done

assert_job_not_disabled CIContract "$ci_job"
assert_job_not_disabled BuildAndTest "$build_job"
assert_job_not_disabled PackageConsumer "$package_consumer_job"

assert_full_history_checkout CIContract "$ci_job"
assert_full_history_checkout BuildAndTest "$build_job"
assert_full_history_checkout PackageConsumer "$package_consumer_job"
assert_full_history_checkout NuGet "$nuget_job"

env_block="$(printf '%s\n' "$workflow_content" | awk '
  /^env:/ { found = 1; print; next }
  found && /^[^[:space:]]/ { exit }
  found { print }
')"
require_step_literal workflow env "$env_block" 'skipAllTests: false'
require_step_literal workflow env "$env_block" 'skipWindowsTests: false'

require_job_literal CIContract "$ci_job" 'runs-on: ubuntu-latest'
ci_validation_step="$(step_block "$ci_job" 'Validate EF Core 10 CI contract')"
require_step_literal CIContract 'Validate EF Core 10 CI contract' "$ci_validation_step" 'run: ./test/EFCore.MySql.FunctionalTests/validate-efcore10-ci.sh'
assert_step_not_disabled CIContract 'Validate EF Core 10 CI contract' "$ci_validation_step"

require_job_literal BuildAndTest "$build_job" 'needs: CIContract'
require_job_literal BuildAndTest "$build_job" 'runs-on: ${{ matrix.os }}'
strategy_block="$(printf '%s\n' "$build_job" | awk '
  /^    strategy:/ { found = 1; print; next }
  found && /^    [A-Za-z0-9_-]+:/ { exit }
  found { print }
')"
[[ -n "$strategy_block" ]] || fail 'BuildAndTest strategy was not found'
require_step_literal BuildAndTest strategy "$strategy_block" 'fail-fast: false'
matrix_block="$(printf '%s\n' "$strategy_block" | awk '
  /^      matrix:/ { found = 1; print; next }
  found && /^      [A-Za-z0-9_-]+:/ { exit }
  found { print }
')"
[[ -n "$matrix_block" ]] || fail 'BuildAndTest matrix was not found'
if printf '%s\n' "$matrix_block" | grep -E -n '^[[:space:]]+(exclude|include):'; then
  fail 'BuildAndTest matrix must not alter the existing 2 x 9 release matrix'
fi

expected_database_versions='8.4.3-mysql
8.0.40-mysql
11.6.2-mariadb
11.5.2-mariadb
11.4.4-mariadb
11.3.2-mariadb
10.11.10-mariadb
10.6.20-mariadb
10.5.27-mariadb'
actual_database_versions="$(printf '%s\n' "$matrix_block" | awk '
  /^        dbVersion:/ { in_block = 1; next }
  /^        os:/ { in_block = 0 }
  in_block && /^[[:space:]]+- / {
    value = $0
    sub(/^[[:space:]]+- /, "", value)
    print value
  }
')"
[[ "$actual_database_versions" == "$expected_database_versions" ]] \
  || fail 'BuildAndTest database matrix changed: expected the existing nine versions'

expected_os='ubuntu-latest
windows-latest'
actual_os="$(printf '%s\n' "$matrix_block" | awk '
  /^        os:/ { in_block = 1; next }
  in_block && /^        [A-Za-z0-9_-]+:/ { in_block = 0 }
  in_block && /^[[:space:]]+- / {
    value = $0
    sub(/^[[:space:]]+- /, "", value)
    print value
  }
')"
[[ "$actual_os" == "$expected_os" ]] \
  || fail 'BuildAndTest OS matrix changed: expected ubuntu-latest and windows-latest'

required_gate_steps=(
  'EF Core 10 specification audit'
  'Build Solution'
  'Functional Tests'
  'Tests'
  'Integration Tests - Applying migrations'
  'Integration Tests - Scaffolding'
  'Integration Tests - Compiled model'
  'Integration Tests - With EF_BATCH_SIZE = 1'
  'Integration Tests - Legacy migrations'
)
for gate_step_name in "${required_gate_steps[@]}"; do
  assert_gate_step BuildAndTest "$build_job" "$gate_step_name"
done

build_step="$(step_block "$build_job" 'Build Solution')"
require_step_literal BuildAndTest 'Build Solution' "$build_step" 'dotnet build -c Debug -p:TreatWarningsAsErrors=true'
require_step_literal BuildAndTest 'Build Solution' "$build_step" 'dotnet build -c Release -p:TreatWarningsAsErrors=true'
require_step_literal BuildAndTest 'Build Solution' "$build_step" 'shell: pwsh'
set_variables_step="$(step_block "$build_job" 'Set additional variables')"
require_step_literal BuildAndTest 'Set additional variables' "$set_variables_step" 'shell: pwsh'
require_run_body_literals_in_order BuildAndTest 'Set additional variables' "$set_variables_step" \
  '$functionalTestMaxParallelThreads = $os -eq '\''linux'\'' -and $databaseServerType -eq '\''mariadb'\'' ? 1 : 0' \
  'echo "functionalTestMaxParallelThreads=$functionalTestMaxParallelThreads" >> $env:GITHUB_ENV'
require_run_body_unique_command BuildAndTest 'Set additional variables' "$set_variables_step" \
  '$functionalTestMaxParallelThreads = ' \
  '$functionalTestMaxParallelThreads = $os -eq '\''linux'\'' -and $databaseServerType -eq '\''mariadb'\'' ? 1 : 0'
require_run_body_unique_command BuildAndTest 'Set additional variables' "$set_variables_step" \
  'echo "functionalTestMaxParallelThreads=' \
  'echo "functionalTestMaxParallelThreads=$functionalTestMaxParallelThreads" >> $env:GITHUB_ENV'
output_variables_step="$(step_block "$build_job" 'Output Variables')"
require_run_body_literals_in_order BuildAndTest 'Output Variables' "$output_variables_step" \
  'echo "functionalTestMaxParallelThreads: ${{ env.functionalTestMaxParallelThreads }}"'
require_run_body_unique_command BuildAndTest 'Output Variables' "$output_variables_step" \
  'echo "functionalTestMaxParallelThreads:' \
  'echo "functionalTestMaxParallelThreads: ${{ env.functionalTestMaxParallelThreads }}"'
audit_step="$(step_block "$build_job" 'EF Core 10 specification audit')"
require_step_literal BuildAndTest 'EF Core 10 specification audit' "$audit_step" 'run: ./test/EFCore.MySql.FunctionalTests/audit-efcore10-spec-coverage.sh'
require_step_literal BuildAndTest 'EF Core 10 specification audit' "$audit_step" 'shell: bash'
functional_step="$(step_block "$build_job" 'Functional Tests')"
require_step_literal BuildAndTest 'Functional Tests' "$functional_step" 'shell: pwsh'
require_run_command BuildAndTest 'Functional Tests' "$functional_step" 'dotnet test .*test/EFCore[.]MySql[.]FunctionalTests'
require_run_command_suffix BuildAndTest 'Functional Tests' "$functional_step" '-- xUnit.MaxParallelThreads=${{ env.functionalTestMaxParallelThreads }}'
unit_step="$(step_block "$build_job" 'Tests')"
require_step_literal BuildAndTest 'Tests' "$unit_step" 'shell: pwsh'
require_run_command BuildAndTest 'Tests' "$unit_step" 'dotnet test .*test/EFCore[.]MySql[.]Tests'
migration_step="$(step_block "$build_job" 'Integration Tests - Applying migrations')"
require_step_literal BuildAndTest 'Integration Tests - Applying migrations' "$migration_step" 'shell: pwsh'
require_run_command BuildAndTest 'Integration Tests - Applying migrations' "$migration_step" 'dotnet run .*test/EFCore[.]MySql[.]IntegrationTests .*testMigrate'
integration_test_step="$(step_block "$build_job" 'Integration Tests - With EF_BATCH_SIZE = 1')"
require_step_literal BuildAndTest 'Integration Tests - With EF_BATCH_SIZE = 1' "$integration_test_step" 'shell: pwsh'
require_run_command BuildAndTest 'Integration Tests - With EF_BATCH_SIZE = 1' "$integration_test_step" 'dotnet test .*test/EFCore[.]MySql[.]IntegrationTests'
scaffold_step="$(step_block "$build_job" 'Integration Tests - Scaffolding')"
require_step_literal BuildAndTest 'Integration Tests - Scaffolding' "$scaffold_step" 'run: ./test/EFCore.MySql.IntegrationTests/scripts/scaffold.ps1'
require_step_literal BuildAndTest 'Integration Tests - Scaffolding' "$scaffold_step" 'shell: pwsh'
compiled_step="$(step_block "$build_job" 'Integration Tests - Compiled model')"
require_step_literal BuildAndTest 'Integration Tests - Compiled model' "$compiled_step" 'run: ./test/EFCore.MySql.IntegrationTests/scripts/optimize.ps1'
require_step_literal BuildAndTest 'Integration Tests - Compiled model' "$compiled_step" 'shell: pwsh'
legacy_step="$(step_block "$build_job" 'Integration Tests - Legacy migrations')"
require_step_literal BuildAndTest 'Integration Tests - Legacy migrations' "$legacy_step" 'shell: pwsh'
legacy_migration_directory='$migrationDirectory = '\''test/EFCore.MySql.IntegrationTests/Migrations'\'''
legacy_tracked_migrations='$trackedMigrations = @(git ls-files -- ":(glob)$migrationDirectory/*.cs")'
legacy_index_guard='if ($LASTEXITCODE -ne 0) { throw '\''git ls-files failed.'\'' }'
legacy_tracked_guard='if ($trackedMigrations.Count -ne 0) { throw '\''Refusing to run with tracked migration sources.'\'' }'
legacy_migration_cleanup='git clean -fX -- ":(glob)$migrationDirectory/*.cs"'
legacy_cleanup_guard='if ($LASTEXITCODE -ne 0) { throw '\''git clean failed.'\'' }'
legacy_script_path='./test/EFCore.MySql.IntegrationTests/scripts/legacy.ps1'
require_step_literal BuildAndTest 'Integration Tests - Legacy migrations' "$legacy_step" "$legacy_script_path"
require_run_body_exact_commands BuildAndTest 'Integration Tests - Legacy migrations' "$legacy_step" \
  "$legacy_migration_directory" \
  "$legacy_tracked_migrations" \
  "$legacy_index_guard" \
  "$legacy_tracked_guard" \
  "$legacy_migration_cleanup" \
  "$legacy_cleanup_guard" \
  "$legacy_script_path"

require_job_literal PackageConsumer "$package_consumer_job" 'needs: BuildAndTest'
require_job_literal PackageConsumer "$package_consumer_job" 'runs-on: ubuntu-latest'
package_step="$(step_block "$package_consumer_job" 'Pack and verify local package consumer')"
require_step_literal PackageConsumer 'Pack and verify local package consumer' "$package_step" 'run: ./test/EFCore.MySql.PackageConsumer/scripts/package-consumer.sh'
require_step_literal PackageConsumer 'Pack and verify local package consumer' "$package_step" 'shell: bash'
assert_step_not_disabled PackageConsumer 'Pack and verify local package consumer' "$package_step"
upload_step="$(step_block "$package_consumer_job" 'Upload package validation artifacts')"
require_step_literal PackageConsumer 'Upload package validation artifacts' "$upload_step" 'uses: actions/upload-artifact@v4'
require_step_literal PackageConsumer 'Upload package validation artifacts' "$upload_step" 'path: artifacts/packages'
assert_step_not_disabled PackageConsumer 'Upload package validation artifacts' "$upload_step"
if printf '%s\n' "$package_consumer_job" | grep -E -n 'dotnet nuget push|git tag|gh release'; then
  fail 'PackageConsumer must only verify and upload artifacts'
fi

require_job_literal NuGet "$nuget_job" 'needs: [BuildAndTest, PackageConsumer]'

for job in "$ci_job" "$build_job" "$package_consumer_job" "$nuget_job"; do
  if printf '%s\n' "$job" | grep -E -n 'continue-on-error:|\|\|[[:space:]]*true'; then
    fail 'workflow jobs must not mask product failures with continue-on-error or || true'
  fi
done

grep -F -q 'dotnet pack' "$package_consumer_script" \
  || fail 'package consumer validation must pack local artifacts'
grep -F -q 'compiledModel' "$repository_directory/test/EFCore.MySql.IntegrationTests/scripts/optimize.sh" \
  || fail 'compiled-model validation must execute its public runtime seam'

"$repository_directory/test/EFCore.MySql.FunctionalTests/audit-efcore10-spec-coverage.sh"
printf 'EF Core 10 CI contract passed: 2 OS x 9 database versions and all release gates are wired.\n'
