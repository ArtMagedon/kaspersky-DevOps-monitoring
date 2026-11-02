#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }
require_command() { command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"; }

require_command docker
require_command curl
require_command python3
[ -f .env ] || fail ".env is missing; copy .env.example and set test credentials"

set -a
. ./.env
set +a

check_http() {
  name="$1"
  url="$2"
  curl --silent --show-error --fail --max-time 10 "$url" >/dev/null || fail "$name endpoint is unavailable: $url"
  pass "$name HTTP endpoint"
}

query_prometheus() {
  query="$1"
  encoded="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$query")"
  curl --silent --show-error --fail --max-time 10 "http://127.0.0.1:9090/api/v1/query?query=$encoded"
}

wait_for_targets() {
  attempt=0
  while [ "$attempt" -lt 40 ]; do
    if python3 - <<'PY'
import json, urllib.request
expected = {
    "prometheus", "cadvisor", "node-exporter", "mysqld-exporter",
    "blackbox-uptime-kuma", "blackbox-mariadb",
}
try:
    with urllib.request.urlopen("http://127.0.0.1:9090/api/v1/targets", timeout=5) as response:
        payload = json.load(response)
    targets = payload["data"]["activeTargets"]
    by_job = {}
    for target in targets:
        job = target.get("labels", {}).get("job")
        if job:
            by_job.setdefault(job, []).append(target.get("health"))
    missing = sorted(expected - by_job.keys())
    down = sorted(job for job in expected & by_job.keys() if any(h != "up" for h in by_job[job]))
    if not missing and not down:
        print("All expected Prometheus scrape targets are UP.")
        raise SystemExit(0)
except Exception:
    pass
raise SystemExit(1)
PY
    then
      pass "Prometheus scrape targets"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 3
  done
  docker compose -f compose/app.yml -f compose/monitoring.yml ps >&2 || true
  fail "Prometheus targets did not all become UP"
}

assert_metric_one() {
  label="$1"
  query="$2"
  response="$(query_prometheus "$query")" || fail "$label: Prometheus query failed"
  printf '%s' "$response" | python3 -c '
import json,sys
data=json.load(sys.stdin)
rows=data.get("data",{}).get("result",[])
if not rows or float(rows[0]["value"][1]) != 1:
    raise SystemExit(1)
' || fail "$label: expected metric value 1; response: $response"
  pass "$label"
}

echo "Running Uptime Kuma monitoring integration tests..."

docker compose --env-file .env -f compose/app.yml config -q || fail "Application Compose configuration is invalid"
docker compose --env-file .env -f compose/monitoring.yml config -q || fail "Monitoring Compose configuration is invalid"
pass "Docker Compose configuration"

check_http "Uptime Kuma" "http://127.0.0.1:3001/"
check_http "Prometheus" "http://127.0.0.1:9090/-/healthy"
check_http "Grafana" "http://127.0.0.1:3000/api/health"

docker exec mariadb healthcheck.sh --connect --innodb_initialized >/dev/null 2>&1 || fail "MariaDB healthcheck failed"
docker exec mariadb mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" -Nse 'SELECT 1' 2>/dev/null | grep -qx '1' || fail "MariaDB application credentials/query failed"
pass "MariaDB readiness and SQL query"

wait_for_targets
assert_metric_one "Uptime Kuma HTTP blackbox probe" 'probe_success{job="blackbox-uptime-kuma"}'
assert_metric_one "MariaDB TCP blackbox probe" 'probe_success{job="blackbox-mariadb"}'
assert_metric_one "MariaDB exporter connection" 'mysql_up'

auth="$GRAFANA_ADMIN_USER:$GRAFANA_ADMIN_PASSWORD"
curl --silent --show-error --fail --user "$auth" http://127.0.0.1:3000/api/datasources/uid/prometheus >/dev/null || fail "Grafana Prometheus datasource is missing"
pass "Grafana Prometheus datasource"
curl --silent --show-error --fail --user "$auth" http://127.0.0.1:3000/api/dashboards/uid/kuma-health >/dev/null || fail "Grafana dashboard kuma-health is missing"
pass "Grafana dashboard API"

echo "All integration tests passed."
