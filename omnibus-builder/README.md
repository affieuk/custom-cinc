# Cinc Omnibus Builder

## Authoritative project intent

This README is the source of truth for this repository. Future maintenance, prompts, and chats must start here rather than reconstructing intent from old project history.

The repository exists to do **three things only**:

1. Build and validate a requested **Cinc Omnibus Toolchain RPM for RHEL 7**.
2. Build and validate **reusable Omnibus builder images** for RHEL 7, RHEL 8, RHEL 10, Ubuntu 22.04, and Windows Server Core LTSC 2022.
3. Use those reusable builders to build and validate **Cinc Client packages**, with simple overrides for Ruby, OpenSSL, and selected Ruby gems.

The desired end product is a working Cinc installation on each target. In particular, the installed package must have working `cinc-client`, `cinc-solo`, and `cinc-auditor` commands.

This is **not** a provenance system, evidence archive, historical research repository, AI handoff system, generic orchestration framework, or checksum catalogue. Do not add machinery merely to record how a build happened. Keep normal logs needed to diagnose failures; keep source/version pins only where they are technically useful to make a build behave predictably.

The test for keeping code is:

> Does it materially help build or validate one of the required outputs?

If the answer is no, it should normally not be in this repository.

### Deliberate product rule: no runtime `ruby-msys2-devkit`

The Windows builder needs MSYS2/compiler tooling to build native gems. The installed Cinc Client does not. `ruby-msys2-devkit` is deliberately removed from the Cinc Omnibus project before packaging because shipping a second development toolchain is unnecessary runtime bloat and additional attack surface. This rule is intentional and should remain unless the owner explicitly changes it.

## What the project builds

| Operation | Target | Result |
|---|---|---|
| RHEL7 toolchain | RHEL 7 | `omnibus-toolchain-<version>-*.rpm` |
| Reusable builders | RHEL7, RHEL8, RHEL10, Ubuntu 22.04 | Podman images on the Linux host |
| Reusable builder | Windows Server Core LTSC2022 | containerd/BuildKit image on the Windows Server 2025 host |
| Cinc Client | RHEL7, RHEL8, RHEL10 | RPM |
| Cinc Client | Ubuntu 22.04 | DEB |
| Cinc Client | Windows LTSC2022 build/runtime validation | MSI |

RHEL7 is a compatibility bridge. It is the only platform for which this project builds the Omnibus Toolchain from source. Modern platforms normally consume the Cinc-published toolchain version requested by the builder command.

Linux and Windows are intentionally separate host workflows. `all` on Linux means the four Linux targets. The PowerShell commands have no target argument because they only operate on Windows. There is no SSH/WinRM/control-plane layer joining the two hosts.

## User-facing commands

There are five host-native entry points representing three operations.

### 1. Build the RHEL7 Omnibus Toolchain

```bash
./build-toolchain.sh --version 26.0.3
```

`--version` defaults to `TOOLCHAIN_VERSION` in `config/build.env`.

Useful optional controls:

```bash
./build-toolchain.sh --version 26.0.4 --memory 6g --cpus 8
```

The command checks out the requested toolchain tag, applies the RHEL7 compatibility override, builds the RPM, installs it into a clean RHEL7 container, and executes the installed toolchain runtime.

### 2. Build reusable Omnibus images

Linux:

```bash
./build-omnibus-image.sh all
./build-omnibus-image.sh rhel7
./build-omnibus-image.sh rhel8
./build-omnibus-image.sh rhel10
./build-omnibus-image.sh ubuntu2204

# Request a different toolchain generation
./build-omnibus-image.sh all --toolchain-version 26.0.4
```

Windows Server 2025 host:

```powershell
.\build-omnibus-image.ps1
.\build-omnibus-image.ps1 -ToolchainVersion 26.0.4
```

For RHEL7, build the matching toolchain RPM first. RHEL8/RHEL10/Ubuntu and Windows obtain the requested published Cinc toolchain through the Cinc builder mechanisms.

### 3. Build Cinc Client

Linux:

