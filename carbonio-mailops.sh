#!/usr/bin/env bash
set -Eeuo pipefail
################################################################################
#                    Carbonio/Zimbra Mail Operations                           #
#                                                                              #
# Utility for Carbonio CE and Zimbra mail operations: migration, backup,        #
# import/export, reporting and transfer workflows.                              #
################################################################################

PID=$$
DIRAPP=$(dirname "$(readlink -f "$0")")
ENV_FILE="$DIRAPP/.varset"

if [ ! -f "$ENV_FILE" ] ; then
   echo ".varset file not found"
   exit 1
fi

. "$ENV_FILE"

DIRLOG="${DIRAPP}/log"
TODAY_LINE=$(date '+%Y%m%d%H%M%S')
LOGFILE="${DIRLOG}/carbonio_mailops_${TODAY_LINE}.log"

if [ ! -d "$DIRLOG" ] ; then
   mkdir -p "$DIRLOG"
fi

. "$DIRAPP/lib/logging.sh"
. "$DIRAPP/lib/context.sh"
. "$DIRAPP/lib/carbonio.sh"
. "$DIRAPP/lib/report.sh"
. "$DIRAPP/lib/export.sh"
. "$DIRAPP/lib/transfer.sh"
. "$DIRAPP/lib/import.sh"
. "$DIRAPP/lib/backup.sh"
. "$DIRAPP/lib/cli.sh"

if [ -z "${1:-}" ]; then
   usage
   exit
fi

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
   usage
   exit
fi

dispatch_command "$1"
