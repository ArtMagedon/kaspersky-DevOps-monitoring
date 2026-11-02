#!/bin/sh
set -eu

set -a
. ./.env
set +a

: "${GRAFANA_ADMIN_USER:?GRAFANA_ADMIN_USER is required}"
: "${GRAFANA_ADMIN_PASSWORD:?GRAFANA_ADMIN_PASSWORD is required}"

BASE_URL="http://grafana:3000"
AUTH="$GRAFANA_ADMIN_USER:$GRAFANA_ADMIN_PASSWORD"

attempt=0
until curl --silent --show-error --fail --user "$AUTH" "$BASE_URL/api/health" >/dev/null; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 40 ]; then
    echo "Grafana API did not become ready" >&2
    exit 1
  fi
  sleep 3
done

# Datasource and dashboard are provisioned from files mounted into Grafana.
# Provisioned resources are intentionally read-only through the Grafana API.
datasource_response="$(curl --silent --show-error --fail --user "$AUTH" "$BASE_URL/api/datasources/uid/prometheus")" || {
  echo "Grafana Prometheus datasource is unavailable through the API" >&2
  exit 1
}
printf '%s' "$datasource_response" | python3 -c '
import json, sys
data = json.load(sys.stdin)
assert data.get("uid") == "prometheus", "Unexpected datasource UID"
assert data.get("type") == "prometheus", "Unexpected datasource type"
assert data.get("url") == "http://prometheus:9090", "Unexpected Prometheus URL"
'

dashboard_response="$(curl --silent --show-error --fail --user "$AUTH" "$BASE_URL/api/dashboards/uid/kuma-health")" || {
  echo "Grafana kuma-health dashboard is unavailable through the API" >&2
  exit 1
}
printf '%s' "$dashboard_response" | python3 -c '
import json, sys
data = json.load(sys.stdin)
dashboard = data.get("dashboard", {})
assert dashboard.get("uid") == "kuma-health", "Unexpected dashboard UID"
'

echo "Grafana provisioning verified through the API."