```bash
./build-cinc-client.sh all --version 19.3.14
./build-cinc-client.sh rhel7 --version 19.3.14
./build-cinc-client.sh rhel8 --version 19.3.14
./build-cinc-client.sh rhel10 --version 19.3.14
./build-cinc-client.sh ubuntu2204 --version 19.3.14
```

Select a different builder/toolchain generation when required:

```bash
./build-cinc-client.sh all \
  --version 19.3.14 \
  --toolchain-version 26.0.4
```

The Linux command supports parallel target builds:

```bash
./build-cinc-client.sh all --jobs 4 --memory 4g --tmux
```

Windows Server 2025 host:

```powershell
.\build-cinc-client.ps1 -Version 19.3.14
.\build-cinc-client.ps1 -Version 19.3.14 -ToolchainVersion 26.0.4
```

The Windows build keeps persistent Bundler and Omnibus BuildKit caches. To clear only those product-build cache mounts:

```powershell
.\build-cinc-client.ps1 -Version 19.3.14 -CleanBuildCaches
```

`-NoCache` disables the BuildKit layer cache for that solve. `-SkipValidation` exists for build troubleshooting only; a package built with validation skipped is not an accepted result.

## Defaults and version selection

`config/build.env` contains only simple defaults:

- `TOOLCHAIN_VERSION`
- `CINC_VERSION`
- `CINC_CLIENT_REPO`
- `CINC_CLIENT_REF`
- `CINC_DOCKER_IMAGES_REPO`
- `CINC_DOCKER_IMAGES_REF`

The current defaults are the last known working baseline, not protected historical artefacts. Commands can override versions without editing the file.

For a Cinc release `X.Y.Z`, the build passes `REF=vX.Y.Z` to Cinc's `distribution/client` build flow. The default `distribution/client` ref is `master`; use `--client-ref` on Linux or `-ClientRef` on Windows only when a particular Cinc release needs a different implementation of that build wrapper.

A requested version is not a promise that upstream still supports RHEL7 or that every arbitrary dependency combination is valid. The scripts should attempt the requested version and fail clearly when an upstream source shape or RHEL7 compatibility assumption must be updated. Do not silently substitute a different release.

## Dependency overrides

There are exactly two Cinc override files.

### Ruby and OpenSSL: `overrides/cinc/omnibus.rb`

This file is appended to the selected Cinc source's `chef/omnibus/omnibus.rb` before the product build. Use normal Omnibus project override syntax.

Examples:

```ruby
override :ruby, version: "3.4.11"
override :openssl, version: "3.6.5"
```

When a Ruby/OpenSSL combination needs an explicit OpenSSL gem used during Ruby construction, ordinary omnibus-software override options may also be used, for example:

```ruby
override :ruby, version: "3.4.11", openssl_gem: "3.3.2"
```

Leave the file with comments only to use upstream versions.

### Runtime gems: `overrides/cinc/Gemfile`

Use ordinary Gemfile declarations with exact versions:

```ruby
gem "openssl", "= 3.3.2"
gem "ffi", "= 1.17.2"
```

For each active line, the build replaces an existing active declaration for that gem in `chef/Gemfile`, or appends the declaration when the gem is not already present. It then runs `bundle lock` before the Omnibus build.

Use exact `= x.y.z` requirements. Clean package validation reads the same file and proves that every requested version is installed in the embedded Cinc runtime.

Do not introduce YAML/JSON schemas or a generic override framework. These two files deliberately expose the native Omnibus/Bundler mechanisms directly to the engineer maintaining the build.

## Validation contract

Validation is about whether the resulting software works, not about producing an evidence bundle.

### RHEL7 Omnibus Toolchain

`build-toolchain.sh` is successful only when:

- the requested source tag can be checked out;
- the RHEL7 RPM builds;
- the RPM reports the requested package version;
- it installs into a clean RHEL7 container;
- installed Ruby, Bundler, make, and OpenSSL runtime execute.

### Reusable builder image

A Linux reusable builder is accepted only when:

