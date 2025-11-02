#!/usr/bin/env bash
set -euo pipefail

# ---- CONFIG ----
CONTAINER="${CONTAINER:-plex}"                         # docker container name
TRANSCODE_DIR_HOST="${TRANSCODE_DIR_HOST:-~/plex/transcode}"  # host path mapped to /transcode
STALE_MINUTES="${STALE_MINUTES:-10}"                  # how old a stale chunk must be to count (minutes)
LOG_WINDOW="${LOG_WINDOW:-10m}"                       # how far back to scan logs (e.g., 10m, 1h)
RESTART_ON_ERROR="${RESTART_ON_ERROR:-1}"             # 1 = restart on detection
CLEAR_DIR_ON_RESTART="${CLEAR_DIR_ON_RESTART:-1}"     # 1 = clear transcode dir before restart
# Optional: set PLEX_TOKEN to enable API session check (recommended).
# export PLEX_TOKEN=xxxxxxxxxxxxxxxxxxxx

# ---- FUNCTIONS ----
have_api_token() { [[ -n "${PLEX_TOKEN:-}" ]]; }

active_sessions_via_api() {
  # Tries localhost first (same host), then container IP
  local urls=("http://127.0.0.1:32400/status/sessions" "http://localhost:32400/status/sessions")
  local xml=""
  for u in "${urls[@]}"; do
    if xml="$(curl -fsS -m 2 "${u}?X-Plex-Token=${PLEX_TOKEN}" || true)"; then
      break
    fi
  done
  # Count <Video ...> items
  grep -c "<Video " <<<"${xml:-}" || echo 0
}

active_sessions_via_ps() {
  # Look for Plex Transcoder / ffmpeg inside the container
  docker exec "${CONTAINER}" sh -c 'pgrep -af "Plex .*Transcoder|ffmpeg|Plex New Transcoder" >/dev/null 2>&1'
  if [[ $? -eq 0 ]]; then
    docker exec "${CONTAINER}" sh -c 'pgrep -af "Plex .*Transcoder|ffmpeg|Plex New Transcoder" | wc -l'
  else
    echo 0
  fi
}

count_active_sessions() {
  if have_api_token; then
    active_sessions_via_api
  else
    active_sessions_via_ps
  fi
}

has_stale_transcode_chunks() {
  # Any file in TRANSCODE_DIR_HOST older than STALE_MINUTES?
  [[ -d "${TRANSCODE_DIR_HOST}" ]] || return 1
  find "${TRANSCODE_DIR_HOST}" -type f -mmin +"${STALE_MINUTES}" | head -n1 | grep -q .
}

recent_transcoder_errors() {
  # Look for failure/crash signatures in recent logs
  docker logs --since "${LOG_WINDOW}" "${CONTAINER}" 2>&1 \
    | grep -E -i 'Transcod(er|e).*fail|Transcod(er|e).*crash|ffmpeg.*(error|fail)|decoder.*error' \
    >/dev/null
}

restart_container() {
  echo "[watchdog] Restarting ${CONTAINER}…"
  if [[ "${CLEAR_DIR_ON_RESTART}" == "1" && -d "${TRANSCODE_DIR_HOST}" ]]; then
    echo "[watchdog] Clearing ${TRANSCODE_DIR_HOST}…"
    rm -rf "${TRANSCODE_DIR_HOST:?}/"* || true
  fi
  docker restart "${CONTAINER}" >/dev/null
  echo "[watchdog] ${CONTAINER} restarted."
}

# ---- MAIN ----
SESSIONS="$(count_active_sessions || echo 0)"
STALE=false
ERRORS=false

if has_stale_transcode_chunks; then
  STALE=true
fi

if recent_transcoder_errors; then
  ERRORS=true
fi

echo "[watchdog] sessions=${SESSIONS} stale=${STALE} errors=${ERRORS}"

# ZOMBIE HEURISTIC:
# - Stale chunks present AND no active sessions  OR
# - Recent transcoder errors and no active sessions
if { $STALE && [[ "${SESSIONS}" -eq 0 ]]; } || { $ERRORS && [[ "${SESSIONS}" -eq 0 ]]; }; then
  echo "[watchdog] Likely zombified transcoder detected."
  if [[ "${RESTART_ON_ERROR}" == "1" ]]; then
    restart_container
  else
    echo "[watchdog] Would restart ${CONTAINER}, but RESTART_ON_ERROR=0"
  fi
else
  echo "[watchdog] No action needed."
fi
