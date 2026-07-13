#!/bin/sh
set -eu

APP_DIR="${APP_DIR:-/config}"
APP_FILE="${APP_FILE:-app.py}"
APP_MODULE="${APP_MODULE:-app:app}"
REQUIREMENTS_FILE="${REQUIREMENTS_FILE:-requirements.txt}"
PORT="${PORT:-8000}"
WORKERS="${WORKERS:-1}"
THREADS="${THREADS:-4}"
TIMEOUT="${TIMEOUT:-120}"
PRE_START_COMMAND="${PRE_START_COMMAND:-}"

if [ ! -d "$APP_DIR" ]; then
    echo "ERROR: application directory '$APP_DIR' was not found." >&2
    exit 1
fi

cd "$APP_DIR"

if [ ! -f "$APP_FILE" ]; then
    echo "ERROR: expected '$APP_FILE' in '$APP_DIR'." >&2
    exit 1
fi

if [ -f "$REQUIREMENTS_FILE" ]; then
    echo "Installing Python requirements from $APP_DIR/$REQUIREMENTS_FILE ..."
    python -m pip install -r "$REQUIREMENTS_FILE"
else
    echo "No $APP_DIR/$REQUIREMENTS_FILE found. Continuing without additional installs."
fi

if [ -n "$PRE_START_COMMAND" ]; then
    echo "Running pre-start command ..."
    sh -c "$PRE_START_COMMAND"
fi

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
    --access-logfile - \
    --error-logfile - \
    --capture-output
