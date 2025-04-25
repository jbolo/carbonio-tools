#!/bin/bash
################################################################################
#                    Migration Script Zimbra -> Carbonio                       #
#                                                                              #
# Script to mail migration - Zimbra to Carbonio.                               #
#                                                                              #
# Change History                                                               #
# 02/10/2023   Jonathan Bolo   Initial Version.                                #
#                                                                              #
################################################################################

#################################
# Constants / global variables
#################################
PID=$$
DIRAPP=`readlink -f $0 | xargs dirname`
ENV_FILE="$DIRAPP/.varset"
if [ -z "$ENV_FILE" ] ; then
   echo ".varset file not found\n"
   exit 1
fi
. $DIRAPP/.varset

DIRLOG="${DIRAPP}/log"
TODAY_LINE=`date '+%Y%m%d%H%M%S'`
LOGFILE="${DIRLOG}/mail_migrate_${TODAY_LINE}.log"

if [ ! -d $DIRLOG ] ; then
   mkdir -p $DIRLOG
fi

. $DIRAPP/functions.sh

#################################
# Main
#################################
function set_context
{
   export TYPEB="full"
   export DIRBACKUP="${DIRAPP}/backup_${TYPEB}_${TODAY_LINE}"
   export DIRMAILBOX="${DIRBACKUP}/mailbox_${TODAY_LINE}"
   if [[ "$1" == *"incremental"* ]] ; then
      export TYPEB="incremental"
      export DIRBACKUP="${DIRAPP}/backup_${TYPEB}"
      export DIRMAILBOX="${DIRBACKUP}/mailbox"
   fi

   if [ -d $PATH_BIN_ZIMBRA ] ; then
      export CONTEXT="ZIMBRA"
      export USER_APP=$USER_ZIMBRA
      export PATH_BIN_APP=$PATH_BIN_ZIMBRA
      export ZMPROV="$PATH_BIN_ZIMBRA/zmprov"
      export ZMCONTROL="$PATH_BIN_ZIMBRA/zmcontrol"
      export ZMMAILBOX="$PATH_BIN_ZIMBRA/zmmailbox"

   elif [ -d $PATH_BIN_CARBONIO ]; then
      export CONTEXT="CARBONIO"
      export USER_APP=$USER_CARBONIO
      export PATH_BIN_APP=$PATH_BIN_CARBONIO
      export ZMPROV="$PATH_BIN_CARBONIO/carbonio prov"
      export ZMCONTROL="$PATH_BIN_CARBONIO/zmcontrol"
      export ZMMAILBOX="$PATH_BIN_CARBONIO/zmmailbox"
   else
      log_error "Context type not identified."
      end_shell 1
   fi

   validate_user $USER_APP

   if [[ "$1" == *"import"* ]] ; then
      validate_remote_files
      return 0
   fi

   export DIRUSERPASS="${DIRBACKUP}/userpass_${TODAY_LINE}"
   export DIRUSERDATA="${DIRBACKUP}/userdata_${TODAY_LINE}"
   export DIRDLIST="${DIRBACKUP}/dlist_${TODAY_LINE}"
   export DIRALIAS="${DIRBACKUP}/alias_${TODAY_LINE}"
   export DIRCALENDAR="${DIRBACKUP}/calendar_${TODAY_LINE}"
   export DIRCONTACTS="${DIRBACKUP}/contacts_${TODAY_LINE}"

   # CREATE DIRECTORIES
   if [ ! -d $DIRBACKUP ] ; then
      mkdir -p $DIRBACKUP
   fi

   if [ ! -d $DIRUSERPASS ] ; then
      mkdir -p $DIRUSERPASS
   fi

   if [ ! -d $DIRUSERDATA ] ; then
      mkdir -p $DIRUSERDATA
   fi

   if [ ! -d $DIRMAILBOX ] ; then
      mkdir -p $DIRMAILBOX
   fi

   if [ ! -d $DIRDLIST ] ; then
      mkdir -p $DIRDLIST
   fi

   if [ ! -d $DIRALIAS ] ; then
      mkdir -p $DIRALIAS
   fi
}

function validate_user
{
   user=`whoami`
   if [[ ! "$user" == "${USER_APP}" ]]; then
      log_error "The actually user is not: ${USER_APP}"
      end_shell 1
   fi
}

