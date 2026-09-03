#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_directory/../../.." && pwd)"
consumer_project="$repository_root/test/EFCore.MySql.PackageConsumer/EFCore.MySql.PackageConsumer.csproj"
consumer_project_directory="$(dirname -- "$consumer_project")"
consumer_nuget_config="$repository_root/test/EFCore.MySql.PackageConsumer/NuGet.config"
package_output="${PACKAGE_OUTPUT:-$repository_root/artifacts/packages}"
provider_version="${POMELO_PACKAGE_VERSION:-10.0.0-rtm.3}"
efcore_floor_version="${EFCORE_FLOOR_VERSION:-10.0.0}"
efcore_latest_version="${EFCORE_LATEST_VERSION:-10.0.11}"
mysql_image="${MYSQL_IMAGE:-mysql:8.4.3}"
mariadb_image="${MARIADB_IMAGE:-mariadb:11.6.2}"
database_password="${DATABASE_PASSWORD:-Password12!}"
dotnet_working_directory="${DOTNET_WORKING_DIRECTORY:-$repository_root}"
consumer_packages_directories=()
active_consumer_packages_directory=
consumer_config_directory=
consumer_config_file=
migrations_directory="$consumer_project_directory/Migrations"
migrations_directory_created=false
containers=()
database_port=

fail() {
    printf 'Package consumer validation failed: %s\n' "$1" >&2
    exit 1
}

assert_assets_resolved() {
    local assets_file="$1"
    local package="$2"
    local version="$3"

    grep -F -q "\"$package/$version\"" "$assets_file"
}

if [[ "${PACKAGE_CONSUMER_SELF_TEST:-false}" == "true" ]]; then
    self_test_assets_file="$(mktemp "${TMPDIR:-/tmp}/pomelo-package-consumer-assets.XXXXXX")"
    cleanup_self_test() {
        rm -f -- "$self_test_assets_file"
    }
    trap cleanup_self_test EXIT

    printf '%s\n' \
        '{' \
        '  "libraries": {' \
        '    "Microsoft.EntityFrameworkCore/10.0.0": {},' \
        '    "Pomelo.EntityFrameworkCore.MySql/10.0.0": {}' \
        '  }' \
        '}' > "$self_test_assets_file"

    assert_assets_resolved "$self_test_assets_file" 'Microsoft.EntityFrameworkCore' '10.0.0' \
        || fail 'asset self-test did not find the expected EF Core package'
    assert_assets_resolved "$self_test_assets_file" 'Pomelo.EntityFrameworkCore.MySql' '10.0.0' \
        || fail 'asset self-test did not find the expected Pomelo package'
    if assert_assets_resolved "$self_test_assets_file" 'Missing.Package' '10.0.0'; then
        fail 'asset self-test unexpectedly found a missing package'
    fi

    printf 'Package consumer asset self-test passed (hit and miss).\n'
    exit 0
fi

if [[ -e "$migrations_directory" ]]; then
    fail "refusing to overwrite pre-existing migration directory: $migrations_directory"
fi

