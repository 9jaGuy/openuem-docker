#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <tag-or-commit>" >&2
  exit 2
fi

ref=$1
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
env_file=${OPENUEM_ENV_FILE:-/etc/openuem/openuem.env}
compose=(docker compose --env-file "$env_file" -f compose.yml -f ops/compose.lan.yml)

[[ -f "$env_file" ]] || { echo "missing $env_file" >&2; exit 1; }

while IFS= read -r key; do
  [[ -z "$key" ]] && continue
  grep -qE "^${key}=.+" "$env_file" || { echo "missing required env: $key" >&2; exit 1; }
done <"$repo_dir/ops/required-env"

cd "$repo_dir"
git fetch --tags origin
git rev-parse --verify "${ref}^{commit}" >/dev/null
git checkout --detach "$ref"

"${compose[@]}" config --quiet
"${compose[@]}" pull
"${compose[@]}" up -d db openuem-certs

for _ in {1..60}; do
  if [[ -f certificates/agents/agent.cer && -f certificates/agents/agent.key ]] \
    && find certificates/users -maxdepth 1 -type f -name '*.pfx' -print -quit | grep -q . \
    && [[ -f nats/nats.cfg ]]; then
    break
  fi
  sleep 5
done

[[ -f certificates/agents/agent.cer ]] || { echo "agent certificate was not generated" >&2; exit 1; }
[[ -f certificates/agents/agent.key ]] || { echo "agent key was not generated" >&2; exit 1; }
find certificates/users -maxdepth 1 -type f -name '*.pfx' -print -quit | grep -q . \
  || { echo "user certificate was not generated" >&2; exit 1; }
[[ -f nats/nats.cfg ]] || { echo "NATS configuration was not generated" >&2; exit 1; }

"$repo_dir/ops/install-firewall.sh"
"$repo_dir/ops/install-caddy.sh"
"${compose[@]}" up -d

for _ in {1..60}; do
  ps_json=$("${compose[@]}" ps --format json)
  unhealthy=$(jq -r 'select(.Health == "unhealthy") | .Name' <<<"$ps_json")
  starting=$(jq -r 'select(.Health == "starting") | .Name' <<<"$ps_json")
  running=$(jq -r 'select(.State == "running") | .Name' <<<"$ps_json" | wc -l)
  [[ -z "$unhealthy" ]] || { echo "unhealthy containers: $unhealthy" >&2; exit 1; }
  [[ $running -ge 7 && -z "$starting" ]] && break
  sleep 5
done

[[ $running -ge 7 ]] || { echo "only $running of 7 long-running containers started" >&2; exit 1; }
[[ -z "$starting" ]] || { echo "containers still starting: $starting" >&2; exit 1; }

"${compose[@]}" ps
console_ready=0
for (( attempt = 1; attempt <= 60; attempt++ )); do
  if curl --fail --silent --show-error \
    --resolve openuem.epoh.casa:443:127.0.0.1 https://openuem.epoh.casa/ >/dev/null; then
    console_ready=1
    break
  fi
  sleep 2
done
(( console_ready == 1 )) || { echo "console did not serve a publicly trusted certificate" >&2; exit 1; }
curl --fail --silent --show-error http://192.168.1.106:8000/health >/dev/null
ss -ltn | grep -E '127\.0\.0\.1:(1323|1324)|192\.168\.1\.106:(4433|8000)'
"$repo_dir/ops/install-backup-timer.sh"