function count_mailbox_user
{
   EMAILS_FILE="$1"
   REPORT_FILE="$2"

   if [ ! -f "$EMAILS_FILE" ]; then
      # file not exists
      EMAILS_FILE="${DIRBACKUP}/emails_${TODAY_LINE}.txt"
      get_list_emails "$EMAILS_FILE"
   fi

   begin_process "Getting mailbox user details"
   for j in `cat ${EMAILS_FILE}`; do
      log_info "Analizing account: ${j}"
      total=0;

      for i in `${ZMMAILBOX} -z -m "$j" gaf | awk '{print $4}' | egrep -o "[0-9]+"`; do
         total=$((total + i ));
      done;

      size=`${ZMMAILBOX} -z -m "$j" gms`;
      log_info "Report:Email:${j}|Q=${total}|Size=${size}";

      if [ ! -z "$REPORT_FILE" ]; then
         LINE_RESUME="${j}|${total}|${size}"
         echo $LINE_RESUME >> $REPORT_FILE
      fi
   done

   end_process "Getting mailbox user details"
}

function get_status_server
{
   begin_process "Getting status"
   version=`${ZMCONTROL} -v`
   log_info "${version}"

   status=`${ZMCONTROL} status`
   log_info "${status}"
   end_process "Getting status"
}

function get_list_emails
{
   EMAILS_FILE="$1"
   if [ -z "$1" ]; then
      echo "Filename empty"
      exit 1
   fi

   begin_process "Getting emails"
   log_info "${ZMPROV} -l gaa ${DOMAIN} > ${EMAILS_FILE}"
   ${ZMPROV} -l gaa ${DOMAIN}  | egrep -v "^(spam|ham)" > "${EMAILS_FILE}"
   cat "${EMAILS_FILE}"
   q_emails=`wc -l ${EMAILS_FILE} |awk '{print $1}'`
   log_info "Total emails: $q_emails"
   end_process "Getting emails"
}

function export_account
{
   cd ${DIRBACKUP}

   begin_process "Getting domains"
   log_info "${ZMPROV} -l gad > domains_${TODAY_LINE}.txt"
   ${ZMPROV} -l gad > "${DIRBACKUP}/domains_${TODAY_LINE}.txt"

   if [[ ! "${DOMAIN}" == "" ]]; then
      if [ ! `grep -c "${DOMAIN}" "${DIRBACKUP}/domains_${TODAY_LINE}.txt"` -eq 1 ]; then
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
   for i in `cat ${EMAILS_FILE}`; do
      let count=$count+1
      log_info "[$count/$q_emails] ${ZMPROV} -l ga ${i} userPassword..."
      ${ZMPROV}  -l ga ${i} userPassword | grep userPassword: | awk '{print $2}' > ${DIRUSERPASS}/${i}.shadow;
   done

   end_process "Exporting users and password"

   #################################################

   begin_process "Exporting usersdata"
   log_info "Exporting user data in: ${DIRUSERDATA}"
   count=0
   for i in `cat ${EMAILS_FILE}`; do
      let count=$count+1
      log_info "[$count/$q_emails] ${ZMPROV} ga ${i}..."
      ${ZMPROV} ga ${i} | grep -E "^(cn:|sn:|displayName:|givenName:|zimbraPrefIdentityName:)" > ${DIRUSERDATA}/${i}.txt
   done

   end_process "Exporting usersdata"
}

