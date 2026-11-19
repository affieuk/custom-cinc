<#
.SYNOPSIS
  Build and validate the reusable Windows LTSC2022 Omnibus builder image.
.DESCRIPTION
  Run on the Windows Server 2025 WCOW host. The image consumes the requested
  published Cinc Omnibus Toolchain. No target argument is required because this
  PowerShell entry point has exactly one target: Windows LTSC2022.
#>
[CmdletBinding()]
param(
  [string]$ToolchainVersion,
  [string]$DockerImagesRef,
  [string]$Base = 'ltsc2022',
  [switch]$NoCache
)
$ErrorActionPreference = 'Stop'

function Invoke-Native {
  param([Parameter(Mandatory)][string]$FilePath, [Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
  & $FilePath @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$FilePath $($Arguments -join ' ') failed with exit code $LASTEXITCODE" }
}
function Read-BuildDefaults([string]$Path) {
  $values = @{}
  foreach ($line in Get-Content $Path) {
    if ($line -match '^([A-Z0-9_]+)=(.*)$') { $values[$Matches[1]] = $Matches[2] }
  }
  return $values
}
foreach ($cmd in 'git','nerdctl','buildctl','ctr') {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "$cmd is required on PATH" }
}

$ProjectRoot = $PSScriptRoot
$defaults = Read-BuildDefaults (Join-Path $ProjectRoot 'config\build.env')
if (-not $ToolchainVersion) { $ToolchainVersion = $defaults['TOOLCHAIN_VERSION'] }
if (-not $DockerImagesRef) { $DockerImagesRef = $defaults['CINC_DOCKER_IMAGES_REF'] }
$UpstreamRepo = $defaults['CINC_DOCKER_IMAGES_REPO']
$Image = "localhost/cinc-omnibus-builder:windows-ltsc2022-$ToolchainVersion"
$WorkRoot = Join-Path $ProjectRoot '.work\builder\windows'
$UpstreamDir = Join-Path $WorkRoot 'docker-images'
$Context = Join-Path $UpstreamDir 'omnibus-windows'
$Dockerfile = Join-Path $Context 'Dockerfile'
$BaseImage = "mcr.microsoft.com/dotnet/framework/runtime:3.5-windowsservercore-$Base"
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

if (-not (Test-Path (Join-Path $UpstreamDir '.git'))) { Invoke-Native git 'clone' $UpstreamRepo $UpstreamDir }
Push-Location $UpstreamDir
try {
  Invoke-Native git 'fetch' '--tags' 'origin' $DockerImagesRef
  Invoke-Native git 'checkout' '--force' 'FETCH_HEAD'
} finally { Pop-Location }
if (-not (Test-Path $Dockerfile)) { throw "upstream omnibus-windows Dockerfile missing: $Dockerfile" }

# Some redirector-selected MSYS2 mirrors rate-limit package downloads. Keep the
# builder on the primary MSYS2 repository. Apply once and fail if upstream has
# changed the initialization shape beyond recognition.
$MsysPrimaryMarker = 'Server = https://repo.msys2.org/msys/$arch/'
if (-not (Select-String -Path $Dockerfile -SimpleMatch $MsysPrimaryMarker -Quiet)) {
  $init = "    msys 'true'; ``"
  $lines = @(Get-Content $Dockerfile)
  if (@($lines | Where-Object { $_ -eq $init }).Count -ne 1) { throw 'could not locate the expected MSYS2 initialization line in upstream Dockerfile' }
  $insert = @'
    msys 'printf ''%s\n'' ''Server = https://repo.msys2.org/msys/$arch/'' > /etc/pacman.d/mirrorlist.msys; printf ''%s\n'' ''Server = https://repo.msys2.org/mingw/$repo/'' > /etc/pacman.d/mirrorlist.mingw'; `
'@.TrimEnd("`r", "`n")
  $patched = foreach ($line in $lines) { $line; if ($line -eq $init) { $insert } }
  [IO.File]::WriteAllLines($Dockerfile, [string[]]$patched, (New-Object System.Text.UTF8Encoding($false)))
}

Invoke-Native nerdctl 'pull' $BaseImage
$buildArgs = @(
  'build', '--progress', 'plain', '--frontend', 'dockerfile.v0',
  '--local', "context=$Context", '--local', "dockerfile=$Context",
  '--opt', "build-arg:BASE=$Base", '--opt', "build-arg:TOOLCHAIN_VERSION=$ToolchainVersion",
  '--output', "type=image,name=$Image"
)
if ($NoCache) { $buildArgs += '--no-cache' }
Invoke-Native buildctl @buildArgs

$imageRefs = @(& ctr.exe --namespace buildkit images ls --quiet)
if ($LASTEXITCODE -ne 0 -or -not ($imageRefs -contains $Image)) { throw "builder image is missing after BuildKit solve: $Image" }

# Smoke-test the actual toolchain environment in a fresh WCOW container.
$probe = '& C:\omnibus\load-omnibus-toolchain.ps1; ruby --version; bundle --version; git --version; gcc --version; make --version'
Invoke-Native nerdctl '--namespace' 'buildkit' 'run' '--rm' '--net=none' '--pull=never' $Image `
  'powershell.exe' '-NoLogo' '-NoProfile' '-Command' $probe

Write-Host ''
Write-Host "PASS: Windows LTSC2022 reusable builder $Image"
