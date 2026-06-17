function transfer_data
{
   if [ "${TRANSFER_ENABLED:-0}" -ne "1" ] ; then
      return 0
   fi
   begin_process "Transfering backup to remote server"
   if [ "${1:-}" = "" ] ; then
      DIR_BACKUP_WORK=$(find "$DIRAPP" -maxdepth 1 -type d -name "backup_*" -printf "%T@ %p\n" | sort -n | tail -2 | head -1 | awk '{print $2}')
   else
      DIR_BACKUP_WORK=$1
   fi
   if [ -z "$DIR_BACKUP_WORK" ]; then
      log_error "Backup directory to transfer not found."
      end_shell 1
   fi
   log_info "sshpass -p \"${SSHPASSWORD}\" rsync -avp ${DIR_BACKUP_WORK} ${SSHREMOTE}:${SSHDIR} --log-file=${LOGFILE}"

   sshpass -p "${SSHPASSWORD}" rsync -avp "${DIR_BACKUP_WORK}" "${SSHREMOTE}:${SSHDIR}" --log-file="${LOGFILE}"

   if [ "${MAILX_ENABLED:-0}" -eq 1 ] ; then
      log_info "Enviando Correo de confirmacion" ;
      TODAY_PROC=$(date '+%Y/%m/%d')
      echo "Se termino de enviar con exito el backup a SFTP." | /usr/bin/mailx -r "${MAILX_FROM:-}" -s "${MAILX_SUBJECT:-} $TODAY_PROC - OK" "${MAILX_TO:-}" || log_warn "Confirmation email failed"
   fi
   end_process "Transfering backup to remote server"
}

