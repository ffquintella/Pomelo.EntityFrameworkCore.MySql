#!/usr/bin/env bash

set -Eeuo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_directory="$(cd -- "$script_directory/../.." && pwd)"
compliance_file="$repository_directory/test/EFCore.MySql.FunctionalTests/MySqlComplianceTest.cs"
ledger_file="$repository_directory/docs/efcore10-spec-deferrals.md"

# This is the immutable main tip used when EF Core 10 work started. The checkout
# must retain this commit (CI should use a full-history checkout); keeping the
# comparison fixed avoids auditing all historical skips in the repository.
baseline_commit="14c2cd558e37c71e7a2fca75e339ef902effdf60"

fail() {
  printf 'EF Core 10 specification audit failed: %s\n' "$1" >&2
  exit 1
}

trim() {
  local value="$1"
  value="${value#${value%%[![:space:]]*}}"
  value="${value%${value##*[![:space:]]}}"
  printf '%s' "$value"
}

[[ -f "$compliance_file" ]] || fail "compliance source was not found: $compliance_file"
[[ -f "$ledger_file" ]] || fail "ledger was not found: $ledger_file"
git -C "$repository_directory" cat-file -e "$baseline_commit^{commit}" \
  || fail "fixed audit baseline is unavailable: $baseline_commit"

is_valid_category() {
  case "$1" in
    database-native|upstream\ issue|historically\ unsupported|explicit\ follow-up)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# The table is deliberately machine-readable, but the document remains the
# source of the explanation and evidence for each entry.
while IFS='|' read -r _ kind key category owner reference _; do
  kind="$(trim "${kind:-}")"
  [[ "$kind" == base || "$kind" == method ]] || continue
  key="$(trim "${key:-}")"
  category="$(trim "${category:-}")"
  owner="$(trim "${owner:-}")"
  reference="$(trim "${reference:-}")"

  [[ -n "$key" ]] || fail "ledger row has no stable source key"
  is_valid_category "$category" || fail "invalid category for $kind $key: $category"
  [[ -n "$owner" && "$owner" != "-" ]] || fail "missing owner for $kind $key"
  [[ -n "$reference" && "$reference" != "-" ]] || fail "missing follow-up/reference for $kind $key"
done < "$ledger_file"

base_types_text="$(awk '
  /EF10-SPEC-DEFERRALS/ { in_block = 1 }
  in_block && /typeof\(/ {
    value = $0
    sub(/^.*typeof\(/, "", value)
    sub(/\).*/, "", value)
    print value
  }
  in_block && /};/ { exit }
' "$compliance_file")"

base_type_count="$(printf '%s\n' "$base_types_text" | awk 'NF { count++ } END { print count + 0 }')"
[[ "$base_type_count" == 39 ]] || fail "expected 39 EF Core 10 base ignores, found $base_type_count"

while IFS= read -r base_type; do
  [[ -n "$base_type" ]] || continue
  row_count="$(grep -F -c "| base | $base_type |" "$ledger_file" || true)"
  [[ "$row_count" == 1 ]] || fail "base ignore is missing or duplicated in the ledger: $base_type"
done <<< "$base_types_text"

extract_ignored_types() {
  awk '
    function emit_type(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      if (value != "") {
        print value
      }
    }
    function scan(line,    start, closing_position) {
      sub(/\/\/.*$/, "", line)
      while (1) {
        if (in_type) {
          closing_position = index(line, ")")
          if (closing_position == 0) {
            type_value = type_value line
            return
          }
          emit_type(type_value substr(line, 1, closing_position - 1))
          in_type = 0
          type_value = ""
          line = substr(line, closing_position + 1)
        }

        start = index(line, "typeof(")
        if (start == 0) {
          return
        }
        line = substr(line, start + 7)
        closing_position = index(line, ")")
        if (closing_position == 0) {
          in_type = 1
          type_value = line
          return
        }
        emit_type(substr(line, 1, closing_position - 1))
        line = substr(line, closing_position + 1)
      }
    }
    /IgnoredTestBases/ && /new HashSet<Type>/ {
      in_initializer = 1
      next
    }
    in_initializer {
      scan($0)
      if (!in_type && $0 ~ /^[[:space:]]*};/) {
        exit
      }
    }
  '
}