function export_mailbox
{
   EMAILS_FILE="${DIRBACKUP}/emails_${TODAY_LINE}.txt"
   REPORT_FILE="${DIRBACKUP}/report_${TODAY_LINE}.txt"
   if [ ! -f $EMAILS_FILE ]; then
      # file not exists
      get_list_emails $EMAILS_FILE
   fi
   count_mailbox_user "$EMAILS_FILE" "$REPORT_FILE"

   begin_process "Exporting mailbox"

   log_info "Exporting mailbox in : ${DIRMAILBOX}"
   if [ "$TYPEB" == "full" ] ; then
      log_info "Execution of full backup"
      q_emails=`wc -l ${EMAILS_FILE} |awk '{print $1}'`
      count=0
      for email in `cat ${EMAILS_FILE}`; do
         let count=$count+1
         log_info "[$count/$q_emails] ${ZMMAILBOX} -z -m ${email} -t 0 getRestURL '/?fmt=tgz' > ${DIRMAILBOX}/${email}.tgz" ;
         ${ZMMAILBOX} -z -m ${email} -t 0 getRestURL '/?fmt=tgz' > ${DIRMAILBOX}/${email}.tgz &
         N_PROC_PARALLEL=`awk -F"=" '$1=="N_PROC_PARALLEL" {print $2}' ${ENV_FILE} |cut -d";" -f1`
         nrwait $N_PROC_PARALLEL
      done
   fi
   if [ "$TYPEB" == "incremental" ] ; then
      log_info "Execution of incremental backup"
      day_after=`date -d '-48 hours' +"%m/%d/%Y"`
          day_before=`date +"%m/%d/%Y"`
      filename_tgz=`date -d '-24 hours' +"%Y-%m-%d.tgz"`
      query="&query=after:\"${day_after}\" and before:\"${day_before}\""
      log_info "Incremental for day: ${day_bk}"

      q_emails=`wc -l ${EMAILS_FILE} |awk '{print $1}'`
      count=0
      for email in `cat ${EMAILS_FILE}`; do
         mkdir -p ${DIRMAILBOX}/$email/
         let count=$count+1
         log_info "[$count/$q_emails] ${ZMMAILBOX} -z -m ${email} -t 0 getRestURL '/?fmt=tgz${query}' > ${DIRMAILBOX}/${email}/${filename_tgz}" ;
         ${ZMMAILBOX} -z -m ${email} -t 0 getRestURL "/?fmt=tgz${query}" > ${DIRMAILBOX}/${email}/${filename_tgz} &
         N_PROC_PARALLEL=`awk -F"=" '$1=="N_PROC_PARALLEL" {print $2}' ${ENV_FILE} |cut -d";" -f1`
         nrwait $N_PROC_PARALLEL
      done
   fi
   end_process "Exporting mailbox"
}

function export_dlist
{
   begin_process "Exporting distribution list"
   DLIST_FILE="${DIRBACKUP}/dlist_${TODAY_LINE}.txt"
   log_info "${ZMPROV} gadl > $DLIST_FILE"
   ${ZMPROV} gadl > $DLIST_FILE
   cat $DLIST_FILE

   for listname in `cat ${DLIST_FILE}`; do
      log_info "${ZMPROV} gdlm $listname > ${DIRDLIST}/$listname.txt..."
      ${ZMPROV} gdlm $listname > ${DIRDLIST}/$listname.txt ;
   done
   end_process "Exporting distribution list"
}

function export_alias
{
   EMAILS_FILE="${DIRBACKUP}/emails_${TODAY_LINE}.txt"
   if [ ! -f $EMAILS_FILE ]; then
      # file not exists
      get_list_emails $EMAILS_FILE
   fi

   begin_process "Exporting alias"

   log_info "Exporting alias in : ${DIRALIAS}"
   q_emails=`wc -l ${EMAILS_FILE} |awk '{print $1}'`
   count=0
   for email in `cat ${EMAILS_FILE}`; do
      let count=$count+1
      log_info "[$count/$q_emails] ${ZMPROV} ga $email | grep zimbraMailAlias > ${DIRALIAS}/$email.txt..." ;
      ${ZMPROV} ga $email | grep zimbraMailAlias > ${DIRALIAS}/$email.txt || log_info "zimbraMailAlias No ubicado" ;
      if [ ! -s "${DIRALIAS}/$email.txt" ]; then
         del_file "${DIRALIAS}/$email.txt"
      fi
   done

   q_alias=`ls ${DIRALIAS} | wc -l | awk '{print $1}'`
   log_info "Total alias: $q_alias"

   end_process "Exporting alias"
}

function export_calendar_contacts
{
   EMAILS_FILE="${DIRBACKUP}/emails_${TODAY_LINE}.txt"

   if [ ! -f $EMAILS_FILE ]; then
      # file not exists
      get_list_emails $EMAILS_FILE
   fi

   begin_process "Exporting calendar and contacts"

   log_info "Exporting calendar in : ${DIRCALENDAR}"
   log_info "Exporting contacts in : ${DIRCONTACTS}"

   q_emails=`wc -l ${EMAILS_FILE} |awk '{print $1}'`
   count=0
   for email in `cat ${EMAILS_FILE}`; do
      let count=$count+1
      log_info "[$count/$q_emails] ${ZMMAILBOX} -z -m ${email}.../Calendar/?fmt=tgz" ;
      ${ZMMAILBOX} -z -m ${email} -t 0 getRestURL '/Calendar/?fmt=tgz' > ${DIRCALENDAR}/$email.tgz ;

      log_info "[$count/$q_emails] ${ZMMAILBOX} -z -m ${email}.../Contacts/?fmt=tgz" ;
      ${ZMMAILBOX} -z -m ${email} -t 0 getRestURL '/Contacts/?fmt=tgz' > ${DIRCONTACTS}/$email.tgz ;
      ${ZMMAILBOX} -z -m ${email} -t 0 getRestURL '/Emailed Contacts/?fmt=tgz' > ${DIRCONTACTS}/emailed_$email.tgz ;
      log_info "${email} -- finished " ;
   done

   end_process "Exporting calendar and contacts"
}

