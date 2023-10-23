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
LOGFILE="${DIRLOG}/migracion_${TODAY_LINE}.log"
LOGLEVEL="INFO"

# One Domain to work(optional)
DOMAIN=""

ZIMBRA_USER="zimbra"
DIRBACKUP="${DIRAPP}/zmigrate_${TODAY_LINE}"
DIRUSERPASS="${DIRBACKUP}/userpass"
DIRUSERDATA="${DIRBACKUP}/userdata"
DIRMAILBOX="${DIRBACKUP}/mailbox"

ZEXTRAS_USER="zextras"
SSHDIR="/home/sftp_dir"
# DIRREMOTE is
DIRREMOTEUSERPASS="${DIRREMOTE}/userpass"
DIRREMOTEUSERDATA="${DIRREMOTE}/userdata"
DIRREMOTEMAILBOX="${DIRREMOTE}/mailbox"

#################################
# Functions
#################################

# Logging functions
function log_output {
   fecha_ahora=`date "+%Y/%m/%d %H:%M:%S"`
   echo "${fecha_ahora} $1"
   echo "${fecha_ahora} $1" >> $LOGFILE
}

function log_debug {
   if [[ "$LOGLEVEL" =~ ^(DEBUG)$ ]]; then
      log_output "DEBUG $1"
   fi
}

function log_info {
   if [[ "$LOGLEVEL" =~ ^(DEBUG|INFO)$ ]]; then
      log_output "INFO $1"
   fi
}

function log_warn {
   if [[ "$LOGLEVEL" =~ ^(DEBUG|INFO|WARN)$ ]]; then
      log_output "WARN $1"
   fi
}

function log_error {
   if [[ "$LOGLEVEL" =~ ^(DEBUG|INFO|WARN|ERROR)$ ]]; then
      log_output "ERROR $1"
   fi
}

function begin_process()
{
   log_info ""
   log_info "################# $1 ###################"
}

function end_shell()
{
   last_date=`date +"%Y%m%d%H%M%S"`
   log_info "End Process .. $last_date"
   exit $1
}

function del_file()
{
   file_name=$1
   if [ -s $file_name ] || [ ! -z $file_name ] || [ -f $file_name ] ; then
      rm -f $file_name
   fi
}

function notify()
{
   if [ $TELEGRAM_ENABLED -eq 1 ] ; then
      message=$1
      echo "{\"chat_id\": "${TELEGRAM_CHAT_ID}", \"text\": \""${PROCESS_NAME}":"${PID}"|"${message}"\"}" > $DIRLOG/not.txt
      curl -X POST \
           -H 'Content-Type: application/json' \
           -d @${DIRLOG}/not.txt \
           https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage
      del_file $DIRLOG/not.txt
   fi
}

function usage()
{
   echo "Script to mail migration - Zimbra to Carbonio."
   echo
   echo "Usage: mail_migrate.sh [-e|i|h]"
   echo "options:"
   echo "e     Export mailbox Zimbra."
   echo "i     Import mailboz Carbonio."
   echo
   exit 0
}
#################################
# Main
#################################
function validate_zextras_user()
{
   user=`whoami`
   if [[ ! "$user" == "${ZEXTRAS_USER}" ]]; then
      log_error "The actually user is not zextras: ${user}"
      end_shell 1
   fi
}

function validate_zimbra_user()
{
   user=`whoami`
   if [[ ! "$user" == "${ZIMBRA_USER}" ]]; then
      log_error "The actually user is not zimbra: ${user}"
      end_shell 1
   fi
}

function count_mailbox_user()
{
   begin_process "Getting mailbox user details"
   for j in `cat ${DIRBACKUP}/emails.txt | egrep -v "^(spam|ham)"`; do
      log_info "Analizing account: ${j}"
      total=0;

      for i in $( zmmailbox -z -m "$j" gaf | awk '{print $4}' | egrep -o "[0-9]+" ); do
         total=$((total + i ));
      done;
      log_info "Total Q    for ${j} = ${total}";

      size=`zmmailbox -z -m "$j" gms`;
      log_info "Total size for ${j} = ${size}";
   done
}

