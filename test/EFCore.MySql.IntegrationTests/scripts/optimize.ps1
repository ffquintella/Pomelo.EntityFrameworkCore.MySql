#!/usr/bin/env pwsh

$ErrorActionPreference = "Stop"

Push-Location (Join-Path (Split-Path $MyInvocation.MyCommand.Path) "../")

$projectFile = (Resolve-Path "EFCore.MySql.IntegrationTests.csproj").Path
$configFile = (Resolve-Path "config.json" -ErrorAction SilentlyContinue)
$targetDirectoryName = "Optimize"
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
  if ($null -eq $configFile)
  {
    throw "Required integration test configuration was not found: config.json"
  }

  Invoke-Dotnet "tool", "restore"

  if (Test-Path $targetDirectoryName)
  {
    throw "Refusing to overwrite existing generated output directory: $targetDirectoryName"
  }

  New-Item -ItemType Directory -Path $targetDirectoryName | Out-Null
  $targetDirectoryCreated = $true

  $arguments = @(
    "ef", "dbcontext", "optimize",
    "--project", $projectFile,
    "--startup-project", $projectFile,
    "--context", "Pomelo.EntityFrameworkCore.MySql.IntegrationTests.AppDb",
    "--output-dir", $targetDirectoryName,
    "--namespace", "Pomelo.EntityFrameworkCore.MySql.IntegrationTests.Optimize",
    "--configuration", "Debug"
  )
  Invoke-Dotnet $arguments

  $requiredFiles = @(
    "AppDbAssemblyAttributes.cs",
    "AppDbModel.cs",
    "AppDbModelBuilder.cs",
    "AppIdentityUserEntityType.cs",
    "DataTypesSimpleEntityType.cs",
    "DataTypesVariableEntityType.cs",
    "ProductEntityType.cs",
    "SequenceEntityType.cs"
  )

  foreach ($generatedFile in $requiredFiles)
  {
    $file = Join-Path $targetDirectoryName $generatedFile

    if (!(Test-Path $file -PathType Leaf))
    {
      throw "Failed to generate compiled-model file: $file"
    }
  }

  Invoke-Dotnet "build", $projectFile, "--no-restore", "--configuration", "Debug"

  # This command resolves AppDb through the integration host, verifies the generated model type,
  # and executes a query against a real database using that model.
  Invoke-Dotnet "run", "--project", $projectFile, "--no-build", "--no-launch-profile", "--configuration", "Debug", "--", "compiledModel"
}
finally
{
  if ($targetDirectoryCreated)
  {
    Remove-Item -Recurse -Force $targetDirectoryName
  }

  Pop-Location
}
