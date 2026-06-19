#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESTIC_ENV_FILE="${RESTIC_ENV_FILE:-${HOME}/.config/restic/r2.env}"
LOG_DIR="${LOG_DIR:-${APP_DIR}/log}"
LOCK_FILE="${LOCK_FILE:-/tmp/carbonio-restic-full.lock}"
TODAY="$(date +%F)"
LOG_FILE="${LOG_DIR}/restic_full_${TODAY}_$(date +%H%M%S).log"

mkdir -p "$LOG_DIR"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
   echo "Another full backup is already running: ${LOCK_FILE}" >&2
   exit 1
fi

{
   echo "Starting Carbonio full backup: $(date -Is)"
   cd "$APP_DIR"

   if [ ! -f "$RESTIC_ENV_FILE" ]; then
      echo "Restic env file not found: ${RESTIC_ENV_FILE}" >&2
      exit 1
   fi

   # shellcheck disable=SC1090
   source "$RESTIC_ENV_FILE"

   command -v restic >/dev/null

   ./carbonio-mailops.sh --export

   restic backup "$APP_DIR" \
      --tag carbonio \
      --tag full \
      --tag "$TODAY" \
      --verbose=2

   restic snapshots --tag carbonio

   if [ "${RESTIC_RUN_CHECK:-0}" = "1" ]; then
      restic check
   fi

   echo "Finished Carbonio full backup: $(date -Is)"
} >> "$LOG_FILE" 2>&1
