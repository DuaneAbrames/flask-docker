#!/bin/sh
set -eu

APP_DIR="${APP_DIR:-/config}"
APP_FILE="${APP_FILE:-app.py}"
APP_MODULE="${APP_MODULE:-app:app}"
PACKAGES_FILE="${PACKAGES_FILE:-packages.txt}"
REQUIREMENTS_FILE="${REQUIREMENTS_FILE:-requirements.txt}"
PORT="${PORT:-8000}"
WORKERS="${WORKERS:-1}"
THREADS="${THREADS:-4}"
TIMEOUT="${TIMEOUT:-120}"
PRE_START_COMMAND="${PRE_START_COMMAND:-}"
GUNICORN_PID_FILE="${GUNICORN_PID_FILE:-/tmp/gunicorn.pid}"

if [ ! -d "$APP_DIR" ]; then
    echo "ERROR: application directory '$APP_DIR' was not found." >&2
    exit 1
fi

cd "$APP_DIR"

if [ ! -f "$APP_FILE" ]; then
    echo "ERROR: expected '$APP_FILE' in '$APP_DIR'." >&2
    exit 1
fi

if [ -f "$PACKAGES_FILE" ]; then
    PACKAGES="$(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$PACKAGES_FILE")"

    if [ -n "$PACKAGES" ]; then
        echo "Installing APT packages from $APP_DIR/$PACKAGES_FILE ..."
        apt-get update
        # Intentionally rely on shell word splitting so each package becomes its own argument.
        apt-get install -y --no-install-recommends $PACKAGES
        rm -rf /var/lib/apt/lists/*
    else
        echo "$APP_DIR/$PACKAGES_FILE is present but empty. Continuing without additional APT installs."
    fi
else
    echo "No $APP_DIR/$PACKAGES_FILE found. Continuing without additional APT installs."
fi

if [ -f "$REQUIREMENTS_FILE" ]; then
    echo "Installing Python requirements from $APP_DIR/$REQUIREMENTS_FILE ..."
    python -m pip install -r "$REQUIREMENTS_FILE"
else
    echo "No $APP_DIR/$REQUIREMENTS_FILE found. Continuing without additional installs."
fi

STARTUP_DIR="$APP_DIR/startup.d"

if [ -d "$STARTUP_DIR" ]; then
    found_startup_file=false

    for startup_file in "$STARTUP_DIR"/*; do
        [ -f "$startup_file" ] || continue
        found_startup_file=true

        echo "Starting background worker $startup_file ..."
        chmod +x "$startup_file"
        "$startup_file" &
    done

    if [ "$found_startup_file" = false ]; then
        echo "No startup workers found in $STARTUP_DIR."
    fi
else
    echo "No $STARTUP_DIR directory found. Continuing without background workers."
fi

if [ -n "$PRE_START_COMMAND" ]; then
    echo "Running pre-start command ..."
    sh -c "$PRE_START_COMMAND"
fi

echo "Starting Gunicorn restart watcher for $APP_DIR/restart.txt ..."
GUNICORN_PID_FILE="$GUNICORN_PID_FILE" RESTART_FILE="$APP_DIR/restart.txt" \
    /usr/local/bin/gunicorn-restart-watcher &

echo "Starting Gunicorn"
echo "  APP_MODULE=$APP_MODULE"
echo "  PORT=$PORT"
echo "  WORKERS=$WORKERS"
echo "  THREADS=$THREADS"
echo "  TIMEOUT=$TIMEOUT"

exec gunicorn "$APP_MODULE" \
    --bind "0.0.0.0:$PORT" \
    --workers "$WORKERS" \
    --threads "$THREADS" \
    --timeout "$TIMEOUT" \
    --pid "$GUNICORN_PID_FILE" \
    --access-logfile - \
    --error-logfile - \
    --capture-output
