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
KEEP_WITHIN="${KEEP_WITHIN:-}"
RESTIC_DRY_RUN="${RESTIC_DRY_RUN:-0}"

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

   forget_args=(--tag carbonio)
   if [ -n "$KEEP_WITHIN" ]; then
      echo "Retention policy: keep snapshots within ${KEEP_WITHIN}"
      forget_args+=(--keep-within "$KEEP_WITHIN")
   else
      echo "Retention policy: keep ${KEEP_DAILY} daily, ${KEEP_WEEKLY} weekly, ${KEEP_MONTHLY} monthly snapshots"
      forget_args+=(
         --keep-daily "$KEEP_DAILY"
         --keep-weekly "$KEEP_WEEKLY"
         --keep-monthly "$KEEP_MONTHLY"
      )
   fi

   if [ "$RESTIC_DRY_RUN" = "1" ]; then
      echo "Running retention in dry-run mode"
      forget_args+=(--dry-run)
   else
      forget_args+=(--prune)
   fi

   restic forget "${forget_args[@]}"

   restic snapshots --tag carbonio

   if [ "${RESTIC_RUN_CHECK:-0}" = "1" ]; then
      restic check
   fi

   echo "Finished Restic retention: $(date -Is)"
} >> "$LOG_FILE" 2>&1
