#!/usr/bin/env bash

set -Eeuo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_directory="$(cd -- "$script_directory/.." && pwd)"
project_file="$project_directory/EFCore.MySql.IntegrationTests.csproj"
config_file="$project_directory/config.json"
target_directory_name="Scaffold"
target_directory="$project_directory/$target_directory_name"
target_directory_created=false

if [[ -e "$target_directory" ]]; then
  printf 'Refusing to overwrite existing generated output directory: %s\n' "$target_directory" >&2
  exit 1
fi

if [[ ! -f "$config_file" ]]; then
  printf 'Required integration test configuration was not found: %s\n' "$config_file" >&2
  exit 1
fi

connection_string="$(sed -n 's/.*"ConnectionString"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$config_file" | head -n 1)"

if [[ -z "$connection_string" ]]; then
  printf 'Data.ConnectionString was not found in %s\n' "$config_file" >&2
  exit 1
fi

cleanup() {
  if [[ "$target_directory_created" == true ]]; then
    rm -rf -- "$target_directory"
  fi
}

trap cleanup EXIT

cd "$project_directory"

dotnet tool restore
mkdir "$target_directory"
target_directory_created=true

dotnet ef dbcontext scaffold "$connection_string" Pomelo.EntityFrameworkCore.MySql \
  --project "$project_file" \
  --startup-project "$project_file" \
  --context ScaffoldContext \
  --output-dir "$target_directory_name" \
  --no-onconfiguring \
  --table DataTypesSimple \
  --table DataTypesVariable

for table in DataTypesSimple DataTypesVariable; do
  if [[ ! -f "$target_directory/$table.cs" ]]; then
    printf 'Failed to scaffold file: %s\n' "$target_directory/$table.cs" >&2
    exit 1
  fi
done

actual_files="$(find "$target_directory" -maxdepth 1 -type f -name '*.cs' -exec basename {} \; | LC_ALL=C sort | paste -sd ' ' -)"
expected_files='DataTypesSimple.cs DataTypesVariable.cs ScaffoldContext.cs'
if [[ "$actual_files" != "$expected_files" ]]; then
  printf 'Unexpected generated C# files: %s\n' "$actual_files" >&2
  exit 1
fi

if [[ ! -f "$target_directory/ScaffoldContext.cs" ]]; then
  printf 'Failed to scaffold context: %s\n' "$target_directory/ScaffoldContext.cs" >&2
  exit 1
fi

if ! rg -q 'HasColumnType\("json"\)' "$target_directory/ScaffoldContext.cs"; then
  printf 'Generated context did not preserve the JSON store type.\n' >&2
  exit 1
fi

if ! rg -q 'UseCollation\("[^" ]+"\)' "$target_directory/ScaffoldContext.cs" || \
   ! rg -q 'HasCharSet\("[^" ]+"\)' "$target_directory/ScaffoldContext.cs"; then
  printf 'Generated context did not preserve MySQL charset and collation metadata.\n' >&2
  exit 1
fi

dotnet build "$project_file" --no-restore --configuration Debug
