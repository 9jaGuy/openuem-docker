#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
log=$test_dir/docker.log
cleanup() { rm -rf "$test_dir"; }
trap cleanup EXIT

mkdir -p "$test_dir/caddy"
printf 'services:\n  caddy:\n    volumes:\n      - %s/caddy/pve-root-ca.pem:/etc/caddy/pve-root-ca.pem:ro\n' "$test_dir" \
  >"$test_dir/caddy/docker-compose.yml"
printf 'example.test { respond "ok" }\n' >"$test_dir/caddy/Caddyfile"
printf 'CLOUDFLARE_DNS_TOKEN=test-token\n' >"$test_dir/caddy/.env"
touch "$test_dir/caddy/pve-root-ca.pem"

docker() {
  printf '%s\n' "$*" >>"$log"
  if [[ ${1:-} == inspect ]]; then
    printf 'test-caddy-image\n'
  elif [[ $* == 'exec caddy caddy reload '* ]]; then
    return 1
  fi
}
curl() { return 0; }
export log
export -f curl docker

CADDY_DIR="$test_dir/caddy" "$repo_dir/ops/install-caddy.sh"
grep -q '^exec caddy caddy validate ' "$log"
if grep -q '^exec caddy caddy reload ' "$log"; then
  echo 'unexpected Caddy reload' >&2
  exit 1
fi
echo caddy_recreate_without_reload=passed