- it starts as the intended OS target;
- `/opt/omnibus-toolchain` and the standard loader exist;
- the requested toolchain generation is present when a version manifest is available;
- Ruby, Bundler, RubyGems, Git, GCC/G++, make, patch and tar execute;
- the target packaging tools (`rpmbuild` or `dpkg-*`) are available.

The Windows reusable builder is accepted only when the LTSC2022 image builds, starts under WCOW, loads the Omnibus toolchain, and executes Ruby, Bundler, Git, GCC and make.

### Cinc Client package

Linux package validation occurs in a fresh native target container with no Omnibus Toolchain installed. It must prove:

- RPM/DEB package identity and requested Cinc version;
- installation succeeds;
- `cinc-client --version` works;
- `cinc-solo --version` works;
- `cinc-auditor version` works;
- a small real `cinc-solo` cookbook converges and creates a marker;
- a small real Auditor/InSpec profile tests that marker successfully;
- embedded Ruby and OpenSSL load successfully;
- any active Ruby/OpenSSL override has the requested version;
- every exact gem override is installed at the requested version.

Windows validation builds a clean LTSC2022 validation image around the generated MSI and performs the equivalent client/solo/auditor, recipe, profile, Ruby/OpenSSL, and gem-override checks.

Host-side Podman/WCOW runs remain the acceptance tests. Static checks performed on another machine do not replace them.

## Generated layout

Generated state is intentionally shallow:

```text
artifacts/
  toolchain/
    rhel7/
  cinc/
    rhel7/
    rhel8/
    rhel10/
    ubuntu2204/
    windows/

.work/       # disposable transient work/handoff/parallel-runner state
logs/        # ordinary troubleshooting logs
```

It is safe to remove `.work/`. BuildKit cache mounts on Windows are separate and intentionally persist because they materially shorten the native-gem/Omnibus feedback loop.

There are no permanent `evidence/`, `provenance/`, historical-source, source-diff, or AI-handoff output trees.

## Host prerequisites

### Linux build host

The normal Linux orchestration host is a registered RHEL system with:

- Podman;
- access to `registry.redhat.io`;
- a readable Podman registry auth file (default `/root/.config/containers/auth.json`);
- Red Hat entitlement/repository secrets available to the RHEL containers as `/run/secrets/redhat.repo`;
- outbound HTTPS to Cinc/Git/Chef package and source services;
- enough CPU, memory, disk and container storage for Omnibus builds;
- `tmux` only if the optional dashboard is requested.

RHEL7 additionally requires the RHEL 7 Optional and RHSCL repositories so DTS11 and the build prerequisites can be installed.

### Windows build host

The Windows path is designed for Windows Server 2025 running WCOW LTSC2022 containers. It expects these commands on `PATH`:

- Git;
- `containerd`;
- `nerdctl`;
- `buildctl`;
- `ctr`.

BuildKit/containerd must be configured for Windows containers and outbound network access. Host provisioning itself is deliberately outside this repository; install/configure those components using your normal server management process.

Before using the Windows builders, run:

```powershell
.\scripts\windows\test-container-host.ps1
```

That checks WCOW pull/runtime, BuildKit image export, and BuildKit outbound HTTPS.

## Engineering flow

### RHEL7 toolchain flow

```text
build-toolchain.sh
  -> scripts/toolchain/build-rhel7.sh
       -> requested distribution/omnibus-toolchain tag
       -> scripts/toolchain/patch-libnghttp2.sh
       -> overrides/toolchain/rhel7/libnghttp2.rb
       -> upstream build/build.sh
  -> scripts/toolchain/validate.sh in a clean RHEL7 container
  -> artifacts/toolchain/rhel7/
```

The RHEL7 `libnghttp2` override is a compatibility band-aid. RHEL7's old Autotools stack cannot safely regenerate the contemporary release tarball build files. The override builds the library-only target and avoids the regeneration step. It currently contains the libnghttp2 release known to work with the present toolchain generation; when a requested future toolchain materially changes that dependency, update this one compatibility file rather than creating another build path.

### Linux builder flow

