# Restore OpenUEM on svc1

1. Stop the stack with the same compose files used by `ops/deploy.sh`.
2. Verify `SHA256SUMS` in the selected backup directory.
3. Restore `config-and-certificates.tar.gz` into the repository root.
4. Start only `db`, then restore `postgres.dump` with `pg_restore --clean --if-exists`.
5. With `nats-server` stopped, restore `jetstream.tar.gz` into the `openuem_jetstream` volume.
6. Run `ops/deploy.sh` with the recorded commit and verify console, OCSP, NATS, firewall rules, and one enrolled endpoint.

Test this procedure on a disposable compose project before relying on a backup. Never replace the live database or certificates as a restore test.