function count_mailbox_usercarbonio()
{
   for j in `cat ${DIRREMOTE}/emails.txt | egrep -v "^(spam|ham)"`; do
      log_info "Analizing account: ${j}"
      total=0;

      for i in $( zmmailbox -z -m "$j" gaf | awk '{print $4}' | egrep -o "[0-9]+" ); do
         total=$((total + i ));
      done;
      log_info "Total Q    for ${j} = ${total}";

      size=`zmmailbox -z -m "$j" gms`;
      log_info "Total size for ${j} = ${size}";
   done
}

function export_account()
{
   notify "Export account - Started"
   mkdir -p "${DIRLOG}"
   validate_zimbra_user
   begin_process "Starting process of account export"

   version=`zmcontrol -v`
   log_info "${version}"

   status=`zmcontrol status`
   log_info "${status}"

   log_info "Creating backup directory: ${DIRBACKUP}"
   mkdir -p ${DIRBACKUP}
   cd ${DIRBACKUP}

   begin_process "Getting domains"
   log_info "zmprov -l gad > domains.txt"
   zmprov -l gad > "${DIRBACKUP}/domains.txt"

   if [[ ! "${DOMAIN}" == "" ]]; then
      if [ ! $(grep -c "${DOMAIN}" "${DIRBACKUP}/domains.txt") -eq 1 ]; then
         log_error "Domain ${DOMAIN} not exist."
         exit 1
      fi
      log_info "Using domain: ${DOMAIN}"
      echo "${DOMAIN}" > "${DIRBACKUP}/domains.txt"
   fi

   begin_process "Getting emails"
   log_info "zmprov -l gaa ${DOMAIN} > emails.txt"
   zmprov -l gaa ${DOMAIN} > "${DIRBACKUP}/emails.txt"
   cat "${DIRBACKUP}/emails.txt"
   q_emails=`wc -l ${DIRBACKUP}/emails.txt |awk '{print $1}'`
   log_info "Total emails: $q_emails"

   begin_process "Exporting users and password"
   mkdir -p ${DIRUSERPASS}
   log_info "Exporting user password in: ${DIRUSERPASS}"
   count=0
   for i in `cat ${DIRBACKUP}/emails.txt`; do
      let count=$count+1
      log_info "[$count/$q_emails] zmprov  -l ga ${i} userPassword..."
      zmprov  -l ga ${i} userPassword | grep userPassword: | awk '{print $2}' > ${DIRUSERPASS}/${i}.shadow;
   done

   begin_process "Exporting usersdata"
   mkdir -p ${DIRUSERDATA}
   log_info "Exporting user data in: ${DIRUSERDATA}"
   count=0
   for i in `cat ${DIRBACKUP}/emails.txt`; do
      let count=$count+1
      log_info "[$count/$q_emails] zmprov ga ${i}..."
      zmprov ga ${i}  | grep -i Name: > ${DIRUSERDATA}/${i}.txt ;
   done
   notify "Export account - Terminated"

}

function export_mailbox()
{
   count_mailbox_user

   notify "Export mailbox - Started"
   mkdir -p ${DIRMAILBOX}
   begin_process "Exporting mailbox in : ${DIRMAILBOX}"
   q_emails=`wc -l ${DIRBACKUP}/emails.txt |awk '{print $1}'`
   count=0
   for email in `cat ${DIRBACKUP}/emails.txt`; do
      let count=$count+1
      log_info "[$count/$q_emails] zmmailbox -z -m ${email}..." ;
      zmmailbox -z -m ${email} -t 0 getRestURL '/?fmt=tgz' > ${DIRMAILBOX}/$email.tgz ;
      log_info "${email} -- finished " ;
   done
   notify "Export mailbox - Terminated"
}

