# postgres-partman-cron

A Docker image combining PostgreSQL (Alpine) with [pg_partman](https://github.com/pgpartman/pg_partman) and [pg_cron](https://github.com/citusdata/pg_cron) extensions, automatically built and published when any upstream component releases a new version.

## Features

- **PostgreSQL Alpine**: Lightweight PostgreSQL base image
- **pg_partman**: Automatic partition management for PostgreSQL
- **pg_cron**: Simple cron-based job scheduler for PostgreSQL

Both extensions are compiled from source and pre-installed. The image is configured so that extensions can be used immediately after container start.

## Automatic Builds

A GitHub Actions workflow runs daily to check for new releases of:
- PostgreSQL Alpine Docker image (major version)
- pg_partman
- pg_cron

When any of these have a new release, a new Docker image is automatically built and pushed to Docker Hub.

## Image Tags

- `latest` - Always the most recent build
- `{pg_version}_{partman_version}_{cron_version}` - Specific version combination (e.g., `17_5.2.4_1.6.5`)

## Platforms

Images are built for:
- `linux/amd64`
- `linux/arm64`

## Usage

```bash
docker run -d \
  --name postgres-partman-cron \
  -e POSTGRES_PASSWORD=mysecretpassword \
  -p 5432:5432 \
  yourusername/postgres-partman-cron:latest
```

The extensions are automatically created on first startup. You can verify:

```sql
SELECT * FROM pg_extension WHERE extname IN ('pg_partman', 'pg_cron');
```

## Configuration

### pg_cron

pg_cron is configured to run in the `postgres` database by default. To change this, set the `POSTGRES_DB` environment variable.

### pg_partman

pg_partman requires the partman schema and background worker configuration for automatic maintenance. See the [pg_partman documentation](https://github.com/pgpartman/pg_partman#configuration) for details.

## Required GitHub Secrets

To use this workflow in your own repository:

- `DOCKERHUB_USERNAME`: Your Docker Hub username
- `DOCKERHUB_TOKEN`: Your Docker Hub access token

## License

This project is provided as-is. The included software components have their own licenses:
- PostgreSQL: [PostgreSQL License](https://www.postgresql.org/about/licence/)
- pg_partman: [PostgreSQL License](https://github.com/pgpartman/pg_partman/blob/master/LICENSE.txt)
- pg_cron: [PostgreSQL License](https://github.com/citusdata/pg_cron/blob/main/LICENSE)

