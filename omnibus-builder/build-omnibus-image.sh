#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/config/build.env"
VERSION="${TOOLCHAIN_VERSION}"
REGISTRY_AUTH_FILE="${REGISTRY_AUTH_FILE:-/root/.config/containers/auth.json}"

usage() {
  cat <<USAGE
usage: $0 [all|rhel7|rhel8|rhel10|ubuntu2204 ...] [--toolchain-version X.Y.Z]

Build and validate reusable Linux Omnibus builder images.
"all" means the four Linux targets; Windows is built on the Windows host with
.\\build-omnibus-image.ps1.
USAGE
}
selectors=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --toolchain-version) VERSION="${2:?missing value for --toolchain-version}"; shift 2 ;;
    all|rhel7|rhel8|rhel10|ubuntu2204) selectors+=("$1"); shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
((${#selectors[@]})) || selectors=(all)
targets=()
add() { local x=$1 y; for y in "${targets[@]}"; do [[ "$y" == "$x" ]] && return; done; targets+=("$x"); }
for s in "${selectors[@]}"; do
  case "$s" in
    all) for t in rhel7 rhel8 rhel10 ubuntu2204; do add "$t"; done ;;
    *) add "$s" ;;
  esac
done
command -v podman >/dev/null 2>&1 || { echo "ERROR: podman is required" >&2; exit 1; }
needs_redhat=0; for t in "${targets[@]}"; do [[ "$t" == rhel* ]] && needs_redhat=1; done
if ((needs_redhat)) && [[ ! -r "${REGISTRY_AUTH_FILE}" ]]; then echo "ERROR: Red Hat registry auth file is not readable: ${REGISTRY_AUTH_FILE}" >&2; exit 1; fi
mkdir -p "${ROOT}/logs"

image_for() { echo "localhost/cinc-omnibus-builder:$1-${VERSION}"; }
for target in "${targets[@]}"; do
  image="$(image_for "$target")"
  log="${ROOT}/logs/build-omnibus-image-${target}.log"
  auth=(); [[ "$target" == rhel* ]] && auth=(--authfile "${REGISTRY_AUTH_FILE}")
  echo "===== ${target}: build reusable Omnibus image ${VERSION} =====" | tee "$log"
  if [[ "$target" == rhel7 ]]; then
    dir="${ROOT}/artifacts/toolchain/rhel7"
    shopt -s nullglob; rpms=("${dir}"/omnibus-toolchain-"${VERSION}"-*.rpm); shopt -u nullglob
    ((${#rpms[@]} == 1)) || { echo "ERROR: build RHEL7 toolchain ${VERSION} first with ./build-toolchain.sh --version ${VERSION}" >&2; exit 1; }
    podman build "${auth[@]}" -f "${ROOT}/containers/rhel7/Containerfile" \
      --build-arg "TOOLCHAIN_RPM=$(basename "${rpms[0]}")" --build-arg "TOOLCHAIN_VERSION=${VERSION}" \
      -t "$image" "$dir" 2>&1 | tee -a "$log"
  else
    podman build "${auth[@]}" -f "${ROOT}/containers/${target}/Containerfile" \
      --build-arg "TOOLCHAIN_VERSION=${VERSION}" -t "$image" "${ROOT}" 2>&1 | tee -a "$log"
  fi
  podman run --rm "${auth[@]}" --user 0 \
    -v "${ROOT}:/project:ro,z" "$image" \
    /project/scripts/builder/validate-linux.sh --platform "$target" --toolchain-version "$VERSION" 2>&1 | tee -a "$log"
  echo "PASS: ${target} builder ${image}" | tee -a "$log"
done
