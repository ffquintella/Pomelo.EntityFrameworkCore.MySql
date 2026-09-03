#!/usr/bin/env bash

set -Eeuo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_directory="$(cd -- "$script_directory/.." && pwd)"
project_file="$project_directory/EFCore.MySql.IntegrationTests.csproj"
config_file="$project_directory/config.json"
target_directory_name="Optimize"
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

dotnet ef dbcontext optimize \
  --project "$project_file" \
  --startup-project "$project_file" \
  --context 'Pomelo.EntityFrameworkCore.MySql.IntegrationTests.AppDb' \
  --output-dir "$target_directory_name" \
  --namespace 'Pomelo.EntityFrameworkCore.MySql.IntegrationTests.Optimize' \
  --configuration Debug

for generated_file in \
  AppDbAssemblyAttributes.cs \
  AppDbModel.cs \
  AppDbModelBuilder.cs \
  AppIdentityUserEntityType.cs \
  DataTypesSimpleEntityType.cs \
  DataTypesVariableEntityType.cs \
  ProductEntityType.cs \
  SequenceEntityType.cs; do
  if [[ ! -f "$target_directory/$generated_file" ]]; then
    printf 'Failed to generate compiled-model file: %s\n' "$target_directory/$generated_file" >&2
    exit 1
  fi
done

dotnet build "$project_file" --no-restore --configuration Debug

# This command resolves AppDb through the integration host, verifies the generated model type,
# and executes a query against a real database using that model.
dotnet run --project "$project_file" --no-build --no-launch-profile --configuration Debug -- compiledModel
