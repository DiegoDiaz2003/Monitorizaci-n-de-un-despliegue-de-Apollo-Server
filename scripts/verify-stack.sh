#!/usr/bin/env bash
set -euo pipefail

APOLLO_URL="${APOLLO_URL:-http://localhost/}"
ELASTICSEARCH_URL="${ELASTICSEARCH_URL:-http://localhost:9200}"
KIBANA_URL="${KIBANA_URL:-http://localhost:5601}"
APM_URL="${APM_URL:-http://localhost:8200}"

echo "Elasticsearch:"
curl -fsS "$ELASTICSEARCH_URL/_cluster/health?pretty"

echo "Kibana:"
curl -fsS "$KIBANA_URL/api/status" | head -c 500
echo

echo "APM Server:"
curl -fsS "$APM_URL/" | head -c 500
echo

echo "Apollo:"
curl -fsS -X POST "$APOLLO_URL" \
  -H "content-type: application/json" \
  --data '{"operationName":"GetBooks","query":"query GetBooks { books { title author } }"}'
echo

echo "Apollo health:"
curl -fsS -X POST "$APOLLO_URL" \
  -H "content-type: application/json" \
  --data '{"operationName":"Health","query":"query Health { health }"}'
echo