baseline_ignored_types="$(git -C "$repository_directory" show "$baseline_commit:test/EFCore.MySql.FunctionalTests/MySqlComplianceTest.cs" | extract_ignored_types | sort -u)"
current_ignored_types="$(extract_ignored_types < "$compliance_file" | sort -u)"
added_ignored_types="$(comm -13 <(printf '%s\n' "$baseline_ignored_types") <(printf '%s\n' "$current_ignored_types") || true)"

while IFS= read -r added_type; do
  [[ -n "$added_type" ]] || continue
  row_count="$(grep -F -c "| base | $added_type |" "$ledger_file" || true)"
  [[ "$row_count" == 1 ]] || fail "new ignored base is missing or duplicated in the ledger: $added_type"
done <<< "$added_ignored_types"

expected_method_keys='test/EFCore.MySql.FunctionalTests/LazyLoadProxyMySqlTest.cs#Top_level_projection_track_entities_before_passing_to_client_method()
test/EFCore.MySql.FunctionalTests/MigrationsInfrastructureMySqlTest.cs#Can_apply_two_migrations_in_transaction_async()
test/EFCore.MySql.FunctionalTests/MigrationsMySqlTest.cs#Convert_string_column_to_a_json_column_containing_collection()
test/EFCore.MySql.FunctionalTests/MigrationsMySqlTest.cs#Convert_string_column_to_a_json_column_containing_reference()
test/EFCore.MySql.FunctionalTests/MigrationsMySqlTest.cs#Multiop_rename_table_and_create_new_table_with_the_old_name()
test/EFCore.MySql.FunctionalTests/MigrationsMySqlTest.cs#Multiop_rename_table_and_drop()
test/EFCore.MySql.FunctionalTests/MigrationsMySqlTest.cs#Rename_table_with_json_column()
test/EFCore.MySql.FunctionalTests/Query/AdHocQuerySplittingQueryMySqlTest.cs#Can_query_with_nav_collection_in_projection_with_split_query_in_parallel_async()
test/EFCore.MySql.FunctionalTests/Query/AdHocQuerySplittingQueryMySqlTest.cs#Can_query_with_nav_collection_in_projection_with_split_query_in_parallel_sync()
test/EFCore.MySql.FunctionalTests/Query/FromSqlQueryMySqlTest.cs#Multiple_occurrences_of_FromSql_with_db_parameter_adds_two_parameters(bool async)
test/EFCore.MySql.FunctionalTests/Query/NonSharedPrimitiveCollectionsQueryMySqlTest.cs#Column_collection_inside_json_owned_entity()
test/EFCore.MySql.FunctionalTests/Query/NorthwindMiscellaneousQueryMySqlTest.cs#Where_nanosecond_and_microsecond_component(bool async)
test/EFCore.MySql.FunctionalTests/Query/PrimitiveCollectionsQueryMySqlTest.cs#Inline_collection_index_Column_with_EF_Constant()
test/EFCore.MySql.FunctionalTests/Query/SqlQueryMySqlTest.cs#Multiple_occurrences_of_SqlQuery_with_db_parameter_adds_two_parameters(bool async)'

extract_skipped_methods() {
  local include_line="${1:-0}"

  awk -v include_line="$include_line" '
    function emit_method(declaration,    open_position, close_position, method_name, parameters, signature) {
      sub(/^.*\][[:space:]]*/, "", declaration)
      sub(/^[[:space:]]*(public|protected|private|internal)[[:space:]]*/, "", declaration)
      open_position = index(declaration, "(")
      if (open_position == 0) {
        return
      }
      method_name = substr(declaration, 1, open_position - 1)
      sub(/^.*[[:space:]]/, "", method_name)
      parameters = substr(declaration, open_position + 1)
      close_position = index(parameters, ")")
      if (close_position > 0) {
        parameters = substr(parameters, 1, close_position - 1)
      }
      gsub(/[[:space:]]+/, " ", parameters)
      sub(/^[[:space:]]+/, "", parameters)
      sub(/[[:space:]]+$/, "", parameters)
      signature = method_name "(" parameters ")"
      if (include_line) {
        print skip_line "\t" signature
      } else {
        print signature
      }
    }
    /Skip[[:space:]]*=/ {
      pending = 1
      skip_line = FNR
      if ($0 ~ /\][[:space:]]*(public|protected|private|internal)[[:space:]]/) {
        emit_method($0)
        pending = 0
      }
      next
    }
    pending && /^[[:space:]]*(public|protected|private|internal)[[:space:]]/ {
      emit_method($0)
      pending = 0
      next
    }
    /^[[:space:]]*(public|protected|private|internal)[[:space:]]/ { pending = 0 }
  '
}

