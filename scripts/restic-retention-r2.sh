#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESTIC_ENV_FILE="${RESTIC_ENV_FILE:-${HOME}/.config/restic/r2.env}"
LOG_DIR="${LOG_DIR:-${APP_DIR}/log}"
LOCK_FILE="${LOCK_FILE:-/tmp/carbonio-restic-retention.lock}"
TODAY="$(date +%F)"
LOG_FILE="${LOG_DIR}/restic_retention_${TODAY}_$(date +%H%M%S).log"

KEEP_DAILY="${KEEP_DAILY:-14}"
KEEP_WEEKLY="${KEEP_WEEKLY:-8}"
KEEP_MONTHLY="${KEEP_MONTHLY:-12}"

mkdir -p "$LOG_DIR"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
   echo "Another restic retention job is already running: ${LOCK_FILE}" >&2
   exit 1
fi

{
   echo "Starting Restic retention: $(date -Is)"
   cd "$APP_DIR"

   if [ ! -f "$RESTIC_ENV_FILE" ]; then
      echo "Restic env file not found: ${RESTIC_ENV_FILE}" >&2
      exit 1
   fi

   # shellcheck disable=SC1090
   source "$RESTIC_ENV_FILE"

   command -v restic >/dev/null

   restic forget \
      --tag carbonio \
      --keep-daily "$KEEP_DAILY" \
      --keep-weekly "$KEEP_WEEKLY" \
      --keep-monthly "$KEEP_MONTHLY" \
      --prune

   restic snapshots --tag carbonio

   if [ "${RESTIC_RUN_CHECK:-0}" = "1" ]; then
      restic check
   fi

   echo "Finished Restic retention: $(date -Is)"
} >> "$LOG_FILE" 2>&1
