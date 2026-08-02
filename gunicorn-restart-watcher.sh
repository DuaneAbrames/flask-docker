#!/bin/sh
set -eu

RESTART_FILE="${RESTART_FILE:-/config/restart.txt}"
GUNICORN_PID_FILE="${GUNICORN_PID_FILE:-/tmp/gunicorn.pid}"
RESTART_POLL_INTERVAL="${RESTART_POLL_INTERVAL:-1}"

is_gunicorn_master() {
    gunicorn_pid="$1"

    case "$gunicorn_pid" in
        ''|*[!0-9]*) return 1 ;;
    esac

    # A PID file can briefly be stale after Gunicorn exits. `kill -0` only
    # proves that some process owns the PID, so confirm it is Gunicorn before
    # consuming a reload request.
    [ -r "/proc/$gunicorn_pid/cmdline" ] || return 1
    gunicorn_command="$(tr '\000' ' ' < "/proc/$gunicorn_pid/cmdline")"
    case "$gunicorn_command" in
        *gunicorn*) kill -0 "$gunicorn_pid" 2>/dev/null ;;
        *) return 1 ;;
    esac
}

while :; do
    if [ -f "$RESTART_FILE" ]; then
        processing_file="${RESTART_FILE}.processing.$$"

        # Rename atomically so a new request written during a reload is retained
        # for the next polling cycle.
        if mv "$RESTART_FILE" "$processing_file" 2>/dev/null; then
            if [ -r "$GUNICORN_PID_FILE" ]; then
                gunicorn_pid="$(cat "$GUNICORN_PID_FILE")"

                if is_gunicorn_master "$gunicorn_pid"; then
                    if kill -HUP "$gunicorn_pid"; then
                        echo "Reload request received; sent HUP to Gunicorn master (pid $gunicorn_pid)."
                        rm -f "$processing_file"
                    else
                        echo "Unable to send HUP to Gunicorn master (pid $gunicorn_pid); retrying reload request." >&2
                        mv "$processing_file" "$RESTART_FILE"
                    fi
                else
                    echo "PID file '$GUNICORN_PID_FILE' does not identify a live Gunicorn master (pid '$gunicorn_pid'); retrying reload request." >&2
                    mv "$processing_file" "$RESTART_FILE"
                fi
            else
                echo "Gunicorn PID file '$GUNICORN_PID_FILE' is not ready; retrying reload request." >&2
                mv "$processing_file" "$RESTART_FILE"
            fi
        fi
    fi

    sleep "$RESTART_POLL_INTERVAL"
done