function transfer_data
{
   if [ "$TRANSFER_ENABLED" -ne "1" ] ; then
      return 0
   fi
   begin_process "Transfering backup to remote server"
   if [ "$1" = "" ] ; then
      DIR_BACKUP_WORK=`ls -ltr ${DIRAPP}|grep "zmigrate_"|awk '{print $9}'|tail -2|head -1`
   else
      DIR_BACKUP_WORK=$1
   fi
   log_info "sshpass -p \"${SSHPASSWORD}\" rsync -avp ${DIR_BACKUP_WORK} ${SSHREMOTE}:${SSHDIR} --log-file=${LOGFILE}"

   sshpass -p ${SSHPASSWORD} rsync -avp ${DIR_BACKUP_WORK} ${SSHREMOTE}:${SSHDIR} --log-file=${LOGFILE}

   if [ $MAILX_ENABLED -eq 1 ] ; then
      log_info "Enviando Correo de confirmacion" ;
      TODAY_PROC=`date '+%Y/%m/%d'`
      echo "Se termino de enviar con exito el backup a SFTP." | /usr/bin/mailx -r "$MAILX_FROM" -s "$MAILX_SUBJECT $TODAY_PROC - OK" $MAILX_TO
   fi
   end_process "Transfering backup to remote server"
}

function validate_remote_files
{
   if [ ! -d "${DIRREMOTE}" ]; then
      echo "Backup Directory not exists."
      end_shell 1
   fi

   export REMOTE_DOMAINS_FILE=`ls ${DIRREMOTE}/domains_*.txt | sort | tail -1`
   export REMOTE_EMAILS_FILE=`ls ${DIRREMOTE}/emails_*.txt | sort | tail -1`

   if [ ! -f "${REMOTE_DOMAINS_FILE}" ]; then
      echo "Domain file not exists."
      end_shell 1
   fi
   if [ ! -f "${REMOTE_EMAILS_FILE}" ]; then
      echo "Emails file not exists."
      end_shell 1
   fi

   DATE_PROC=`echo $REMOTE_EMAILS_FILE|awk -F"_" '{print $NF}'|cut -d"." -f1`

   # DIRREMOTE
   export DIRREMOTEUSERPASS=`ls -d ${DIRREMOTE}/userpass_${DATE_PROC} | sort | tail -1`
   export DIRREMOTEUSERDATA=`ls -d ${DIRREMOTE}/userdata_${DATE_PROC} | sort | tail -1`
   export DIRREMOTEMAILBOX=`ls -d ${DIRREMOTE}/mailbox_${DATE_PROC} | sort | tail -1`

   export DLIST_FILE=`ls ${DIRREMOTE}/dlist_${DATE_PROC}.txt | sort | tail -1`
   export DIRREMOTEDLIST=`ls -d ${DIRREMOTE}/dlist_${DATE_PROC} | sort | tail -1`
   export DIRREMOTEALIAS=`ls -d ${DIRREMOTE}/alias_${DATE_PROC} | sort | tail -1`
   export DIRREMOTECALENDAR=`ls -d ${DIRREMOTE}/calendar_${DATE_PROC} | sort | tail -1`
   export DIRREMOTECONTACTS=`ls -d ${DIRREMOTE}/contacts_${DATE_PROC} | sort | tail -1`

}

