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

function begin_process()
{
   log_info ""
   log_info "################# $1 - Started ###################"

   notify "$1 - Started"
}

function end_process()
{
   log_info ""
   log_info "################# $1 - Ended ###################"

   notify "$1 - Ended"
}

function begin_shell()
{
   log_info "#######################################"
   trap 'end_shell 1' INT TERM EXIT ERR
}

function end_shell()
{
   last_date=`date +"%Y%m%d%H%M%S"`

   if [[ "$1" == "1" ]] ; then
      notify "Error ocurred"
      log_error "End Process with error .. $last_date"
      exit $1
   fi
   log_info "End Process .. $last_date"
   exit
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