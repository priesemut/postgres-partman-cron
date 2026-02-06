# Build stage for compiling pg_partman and pg_cron extensions
ARG PG_VERSION=18
FROM postgres:${PG_VERSION}-alpine AS builder

ARG PG_PARTMAN_VERSION
ARG PG_CRON_VERSION

RUN apk add --no-cache \
    build-base \
    clang \
    llvm \
    llvm-dev \
    git \
    curl \
    postgresql-dev \
    gcc \
    musl-dev \
    perl

WORKDIR /tmp

# Create a clang-19 wrapper that disables LTO compilation
RUN mkdir -p /usr/local/bin && \
    echo '#!/bin/sh' > /usr/local/bin/clang-19 && \
    echo 'args=""' >> /usr/local/bin/clang-19 && \
    echo 'for arg in "$@"; do' >> /usr/local/bin/clang-19 && \
    echo '    case "$arg" in' >> /usr/local/bin/clang-19 && \
    echo '        -emit-llvm) ;;' >> /usr/local/bin/clang-19 && \
    echo '        -flto=thin) ;;' >> /usr/local/bin/clang-19 && \
    echo '        -flto) ;;' >> /usr/local/bin/clang-19 && \
    echo '        *.bc) arg="${arg%.bc}.o" ;;' >> /usr/local/bin/clang-19 && \
    echo '    esac' >> /usr/local/bin/clang-19 && \
    echo '    args="$args $arg"' >> /usr/local/bin/clang-19 && \
    echo 'done' >> /usr/local/bin/clang-19 && \
    echo 'exec gcc $args -fno-lto' >> /usr/local/bin/clang-19 && \
    chmod +x /usr/local/bin/clang-19 && \
    ln -sf /usr/local/bin/clang-19 /usr/local/bin/clang

# Patch PostgreSQL Makefiles to remove LTO compilation flags
RUN for f in /usr/local/lib/postgresql/pgxs/src/Makefile.global* /usr/local/lib/postgresql/pgxs/src/makefiles/Makefile.global*; do \
        if [ -f "$f" ]; then \
            sed -i 's|-flto=thin||g' "$f"; \
            sed -i 's|-flto||g' "$f"; \
            sed -i 's|-emit-llvm||g' "$f"; \
        fi; \
    done || true

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

# Configure PostgreSQL to preload pg_cron
RUN mkdir -p /usr/local/share/postgresql && \
    echo "shared_preload_libraries = 'pg_cron'" >> /usr/local/share/postgresql/postgresql.conf.sample && \
    echo "cron.database_name = 'postgres'" >> /usr/local/share/postgresql/postgresql.conf.sample

# Add initialization script to create extensions
RUN mkdir -p /docker-entrypoint-initdb.d && \
    echo "#!/bin/bash" > /docker-entrypoint-initdb.d/00-create-extensions.sh && \
    echo "set -e" >> /docker-entrypoint-initdb.d/00-create-extensions.sh && \
    echo "" >> /docker-entrypoint-initdb.d/00-create-extensions.sh && \
    echo "psql -v ON_ERROR_STOP=1 --username \"\$POSTGRES_USER\" --dbname \"\$POSTGRES_DB\" <<-EOSQL" >> /docker-entrypoint-initdb.d/00-create-extensions.sh && \
    echo "    CREATE EXTENSION IF NOT EXISTS pg_cron;" >> /docker-entrypoint-initdb.d/00-create-extensions.sh && \
    echo "    CREATE EXTENSION IF NOT EXISTS pg_partman;" >> /docker-entrypoint-initdb.d/00-create-extensions.sh && \
    echo "EOSQL" >> /docker-entrypoint-initdb.d/00-create-extensions.sh && \
    chmod +x /docker-entrypoint-initdb.d/00-create-extensions.sh

LABEL org.opencontainers.image.description="PostgreSQL Alpine with pg_partman and pg_cron extensions" \
      org.opencontainers.image.source="https://github.com/username/postgres-partman-cron" \
      pg_partman.version="${PG_PARTMAN_VERSION}" \
      pg_cron.version="${PG_CRON_VERSION}"

