function export_account
{
   cd "${DIRBACKUP}"

   begin_process "Getting domains"
   log_info "${ZMPROV} -l gad > domains_${TODAY_LINE}.txt"
   prov -l gad > "${DIRBACKUP}/domains_${TODAY_LINE}.txt"

   if [[ "${DOMAIN:-}" != "" ]]; then
      if ! grep -Fxq "${DOMAIN}" "${DIRBACKUP}/domains_${TODAY_LINE}.txt"; then
         log_error "Domain ${DOMAIN} not exist."
         end_shell 1
      fi
      log_info "Using domain: ${DOMAIN}"
      echo "${DOMAIN}" > "${DIRBACKUP}/domains_${TODAY_LINE}.txt"
   fi
   end_process "Getting domains"

   #################################################

   EMAILS_FILE="${DIRBACKUP}/emails_${TODAY_LINE}.txt"
   get_list_emails "${EMAILS_FILE}"

   #################################################

   begin_process "Exporting users and password"
   log_info "Exporting user password in: ${DIRUSERPASS}"
   count=0
   while read -r i; do
      if [ -z "$i" ]; then
         continue
      fi
      count=$((count + 1))
      log_info "[$count/$q_emails] ${ZMPROV} -l ga ${i} userPassword..."
      prov -l ga "${i}" userPassword | grep userPassword: | awk '{print $2}' > "${DIRUSERPASS}/${i}.shadow" || true
   done < "$EMAILS_FILE"

   end_process "Exporting users and password"

   #################################################

   begin_process "Exporting usersdata"
   log_info "Exporting user data in: ${DIRUSERDATA}"
   count=0
   while read -r i; do
      if [ -z "$i" ]; then
         continue
      fi
      count=$((count + 1))
      log_info "[$count/$q_emails] ${ZMPROV} ga ${i}..."
      prov ga "${i}" | grep -E "^(cn:|sn:|displayName:|givenName:|zimbraPrefIdentityName:)" > "${DIRUSERDATA}/${i}.txt" || true
   done < "$EMAILS_FILE"

   end_process "Exporting usersdata"
}

function export_mailbox
{
   EMAILS_FILE="${DIRBACKUP}/emails_${TODAY_LINE}.txt"
   REPORT_FILE="${DIRBACKUP}/report_${TODAY_LINE}.txt"
   if [ ! -f "$EMAILS_FILE" ]; then
      # file not exists
      get_list_emails "$EMAILS_FILE"
   fi
   count_mailbox_user "$EMAILS_FILE" "$REPORT_FILE"

   begin_process "Exporting mailbox"

   log_info "Exporting mailbox in : ${DIRMAILBOX}"
   if [ "$TYPEB" == "full" ] ; then
      log_info "Execution of full backup"
      q_emails=$(count_file_lines "$EMAILS_FILE")
      count=0
      while read -r email; do
         if [ -z "$email" ]; then
            continue
         fi
         count=$((count + 1))
         log_info "[$count/$q_emails] ${ZMMAILBOX} -z -m ${email} -t 0 getRestURL '/?fmt=tgz' > ${DIRMAILBOX}/${email}.tgz" ;
         mailbox -z -m "${email}" -t 0 getRestURL '/?fmt=tgz' > "${DIRMAILBOX}/${email}.tgz" &
         N_PROC_PARALLEL=$(get_parallel_limit)
         nrwait $N_PROC_PARALLEL
      done < "$EMAILS_FILE"
      wait_all_jobs || end_shell 1
   fi
   if [ "$TYPEB" == "incremental" ] ; then
      log_info "Execution of incremental backup"
      day_after=$(date -d '-48 hours' +"%m/%d/%Y")
      day_before=$(date +"%m/%d/%Y")
      day_bk=$(date -d '-24 hours' +"%Y-%m-%d")
      filename_tgz="${day_bk}.tgz"
      query="&query=after:\"${day_after}\" and before:\"${day_before}\""
      log_info "Incremental for day: ${day_bk}"

      q_emails=$(count_file_lines "$EMAILS_FILE")
      count=0
      while read -r email; do
         if [ -z "$email" ]; then
            continue
         fi
         mkdir -p "${DIRMAILBOX}/${email}/"
         count=$((count + 1))
         log_info "[$count/$q_emails] ${ZMMAILBOX} -z -m ${email} -t 0 getRestURL '/?fmt=tgz${query}' > ${DIRMAILBOX}/${email}/${filename_tgz}" ;
         mailbox -z -m "${email}" -t 0 getRestURL "/?fmt=tgz${query}" > "${DIRMAILBOX}/${email}/${filename_tgz}" &
         N_PROC_PARALLEL=$(get_parallel_limit)
         nrwait $N_PROC_PARALLEL
      done < "$EMAILS_FILE"
      wait_all_jobs || end_shell 1
   fi
   end_process "Exporting mailbox"
}

