param(
  [ValidateSet('debug', 'release')]
  [string]$Mode = 'release',
  [string]$TargetPlatform = 'ohos-arm64'
)

$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$sourceRoot = $PSScriptRoot
$appRoot = Join-Path $projectRoot 'build\openharmony\app'
$appLib = Join-Path $appRoot 'lib'
$flutterCommand = Get-Command flutter -ErrorAction Stop
$flutterPath = $flutterCommand.Source

New-Item -ItemType Directory -Force -Path $appRoot, $appLib | Out-Null
$pubspec = Get-Content (Join-Path $sourceRoot 'pubspec.yaml') -Raw
$pubspec = $pubspec.Replace('path: ../..', 'path: ../../..')
Set-Content -Path (Join-Path $appRoot 'pubspec.yaml') -Value $pubspec -Encoding utf8
Copy-Item (Join-Path $sourceRoot 'lib\main.dart') (Join-Path $appLib 'main.dart') -Force
if (Test-Path (Join-Path $sourceRoot 'pubspec.lock')) {
  Copy-Item (Join-Path $sourceRoot 'pubspec.lock') (Join-Path $appRoot 'pubspec.lock') -Force
}

Push-Location $appRoot
try {
  if (-not (Test-Path (Join-Path $appRoot 'ohos\build-profile.json5'))) {
    & $flutterPath create --platforms ohos --org com.nebula --project-name ddns --no-pub .
    if ($LASTEXITCODE -ne 0) {
      throw 'OHOS project generation failed. Use the CPF-Flutter OpenHarmony SDK, not upstream Flutter.'
    }
  }

  & $flutterPath pub get
  if ($LASTEXITCODE -ne 0) {
    throw 'Flutter dependency resolution failed for the OHOS wrapper.'
  }

  & $flutterPath build hap "--$Mode" --target-platform $TargetPlatform
  if ($LASTEXITCODE -ne 0) {
    throw 'HAP build failed. Check the DevEco/OpenHarmony SDK and signing configuration.'
  }
} finally {
  Pop-Location
}

$hapFiles = Get-ChildItem $appRoot -Filter '*.hap' -File -Recurse -ErrorAction SilentlyContinue
if (-not $hapFiles) {
  throw "Build reported success, but no HAP artifact was found under $appRoot."
}

$hapFiles | ForEach-Object { Write-Host "HAP output: $($_.FullName)" }
