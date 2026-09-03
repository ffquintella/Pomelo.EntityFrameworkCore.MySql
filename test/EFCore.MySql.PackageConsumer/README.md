# Package consumer smoke test

This is an external consumer of the locally packed Pomelo packages. It intentionally uses
`PackageReference` only; a `ProjectReference` would not verify the package boundary.

Run the complete local check from the repository root:

```sh
./test/EFCore.MySql.PackageConsumer/scripts/package-consumer.sh
```

The script compiles the provider against EF Core `10.0.0`, creates local packages whose
dependencies declare `[10.0.0,10.0.999]`, and runs four independent consumers:

* EF Core `10.0.0` against MySQL `8.4.3`.
* EF Core `10.0.0` against MariaDB `11.6.2`.
* EF Core `10.0.11` against MySQL `8.4.3`.
* EF Core `10.0.11` against MariaDB `11.6.2`.

Each consumer restores from the local package directory into a fresh NuGet cache, uses the
public `dotnet ef migrations add` and `database update` commands, then runs model construction,
CRUD, and a query against the migrated database. The four Pomelo packages (core, Microsoft JSON,
Newtonsoft JSON, and NetTopologySuite) are loaded and registered through their public extensions.

Both database servers run in disposable Docker containers. The source package version can be
overridden; the override is passed to source build, pack, and the consumer restore:

```sh
POMELO_PACKAGE_VERSION=10.0.0-ci.20260901 \
./test/EFCore.MySql.PackageConsumer/scripts/package-consumer.sh
```

Each consumer restore uses a fresh temporary global-packages directory, so a pre-existing package
with the same version cannot bypass the local package source. The script writes local packages
under `artifacts/packages` by default (or the `PACKAGE_OUTPUT` override), binds the temporary
NuGet configuration to that directory, and verifies each restored Pomelo package's source and
content hash. It removes the temporary cache and never pushes packages to a feed. It requires the
.NET 10 SDK, Docker, and network access to restore NuGet dependencies.