function export_mailbox_user
{
   local email="${1:-}"
   local emails_file="${DIRBACKUP}/emails_${TODAY_LINE}.txt"
   local all_accounts_file="${DIRBACKUP}/accounts_${TODAY_LINE}.txt"

   if [ -z "$email" ]; then
      log_error "Mailbox user is required. Usage: $(basename "$0") --export-mailbox-user user@example.com"
      end_shell 1
   fi

   begin_process "Validating mailbox user"
   write_all_accounts "$all_accounts_file"
   if ! grep -Fxq "$email" "$all_accounts_file" && ! prov -l ga "$email" zimbraAccountStatus >/dev/null 2>&1; then
      log_error "Mailbox user not found: ${email}"
      end_shell 1
   fi

   echo "$email" > "$emails_file"
   log_info "Using mailbox user: ${email}"
   end_process "Validating mailbox user"

   export_mailbox
}

function export_mailbox_list
{
   local source_file="${1:-}"
   local emails_file="${DIRBACKUP}/emails_${TODAY_LINE}.txt"
   local invalid_file="${DIRBACKUP}/invalid_emails_${TODAY_LINE}.txt"
   local all_accounts_file="${DIRBACKUP}/accounts_${TODAY_LINE}.txt"
   local email
   local total_emails

   if [ -z "$source_file" ]; then
      log_error "Mailbox list file is required. Usage: $(basename "$0") --export-mailbox-list emails.txt"
      end_shell 1
   fi

   if [ ! -f "$source_file" ]; then
      log_error "Mailbox list file not found: ${source_file}"
      end_shell 1
   fi

   begin_process "Preparing mailbox list"
   awk '
      {
         sub(/\r$/, "")
         sub(/^[[:space:]]+/, "")
         sub(/[[:space:]]+$/, "")
      }
      $0 != "" && $0 !~ /^#/ && !seen[$0]++
   ' "$source_file" > "$emails_file"

   if [ ! -s "$emails_file" ]; then
      log_error "Mailbox list file has no valid email lines: ${source_file}"
      end_shell 1
   fi

   total_emails=$(count_file_lines "$emails_file")
   log_info "Mailbox list file: ${source_file}"
   log_info "Mailbox users selected: ${total_emails}"
   end_process "Preparing mailbox list"

   begin_process "Validating mailbox list"
   write_all_accounts "$all_accounts_file"
   log_info "Account catalog loaded: ${all_accounts_file}"
   : > "$invalid_file"
   while read -r email; do
      if ! grep -Fxq "$email" "$all_accounts_file" && ! prov -l ga "$email" zimbraAccountStatus >/dev/null 2>&1; then
         log_error "Mailbox user not found: ${email}"
         echo "$email" >> "$invalid_file"
      fi
   done < "$emails_file"

   if [ -s "$invalid_file" ]; then
      log_error "Invalid mailbox users found. Review: ${invalid_file}"
      end_shell 1
   fi

   del_file "$invalid_file"
   end_process "Validating mailbox list"

   export_mailbox
}

function export_dlist
{
   begin_process "Exporting distribution list"
   DLIST_FILE="${DIRBACKUP}/dlist_${TODAY_LINE}.txt"
   log_info "${ZMPROV} gadl > $DLIST_FILE"
   prov gadl > "$DLIST_FILE"
   cat "$DLIST_FILE"

   while read -r listname; do
      if [ -z "$listname" ]; then
         continue
      fi
      log_info "${ZMPROV} gdlm $listname > ${DIRDLIST}/$listname.txt..."
      prov gdlm "$listname" > "${DIRDLIST}/$listname.txt" ;
   done < "$DLIST_FILE"
   end_process "Exporting distribution list"
}

function export_alias
{
   EMAILS_FILE="${DIRBACKUP}/emails_${TODAY_LINE}.txt"
   if [ ! -f "$EMAILS_FILE" ]; then
      # file not exists
      get_list_emails "$EMAILS_FILE"
   fi

   begin_process "Exporting alias"

   log_info "Exporting alias in : ${DIRALIAS}"
   q_emails=$(count_file_lines "$EMAILS_FILE")
   count=0
   while read -r email; do
      if [ -z "$email" ]; then
         continue
      fi
      count=$((count + 1))
      log_info "[$count/$q_emails] ${ZMPROV} ga $email | grep zimbraMailAlias > ${DIRALIAS}/$email.txt..." ;
      prov ga "$email" zimbraMailAlias | grep zimbraMailAlias | awk '{print $2}' > "${DIRALIAS}/$email.txt" || log_info "zimbraMailAlias No ubicado" ;
      if [ ! -s "${DIRALIAS}/$email.txt" ]; then
         del_file "${DIRALIAS}/$email.txt"
      fi
   done < "$EMAILS_FILE"

   q_alias=$(find "$DIRALIAS" -maxdepth 1 -type f | wc -l | awk '{print $1}')
   log_info "Total alias: $q_alias"

   end_process "Exporting alias"
}

