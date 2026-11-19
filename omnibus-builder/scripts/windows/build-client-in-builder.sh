#!/usr/bin/env bash
set -euo pipefail
REF="${REF:?REF is required}"
CLIENT_REPO="${CLIENT_REPO:-https://gitlab.com/cinc-project/distribution/client.git}"
CLIENT_REF="${CLIENT_REF:-master}"
EXPECTED_TARGET_VERSION="${EXPECTED_TARGET_VERSION:?EXPECTED_TARGET_VERSION is required}"
WORK_ROOT=/c/work
CLIENT_DIR="${WORK_ROOT}/client"
OUT=/c/artifacts
fail() { echo "ERROR: $*" >&2; exit 1; }
for cmd in git ruby bundle make gcc g++ powershell.exe; do command -v "$cmd" >/dev/null 2>&1 || fail "required command not found: $cmd"; done

# distribution/client patch.sh expects the Linux loader path even when its
# Windows build runs inside the already-prepared omnibus-windows image.
mkdir -p /home/omnibus
printf '#!/usr/bin/env bash\n:\n' > /home/omnibus/load-omnibus-toolchain.sh
chmod 0755 /home/omnibus/load-omnibus-toolchain.sh
# shellcheck disable=SC1091
source /c/handoff/scripts/client/compat.sh

rm -rf "$WORK_ROOT" /c/artifacts
mkdir -p "$WORK_ROOT" "$OUT"
# Native Git for Windows needs a writable build-local HOME/Git config.
export HOME="${WORK_ROOT}/home"
export USERPROFILE='C:/work/home'
export GIT_CONFIG_GLOBAL='C:/work/home/.gitconfig'
mkdir -p "$HOME"
cat > "$HOME/.gitconfig" <<'GITCFG'
[user]
  name = Omnibus
  email = maintainers@cinc.sh
GITCFG

git clone "$CLIENT_REPO" "$CLIENT_DIR"
cd "$CLIENT_DIR"
[[ -z "$CLIENT_REF" ]] || git checkout -q "$CLIENT_REF"
export REF
client_transform_patch_sh patch.sh patch.sh.omnibus-builder
mv patch.sh.omnibus-builder patch.sh
chmod 0755 patch.sh
./patch.sh

[[ -f chef/VERSION ]] || fail "patch.sh did not create chef/VERSION"
actual_version="$(tr -d '\r\n' < chef/VERSION)"
[[ "$actual_version" == "$EXPECTED_TARGET_VERSION" ]] || fail "Cinc version mismatch: expected $EXPECTED_TARGET_VERSION, got $actual_version"

# Deliberate product policy: the reusable builder has MSYS2/compiler tooling;
# do not ship ruby-msys2-devkit in the installed Cinc runtime.
client_disable_windows_runtime_devkit chef/omnibus/config/projects/cinc.rb
client_apply_omnibus_overrides /c/handoff/overrides/cinc/omnibus.rb chef/omnibus/omnibus.rb
client_apply_gem_overrides /c/handoff/overrides/cinc/Gemfile chef/Gemfile
if grep -Eq '^[[:space:]]*[^#[:space:]]' /c/handoff/overrides/cinc/Gemfile; then (cd chef && bundle lock); fi
if client_append_timestamp_needed build-windows.sh chef/omnibus/Gemfile; then
  client_apply_append_timestamp build-windows.sh chef/omnibus/omnibus.rb
fi

