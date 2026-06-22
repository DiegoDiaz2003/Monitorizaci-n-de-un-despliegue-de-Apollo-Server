#!/usr/bin/env bash
set -euo pipefail

KIBANA_URL="${KIBANA_URL:-http://localhost:5601}"

create_index_pattern() {
  local id="$1"
  local title="$2"
  local time_field="${3:-@timestamp}"

  curl -fsS -X POST "${KIBANA_URL}/api/saved_objects/index-pattern/${id}?overwrite=true" \
    -H "kbn-xsrf: true" \
    -H "content-type: application/json" \
    --data "{\"attributes\":{\"title\":\"${title}\",\"timeFieldName\":\"${time_field}\"}}" >/dev/null

  echo "Index pattern ready: ${title}"
}

create_index_pattern "metricbeat-star" "metricbeat-*"
create_index_pattern "apm-star" "apm-*"
create_index_pattern "nginx-access-star" "nginx.access-*"
create_index_pattern "nginx-error-star" "nginx.error-*"
create_index_pattern "apollo-application-star" "apollo.application-*"

echo "Kibana index patterns created at ${KIBANA_URL}"