function transfer_data()
{
   notify "Transfer data - Started"
   begin_process "Transfering backup to remote server"
   if [ "$1" = "" ] ; then
      DIR_BACKUP_WORK=`ls -ltr ${DIRAPP}|grep "zmigrate_"|awk '{print $9}'|tail -1`
   else
      DIR_BACKUP_WORK=$1
   fi
   log_info "sshpass -p \"${SSHPASSWORD}\" rsync -avp ${DIR_BACKUP_WORK} ${SSHREMOTE}:${SSHDIR} --log-file=${LOGFILE}"
   sshpass -p ${SSHPASSWORD} rsync -avp ${DIR_BACKUP_WORK} ${SSHREMOTE}:${SSHDIR} --log-file=${LOGFILE}
   notify "Transfer data - Terminated"
}

function import_account()
{
   notify "Import account - Started"
   mkdir -p "${DIRLOG}"
   validate_zextras_user

   begin_process "Starting process of account import..."

   version=`zmcontrol -v`
   log_info "${version}"

   status=`zmcontrol status`
   log_info "${status}"

   log_info "List of Domains:"
   log_info "carbonio prov -l gad"
   list_domain=`carbonio prov -l gad`
   log_info "${list_domain}"

   begin_process "Provisioning domains"
   for i in `cat ${DIRREMOTE}/domains.txt `; do
      log_info "Domain: ${i}"
      provi=`carbonio prov cd $i zimbraAuthMech zimbra`
      log_info "${provi}"
   done

   log_info "List of Domains:"
   log_info "carbonio prov -l gad"
   list_domain=`carbonio prov -l gad`
   log_info "${list_domain}"

   begin_process "Provisiong accounts"
   q_emails=`wc -l ${DIRREMOTE}/emails.txt |awk '{print $1}'`
   count=0
   for i in `cat ${DIRREMOTE}/emails.txt`
   do
      let count=$count+1
      log_info "[$count/$q_emails] Account ${i}"
      givenname=`grep givenName: ${DIRREMOTEUSERDATA}/$i.txt | cut -d ":" -f2`
      displayname=`grep displayName: ${DIRREMOTEUSERDATA}/$i.txt | cut -d ":" -f2`
      shadowpass=`cat ${DIRREMOTEUSERPASS}/$i.shadow`

      log_info "Creating account"
      carbonio prov ca $i CHANGEme cn "$givenname" displayName "$displayname" givenName "$givenname"
      log_info "Updating account password"
      carbonio prov ma $i userPassword "$shadowpass"
   done

   log_info "List of Accounts:"
   list_acc=`carbonio prov -l gaa -v ${DOMAIN} | grep -e displayName`
   log_info "${list_acc}"
   notify "Import account - Terminated"
}


function import_mailbox()
{
   notify "Import mailbox - Started"
   begin_process "Importing mailboxs"
   log_info "   Important Note:"
   log_info ""
   log_info "Few things you should keep in mind before starting the mailbox export/import process:"
   log_info "1. Set the socket timeout high (i.e. zmlocalconfig -e socket_so_timeout=3000000; zmlocalconfig -reload)"
   log_info "2. Check if you have any attachment limits. If you have increase the value during the migration period"
   log_info "3. Set Public Service Host Name & Public Service Protocol to avoid any error/issue like below one"

   q_emails=`wc -l ${DIRREMOTE}/emails.txt |awk '{print $1}'`
   count=0
   for email in `cat ${DIRREMOTE}/emails.txt`; do
      let count=$count+1
      log_info "[$count/$q_emails] zmmailbox -z -m ${email}..."
      zmmailbox -z -m ${email} -t 0 postRestURL "/?fmt=tgz&resolve=skip" ${DIRREMOTEMAILBOX}/$email.tgz ;
      log_info "${email} -- finished " ;
   done
   notify "Import mailbox - Terminated"
   count_mailbox_usercarbonio
}

while getopts ":eitmh" options; do
   case "${options}" in
      e) # Export zimbra mailbox
         export_account
         export_mailbox
         transfer_data ${DIRBACKUP}
         end_shell;;
      i) # Import account to carbonio
         import_account
         end_shell;;
      m) # Import mailbox to carbonio
         import_mailbox
         end_shell;;
      t) # Transfer data by rsync
         transfer_data
         end_shell;;
      *) # Invalid option
         echo "Invalid option: "$1
         usage
         end_shell 1
         ;;
   esac
done

echo "Enter an option."
usage