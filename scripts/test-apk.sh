#!/bin/sh
# Install-test the APKs that `abuild` just built for one app.
# Usage (inside alpine:edge, from the repo root): sh scripts/test-apk.sh <app>
show_log() {
    echo "--- last lines of /var/log/messages ---" >&2
    tail -n 20 /var/log/messages 2>/dev/null || echo "(no log available)" >&2
}

set -eu

apk add -q jq openrc

# need a "booted" marker
mkdir -p /run/openrc && touch /run/openrc/softlevel
# start syslogd so we can log
syslogd

app="${1:?usage: test-apk.sh <app>}"
pkg=$(jq -r --arg app "$app" '.[] | select(.app == $app) | .pkg // empty' apps.json)
port=$(jq -r --arg app "$app" '.[] | select(.app == $app) | .port // empty' apps.json)

if [ -z "$pkg" ] || [ -z "$port" ]; then
    echo "error: '$app' has no pkg/port in apps.json" >&2
    exit 1
fi

apk add -q --allow-untrusted "$app"/out/*.apk

id "$pkg"                           # service user
apk info -e "$pkg"                  # really installed?

if [ -f "$app/smoke.sh" ]; then     # run per-app smoke test it exists
    sh "$app/smoke.sh"
fi

rc-service "$pkg" start || { echo "FAIL: start" >&2; show_log; exit 1; }

attempt=0
until [ "$attempt" -gt 20 ]; do
    attempt=$((attempt+1))
    if wget -q -T 5 -O /dev/null "http://127.0.0.1:$port/"; then
        if ! rc-service "$pkg" stop; then
            echo "FAIL: $app ($pkg) did not stop properly" >&2
            show_log
            exit 1
        fi

        sleep 2
        if pgrep -u "$pkg" >/dev/null; then
            echo "FAIL: $app ($pkg) not cleaned up properly" >&2
            show_log
            exit 1
        fi

        echo "OK: $app ($pkg)"
        exit 0
    fi

    sleep 3
done

echo "ERROR: $app ($pkg) did not respond" >&2
show_log
exit 1
