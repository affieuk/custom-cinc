#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/config/build.env"
VERSION="${CINC_VERSION}"
TC_VERSION="${TOOLCHAIN_VERSION}"
CLIENT_REPO="${CINC_CLIENT_REPO}"
CLIENT_REF="${CINC_CLIENT_REF}"
JOBS="${BUILD_CONCURRENCY:-2}"
MEMORY="${CONTAINER_MEMORY:-4g}"
CPUS="${CONTAINER_CPUS:-8}"
TMUX="${TMUX_DASHBOARD:-0}"
REGISTRY_AUTH_FILE="${REGISTRY_AUTH_FILE:-/root/.config/containers/auth.json}"

usage() {
  cat <<USAGE
usage: $0 [all|rhel7|rhel8|rhel10|ubuntu2204 ...] [options]

Options:
  --version X.Y.Z             Cinc Client version (default: ${CINC_VERSION})
  --toolchain-version X.Y.Z   reusable builder/toolchain version (default: ${TOOLCHAIN_VERSION})
  --client-ref REF            distribution/client ref (default: ${CINC_CLIENT_REF})
  --jobs N                    concurrent target pipelines (default: 2)
  --memory SIZE               memory limit per target container (default: 4g)
  --cpus N                    CPU limit per target container (default: 8)
  --tmux / --no-tmux          optional split-pane progress dashboard

"all" means the four Linux targets. Build Windows on the Windows Server 2025
host with .\\build-cinc-client.ps1.
USAGE
}
selectors=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    all|rhel7|rhel8|rhel10|ubuntu2204) selectors+=("$1"); shift ;;
    --version) VERSION="${2:?missing version}"; shift 2 ;;
    --toolchain-version) TC_VERSION="${2:?missing toolchain version}"; shift 2 ;;
    --client-ref) CLIENT_REF="${2:?missing client ref}"; shift 2 ;;
    -j|--jobs) JOBS="${2:?missing jobs}"; shift 2 ;;
    --memory) MEMORY="${2:?missing memory}"; shift 2 ;;
    --cpus) CPUS="${2:?missing cpus}"; shift 2 ;;
    --tmux) TMUX=1; shift ;;
    --no-tmux) TMUX=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