if [[ "$package_output" != /* ]]; then
    package_output="$repository_root/$package_output"
fi
mkdir -p -- "$package_output"
package_output="$(cd -- "$package_output" && pwd -P)"

cleanup() {
    if ((${#containers[@]} > 0)); then
        for container in "${containers[@]}"; do
            docker rm --force "$container" >/dev/null 2>&1 || true
        done
    fi

    if [[ "$migrations_directory_created" == true && -d "$migrations_directory" ]]; then
        rm -rf -- "$migrations_directory"
        printf 'Removed generated consumer migrations: %s\n' "$migrations_directory" >&2
    fi

    for packages_directory in "${consumer_packages_directories[@]}"; do
        if [[ -d "$packages_directory" ]]; then
            rm -rf -- "$packages_directory"
            printf 'Removed isolated consumer NuGet packages: %s\n' "$packages_directory" >&2
        fi
    done

    if [[ -n "$consumer_config_directory" && -d "$consumer_config_directory" ]]; then
        rm -rf -- "$consumer_config_directory"
        printf 'Removed temporary consumer NuGet config.\n' >&2
    fi
}

trap cleanup EXIT

run_dotnet() {
    (
        cd "$dotnet_working_directory"
        dotnet "$@"
    )
}

run_consumer_dotnet() {
    (
        cd "$dotnet_working_directory"
        NUGET_PACKAGES="$active_consumer_packages_directory" dotnet "$@"
    )
}

new_consumer_packages_directory() {
    active_consumer_packages_directory="$(mktemp -d "${TMPDIR:-/tmp}/pomelo-efcore10-package-consumer.XXXXXX")"
    consumer_packages_directories+=("$active_consumer_packages_directory")
    printf 'Using isolated consumer NuGet packages: %s\n' "$active_consumer_packages_directory" >&2
}

consumer_config_directory="$(mktemp -d "${TMPDIR:-/tmp}/pomelo-efcore10-package-consumer-config.XXXXXX")"
consumer_config_file="$consumer_config_directory/NuGet.config"
cp -- "$consumer_nuget_config" "$consumer_config_file"
run_dotnet nuget update source local-pomelo \
    --source "$package_output" \
    --configfile "$consumer_config_file" >/dev/null

source_projects=(
    "$repository_root/src/EFCore.MySql/EFCore.MySql.csproj"
    "$repository_root/src/EFCore.MySql.NTS/EFCore.MySql.NTS.csproj"
    "$repository_root/src/EFCore.MySql.Json.Microsoft/EFCore.MySql.Json.Microsoft.csproj"
    "$repository_root/src/EFCore.MySql.Json.Newtonsoft/EFCore.MySql.Json.Newtonsoft.csproj"
)

if [[ "${SKIP_PACKAGE:-false}" != "true" ]]; then
    # Restore and build with the floor first. The package metadata is regenerated after a
    # range restore below, while --no-build keeps these floor-compiled binaries intact.
    for project in "${source_projects[@]}"; do
        run_dotnet restore "$project" \
            --no-cache \
            -p:EFCoreVersion="$efcore_floor_version" \
            -p:Version="$provider_version"
    done

    for configuration in Debug Release; do
        for project in "${source_projects[@]}"; do
            run_dotnet build "$project" \
                -c "$configuration" \
                --no-restore \
                -p:EFCoreVersion="$efcore_floor_version" \
                -p:Version="$provider_version"
        done
    done

    # A range restore makes the generated nuspec retain the declared compatibility range. The
    # no-build pack then packages the binaries compiled against the 10.0.0 floor above.
    for project in "${source_projects[@]}"; do
        run_dotnet restore "$project" \
            --no-cache \
            -p:Version="$provider_version"
    done

    for project in "${source_projects[@]}"; do
        run_dotnet pack "$project" \
            -c Release \
            -o "$package_output" \
            --no-restore \
            --no-build \
            -p:Version="$provider_version"
    done

    provider_package="$package_output/Pomelo.EntityFrameworkCore.MySql.$provider_version.nupkg"
    provider_nuspec="$(unzip -p "$provider_package" '*.nuspec')"
    if [[ "$provider_nuspec" != *'version="[10.0.0, 10.0.999]"'* ]]; then
        printf 'The provider package does not declare EF Core [10.0.0,10.0.999].\n' >&2
        exit 1
    fi

    printf 'Provider package declares EF Core [10.0.0,10.0.999].\n'
fi

assert_restored_packages() {
    local efcore_version="$1"
    local assets_file="$consumer_project_directory/obj/project.assets.json"
    local package
    local package_directory
    local package_file
    local metadata_file
    local metadata_source
    local metadata_hash
    local expected_hash

    [[ -f "$assets_file" ]] || fail "consumer restore did not produce $assets_file"
    assert_assets_resolved "$assets_file" 'Microsoft.EntityFrameworkCore' "$efcore_version" \
        || fail "consumer restore did not resolve EF Core $efcore_version"

    for package in \
        Pomelo.EntityFrameworkCore.MySql \
        Pomelo.EntityFrameworkCore.MySql.Json.Microsoft \
        Pomelo.EntityFrameworkCore.MySql.Json.Newtonsoft \
        Pomelo.EntityFrameworkCore.MySql.NetTopologySuite; do
        assert_assets_resolved "$assets_file" "$package" "$provider_version" \
            || fail "consumer restore did not resolve $package $provider_version"

        package_directory="$active_consumer_packages_directory/$(printf '%s' "$package" | tr '[:upper:]' '[:lower:]')/$provider_version"
        package_file="$package_output/$package.$provider_version.nupkg"
        metadata_file="$package_directory/.nupkg.metadata"
        [[ -f "$package_file" ]] \
            || fail "expected local package artifact is missing: $package_file"
        [[ -f "$metadata_file" ]] \
            || fail "NuGet did not write package provenance metadata for $package"

        metadata_source="$(sed -n 's/.*"source"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$metadata_file")"
        [[ "$metadata_source" == "$package_output" ]] \
            || fail "NuGet restored $package from an unexpected package source"

        metadata_hash="$(sed -n 's/.*"contentHash"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$metadata_file")"
        expected_hash="$(openssl dgst -sha512 -binary "$package_file" | base64 | tr -d '\n')"
        [[ -n "$metadata_hash" && "$metadata_hash" == "$expected_hash" ]] \
            || fail "NuGet package provenance hash mismatch for $package"
    done

    printf 'Local Pomelo package provenance verified for EF Core %s.\n' "$efcore_version"
}

start_database() {
    local scenario_name="$1"
    local database_type="$2"
    local image="$3"
    local client
    local container_name="pomelo-efcore10-package-consumer-${scenario_name}-${database_type}-$$"
    local database_name="pomelo_package_consumer_${database_type}"
    local host_port
    local attempt

    if [[ "$database_type" == "mysql" ]]; then
        client=mysql
        docker run \
            --name "$container_name" \
            --env MYSQL_ROOT_PASSWORD="$database_password" \
            --env MYSQL_DATABASE="$database_name" \
            --publish 127.0.0.1::3306 \
            --detach \
            "$image" >/dev/null
    else
        client=mariadb
        docker run \
            --name "$container_name" \
            --env MARIADB_ROOT_PASSWORD="$database_password" \
            --env MARIADB_DATABASE="$database_name" \
            --publish 127.0.0.1::3306 \
            --detach \
            "$image" >/dev/null
    fi

    containers+=("$container_name")
    host_port="$(docker port "$container_name" 3306/tcp | sed -n 's/.*://p' | head -n 1)"

    for attempt in $(seq 1 120); do
        if docker exec "$container_name" "$client" \
            --protocol=socket \
            --user=root \
            --password="$database_password" \
            --execute='SELECT 1' >/dev/null 2>&1; then
            printf '%s database ready: image=%s port=%s attempts=%s\n' "$database_type" "$image" "$host_port" "$attempt" >&2
            database_port="$host_port"
            return 0
        fi

        sleep 1
    done

    docker logs "$container_name"
    return 1
}

run_consumer() {
    local scenario_name="$1"
    local database_type="$2"
    local efcore_version="$3"
    local image="$4"
    local port
    local connection_string

    new_consumer_packages_directory
    run_consumer_dotnet tool restore \
        --tool-manifest "$repository_root/dotnet-tools.json" \
        --configfile "$consumer_config_file"

    start_database "$scenario_name" "$database_type" "$image"
    port="$database_port"
    connection_string="Server=127.0.0.1;Port=$port;User ID=root;Password=$database_password;Database=pomelo_package_consumer_${database_type};"

    run_consumer_dotnet restore "$consumer_project" \
        --configfile "$consumer_config_file" \
        --no-cache \
        -p:ConsumerProviderVersion="$provider_version" \
        -p:ConsumerEfCoreVersion="$efcore_version"
    assert_restored_packages "$efcore_version"

    run_consumer_dotnet build "$consumer_project" \
        -c Release \
        --no-restore \
        -p:ConsumerProviderVersion="$provider_version" \
        -p:ConsumerEfCoreVersion="$efcore_version"

    migrations_directory_created=true
    ConsumerProviderVersion="$provider_version" \
    ConsumerEfCoreVersion="$efcore_version" \
    POMELO_PACKAGE_CONSUMER_CONNECTION_STRING="$connection_string" \
    POMELO_PACKAGE_CONSUMER_SERVER_TYPE="$database_type" \
        run_consumer_dotnet ef migrations add Initial \
            --project "$consumer_project" \
            --startup-project "$consumer_project" \
            --context SmokeContext \
            --output-dir Migrations \
            --configuration Release

    migration_file_count="$(find "$migrations_directory" -maxdepth 1 -type f -name '*.cs' | wc -l | tr -d ' ')"
    [[ "$migration_file_count" == 3 ]] \
        || fail "public migrations add generated $migration_file_count C# files, expected 3"
    [[ -f "$migrations_directory/SmokeContextModelSnapshot.cs" ]] \
        || fail "public migrations add did not generate the model snapshot"

    run_consumer_dotnet build "$consumer_project" \
        -c Release \
        --no-restore \
        -p:ConsumerProviderVersion="$provider_version" \
        -p:ConsumerEfCoreVersion="$efcore_version"

    ConsumerProviderVersion="$provider_version" \
    ConsumerEfCoreVersion="$efcore_version" \
    POMELO_PACKAGE_CONSUMER_CONNECTION_STRING="$connection_string" \
    POMELO_PACKAGE_CONSUMER_SERVER_TYPE="$database_type" \
        run_consumer_dotnet ef database update \
            --project "$consumer_project" \
            --startup-project "$consumer_project" \
            --context SmokeContext \
            --no-build \
            --configuration Release

    POMELO_PACKAGE_CONSUMER_CONNECTION_STRING="$connection_string" \
    POMELO_PACKAGE_CONSUMER_SERVER_TYPE="$database_type" \
        run_consumer_dotnet run \
            --project "$consumer_project" \
            -c Release \
            --no-restore \
            --no-build \
            -p:ConsumerProviderVersion="$provider_version" \
            -p:ConsumerEfCoreVersion="$efcore_version"

    rm -rf -- "$migrations_directory"
    migrations_directory_created=false
}

run_consumer floor-mysql mysql "$efcore_floor_version" "$mysql_image"
run_consumer floor-mariadb mariadb "$efcore_floor_version" "$mariadb_image"
run_consumer latest-mysql mysql "$efcore_latest_version" "$mysql_image"
run_consumer latest-mariadb mariadb "$efcore_latest_version" "$mariadb_image"

printf 'Package consumer validation passed for EF Core %s and %s on MySQL and MariaDB.\n' \
    "$efcore_floor_version" "$efcore_latest_version"
