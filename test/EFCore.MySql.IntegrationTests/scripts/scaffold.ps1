#!/usr/bin/env pwsh

$ErrorActionPreference = "Stop"

Push-Location (Join-Path (Split-Path $MyInvocation.MyCommand.Path) "../")

$projectFile = (Resolve-Path "EFCore.MySql.IntegrationTests.csproj").Path
$targetDirectoryName = "Scaffold"
$targetDirectoryCreated = $false

function Invoke-Dotnet([string[]] $arguments)
{
  & dotnet @arguments

  if ($LASTEXITCODE -ne 0)
  {
    throw "dotnet $($arguments -join ' ') failed with exit code $LASTEXITCODE"
  }
}

try
{
  Invoke-Dotnet "tool", "restore"

  if (Test-Path $targetDirectoryName)
  {
    throw "Refusing to overwrite existing generated output directory: $targetDirectoryName"
  }

  New-Item -ItemType Directory -Path $targetDirectoryName | Out-Null
  $targetDirectoryCreated = $true

  $tables = 'DataTypesSimple', 'DataTypesVariable'

  $connectionString = (Get-Content config.json -Raw | ConvertFrom-Json).Data.ConnectionString
  $arguments = @(
    "ef", "dbcontext", "scaffold", $connectionString, "Pomelo.EntityFrameworkCore.MySql",
    "--project", $projectFile,
    "--startup-project", $projectFile,
    "--context", "ScaffoldContext",
    "--output-dir", $targetDirectoryName,
    "--no-onconfiguring"
  )

  foreach ($table in $tables)
  {
    $arguments += "--table", $table
  }

  Invoke-Dotnet $arguments

  foreach ($table in $tables)
  {
    $file = Join-Path $targetDirectoryName ($table + '.cs')

    if (!(Test-Path $file -PathType Leaf))
    {
      throw "Failed to scaffold file: $file"
    }
  }

  $contextFile = Join-Path $targetDirectoryName "ScaffoldContext.cs"
  if (!(Test-Path $contextFile -PathType Leaf))
  {
    throw "Failed to scaffold context: $contextFile"
  }

  $expectedFiles = @("DataTypesSimple.cs", "DataTypesVariable.cs", "ScaffoldContext.cs")
  $actualFiles = @(Get-ChildItem $targetDirectoryName -File -Filter "*.cs" | Select-Object -ExpandProperty Name | Sort-Object)
  if (($actualFiles -join "|") -ne ($expectedFiles -join "|"))
  {
    throw "Unexpected generated C# files: $($actualFiles -join ', ')"
  }

  $contextSource = Get-Content $contextFile -Raw
  if ($contextSource -notmatch 'HasColumnType\("json"\)')
  {
    throw "Generated context did not preserve the JSON store type."
  }

  if ($contextSource -notmatch 'UseCollation\("[^"]+"\)' -or
      $contextSource -notmatch 'HasCharSet\("[^"]+"\)')
  {
    throw "Generated context did not preserve MySQL charset and collation metadata."
  }

  Invoke-Dotnet "build", $projectFile, "--no-restore", "--configuration", "Debug"
}
finally
{
  if ($targetDirectoryCreated)
  {
    Remove-Item -Recurse -Force $targetDirectoryName -ErrorAction SilentlyContinue
  }

  Pop-Location
}
