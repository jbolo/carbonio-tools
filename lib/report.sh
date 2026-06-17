function count_file_lines
{
   wc -l "$1" | awk '{print $1}'
}

function get_parallel_limit
{
   local parallel_limit

   parallel_limit=$(awk -F"=" '$1=="N_PROC_PARALLEL" {print $2}' "$ENV_FILE" | cut -d";" -f1 || true)
   if [[ ! "$parallel_limit" =~ ^[0-9]+$ ]] || [ "$parallel_limit" -lt 1 ]; then
      parallel_limit=2
   fi

   echo "$parallel_limit"
}

function get_account_attr
{
   ACCOUNT_DATA="$1"
   ATTR_NAME="$2"
   DEFAULT_VALUE="$3"
   ATTR_VALUE=$(echo "$ACCOUNT_DATA" | awk -F': ' -v attr="$ATTR_NAME" '$1 == attr {print $2; exit}')

   if [ -z "$ATTR_VALUE" ]; then
      echo "$DEFAULT_VALUE"
      return 0
   fi

   echo "$ATTR_VALUE"
}

function format_zimbra_timestamp
{
   RAW_TS="$1"

   if [ -z "$RAW_TS" ]; then
      echo "NEVER"
      return 0
   fi

   COMPACT_TS="${RAW_TS%%.*}"
   COMPACT_TS="${COMPACT_TS%Z}"

   if [[ "$COMPACT_TS" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})$ ]]; then
      date -u -d "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]} UTC" "+%Y-%m-%d %H:%M:%S UTC" 2>/dev/null || echo "$RAW_TS"
      return 0
   fi

   echo "$RAW_TS"
}

function days_since_zimbra_timestamp
{
   RAW_TS="$1"

   if [ -z "$RAW_TS" ]; then
      echo "NA"
      return 0
   fi

   COMPACT_TS="${RAW_TS%%.*}"
   COMPACT_TS="${COMPACT_TS%Z}"

   if [[ "$COMPACT_TS" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})$ ]]; then
      TS_EPOCH=$(date -u -d "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]} UTC" "+%s" 2>/dev/null || true)
      NOW_EPOCH=$(date -u "+%s")

      if [ ! -z "$TS_EPOCH" ]; then
         echo $(( (NOW_EPOCH - TS_EPOCH) / 86400 ))
         return 0
      fi
   fi

   echo "NA"
}

function quota_to_mb
{
   QUOTA_BYTES="$1"

   if [ -z "$QUOTA_BYTES" ] || [ "$QUOTA_BYTES" = "0" ]; then
      echo "UNLIMITED"
      return 0
   fi

   echo $(( QUOTA_BYTES / 1024 / 1024 ))
}

function count_mailbox_user
{
   EMAILS_FILE="${1:-}"
   REPORT_FILE="${2:-}"

   if [ ! -f "$EMAILS_FILE" ]; then
      # file not exists
      EMAILS_FILE="${DIRBACKUP}/emails_${TODAY_LINE}.txt"
      get_list_emails "$EMAILS_FILE"
   fi

   begin_process "Getting mailbox user details"
   if [ ! -z "$REPORT_FILE" ] && [ ! -s "$REPORT_FILE" ]; then
      echo "Email|Messages|MailboxSize|Status|LastLogin|DaysSinceLastLogin|Created|DaysSinceCreated|PasswordModified|MailHost|QuotaBytes|QuotaMB|IsAdmin" >> "$REPORT_FILE"
   fi

   while read -r j; do
      if [ -z "$j" ]; then
         continue
      fi

      log_info "Analizing account: ${j}"
      total=0;

      while read -r i; do
         if [ -z "$i" ]; then
            continue
         fi
         total=$((total + i ));
      done < <(mailbox -z -m "$j" gaf | awk '{print $4}' | grep -E -o "[0-9]+" || true)

      size=$(mailbox -z -m "$j" gms)
      account_data=$(prov -l ga "$j" zimbraAccountStatus zimbraLastLogonTimestamp zimbraCreateTimestamp zimbraPasswordModifiedTime zimbraMailHost zimbraMailQuota zimbraIsAdminAccount 2>/dev/null || true)
      account_status=$(get_account_attr "$account_data" "zimbraAccountStatus" "UNKNOWN")
      last_login_raw=$(get_account_attr "$account_data" "zimbraLastLogonTimestamp" "")
      created_raw=$(get_account_attr "$account_data" "zimbraCreateTimestamp" "")
      password_modified_raw=$(get_account_attr "$account_data" "zimbraPasswordModifiedTime" "")
      mail_host=$(get_account_attr "$account_data" "zimbraMailHost" "UNKNOWN")
      quota_bytes=$(get_account_attr "$account_data" "zimbraMailQuota" "0")
      is_admin=$(get_account_attr "$account_data" "zimbraIsAdminAccount" "FALSE")

      last_login=$(format_zimbra_timestamp "$last_login_raw")
      days_since_last_login=$(days_since_zimbra_timestamp "$last_login_raw")
      created=$(format_zimbra_timestamp "$created_raw")
      days_since_created=$(days_since_zimbra_timestamp "$created_raw")
      password_modified=$(format_zimbra_timestamp "$password_modified_raw")
      quota_mb=$(quota_to_mb "$quota_bytes")

      log_info "Report:Email:${j}|Q=${total}|Size=${size}|Status=${account_status}|LastLogin=${last_login}|DaysSinceLastLogin=${days_since_last_login}|Created=${created}|MailHost=${mail_host}|QuotaMB=${quota_mb}|IsAdmin=${is_admin}";

      if [ ! -z "$REPORT_FILE" ]; then
         LINE_RESUME="${j}|${total}|${size}|${account_status}|${last_login}|${days_since_last_login}|${created}|${days_since_created}|${password_modified}|${mail_host}|${quota_bytes}|${quota_mb}|${is_admin}"
         echo "$LINE_RESUME" >> "$REPORT_FILE"
      fi
   done < "$EMAILS_FILE"

   end_process "Getting mailbox user details"
}