extract_added_skip_lines() {
  local file_path="$1"

  # Signature keys catch a Skip moved to another overload. A persistent Skip
  # whose EF10 override signature evolved is ignored unless its attribute line
  # was added, which keeps API evolution distinct from a newly moved deferral.
  git -C "$repository_directory" diff --unified=0 "$baseline_commit" -- "$file_path" |
    awk '
      /^@@/ {
        header = $0
        sub(/^.*\+/, "", header)
        sub(/,.*/, "", header)
        current_line = header + 0
        next
      }
      /^\+\+\+/ { next }
      /^\+/ {
        if ($0 ~ /Skip[[:space:]]*=/) {
          print current_line
        }
        current_line++
        next
      }
      /^-/ { next }
      { current_line++ }
    '
}

current_added_method_keys=""
while IFS= read -r file_path; do
  [[ -f "$repository_directory/$file_path" ]] || continue
  baseline_methods="$(git -C "$repository_directory" show "$baseline_commit:$file_path" 2>/dev/null | extract_skipped_methods | sort || true)"
  current_methods_with_lines="$(extract_skipped_methods include-line < "$repository_directory/$file_path" | sort || true)"
  current_methods="$(printf '%s\n' "$current_methods_with_lines" | cut -f2- | sort)"
  added_skip_lines="$(extract_added_skip_lines "$file_path" || true)"
  added_methods="$(comm -13 <(printf '%s\n' "$baseline_methods") <(printf '%s\n' "$current_methods") || true)"

  while IFS= read -r method_signature; do
    [[ -n "$method_signature" ]] || continue
    method_name="${method_signature%%(*}"
    baseline_has_same_name="$(printf '%s\n' "$baseline_methods" | awk -v method_name="$method_name" '
      {
        signature = $0
        sub(/\(.*/, "", signature)
        if (signature == method_name) {
          found = 1
        }
      }
      END { print found + 0 }
    ')"
    if [[ "$baseline_has_same_name" == 1 ]]; then
      current_skip_was_added=0
      while IFS=$'\t' read -r skip_line current_signature; do
        [[ "$current_signature" == "$method_signature" ]] || continue
        if printf '%s\n' "$added_skip_lines" | grep -F -x -q "$skip_line"; then
          current_skip_was_added=1
          break
        fi
      done <<< "$current_methods_with_lines"
      [[ "$current_skip_was_added" == 1 ]] || continue
    fi
    method_key="$file_path#$method_signature"
    current_added_method_keys+="$method_key\n"
    row_count="$(grep -F -c "| method | $method_key |" "$ledger_file" || true)"
    [[ "$row_count" == 1 ]] || fail "new method-level skip is missing or duplicated in the ledger: $method_key"
  done <<< "$added_methods"
done < <(git -C "$repository_directory" diff --name-only "$baseline_commit" -- test/EFCore.MySql.FunctionalTests | grep -E '\.cs$')

expected_method_count="$(printf '%s\n' "$expected_method_keys" | awk 'NF { count++ } END { print count + 0 }')"
actual_method_count="$(printf '%b' "$current_added_method_keys" | awk 'NF { count++ } END { print count + 0 }')"
[[ "$actual_method_count" == "$expected_method_count" ]] \
  || fail "fixed-baseline method skip inventory changed: expected $expected_method_count, found $actual_method_count"

while IFS= read -r method_key; do
  [[ -n "$method_key" ]] || continue
  printf '%b' "$current_added_method_keys" | grep -F -x -q "$method_key" \
    || fail "expected method-level skip is not present in the fixed-baseline diff: $method_key"
done <<< "$expected_method_keys"

ledger_base_count="$(grep -F -c '| base |' "$ledger_file" || true)"
ledger_method_count="$(grep -F -c '| method |' "$ledger_file" || true)"
[[ "$ledger_base_count" == 39 ]] || fail "ledger must contain 39 base rows, found $ledger_base_count"
[[ "$ledger_method_count" == 14 ]] || fail "ledger must contain 14 method rows, found $ledger_method_count"

printf 'EF Core 10 specification audit passed: 39 base ignores and 14 method-level skips are classified.\n'
