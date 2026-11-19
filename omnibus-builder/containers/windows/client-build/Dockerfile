# escape=`
ARG BUILDER_IMAGE=localhost/cinc-omnibus-builder:windows-ltsc2022-26.0.3
FROM ${BUILDER_IMAGE} AS build
ARG REF
ARG CLIENT_REPO=https://gitlab.com/cinc-project/distribution/client.git
ARG CLIENT_REF=master
ARG EXPECTED_TARGET_VERSION
ENV REF=${REF} `
    CLIENT_REPO=${CLIENT_REPO} `
    CLIENT_REF=${CLIENT_REF} `
    EXPECTED_TARGET_VERSION=${EXPECTED_TARGET_VERSION}
COPY scripts/client C:/handoff/scripts/client
COPY scripts/windows/build-client-in-builder.sh C:/handoff/scripts/windows/build-client-in-builder.sh
COPY scripts/windows/patch-omnibus-git-cache.sh C:/handoff/scripts/windows/patch-omnibus-git-cache.sh
COPY overrides/cinc C:/handoff/overrides/cinc
SHELL ["cmd", "/S", "/C"]
RUN --mount=type=cache,id=cinc-client-windows-bundle-v1,target=C:/cinc-client-windows-cache/bundle,sharing=locked `
    --mount=type=cache,id=cinc-client-windows-omnibus-v1,target=C:/cinc-client-windows-cache/omnibus,sharing=locked `
    C:\msys64\usr\bin\bash.exe -lc "/c/handoff/scripts/windows/build-client-in-builder.sh"
# WCOW BuildKit can trip while snapshotting a Windows Update .tmp file that
# disappears under SoftwareDistribution. The package is already built at this
# point, so remove only that transient update cache before the artifact export.
SHELL ["powershell", "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]
RUN Get-Service -Name wuauserv,bits -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue; `
    if (Test-Path 'C:\Windows\SoftwareDistribution\Download') { `
      Remove-Item -Recurse -Force -ErrorAction SilentlyContinue 'C:\Windows\SoftwareDistribution\Download\*' `
    }
SHELL ["cmd", "/S", "/C"]
FROM scratch AS artifacts
COPY --from=build C:/artifacts/ /
