#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
service_file=/etc/systemd/system/openuem-firewall.service
firewall_chain="OPENUEM-LAN-$(date +%s)"
firewall_comment='OpenUEM LAN-only'
activated=0

cleanup_staging_chain() {
  if (( ! activated )); then
    iptables -F "$firewall_chain" 2>/dev/null || true
    iptables -X "$firewall_chain" 2>/dev/null || true
  fi
}
trap cleanup_staging_chain EXIT

iptables -N "$firewall_chain"
for port in 4433 8000; do
  original_destination=(-p tcp -m conntrack --ctdir ORIGINAL --ctorigdst 192.168.1.106 --ctorigdstport "$port")
  iptables -A "$firewall_chain" -s 192.168.1.0/24 "${original_destination[@]}" -j ACCEPT
  iptables -A "$firewall_chain" "${original_destination[@]}" -j DROP
done
iptables -A "$firewall_chain" -j RETURN

old_rule=$(iptables -L DOCKER-USER --line-numbers -n | awk '$2 ~ /^OPENUEM-LAN/ { print $1 ":" $2; exit }')
if [[ -n "$old_rule" ]]; then
  old_rule_number=${old_rule%%:*}
  old_chain=${old_rule#*:}
  iptables -R DOCKER-USER "$old_rule_number" -m comment --comment "$firewall_comment" -j "$firewall_chain"
else
  old_chain=
  iptables -I DOCKER-USER 1 -m comment --comment "$firewall_comment" -j "$firewall_chain"
fi
activated=1
trap - EXIT

if [[ -n "$old_chain" && "$old_chain" != "$firewall_chain" ]]; then
  iptables -F "$old_chain"
  iptables -X "$old_chain"
fi

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