```text
build-omnibus-image.sh
  -> containers/<target>/Containerfile
  -> containers/shared/omnibus/              # modern Linux targets
  -> scripts/builder/validate-linux.sh
  -> localhost/cinc-omnibus-builder:<target>-<toolchain-version>
```

RHEL7 consumes the locally built RPM. RHEL8/RHEL10/Ubuntu retain Cinc's maintained `cinc-omnibus` cookbook resource because it already performs the published-toolchain bootstrap correctly. Do not replace it with another abstraction. It can be removed later only if a direct installation path is demonstrably smaller and passes the same builder/client tests.

### Linux Cinc Client flow

```text
build-cinc-client.sh
  -> reusable builder image
  -> scripts/client/build-linux.sh
       -> distribution/client
       -> scripts/client/compat.sh
       -> overrides/cinc/omnibus.rb
       -> overrides/cinc/Gemfile
       -> upstream patch.sh + build.sh
  -> artifacts/cinc/<target>/cinc*.rpm|deb
  -> clean target runtime
       -> scripts/client/validate-linux.sh
```

The reusable builder is the only supported Linux product-build path. There is no separate direct-container/legacy build mode.

### Windows builder flow

```text
build-omnibus-image.ps1
  -> Cinc docker-images omnibus-windows context
  -> small MSYS2 primary-mirror compatibility edit
  -> BuildKit / containerd image
  -> fresh WCOW smoke test
```

The source ref defaults to `master` and can be overridden with `-DockerImagesRef`. The requested toolchain version is passed to the upstream `omnibus-windows` Dockerfile as a build argument.

### Windows Cinc Client flow

```text
build-cinc-client.ps1
  -> containers/windows/client-build/Dockerfile
  -> reusable LTSC2022 builder
  -> scripts/windows/build-client-in-builder.sh
       -> scripts/client/compat.sh
       -> overrides/cinc/*
       -> scripts/windows/patch-omnibus-git-cache.sh
       -> upstream build-windows.sh
  -> artifacts/cinc/windows/cinc*.msi
  -> containers/windows/client-validation/Dockerfile
       -> real cinc-solo converge
       -> real cinc-auditor profile
       -> override checks
```

## Compatibility code that remains and why

Keep these fixes while they prevent a current supported build failure. Keep their implementation small; do not create separate evidence files for them.

### RHEL7 libnghttp2

RHEL7's Autotools generation is too old for the contemporary nghttp2 source build used by the toolchain. The project-local software recipe builds library-only and avoids regenerating Autotools files.

### Older Cinc `patch.sh` / RHEL7 Git

`scripts/client/compat.sh` makes the newer `cinc-merge-upstream.sh` call conditional so older Cinc branches that lack the helper still build. For remote-qualified branch refs, it also explicitly fetches the branch when RHEL7 Git 1.8 cannot resolve it after the generic upstream fetch.

The same transform removes only the known legacy exact `openssl = 3.3.1` Gemfile pin before the upstream lock step because that pin conflicts with the newer Ruby/toolchain dependency path. Intentional OpenSSL gem versions belong in `overrides/cinc/Gemfile` instead.

### Ruby 3.4 / old Omnibus `append_timestamp`

Some older Cinc build scripts pass `--override append_timestamp:false` through an Omnibus CLI/dependency combination that does not parse that boolean correctly with the current toolchain. The compatibility helper feature-detects that older dependency model, moves the setting into `omnibus.rb`, and removes the CLI argument.

### Windows writable HOME and Git configuration

The MSYS2 shell inside BuildKit does not have the GitLab Runner profile environment that upstream CI normally supplies. The build therefore creates a writable build-local HOME and Git global config so native Git does not try to write `//.gitconfig`.

### Windows MSYS2 mirror

The upstream omnibus-windows image initializes MSYS2 through mirror infrastructure that has produced rate-limit failures. `build-omnibus-image.ps1` pins the generated pacman mirror files to `repo.msys2.org` while preserving MSYS2's `$arch`/`$repo` placeholders.

### Windows Omnibus GitCache `--work-tree`

