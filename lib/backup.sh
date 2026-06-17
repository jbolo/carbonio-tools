function delete_old_export
{
   if [ "${DELETE_OLD_EXPORT_ENABLED:-0}" -ne "1" ] ; then
      return 0
   fi

   begin_process "Deleting old exports"
   log_info "find ${DIRAPP} -maxdepth 1 -name \"backup_full_*\" -type d -mtime +${DELETE_OLD_EXPORT_DAYS}"
   find "$DIRAPP" -maxdepth 1 -name "backup_full_*" -type d -mtime +"${DELETE_OLD_EXPORT_DAYS}" -print >> "$LOGFILE"
   find "$DIRAPP" -maxdepth 1 -name "backup_full_*" -type d -mtime +"${DELETE_OLD_EXPORT_DAYS}" -exec rm -rf "{}" \; >> "$LOGFILE"
   end_process "Deleting old exports"
}
