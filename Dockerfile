FROM python:3.13-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    APP_DIR=/config \
    APP_FILE=app.py \
    APP_MODULE=app:app \
    PACKAGES_FILE=packages.txt \
    REQUIREMENTS_FILE=requirements.txt \
    PORT=8000 \
    WORKERS=1 \
    THREADS=4 \
    TIMEOUT=120

RUN pip install --no-cache-dir gunicorn

COPY entrypoint.sh /usr/local/bin/flask-runner
RUN chmod +x /usr/local/bin/flask-runner

WORKDIR /config

EXPOSE 8000

ENTRYPOINT ["/usr/local/bin/flask-runner"]