Omnibus intentionally strips the drive from its Windows cache layout, but native Git must receive the real `C:/...` install path for `--work-tree`. `scripts/windows/patch-omnibus-git-cache.sh` changes only that argument after Bundler has materialised the vendored Omnibus source.

### `win32-event` License Scout fallback

Older dependency sets contain a License Scout fallback URL ending in `win32-event/.../README`, while the upstream file is `README.md`. The Windows product build corrects that one stale URL after `bundle install`. The fix is feature-detected and becomes a no-op when the dependency is already corrected. Licensing warnings are not disabled to work around it.

### Windows BuildKit artifact export

WCOW BuildKit can encounter transient files under `C:\Windows\SoftwareDistribution\Download` while snapshotting a long-running Windows build. The Cinc build stage therefore clears only that Windows Update download cache after the MSI has been produced and before the final scratch-stage artifact copy. This is export hygiene only; it does not alter the MSI contents.

### Windows product caches

Bundler and Omnibus caches are mounted as BuildKit cache mounts because they materially shorten repeated Windows builds. They are performance state, not project evidence. `-CleanBuildCaches` removes the product-specific cache mounts when a genuinely clean dependency build is needed.

### `ruby-msys2-devkit` exclusion

The dependency is commented out of the Cinc Omnibus project before package construction. The build fails if an active unrecognised `ruby-msys2-devkit` reference remains, and the Windows product build also rejects a generated Omnibus manifest that says the component was shipped.

## Repository layout

```text
README.md
config/build.env

build-toolchain.sh
build-omnibus-image.sh
build-omnibus-image.ps1
build-cinc-client.sh
build-cinc-client.ps1

overrides/
  toolchain/rhel7/libnghttp2.rb
  cinc/omnibus.rb
  cinc/Gemfile

containers/
  rhel7/Containerfile
  rhel8/Containerfile
  rhel10/Containerfile
  ubuntu2204/Containerfile
  shared/omnibus/
  windows/client-build/
  windows/client-validation/

scripts/
  toolchain/
  builder/
  client/
  lib/
  windows/
```

Do not recreate `archive/`, a multi-file documentation tree, handoff prompts, legacy aliases, or parallel build implementations without a current operational requirement.

## Troubleshooting principles

- If the RHEL7 toolchain source changes shape, update the smallest RHEL7 compatibility helper/override necessary for that selected version. Do not generalise the whole project around hypothetical old platforms.
- If a modern published toolchain version does not exist for a requested target, fail rather than silently using another version.
- If a Cinc version needs a different `distribution/client` implementation, use `--client-ref` / `-ClientRef` rather than adding another product build path.
- If Ruby/OpenSSL/gem overrides fail, first confirm that the selected Cinc/omnibus-software source actually defines the requested versions/checksums.
- If Windows rebuilds behave strangely after changing dependency or compatibility logic, retry with `-CleanBuildCaches`; use `-NoCache` only when the image layer cache also needs to be bypassed.
- If the Windows build reaches License Scout or Omnibus GitCache failures, update the narrowly scoped feature-detected fix rather than weakening licensing checks or replacing the Windows builder architecture.
- Never treat a Chat-side syntax check as Linux Podman or WCOW acceptance.

## Acceptance commands after code changes

Run on the Linux host:

```bash
./build-toolchain.sh --version 26.0.3
./build-omnibus-image.sh all --toolchain-version 26.0.3
./build-cinc-client.sh all --version 19.3.14 --toolchain-version 26.0.3 --jobs 4 --tmux
```

Run on the Windows Server 2025 host:

```powershell
.\scripts\windows\test-container-host.ps1
.\build-omnibus-image.ps1 -ToolchainVersion 26.0.3
.\build-cinc-client.ps1 -Version 19.3.14 -ToolchainVersion 26.0.3
```

For a new version, substitute the version requested. Acceptance means those commands and their clean validation phases pass; it does not require collecting a separate evidence bundle.

## Maintenance rule

Prefer fewer files, fewer entry points, fewer abstractions, and tests that prove the final installed product works. Compatibility code may be ugly when a real platform requires it, especially RHEL7 and WCOW, but complexity must solve a current build problem rather than preserve project history.
