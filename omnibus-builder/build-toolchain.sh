#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/config/build.env"
VERSION="${TOOLCHAIN_VERSION}"
MEMORY="${CONTAINER_MEMORY:-4g}"
CPUS="${CONTAINER_CPUS:-8}"
RHEL7_IMAGE="${RHEL7_IMAGE:-registry.redhat.io/rhel7/rhel:latest}"
REGISTRY_AUTH_FILE="${REGISTRY_AUTH_FILE:-/root/.config/containers/auth.json}"

usage() {
  cat <<USAGE
usage: $0 [--version X.Y.Z] [--memory SIZE] [--cpus N]

Build and validate the requested Cinc Omnibus Toolchain for RHEL7.
Default version: ${TOOLCHAIN_VERSION}
USAGE
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:?missing value for --version}"; shift 2 ;;
    --memory) MEMORY="${2:?missing value for --memory}"; shift 2 ;;
    --cpus) CPUS="${2:?missing value for --cpus}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
command -v podman >/dev/null 2>&1 || { echo "ERROR: podman is required" >&2; exit 1; }
[[ -r "${REGISTRY_AUTH_FILE}" ]] || { echo "ERROR: Red Hat registry auth file is not readable: ${REGISTRY_AUTH_FILE}" >&2; exit 1; }

WORK="${ROOT}/.work/toolchain/rhel7"
HANDOFF="${WORK}/handoff"
ARTIFACTS="${ROOT}/artifacts/toolchain/rhel7"
LOGS="${ROOT}/logs/toolchain"
rm -rf "${WORK}" "${ARTIFACTS}"
mkdir -p "${HANDOFF}/scripts/toolchain" "${HANDOFF}/overrides/toolchain/rhel7" "${ARTIFACTS}" "${LOGS}"
cp "${ROOT}/scripts/toolchain/build-rhel7.sh" "${ROOT}/scripts/toolchain/patch-libnghttp2.sh" "${ROOT}/scripts/toolchain/validate.sh" "${HANDOFF}/scripts/toolchain/"
cp "${ROOT}/overrides/toolchain/rhel7/libnghttp2.rb" "${HANDOFF}/overrides/toolchain/rhel7/"
chmod 0755 "${HANDOFF}/scripts/toolchain/"*.sh

BUILD_LOG="${LOGS}/rhel7-${VERSION}-build.log"
VALIDATE_LOG="${LOGS}/rhel7-${VERSION}-validate.log"
echo "===== build RHEL7 Omnibus Toolchain ${VERSION} ====="
podman run --rm --authfile "${REGISTRY_AUTH_FILE}" --user 0 --memory "${MEMORY}" --cpus "${CPUS}" \
  -e "TOOLCHAIN_VERSION=${VERSION}" \
  -v "${HANDOFF}:/handoff:ro,Z" -v "${ARTIFACTS}:/artifacts:Z" \
  "${RHEL7_IMAGE}" /handoff/scripts/toolchain/build-rhel7.sh 2>&1 | tee "${BUILD_LOG}"

shopt -s nullglob
packages=("${ARTIFACTS}"/omnibus-toolchain-"${VERSION}"-*.rpm)
shopt -u nullglob
((${#packages[@]} == 1)) || { echo "ERROR: expected exactly one ${VERSION} RPM in ${ARTIFACTS}" >&2; exit 1; }
package="${packages[0]}"

echo "===== validate RHEL7 Omnibus Toolchain ${VERSION} ====="
podman run --rm --authfile "${REGISTRY_AUTH_FILE}" --user 0 --memory "${MEMORY}" --cpus "${CPUS}" \
  -e "PACKAGE_BASENAME=$(basename "${package}")" -e "EXPECTED_VERSION=${VERSION}" \
  -v "${HANDOFF}:/handoff:ro,Z" -v "${ARTIFACTS}:/artifacts:ro,Z" \
  "${RHEL7_IMAGE}" /handoff/scripts/toolchain/validate.sh 2>&1 | tee "${VALIDATE_LOG}"

echo "Artifact: ${package}"
