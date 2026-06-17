#!/usr/bin/env bash
set -Eeuo pipefail

DIRAPP=$(dirname "$(readlink -f "$0")")
exec "$DIRAPP/carbonio-mailops.sh" "$@"
