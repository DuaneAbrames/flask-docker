# flask-docker

Generic Flask runner image for apps that can be mounted into `/config`.

## Contract

Your mounted application directory should look like this:

```text
/config/
├── app.py
├── packages.txt
├── requirements.txt
├── startup.d/
│   └── worker
└── any other files the app needs
```

The container:

- optionally installs `/config/packages.txt` with `apt-get`
- optionally installs `/config/requirements.txt`
- starts each executable file in `/config/startup.d/` as a background worker
- runs an optional pre-start shell command
- starts Gunicorn against `APP_MODULE`
- watches `/config/restart.txt` and gracefully reloads Gunicorn when it appears

Default expectations:

- app file: `app.py`
- Flask object: `app`
- Gunicorn target: `app:app`

## Environment Variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `APP_DIR` | `/config` | Mounted application directory |
| `APP_FILE` | `app.py` | File that must exist before startup |
| `APP_MODULE` | `app:app` | Gunicorn import target |
| `PACKAGES_FILE` | `packages.txt` | File installed with `apt-get` at container start if present |
| `REQUIREMENTS_FILE` | `requirements.txt` | File installed at container start if present |
| `PORT` | `8000` | Internal listen port |
| `WORKERS` | `1` | Gunicorn worker processes |
| `THREADS` | `4` | Gunicorn threads per worker |
| `TIMEOUT` | `120` | Gunicorn request timeout |
| `PRE_START_COMMAND` | empty | Optional shell command run before Gunicorn |
| `GUNICORN_PID_FILE` | `/tmp/gunicorn.pid` | PID file used by the restart watcher |
| `RESTART_POLL_INTERVAL` | `1` | Seconds between restart-file checks |

## Build

```bash
docker build -t ghcr.io/<owner>/flask-docker:latest .
```

## Run

```bash
docker run -d \
  --name flask-runner \
  --restart unless-stopped \
  -p 5009:8000 \
  -v /path/to/flask-app:/config \
  ghcr.io/<owner>/flask-docker:latest
```

## Docker Compose

```yaml
services:
  flask-runner:
    image: ghcr.io/<owner>/flask-docker:latest
    container_name: flask-runner
    restart: unless-stopped
    ports:
      - "5009:8000"
    volumes:
      - /path/to/flask-app:/config
    environment:
      APP_MODULE: app:app
      WORKERS: "1"
      THREADS: "4"
      TIMEOUT: "180"
```

A ready-to-edit example is also included at [examples/docker-compose.yml](examples/docker-compose.yml).

## Example App

See [examples/app.py](examples/app.py) and [examples/requirements.txt](examples/requirements.txt).

`packages.txt` should contain one Debian package name per line. Blank lines and `#` comments are ignored. Example:

```text
build-essential
libpq-dev
# imagemagick
```

## Background Workers

Place each background worker in `/config/startup.d/`. Every regular file in this directory is made executable and started in the background after APT packages and Python requirements are installed, and before Gunicorn starts. Its shebang selects the interpreter, so both shell and Python workers are supported.

For example:

```bash
#!/usr/bin/env bash
while true; do
  python worker.py
  sleep 5
done
```

```python
#!/usr/bin/env python3
while True:
    process_next_job()
```

You can test locally with:

```bash
docker build -t flask-docker:test .
docker run --rm -p 5009:8000 -v "$(pwd)/examples:/config" flask-docker:test
```

Then open `http://localhost:5009`.

## Requesting a Gunicorn Reload

Create `/config/restart.txt` from the app or another process to request a graceful
Gunicorn reload:

```bash
touch /config/restart.txt
```

The container's background watcher atomically claims the request, sends `HUP` to
the Gunicorn master, and removes the claimed file after the signal succeeds. Gunicorn
then starts replacement workers and gracefully shuts down the previous workers.
If Gunicorn is not ready or cannot be signaled, the request file is retained for a
later retry. This image uses Gunicorn's supported signal interface; it does not
create a `/root/.gunicorn/gunicorn.ctl` control socket.

The watcher validates that the PID file identifies a live Gunicorn process before
it consumes a request. A stale or invalid PID file leaves `restart.txt` in place
and emits a diagnostic to the container log.

## GitHub Container Registry

The workflow at `.github/workflows/publish.yml` publishes:

- `ghcr.io/<owner>/flask-docker:latest` on pushes to `main`
- `ghcr.io/<owner>/flask-docker:<tag>` on version tags like `v1.0.0`

To use it:

1. Push this repository to GitHub.
2. Ensure Actions are enabled for the repo.
3. Push `main` to publish `latest`.
4. Push a version tag to publish a stable release tag.

## Notes

- Installing dependencies at startup is convenient, but it makes startup dependent on package availability.
- Installing APT packages at startup requires the container to run as root, which is the default for this image.
- For SQLite-backed apps, start with `WORKERS=1` unless you are certain your app and storage layer are safe with multiple processes.
