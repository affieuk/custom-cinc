#!/usr/bin/env bash
set -euo pipefail

TARGET="${TARGET:?TARGET is required}"
REF="${REF:?REF is required}"
CLIENT_REPO="${CLIENT_REPO:-https://gitlab.com/cinc-project/distribution/client.git}"
CLIENT_REF="${CLIENT_REF:-master}"
EXPECTED_TARGET_VERSION="${EXPECTED_TARGET_VERSION:?EXPECTED_TARGET_VERSION is required}"
WORK_ROOT="${WORK_ROOT:-/work}"
CLIENT_DIR="${WORK_ROOT}/client"
OUT="/artifacts/${TARGET}"
fail() { echo "ERROR: $*" >&2; exit 1; }

case "$TARGET" in
  rhel7) grep -Eq 'release 7([ .]|$)' /etc/redhat-release || fail "expected RHEL7"; source /home/omnibus/activate-el7-builder.sh ;;
  rhel8) grep -Eq 'release 8([ .]|$)' /etc/redhat-release || fail "expected RHEL8"; source /home/omnibus/load-omnibus-toolchain.sh ;;
  rhel10) grep -Eq 'release 10([ .]|$)' /etc/redhat-release || fail "expected RHEL10"; source /home/omnibus/load-omnibus-toolchain.sh ;;
  ubuntu2204) . /etc/os-release; [[ "$ID" == ubuntu && "$VERSION_ID" == 22.04 ]] || fail "expected Ubuntu 22.04"; source /home/omnibus/load-omnibus-toolchain.sh ;;
  *) fail "unsupported target: $TARGET" ;;
esac
/handoff/scripts/builder/validate-linux.sh --platform "$TARGET" --toolchain-version "${TOOLCHAIN_VERSION:?TOOLCHAIN_VERSION is required}"
# shellcheck disable=SC1091
source /handoff/scripts/client/compat.sh

rm -rf "$CLIENT_DIR"
mkdir -p "$WORK_ROOT" "$OUT"
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

# Keep the Windows compiler toolchain out of the installed Cinc runtime. This is
# intentionally applied on every host; the dependency is Windows-conditional.
client_disable_windows_runtime_devkit chef/omnibus/config/projects/cinc.rb

client_apply_omnibus_overrides /handoff/overrides/cinc/omnibus.rb chef/omnibus/omnibus.rb
client_apply_gem_overrides /handoff/overrides/cinc/Gemfile chef/Gemfile
if grep -Eq '^[[:space:]]*[^#[:space:]]' /handoff/overrides/cinc/Gemfile; then
  (cd chef && bundle lock)
fi

if client_append_timestamp_needed build.sh chef/omnibus/Gemfile; then
  echo 'Applying Ruby 3.4 / older Omnibus append_timestamp compatibility fix'
  client_apply_append_timestamp build.sh chef/omnibus/omnibus.rb
fi

unset OMNIBUS_FIPS_MODE
./build.sh

shopt -s nullglob
case "$TARGET" in
  rhel7|rhel8|rhel10) packages=(chef/omnibus/pkg/cinc*.rpm) ;;
  ubuntu2204) packages=(chef/omnibus/pkg/cinc*.deb) ;;
esac
shopt -u nullglob
((${#packages[@]} == 1)) || fail "expected exactly one Cinc package, found ${#packages[@]}"
rm -f "$OUT"/cinc*.rpm "$OUT"/cinc*.deb 2>/dev/null || true
cp -f "${packages[0]}" "$OUT/"
echo "Built Cinc Client ${actual_version} for ${TARGET}: $OUT/$(basename "${packages[0]}")"
