function validate_remote_files
{
   if [ ! -d "${DIRREMOTE:-}" ]; then
      echo "Backup Directory not exists."
      end_shell 1
   fi

   export REMOTE_DOMAINS_FILE
   export REMOTE_EMAILS_FILE
   REMOTE_DOMAINS_FILE=$(find "$DIRREMOTE" -maxdepth 1 -type f -name "domains_*.txt" | sort | tail -1)
   REMOTE_EMAILS_FILE=$(find "$DIRREMOTE" -maxdepth 1 -type f -name "emails_*.txt" | sort | tail -1)

   if [ ! -f "${REMOTE_DOMAINS_FILE}" ]; then
      echo "Domain file not exists."
      end_shell 1
   fi
   if [ ! -f "${REMOTE_EMAILS_FILE}" ]; then
      echo "Emails file not exists."
      end_shell 1
   fi

   DATE_PROC=$(echo "$REMOTE_EMAILS_FILE" | awk -F"_" '{print $NF}' | cut -d"." -f1)

   # DIRREMOTE
   export DIRREMOTEUSERPASS="${DIRREMOTE}/userpass_${DATE_PROC}"
   export DIRREMOTEUSERDATA="${DIRREMOTE}/userdata_${DATE_PROC}"
   export DIRREMOTEMAILBOX="${DIRREMOTE}/mailbox_${DATE_PROC}"

   export DLIST_FILE="${DIRREMOTE}/dlist_${DATE_PROC}.txt"
   export DIRREMOTEDLIST="${DIRREMOTE}/dlist_${DATE_PROC}"
   export DIRREMOTEALIAS="${DIRREMOTE}/alias_${DATE_PROC}"
   export DIRREMOTECALENDAR="${DIRREMOTE}/calendar_${DATE_PROC}"
   export DIRREMOTECONTACTS="${DIRREMOTE}/contacts_${DATE_PROC}"
   export DIRREMOTESIGNATURE="${DIRREMOTE}/user_signature_${DATE_PROC}"
   export DIRREMOTERULES="${DIRREMOTE}/rules_${DATE_PROC}"
}

function import_account
{
   validate_remote_files

   #################################################

   begin_process "Provisioning domains"
   log_info "List of Domains:"
   log_info "${ZMPROV} -l gad"
   list_domain=$(prov -l gad)
   log_info "${list_domain}"

   while read -r i; do
      if [ -z "$i" ]; then
         continue
      fi
      log_info "Domain: ${i}"
      if echo "${list_domain}" | grep -Fxq "$i" ; then
         log_info "Domain exists..."
         log_info "Setting Protocol and Port..."
         prov md "$i" zimbraPublicServiceProtocol https
         prov md "$i" zimbraPublicServicePort 443
         prov md "$i" zimbraPrefTimeZoneId "America/Bogota"
         continue
      fi
      provi=$(prov cd "$i" zimbraAuthMech zimbra)
      log_info "${provi}"

      log_info "Setting Protocol and Port..."
      prov md "$i" zimbraPublicServiceProtocol https
      prov md "$i" zimbraPublicServicePort 443
      prov md "$i" zimbraPrefTimeZoneId "America/Bogota"
   done < "$REMOTE_DOMAINS_FILE"

   log_info "List of Domains:"
   log_info "${ZMPROV} -l gad"
   list_domain=$(prov -l gad)
   log_info "${list_domain}"

   end_process "Provisioning domains"

   #################################################

   begin_process "Provisiong accounts"
   q_emails=$(count_file_lines "$REMOTE_EMAILS_FILE")
   count=0
   while read -r i; do
      if [ -z "$i" ]; then
         continue
      fi
      count=$((count + 1))
      log_info "[$count/$q_emails] Account ${i}"
      cn=$(grep "^cn:" "${DIRREMOTEUSERDATA}/$i.txt" | cut -d ":" -f2- || true)
      sn=$(grep "^sn:" "${DIRREMOTEUSERDATA}/$i.txt" | cut -d ":" -f2- || true)
      givenname=$(grep "^givenName:" "${DIRREMOTEUSERDATA}/$i.txt" | cut -d ":" -f2- || true)
      displayname=$(grep "^displayName:" "${DIRREMOTEUSERDATA}/$i.txt" | cut -d ":" -f2- || true)
      zimbraprefidentityname=$(grep "^zimbraPrefIdentityName:" "${DIRREMOTEUSERDATA}/$i.txt" | cut -d ":" -f2- || true)
      shadowpass=$(cat "${DIRREMOTEUSERPASS}/$i.shadow")

      log_info "Creating account"
      if ! prov ca "$i" CHANGEme sn "$sn" cn "$cn" displayName "$displayname" givenName "$givenname" zimbraPrefIdentityName "$zimbraprefidentityname"; then
         log_error "Error creating account $i"
         continue
      fi

      log_info "Updating account password"
      
      # take care with the password: dollar and quotes
      prov ma "$i" userPassword "$shadowpass"
   done < "$REMOTE_EMAILS_FILE"

   log_info "List of Accounts:"
   list_acc=$(prov -l gaa -v "${DOMAIN}" | grep -e displayName || true)
   log_info "${list_acc}"
   end_process "Provisiong accounts"
}


