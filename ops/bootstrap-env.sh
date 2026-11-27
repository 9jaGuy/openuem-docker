#!/usr/bin/env bash
set -euo pipefail

env_file=${OPENUEM_ENV_FILE:-/etc/openuem/openuem.env}

if [[ -e "$env_file" ]]; then
  echo "$env_file already exists" >&2
  exit 1
fi

install -d -m 700 "$(dirname "$env_file")"
db_password=$(openssl rand -hex 32)
jwt_key=$(openssl rand -hex 32)

umask 077
cat >"$env_file" <<EOF
DATABASE_PORT=5434
DATABASE_USER=openuem
DATABASE_PASSWORD=$db_password
DATABASE_DB_NAME=openuem
OPENUEM_DATABASE_URL=postgres://openuem:$db_password@db:5434/openuem

OPENUEM_ORGNAME=Acachi LLC
OPENUEM_ORGPROVINCE=Texas
OPENUEM_ORGLOCALITY=Austin
OPENUEM_ORGADDRESS=
OPENUEM_ORGCOUNTRY=US
TZ=America/Chicago
OPENUEM_DOMAIN=epoh.casa
LAN_ADDRESS=192.168.1.106

REVERSE_PROXY_HOST=openuem.epoh.casa
REVERSE_PROXY_CONSOLE_PORT=443
REVERSE_PROXY_AUTH_PORT=4443

NATS_PORT=4433
NATS_HOST=openuem-nats.epoh.casa

OCSP_HOST=openuem-ocsp.epoh.casa
OCSP_PORT=8000
OCSP_URL=http://openuem-ocsp.epoh.casa:8000

CONSOLE_HOST=openuem.epoh.casa
CONSOLE_PORT=1323
CONSOLE_AUTH_PORT=1324
CONSOLE_JWT_KEY=$jwt_key
CONSOLE_RE_ENABLE_CERTIFICATES_AUTH=
CONSOLE_RE_ENABLE_PASSWD_AUTH=
CONSOLE_RESET_OPENUEM_USER=

OPENUEM_NATS_SERVERS=openuem-nats.epoh.casa:4433
EOF

chmod 600 "$env_file"
echo "Created $env_file"