# License Scout in older Cinc dependency sets points win32-event at README even
# though upstream renamed it README.md. Correct only that known stale fallback;
# if the dependency has already been fixed (or no longer has the fallback), do
# nothing. fatal_transitive_dependency_licensing_warnings stays enabled.
LICENSE_PATCH="${WORK_ROOT}/patch-win32-event-license.sh"
cat > "$LICENSE_PATCH" <<'PATCH'
#!/usr/bin/env bash
set -euo pipefail
root="${CINC_WINDOWS_BUNDLE_CACHE_ROOT:-${1}/bundle}/vendor"
mapfile -t files < <(find "$root" -type f -path '*/bundler/gems/license-scout-*/lib/license_scout/overrides.rb' -print)
((${#files[@]} == 1)) || { echo "ERROR: expected one License Scout overrides.rb, found ${#files[@]}" >&2; exit 1; }
f="${files[0]}"
old1='"https://github.com/chef/win32-event/blob/ffi/README"'; new1='"https://github.com/chef/win32-event/blob/ffi/README.md"'
old2='"https://raw.githubusercontent.com/chef/win32-event/ffi/README"'; new2='"https://raw.githubusercontent.com/chef/win32-event/ffi/README.md"'
count() { { grep -Fo -- "$1" "$f" || true; } | wc -l | tr -d '[:space:]'; }
stale=$(( $(count "$old1") + $(count "$old2") ))
if ((stale > 1)); then echo "ERROR: unexpected multiple win32-event stale License Scout fallbacks" >&2; exit 1; fi
if ((stale == 1)); then sed -i -e "s|${old1}|${new1}|g" -e "s|${old2}|${new2}|g" "$f"; echo 'compat: corrected win32-event License Scout README fallback'; else echo 'compat: win32-event License Scout fallback does not need correction'; fi
PATCH
chmod 0755 "$LICENSE_PATCH"

# Run the two Windows-specific compatibility patches after Bundler materialises
# the vendored gems and immediately before the Omnibus build.
awk '
  { print }
  /^[[:space:]]*bundle install[[:space:]]*$/ && !done {
    print "bundle pristine license_scout omnibus"
    print "/c/work/patch-win32-event-license.sh \"${CI_PROJECT_DIR}\""
    print "/c/handoff/scripts/windows/patch-omnibus-git-cache.sh \"${CI_PROJECT_DIR}/bundle/vendor\""
    done=1
  }
  END { if (!done) exit 42 }
' build-windows.sh > build-windows.sh.compat || fail "could not locate bundle install in build-windows.sh"
mv build-windows.sh.compat build-windows.sh
chmod 0755 build-windows.sh

export CI_PROJECT_DIR='C:/work/client'
# Keep Bundler and Omnibus downloads/git caches warm across BuildKit solves.
CACHE_ROOT=/c/cinc-client-windows-cache
BUNDLE_CACHE_ROOT="${CACHE_ROOT}/bundle"
OMNIBUS_CACHE_ROOT="${CACHE_ROOT}/omnibus"
export CINC_WINDOWS_BUNDLE_CACHE_ROOT="$BUNDLE_CACHE_ROOT"
mkdir -p "$BUNDLE_CACHE_ROOT" "$OMNIBUS_CACHE_ROOT"
create_junction() {
  local link=$1 target=$2 link_win target_win
  mkdir -p "$(dirname "$link")" "$target"
  [[ ! -e "$link" ]] || fail "cache junction path already exists: $link"
  link_win="$(cygpath -w "$link")"; target_win="$(cygpath -w "$target")"
  powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "New-Item -ItemType Junction -Path '${link_win}' -Target '${target_win}' | Out-Null"
}
create_junction "$CLIENT_DIR/bundle" "$BUNDLE_CACHE_ROOT"
create_junction "$CLIENT_DIR/cache" "$OMNIBUS_CACHE_ROOT"

# Omnibus uses a drive-stripped path for cache layout; native Git needs the real
# Windows install path for --work-tree. Pre-seed the cache repo accordingly.
INSTALL_DIR=/c/cinc-project/cinc
GIT_CACHE_DIR="$CLIENT_DIR/cache/git_cache/cinc-project/cinc"
INSTALL_WIN="$(cygpath -m "$INSTALL_DIR")"; CACHE_WIN="$(cygpath -m "$GIT_CACHE_DIR")"
mkdir -p "$INSTALL_DIR" "$GIT_CACHE_DIR"
if ! git --git-dir="$CACHE_WIN" rev-parse --git-dir >/dev/null 2>&1; then
  rm -rf "$GIT_CACHE_DIR"; mkdir -p "$GIT_CACHE_DIR"
  git -c core.autocrlf=false -c core.ignorecase=false --git-dir="$CACHE_WIN" --work-tree="$INSTALL_WIN" init -q
  git --git-dir="$CACHE_WIN" config --local user.name 'Omnibus Git Cache'
  git --git-dir="$CACHE_WIN" config --local user.email 'omnibus@localhost'
fi

unset OMNIBUS_FIPS_MODE
./build-windows.sh
shopt -s nullglob; packages=(data/cinc*.msi); shopt -u nullglob
((${#packages[@]} == 1)) || fail "expected exactly one Cinc MSI, found ${#packages[@]}"
for manifest in chef/omnibus/pkg/version-manifest.txt chef/omnibus/pkg/version-manifest.json; do
  if [[ -f "$manifest" ]] && grep -Fq 'ruby-msys2-devkit' "$manifest"; then fail "ruby-msys2-devkit unexpectedly shipped in $manifest"; fi
done
cp -f "${packages[0]}" "$OUT/"
echo "Built Cinc Client ${actual_version} Windows MSI: $OUT/$(basename "${packages[0]}")"
