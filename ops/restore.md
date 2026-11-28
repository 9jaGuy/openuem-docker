# Restore OpenUEM on svc1

1. Select the backup and verify its manifest:

   ```bash
   backup_dir=/var/backups/openuem/<selected-backup>
   (cd "$backup_dir" && sha256sum -c SHA256SUMS)
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

5. Start only `db`, then restore `postgres.dump` with `pg_restore --clean --if-exists`.
6. Restore JetStream into the resolved volume while `nats-server` remains stopped:

   ```bash
   docker run --rm \
     -v "$jetstream_volume:/target" \
     -v "$backup_dir:/backup:ro" \
     busybox:1.37.0 sh -c 'find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} \; && tar -C /target -xzf /backup/jetstream.tar.gz'
   ```

7. Run `ops/deploy.sh` with the recorded commit and verify console, OCSP, NATS, firewall rules, and one enrolled endpoint.

Test this procedure on a disposable compose project before relying on a backup. Never replace the live database or certificates as a restore test.