function export_calendar_contacts
{
   EMAILS_FILE="${DIRBACKUP}/emails_${TODAY_LINE}.txt"

   if [ ! -f "$EMAILS_FILE" ]; then
      # file not exists
      get_list_emails "$EMAILS_FILE"
   fi

   begin_process "Exporting calendar and contacts"

   log_info "Exporting calendar in : ${DIRCALENDAR}"
   log_info "Exporting contacts in : ${DIRCONTACTS}"

   q_emails=$(count_file_lines "$EMAILS_FILE")
   count=0
   while read -r email; do
      if [ -z "$email" ]; then
         continue
      fi
      count=$((count + 1))
      log_info "[$count/$q_emails] ${ZMMAILBOX} -z -m ${email}.../Calendar/?fmt=tgz" ;
      mailbox -z -m "${email}" -t 0 getRestURL '/Calendar/?fmt=tgz' > "${DIRCALENDAR}/$email.tgz" ;

      log_info "[$count/$q_emails] ${ZMMAILBOX} -z -m ${email}.../Contacts/?fmt=tgz" ;
      mailbox -z -m "${email}" -t 0 getRestURL '/Contacts/?fmt=tgz' > "${DIRCONTACTS}/$email.tgz" ;
      mailbox -z -m "${email}" -t 0 getRestURL '/Emailed Contacts/?fmt=tgz' > "${DIRCONTACTS}/emailed_$email.tgz" ;
      log_info "${email} -- finished " ;
   done < "$EMAILS_FILE"

   end_process "Exporting calendar and contacts"
}

function export_signatures
{
   EMAILS_FILE="${DIRBACKUP}/emails_${TODAY_LINE}.txt"

   if [ ! -f "$EMAILS_FILE" ]; then
      # file not exists
      get_list_emails "$EMAILS_FILE"
   fi

   begin_process "Exporting signatures"

   log_info "Exporting signatures in : ${DIRSIGNATURE}"

   q_emails=$(count_file_lines "$EMAILS_FILE")
   count=0
   while read -r email; do
      if [ -z "$email" ]; then
         continue
      fi
      count=$((count + 1))

      log_info "[$count/$q_emails] ${ZMPROV} ga $email zimbraSignatureName > ${DIRSIGNATURE}/${email}_name.txt..." ;
      prov ga "$email" zimbraSignatureName | grep zimbraSignatureName | awk '{print $2}' > "${DIRSIGNATURE}/${email}_name.txt" || true

      if [ ! -s "${DIRSIGNATURE}/${email}_name.txt" ]; then
         log_info "Signature for ${email} not found."
         del_file "${DIRSIGNATURE}/${email}_name.txt"
         log_info "${email} -- finished " ;
         continue;
      fi

      log_info "[$count/$q_emails] ${ZMPROV} ga $email zimbraPrefMailSignatureHTML > ${DIRSIGNATURE}/${email}_html.txt..." ;
      prov ga "$email" zimbraPrefMailSignatureHTML | awk '/^zimbraPrefMailSignatureHTML:/ {flag=1} flag {print}' | sed 's/^zimbraPrefMailSignatureHTML: //' > "${DIRSIGNATURE}/${email}_html.txt"
      log_info "${email} -- finished " ;
   done < "$EMAILS_FILE"

   end_process "Exporting signatures"
}

function export_rules
{
   EMAILS_FILE="${DIRBACKUP}/emails_${TODAY_LINE}.txt"

   if [ ! -f "$EMAILS_FILE" ]; then
      # file not exists
      get_list_emails "$EMAILS_FILE"
   fi

   begin_process "Exporting rules"

   log_info "Exporting rules in : ${DIRRULES}"

   q_emails=$(count_file_lines "$EMAILS_FILE")
   count=0
   while read -r email; do
      if [ -z "$email" ]; then
         continue
      fi
      count=$((count + 1))
      
      log_info "[$count/$q_emails] ${ZMPROV} ga $email zimbraMailSieveScript > ${DIRRULES}/${email}_rules.txt..." ;
      prov ga "$email" zimbraMailSieveScript > "${DIRRULES}/${email}_rules.txt"

      sed -i -e "1d" "${DIRRULES}/${email}_rules.txt"
      sed -i -e 's/zimbraMailSieveScript: //g' "${DIRRULES}/${email}_rules.txt"
      sed -i '/^$/d' "${DIRRULES}/${email}_rules.txt"

      if [ ! -s "${DIRRULES}/${email}_rules.txt" ]; then
         log_info "Rules for ${email} not found."
         del_file "${DIRRULES}/${email}_rules.txt";
         log_info "${email} -- finished " ;
         continue;
      fi

      grep 'fileinto' "${DIRRULES}/${email}_rules.txt" | sed -n 's/.*fileinto "\([^"]*\)".*/\1/p' | sort -u > "${DIRRULES}/${email}_folders.txt" || true
      if [ ! -s "${DIRRULES}/${email}_folders.txt" ]; then
         log_info "Folder Rules for ${email} not found."
         del_file "${DIRRULES}/${email}_folders.txt";
      fi
      if [ -f "${DIRRULES}/${email}_folders.txt" ]; then
         q_folder=$(count_file_lines "${DIRRULES}/${email}_folders.txt")
      else
         q_folder=0
      fi
      log_info "${q_folder} folders found for ${email}"
      log_info "${email} -- finished ";

   done < "$EMAILS_FILE"

   end_process "Exporting rules"
}
