#!/usr/bin/env bash
set -euo pipefail

PACKAGE_BASENAME="${PACKAGE_BASENAME:?PACKAGE_BASENAME is required}"
EXPECTED_VERSION="${EXPECTED_VERSION:?EXPECTED_VERSION is required}"
PACKAGE="/artifacts/${PACKAGE_BASENAME}"
fail() { echo "ERROR: $*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || fail "run as root"
grep -Eq 'release 7([ .]|$)' /etc/redhat-release || fail "expected RHEL7"
[[ -f "${PACKAGE}" ]] || fail "package not found: ${PACKAGE}"
[[ "$(rpm -qp --qf '%{VERSION}' "${PACKAGE}")" == "${EXPECTED_VERSION}" ]] || fail "RPM version does not match ${EXPECTED_VERSION}"
rpm -Uvh "${PACKAGE}"
[[ -x /opt/omnibus-toolchain/bin/ruby ]] || fail "toolchain Ruby missing"
[[ -x /opt/omnibus-toolchain/bin/bundle ]] || fail "toolchain Bundler missing"
[[ -x /opt/omnibus-toolchain/bin/make ]] || fail "toolchain make missing"
/opt/omnibus-toolchain/bin/ruby --version
/opt/omnibus-toolchain/bin/bundle --version
/opt/omnibus-toolchain/bin/make --version | head -1
/opt/omnibus-toolchain/embedded/bin/ruby -ropenssl -e 'puts OpenSSL::OPENSSL_VERSION'
echo "PASS: RHEL7 Omnibus Toolchain ${EXPECTED_VERSION} installs and runs"
