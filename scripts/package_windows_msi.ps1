param(
  [Parameter(Mandatory = $true)]
  [string]$ReleaseDir,

  [Parameter(Mandatory = $true)]
  [string]$AppVersion,

  [Parameter(Mandatory = $true)]
  [string]$OutputPath,

  [string]$WixSource = (Join-Path $PSScriptRoot '..\windows\installer\Package.wxs')
)

$ErrorActionPreference = 'Stop'

$ReleaseDir = (Resolve-Path $ReleaseDir).Path
$WixSource = (Resolve-Path $WixSource).Path

if (-not (Test-Path (Join-Path $ReleaseDir 'QAQ.exe'))) {
  throw "Windows release executable not found in: $ReleaseDir"
}

$versionText = $AppVersion.Trim()
if ($versionText.StartsWith('v')) {
  $versionText = $versionText.Substring(1)
}

if ($versionText -notmatch '^(\d+)\.(\d+)\.(\d+)') {
  throw "AppVersion must start with major.minor.patch; got: $AppVersion"
}

$msiVersion = "$($Matches[1]).$($Matches[2]).$($Matches[3])"
Write-Host "MSI ProductVersion: $msiVersion"

$dotnetTools = Join-Path $HOME '.dotnet\tools'
if (-not (Get-Command wix -ErrorAction SilentlyContinue)) {
  Write-Host 'Installing WiX Toolset 6.0.2...'
  dotnet tool install --global wix --version 6.0.2
}
if ($env:PATH -notlike "*$dotnetTools*") {
  $env:PATH = "$dotnetTools;$env:PATH"
}

if (-not (Get-Command wix -ErrorAction SilentlyContinue)) {
  throw 'WiX CLI is not available after installation.'
}

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory) {
  New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
}

& wix build `
  -arch x64 `
  -bindpath $ReleaseDir `
  -define "MsiVersion=$msiVersion" `
  -pdbtype none `
  -out $OutputPath `
  $WixSource

if ($LASTEXITCODE -ne 0) {
  throw "WiX build failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path $OutputPath)) {
  throw "MSI was not produced: $OutputPath"
}

Get-Item $OutputPath | Format-List FullName, Length, LastWriteTime