function import_mailbox
{
   validate_remote_files

   #################################################

   begin_process "Importing mailbox"
   log_info "   Important Note:"
   log_info ""
   log_info "Few things you should keep in mind before starting the mailbox export/import process:"
   log_info "1. Set the socket timeout high (i.e. zmlocalconfig -e socket_so_timeout=3000000; zmlocalconfig -reload)"
   log_info "2. Check if you have any attachment limits. If you have increase the value during the migration period"
   log_info "   zmprov modifyConfig zimbraMtaMaxMessageSize 20000000"
   log_info "3. Set Public Service Host Name & Public Service Protocol to avoid any error/issue like below one"

   log_info "** resolve options:"
   log_info "skip    - ignores duplicates of old items, it’s also the default conflict-resolution."
   log_info "modify  - changes old items."
   log_info "reset   - will delete the old subfolder (or entire mailbox if /)."
   log_info "replace - will delete and re-enter them."

   prepare_import_mailbox_config
   sleep 30

   if [[ "${DIRREMOTEMAILBOX}" != *"incremental"* ]] ; then
      q_emails=$(count_file_lines "$REMOTE_EMAILS_FILE")
      count=0
      while read -r email; do
         if [ -z "$email" ]; then
            continue
         fi
         count=$((count + 1))
         log_info "[$count/$q_emails] zmmailbox -z -m ${email} -t 0 postRestURL '/?fmt=tgz&resolve=skip' ${DIRREMOTEMAILBOX}/$email.tgz"
         mailbox -z -m "${email}" -t 0 postRestURL "/?fmt=tgz&resolve=skip" "${DIRREMOTEMAILBOX}/$email.tgz" &
         # curl --max-time 1800 -k -H "Transfer-Encoding: chunked" -u zextras:${ZEXTRAS_PASS} -p -T ${DIRREMOTEMAILBOX}/$email.tgz "https://localhost:6071/service/home/$email/?fmt=tgz&resolve=skip" &
         N_PROC_PARALLEL=$(get_parallel_limit)
         nrwait $N_PROC_PARALLEL
      done < "$REMOTE_EMAILS_FILE"
      wait_all_jobs || { restore_import_mailbox_config; end_shell 1; }
   fi

   if [[ "${DIRREMOTEMAILBOX}" == *"incremental"* ]] ; then
      q_emails=$(count_file_lines "$REMOTE_EMAILS_FILE")
      count=0

      while read -r email; do
         if [ -z "$email" ]; then
            continue
         fi
         count=$((count + 1))
         log_info "[$count/$q_emails] zmmailbox -z -m ${email}..."

         while read -r bk_file; do
            if [ -z "$bk_file" ]; then
               continue
            fi
            log_info "Processing bk: ${email} | ${bk_file}"
            file_size=$(wc -c "${bk_file}" | cut -d' ' -f1)
            if [ "$file_size" == "0" ]; then
               log_info "File empty: ${bk_file}"
               continue
            fi
            log_info "zmmailbox -z -m ${email} -t 0 postRestURL '/?fmt=tgz&resolve=replace' ${bk_file}"
            mailbox -z -m "${email}" -t 0 postRestURL "/?fmt=tgz&resolve=replace" "${bk_file}"
            # curl --max-time 1800 -k -H "Transfer-Encoding: chunked" -u zextras:${ZEXTRAS_PASS} -p -T ${DIRREMOTEMAILBOX}/${email}/${bk_file} "https://localhost:6071/service/home/$email/?fmt=tgz&resolve=replace" &
            # N_PROC_PARALLEL=$(get_parallel_limit)
            # nrwait $N_PROC_PARALLEL
         done < <(find "${DIRREMOTEMAILBOX}/${email}" -maxdepth 1 -type f -name "*.tgz" | sort || true)
      done < "$REMOTE_EMAILS_FILE"
   fi

   restore_import_mailbox_config

   end_process "Importing mailbox"
}

