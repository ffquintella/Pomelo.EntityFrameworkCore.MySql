#!/usr/bin/env pwsh

$ErrorActionPreference = 'Stop'

$projectDirectory = Join-Path (Split-Path $MyInvocation.MyCommand.Path) '../'
$migrationDirectory = Join-Path $projectDirectory 'Migrations'
$scriptOutputDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('pomelo-legacy-migrations-' + [Guid]::NewGuid().ToString('N'))

$preExistingMigrations = @(Get-ChildItem (Join-Path $migrationDirectory '*.cs') -File -ErrorAction SilentlyContinue)

if ($preExistingMigrations.Count -ne 0)
{
  throw "Refusing to run with pre-existing migration sources: $($preExistingMigrations.FullName -join ', ')"
}

function Invoke-DotNet([string[]] $arguments)
{
  & dotnet @arguments

  if ($LASTEXITCODE -ne 0)
  {
    throw "dotnet $($arguments -join ' ') failed with exit code $LASTEXITCODE"
  }
}

function Remove-GeneratedMigrations()
{
  Get-ChildItem (Join-Path $migrationDirectory '*.cs') -File -ErrorAction SilentlyContinue | Remove-Item -Force
}

Push-Location $projectDirectory

try
{
  New-Item -ItemType Directory -Path $scriptOutputDirectory | Out-Null
  Invoke-DotNet @('tool', 'restore')

  $legacyVersions = @(Get-ChildItem 'LegacyMigrations' -Directory | Sort-Object Name)

  if ($legacyVersions.Count -eq 0)
  {
    throw 'No legacy migration sets were found.'
  }

  foreach ($legacyVersionDirectory in $legacyVersions)
  {
    $legacyVersion = $legacyVersionDirectory.Name
    $legacyFiles = @(Get-ChildItem (Join-Path $legacyVersionDirectory.FullName '*.csbak') -File | Sort-Object Name)

    if ($legacyFiles.Count -eq 0)
    {
      throw "No migration files were found for legacy version $legacyVersion."
    }

    Remove-GeneratedMigrations
    Invoke-DotNet @('ef', 'database', 'drop', '-f')

    foreach ($legacyFile in $legacyFiles)
    {
      Copy-Item $legacyFile.FullName (Join-Path 'Migrations' ($legacyFile.BaseName + '.cs'))
    }

    Invoke-DotNet @('ef', 'migrations', 'add', 'Current', '--verbose')

    $normalScript = Join-Path $scriptOutputDirectory "$legacyVersion-normal.sql"
    $idempotentScript = Join-Path $scriptOutputDirectory "$legacyVersion-idempotent.sql"

    Invoke-DotNet @('ef', 'migrations', 'script', '--output', $normalScript, '--verbose')
    Invoke-DotNet @('ef', 'migrations', 'script', '--idempotent', '--output', $idempotentScript, '--verbose')

    if (!(Test-Path $normalScript -PathType Leaf) -or (Get-Item $normalScript).Length -eq 0)
    {
      throw "The normal migration script for legacy version $legacyVersion was not generated."
    }

    if (!(Test-Path $idempotentScript -PathType Leaf) -or (Get-Item $idempotentScript).Length -eq 0)
    {
      throw "The idempotent migration script for legacy version $legacyVersion was not generated."
    }

    Invoke-DotNet @('ef', 'database', 'update', '--verbose')

    # testMigrate exercises Database.Migrate() and asserts the final table set through the public integration CLI.
    Invoke-DotNet @('run', '--no-build', '--', 'testMigrate')
    Invoke-DotNet @('test', '--no-build')
  }
}
finally
{
  Remove-GeneratedMigrations

  if (Test-Path $scriptOutputDirectory)
  {
    Remove-Item $scriptOutputDirectory -Recurse -Force
  }

  Pop-Location
}
