#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

cat >/etc/systemd/system/openuem-backup.service <<EOF
[Unit]
Description=Back up OpenUEM state
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
ExecStart=$repo_dir/ops/backup.sh
EOF

cat >/etc/systemd/system/openuem-backup.timer <<'EOF'
[Unit]
Description=Nightly OpenUEM backup

[Timer]
OnCalendar=*-*-* 03:17:00 America/Chicago
Persistent=true
RandomizedDelaySec=10m

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now openuem-backup.timer