function prepare_import_mailbox_config
{
   log_info "Incrementing value timeout during the migration period"
   localconfig -e socket_so_timeout=7200000

   prov mcf zimbraReverseProxyUpstreamReadTimeout 120m
   prov mcf zimbraReverseProxySSLSessionTimeout 120m
   prov mcf zimbraReverseProxyUpstreamSendTimeout 1200m

   log_info "Incrementing value attachment limits=50MB"
   prov mcf zimbraMtaMaxMessageSize 51200000
   prov mcf zimbraFileUploadMaxSize 52428800
   prov mcf zimbraMailContentMaxSize 51200000

   control restart
}

function restore_import_mailbox_config
{
   log_info "Reseting value timeout during the migration period"
   localconfig -e socket_so_timeout=30000

   prov mcf zimbraReverseProxyUpstreamReadTimeout 60s
   prov mcf zimbraReverseProxySSLSessionTimeout 10m
   prov mcf zimbraReverseProxyUpstreamSendTimeout 60s

   log_info "Reseting value attachment limits=25MB"
   prov mcf zimbraMtaMaxMessageSize 25600000
   prov mcf zimbraFileUploadMaxSize 26214400
   prov mcf zimbraMailContentMaxSize 25600000

   control restart
}

function import_calendar_contacts
{
   validate_remote_files

   #################################################

   begin_process "Importing calendar and contacts"

   q_emails=$(count_file_lines "$REMOTE_EMAILS_FILE")
   count=0
   while read -r email; do
      if [ -z "$email" ]; then
         continue
      fi
      count=$((count + 1))
      log_info "[$count/$q_emails] zmmailbox -z -m ${email}...Calendar"
      mailbox -z -m "${email}" -t 0 postRestURL "/?fmt=tgz&resolve=skip" "${DIRREMOTECALENDAR}/$email.tgz" ;

      log_info "[$count/$q_emails] zmmailbox -z -m ${email}...Contacts"
      mailbox -z -m "${email}" -t 0 postRestURL "/?fmt=tgz&resolve=skip" "${DIRREMOTECONTACTS}/$email.tgz" ;

      log_info "[$count/$q_emails] zmmailbox -z -m ${email}...Emailed Contacts"
      mailbox -z -m "${email}" -t 0 postRestURL "/?fmt=tgz&resolve=skip" "${DIRREMOTECONTACTS}/emailed_$email.tgz" ;

      log_info "${email} -- finished " ;
   done < "$REMOTE_EMAILS_FILE"

   end_process "Importing mailbox"
}

