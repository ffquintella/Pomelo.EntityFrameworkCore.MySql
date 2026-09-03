#!/usr/bin/env bash

set -Eeuo pipefail
shopt -s nullglob

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_directory="$(cd -- "$script_directory/.." && pwd)"
project_file="$project_directory/EFCore.MySql.IntegrationTests.csproj"
migration_directory="$project_directory/Migrations"

pre_existing_migrations=("$migration_directory"/*.cs)

if (( ${#pre_existing_migrations[@]} != 0 )); then
  printf 'Refusing to run with pre-existing migration sources: %s\n' "${pre_existing_migrations[*]}" >&2
  exit 1
fi

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/pomelo-legacy-migrations.XXXXXX")"

cleanup() {
  find "$migration_directory" -maxdepth 1 -type f -name '*.cs' -delete
  rm -rf "$temporary_directory"
}

trap cleanup EXIT

cd "$project_directory"

dotnet tool restore

dotnet_ef() {
  dotnet ef "$@" \
    --project "$project_file" \
    --startup-project "$project_file" \
    --context 'Pomelo.EntityFrameworkCore.MySql.IntegrationTests.AppDb'
}

dotnet_command() {
  dotnet "$@"
}

legacy_version_directories=("$project_directory"/LegacyMigrations/*/)

if (( ${#legacy_version_directories[@]} == 0 )); then
  printf '%s\n' 'No legacy migration sets were found.' >&2
  exit 1
fi

for legacy_version_directory in "${legacy_version_directories[@]}"; do
  legacy_version="$(basename "$legacy_version_directory")"
  legacy_files=("$legacy_version_directory"/*.csbak)

  if (( ${#legacy_files[@]} == 0 )); then
    printf 'No migration files were found for legacy version %s.\n' "$legacy_version" >&2
    exit 1
  fi

  find "$migration_directory" -maxdepth 1 -type f -name '*.cs' -delete
  dotnet_ef database drop -f

  for legacy_file in "${legacy_files[@]}"; do
    cp "$legacy_file" "$migration_directory/$(basename "${legacy_file%.csbak}").cs"
  done

  dotnet_ef migrations add Current --verbose
  dotnet_ef migrations script --output "$temporary_directory/$legacy_version-normal.sql" --verbose
  dotnet_ef migrations script --idempotent --output "$temporary_directory/$legacy_version-idempotent.sql" --verbose

  [[ -s "$temporary_directory/$legacy_version-normal.sql" ]]
  [[ -s "$temporary_directory/$legacy_version-idempotent.sql" ]]

  dotnet_ef database update --verbose

  # testMigrate exercises Database.Migrate() and asserts the final table set through the public integration CLI.
  dotnet_command run --project "$project_file" --no-build -- testMigrate
  dotnet_command test "$project_file" --no-build
done
