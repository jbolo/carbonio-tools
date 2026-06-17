function print_command
{
   printf '  %-34s %s\n' "$1" "$2"
}

function command_specs
{
   cat <<'EOF'
export|--export|Full export: accounts, lists, aliases, mailboxes, signatures and rules.|run_export_full
export|--export-incremental|Incremental export using the configured mailbox date window.|run_export_incremental
export|--export-account|Export domains, accounts, passwords and user profile data.|run_export_account
export|--export-mailbox|Export mailbox TGZ files and mailbox report.|run_export_mailbox
export|--export-mailbox-user <email>|Export one mailbox TGZ file and mailbox report.|run_export_mailbox_user
export|--export-mailbox-list <file>|Export mailbox TGZ files from an email list.|run_export_mailbox_list
export|--export-dlist|Export distribution lists and members.|run_export_dlist
export|--export-alias|Export account aliases.|run_export_alias
export|--export-calendar-contacts|Export calendars and contacts.|run_export_calendar_contacts
import|--import|Full import: accounts, lists, aliases, mailboxes, signatures and rules.|run_import_full
import|--import-incremental|Import incremental mailbox backups.|run_import_incremental
import|--import-account|Import domains, accounts and passwords.|run_import_account
import|--import-mailbox|Import mailbox TGZ files.|run_import_mailbox
import|--import-dlist|Import distribution lists and members.|run_import_dlist
import|--import-alias|Import account aliases.|run_import_alias
import|--import-calendar-contacts|Import calendars and contacts.|run_import_calendar_contacts
operation|--transfer|Transfer the latest backup directory with rsync.|run_transfer
operation|--status|Show server status and mailbox/account report.|run_status
EOF
}

function print_command_group
{
   local group="$1"
   local spec_group
   local command
   local description
   local handler

   while IFS='|' read -r spec_group command description handler; do
      if [ "$spec_group" = "$group" ]; then
         print_command "$command" "$description"
      fi
   done < <(command_specs)
}

function usage
{
   cat <<EOF
Carbonio/Zimbra migration and backup utility.

Usage:
  $(basename "$0") <command> [args]

Export commands:
EOF
   print_command_group "export"
   echo

   echo "Import commands:"
   print_command_group "import"
   echo

   echo "Operations:"
   print_command_group "operation"
   print_command "--help, -h" "Show this help."
   echo
}

function get_command_handler
{
   local requested_command="${1:-}"
   local spec_group
   local command
   local description
   local handler

   while IFS='|' read -r spec_group command description handler; do
      if [ "${command%% *}" = "$requested_command" ]; then
         echo "$handler"
         return 0
      fi
   done < <(command_specs)

   return 1
}

function dispatch_command
{
   local command="$1"
   local handler

   if ! handler=$(get_command_handler "$command"); then
      echo "Invalid option: $command"
      echo
      usage
      exit 1
   fi

   "$handler" "$@"
}

function run_export_incremental
{
   set_context "$1"
   begin_shell
   get_status_server
   export_account
   export_dlist
   export_alias
   export_mailbox
   transfer_data "${DIRBACKUP}"
   end_shell
}

function run_export_full
{
   set_context "$1"
   begin_shell
   delete_old_export
   get_status_server
   export_account
   export_dlist
   export_alias
   export_mailbox
   export_signatures
   export_rules
   transfer_data "${DIRBACKUP}"
   end_shell
}

function run_export_account
{
   set_context "$1"
   begin_shell
   delete_old_export
   export_account
   end_shell
}

function run_export_mailbox
{
   set_context "$1"
   begin_shell
   delete_old_export
   export_mailbox
   end_shell
}

function run_export_mailbox_user
{
   set_context "$1"
   begin_shell
   delete_old_export
   export_mailbox_user "${2:-}"
   end_shell
}

function run_export_mailbox_list
{
   set_context "$1"
   begin_shell
   delete_old_export
   export_mailbox_list "${2:-}"
   end_shell
}

function run_export_dlist
{
   set_context "$1"
   begin_shell
   delete_old_export
   export_dlist
   end_shell
}

function run_export_alias
{
   set_context "$1"
   begin_shell
   delete_old_export
   export_alias
   end_shell
}

function run_export_calendar_contacts
{
   set_context "$1"
   begin_shell
   delete_old_export
   export_calendar_contacts
   end_shell
}

function run_import_incremental
{
   set_context "$1"
   begin_shell
   get_status_server
   import_mailbox
   end_shell
}

function run_import_full
{
   set_context "$1"
   begin_shell
   get_status_server
   import_account
   import_dlist
   import_alias
   import_mailbox
   import_signatures
   import_rules
   end_shell
}

function run_import_account
{
   set_context "$1"
   begin_shell
   import_account
   end_shell
}

function run_import_mailbox
{
   set_context "$1"
   begin_shell
   import_mailbox
   end_shell
}

function run_import_dlist
{
   set_context "$1"
   begin_shell
   import_dlist
   end_shell
}

function run_import_alias
{
   set_context "$1"
   begin_shell
   import_alias
   end_shell
}

function run_import_calendar_contacts
{
   set_context "$1"
   begin_shell
   import_calendar_contacts
   end_shell
}

function run_transfer
{
   set_context "$1"
   begin_shell
   transfer_data
   end_shell
}

function run_status
{
   set_context "$1"
   begin_shell
   get_status_server
   count_mailbox_user
   end_shell
}
