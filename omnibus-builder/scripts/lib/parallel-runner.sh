#!/usr/bin/env bash
# Shared host-side parallel runner for the RHEL 9 Podman orchestrators.
#
# The worker function itself performs one complete target build + validation.
# This library limits how many workers are active at once, assigns each worker
# a stable progress slot, and can expose those slot logs in a tmux dashboard.

parallel_runner_init() {
  local name=$1 run_root=$2 jobs=$3 tmux_dashboard=$4 tmux_session=$5

  [[ "${jobs}" =~ ^[1-9][0-9]*$ ]] || {
    echo "ERROR: build concurrency must be a positive integer: ${jobs}" >&2
    return 2
  }

  PARALLEL_NAME="${name}"
  PARALLEL_RUN_ROOT="${run_root}"
  PARALLEL_JOBS="${jobs}"
  PARALLEL_TMUX_DASHBOARD="${tmux_dashboard}"
  PARALLEL_TMUX_SESSION="${tmux_session}"
  PARALLEL_STATUS_ROOT="${run_root}/runner"
  PARALLEL_ANY_FAILURE=0
  PARALLEL_SLOT=''

  mkdir -p "${PARALLEL_STATUS_ROOT}"
  rm -f "${PARALLEL_STATUS_ROOT}"/*.status "${PARALLEL_STATUS_ROOT}"/*.live.log 2>/dev/null || true

  declare -gA PARALLEL_PIDS=()
  declare -gA PARALLEL_TARGETS=()

  local slot
  for ((slot=1; slot<=PARALLEL_JOBS; slot++)); do
    printf 'slot %d: waiting for work\n' "${slot}" > "${PARALLEL_STATUS_ROOT}/slot-${slot}.log"
  done

  if [[ "${PARALLEL_TMUX_DASHBOARD}" == 1 ]]; then
    parallel_runner_start_tmux
  fi
}

parallel_runner_start_tmux() {
  if ! command -v tmux >/dev/null 2>&1; then
    echo "WARNING: --tmux requested but tmux is not installed; continuing without dashboard." >&2
    PARALLEL_TMUX_DASHBOARD=0
    return 0
  fi

  if tmux has-session -t "${PARALLEL_TMUX_SESSION}" 2>/dev/null; then
    tmux kill-session -t "${PARALLEL_TMUX_SESSION}"
  fi

  # Never assume tmux windows or panes start at index 0.  User tmux configs can
  # set base-index/pane-base-index to 1 (or another value).  Work with tmux's
  # stable internal @window and %pane IDs instead.
  local slot log qlog cmd window_id pane_id
  log="${PARALLEL_STATUS_ROOT}/slot-1.log"
  printf -v qlog '%q' "${log}"
  cmd="exec tail -n 80 -F ${qlog}"

  if ! tmux new-session -d -s "${PARALLEL_TMUX_SESSION}" -n progress "${cmd}"; then
    echo "ERROR: could not create tmux session ${PARALLEL_TMUX_SESSION}" >&2
    return 1
  fi

  window_id="$(tmux display-message -p -t "${PARALLEL_TMUX_SESSION}:progress" '#{window_id}')" || {
    echo "ERROR: could not resolve tmux progress window" >&2
    return 1
  }
  pane_id="$(tmux list-panes -t "${window_id}" -F '#{pane_id}' | head -n 1)"
  [[ -n "${pane_id}" ]] || {
    echo "ERROR: could not resolve first tmux dashboard pane" >&2
    return 1
  }
  tmux select-pane -t "${pane_id}" -T 'slot 1' >/dev/null

  for ((slot=2; slot<=PARALLEL_JOBS; slot++)); do
    log="${PARALLEL_STATUS_ROOT}/slot-${slot}.log"
    printf -v qlog '%q' "${log}"
    cmd="exec tail -n 80 -F ${qlog}"

    pane_id="$(tmux split-window -P -F '#{pane_id}' -t "${window_id}" "${cmd}")" || {
      echo "ERROR: could not create tmux pane for slot ${slot}" >&2
      return 1
    }
    tmux select-pane -t "${pane_id}" -T "slot ${slot}" >/dev/null
  done

  tmux select-layout -t "${window_id}" tiled >/dev/null || {
    echo "ERROR: could not tile tmux dashboard panes" >&2
    return 1
  }
  tmux set-option -t "${PARALLEL_TMUX_SESSION}" remain-on-exit on >/dev/null
  tmux set-option -t "${window_id}" pane-border-status top >/dev/null 2>&1 || true
  tmux set-option -t "${window_id}" pane-border-format '#{pane_index}: #{pane_title}' >/dev/null 2>&1 || true

  echo "tmux dashboard: tmux attach -t ${PARALLEL_TMUX_SESSION}"
  echo "Detach with Ctrl-b d; the builds keep running."
}

parallel_runner_find_free_slot() {
  local slot
  PARALLEL_SLOT=''
  for ((slot=1; slot<=PARALLEL_JOBS; slot++)); do
    if [[ -z "${PARALLEL_PIDS[${slot}]:-}" ]]; then
      PARALLEL_SLOT="${slot}"
      return 0
    fi
  done
  return 1
}

parallel_runner_finish_pid() {
  local finished_pid=$1 wait_rc=$2
  local slot target

  for ((slot=1; slot<=PARALLEL_JOBS; slot++)); do
    if [[ "${PARALLEL_PIDS[${slot}]:-}" == "${finished_pid}" ]]; then
      target="${PARALLEL_TARGETS[${slot}]}"
      printf '[done]  slot=%s target=%s rc=%s log=%s\n' \
        "${slot}" "${target}" "${wait_rc}" "${PARALLEL_STATUS_ROOT}/${target}.live.log"
      if ((wait_rc != 0)); then PARALLEL_ANY_FAILURE=1; fi
      unset 'PARALLEL_PIDS['"${slot}"']'
      unset 'PARALLEL_TARGETS['"${slot}"']'
      printf 'slot %d: waiting for work\n' "${slot}" >> "${PARALLEL_STATUS_ROOT}/slot-${slot}.log"
      return 0
    fi
  done

  echo "WARNING: completed worker pid ${finished_pid} was not mapped to a slot" >&2
  PARALLEL_ANY_FAILURE=1
  return 1
}

parallel_runner_wait_one() {
  local finished_pid='' wait_rc
  if wait -n -p finished_pid; then
    wait_rc=0
  else
    wait_rc=$?
  fi

  if [[ -z "${finished_pid}" ]]; then
    echo "ERROR: wait -n returned without a worker pid" >&2
    PARALLEL_ANY_FAILURE=1
    return 1
  fi

  parallel_runner_finish_pid "${finished_pid}" "${wait_rc}"
}

parallel_runner_acquire_slot() {
  while ! parallel_runner_find_free_slot; do
    parallel_runner_wait_one || true
  done
}

parallel_runner_launch() {
  local slot=$1 target=$2 worker_function=$3
  local slot_log target_live
  shift 3

  slot_log="${PARALLEL_STATUS_ROOT}/slot-${slot}.log"
  target_live="${PARALLEL_STATUS_ROOT}/${target}.live.log"

  : > "${target_live}"
  {
    printf '\n===== slot %d: %s =====\n' "${slot}" "${target}"
    printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'target_log=%s\n\n' "${target_live}"
  } > "${slot_log}"

  (
    # Keep concurrent workers from interleaving thousands of build lines in the
    # parent terminal. Every line goes to both the target log and the slot log.
    exec > >(tee -a "${target_live}" >> "${slot_log}") 2>&1
    "${worker_function}" "${target}" "${slot}" "$@"
  ) &

  PARALLEL_PIDS["${slot}"]=$!
  PARALLEL_TARGETS["${slot}"]="${target}"

  printf '[start] slot=%s target=%s pid=%s log=%s\n' \
    "${slot}" "${target}" "${PARALLEL_PIDS[${slot}]}" "${target_live}"
}

parallel_runner_wait_all() {
  local slot active
  while :; do
    active=0
    for ((slot=1; slot<=PARALLEL_JOBS; slot++)); do
      [[ -n "${PARALLEL_PIDS[${slot}]:-}" ]] && active=$((active+1))
    done
    ((active == 0)) && break
    parallel_runner_wait_one || true
  done
}
