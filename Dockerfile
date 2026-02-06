# Build stage for compiling pg_partman and pg_cron extensions
ARG PG_VERSION=18
FROM postgres:${PG_VERSION}-alpine AS builder

ARG PG_PARTMAN_VERSION
ARG PG_CRON_VERSION

RUN apk add --no-cache \
    build-base \
    git \
    curl \
    postgresql-dev \
    gcc \
    musl-dev

WORKDIR /tmp

# Disable LLVM by creating a dummy clang-19 that creates empty .bc files
RUN echo '#!/bin/sh' > /usr/bin/clang-19 && \
    echo 'for arg in "$@"; do case "$arg" in *.bc) touch "$arg"; exit 0 ;; esac; done' >> /usr/bin/clang-19 && \
    echo 'exit 0' >> /usr/bin/clang-19 && \
    chmod +x /usr/bin/clang-19 && \
    mkdir -p /usr/lib/llvm19/bin && \
    echo '#!/bin/sh' > /usr/lib/llvm19/bin/llvm-lto && \
    echo 'exit 0' >> /usr/lib/llvm19/bin/llvm-lto && \
    chmod +x /usr/lib/llvm19/bin/llvm-lto


# Build pg_partman
RUN echo "### Building pg_partman ${PG_PARTMAN_VERSION}" && \
    curl -fL -o pg_partman.tar.gz "https://github.com/pgpartman/pg_partman/archive/refs/tags/v${PG_PARTMAN_VERSION}.tar.gz" && \
    tar -xzf pg_partman.tar.gz && \
    cd pg_partman-${PG_PARTMAN_VERSION} && \
    make && \
    make install

# Build pg_cron
RUN echo "### Building pg_cron ${PG_CRON_VERSION}" && \
    curl -fL -o pg_cron.tar.gz "https://github.com/citusdata/pg_cron/archive/refs/tags/v${PG_CRON_VERSION}.tar.gz" && \
    tar -xzf pg_cron.tar.gz && \
    cd pg_cron-${PG_CRON_VERSION} && \
    make && \
    make install

# Final image
ARG PG_VERSION=17
FROM postgres:${PG_VERSION}-alpine

ARG PG_PARTMAN_VERSION
ARG PG_CRON_VERSION

RUN apk add --no-cache \
    libstdc++

# Copy compiled extensions from builder
RUN mkdir -p /usr/local/lib/postgresql /usr/local/share/postgresql/extension
COPY --from=builder /usr/local/lib/postgresql/*.so /usr/local/lib/postgresql/
COPY --from=builder /usr/local/share/postgresql/extension/* /usr/local/share/postgresql/extension/

# Note: pg_cron requires shared_preload_libraries = 'pg_cron' in postgresql.conf
# Users can enable this by:
# 1. Setting POSTGRES_ARGS="-c shared_preload_libraries=pg_cron"
# 2. Or mounting a custom postgresql.conf
# 3. Or using: ALTER SYSTEM SET shared_preload_libraries = 'pg_cron'; (requires restart)

# Add optional initialization script to create extensions (only runs if extensions are enabled)
RUN mkdir -p /docker-entrypoint-initdb.d && \
    echo '#!/bin/bash' > /docker-entrypoint-initdb.d/00-create-extensions.sh && \
    echo 'set -e' >> /docker-entrypoint-initdb.d/00-create-extensions.sh && \
    echo '' >> /docker-entrypoint-initdb.d/00-create-extensions.sh && \
    echo '# Check if pg_cron is loaded in shared_preload_libraries' >> /docker-entrypoint-initdb.d/00-create-extensions.sh && \
    echo 'if psql -v ON_ERROR_STOP=0 --username "$POSTGRES_USER" --dbname postgres -tAc "SHOW shared_preload_libraries" | grep -q pg_cron; then' >> /docker-entrypoint-initdb.d/00-create-extensions.sh && \
    echo '    echo "pg_cron is enabled, creating extension..."' >> /docker-entrypoint-initdb.d/00-create-extensions.sh && \
    echo '    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<-EOSQL' >> /docker-entrypoint-initdb.d/00-create-extensions.sh && \
    echo '        CREATE EXTENSION IF NOT EXISTS pg_cron;' >> /docker-entrypoint-initdb.d/00-create-extensions.sh && \
    echo 'EOSQL' >> /docker-entrypoint-initdb.d/00-create-extensions.sh && \
    echo 'else' >> /docker-entrypoint-initdb.d/00-create-extensions.sh && \
    echo '    echo "pg_cron not in shared_preload_libraries, skipping extension creation"' >> /docker-entrypoint-initdb.d/00-create-extensions.sh && \
    echo 'fi' >> /docker-entrypoint-initdb.d/00-create-extensions.sh && \
    echo '' >> /docker-entrypoint-initdb.d/00-create-extensions.sh && \
    echo '# pg_partman can always be created' >> /docker-entrypoint-initdb.d/00-create-extensions.sh && \
    echo 'echo "Creating pg_partman extension..."' >> /docker-entrypoint-initdb.d/00-create-extensions.sh && \
    echo 'psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL' >> /docker-entrypoint-initdb.d/00-create-extensions.sh && \
    echo '    CREATE EXTENSION IF NOT EXISTS pg_partman;' >> /docker-entrypoint-initdb.d/00-create-extensions.sh && \
    echo 'EOSQL' >> /docker-entrypoint-initdb.d/00-create-extensions.sh && \
    chmod +x /docker-entrypoint-initdb.d/00-create-extensions.sh

LABEL org.opencontainers.image.description="PostgreSQL Alpine with pg_partman and pg_cron extensions" \
      org.opencontainers.image.source="https://github.com/username/postgres-partman-cron" \
      pg_partman.version="${PG_PARTMAN_VERSION}" \
      pg_cron.version="${PG_CRON_VERSION}"

