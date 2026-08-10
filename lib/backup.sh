function delete_old_export
{
   if [ "${DELETE_OLD_EXPORT_ENABLED:-0}" -ne "1" ] ; then
      return 0
   fi

   begin_process "Deleting old exports"
   BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-$DIRAPP}"
   log_info "find ${BACKUP_BASE_DIR} -maxdepth 1 -name \"backup_full_*\" -type d -mtime +${DELETE_OLD_EXPORT_DAYS}"
   find "$BACKUP_BASE_DIR" -maxdepth 1 -name "backup_full_*" -type d -mtime +"${DELETE_OLD_EXPORT_DAYS}" -print >> "$LOGFILE"
   find "$BACKUP_BASE_DIR" -maxdepth 1 -name "backup_full_*" -type d -mtime +"${DELETE_OLD_EXPORT_DAYS}" -exec rm -rf "{}" \; >> "$LOGFILE"
   end_process "Deleting old exports"
}
