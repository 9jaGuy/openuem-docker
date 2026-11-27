#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
env_file=${OPENUEM_ENV_FILE:-/etc/openuem/openuem.env}
backup_root=${OPENUEM_BACKUP_DIR:-/var/backups/openuem}
retention_days=${OPENUEM_BACKUP_RETENTION_DAYS:-14}
stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup_root=$(realpath -m "$backup_root")
[[ "$backup_root" == /var/backups/openuem || "$backup_root" == /var/backups/openuem/* ]] \
  || { echo "backup directory must stay under /var/backups/openuem" >&2; exit 1; }
destination=$backup_root/$stamp
compose=(docker compose --env-file "$env_file" -f compose.yml -f ops/compose.lan.yml)

install -d -m 700 "$destination"
cd "$repo_dir"

# The database variables expand inside the container.
# shellcheck disable=SC2016
"${compose[@]}" exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" -p "$POSTGRES_PORT" -Fc "$POSTGRES_DB"' \
  >"$destination/postgres.dump"

services=(console agents-worker cert-manager-worker notification-worker nats-server)
"${compose[@]}" stop "${services[@]}"
trap '"${compose[@]}" up -d "${services[@]}"' EXIT

docker run --rm \
  -v openuem_jetstream:/source:ro \
  -v "$destination:/backup" \
  busybox:1.37.0 tar -C /source -czf /backup/jetstream.tar.gz .
tar -C "$repo_dir" -czf "$destination/config-and-certificates.tar.gz" certificates nats
sha256sum "$destination"/* >"$destination/SHA256SUMS"

"${compose[@]}" up -d "${services[@]}"
trap - EXIT
find "$backup_root" -mindepth 1 -maxdepth 1 -type d -mtime "+$retention_days" -exec rm -rf -- {} +
echo "$destination"