function import_account
{
   validate_remote_files

   #################################################

   begin_process "Provisioning domains"
   log_info "List of Domains:"
   log_info "${ZMPROV} -l gad"
   list_domain=`${ZMPROV} -l gad`
   log_info "${list_domain}"

   for i in `cat ${REMOTE_DOMAINS_FILE} `; do
      log_info "Domain: ${i}"
      if [[ $(echo "${list_domain}" | grep "$i") ]] ; then
         log_info "Domain exists..."
         ${ZMPROV} md $i zimbraPublicServiceProtocol https
         ${ZMPROV} md $i zimbraPublicServicePort 443
         ${ZMPROV} md $i zimbraPrefTimeZoneId "America/Bogota"
         continue
      fi
      provi=`${ZMPROV} cd $i zimbraAuthMech zimbra`
      log_info "${provi}"

      ${ZMPROV} md $i zimbraPublicServiceProtocol https
      ${ZMPROV} md $i zimbraPublicServicePort 443
      ${ZMPROV} md $i zimbraPrefTimeZoneId "America/Bogota"
   done

   log_info "List of Domains:"
   log_info "${ZMPROV} -l gad"
   list_domain=`${ZMPROV} -l gad`
   log_info "${list_domain}"

   end_process "Provisioning domains"

   #################################################

   begin_process "Provisiong accounts"
   q_emails=`wc -l ${REMOTE_EMAILS_FILE} |awk '{print $1}'`
   count=0
   for i in `cat ${REMOTE_EMAILS_FILE}`
   do
      let count=$count+1
      log_info "[$count/$q_emails] Account ${i}"
      cn=`grep cn: ${DIRREMOTEUSERDATA}/$i.txt | cut -d ":" -f2`
      sn=`grep sn: ${DIRREMOTEUSERDATA}/$i.txt | cut -d ":" -f2`
      givenname=`grep givenName: ${DIRREMOTEUSERDATA}/$i.txt | cut -d ":" -f2`
      displayname=`grep displayName: ${DIRREMOTEUSERDATA}/$i.txt | cut -d ":" -f2`
      zimbraprefidentityname=`grep zimbraPrefIdentityName: ${DIRREMOTEUSERDATA}/$i.txt | cut -d ":" -f2`
      shadowpass=`cat ${DIRREMOTEUSERPASS}/$i.shadow`

      log_info "Creating account"
      ${ZMPROV} ca $i CHANGEme sn "$sn" cn "$cn" displayName "$displayname" givenName "$givenname" zimbraPrefIdentityName "$zimbraprefidentityname"|| log_error "Error creating account $i"; continue

      log_info "Updating account password"zimbraprefidentityname
      ${ZMPROV} ma $i userPassword "$shadowpass"
   done

   log_info "List of Accounts:"
   list_acc=`${ZMPROV} -l gaa -v ${DOMAIN} | grep -e displayName`
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

   log_info "Incrementing value timeout during the migration period"
   zmlocalconfig -e socket_so_timeout=7200000

   zmprov mcf zimbraReverseProxyUpstreamReadTimeout 120m
   zmprov mcf zimbraReverseProxySSLSessionTimeout 120m
   zmprov mcf zimbraReverseProxyUpstreamSendTimeout 1200m

   log_info "Incrementing value attachment limits=50MB"
   zmprov mcf zimbraMtaMaxMessageSize 51200000
   zmprov mcf zimbraFileUploadMaxSize 52428800
   zmprov mcf zimbraMailContentMaxSize 51200000

   zmcontrol restart
   sleep 30

   if [[ "${DIRREMOTEMAILBOX}" != *"incremental"* ]] ; then
      q_emails=`wc -l ${REMOTE_EMAILS_FILE} |awk '{print $1}'`
      count=0
      for email in `cat ${REMOTE_EMAILS_FILE}`; do
         let count=$count+1
         log_info "[$count/$q_emails] zmmailbox -z -m ${email} -t 0 postRestURL '/?fmt=tgz&resolve=skip' ${DIRREMOTEMAILBOX}/$email.tgz"
         zmmailbox -z -m ${email} -t 0 postRestURL "/?fmt=tgz&resolve=skip" ${DIRREMOTEMAILBOX}/$email.tgz &
         # curl --max-time 1800 -k -H "Transfer-Encoding: chunked" -u zextras:${ZEXTRAS_PASS} -p -T ${DIRREMOTEMAILBOX}/$email.tgz "https://localhost:6071/service/home/$email/?fmt=tgz&resolve=skip" &
         N_PROC_PARALLEL=`awk -F"=" '$1=="N_PROC_PARALLEL" {print $2}' ${ENV_FILE} |cut -d";" -f1`
         nrwait $N_PROC_PARALLEL
      done
   fi

   if [[ "${DIRREMOTEMAILBOX}" == *"incremental"* ]] ; then
      q_emails=`wc -l ${REMOTE_EMAILS_FILE} |awk '{print $1}'`
      count=0

      for email in `cat ${REMOTE_EMAILS_FILE}`; do
         let count=$count+1
         log_info "[$count/$q_emails] zmmailbox -z -m ${email}..."

         for bk_file in `ls ${DIRREMOTEMAILBOX}/${email}/*.tgz | sort`; do
            log_info "Processing bk: ${email} | ${bk_file}"
                        file_size=$(wc -c "${bk_file}" | cut -d' ' -f1)
                        if [ "$file_size" == "0" ]; then
                           log_info "File empty: ${bk_file}"
                           continue
                        fi
                        log_info "zmmailbox -z -m ${email} -t 0 postRestURL '/?fmt=tgz&resolve=replace' ${bk_file}"
            zmmailbox -z -m ${email} -t 0 postRestURL "/?fmt=tgz&resolve=replace" ${bk_file}
            # curl --max-time 1800 -k -H "Transfer-Encoding: chunked" -u zextras:${ZEXTRAS_PASS} -p -T ${DIRREMOTEMAILBOX}/${email}/${bk_file} "https://localhost:6071/service/home/$email/?fmt=tgz&resolve=replace" &
            # N_PROC_PARALLEL=`awk -F"=" '$1=="N_PROC_PARALLEL" {print $2}' ${ENV_FILE} |cut -d";" -f1`
            # nrwait $N_PROC_PARALLEL
         done
      done
   fi

   log_info "Reseting value timeout during the migration period"
   zmlocalconfig -e socket_so_timeout=3000000

   zmprov mcf zimbraReverseProxyUpstreamReadTimeout 60s
   zmprov mcf zimbraReverseProxySSLSessionTimeout 10m
   zmprov mcf zimbraReverseProxyUpstreamSendTimeout 60s

   log_info "Reseting value attachment limits=25MB"
   zmprov mcf zimbraMtaMaxMessageSize 25600000
   zmprov mcf zimbraFileUploadMaxSize 26214400
   zmprov mcf zimbraMailContentMaxSize 25600000

   zmcontrol restart

   end_process "Importing mailbox"
}

