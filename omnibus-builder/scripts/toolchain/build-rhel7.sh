#!/usr/bin/env bash
set -euo pipefail

TOOLCHAIN_VERSION="${TOOLCHAIN_VERSION:?TOOLCHAIN_VERSION is required}"
TOOLCHAIN_REPO="${TOOLCHAIN_REPO:-https://gitlab.com/cinc-project/distribution/omnibus-toolchain.git}"
WORKDIR="${WORKDIR:-/tmp/omnibus-toolchain}"
OUTPUT_DIR="${OUTPUT_DIR:-/artifacts}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "$(id -u)" -eq 0 ]] || fail "run as root inside RHEL7"
grep -Eq 'release 7([ .]|$)' /etc/redhat-release || fail "this build must run on RHEL7"
rm -rf "${WORKDIR}"

yum install -y \
  --enablerepo=rhel-7-server-optional-rpms \
  --enablerepo=rhel-server-rhscl-7-rpms \
  devtoolset-11-toolchain \
  autoconf automake bison bzip2 ca-certificates curl file flex gettext git gzip \
  libffi-devel libtool libyaml-devel ncurses-devel openssh-clients openssl-devel \
  patch perl perl-Digest-SHA perl-IPC-Cmd perl-Pod-Html perl-Time-Piece \
  perl-podlators pkgconfig procps-ng readline-devel rpm-build rsync tar tzdata \
  wget which xz zlib-devel

source /opt/rh/devtoolset-11/enable
export CC=/opt/rh/devtoolset-11/root/usr/bin/gcc
export CXX=/opt/rh/devtoolset-11/root/usr/bin/g++

git clone --branch "${TOOLCHAIN_VERSION}" --depth 1 "${TOOLCHAIN_REPO}" "${WORKDIR}" || \
  fail "toolchain tag ${TOOLCHAIN_VERSION} was not found"
cd "${WORKDIR}"
actual_version="$(tr -d '\r\n' < VERSION)"
[[ "${actual_version}" == "${TOOLCHAIN_VERSION}" ]] || \
  fail "VERSION mismatch: requested ${TOOLCHAIN_VERSION}, source contains ${actual_version}"

# RHEL7 cannot regenerate contemporary nghttp2 release tarballs with its old
# Autotools stack. Install the small known compatibility recipe. The helper
# fails if the selected source carries a conflicting project-local recipe.
"${SCRIPT_DIR}/patch-libnghttp2.sh" "${WORKDIR}"

./build/build.sh

mkdir -p "${OUTPUT_DIR}"
shopt -s nullglob
packages=(data/omnibus-toolchain-*.rpm)
shopt -u nullglob
((${#packages[@]} == 1)) || fail "expected exactly one toolchain RPM, found ${#packages[@]}"
cp -f "${packages[0]}" "${OUTPUT_DIR}/"
echo "Built Cinc Omnibus Toolchain ${actual_version} for RHEL7: ${OUTPUT_DIR}/$(basename "${packages[0]}")"
