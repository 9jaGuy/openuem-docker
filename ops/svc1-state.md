# OpenUEM on svc1

- Host: `svc1`, `192.168.1.106`, Proxmox VM 106
- Repository: `https://github.com/9jaGuy/openuem-docker`
- Checkout: `/opt/openuem/repo`
- Environment: `/etc/openuem/openuem.env`, mode `0600`
- State: `/opt/openuem/repo/certificates`, `/opt/openuem/repo/nats`, and the Compose-managed Postgres and JetStream volumes
- Console: `https://openuem.epoh.casa`, LAN only
- Certificate authentication: `https://openuem.epoh.casa:4443`, LAN only
- NATS: `openuem-nats.epoh.casa:4433`, bound to `192.168.1.106`, LAN firewall enforced
- OCSP: `http://openuem-ocsp.epoh.casa:8000`, bound to `192.168.1.106`, LAN firewall enforced
- DNS: the existing CoreDNS `*.epoh.casa` template resolves all three names to `192.168.1.106`
- Reverse proxy: existing Caddy in `/opt/docker/caddy`; OpenUEM certificates are mounted read-only
- Backups: `/var/backups/openuem`, nightly via `openuem-backup.timer`, 14-day retention
- Public access: disabled. Revisit DNS, firewall, trusted proxy ranges, certificates, and agent update channels before exposing any port publicly.
- Endpoint enrollment: follow `ops/onboarding.md`, beginning with one Windows pilot endpoint.
