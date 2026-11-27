#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
service_file=/etc/systemd/system/openuem-firewall.service

iptables -C DOCKER-USER -s 192.168.1.0/24 -d 192.168.1.106/32 -p tcp -m multiport --dports 4433,8000 -j ACCEPT 2>/dev/null \
  || iptables -I DOCKER-USER 1 -s 192.168.1.0/24 -d 192.168.1.106/32 -p tcp -m multiport --dports 4433,8000 -j ACCEPT
iptables -C DOCKER-USER -d 192.168.1.106/32 -p tcp -m multiport --dports 4433,8000 -j DROP 2>/dev/null \
  || iptables -I DOCKER-USER 2 -d 192.168.1.106/32 -p tcp -m multiport --dports 4433,8000 -j DROP

cat >"$service_file" <<EOF
[Unit]
Description=OpenUEM LAN-only Docker firewall rules
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$repo_dir/ops/install-firewall.sh --rules-only

[Install]
WantedBy=multi-user.target
EOF

if [[ ${1:-} != --rules-only ]]; then
  systemctl daemon-reload
  systemctl enable openuem-firewall.service
fi