function import_calendar_contacts
{
   validate_remote_files

   #################################################

   begin_process "Importing calendar and contacts"

   q_emails=`wc -l ${REMOTE_EMAILS_FILE} |awk '{print $1}'`
   count=0
   for email in `cat ${REMOTE_EMAILS_FILE}`; do
      let count=$count+1
      log_info "[$count/$q_emails] zmmailbox -z -m ${email}...Calendar"
      zmmailbox -z -m ${email} -t 0 postRestURL "/?fmt=tgz&resolve=skip" ${DIRREMOTECALENDAR}/$email.tgz ;

      log_info "[$count/$q_emails] zmmailbox -z -m ${email}...Contacts"
      zmmailbox -z -m ${email} -t 0 postRestURL "/?fmt=tgz&resolve=skip" ${DIRREMOTECONTACTS}/$email.tgz ;

      log_info "[$count/$q_emails] zmmailbox -z -m ${email}...Emailed Contacts"
      zmmailbox -z -m ${email} -t 0 postRestURL "/?fmt=tgz&resolve=skip" ${DIRREMOTECONTACTS}/emailed_$email.tgz ;

      log_info "${email} -- finished " ;
   done

   end_process "Importing mailbox"
}

function import_dlist
{
   validate_remote_files

   #################################################

   begin_process "Importing distribution list"

   if [ ! -f $DLIST_FILE ]; then
      log_info "Distribution List file not found"
      return 0
   fi

   q_dlist=`wc -l ${DLIST_FILE} | awk '{print $1}'`
   log_info "Total dlist: $q_dlist"

   for listname in `cat ${DLIST_FILE}`; do
      log_info "Importing dlist: $listname"
      log_info "${ZMPROV} cdl $listname..."
      ${ZMPROV} cdl $listname

      for email in `grep -v '#' ${DIRREMOTEDLIST}/${listname}.txt | grep '@'`; do
         log_info "${ZMPROV} adlm $listname $email"
         ${ZMPROV} adlm $listname $email
      done
   done
   end_process "Importing distribution list"
}

