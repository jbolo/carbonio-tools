#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESTIC_ENV_FILE="${RESTIC_ENV_FILE:-${HOME}/.config/restic/r2.env}"
BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-/var/backups/carbonio-mailops}"
LOG_DIR="${LOG_DIR:-${APP_DIR}/log}"
LOCK_FILE="${LOCK_FILE:-/tmp/carbonio-restic-incremental.lock}"
TODAY="$(date +%F)"
LOG_FILE="${LOG_DIR}/restic_incremental_${TODAY}_$(date +%H%M%S).log"
LOCAL_INCREMENTAL_KEEP_DAYS="${LOCAL_INCREMENTAL_KEEP_DAYS:-}"
LOCAL_CLEANUP_DRY_RUN="${LOCAL_CLEANUP_DRY_RUN:-0}"

mkdir -p "$LOG_DIR"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
   echo "Another incremental backup is already running: ${LOCK_FILE}" >&2
   exit 1
fi

{
   echo "Starting Carbonio incremental backup: $(date -Is)"
   cd "$APP_DIR"

   if [ ! -f "$RESTIC_ENV_FILE" ]; then
      echo "Restic env file not found: ${RESTIC_ENV_FILE}" >&2
      exit 1
   fi

   # shellcheck disable=SC1090
   source "$RESTIC_ENV_FILE"

   command -v restic >/dev/null

   mkdir -p "$BACKUP_BASE_DIR"

   if [ -n "$LOCAL_INCREMENTAL_KEEP_DAYS" ]; then
      echo "Local cleanup: incremental files older than ${LOCAL_INCREMENTAL_KEEP_DAYS} days"
      if [ -d "${BACKUP_BASE_DIR}/backup_incremental" ]; then
         if [ "$LOCAL_CLEANUP_DRY_RUN" = "1" ]; then
            find "${BACKUP_BASE_DIR}/backup_incremental" -type f -mtime +"$LOCAL_INCREMENTAL_KEEP_DAYS" -print
         else
            find "${BACKUP_BASE_DIR}/backup_incremental" -type f -mtime +"$LOCAL_INCREMENTAL_KEEP_DAYS" -print -delete
            find "${BACKUP_BASE_DIR}/backup_incremental" -type d -empty -print -delete
         fi
      fi
   fi

   if [ "$LOCAL_CLEANUP_DRY_RUN" = "1" ] && [ -n "$LOCAL_INCREMENTAL_KEEP_DAYS" ]; then
      echo "Local cleanup dry-run finished; skipping export and restic backup"
      exit 0
   fi

   export BACKUP_BASE_DIR

   ./carbonio-mailops.sh --export-incremental

   restic backup \
      "${BACKUP_BASE_DIR}/backup_incremental" \
      "${APP_DIR}/carbonio-mailops.sh" \
      "${APP_DIR}/mail_migrate.sh" \
      "${APP_DIR}/functions.sh" \
      "${APP_DIR}/lib" \
      "${APP_DIR}/scripts" \
      "${APP_DIR}/mailbox_groups" \
      "${APP_DIR}/README.md" \
      "${APP_DIR}/AGENTS.md" \
      --tag carbonio \
      --tag incremental \
      --tag "$TODAY" \
      --verbose=2

   restic snapshots --tag carbonio

   if [ "${RESTIC_RUN_CHECK:-0}" = "1" ]; then
      restic check
   fi

   echo "Finished Carbonio incremental backup: $(date -Is)"
} >> "$LOG_FILE" 2>&1
