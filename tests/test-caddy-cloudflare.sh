#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
caddy_config=$repo_dir/ops/caddy-openuem.caddy
deploy_script=$repo_dir/ops/deploy.sh

[[ $(grep -c 'dns cloudflare {env.CLOUDFLARE_DNS_TOKEN}' "$caddy_config") -eq 2 ]]
if grep -q 'tls /etc/caddy/openuem/console/proxy.cer' "$caddy_config"; then
  echo 'console still uses its private server certificate' >&2
  exit 1
fi
grep -q 'mode require_and_verify' "$caddy_config"
if grep -q -- '--cacert certificates/ca/ca.cer' "$deploy_script"; then
  echo 'deployment still trusts only the OpenUEM private CA' >&2
  exit 1
fi
grep -q 'console did not serve a publicly trusted certificate' "$deploy_script"
install_timeout_count=$(grep -c -- '--connect-timeout 5 --max-time 10' "$repo_dir/ops/install-caddy.sh")
deploy_timeout_count=$(grep -c -- '--connect-timeout 5 --max-time 10' "$deploy_script")
(( install_timeout_count + deploy_timeout_count == 2 ))

test_dir=$(mktemp -d)
cleanup() { rm -rf "$test_dir"; }
trap cleanup EXIT
mkdir -p "$test_dir/caddy"
touch "$test_dir/caddy/docker-compose.yml" "$test_dir/caddy/Caddyfile" "$test_dir/caddy/.env"
if CADDY_DIR="$test_dir/caddy" CADDY_SKIP_RELOAD=1 "$repo_dir/ops/install-caddy.sh" 2>/dev/null; then
  echo 'install accepted a missing Cloudflare token' >&2
  exit 1
fi

printf 'services:\n  caddy:\n    volumes:\n      - %s/caddy/pve-root-ca.pem:/etc/caddy/pve-root-ca.pem:ro\n' "$test_dir" \
  >"$test_dir/caddy/docker-compose.yml"
printf 'example.test { respond "ok" }\n' >"$test_dir/caddy/Caddyfile"
printf 'CLOUDFLARE_DNS_TOKEN=test-token\n' >"$test_dir/caddy/.env"
touch "$test_dir/caddy/pve-root-ca.pem"
log=$test_dir/docker.log
docker() {
  printf '%s\n' "$*" >>"$log"
  [[ ${1:-} != inspect ]] || printf 'test-caddy-image\n'
}
curl() { return 1; }
sleep() { :; }
export log
export -f curl docker sleep
if CADDY_DIR="$test_dir/caddy" CADDY_READY_ATTEMPTS=2 "$repo_dir/ops/install-caddy.sh" 2>/dev/null; then
  echo 'install accepted a Caddy instance without a trusted certificate' >&2
  exit 1
fi
[[ $(grep -c '^compose -f .* up -d --force-recreate caddy$' "$log") -eq 2 ]]
