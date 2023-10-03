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
DIRAPP=`pwd`
DIRLOG="${DIRAPP}/log"
LOGFILE="${DIRLOG}/migracion_"`date '+%Y%m%d%H%M%S'`".log"
LOGLEVEL="INFO"
ZIMBRA_USER="zextras"

DIRBACKUP="${DIRAPP}/zmigrate"
DIRUSERPASS="${DIRBACKUP}/userpass"
DIRUSERDATA="${DIRBACKUP}/userdata"
DIRMAILBOX="${DIRBACKUP}/mailbox"
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
   if [[ ! "$user" == "${ZIMBRA_USER}" ]]; then
      log_error "The actually user is not zextras: ${user}"
      exit 1
   fi
}

function count_mailbox_user()
{
   for j in $( zmprov -l gaa | egrep -v "^(spam|ham)"); do
      total=0;

      for i in $( zmmailbox -z -m "$j" gaf | awk '{print $4}' | egrep -o "[0-9]+" ); do
         total=$((total + i ));
      done;

      log_info "Total for ${j} = ${total}";
   done
}

function export_account()
{
   mkdir -p "${DIRLOG}"
   validate_zextras_user
   log_info "Starting process of account export..."

   version=`zmcontrol -v`
   log_info "${version}"

   status=`zmcontrol status`
   log_info "${status}"

   log_info "Creating backup directory: ${DIRBACKUP}"
   mkdir -p ${DIRBACKUP}
   cd ${DIRBACKUP}

   log_info "zmprov -l gad > domains.txt"
   zmprov -l gad > "${DIRBACKUP}/domains.txt"

   log_info "zmprov -l gaa > emails.txt"
   zmprov -l gaa > "${DIRBACKUP}/emails.txt"

   mkdir -p ${DIRUSERPASS}
   log_info "Exporting user password in: ${DIRUSERPASS}"
   for i in `cat ${DIRBACKUP}/emails.txt`; do
      log_info "zmprov  -l ga ${i} userPassword..."
      zmprov  -l ga ${i} userPassword | grep userPassword: | awk '{print $2}' > ${DIRUSERPASS}/${i}.shadow;
   done

   mkdir -p ${DIRUSERDATA}
   log_info "Exporting user data in: ${DIRUSERDATA}"
   for i in `cat ${DIRBACKUP}/emails.txt`; do
      log_info "zmprov ga ${i}..."
      zmprov ga ${i}  | grep -i Name: > ${DIRUSERDATA}/${i}.txt ;
   done

   count_mailbox_user

}

function export_mailbox()
{
   mkdir -p ${DIRMAILBOX}
   log_info "Exporting mailbox in : ${DIRMAILBOX}"
   for email in `cat ${DIRBACKUP}/emails.txt`; do
      log_info "zmmailbox -z -m ${email}..."
      zmmailbox -z -m ${email} -t 0 getRestURL '/?fmt=tgz' > ${DIRMAILBOX}/$email.tgz ;
      log_info "${email}"
   done
}

function import_account()
{
   validate_zextras_user
   # ... Pending
}

while getopts ":eih" options; do
   case "${options}" in
      e) # Export zimbra mailbox
         export_account
         export_mailbox
         exit;;
      i) # Import mailbox to carbonio
         import_account
         exit;;
      *) # Invalid option
         echo "Invalid option: "$1
         usage
         exit 1
         ;;
   esac
done

echo "Enter an option."
usage