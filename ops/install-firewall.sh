#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mode=${1:-install}
firewall_comment='OpenUEM LAN-only'
cleanup_chain=
cleanup_table=
lock_file=${OPENUEM_FIREWALL_LOCK:-/run/lock/openuem-firewall.lock}
lock_dir=$(dirname "$lock_file")

[[ -d "$lock_dir" ]] || install -d -m 755 "$lock_dir"
exec 9>"$lock_file"
flock 9

cleanup_staging_chain() {
  local -a table_args=()
  [[ -z "$cleanup_table" ]] || table_args=(-t "$cleanup_table")
  iptables "${table_args[@]}" -F "$cleanup_chain" 2>/dev/null || true
  iptables "${table_args[@]}" -X "$cleanup_chain" 2>/dev/null || true
}

chain_name() {
  local prefix=$1
  local suffix
  suffix=$(tr -d '-' </proc/sys/kernel/random/uuid | cut -c1-10)
  printf '%s-%s\n' "$prefix" "$suffix"
}

sweep_stale_chains() {
  local table=$1
  local parent=$2
  local prefix=$3
  local current=$4
  local candidate
  local -a table_args=()
  [[ -z "$table" ]] || table_args=(-t "$table")

  while IFS= read -r candidate; do
    [[ "$candidate" == "$current" ]] && continue
    if iptables "${table_args[@]}" -S "$parent" | grep -Fq -- "-j $candidate"; then
      continue
    fi
    if ! iptables "${table_args[@]}" -F "$candidate" \
      || ! iptables "${table_args[@]}" -X "$candidate"; then
      echo "warning: could not remove stale firewall chain $candidate" >&2
    fi
  done < <(iptables "${table_args[@]}" -S \
    | awk -v prefix="$prefix" '$1 == "-N" && index($2, prefix) == 1 { print $2 }')
}

remove_extra_jumps() {
  local table=$1
  local parent=$2
  local prefix=$3
  local current=$4
  local rule_number
  local -a table_args=()
  [[ -z "$table" ]] || table_args=(-t "$table")

  while true; do
    rule_number=$(iptables "${table_args[@]}" -L "$parent" --line-numbers -n \
      | awk -v prefix="$prefix" -v current="$current" \
        '$2 != current && index($2, prefix) == 1 { print $1; exit }')
    [[ -n "$rule_number" ]] || break
    iptables "${table_args[@]}" -D "$parent" "$rule_number"
  done
}

install_guard_rules() {
  local chain old_rule old_rule_number
  chain=$(chain_name OPENUEM-GUARD)

  iptables -t raw -N "$chain"
  cleanup_chain=$chain
  cleanup_table=raw
  trap cleanup_staging_chain EXIT
  iptables -t raw -A "$chain" -s 192.168.1.0/24 -d 192.168.1.106/32 \
    -p tcp -m multiport --dports 4433,8000 -j RETURN
  iptables -t raw -A "$chain" -d 192.168.1.106/32 \
    -p tcp -m multiport --dports 4433,8000 -j DROP
  iptables -t raw -A "$chain" -j RETURN

  old_rule=$(iptables -t raw -L PREROUTING --line-numbers -n \
    | awk '$2 ~ /^OPENUEM-GUARD/ { print $1 ":" $2; exit }')
  if [[ -n "$old_rule" ]]; then
    old_rule_number=${old_rule%%:*}
    iptables -t raw -R PREROUTING "$old_rule_number" \
      -m comment --comment "$firewall_comment" -j "$chain"
  else
    iptables -t raw -I PREROUTING 1 \
      -m comment --comment "$firewall_comment" -j "$chain"
  fi
  trap - EXIT
  cleanup_chain=
  cleanup_table=

  remove_extra_jumps raw PREROUTING OPENUEM-GUARD "$chain"
  sweep_stale_chains raw PREROUTING OPENUEM-GUARD "$chain"
}

install_docker_rules() {
  local chain old_rule old_rule_number port
  local -a original_destination
  chain=$(chain_name OPENUEM-LAN)

  iptables -N "$chain"
  cleanup_chain=$chain
  cleanup_table=
  trap cleanup_staging_chain EXIT
  for port in 4433 8000; do
    original_destination=(-p tcp -m conntrack --ctdir ORIGINAL --ctorigdst 192.168.1.106 --ctorigdstport "$port")
    iptables -A "$chain" -s 192.168.1.0/24 "${original_destination[@]}" -j ACCEPT
    iptables -A "$chain" "${original_destination[@]}" -j DROP
  done
  iptables -A "$chain" -j RETURN

  old_rule=$(iptables -L DOCKER-USER --line-numbers -n \
    | awk '$2 ~ /^OPENUEM-LAN/ { print $1 ":" $2; exit }')
  if [[ -n "$old_rule" ]]; then
    old_rule_number=${old_rule%%:*}
    iptables -R DOCKER-USER "$old_rule_number" \
      -m comment --comment "$firewall_comment" -j "$chain"
  else
    iptables -I DOCKER-USER 1 \
      -m comment --comment "$firewall_comment" -j "$chain"
  fi
  trap - EXIT
  cleanup_chain=

  remove_extra_jumps '' DOCKER-USER OPENUEM-LAN "$chain"
  sweep_stale_chains '' DOCKER-USER OPENUEM-LAN "$chain"
}

if [[ $mode == --guard-only ]]; then
  install_guard_rules
  exit 0
fi

if [[ $mode == --rules-only ]]; then
  install_docker_rules
  exit 0
fi

[[ $mode == install ]] || { echo "usage: $0 [--guard-only|--rules-only]" >&2; exit 2; }

install_guard_rules
install_docker_rules

install -d -m 755 /etc/systemd/system/docker.service.d /etc/systemd/system/docker.socket.d

cat >/etc/systemd/system/openuem-firewall-guard.service <<EOF
[Unit]
Description=OpenUEM pre-Docker LAN-only firewall guard
DefaultDependencies=no
After=local-fs.target
Before=docker.service docker.socket

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$repo_dir/ops/install-firewall.sh --guard-only

[Install]
WantedBy=sysinit.target
EOF

cat >/etc/systemd/system/openuem-firewall.service <<EOF
[Unit]
Description=OpenUEM LAN-only Docker firewall rules
After=docker.service openuem-firewall-guard.service
Requires=docker.service openuem-firewall-guard.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$repo_dir/ops/install-firewall.sh --rules-only

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/docker.service.d/openuem-firewall.conf <<EOF
[Unit]
Requires=openuem-firewall-guard.service
After=openuem-firewall-guard.service
EOF

cat >/etc/systemd/system/docker.socket.d/openuem-firewall.conf <<EOF
[Unit]
Requires=openuem-firewall-guard.service
After=openuem-firewall-guard.service
EOF

systemctl daemon-reload
systemctl enable openuem-firewall-guard.service openuem-firewall.service
