<#
.SYNOPSIS
  Build and clean-validate a Windows Cinc Client MSI.
.DESCRIPTION
  Run on the Windows Server 2025 host. No target argument is required; this
  PowerShell entry point always builds the Windows LTSC2022 target.
#>
[CmdletBinding()]
param(
  [string]$Version,
  [string]$ToolchainVersion,
  [string]$ClientRef,
  [switch]$NoCache,
  [switch]$CleanBuildCaches,
  [switch]$SkipValidation
)
$ErrorActionPreference = 'Stop'
function Invoke-Native {
  param([Parameter(Mandatory)][string]$FilePath, [Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
  & $FilePath @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$FilePath $($Arguments -join ' ') failed with exit code $LASTEXITCODE" }
}
function Read-BuildDefaults([string]$Path) {
  $values = @{}
  foreach ($line in Get-Content $Path) { if ($line -match '^([A-Z0-9_]+)=(.*)$') { $values[$Matches[1]] = $Matches[2] } }
  return $values
}
foreach ($cmd in 'buildctl','ctr') { if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "$cmd is required on PATH" } }

$ProjectRoot = $PSScriptRoot
$defaults = Read-BuildDefaults (Join-Path $ProjectRoot 'config\build.env')
if (-not $Version) { $Version = $defaults['CINC_VERSION'] }
if (-not $ToolchainVersion) { $ToolchainVersion = $defaults['TOOLCHAIN_VERSION'] }
if (-not $ClientRef) { $ClientRef = $defaults['CINC_CLIENT_REF'] }
$ClientRepo = $defaults['CINC_CLIENT_REPO']
$BuilderImage = "localhost/cinc-omnibus-builder:windows-ltsc2022-$ToolchainVersion"
$BuildDockerfileDir = Join-Path $ProjectRoot 'containers\windows\client-build'
$ValidationDir = Join-Path $ProjectRoot 'containers\windows\client-validation'
$WorkRoot = Join-Path $ProjectRoot '.work\cinc-client-windows'
$ArtifactDir = Join-Path $ProjectRoot 'artifacts\cinc\windows'
$ValidationContext = Join-Path $WorkRoot 'validation'
$ValidationImage = "localhost/cinc-client-validation:windows-ltsc2022-$Version"
$BaseImage = 'mcr.microsoft.com/dotnet/framework/runtime:3.5-windowsservercore-ltsc2022'

$imageRefs = @(& ctr.exe --namespace buildkit images ls --quiet)
if ($LASTEXITCODE -ne 0 -or -not ($imageRefs -contains $BuilderImage)) { throw "builder image missing: $BuilderImage. Run .\build-omnibus-image.ps1 -ToolchainVersion $ToolchainVersion first." }
if ($CleanBuildCaches) {
  Invoke-Native buildctl 'prune' '--filter' 'type=exec.cachemount' '--filter' 'description~=cinc-client-windows-cache'
}
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $WorkRoot, $ArtifactDir
New-Item -ItemType Directory -Force -Path $WorkRoot, $ArtifactDir | Out-Null

$buildArgs = @(
  'build', '--progress', 'plain', '--frontend', 'dockerfile.v0',
  '--local', "context=$ProjectRoot", '--local', "dockerfile=$BuildDockerfileDir",
  '--opt', 'filename=Dockerfile', '--opt', 'image-resolve-mode=local',
  '--opt', "build-arg:BUILDER_IMAGE=$BuilderImage",
  '--opt', "build-arg:REF=v$Version", '--opt', "build-arg:CLIENT_REPO=$ClientRepo",
  '--opt', "build-arg:CLIENT_REF=$ClientRef", '--opt', "build-arg:EXPECTED_TARGET_VERSION=$Version",
  '--opt', 'target=artifacts', '--output', "type=local,dest=$ArtifactDir,mode=delete"
)
if ($NoCache) { $buildArgs += '--no-cache' }
Invoke-Native buildctl @buildArgs
$msis = @(Get-ChildItem -Path $ArtifactDir -Filter 'cinc*.msi' -File -Recurse)
if ($msis.Count -ne 1) { throw "expected exactly one Cinc MSI, found $($msis.Count) under $ArtifactDir" }
$Msi = $msis[0]

if (-not $SkipValidation) {
  New-Item -ItemType Directory -Force -Path $ValidationContext | Out-Null
  Copy-Item -Force $Msi.FullName (Join-Path $ValidationContext 'cinc.msi')
  Copy-Item -Force (Join-Path $ValidationDir 'Dockerfile') (Join-Path $ValidationContext 'Dockerfile')
  Copy-Item -Recurse -Force (Join-Path $ValidationDir 'cookbooks') (Join-Path $ValidationContext 'cookbooks')
  Copy-Item -Recurse -Force (Join-Path $ValidationDir 'profile') (Join-Path $ValidationContext 'profile')
  Copy-Item -Force (Join-Path $ValidationDir 'client.rb') (Join-Path $ValidationContext 'client.rb')
  Copy-Item -Force (Join-Path $ValidationDir 'validate-overrides.rb') (Join-Path $ValidationContext 'validate-overrides.rb')
  Copy-Item -Force (Join-Path $ProjectRoot 'overrides\cinc\omnibus.rb') (Join-Path $ValidationContext 'omnibus.rb')
  Copy-Item -Force (Join-Path $ProjectRoot 'overrides\cinc\Gemfile') (Join-Path $ValidationContext 'Gemfile')
  Invoke-Native buildctl 'build' '--progress' 'plain' '--frontend' 'dockerfile.v0' `
    '--local' "context=$ValidationContext" '--local' "dockerfile=$ValidationContext" `
    '--opt' 'filename=Dockerfile' '--opt' "build-arg:BASE_IMAGE=$BaseImage" '--opt' "build-arg:EXPECTED_TARGET_VERSION=$Version" `
    '--output' "type=image,name=$ValidationImage"
}
Write-Host ''
Write-Host "PASS: Cinc Client $Version Windows MSI built"
if (-not $SkipValidation) { Write-Host 'PASS: clean LTSC2022 client/solo/auditor validation' }
Write-Host "Artifact: $($Msi.FullName)"
