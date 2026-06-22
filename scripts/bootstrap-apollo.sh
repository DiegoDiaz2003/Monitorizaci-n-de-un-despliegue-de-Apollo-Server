#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  exec sudo -E bash "$0" "$@"
fi

: "${APM_SERVER_URL:?Set APM_SERVER_URL, for example http://10.0.1.20:8200}"
: "${LOGSTASH_HOST:?Set LOGSTASH_HOST, for example 10.0.1.20:5044}"
: "${ELASTICSEARCH_HOST:?Set ELASTICSEARCH_HOST, for example http://10.0.1.20:9200}"
: "${KIBANA_HOST:?Set KIBANA_HOST, for example http://10.0.1.20:5601}"

export DEBIAN_FRONTEND=noninteractive

install_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    return
  fi

  apt-get update
  apt-get install -y ca-certificates curl gnupg lsb-release unzip
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker

cd "$(dirname "$0")/.."
mkdir -p runtime/apollo-logs runtime/nginx-logs

cat > .env <<EOF
ELASTIC_VERSION=${ELASTIC_VERSION:-7.9.3}
APM_SERVER_URL=${APM_SERVER_URL}
LOGSTASH_HOST=${LOGSTASH_HOST}
ELASTICSEARCH_HOST=${ELASTICSEARCH_HOST}
KIBANA_HOST=${KIBANA_HOST}
EOF

docker compose -f docker-compose.apollo.yml build --pull
docker compose -f docker-compose.apollo.yml up -d

echo "Waiting for Apollo through Nginx..."
until curl -fsS -X POST http://localhost/ \
  -H "content-type: application/json" \
  --data '{"operationName":"Health","query":"query Health { health }"}' | grep -q '"health":"ok"'; do
  sleep 5
done

echo "Validating GraphQL health query..."
curl -fsS -X POST http://localhost/ \
  -H "content-type: application/json" \
  --data '{"operationName":"Health","query":"query Health { health }"}' | grep -q '"health":"ok"'

echo "Validating connectivity to observability endpoints..."
curl -fsS "${APM_SERVER_URL}/" >/dev/null
curl -fsS "${ELASTICSEARCH_HOST}/" >/dev/null
curl -fsS "${KIBANA_HOST}/api/status" >/dev/null

docker compose -f docker-compose.apollo.yml ps
