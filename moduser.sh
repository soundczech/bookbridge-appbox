#!/bin/bash
# Usage: /moduser.sh <new_password>
# Resets the admin password (the install-time admin, or the oldest admin if it
# was renamed) and re-activates the account.

NEW_PASSWORD="$1"

if [[ -z "${NEW_PASSWORD}" || $# -ne 1 ]]; then
    echo "Usage: /moduser.sh <new_password>"
    exit 1
fi

# Run as 1000 so files in /data don't become root-owned. The password goes
# through the environment, not the command line.
export NEW_PASSWORD
exec gosu 1000:1000 python /appbox_admin.py reset
