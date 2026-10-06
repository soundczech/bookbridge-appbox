# Thin wrapper around the upstream BookBridge image. It's a single process
# with SQLite, so there's no init system or extra services.
# Build with: docker build --platform linux/amd64 -t bookbridge-appbox .

ARG BOOKBRIDGE_VERSION=7.9.0
FROM ghcr.io/cporcellijr/bookbridge:${BOOKBRIDGE_VERSION}

USER root

# gosu is the only real addition; bash and curl ship with the base image.
RUN apt-get update && \
    apt-get install -y --no-install-recommends bash curl gosu && \
    rm -rf /var/lib/apt/lists/*

# Upstream runs as root and has no UID 1000 user, but Appbox needs 1000:1000.
RUN if ! getent group 1000 >/dev/null; then groupadd -g 1000 bookbridge; fi && \
    if ! getent passwd 1000 >/dev/null; then \
        useradd -u 1000 -g 1000 -d /data -M -s /usr/sbin/nologin bookbridge; \
    fi

COPY entrypoint.sh /entrypoint.sh
COPY moduser.sh /moduser.sh
COPY appbox_admin.py /appbox_admin.py
RUN sed -i 's/\r$//' /entrypoint.sh /moduser.sh /appbox_admin.py && \
    chmod +x /entrypoint.sh /moduser.sh && \
    chmod 644 /appbox_admin.py && \
    mkdir -p /data && chown -R 1000:1000 /data && \
    # Break the build early if a newer upstream moves anything the scripts use.
    test -x /app/start.sh && test -f /app/alembic.ini && \
    python -c "import sys; sys.path.insert(0, '/app'); from src.db.user_bootstrap import create_initial_admin_user; from src.db.migration_utils import get_database_service"

# Keep caches in /tmp rather than the data volume. Whisper models still land
# in /data/models.
ENV DATA_DIR=/data \
    HOME=/tmp

# Upstream's healthcheck (GET / on 5757) is inherited as-is.
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/app/start.sh"]
EXPOSE 5757
