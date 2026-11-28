# Restore OpenUEM on svc1

Run the entire procedure in one root shell so the variables, error handling, and backup lock remain active.

1. Enable fail-fast shell behavior, select the backup, wait for any running backup, and hold its lock through deployment:

   ```bash
   set -euo pipefail
   backup_dir=/var/backups/openuem/<selected-backup>
   (cd "$backup_dir" && sha256sum -c SHA256SUMS)
   exec 9>/run/lock/openuem-backup.lock
   flock 9
   deployment_ref=$(tr -d '\r\n' <"$backup_dir/DEPLOYED_COMMIT")
   test -n "$deployment_ref"
   ```

2. From the repository root, resolve the JetStream volume before stopping its container:

   ```bash
   env_file=${OPENUEM_ENV_FILE:-/etc/openuem/openuem.env}
   compose=(docker compose --env-file "$env_file" -f compose.yml -f ops/compose.lan.yml)
   nats_container=$("${compose[@]}" ps -aq nats-server)
   test -n "$nats_container"
   jetstream_volume=$(docker inspect "$nats_container" \
     --format '{{range .Mounts}}{{if eq .Destination "/var/lib/jetstream/data"}}{{.Name}}{{end}}{{end}}')
   test -n "$jetstream_volume"
   docker volume inspect "$jetstream_volume" >/dev/null
   ```

3. Stop the stack with `"${compose[@]}" stop`.
4. Move the existing bind-mounted state aside, then restore the archive into the repository root:

   ```bash
   safety_dir=/var/backups/openuem/pre-restore-$(date -u +%Y%m%dT%H%M%SZ)
   install -d -m 700 "$safety_dir"
   for path in certificates nats; do
     test ! -e "$path" || mv -- "$path" "$safety_dir/"
   done
   tar -xzf "$backup_dir/config-and-certificates.tar.gz" certificates nats
   ```

5. Start only `db`, recreate the target database, and restore with error checking:

   ```bash
   "${compose[@]}" up -d db
   "${compose[@]}" exec -T db sh -c "
     psql -v ON_ERROR_STOP=1 -U \"\$POSTGRES_USER\" -p \"\$POSTGRES_PORT\" -d postgres \\
       -v dbname=\"\$POSTGRES_DB\" -v dbuser=\"\$POSTGRES_USER\" <<'SQL'
   SELECT pg_terminate_backend(pid) FROM pg_stat_activity
     WHERE datname = :'dbname' AND pid <> pg_backend_pid();
   DROP DATABASE IF EXISTS :\"dbname\";
   CREATE DATABASE :\"dbname\" OWNER :\"dbuser\";
   SQL
   "
   "${compose[@]}" exec -T db sh -c '
     pg_restore --exit-on-error -U "$POSTGRES_USER" -p "$POSTGRES_PORT" -d "$POSTGRES_DB"
   ' <"$backup_dir/postgres.dump"
   ```

6. Restore JetStream into the resolved volume while `nats-server` remains stopped:

   ```bash
   docker run --rm \
     -v "$jetstream_volume:/target" \
     -v "$backup_dir:/backup:ro" \
     busybox:1.37.0 sh -c 'find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} \; && tar -C /target -xzf /backup/jetstream.tar.gz'
   ```

7. Deploy the commit recorded with the backup, verify console, OCSP, NATS, firewall rules, and one enrolled endpoint, then release the backup lock:

   ```bash
   ops/deploy.sh "$deployment_ref"
   flock -u 9
   exec 9>&-
   ```

Test this procedure on a disposable compose project before relying on a backup. Never replace the live database or certificates as a restore test.
