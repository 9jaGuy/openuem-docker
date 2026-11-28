#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
caddy_dir=${CADDY_DIR:-/opt/docker/caddy}
compose_file=$caddy_dir/docker-compose.yml
caddyfile=$caddy_dir/Caddyfile
backup_dir=$(mktemp -d)
replacement_started=0
preserve_backup=0

[[ -f "$compose_file" && -f "$caddyfile" ]] || { echo "Caddy configuration not found" >&2; exit 1; }
grep -qE '^CLOUDFLARE_DNS_TOKEN=.+' "$caddy_dir/.env" \
  || { echo "CLOUDFLARE_DNS_TOKEN is missing from $caddy_dir/.env" >&2; exit 1; }

cp -a "$compose_file" "$caddyfile" "$backup_dir/"
[[ ! -f "$caddy_dir/openuem.caddy" ]] || cp -a "$caddy_dir/openuem.caddy" "$backup_dir/"

rollback() {
  preserve_backup=1
  cp -a "$backup_dir/docker-compose.yml" "$compose_file"
  cp -a "$backup_dir/Caddyfile" "$caddyfile"
  if [[ -f "$backup_dir/openuem.caddy" ]]; then
    cp -a "$backup_dir/openuem.caddy" "$caddy_dir/openuem.caddy"
  else
    rm -f "$caddy_dir/openuem.caddy"
  fi
  if (( replacement_started )); then
    docker compose -f "$compose_file" up -d --force-recreate caddy
  fi
  preserve_backup=0
}
cleanup() {
  if (( preserve_backup )); then
    echo "Caddy recovery failed; backup retained at $backup_dir" >&2
  else
    rm -rf "$backup_dir"
  fi
}
trap rollback ERR
trap cleanup EXIT

install -m 644 "$repo_dir/ops/caddy-openuem.caddy" "$caddy_dir/openuem.caddy"

if ! grep -q '/etc/caddy/openuem:ro' "$compose_file"; then
  grep -q 'pve-root-ca.pem' "$compose_file" \
    || { echo "pve-root-ca.pem anchor not found in $compose_file" >&2; false; }
  sed -i "/pve-root-ca.pem/a\      - $repo_dir/certificates:/etc/caddy/openuem:ro" "$compose_file"
fi

if ! grep -q '^import /etc/caddy/openuem.caddy$' "$caddyfile"; then
  printf '\nimport /etc/caddy/openuem.caddy\n' >>"$caddyfile"
fi

if ! grep -q '/etc/caddy/openuem.caddy:ro' "$compose_file"; then
  grep -q 'pve-root-ca.pem' "$compose_file" \
    || { echo "pve-root-ca.pem anchor not found in $compose_file" >&2; false; }
  sed -i "/pve-root-ca.pem/a\      - $caddy_dir/openuem.caddy:/etc/caddy/openuem.caddy:ro" "$compose_file"
fi

[[ ${CADDY_SKIP_RELOAD:-0} == 1 ]] && exit 0

docker compose -f "$compose_file" config --quiet
caddy_image=$(docker inspect caddy --format '{{.Config.Image}}')
docker run --rm --entrypoint caddy --env-file "$caddy_dir/.env" \
  -v "$caddyfile:/etc/caddy/Caddyfile:ro" \
  -v "$caddy_dir/openuem.caddy:/etc/caddy/openuem.caddy:ro" \
  -v "$caddy_dir/pve-root-ca.pem:/etc/caddy/pve-root-ca.pem:ro" \
  -v "$repo_dir/certificates:/etc/caddy/openuem:ro" \
  "$caddy_image" validate --config /etc/caddy/Caddyfile
if [[ ${CADDY_VALIDATE_ONLY:-0} == 1 ]]; then
  trap - ERR
  exit 0
fi
replacement_started=1
docker compose -f "$compose_file" up -d --force-recreate caddy
docker exec caddy caddy validate --config /etc/caddy/Caddyfile
ready=0
for (( attempt = 1; attempt <= ${CADDY_READY_ATTEMPTS:-60}; attempt++ )); do
  if curl --connect-timeout 5 --max-time 10 --fail --silent --show-error --output /dev/null \
    "${CADDY_READY_URL:-https://openuem.epoh.casa}"; then
    ready=1
    break
  fi
  sleep "${CADDY_READY_INTERVAL:-2}"
done
(( ready == 1 )) || { echo "Caddy did not serve a trusted OpenUEM certificate" >&2; false; }
replacement_started=0
trap - ERR