function import_signatures
{
   validate_remote_files

   #################################################

   begin_process "Importing calendar and contacts"

   q_emails=$(count_file_lines "$REMOTE_EMAILS_FILE")
   count=0
   while read -r email; do
      if [ -z "$email" ]; then
         continue
      fi
      count=$((count + 1))

      log_info "[$count/$q_emails] ${email}"
      if [ ! -f "${DIRREMOTESIGNATURE}/${email}_name.txt" ]; then
         log_info "Signature for ${email} not found."
         continue;
      fi

      sig_name=$(cat "${DIRREMOTESIGNATURE}/${email}_name.txt")
      sig_html=$(cat "${DIRREMOTESIGNATURE}/${email}_html.txt")

      log_info "[$count/$q_emails] ${ZMPROV} csig ${email}..."
      prov csig "$email" "${sig_name}" zimbraPrefMailSignatureHTML "${sig_html}"

      log_info "${email} -- finished " ;
   done < "$REMOTE_EMAILS_FILE"

   end_process "Importing mailbox"
}

function import_rules
{
   validate_remote_files

   #################################################

   begin_process "Importing rules"

   q_emails=$(count_file_lines "$REMOTE_EMAILS_FILE")
   count=0
   while read -r email; do
      if [ -z "$email" ]; then
         continue
      fi
      count=$((count + 1))

      log_info "[$count/$q_emails] ${email}"
      if [ ! -f "${DIRREMOTERULES}/${email}_rules.txt" ]; then
         log_info "Rules for ${email} not found."
         continue;
      fi

      if [ -f "${DIRREMOTERULES}/${email}_folders.txt" ]; then
         log_info "Folders Rule for ${email} found."

         while IFS= read -r folder; do
            log_info "Creating folder: $folder"
            log_info "zmmailbox -z -m $email cf -V message $folder"
            mailbox -z -m "$email" cf -V message "$folder"
         done < "${DIRREMOTERULES}/${email}_folders.txt"
      fi

      log_info "${ZMPROV} ma $email zimbraMailSieveScript 'cat ${DIRREMOTERULES}/${email}_rules.txt'"
      prov ma "$email" zimbraMailSieveScript "$(cat "${DIRREMOTERULES}/${email}_rules.txt")"

      log_info "${email} -- finished " ;
   done < "$REMOTE_EMAILS_FILE"

   end_process "Importing rules"
}

function import_dlist
{
   validate_remote_files

   #################################################

   begin_process "Importing distribution list"

   if [ ! -f "$DLIST_FILE" ]; then
      log_info "Distribution List file not found"
      return 0
   fi

   q_dlist=$(count_file_lines "$DLIST_FILE")
   log_info "Total dlist: $q_dlist"

   while IFS= read -r listname; do
      log_info "Importing dlist: $listname"
      log_info "${ZMPROV} cdl $listname..."
      prov cdl "$listname"

      while read -r email; do
         if [ -z "$email" ]; then
            continue
         fi
         log_info "${ZMPROV} adlm $listname $email"
         prov adlm "$listname" "$email"
      done < <(grep -v '#' "${DIRREMOTEDLIST}/${listname}.txt" | grep '@' || true)
   done < "$DLIST_FILE"

   end_process "Importing distribution list"
}

function import_alias
{
   validate_remote_files

   #################################################

   begin_process "Importing alias"

   if [ ! -d "$DIRREMOTEALIAS" ]; then
      log_info "Alias directory not found."
      return 0
   fi

   q_alias=$(find "$DIRREMOTEALIAS" -maxdepth 1 -type f | wc -l | awk '{print $1}')
   log_info "Total alias: $q_alias"

   if [ "$q_alias" -eq 0 ]; then
      log_info "Alias files not found."
      return 0
   fi

   while read -r email_filename; do
      if [ -z "$email_filename" ]; then
         continue
      fi
      email=${email_filename:0:-4}
      log_info "Creating alias to: ${email}"
      while read -r alias; do
         if [ -z "$alias" ]; then
            continue
         fi
         log_info "${ZMPROV} aaa $email $alias ..."
         prov aaa "$email" "$alias"
      done < <(grep '@' "${DIRREMOTEALIAS}/${email_filename}" || true)
   done < <(find "$DIRREMOTEALIAS" -maxdepth 1 -type f -printf "%f\n" | sort)
   end_process "Importing alias"
}

