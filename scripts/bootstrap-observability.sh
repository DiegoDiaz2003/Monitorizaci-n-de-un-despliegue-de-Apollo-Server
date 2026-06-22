#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  exec sudo -E bash "$0" "$@"
fi

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

sysctl -w vm.max_map_count=262144
grep -q "vm.max_map_count=262144" /etc/sysctl.conf || echo "vm.max_map_count=262144" >> /etc/sysctl.conf

cd "$(dirname "$0")/.."
mkdir -p runtime

docker compose -f docker-compose.elastic.yml pull
docker compose -f docker-compose.elastic.yml up -d

echo "Waiting for Elasticsearch..."
until curl -fsS http://localhost:9200 >/dev/null; do sleep 5; done

echo "Waiting for Kibana..."
until curl -fsS http://localhost:5601/api/status >/dev/null; do sleep 5; done

echo "Waiting for Logstash API..."
until curl -fsS http://localhost:9600 >/dev/null; do sleep 5; done

echo "Waiting for APM Server..."
until curl -fsS http://localhost:8200/ >/dev/null; do sleep 5; done

echo "Elastic cluster health:"
curl -fsS http://localhost:9200/_cluster/health?pretty

docker compose -f docker-compose.elastic.yml ps
