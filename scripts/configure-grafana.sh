#!/bin/sh
set -eu
set -a
. ./.env
set +a
: "$GRAFANA_ADMIN_PASSWORD"
BASE_URL="http://grafana:3000"
AUTH="$GRAFANA_ADMIN_USER:$GRAFANA_ADMIN_PASSWORD"
attempt=0
until curl -fsS -u "$AUTH" "$BASE_URL/api/health" >/dev/null; do
 attempt=$((attempt+1))
 [ "$attempt" -lt 40 ] || { echo "Grafana API did not become ready" >&2; exit 1; }
 sleep 3
done
curl -fsS -u "$AUTH" -X PUT "$BASE_URL/api/datasources/uid/prometheus" -H 'Content-Type: application/json' --data-binary '{"name":"Prometheus","uid":"prometheus","type":"prometheus","access":"proxy","url":"http://prometheus:9090","isDefault":true,"editable":true}' >/dev/null
python3 - <<'PY' | curl -fsS -u "$AUTH" -X POST "$BASE_URL/api/dashboards/db" -H 'Content-Type: application/json' --data-binary @- >/dev/null
import json
with open("grafana/dashboards/kuma-health.json",encoding="utf-8") as f: dashboard=json.load(f)
print(json.dumps({"dashboard":dashboard,"folderId":0,"overwrite":True,"message":"Provisioned by Dagger"}))
PY
echo "Grafana API configuration applied."
