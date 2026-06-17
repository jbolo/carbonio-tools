function set_context
{
   local action="${1:-}"

   export TYPEB="full"
   export DIRBACKUP="${DIRAPP}/backup_${TYPEB}_${TODAY_LINE}"
   export DIRMAILBOX="${DIRBACKUP}/mailbox_${TODAY_LINE}"
   if [[ "$action" == *"incremental"* ]] ; then
      export TYPEB="incremental"
      export DIRBACKUP="${DIRAPP}/backup_${TYPEB}"
      export DIRMAILBOX="${DIRBACKUP}/mailbox"
   fi

   if [ -d "${PATH_BIN_ZIMBRA:-}" ] ; then
      export CONTEXT="ZIMBRA"
      export USER_APP=$USER_ZIMBRA
      export PATH_BIN_APP=$PATH_BIN_ZIMBRA
      export ZMPROV="$PATH_BIN_ZIMBRA/zmprov"
      export ZMCONTROL="$PATH_BIN_ZIMBRA/zmcontrol"
      export ZMMAILBOX="$PATH_BIN_ZIMBRA/zmmailbox"
      export ZMLOCALCONFIG="$PATH_BIN_ZIMBRA/zmlocalconfig"

   elif [ -d "${PATH_BIN_CARBONIO:-}" ]; then
      export CONTEXT="CARBONIO"
      export USER_APP=$USER_CARBONIO
      export PATH_BIN_APP=$PATH_BIN_CARBONIO
      export ZMPROV="$PATH_BIN_CARBONIO/carbonio prov"
      export ZMCONTROL="$PATH_BIN_CARBONIO/zmcontrol"
      export ZMMAILBOX="$PATH_BIN_CARBONIO/zmmailbox"
      export ZMLOCALCONFIG="$PATH_BIN_CARBONIO/zmlocalconfig"
   else
      log_error "Context type not identified."
      end_shell 1
   fi

   validate_user "$USER_APP"

   if [[ "$action" == *"import"* ]] ; then
      validate_remote_files
      return 0
   fi

   export DIRUSERPASS="${DIRBACKUP}/userpass_${TODAY_LINE}"
   export DIRUSERDATA="${DIRBACKUP}/userdata_${TODAY_LINE}"
   export DIRDLIST="${DIRBACKUP}/dlist_${TODAY_LINE}"
   export DIRALIAS="${DIRBACKUP}/alias_${TODAY_LINE}"
   export DIRCALENDAR="${DIRBACKUP}/calendar_${TODAY_LINE}"
   export DIRCONTACTS="${DIRBACKUP}/contacts_${TODAY_LINE}"
   export DIRSIGNATURE="${DIRBACKUP}/user_signature_${TODAY_LINE}"
   export DIRRULES="${DIRBACKUP}/rules_${TODAY_LINE}"

   # CREATE DIRECTORIES
   ensure_dirs "$DIRBACKUP" "$DIRUSERPASS" "$DIRUSERDATA" "$DIRMAILBOX" "$DIRDLIST" "$DIRALIAS" "$DIRCALENDAR" "$DIRCONTACTS" "$DIRSIGNATURE" "$DIRRULES"
}

function validate_user
{
   user=$(whoami)
   if [[ ! "$user" == "${USER_APP}" ]]; then
      log_error "The actually user is not: ${USER_APP}"
      end_shell 1
   fi
}

function ensure_dirs
{
   local dir

   for dir in "$@"; do
      if [ ! -d "$dir" ]; then
         mkdir -p "$dir"
      fi
   done
}

function get_status_server
{
   begin_process "Getting status"
   version=$(control -v)
   log_info "${version}"

   status=$(control status)
   log_info "${status}"
   end_process "Getting status"
}

function get_list_emails
{
   EMAILS_FILE="${1:-}"
   if [ -z "$EMAILS_FILE" ]; then
      echo "Filename empty"
      exit 1
   fi

   begin_process "Getting emails"
   log_info "${ZMPROV} -l gaa ${DOMAIN} > ${EMAILS_FILE}"
   prov -l gaa "${DOMAIN}"  | grep -E -v "^(spam|ham|galsync|virus|zextras)" > "${EMAILS_FILE}"
   cat "${EMAILS_FILE}"
   q_emails=$(count_file_lines "$EMAILS_FILE")
   log_info "Total emails: $q_emails"
   end_process "Getting emails"
}