((${#selectors[@]})) || selectors=(all)
targets=()
add() { local x=$1 y; for y in "${targets[@]}"; do [[ "$y" == "$x" ]] && return; done; targets+=("$x"); }
for s in "${selectors[@]}"; do case "$s" in all) for t in rhel7 rhel8 rhel10 ubuntu2204; do add "$t"; done ;; *) add "$s" ;; esac; done

command -v podman >/dev/null 2>&1 || { echo "ERROR: podman is required" >&2; exit 1; }
# shellcheck disable=SC1091
source "${ROOT}/scripts/lib/parallel-runner.sh"
needs_redhat=0; for t in "${targets[@]}"; do [[ "$t" == rhel* ]] && needs_redhat=1; done
if ((needs_redhat)) && [[ ! -r "$REGISTRY_AUTH_FILE" ]]; then echo "ERROR: Red Hat registry auth file is not readable: $REGISTRY_AUTH_FILE" >&2; exit 1; fi

WORK="${ROOT}/.work/cinc-client"
HANDOFF="${WORK}/handoff"
ARTIFACT_ROOT="${ROOT}/artifacts/cinc"
LOG_ROOT="${ROOT}/logs/cinc-client"
rm -rf "$WORK"
mkdir -p "$HANDOFF/scripts/client" "$HANDOFF/scripts/builder" "$HANDOFF/overrides/cinc" "$ARTIFACT_ROOT" "$LOG_ROOT"
cp "$ROOT/scripts/client/"*.sh "$HANDOFF/scripts/client/"
cp "$ROOT/scripts/builder/validate-linux.sh" "$HANDOFF/scripts/builder/"
cp "$ROOT/overrides/cinc/omnibus.rb" "$ROOT/overrides/cinc/Gemfile" "$HANDOFF/overrides/cinc/"
chmod 0755 "$HANDOFF/scripts/client/"*.sh "$HANDOFF/scripts/builder/validate-linux.sh"

builder_for() { echo "localhost/cinc-omnibus-builder:$1-${TC_VERSION}"; }
runtime_for() {
  case "$1" in
    rhel7) echo 'registry.redhat.io/rhel7/rhel:latest' ;;
    rhel8) echo 'registry.redhat.io/ubi8/ubi:latest' ;;
    rhel10) echo 'registry.redhat.io/ubi10/ubi:latest' ;;
    ubuntu2204) echo 'docker.io/library/ubuntu:22.04' ;;
  esac
}
find_package() {
  local target=$1 dir=$2 files=()
  shopt -s nullglob
  case "$target" in rhel*) files=("$dir"/cinc*.rpm) ;; ubuntu2204) files=("$dir"/cinc*.deb) ;; esac
  shopt -u nullglob
  ((${#files[@]} == 1)) || return 1
  echo "${files[0]}"
}

run_target() {
  local target=$1 slot=$2 builder runtime out package build_log validate_log build_rc validate_rc
  local -a auth
  builder="$(builder_for "$target")"; runtime="$(runtime_for "$target")"; out="$ARTIFACT_ROOT/$target"
  build_log="$LOG_ROOT/${target}-build.log"; validate_log="$LOG_ROOT/${target}-validate.log"
  rm -rf "$out"; mkdir -p "$out"
  auth=(); [[ "$target" == rhel* ]] && auth=(--authfile "$REGISTRY_AUTH_FILE")
  podman image exists "$builder" || { echo "ERROR: builder image missing: $builder" >&2; return 1; }

  echo "===== ${target}: build Cinc Client ${VERSION} ====="
  set +e
  podman run --rm "${auth[@]}" --user 0 --memory "$MEMORY" --cpus "$CPUS" \
    -e "TARGET=$target" -e "REF=v${VERSION}" -e "EXPECTED_TARGET_VERSION=$VERSION" \
    -e "CLIENT_REPO=$CLIENT_REPO" -e "CLIENT_REF=$CLIENT_REF" -e "TOOLCHAIN_VERSION=$TC_VERSION" \
    -v "$HANDOFF:/handoff:ro,z" -v "$out:/artifacts/${target}:Z" \
    "$builder" /handoff/scripts/client/build-linux.sh 2>&1 | tee "$build_log"
  build_rc=${PIPESTATUS[0]}; set -e
  ((build_rc == 0)) || return "$build_rc"
  package="$(find_package "$target" "$out")" || { echo "ERROR: expected exactly one Cinc package in $out" >&2; return 1; }

  echo "===== ${target}: clean package validation ====="
  set +e
  podman run --rm "${auth[@]}" --user 0 --memory "$MEMORY" --cpus "$CPUS" \
    -e "TARGET=$target" -e "PACKAGE_BASENAME=$(basename "$package")" -e "EXPECTED_TARGET_VERSION=$VERSION" \
    -v "$HANDOFF:/handoff:ro,z" -v "$out:/artifacts:ro,Z" \
    "$runtime" /handoff/scripts/client/validate-linux.sh 2>&1 | tee "$validate_log"
  validate_rc=${PIPESTATUS[0]}; set -e
  return "$validate_rc"
}

parallel_runner_init cinc-client "$WORK" "$JOBS" "$TMUX" cinc-client-build || exit $?
for target in "${targets[@]}"; do
  parallel_runner_acquire_slot
  parallel_runner_launch "$PARALLEL_SLOT" "$target" run_target
 done
parallel_runner_wait_all

echo
echo "Artifacts: $ARTIFACT_ROOT"
echo "Logs:      $LOG_ROOT"
exit "$PARALLEL_ANY_FAILURE"
