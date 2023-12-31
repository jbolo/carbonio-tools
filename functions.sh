#!/bin/bash
#################################
# Functions
#################################

# Logging functions
function log_output {
   DATENOW=`date "+%Y/%m/%d %H:%M:%S"`
   echo "${DATENOW} $1"
   echo "${DATENOW} $1" >> $LOGFILE
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

function begin_process
{
   log_info ""
   log_info "################# $1 - Started ###################"

   notify "$1 - Started"
}

function end_process
{
   log_info ""
   log_info "################# $1 - Ended ###################"

   notify "$1 - Ended"
}

function begin_shell
{
   log_info "#######################################"
   trap 'end_shell $? $LINENO' INT TERM EXIT ERR
}

function end_shell
{
   last_date=`date +"%Y%m%d%H%M%S"`

   if [[ "$1" != "0" && "$1" != "" ]] ; then
      notify "Error ocurred"
      log_error "Error $1 occurred on $2"
      log_error "End Process with error .. $last_date"
      if [ "$MAILX_ENABLED" -eq "1" ] ; then
         log_info "Enviando Correo de Error" ;
         TODAY_PROC=`date '+%Y/%m/%d'`
         echo "Ocurrio un error en el proceso." | /usr/bin/mailx -r "$MAILX_FROM" -s "$MAILX_SUBJECT $TODAY_PROC - ERROR" $MAILX_TO
      fi
      exit 1
   fi
   log_info "End Process .. $last_date"
   exit
}

function del_file
{
   file_name=$1
   if [ -s $file_name ] || [ ! -z $file_name ] || [ -f $file_name ] ; then
      rm -f $file_name
   fi
}

function notify
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

function nrwait
{
   nrwait_my_arg=0
   if [[ -z $1 ]] ; then
      nrwait_my_arg=2
   else
      nrwait_my_arg=$1
   fi
   jobs -l
   V_JOB=`jobs -l | grep -c "Running"`
   log_info "Before - Count: $V_JOB  ... Max = $nrwait_my_arg"

   while [[ $V_JOB -ge $nrwait_my_arg ]]
   do
       V_JOB=`jobs -l | grep -c "Running"`
       sleep 0.33;
   done

   log_info "After - Count: $V_JOB"
}