function import_alias
{
   validate_remote_files

   #################################################

   begin_process "Importing alias"

   q_alias=`ls ${DIRREMOTEALIAS} | wc -l | awk '{print $1}'`
   log_info "Total alias: $q_alias"

   if [ $q_alias -eq 0 ]; then
      log_info "Alias files not found."
      return 0
   fi

   for email_filename in `ls ${DIRREMOTEALIAS}`; do
      email=${email_filename:0:-4}
      log_info "Creating alias to: ${email}"
      for alias in `grep '@' ${DIRREMOTEALIAS}/${email_filename}`; do
         log_info "${ZMPROV} aaa $email $alias ..."
         ${ZMPROV} aaa $email $alias
      done
   done
   end_process "Importing alias"
}

function delete_old_export
{
   if [ "$DELETE_OLD_EXPORT_ENABLED" -ne "1" ] ; then
      return 0
   fi

   begin_process "Deleting old exports"
   log_info "find ${DIRAPP} -maxdepth 1 -name "zmigrate_" -type d -mtime +${DELETE_OLD_EXPORT_DAYS}"
   find ${DIRAPP} -maxdepth 1 -name "zmigrate_*" -type d -mtime +${DELETE_OLD_EXPORT_DAYS} -print >> $LOGFILE
   find ${DIRAPP} -maxdepth 1 -name "zmigrate_*" -type d -mtime +${DELETE_OLD_EXPORT_DAYS} -exec rm -rf "{}" \; >> $LOGFILE
   end_process "Deleting old exports"
}
options=("--export-incremental" "--export" "--export-account" "--export-mailbox" "--export-dlist" "--export-alias" "--import-incremental" "--import" "--import-account" "--import-mailbox" "--import-dlist" "--import-alias" "--transfer" "--status")

function usage
{
   echo "Script to mail migration - Zimbra&Carbonio."
   echo
   echo "Usage: mail_migrate.sh [option]"
   echo "Options:"
   for i in ${options[@]}
   do
      echo "   "$i
   done
   echo
}

if [ -z "$1" ]; then
   usage
   exit
fi

if [[ ! $(echo "${options[@]}" | grep -- "$1") ]]; then
   echo "Invalid option: "$1
   usage
   exit 1
fi

case "$1" in
   "--export-incremental") # Export mailbox incremental
      set_context $1
      begin_shell
      get_status_server
      export_account
      export_dlist
      export_alias
      export_mailbox
      transfer_data ${DIRBACKUP}
      end_shell;;
   "--export") # Export full
      set_context $1
      begin_shell
      delete_old_export
      get_status_server
      export_account
      export_dlist
      export_alias
      export_mailbox
      transfer_data ${DIRBACKUP}
      end_shell;;
   "--export-account") # Export account
      set_context $1
      begin_shell
      delete_old_export
      export_account
      end_shell;;
   "--export-mailbox") # Export mailbox
      set_context $1
      begin_shell
      delete_old_export
      export_mailbox
      end_shell;;
   "--export-dlist") # Export distribution list
      set_context $1
      begin_shell
      delete_old_export
      export_dlist
      end_shell;;
   "--export-alias") # Export alias
      set_context $1
      begin_shell
      delete_old_export
      export_alias
      end_shell;;
   "--export-calendar-contacts") # Export Calendar and Contacts
      set_context $1
      begin_shell
      delete_old_export
      export_calendar_contacts
      end_shell;;
   "--import-incremental") # Import all and incremental mailbox
      set_context $1
      begin_shell
      get_status_server
      import_mailbox
      end_shell;;
   "--import") # Import all
      set_context $1
      begin_shell
      get_status_server
      import_account
      import_dlist
      import_alias
      import_mailbox
      end_shell;;
   "--import-account") # Import account
      set_context $1
      begin_shell
      import_account
      end_shell;;
   "--import-mailbox") # Import mailbox
      set_context $1
      begin_shell
      import_mailbox
      end_shell;;
   "--import-dlist") # Import distribution list
      set_context $1
      begin_shell
      import_dlist
      end_shell;;
   "--import-alias") # Import alias
      set_context
      begin_shell
      import_alias
      end_shell;;
   "--import-calendar-contacts") # Import Calendar and Contacts
      set_context $1
      begin_shell
      import_calendar_contacts
      end_shell;;
   "--transfer") # Transfer data by rsync
      set_context $1
      begin_shell
      transfer_data
      end_shell;;
   "--status") # Status
      set_context $1
      get_status_server
      count_mailbox_user
      end_shell;;
   *) # Invalid option
      echo "Invalid option: "$1
      usage
      exit 1
      ;;
esac