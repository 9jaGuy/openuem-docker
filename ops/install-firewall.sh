#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
service_file=/etc/systemd/system/openuem-firewall.service
firewall_chain=OPENUEM-LAN

iptables -N "$firewall_chain" 2>/dev/null || true
iptables -F "$firewall_chain"
for port in 4433 8000; do
  original_destination=(-p tcp -m conntrack --ctdir ORIGINAL --ctorigdst 192.168.1.106 --ctorigdstport "$port")
  iptables -A "$firewall_chain" -s 192.168.1.0/24 "${original_destination[@]}" -j ACCEPT
  iptables -A "$firewall_chain" "${original_destination[@]}" -j DROP
done
iptables -A "$firewall_chain" -j RETURN
iptables -C DOCKER-USER -j "$firewall_chain" 2>/dev/null \
  || iptables -I DOCKER-USER 1 -j "$firewall_chain"

if [[ ${1:-} != --rules-only ]]; then
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

  systemctl daemon-reload
  systemctl enable openuem-firewall.service
fi
