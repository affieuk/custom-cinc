#!/usr/bin/env bash
set -euo pipefail

platform=''
expected_version=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform) platform="${2:?missing platform}"; shift 2 ;;
    --toolchain-version) expected_version="${2:?missing toolchain version}"; shift 2 ;;
    -h|--help) echo "usage: $0 --platform TARGET --toolchain-version X.Y.Z"; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$platform" && -n "$expected_version" ]] || { echo "ERROR: platform and toolchain version are required" >&2; exit 2; }
fail() { echo "ERROR: $*" >&2; exit 1; }
require() { command -v "$1" >/dev/null 2>&1 || fail "command not found: $1"; }

[[ -d /opt/omnibus-toolchain ]] || fail "/opt/omnibus-toolchain missing"
[[ -r /home/omnibus/load-omnibus-toolchain.sh ]] || fail "toolchain loader missing"
case "$platform" in
  rhel7)
    grep -Eq 'release 7([ .]|$)' /etc/redhat-release || fail "expected RHEL7"
    source /home/omnibus/activate-el7-builder.sh
    require rpmbuild
    ;;
  rhel8)
    grep -Eq 'release 8([ .]|$)' /etc/redhat-release || fail "expected RHEL8"
    source /home/omnibus/load-omnibus-toolchain.sh
    require rpmbuild
    ;;
  rhel10)
    grep -Eq 'release 10([ .]|$)' /etc/redhat-release || fail "expected RHEL10"
    source /home/omnibus/load-omnibus-toolchain.sh
    require rpmbuild
    ;;
  ubuntu2204)
    . /etc/os-release
    [[ "$ID" == ubuntu && "$VERSION_ID" == 22.04 ]] || fail "expected Ubuntu 22.04"
    source /home/omnibus/load-omnibus-toolchain.sh
    require dpkg-deb; require dpkg-buildpackage
    ;;
  *) fail "unsupported platform: $platform" ;;
esac
for cmd in ruby bundle gem git gcc g++ make patch tar; do require "$cmd"; done
if [[ -f /opt/omnibus-toolchain/version-manifest.txt ]]; then
  grep -F "$expected_version" /opt/omnibus-toolchain/version-manifest.txt >/dev/null || fail "toolchain version ${expected_version} not found in manifest"
fi
ruby --version
bundle --version
git --version
gcc --version | head -1
make --version | head -1
ruby -ropenssl -e 'puts OpenSSL::OPENSSL_VERSION'
echo "PASS: ${platform} reusable builder with toolchain ${expected_version}"
