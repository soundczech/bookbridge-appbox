#!/bin/bash
# Three cases on boot:
#   fresh install - no /etc/app_configured and no database: create admin, callback
#   upgrade       - no /etc/app_configured but a database exists: callback only
#   restart       - /etc/app_configured exists: just start the app
#
# The web setup page is a CSRF-protected form, so the admin is created up front
# with appbox_admin.py instead of scripting a browser request.
set -x

CONFIG_FLAG="/etc/app_configured"
DATA_DB="/data/database.db"
APP_USER="1000:1000"

callback_installed() {
    if [[ "${SKIP_APPBOX_CALLBACK:-0}" == "1" ]]; then
        echo "Skipping Appbox callback because SKIP_APPBOX_CALLBACK=1"
        return 0
    fi

    local callback_url="https://api.cylo.net/v1/apps/installed/${INSTANCE_ID}"
    local headers=(
        -H "Accept: application/json"
        -H "Content-Type: application/json"
    )
    if [[ -n "${CALLBACK_TOKEN:-}" ]]; then
        headers+=(-H "Authorization: Bearer ${CALLBACK_TOKEN}")
    fi

    until curl -fsS -o /dev/null "${headers[@]}" -X POST "${callback_url}"; do
        sleep 5
    done
}

# New volumes are root-owned. Only chown recursively on first boot.
mkdir -p /data
if [[ ! -f "${CONFIG_FLAG}" ]]; then
    chown -R "${APP_USER}" /data
else
    chown "${APP_USER}" /data
fi

if [[ ! -f "${CONFIG_FLAG}" ]]; then
    touch "${CONFIG_FLAG}"

    if [[ ! -f "${DATA_DB}" ]]; then
        echo "Fresh install: creating admin account"
        # The helper reads credentials from the environment so the password
        # stays out of the set -x trace.
        if ! gosu "${APP_USER}" python /appbox_admin.py create; then
            echo "WARNING: admin user was not created. Open the app to finish setup in the browser."
        fi
    else
        echo "Upgrade: existing data found at ${DATA_DB}"
        echo "Skipping admin creation; BookBridge migrates its database on start."
    fi

    callback_installed
fi

# No longer needed after setup, so don't hand it to the app.
unset PASSWORD

exec gosu "${APP_USER}" "$@"
