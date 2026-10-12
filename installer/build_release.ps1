<#
  Builds a Windows release of the Optics desktop app and its installer.

  Usage (PowerShell, from the repository root):
    .\installer\build_release.ps1 -Version 1.0.0 -BuildNumber 1
    .\installer\build_release.ps1 -Version 1.0.1 -BuildNumber 2 -ApiBaseUrl https://optics-api.tera-software1.com/api/v1

  Needs: Flutter 3.44.8 on PATH, Visual Studio 2022 "Desktop development with C++",
  Inno Setup 6 (iscc.exe). Output: installer\Output\optics-setup-<Version>.exe + its SHA-256.
#>
param(
  [Parameter(Mandatory = $true)][string]$Version,
  [Parameter(Mandatory = $true)][int]$BuildNumber,
  [string]$ApiBaseUrl = "https://optics-api.tera-software1.com/api/v1",
  [string]$Iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Version must look like 1.2.3" }
if (-not (Test-Path $Iscc)) { throw "Inno Setup compiler not found at $Iscc" }

Push-Location (Join-Path $root "app")
try {
  flutter --version
  flutter pub get
  flutter test
  # APP_VERSION must equal --build-name: the app sends it to the update check.
  flutter build windows --release `
    --build-name=$Version --build-number=$BuildNumber `
    --dart-define=API_BASE_URL=$ApiBaseUrl `
    --dart-define=APP_VERSION=$Version
} finally {
  Pop-Location
}

& $Iscc "/DAppVersion=$Version" "/DBuildNumber=$BuildNumber" (Join-Path $PSScriptRoot "optics.iss")
if ($LASTEXITCODE -ne 0) { throw "iscc failed" }

$setup = Join-Path $PSScriptRoot "Output\optics-setup-$Version.exe"
$hash = (Get-FileHash -Algorithm SHA256 $setup).Hash.ToLower()
Write-Host ""
Write-Host "Installer: $setup"
Write-Host "SHA-256  : $hash"
Write-Host "Publish it in Django admin → App updates → Desktop app versions (upload the .exe;"
Write-Host "the SHA-256 is computed on upload) with version $Version and build $BuildNumber."
