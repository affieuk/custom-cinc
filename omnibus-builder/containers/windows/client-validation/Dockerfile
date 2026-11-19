# escape=`
ARG BASE_IMAGE=mcr.microsoft.com/dotnet/framework/runtime:3.5-windowsservercore-ltsc2022
FROM ${BASE_IMAGE}
ARG EXPECTED_TARGET_VERSION
ENV EXPECTED_TARGET_VERSION=${EXPECTED_TARGET_VERSION}
SHELL ["powershell.exe", "-NoLogo", "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]
COPY cinc.msi C:/validation/cinc.msi
COPY cookbooks/ C:/validation/cookbooks/
COPY profile/ C:/validation/profile/
COPY client.rb C:/validation/client.rb
COPY omnibus.rb C:/validation/omnibus.rb
COPY Gemfile C:/validation/Gemfile
COPY validate-overrides.rb C:/validation/validate-overrides.rb
RUN $p = Start-Process msiexec.exe -ArgumentList '/i','C:\validation\cinc.msi','/qn','/norestart' -Wait -PassThru; `
    if ($p.ExitCode -ne 0) { throw ('MSI install failed with exit code {0}' -f $p.ExitCode) }; `
    $root = 'C:\cinc-project\cinc'; `
    $client = Join-Path $root 'bin\cinc-client.bat'; `
    $solo = Join-Path $root 'bin\cinc-solo.bat'; `
    $auditor = Join-Path $root 'bin\cinc-auditor.bat'; `
    $ruby = Join-Path $root 'embedded\bin\ruby.exe'; `
    foreach ($f in $client,$solo,$auditor,$ruby) { if (-not (Test-Path $f)) { throw ('required runtime missing: ' + $f) } }; `
    $clientVersion = (& $client --version | Out-String); if ($LASTEXITCODE) { throw 'cinc-client --version failed' }; Write-Host $clientVersion; if ($clientVersion -notmatch [regex]::Escape($env:EXPECTED_TARGET_VERSION)) { throw ('unexpected Cinc version: ' + $clientVersion) }; `
    & $solo --version; if ($LASTEXITCODE) { throw 'cinc-solo --version failed' }; `
    & $auditor version; if ($LASTEXITCODE) { throw 'cinc-auditor version failed' }; `
    & $ruby 'C:\validation\validate-overrides.rb' 'C:\validation\omnibus.rb' 'C:\validation\Gemfile'; if ($LASTEXITCODE) { throw 'override validation failed' }; `
    & $solo -N 'cinc-windows-validation' -c 'C:\validation\client.rb' -o 'recipe[cinc_validation]'; if ($LASTEXITCODE) { throw 'cinc-solo converge failed' }; `
    if (-not (Test-Path 'C:\validation\cinc-solo-converged.txt')) { throw 'cinc-solo validation marker missing' }; `
    & $auditor exec 'C:\validation\profile' --no-color; if ($LASTEXITCODE) { throw 'cinc-auditor profile failed' }
