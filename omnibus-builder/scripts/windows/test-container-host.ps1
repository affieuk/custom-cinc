<#
.SYNOPSIS
  Prove the Windows Server 2025 WCOW substrate before building the Cinc image.
.DESCRIPTION
  Uses nerdctl only for the containerd pull/runtime check and deliberately runs
  the WCOW probe with --net=none. The current nerdctl Windows default-network
  path can panic when it encounters the externally-created HNS/CNI NAT network.

  Image construction is tested with buildctl directly, matching BuildKit's
  native Windows guidance. The second build probe performs an HTTPS request to
  omnitruck.cinc.sh so that BuildKit/containerd/CNI outbound networking is
  proven before the real Cinc omnibus-windows image is attempted.
#>
[CmdletBinding()]
param(
  [string]$BaseImage = 'mcr.microsoft.com/dotnet/framework/runtime:3.5-windowsservercore-ltsc2022'
)
$ErrorActionPreference = 'Stop'

function Invoke-Native {
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(ValueFromRemainingArguments)][string[]]$Arguments
  )
  & $FilePath @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "$FilePath $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
  }
}

foreach ($cmd in 'containerd','nerdctl','buildctl','ctr') {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    throw "$cmd is not on PATH; install/configure the Windows container toolchain described in README.md."
  }
}

Write-Host '==> Host inventory'
Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber | Format-List
Invoke-Native containerd '--version'
Invoke-Native nerdctl 'version'
Invoke-Native buildctl '--version'
Invoke-Native buildctl 'debug' 'workers'

Write-Host "==> Pull/runtime check: $BaseImage"
Invoke-Native nerdctl 'pull' $BaseImage
# No network is needed to prove WCOW execution. Avoid nerdctl's experimental
# Windows default-network path; BuildKit networking is tested separately below.
Invoke-Native nerdctl 'run' '--rm' '--net=none' '--pull=never' $BaseImage 'cmd' '/S' '/C' 'ver'

$temp = Join-Path $env:TEMP 'cinc-wcow-build-probe'
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $temp
New-Item -ItemType Directory -Path $temp | Out-Null
try {
  @(
    '# escape=`',
    "FROM $BaseImage",
    'RUN cmd /S /C echo WCOW image build probe OK'
  ) | Set-Content -Encoding ascii (Join-Path $temp 'Dockerfile')

  Write-Host '==> Trivial WCOW BuildKit image build/export'
  Invoke-Native buildctl 'build' `
    '--frontend' 'dockerfile.v0' `
    '--local' "context=$temp" `
    '--local' "dockerfile=$temp" `
    '--output' 'type=image,name=localhost/cinc-wcow-build-probe:ltsc2022'

  $probeImageRefs = @(& ctr.exe --namespace buildkit images ls --quiet)
  if ($LASTEXITCODE -ne 0 -or -not ($probeImageRefs -contains 'localhost/cinc-wcow-build-probe:ltsc2022')) {
    throw 'BuildKit reported success but the probe image is not present in the containerd buildkit namespace.'
  }

  @(
    '# escape=`',
    "FROM $BaseImage",
    'SHELL ["powershell.exe", "-NoLogo", "-NoProfile", "-Command"]',
    'RUN $r = Invoke-WebRequest -UseBasicParsing https://omnitruck.cinc.sh/install.sh; `',
    "    Write-Host ('HTTP status: ' + `$r.StatusCode); `",
    '    if ($r.StatusCode -ne 200) { exit 1 }'
  ) | Set-Content -Encoding ascii (Join-Path $temp 'Dockerfile')

  Write-Host '==> BuildKit outbound-network probe'
  Invoke-Native buildctl 'build' `
    '--frontend' 'dockerfile.v0' `
    '--local' "context=$temp" `
    '--local' "dockerfile=$temp" `
    '--output' 'type=image,name=localhost/cinc-wcow-network-probe:ltsc2022'

  Write-Host 'PASS: WCOW pull/runtime + BuildKit image export + BuildKit outbound networking'
} finally {
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $temp
}
