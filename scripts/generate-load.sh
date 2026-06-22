#!/usr/bin/env bash
set -euo pipefail

APOLLO_URL="${1:-http://localhost/}"
REQUESTS="${REQUESTS:-60}"

for i in $(seq 1 "$REQUESTS"); do
  if [ $((i % 5)) -eq 0 ]; then
    QUERY='query SlowBooks($delayMs: Int!) { slowBooks(delayMs: $delayMs) { title author } }'
    BODY=$(printf '{"operationName":"SlowBooks","query":"%s","variables":{"delayMs":%s}}' "$QUERY" "$((150 + (i % 10) * 100))")
  else
    BODY='{"operationName":"GetBooks","query":"query GetBooks { books { title author } }"}'
  fi

  curl -sS -X POST "$APOLLO_URL" \
    -H "content-type: application/json" \
    --data "$BODY" >/dev/null

  printf "request %s/%s sent\n" "$i" "$REQUESTS"
  sleep 1
done

