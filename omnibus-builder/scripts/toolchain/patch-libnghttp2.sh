#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${1:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OVERRIDE="${PROJECT_DIR}/overrides/toolchain/rhel7/libnghttp2.rb"
[[ -f "${OVERRIDE}" ]] || OVERRIDE="/handoff/overrides/toolchain/rhel7/libnghttp2.rb"
DEST="${REPO_DIR}/config/software/libnghttp2.rb"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

default_version() {
  local recipe=$1
  sed -n -E 's/^[[:space:]]*default_version[[:space:]]+"([^"]+)".*/\1/p' "${recipe}" | head -1
}

[[ -f "${OVERRIDE}" ]] || fail "missing override: ${OVERRIDE}"
[[ -d "${REPO_DIR}/config/software" ]] || fail "not an omnibus-toolchain checkout: ${REPO_DIR}"

OVERRIDE_DEFAULT_VERSION="$(default_version "${OVERRIDE}")"
[[ -n "${OVERRIDE_DEFAULT_VERSION}" ]] || fail "cannot read default_version from RHEL7 override"
grep -Fq -- '--enable-lib-only' "${OVERRIDE}" || \
  fail "RHEL7 override lost --enable-lib-only"
if grep -Eq '^[[:space:]]*[^#].*(libtoolize|aclocal|autoheader|automake|autoconf)' "${OVERRIDE}"; then
  fail "RHEL7 override unexpectedly regenerates Autotools files"
fi

# The validated 26.0.4 and 26.0.3 source trees do not carry libnghttp2.rb
# locally; omnibus-software supplies it as a gem and this project-local file
# overrides it. If a selected future source does add a local recipe, fail
# closed on an unreviewed component/version or recipe-shape change before
# replacing it.
if [[ -f "${DEST}" ]]; then
  UPSTREAM_DEFAULT_VERSION="$(default_version "${DEST}")"
  [[ -n "${UPSTREAM_DEFAULT_VERSION}" ]] || fail "cannot read default_version from checked-out recipe"
  for expected_token in libtoolize aclocal autoheader automake autoconf; do
    grep -Eq "^[[:space:]]*[^#].*${expected_token}" "${DEST}" || \
      fail "checked-out libnghttp2 recipe shape changed (missing active ${expected_token}); review the RHEL7 override"
  done
  [[ "${UPSTREAM_DEFAULT_VERSION}" == "${OVERRIDE_DEFAULT_VERSION}" ]] || {
    echo "ERROR: EL7 libnghttp2 override is not reviewed for the selected toolchain source." >&2
    echo "checked-out default_version: ${UPSTREAM_DEFAULT_VERSION}" >&2
    echo "override default_version:    ${OVERRIDE_DEFAULT_VERSION}" >&2
    echo "Review/update the RHEL7 compatibility override before building this toolchain version." >&2
    exit 1
  }
else
  echo "No project-local libnghttp2 recipe in checkout; installing RHEL7 override."
fi

cp -f "${OVERRIDE}" "${DEST}"

echo "Installed EL7 libnghttp2 override: ${DEST}"
echo "libnghttp2 default_version: ${OVERRIDE_DEFAULT_VERSION}"
grep -nE 'default_version|enable-lib-only|libtoolize|aclocal|autoheader|automake|autoconf' "${DEST}" || true
